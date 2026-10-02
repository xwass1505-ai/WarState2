# -*- coding: utf-8 -*-
"""Static map generator for War State (Phase 1).

Reads src/ReplicatedStorage/Shared/Config/GameConfig.json and writes Rojo .model.json files into
src/Workspace/Map/. The real `rojo build` then puts the whole map (central island, 6 player islands,
exits, bridges, trees, bushes, rocks, dirt paths, invisible boundaries, lobby spawn) into the place
file, so the map exists BEFORE any player joins. Nothing is generated on PlayerAdded.

Terrain water cannot be serialized from source by Rojo, so WorldService fills real Terrain water
once at server start (before players can join). See WorldService.fillTerrainWater.

    python tools/gen_static_map.py          # write files
    python tools/gen_static_map.py --check  # exit 1 if committed files are out of date

Property encoding follows the format verified with the real Rojo 7.7.0 in CI
(tools/rojo_probe/a_map/Thing.model.json): explicitly typed Vector3 / CFrame / Color3 / Enum values.
The output is deterministic (seeded RNG, fixed float rounding).
"""

from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "src" / "ReplicatedStorage" / "Shared" / "Config"
OUT = ROOT / "src" / "Workspace" / "Map"

# Enum.Material values
MAT = {
    "SmoothPlastic": 272, "Neon": 288, "Wood": 512, "WoodPlanks": 528, "Slate": 800, "Concrete": 816,
    "Pebble": 864, "Rock": 896, "Metal": 1088, "Grass": 1280, "LeafyGrass": 1284, "Sand": 1296,
    "Ground": 1360, "Asphalt": 1376,
}
SIDE = {"N": (0, -1), "E": (1, 0), "S": (0, 1), "W": (-1, 0)}


def r(v):
    return round(float(v), 3)


def rot_y(yaw):
    c, s = math.cos(yaw), math.sin(yaw)
    # rows of the rotation matrix (R00 R01 R02 / R10 R11 R12 / R20 R21 R22) == CFrame.Angles(0, yaw, 0)
    return [[r(c), 0, r(s)], [0, 1, 0], [r(-s), 0, r(c)]]


IDENTITY = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
FLAT_CYLINDER = [[0, -1, 0], [1, 0, 0], [0, 0, 1]]  # cylinder axis (X) turned to point up


def part(name, size, pos, color, material="SmoothPlastic", orientation=None, collide=True, transparency=None,
         shape=None, query=True, shadow=True, attributes=None, children=None, class_name="Part", extra=None):
    props = {
        "Anchored": True,
        "CanCollide": bool(collide),
        "CanTouch": False,
        "Size": {"Vector3": [r(size[0]), r(size[1]), r(size[2])]},
        "CFrame": {"CFrame": {"position": [r(pos[0]), r(pos[1]), r(pos[2])], "orientation": orientation or IDENTITY}},
        "Color": {"Color3": [r(color[0]), r(color[1]), r(color[2])]},
        "Material": {"Enum": MAT[material]},
        "TopSurface": {"Enum": 0},
        "BottomSurface": {"Enum": 0},
    }
    if transparency is not None:
        props["Transparency"] = r(transparency)
    if shape is not None:
        props["Shape"] = {"Enum": shape}
    if not query:
        props["CanQuery"] = False
    if not shadow:
        props["CastShadow"] = False
    if extra:
        props.update(extra)
    node = {"Name": name, "ClassName": class_name, "Properties": props}
    if attributes:
        node["Attributes"] = attributes
    if children:
        node["Children"] = children
    return node


def model(name, children, attributes=None, class_name="Model"):
    node = {"Name": name, "ClassName": class_name, "Children": children}
    if attributes:
        node["Attributes"] = attributes
    return node


def strip(name, ax, az, bx, bz, width, thick, top, color, material, **kw):
    dx, dz = bx - ax, bz - az
    length = math.hypot(dx, dz)
    yaw = math.atan2(-dx, -dz)  # CFrame.lookAt direction -> yaw so that -Z faces (dx, dz)
    return part(name, (width, thick, length), ((ax + bx) / 2, top - thick / 2, (az + bz) / 2), color, material,
                orientation=rot_y(yaw), **kw)


# ---------------------------------------------------------------------------------------------
def plot_bounds(game, p):
    t = game["Territory"]
    half = t["Size"] / 2
    return {
        "index": p["Index"], "cx": p["CenterX"], "cz": p["CenterZ"], "minX": p["CenterX"] - half,
        "minZ": p["CenterZ"] - half, "size": t["Size"], "y": t["SurfaceY"], "side": p["ExitSide"],
    }


