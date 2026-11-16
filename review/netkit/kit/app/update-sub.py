#!/usr/bin/env python3
# update-sub.py — УСТАРЕВШИЙ вариант обновления подписки. Основной путь — update-sub.ps1
# (меню, пункт 3): он умеет пароль на ключи (secret.dat, *.enc) и шифрует результат.
#
# Этот скрипт оставлен только для случая «Python есть, PowerShell нет» и работает
# ТОЛЬКО с открытыми vpn\sub.txt / vpn\config.json. Если включён пароль
# (есть vpn\secret.dat) — отказывается что-либо менять, чтобы не оставить открытую
# копию ключей рядом с шифрованной.
#
# Полный паритет с update-sub.ps1: tcp (+ http header), ws, grpc, httpupgrade,
# tls и reality (включая spiderX), flow, sni/host/path/alpn.
# Конфиг собирается словарями и json.dumps — без ручной склейки строк (аудит F-08).
#
# Запускать ТОЛЬКО ДОМА:   python app\update-sub.py
# Данные подписки читаются/сохраняются в vpn\sub.txt (url=..., hwid=..., ua=...).

import base64
import json
import os
import re
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
VPN = os.path.normpath(os.path.join(HERE, "..", "vpn"))
CFG = os.path.join(VPN, "config.json")
SUB = os.path.join(VPN, "sub.txt")


def load_sub_params():
    """Читает url/hwid/ua из sub.txt; спрашивает недостающее; сохраняет обратно."""
    params = {"url": "", "hwid": "", "ua": "INCY/3.0.28"}
    if os.path.exists(SUB):
        with open(SUB, encoding="utf-8") as f:
            for line in f:
                if "=" in line:
                    k, v = line.strip().split("=", 1)
                    if k.lower() in params and v:
                        params[k.lower()] = v
    if not params["url"]:
        params["url"] = input("URL подписки (https://api.../sub/...): ").strip()
    if not params["hwid"]:
        params["hwid"] = input("x-hwid (GUID клиента; Enter — не отправлять): ").strip()
    if not params["url"].startswith("https://"):
        sys.exit("[X] URL подписки должен начинаться с https://")
    os.makedirs(VPN, exist_ok=True)
    with open(SUB, "w", encoding="utf-8", newline="\r\n") as f:
        f.write("url=%s\r\nhwid=%s\r\nua=%s\r\n" % (params["url"], params["hwid"], params["ua"]))
    return params


def fetch(url, hwid, ua, timeout=25):
    headers = {"User-Agent": ua}
    if hwid:
        headers["x-hwid"] = hwid
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def decode_lines(raw):
    """Тело подписки: либо сразу список vless://, либо base64 (в т.ч. без '=' и url-safe)."""
    raw = raw.strip()
    if "vless://" in raw:
        return raw.splitlines()
    b = "".join(raw.split()).replace("-", "+").replace("_", "/")
    b += "=" * (-len(b) % 4)  # восстановить паддинг
    try:
        text = base64.b64decode(b.encode("ascii"), validate=True).decode("utf-8", "replace")
    except ValueError:  # binascii.Error и UnicodeEncodeError — оба ValueError
        sys.exit("[X] Тело подписки не распознано (не список vless:// и не base64). config.json НЕ тронут.")
    return text.splitlines()


