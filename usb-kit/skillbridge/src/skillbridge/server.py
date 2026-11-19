"""Skillbridge: MCP stdio-сервер поверх реестра бандлов skillware-формата.

Реестр — дерево каталогов вида <root>/<category>/<name>/ с manifest.yaml и skill.py.
Наружу вынесены три стабильных инструмента (имена не плодятся при добавлении скиллов,
контекст модели остаётся компактным):

  skills_list(query)          — каталог: id, описание, теги
  skills_info(skill)          — полный контракт манифеста + директива instructions.md
  skills_invoke(skill,params) — validate_params → execute → структурированный JSON

Исполнение детерминированное: код скилла выполняется здесь, в Python; в контекст модели
возвращается только результат по схеме outputs манифеста.
"""
from __future__ import annotations

import argparse
import importlib.util
import inspect
import json
import os
import sys
import traceback
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

try:  # mcp 2.x
    from mcp.server.mcpserver import MCPServer as _Server
except Exception:  # pragma: no cover - мост совместим с mcp 1.x
    from mcp.server.fastmcp import FastMCP as _Server

# Skillware опционален: без него работаем по duck-typing контракту.
try:
    from skillware.core.base_skill import BaseSkill  # type: ignore
except Exception:  # pragma: no cover
    BaseSkill = None  # type: ignore


def _log(msg: str) -> None:
    print(f"[skillbridge] {msg}", file=sys.stderr, flush=True)


class BundleError(Exception):
    pass


class Bundle:
    """Один бандл навыка на диске."""

    def __init__(self, skill_id: str, path: Path, manifest: Dict[str, Any]):
        self.skill_id = skill_id
        self.path = path
        self.manifest = manifest
        self._cls = None

    @property
    def description(self) -> str:
        return str(self.manifest.get("description") or self.manifest.get("short_description") or "").strip()

    @property
    def tags(self) -> List[str]:
        return [str(t).lower() for t in (self.manifest.get("tags") or [])]

    def load_class(self):
        if self._cls is not None:
            return self._cls
        entry = self.path / "skill.py"
        if not entry.is_file():
            raise BundleError(f"{self.skill_id}: нет skill.py")
        modname = f"skillbridge_bundle_{uuid.uuid4().hex}"
        spec = importlib.util.spec_from_file_location(modname, entry)
        if spec is None or spec.loader is None:
            raise BundleError(f"{self.skill_id}: не удалось загрузить skill.py")
        module = importlib.util.module_from_spec(spec)
        sys.modules[modname] = module
        try:
            spec.loader.exec_module(module)
        except Exception as exc:
            raise BundleError(f"{self.skill_id}: ошибка импорта skill.py: {exc}") from exc
        candidates = []
        for _, obj in vars(module).items():
            if inspect.isclass(obj) and obj.__module__ == modname and hasattr(obj, "execute"):
                candidates.append(obj)
        if not candidates:
            raise BundleError(f"{self.skill_id}: в skill.py нет класса с методом execute()")
        if BaseSkill is not None:
            preferred = [c for c in candidates if issubclass(c, BaseSkill)]
            candidates = preferred or candidates
        self._cls = candidates[0]
        return self._cls


def discover(root: Path) -> List[Bundle]:
    bundles: List[Bundle] = []
    if not root.is_dir():
        return bundles
    for manifest_path in sorted(root.glob("**/manifest.yaml")):
        folder = manifest_path.parent
        if not (folder / "skill.py").is_file():
            continue
        rel = folder.relative_to(root).as_posix()
        try:
            with open(manifest_path, "r", encoding="utf-8") as fh:
                manifest = yaml.safe_load(fh) or {}
        except Exception as exc:
            _log(f"пропускаю {rel}: невалидный manifest.yaml ({exc})")
            continue
        if not isinstance(manifest, dict):
            continue
        bundles.append(Bundle(str(manifest.get("name") or rel), folder, manifest))
    return bundles


_INSTANTIATE_ARGS = ("config", "manifest", "env", "logger", "settings")


def instantiate(cls: type, manifest: Dict[str, Any]) -> Any:
    """Создаёт экземпляр скилла, подстраиваясь под сигнатуру __init__."""
    config = {"manifest": manifest, "env": dict(os.environ)}
    known = {
        "config": config,
        "manifest": manifest,
        "env": dict(os.environ),
        "logger": None,
        "settings": {},
    }
    try:
        params = inspect.signature(cls.__init__).parameters
        wanted = {name: known[name] for name in params if name in known and name != "self"}
        if any(p.kind == inspect.Parameter.VAR_KEYWORD for p in params.values()):
            wanted = known
        return cls(**wanted)
    except (TypeError, ValueError):
        return cls()


def _to_content(result: Any) -> Dict[str, Any]:
    if isinstance(result, dict) and "status" in result:
        return result
    return {"status": "success", "result": result}


