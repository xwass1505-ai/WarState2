#!/usr/bin/env python3
"""CI prebuild hook: unpacks the REAL Rojo release ZIP committed in the repo, puts rojo on PATH and
generates the static map sources (src/Workspace/Map/*.model.json) from GameConfig.json.

    python tools/ci_unpack_rojo.py rojo-7.7.0-windows-x86_64.zip .rojo_bin

The static map is generated BEFORE `rojo build`, so the real Rojo 7.7.0 serializes the whole map
into build/WarState.rbxlx (the map exists in the place before any player joins). The generated
files are deterministic and are also shipped inside WarState_READY_BUILD.zip.
"""
import os
import stat
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

archive, dest = Path(sys.argv[1]), Path(sys.argv[2]).resolve()
dest.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(archive) as z:
    z.extractall(dest)
exe = next((p for p in dest.rglob("*") if p.name.lower() in ("rojo.exe", "rojo")), None)
if exe is None:
    print("FAIL: no rojo binary inside", archive)
    sys.exit(1)
exe.chmod(exe.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
print("Rojo binary:", exe, "(%d bytes)" % exe.stat().st_size)
gh_path = os.environ.get("GITHUB_PATH")
if gh_path:
    with open(gh_path, "a", encoding="utf-8") as f:
        f.write(str(exe.parent) + "\n")

# Prebuild: static map sources (must exist before the real rojo build).
r = subprocess.run([sys.executable, str(ROOT / "tools" / "gen_static_map.py")], cwd=str(ROOT))
if r.returncode != 0:
    print("FAIL: static map generation")
    sys.exit(r.returncode)
r = subprocess.run([sys.executable, str(ROOT / "tools" / "gen_static_map.py"), "--check"], cwd=str(ROOT))
sys.exit(r.returncode)

