#!/usr/bin/env python3
"""Rebuild agpatch.pyz (single-file zipapp) from agpatch/."""
import pathlib, shutil, subprocess, sys

root = pathlib.Path(__file__).resolve().parent
build = root / "build_tmp"
if build.exists():
    shutil.rmtree(build)
(build / "agpatch").mkdir(parents=True)
for f in (root / "agpatch").glob("*.py"):
    shutil.copy2(f, build / "agpatch" / f.name)
shutil.copy2(root / "__main__.py", build / "__main__.py")
subprocess.run([sys.executable, "-m", "zipapp", ".", "-p", "/usr/bin/env python3",
                "-o", str(root / "agpatch.pyz")], cwd=build, check=True)
shutil.rmtree(build)
print(f"wrote {(root / 'agpatch.pyz')} ({(root / 'agpatch.pyz').stat().st_size} bytes)")
