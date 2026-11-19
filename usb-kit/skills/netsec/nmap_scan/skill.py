# SPDX-License-Identifier: Apache-2.0
"""Effect for netsec/nmap_scan: run one safe-profile nmap scan, return structured data."""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, Dict

try:
    import yaml
except Exception:  # pragma: no cover
    yaml = None

try:  # skillware даёт валидацию параметров и работу с секретами, но не обязателен
    from skillware.core.base_skill import BaseSkill
except Exception:  # pragma: no cover
    class BaseSkill:  # минимальная локальная замена
        def __init__(self, *args: Any, **kwargs: Any) -> None:
            pass


_TARGET_RE = re.compile(r"^[A-Za-z0-9:/._-]+$")
_PORTS_RE = re.compile(r"^[0-9,-]+$")
_SCRIPTS_RE = re.compile(r"^[A-Za-z0-9,_.*+-]+$")


def _load_manifest() -> Dict[str, Any]:
    mf = Path(__file__).with_name("manifest.yaml")
    if yaml is not None and mf.is_file():
        return yaml.safe_load(mf.read_text(encoding="utf-8")) or {}
    return {}


class NmapScanSkill(BaseSkill):
    NAME = "netsec/nmap_scan"
    MANIFEST = _load_manifest()

    def validate_params(self, params: Dict[str, Any]) -> None:
        target = str(params.get("target") or "").strip()
        if not target:
            raise ValueError("параметр target обязателен")
        if not _TARGET_RE.match(target) or len(target) > 253:
            raise ValueError("target содержит недопустимые символы")
        ports = params.get("ports")
        if ports is not None and not _PORTS_RE.match(str(ports)):
            raise ValueError("ports: допускаются только цифры, запятые и дефисы")
        scripts = params.get("scripts")
        if scripts is not None and not _SCRIPTS_RE.match(str(scripts)):
            raise ValueError("scripts: недопустимые символы в выборе NSE")
        timing = params.get("timing")
        if timing is not None and str(timing) not in ("T0", "T1", "T2", "T3", "T4", "T5"):
            raise ValueError("timing: ожидается T0..T5")
        timeout = int(params.get("timeout") or 180)
        if not 5 <= timeout <= 900:
            raise ValueError("timeout: допустимо 5..900 секунд")

    def execute(self, params: Dict[str, Any]) -> Dict[str, Any]:
        self.validate_params(params)
        target = str(params["target"]).strip()
        timeout = int(params.get("timeout") or 180)

        nmap = os.environ.get("NMAP_BIN") or shutil.which("nmap")
        if not nmap:
            return {
                "status": "error",
                "error": {
                    "type": "missing_dependency",
                    "message": "nmap не найден в PATH; установите nmap или задайте NMAP_BIN",
                },
            }

        cmd = [nmap, "-sT", "-oX", "-", "--open", f"-{params.get('timing') or 'T3'}"]
        if params.get("ports"):
            cmd += ["-p", str(params["ports"])]
        if params.get("scripts"):
            cmd += ["--script", str(params["scripts"])]
        cmd.append(target)

        started = time.monotonic()
        try:
            proc = subprocess.run(  # noqa: S603 — аргументы валидированы, без shell
                cmd, capture_output=True, text=True, timeout=timeout
            )
        except subprocess.TimeoutExpired:
            return {
                "status": "timeout",
                "summary": f"скан {target} прерван по таймауту {timeout}s",
                "scan": {"command": _cmd_str(cmd), "exit_code": None, "seconds": round(time.monotonic() - started, 1)},
            }
        elapsed = round(time.monotonic() - started, 1)

        if proc.returncode != 0:
            return {
                "status": "error",
                "error": {"type": "nmap_exit_nonzero", "message": proc.stderr.strip()[-2000:] or "nmap завершился с ошибкой"},
                "scan": {"command": _cmd_str(cmd), "exit_code": proc.returncode, "seconds": elapsed},
            }

        hosts = _parse_xml(proc.stdout)
        total_ports = sum(len(h["open_ports"]) for h in hosts)
        return {
            "status": "success",
            "summary": f"{target}: хостов вверх {len(hosts)}, открытых портов {total_ports}",
            "hosts": hosts,
            "scan": {"command": _cmd_str(cmd), "exit_code": 0, "seconds": elapsed},
        }


def _cmd_str(cmd) -> str:
    return " ".join(cmd[:8])  # команду целиком видно в логах моста; модели хватает префикса


def _parse_xml(xml_text: str):
    hosts = []
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return hosts
    for h in root.findall("host"):
        state_el = h.find("status")
        addr_el = h.find("address")
        host_el = h.find(".//hostname/name")
        entry = {
            "state": state_el.get("state") if state_el is not None else "unknown",
            "address": addr_el.get("addr") if addr_el is not None else None,
            "hostname": host_el.text if host_el is not None else None,
            "open_ports": [],
        }
        for p in h.findall(".//port"):
            st = p.find("state")
            if st is None or st.get("state") != "open":
                continue
            svc = p.find("service")
            entry["open_ports"].append(
                {
                    "port": int(p.get("portid") or 0),
                    "proto": p.get("protocol"),
                    "service": svc.get("name") if svc is not None else None,
                    "product": svc.get("product") if svc is not None else None,
                    "version": svc.get("version") if svc is not None else None,
                }
            )
        hosts.append(entry)
    return hosts


if __name__ == "__main__":  # ручной прогон вне MCP
    import json
    import sys as _sys

    args = dict(a.split("=", 1) for a in _sys.argv[1:] if "=" in a)
    print(json.dumps(NmapScanSkill().execute(args), ensure_ascii=False, indent=2))
