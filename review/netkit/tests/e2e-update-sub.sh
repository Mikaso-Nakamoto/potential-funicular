#!/usr/bin/env bash
# e2e-update-sub.sh — сквозная проверка update-sub.ps1 и vless-to-config.ps1 под настоящим pwsh.
#
# Зачем: на Windows эти скрипты зовут `curl.exe` и пишут на флешку. Под Linux их можно
# прогнать целиком, если дать им (1) `curl.exe` в PATH и (2) локальный HTTPS-сервер
# с телом подписки. Скрипт комплекта при этом не меняется ни на строку: подмена живёт
# только в тестовом окружении.
#
# Требуется: pwsh 7 (Linux), python3, openssl, curl.
#   wget/браузер: powershell-<ver>-linux-x64.tar.gz  →  tar xzf → ./pwsh
#
# Запуск (из любого места, путь к pwsh задаётся переменной):
#   PWSH=/tmp/pwsh/pwsh review/netkit/tests/e2e-update-sub.sh
#
# Выход: 0 — все сценарии дали ожидаемый результат, 1 — что-то не так.

set -u
PWSH="${PWSH:-pwsh}"
HERE="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$HERE/../kit" && pwd)"
WORK="$(mktemp -d)"
PORT=8443
FAILED=0

say()  { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  [OK]   %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; FAILED=$((FAILED+1)); }