def plot_exit(game, placement, b):
    """Python mirror of Plots.getExit (Luau)."""
    tile = placement["RoadTileSize"]
    tiles = b["size"] // tile
    mid = tiles // 2
    side = b["side"]
    ix, iz = {"N": (mid, 0), "S": (mid, tiles - 1), "E": (tiles - 1, mid), "W": (0, mid)}[side]
    tile_x = b["minX"] + (ix + 0.5) * tile
    tile_z = b["minZ"] + (iz + 0.5) * tile
    vx, vz = SIDE[side]
    rim = game["Territory"]["RimWidth"]
    half = b["size"] / 2
    edge_x, edge_z = b["cx"] + vx * half, b["cz"] + vz * half
    if vx == 0:
        edge_x = tile_x
    else:
        edge_z = tile_z
    rim_x, rim_z = edge_x + vx * rim, edge_z + vz * rim
    c = game["Map"]["CentralIsland"]
    ch = c["Size"] / 2
    land_x, land_z = rim_x, rim_z
    if side == "S":
        land_z = c["CenterZ"] - ch + c["BeachWidth"]
    elif side == "N":
        land_z = c["CenterZ"] + ch - c["BeachWidth"]
    elif side == "E":
        land_x = c["CenterX"] - ch + c["BeachWidth"]
    else:
        land_x = c["CenterX"] + ch - c["BeachWidth"]
    return {"side": side, "ix": ix, "iz": iz, "edge": (edge_x, edge_z), "rim": (rim_x, rim_z), "land": (land_x, land_z)}


