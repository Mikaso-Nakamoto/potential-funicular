#!/usr/bin/env python3
"""Запуск всех тестов без pytest:  python3 tests/run_all.py

Каждый файл tests/test_*.py: ищем функции test_* и выполняем.
Работает и под pytest:  pytest -q   (если он установлен).
"""

from __future__ import annotations

import importlib
import sys
import time
import traceback
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

MODULES = ["tests.test_slots", "tests.test_flow", "tests.test_scheduler"]


def main() -> int:
    passed = failed = 0
    failures: list[str] = []
    started = time.time()

    for module_name in MODULES:
        module = importlib.import_module(module_name)
        names = [n for n in dir(module) if n.startswith("test_")]
        print(f"\n── {module_name} ({len(names)} тестов) " + "─" * 30)
        for name in sorted(names):
            fn = getattr(module, name)
            if not callable(fn):
                continue
            t0 = time.time()
            try:
                fn()
            except Exception:  # noqa: BLE001
                failed += 1
                print(f"  ✗ {name}")
                failures.append(f"{module_name}.{name}\n{traceback.format_exc()}")
            else:
                passed += 1
                print(f"  ✓ {name} ({(time.time() - t0) * 1000:.0f} ms)")

    print("\n" + "=" * 64)
    if failures:
        print("ОШИБКИ:\n")
        for item in failures:
            print(item)
            print("-" * 64)
    print(f"Итог: {passed} прошло, {failed} упало, {time.time() - started:.1f} c")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
