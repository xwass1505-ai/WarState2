#!/usr/bin/env python3
"""Creates WarState_READY_BUILD.zip: the FULL current project + the fresh build/WarState.rbxlx.

    python tools/make_release_zip.py [WarState_READY_BUILD.zip]

Excluded: .git, dist/, old/nested WarState_READY_BUILD*.zip, __pycache__, *.pyc, ci_logs/.
Fails if build/WarState.rbxlx is missing.
"""
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXCLUDE_DIRS = {".git", "dist", "__pycache__", "ci_logs", ".venv", "node_modules", ".rojo_bin"}


def included(rel: Path) -> bool:
    if any(part in EXCLUDE_DIRS for part in rel.parts):
        return False
    if rel.name.startswith("WarState_READY_BUILD") and rel.suffix == ".zip":
        return False
    if rel.suffix == ".pyc" or rel.name.endswith(".rbxlx.lock"):
        return False
    return True


def main():
    target = ROOT / (sys.argv[1] if len(sys.argv) > 1 else "WarState_READY_BUILD.zip")
    build = ROOT / "build" / "WarState.rbxlx"
    if not build.is_file():
        print("FAIL: build/WarState.rbxlx is missing - run the real rojo build first")
        return 1
    if target.exists():
        target.unlink()
    count = 0
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(ROOT.rglob("*")):
            rel = p.relative_to(ROOT)
            if p.is_file() and p != target and included(rel):
                z.write(p, str(Path("WarState") / rel))
                count += 1
    with zipfile.ZipFile(target) as z:
        names = set(z.namelist())
    for must in ("WarState/default.project.json", "WarState/build/WarState.rbxlx", "WarState/PROJECT.md",
                 "WarState/DEVELOPMENT_ROADMAP.md", "WarState/src/ServerScriptService/ServerMain.server.luau"):
        if must not in names:
            print("FAIL: zip is missing " + must)
            return 1
    print("ZIP: %s (%d files, %d bytes) PASS" % (target.name, count, target.stat().st_size))
    return 0


if __name__ == "__main__":
    sys.exit(main())