# ---------------------------------------------------------------------------------------------
def build_bridge(game, ex, y):
    m = game["Map"]
    w = m["BridgeWidth"]
    base_y = m["BaseY"]
    deck_col = m["BridgeColor"]
    rail_col = m["BridgeRailColor"]
    asphalt = m["BridgeAsphaltColor"]
    (sx, sz), (lx, lz) = ex["rim"], ex["land"]
    vx, vz = SIDE[ex["side"]]
    px, pz = -vz, vx
    kids = []
    kids.append(strip("Deck", sx, sz, lx, lz, w, 0.9, y + 0.1, deck_col, "Concrete"))
    kids.append(strip("Lane", sx, sz, lx, lz, w - 1.6, 0.06, y + 0.16, asphalt, "Asphalt", collide=False))
    for s in (-1, 1):
        ox, oz = px * s * (w / 2 - 0.3), pz * s * (w / 2 - 0.3)
        kids.append(strip("Curb", sx + ox, sz + oz, lx + ox, lz + oz, 0.6, 0.3, y + 0.4, rail_col, "Concrete"))
        rx, rz = px * s * (w / 2 + 0.05), pz * s * (w / 2 + 0.05)
        kids.append(strip("Rail", sx + rx, sz + rz, lx + rx, lz + rz, 0.25, 0.25, y + 1.5, rail_col, "Metal"))
    length = math.hypot(lx - sx, lz - sz)
    posts = max(2, int(length // 10))
    for i in range(posts + 1):
        f = i / posts
        cx, cz = sx + (lx - sx) * f, sz + (lz - sz) * f
        for s in (-1, 1):
            kids.append(part("Post", (0.3, 1.4, 0.3), (cx + px * s * (w / 2 + 0.05), y + 0.8, cz + pz * s * (w / 2 + 0.05)),
                             rail_col, "Metal", collide=False))
    pillars = max(2, int(length // 24))
    for i in range(1, pillars):
        f = i / pillars
        cx, cz = sx + (lx - sx) * f, sz + (lz - sz) * f
        h = (y - 0.8) - base_y
        kids.append(part("Pillar", (w - 1, h, 1.6) if vx == 0 else (1.6, h, w - 1), (cx, base_y + h / 2, cz),
                         deck_col, "Concrete", shadow=False))
    for end_x, end_z in ((sx, sz), (lx, lz)):
        for s in (-1, 1):
            bx, bz = end_x + px * s * (w / 2 + 0.6), end_z + pz * s * (w / 2 + 0.6)
            light = {"Name": "Light", "ClassName": "PointLight",
                     "Properties": {"Range": 14, "Brightness": 0.8, "Color": {"Color3": [1, 0.93, 0.78]}}}
            kids.append(model("Lamp", [
                part("Pole", (0.25, 4, 0.25), (bx, y + 2.1, bz), (0.3, 0.32, 0.35), "Metal", collide=False),
                part("Bulb", (0.6, 0.35, 0.6), (bx, y + 4.2, bz), (1, 0.95, 0.82), "Neon", collide=False, children=[light]),
            ]))
    return model("Bridge", kids, {"Length": r(length)})


def build_plot(game, placement, p):
    t = game["Territory"]
    m = game["Map"]
    b = plot_bounds(game, p)
    y = b["y"]
    base_y = m["BaseY"]
    island = t["Size"] + t["RimWidth"] * 2
    kids = []
    kids.append(part("Rim", (island, (y - 0.12) - base_y, island), (b["cx"], (y - 0.12 + base_y) / 2, b["cz"]),
                     t["SandColor"], "Sand"))
    kids.append(part("Ground", (t["Size"], t["Thickness"], t["Size"]), (b["cx"], y - t["Thickness"] / 2, b["cz"]),
                     t["Color"], "Grass", attributes={"PlotIndex": p["Index"]}))
    bw = t["BorderWidth"]
    S = t["Size"]
    sides = [((S, 0.06, bw), (0, -S / 2 + bw / 2)), ((S, 0.06, bw), (0, S / 2 - bw / 2)),
             ((bw, 0.06, S), (-S / 2 + bw / 2, 0)), ((bw, 0.06, S), (S / 2 - bw / 2, 0))]
    for i, (size, (ox, oz)) in enumerate(sides, 1):
        kids.append(part("Border%d" % i, size, (b["cx"] + ox, y + 0.03, b["cz"] + oz), t["BorderColor"], collide=False, query=False))

    ex = plot_exit(game, placement, b)
    w = m["BridgeWidth"]
    vx, vz = SIDE[ex["side"]]
    px, pz = -vz, vx
    accent = (0.36, 0.62, 0.9)
    exit_kids = [strip("ExitLane", ex["edge"][0], ex["edge"][1], ex["rim"][0], ex["rim"][1], w, 0.4, y + 0.08,
                       (0.49, 0.5, 0.53), "Concrete")]
    exit_kids.append(strip("ExitAsphalt", ex["edge"][0], ex["edge"][1], ex["rim"][0], ex["rim"][1], w - 1.6, 0.05, y + 0.13,
                           m["BridgeAsphaltColor"], "Asphalt", collide=False))
    for s in (-1, 1):
        gx, gz = ex["edge"][0] + px * s * (w / 2 + 0.6), ex["edge"][1] + pz * s * (w / 2 + 0.6)
        exit_kids.append(part("GatePost", (0.6, 3.4, 0.6), (gx, y + 1.7, gz), accent, collide=False))
    beam_len = w + 1.8
    exit_kids.append(part("GateBeam", (beam_len, 0.45, 0.45) if vx == 0 else (0.45, 0.45, beam_len),
                          (ex["edge"][0], y + 3.4, ex["edge"][1]), (0.97, 0.98, 1), collide=False))
    exit_kids.append(build_bridge(game, ex, y))
    kids.append(model("Exit", exit_kids, {"ExitSide": ex["side"], "ExitIx": ex["ix"], "ExitIz": ex["iz"]}))
    kids.append(part("OwnerSign", (1, 1, 1), (b["cx"], y + 20, b["cz"]), (1, 1, 1), collide=False, transparency=1,
                     query=False, shadow=False))
    return model("Plot_%d" % p["Index"], kids, {"PlotIndex": p["Index"], "OwnerUserId": 0})


# ---------------------------------------------------------------------------------------------
def dist_to_segment(px, pz, ax, az, bx, bz):
    dx, dz = bx - ax, bz - az
    L2 = dx * dx + dz * dz
    t = 0 if L2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / L2))
    return math.hypot(px - (ax + t * dx), pz - (az + t * dz))


def build_central(game, placement):
    m = game["Map"]
    c = m["CentralIsland"]
    d = m["Decorations"]
    rng = random.Random(d["Seed"])
    cx, cz, size = c["CenterX"], c["CenterZ"], c["Size"]
    base_y = m["BaseY"]
    inner = size - c["BeachWidth"] * 2
    kids = [
        part("Beach", (size, -0.15 - base_y, size), (cx, (-0.15 + base_y) / 2, cz), game["Territory"]["SandColor"], "Sand"),
        part("Ground", (inner, -base_y, inner), (cx, base_y / 2, cz), c["Color"], "Grass"),
    ]
    # Dirt paths: every bridge landing -> central plaza, plus a ring trail.
    paths, segments = [], []
    pw = d["PathWidth"]
    pcol = d["PathColor"]
    plaza = c["PlazaRadius"]

    def add_polyline(points, width):
        for (ax, az), (bx, bz) in zip(points, points[1:]):
            segments.append((ax, az, bx, bz))
            paths.append(strip("Path", ax, az, bx, bz, width, 0.08, 0.05, pcol, "Ground", collide=False))
            paths.append(part("PathJoint", (width, 0.08, width), (bx, 0.01, bz), pcol, "Ground",
                              orientation=rot_y(math.pi / 4), collide=False))

    for p in m["Plots"]:
        ex = plot_exit(game, placement, plot_bounds(game, p))
        lx, lz = ex["land"]
        pts = [(lx, lz)]
        steps = 9
        for i in range(1, steps):
            f = i / steps
            x, z = lx + (cx - lx) * f, lz + (cz - lz) * f
            jitter = 3.5 * math.sin(f * math.pi)
            x += rng.uniform(-jitter, jitter)
            z += rng.uniform(-jitter, jitter)
            pts.append((x, z))
        vx, vz = (cx - lx), (cz - lz)
        L = math.hypot(vx, vz)
        pts.append((cx - vx / L * plaza, cz - vz / L * plaza))
        add_polyline(pts, pw + rng.uniform(-0.3, 0.4))
    ring_r = inner * 0.3
    ring = []
    for i in range(25):
        a = i / 24 * math.pi * 2
        rr = ring_r + rng.uniform(-4, 4) if i < 24 else ring_r
        ring.append((cx + math.cos(a) * rr, cz + math.sin(a) * rr))
    ring[-1] = ring[0]
    add_polyline(ring, pw - 0.6)
    paths.append(part("Plaza", (0.1, plaza * 2, plaza * 2), (cx, 0.04, cz), pcol, "Ground", orientation=FLAT_CYLINDER,
                      shape=2, collide=False))
    kids.append(model("Paths", paths, class_name="Folder"))

    # Vegetation / rocks (avoid paths, plaza and beach)
    limit = inner / 2 - 6
    occupied = []

    def free_spot(clearance):
        for _ in range(400):
            x = cx + rng.uniform(-limit, limit)
            z = cz + rng.uniform(-limit, limit)
            if math.hypot(x - cx, z - cz) < plaza + 8:
                continue
            if any(dist_to_segment(x, z, *s) < pw / 2 + clearance for s in segments):
                continue
            if any(math.hypot(x - ox, z - oz) < clearance + orad for ox, oz, orad in occupied):
                continue
            occupied.append((x, z, clearance))
            return x, z
        return None

    trees = []
    for i in range(d["Trees"]):
        spot = free_spot(2.5)
        if not spot:
            break
        x, z = spot
        sc = rng.uniform(0.9, 1.5)
        trunk_h = 2.4 * sc
        trunk = part("Trunk", (0.55 * sc, trunk_h, 0.55 * sc), (x, trunk_h / 2, z), (0.59, 0.44, 0.31), "Wood", collide=False)
        g = rng.randint(0, 24)
        if i % 3 == 0:  # pine
            leaf = (0.33, 0.55 + g / 255, 0.36)
            parts_ = [trunk]
            for k, (wd, ht) in enumerate(((2.6, 1.3), (1.9, 1.2), (1.1, 1.1))):
                parts_.append(part("Needles", (wd * sc, ht * sc, wd * sc), (x, trunk_h + (0.4 + k * 1.05) * sc, z), leaf,
                                   orientation=rot_y(rng.uniform(0, 1.5)), collide=False))
        else:  # round leafy tree
            leaf = (0.44 + g / 400, 0.64 + g / 255, 0.38)
            top = (min(1, leaf[0] + 0.06), min(1, leaf[1] + 0.06), min(1, leaf[2] + 0.06))
            parts_ = [trunk,
                      part("Leaves", (2.4 * sc, 1.7 * sc, 2.4 * sc), (x, trunk_h + 0.6 * sc, z), leaf,
                           orientation=rot_y(rng.uniform(0, 1.5)), collide=False),
                      part("LeavesTop", (1.5 * sc, 1.1 * sc, 1.5 * sc), (x, trunk_h + 1.8 * sc, z), top,
                           orientation=rot_y(rng.uniform(0, 1.5)), collide=False)]
        trees.append(model("Tree", parts_))
    bushes = []
    for _ in range(d["Bushes"]):
        spot = free_spot(1.2)
        if not spot:
            break
        x, z = spot
        sc = rng.uniform(0.7, 1.2)
        col = (0.38, 0.6 + rng.uniform(0, 0.08), 0.34)
        kid = [part("Bush", (1.4 * sc, 0.8 * sc, 1.2 * sc), (x, 0.4 * sc, z), col, "LeafyGrass",
                    orientation=rot_y(rng.uniform(0, 3)), collide=False)]
        if rng.random() < 0.5:
            kid.append(part("Bush", (0.9 * sc, 0.6 * sc, 0.9 * sc), (x + 0.5 * sc, 0.5 * sc, z + 0.3 * sc),
                            (col[0] + 0.05, col[1] + 0.05, col[2]), "LeafyGrass", collide=False))
        bushes.append(model("Bush", kid))
    rocks = []
    for _ in range(d["Rocks"]):
        spot = free_spot(1.6)
        if not spot:
            break
        x, z = spot
        sc = rng.uniform(0.7, 1.7)
        grey = rng.uniform(0.62, 0.74)
        kid = [part("Rock", (1.6 * sc, 0.9 * sc, 1.3 * sc), (x, 0.3 * sc, z), (grey, grey + 0.01, grey + 0.03), "Slate",
                    orientation=rot_y(rng.uniform(0, 3)))]
        if rng.random() < 0.4:
            kid.append(part("Pebble", (0.7 * sc, 0.4 * sc, 0.6 * sc), (x + 1.1 * sc, 0.15 * sc, z - 0.4 * sc),
                            (grey - 0.05, grey - 0.04, grey - 0.02), "Slate", orientation=rot_y(rng.uniform(0, 3)), collide=False))
        rocks.append(model("Rock", kid))
    kids.append(model("Trees", trees, class_name="Folder"))
    kids.append(model("Bushes", bushes, class_name="Folder"))
    kids.append(model("Rocks", rocks, class_name="Folder"))

    lobby = m["LobbySpawn"]
    kids.append({"Name": "LobbySpawn", "ClassName": "SpawnLocation", "Properties": {
        "Anchored": True, "Neutral": True, "Duration": 0, "CanTouch": True,
        "Size": {"Vector3": [8, 0.4, 8]},
        "CFrame": {"CFrame": {"position": [lobby[0], 0.2, lobby[2]], "orientation": IDENTITY}},
        "Color": {"Color3": [0.8, 0.9, 1]}, "Material": {"Enum": MAT["SmoothPlastic"]},
        "TopSurface": {"Enum": 0},
    }})
    return model("CentralIsland", kids, {"Purpose": "Future land battles"})


def build_boundaries(game):
    bd = game["Map"]["Boundary"]
    h, half, th = bd["Height"], bd["HalfSize"], bd["Thickness"]
    y = game["Map"]["BaseY"] - 6 + h / 2
    span = half * 2 + th * 2
    walls = []
    for name, size, pos in (
        ("North", (span, h, th), (0, y, -half - th / 2)),
        ("South", (span, h, th), (0, y, half + th / 2)),
        ("West", (th, h, span), (-half - th / 2, y, 0)),
        ("East", (th, h, span), (half + th / 2, y, 0)),
    ):
        walls.append(part(name, size, pos, (1, 1, 1), transparency=1, query=False, shadow=False))
    return model("Boundaries", walls, {"HalfSize": half, "Invisible": True})


def generate():
    game = json.loads((CONFIG / "GameConfig.json").read_text(encoding="utf-8"))
    placement = json.loads((CONFIG / "PlacementConfig.json").read_text(encoding="utf-8"))
    files = {
        "CentralIsland.model.json": build_central(game, placement),
        "Boundaries.model.json": build_boundaries(game),
    }
    for p in game["Map"]["Plots"]:
        files["Plots/Plot_%d.model.json" % p["Index"]] = build_plot(game, placement, p)
    out = {}
    for rel, node in files.items():
        node = dict(node)
        node.pop("Name", None)  # Rojo names the instance after the file
        out[rel] = json.dumps(node, separators=(",", ":"), sort_keys=False) + "\n"
    return out


def count_parts(node):
    n = 1 if node.get("ClassName") in ("Part", "SpawnLocation") else 0
    for c in node.get("Children", []):
        n += count_parts(c)
    return n


def main():
    files = generate()
    if "--check" in sys.argv:
        stale = [rel for rel, text in files.items() if not (OUT / rel).is_file() or (OUT / rel).read_text(encoding="utf-8") != text]
        if stale:
            print("STALE static map files: %s (run python tools/gen_static_map.py)" % stale)
            return 1
        print("static map up to date (%d files)" % len(files))
        return 0
    total = 0
    for rel, text in files.items():
        path = OUT / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        parts = count_parts(json.loads(text))
        total += parts
        print("wrote %-28s %5d parts %7d bytes" % (rel, parts, len(text)))
    print("total parts: %d" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