class Registry:
    """Состояние моста: корень реестра + операции над ним."""

    def __init__(self, root: Path):
        self.root = root

    def bundles(self) -> List[Bundle]:
        return discover(self.root)

    def get(self, skill_id: str) -> Bundle:
        for b in self.bundles():
            if b.skill_id == skill_id or b.skill_id.endswith("/" + skill_id):
                return b
        raise BundleError(f"навык не найден: {skill_id}")

    def list(self, query: str = "") -> List[Dict[str, Any]]:
        q = (query or "").strip().lower()
        out = []
        for b in self.bundles():
            hay = " ".join([b.skill_id, b.description, *b.tags]).lower()
            if not q or q in hay:
                out.append(
                    {
                        "skill": b.skill_id,
                        "version": b.manifest.get("version"),
                        "shape": b.manifest.get("shape"),
                        "description": b.description,
                        "tags": b.tags,
                    }
                )
        return out

    def info(self, skill_id: str) -> Dict[str, Any]:
        b = self.get(skill_id)
        directive = ""
        instr = b.path / "instructions.md"
        if instr.is_file():
            directive = instr.read_text(encoding="utf-8", errors="replace")
        extras = sorted(
            p.relative_to(b.path).as_posix()
            for p in b.path.rglob("*")
            if p.is_file() and p.name not in ("skill.py", "manifest.yaml", "instructions.md", "card.json")
        )
        return {
            "skill": b.skill_id,
            "manifest": b.manifest,
            "directive": directive,
            "bundled_files": extras[:200],
        }

    def invoke(self, skill_id: str, params: Optional[Dict[str, Any]]) -> Dict[str, Any]:
        params = params or {}
        try:
            b = self.get(skill_id)
            cls = b.load_class()
            inst = instantiate(cls, b.manifest)
            if hasattr(inst, "validate_params"):
                inst.validate_params(params)
            result = inst.execute(params)
        except BundleError as exc:
            return {"status": "error", "error": {"type": "bundle_error", "message": str(exc)}}
        except ValueError as exc:  # провал validate_params или санитарных проверок бандла
            _log(f"отклонено {skill_id}: {exc}")
            return {"status": "error", "error": {"type": "invalid_params", "message": str(exc)}}
        except Exception as exc:  # noqa: BLE001 — структурируем любой сбой для модели
            _log(traceback.format_exc())
            return {"status": "error", "error": {"type": exc.__class__.__name__, "message": str(exc)}}
        return _to_content(result)


def build_app(registry: Registry):
    app = _Server("skillbridge")

    @app.tool(
        name="skills_list",
        description="Список доступных типизированных навыков (skillware-бандлы) с описаниями. Опциональная фильтрация подстрокой.",
    )
    def skills_list(query: str = "") -> str:
        return json.dumps(registry.list(query), ensure_ascii=False)

    @app.tool(
        name="skills_info",
        description="Полный контракт навыка: параметры/выходы из manifest.yaml плюс директива instructions.md. Вызывать до первого invoke.",
    )
    def skills_info(skill: str) -> str:
        try:
            return json.dumps(registry.info(skill), ensure_ascii=False)
        except BundleError as exc:
            return json.dumps({"status": "error", "error": {"type": "bundle_error", "message": str(exc)}}, ensure_ascii=False)

    @app.tool(
        name="skills_invoke",
        description="Исполнить навык с параметрами по его контракту. Возвращает структурированный JSON со статусом. Параметры брать из skills_info.",
    )
    def skills_invoke(skill: str, params: dict = None) -> str:  # noqa: RUF013
        return json.dumps(registry.invoke(skill, params), ensure_ascii=False, default=str)

    return app


def _selftest(root: Path) -> int:
    registry = Registry(root)
    found = registry.list()
    _log(f"самотест: корень={root}, найдено навыков={len(found)}")
    ok = True
    for item in found:
        try:
            b = registry.get(item["skill"])
            b.load_class()
            _log(f"  ✓ {item['skill']} загружается")
        except BundleError as exc:
            ok = False
            _log(f"  ✗ {item['skill']}: {exc}")
    if found:
        probe = registry.invoke(found[0]["skill"], {})
        _log(f"пробный вызов {found[0]['skill']}: статус={probe.get('status')}")
    print(json.dumps({"skills": len(found), "ok": ok}, ensure_ascii=False))
    return 0 if ok else 1


def main() -> None:
    parser = argparse.ArgumentParser(prog="skillbridge", description=__doc__)
    parser.add_argument("--root", help="каталог реестра навыков (по умолчанию $SKILLS_ROOT)")
    parser.add_argument("--selftest", action="store_true", help="проверить реестр и выйти")
    args = parser.parse_args()

    root = Path(args.root or os.environ.get("SKILLS_ROOT", "skills")).resolve()
    registry = Registry(root)

    if args.selftest:
        sys.exit(_selftest(root))

    app = build_app(registry)
    _log(f"MCP stdio, реестр: {root}")
    app.run()


if __name__ == "__main__":
    main()
