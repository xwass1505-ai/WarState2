#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""WAR STATE build runner (v0.3).

    python build_war_state.py                 # generate static map + tests + REAL rojo build
    python build_war_state.py --serve         # ... then `rojo serve` for live sync into Studio
    python build_war_state.py --write-registry  # regenerate CountryRegistry.json from tools/countries.py

The only valid place build is the REAL Rojo (7.7.0):
    rojo build default.project.json -o build/WarState.rbxlx
CI (GitHub Actions) does exactly that and publishes WarState_READY_BUILD.zip as an artifact.
tools/rojo_build.py is a structure checker for unit tests only and never counts as a Rojo build.
"""
import argparse, json, shutil, subprocess, sys, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
GENERATOR_VERSION = "0.3.0"
sys.path.insert(0, str(ROOT / "tools"))


def write_registry():
    import countries
    path = ROOT / "src/ReplicatedStorage/Shared/Config/CountryRegistry.json"
    path.write_text(json.dumps(countries.country_registry(), ensure_ascii=False, indent=1), encoding="utf-8")
    print("[registry] wrote %d countries" % len(countries.COUNTRIES))


def generate_map():
    r = subprocess.run([sys.executable, str(ROOT / "tools" / "gen_static_map.py")], cwd=str(ROOT))
    return r.returncode == 0


def run_tests():
    suite = unittest.defaultTestLoader.discover(str(ROOT / "tests"), top_level_dir=str(ROOT))
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    return result.wasSuccessful()


def build():
    out = ROOT / "build" / "WarState.rbxlx"
    if not shutil.which("rojo"):
        print("[rojo] NOT INSTALLED - install Rojo 7.7.0 (or let GitHub Actions build). No place file was produced.")
        return False
    if out.exists():
        out.unlink()
    r = subprocess.run(["rojo", "build", str(ROOT / "default.project.json"), "-o", str(out)])
    print("[rojo] build", "PASS" if r.returncode == 0 else "FAIL")
    return r.returncode == 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--serve", action="store_true")
    ap.add_argument("--write-registry", action="store_true")
    a = ap.parse_args()
    if a.write_registry:
        write_registry()
    ok = generate_map() and run_tests() and build()
    if ok and a.serve:
        subprocess.run(["rojo", "serve", str(ROOT / "default.project.json")])
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