def parse_link(line):
    """vless://... -> dict узла или None (если нерабочий/чужой)."""
    line = line.strip()
    if not line.startswith("vless://"):
        return None
    p = urllib.parse.urlsplit(line)
    try:
        port = p.port
    except ValueError:
        print("[!] битый порт в ссылке, пропускаю:", line[:40] + "...")
        return None
    if p.scheme != "vless" or not p.hostname or not port or not p.username:
        print("[!] не разобрать ссылку, пропускаю:", line[:40] + "...")
        return None
    if not 1 <= port <= 65535:
        print("[!] порт вне диапазона, пропускаю:", line[:40] + "...")
        return None
    qs = {k.lower(): v for k, v in urllib.parse.parse_qsl(p.query)}

    # регистр в ссылке бывает любой: TLS, Reality, WS — приводим к нижнему
    node = {
        "uuid": p.username,
        "address": p.hostname,
        "port": port,
        "net": (qs.get("type", "tcp") or "tcp").strip().lower(),
        "sec": (qs.get("security", "none") or "none").strip().lower(),
        "flow": qs.get("flow", ""),
        "sni": qs.get("sni", ""),
        "fp": qs.get("fp", ""),
        "host": qs.get("host", ""),
        "path": qs.get("path", ""),
        "service_name": qs.get("servicename", ""),
        "alpn": qs.get("alpn", ""),
        "pbk": qs.get("pbk", ""),
        "sid": qs.get("sid", ""),
        "spx": qs.get("spx", ""),
        "header_type": qs.get("headertype", ""),
    }
    # заглушка от панели и служебные адреса: такой «сервер» никуда не ведёт
    if node["address"] in ("0.0.0.0", "::", "127.0.0.1", "localhost") \
            or node["address"].startswith(("10.", "192.168.", "169.254.")) \
            or re.match(r"^172\.(1[6-9]|2\d|3[01])\.", node["address"]):
        print("[!] заглушка или локальный адрес (%s) — пропускаю" % node["address"])
        return None
    # UUID должен быть настоящим: с мусором xray не поднимется уже на чужом ПК
    if not re.match(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", node["uuid"]):
        print("[!] некорректный UUID — пропускаю узел %s:%s" % (node["address"], port))
        return None
    # транспорт, которого нет в xray, — узел бесполезен
    if node["net"] not in ("tcp", "ws", "grpc", "httpupgrade"):
        print("[!] неподдерживаемый транспорт (%s) — пропускаю: %s" % (node["net"], node["address"]))
        return None
    # только шифрованный транспорт: security=none — содержимое видно провайдеру
    if node["sec"] not in ("tls", "reality"):
        print("[!] незашифрованный узел (security=%s) — пропускаю: %s" % (node["sec"], node["address"]))
        return None
    if node["sec"] == "reality" and (not node["pbk"] or not node["sni"]):
        print("[!] REALITY без pbk/sni — пропускаю:", node["address"])
        return None
    # flow имеет смысл только с TLS/REALITY
    if node["flow"] and node["sec"] not in ("tls", "reality"):
        node["flow"] = ""
    return node


def build_stream(node):
    """streamSettings как словарь — экранированием занимается json.dumps."""
    ss = {"network": node["net"], "security": node["sec"]}

    if node["net"] == "ws":
        ws = {"path": node["path"] or "/"}
        if node["host"]:
            ws["headers"] = {"Host": node["host"]}
        ss["wsSettings"] = ws
    elif node["net"] == "grpc":
        ss["grpcSettings"] = {"serviceName": node["service_name"]}
    elif node["net"] == "httpupgrade":
        hu = {"path": node["path"] or "/"}
        if node["host"]:
            hu["host"] = node["host"]
        ss["httpupgradeSettings"] = hu
    elif node["net"] == "tcp" and node["header_type"] == "http":
        ss["tcpSettings"] = {
            "header": {
                "type": "http",
                "request": {
                    "path": [node["path"] or "/"],
                    "headers": {"Host": [node["host"]]},
                },
            }
        }

    if node["sec"] == "tls":
        sn = node["sni"] or node["host"] or node["address"]
        tls = {"serverName": sn, "fingerprint": node["fp"] or "chrome"}
        alpn = [a.strip() for a in node["alpn"].split(",") if a.strip()]
        if alpn:
            tls["alpn"] = alpn
        ss["tlsSettings"] = tls
    elif node["sec"] == "reality":
        rl = {
            "show": False,
            "fingerprint": node["fp"] or "firefox",
            "serverName": node["sni"],
            "publicKey": node["pbk"],
        }
        if node["sid"]:
            rl["shortId"] = node["sid"]
        if node["spx"]:
            rl["spiderX"] = node["spx"]
        ss["realitySettings"] = rl
    return ss


def build_outbound(node, idx):
    user = {"id": node["uuid"], "encryption": "none"}
    if node["flow"] and node["sec"] in ("reality", "tls"):
        user["flow"] = node["flow"]
    return {
        "tag": "proxy-%d" % idx,
        "protocol": "vless",
        "settings": {
            "vnext": [
                {
                    "address": node["address"],
                    "port": node["port"],
                    "users": [user],
                }
            ]
        },
        "streamSettings": build_stream(node),
    }


def build_config(nodes):
    outbounds = [build_outbound(n, i + 1) for i, n in enumerate(nodes)]
    # никаких freedom/blackhole: прямого выхода наружу в конфиге быть не должно
    return {
        "log": {"loglevel": "none"},
        "inbounds": [
            {
                "tag": "socks-in",
                "listen": "127.0.0.1",
                "port": 10808,
                "protocol": "socks",
                "settings": {"auth": "noauth", "udp": False},
                "sniffing": {"enabled": True, "destOverride": ["http", "tls"]},
            },
        ],
        "outbounds": outbounds,
        "observatory": {
            "subjectSelector": ["proxy-"],
            "probeURL": "https://www.gstatic.com/generate_204",
            "probeInterval": "3m",
            "enableConcurrency": True,
        },
        "routing": {
            "domainStrategy": "AsIs",
            "balancers": [
                {
                    "tag": "all-proxies",
                    "selector": ["proxy-"],
                    "strategy": {"type": "leastPing"},
                }
            ],
            "rules": [{"type": "field", "network": "tcp,udp", "balancerTag": "all-proxies"}],
        },
    }


def refuse_if_password_protected():
    """Пароль на ключи (secret.dat) — этот скрипт с ним не работает.
    Иначе он оставил бы открытые sub.txt/config.json рядом с зашифрованными."""
    if os.path.exists(os.path.join(VPN, "secret.dat")):
        sys.exit("[X] На флешке включён пароль на ключи (vpn\\secret.dat).\n"
                 "    Этот скрипт не умеет шифровать и оставил бы ключи открытыми.\n"
                 "    Обновляй подписку через меню, пункт 3 (app\\update-sub.ps1).")


def main():
    refuse_if_password_protected()
    params = load_sub_params()
    print("[..] Запрашиваю подписку...")
    try:
        raw = fetch(params["url"], params["hwid"], params["ua"])
    except Exception as e:
        sys.exit("[X] Не удалось получить подписку: %s" % e)

    nodes, seen, skipped = [], set(), 0
    for line in decode_lines(raw):
        if line.strip() and not line.strip().startswith("vless://"):
            if "://" in line:
                skipped += 1
            continue
        n = parse_link(line)
        if not n:
            continue
        key = (n["uuid"], n["address"], n["port"])
        if key in seen:
            continue
        seen.add(key)
        nodes.append(n)

    if not nodes:
        sys.exit("[X] Валидных vless:// узлов нет (пропущено чужих: %d). config.json НЕ тронут." % skipped)

    text = json.dumps(build_config(nodes), ensure_ascii=False, indent=2)
    json.loads(text)  # самопроверка: невалидный конфиг падает здесь, а не в xray.exe

    if os.path.exists(CFG):
        with open(CFG, encoding="utf-8") as f:
            old = f.read()
        with open(CFG + ".bak.json", "w", encoding="utf-8", newline="\n") as f:
            f.write(old)
        print("[i] Старый конфиг — в config.bak.json")

    with open(CFG, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)

    print("[+] Готово: %d сервер(ов) записано в config.json" % len(nodes))
    for i, n in enumerate(nodes, 1):
        print("    proxy-%d: %s:%s  sni=%s  [%s/%s]" % (i, n["address"], n["port"], n["sni"], n["net"], n["sec"]))
    if skipped:
        print("[i] Пропущено чужих (не vless) строк: %d" % skipped)


if __name__ == "__main__":
    main()