cleanup() {
  [ -n "${SRV_PID:-}" ] && kill "$SRV_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

[ -d "$KIT/app" ] || { echo "не найден комплект: $KIT"; exit 1; }
command -v "$PWSH" >/dev/null 2>&1 || { echo "не найден pwsh ($PWSH)"; exit 1; }

# ---------------------------------------------------------------- окружение
mkdir -p "$WORK/bin" "$WORK/kit/app" "$WORK/kit/vpn" "$WORK/srv"
cp "$KIT"/app/*.ps1 "$WORK/kit/app/"
cp "$KIT"/app/user.js "$WORK/kit/app/" 2>/dev/null

# curl.exe: под Windows это бинарник, здесь — обёртка. -k нужен только из-за
# самоподписанного сертификата локального сервера.
printf '#!/bin/sh\nexec curl -k "$@"\n' > "$WORK/bin/curl.exe"
chmod +x "$WORK/bin/curl.exe"
export PATH="$WORK/bin:$PATH"

openssl req -x509 -newkey rsa:2048 -keyout "$WORK/srv/k.pem" -out "$WORK/srv/c.pem" \
        -days 1 -nodes -subj "/CN=127.0.0.1" >/dev/null 2>&1
cp "$HERE/fixtures/sub-body.txt" "$WORK/srv/sub.txt"
python3 - "$WORK/srv" <<'PY'
import base64, sys
d = sys.argv[1]
open(d + '/sub64.txt', 'wb').write(base64.b64encode(open(d + '/sub.txt', 'rb').read()))
PY
cat > "$WORK/srv/serve.py" <<'PY'
import http.server, ssl, sys, os
os.chdir(sys.argv[1])
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain('c.pem', 'k.pem')
srv = http.server.HTTPServer(('127.0.0.1', int(sys.argv[2])), http.server.SimpleHTTPRequestHandler)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
PY
python3 "$WORK/srv/serve.py" "$WORK/srv" "$PORT" >/dev/null 2>&1 &
SRV_PID=$!
sleep 1

sub() {  # sub <url>
  printf 'url=%s\r\nhwid=11111111-2222-3333-4444-555555555555\r\nua=INCY/3.0.28\r\n' "$1" > "$WORK/kit/vpn/sub.txt"
}
run_update() { "$PWSH" -NoProfile -ExecutionPolicy Bypass -File "$WORK/kit/app/update-sub.ps1" 2>&1; }

# ------------------------------------------------------------------- сценарии
say '1. текстовая подписка https'
sub "https://127.0.0.1:$PORT/sub.txt"
OUT="$(run_update)"; echo "$OUT" | tail -3
if grep -q 'Готово: 7 сервер' <<<"$OUT" && [ -f "$WORK/kit/vpn/config.json" ]; then
  ok 'конфиг записан, 7 серверов'
else bad 'текстовая подписка не разобрана'; fi
if python3 -c "import json,sys;d=json.load(open('$WORK/kit/vpn/config.json'));sys.exit(0 if len(d['outbounds'])==7 and all(o['protocol']=='vless' for o in d['outbounds']) else 1)"; then
  ok 'JSON валиден, 7 proxy, без direct/block'
else bad 'структура конфига не та'; fi
if python3 -c "import json,sys;d=json.load(open('$WORK/kit/vpn/config.json'));inb=d['inbounds'];sys.exit(0 if len(inb)==1 and inb[0]['protocol']=='socks' and inb[0]['port']==10808 and inb[0]['settings']['udp'] is False and d['log']['loglevel']=='none' else 1)"; then
  ok 'один socks-inbound, udp выключен, loglevel none'
else bad 'inbound/логи не те'; fi

say '2. base64-подписка + бэкап прошлого конфига'
sub "https://127.0.0.1:$PORT/sub64.txt"
OUT="$(run_update)"; echo "$OUT" | tail -2
if grep -q 'Готово: 7 сервер' <<<"$OUT"; then ok 'base64 разобран'; else bad 'base64 не разобран'; fi
if [ -f "$WORK/kit/vpn/config.json.bak.json" ]; then ok 'config.json.bak.json создан (а не .json)'; else bad 'бэкап не там'; fi

say '3. 404 — конфиг не должен испортиться'
BEFORE="$(md5sum "$WORK/kit/vpn/config.json" | cut -d' ' -f1)"
sub "https://127.0.0.1:$PORT/nope.txt"
OUT="$(run_update)"; echo "$OUT" | tail -1
AFTER="$(md5sum "$WORK/kit/vpn/config.json" | cut -d' ' -f1)"
[ "$BEFORE" = "$AFTER" ] && ok 'config.json не изменился' || bad 'config.json перезаписан при ошибке'

say '4. http:// — должен отказаться'
sub "http://127.0.0.1:$PORT/sub.txt"
OUT="$(run_update)"; echo "$OUT" | tail -1
AFTER="$(md5sum "$WORK/kit/vpn/config.json" | cut -d' ' -f1)"
[ "$BEFORE" = "$AFTER" ] && ok 'https-only работает' || bad 'http:// принят'

say '5. мусор вместо подписки'
sub "https://127.0.0.1:$PORT/c.pem"
OUT="$(run_update)"; echo "$OUT" | tail -1
AFTER="$(md5sum "$WORK/kit/vpn/config.json" | cut -d' ' -f1)"
[ "$BEFORE" = "$AFTER" ] && ok 'конфиг не тронут' || bad 'конфиг перезаписан мусором'

say '6. vless-to-config.ps1: дубликат и битая ссылка'
rm -f "$WORK/kit/vpn/config.json"*
U=11111111-1111-1111-1111-111111111111
printf 'vless://%s@one.example.com:443?type=ws&security=tls&path=%%2Fp&sni=one.example.com#one\n' "$U" > "$WORK/in.txt"
printf 'vless://%s@two.example.com:443?type=tcp&security=reality&pbk=K&sni=two.example.com#two\n' "$U" >> "$WORK/in.txt"
printf 'vless://%s@one.example.com:443?type=ws&security=tls&path=%%2Fp&sni=one.example.com#dup\n' "$U" >> "$WORK/in.txt"
printf 'vless://broken\n\n' >> "$WORK/in.txt"
OUT="$("$PWSH" -NoProfile -ExecutionPolicy Bypass -File "$WORK/kit/app/vless-to-config.ps1" < "$WORK/in.txt" 2>&1)"; echo "$OUT" | tail -3
if grep -q 'дубликат, пропущен' <<<"$OUT" && grep -q 'Серверов: 2' <<<"$OUT"; then
  ok 'дубликат отброшен, битая ссылка пропущена, 2 сервера'
else bad 'поведение на дубликате/битой ссылке не то'; fi

say '7. незашифрованный узел в подписке не попадает в конфиг'
cp "$HERE/fixtures/sub-body-none.txt" "$WORK/srv/subnone.txt"
sub "https://127.0.0.1:$PORT/subnone.txt"
OUT="$(run_update)"; echo "$OUT" | tail -2
if grep -q 'Готово: 7 сервер' <<<"$OUT" && ! grep -q 'plain.example.com' "$WORK/kit/vpn/config.json" && ! grep -q '"0.0.0.0"' "$WORK/kit/vpn/config.json"; then
  ok 'security=none и заглушка 0.0.0.0 отброшены, остальные 7 серверов на месте'
else bad 'плохой узел попал в конфиг'; fi

say '8. сверка с Python-версией на одних данных'
"$PWSH" -NoProfile -File "$HERE/Dump-Config.ps1" -Body "$HERE/fixtures/sub-body.txt" -Out "$WORK/ps.json" >/dev/null 2>&1
python3 - "$KIT/app/update-sub.py" "$WORK/ps.json" "$HERE/fixtures/sub-body.txt" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location('us', sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
body = open(sys.argv[3], encoding='utf-8').read()
nodes = [n for n in (m.parse_link(l) for l in m.decode_lines(body)) if n]
py = json.loads(json.dumps(m.build_config(nodes)))
ps = json.load(open(sys.argv[2]))

def diff(a, b, p=''):
    out = []
    if isinstance(a, dict) and isinstance(b, dict):
        for k in set(a) | set(b):
            if k not in a: out.append((p + '/' + k, 'нет в PS', b[k]))
            elif k not in b: out.append((p + '/' + k, a[k], 'нет в PY'))
            else: out += diff(a[k], b[k], p + '/' + k)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b): out.append((p + ' [длина]', len(a), len(b)))
        for i, (x, y) in enumerate(zip(a, b)): out += diff(x, y, f'{p}[{i}]')
    elif a != b: out.append((p, a, b))
    return out

d = diff(ps, py)
if d:
    for p, a, b in d[:10]: print(f'  [FAIL] {p}: PS={a!r} PY={b!r}')
    print(f'  расхождений: {len(d)}')
    sys.exit(1)
print('  [OK]   PowerShell и Python собрали идентичный конфиг')
PY
[ $? -eq 0 ] || FAILED=$((FAILED+1))

say 'итог'
if [ "$FAILED" -eq 0 ]; then echo 'ВСЁ ХОРОШО: все сценарии прошли'; exit 0; fi
echo "ПРОВАЛОВ: $FAILED"; exit 1
