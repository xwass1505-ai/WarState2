#!/usr/bin/env python3
"""Verifies the place file produced by the REAL `rojo build` in CI.

    python tools/verify_build.py build/WarState.rbxlx [ci_logs/build_start.txt]

Checks: file exists, is non-empty, was written after the build step started (fresh build),
is valid Roblox XML and contains the required instances (scripts, remotes, static map).
Exit code 0 = PASS, 1 = FAIL.
"""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

REQUIRED_PATHS = [
    "ReplicatedStorage/Shared/Config/GameConfig",
    "ReplicatedStorage/Shared/Modules/Plots",
    "ReplicatedStorage/Remotes/ClaimPlot",
    "ServerScriptService/ServerMain",
    "ServerScriptService/Systems/World/WorldService",
    "StarterPlayer/StarterPlayerScripts/ClientMain",
    "StarterGui/MainUI/Screens/HUD",
    "Workspace/Map",
    "Workspace/Buildings",
    "Workspace/Roads",
    "Workspace/Vehicles",
]
EXTRA_REQUIRED = [p.strip() for p in (Path(__file__).with_name("required_build_paths.txt").read_text().splitlines()
                  if Path(__file__).with_name("required_build_paths.txt").exists() else []) if p.strip() and not p.startswith("#")]


def name_of(item):
    props = item.find("Properties")
    if props is None:
        return None
    for s in props:
        if s.get("name") == "Name":
            return s.text
    return None


def collect(item, prefix, out, classes):
    name = name_of(item) or "?"
    path = name if not prefix else prefix + "/" + name
    out.add(path)
    classes[item.get("class")] = classes.get(item.get("class"), 0) + 1
    for child in item.findall("Item"):
        collect(child, path, out, classes)


def main():
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "build/WarState.rbxlx")
    errors = []
    if not target.is_file():
        print("FAIL: %s does not exist" % target)
        return 1
    size = target.stat().st_size
    print("build file: %s (%d bytes)" % (target, size))
    if size < 10000:
        errors.append("build file is suspiciously small")
    if len(sys.argv) > 2:
        start = float(Path(sys.argv[2]).read_text().strip())
        mtime = target.stat().st_mtime
        print("build started at %.0f, file written at %.0f" % (start, mtime))
        if mtime + 1 < start:
            errors.append("build file is older than this build step (stale build)")
    root = ET.parse(target).getroot()
    paths, classes = set(), {}
    for item in root.findall("Item"):
        collect(item, "", paths, classes)
    for p in REQUIRED_PATHS + EXTRA_REQUIRED:
        if p not in paths:
            errors.append("missing instance: " + p)
    print("instances: %d" % sum(classes.values()))
    for cls in sorted(classes):
        print("  %-22s %d" % (cls, classes[cls]))
    if errors:
        for e in errors:
            print("FAIL: " + e)
        return 1
    print("BUILD VERIFY: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
