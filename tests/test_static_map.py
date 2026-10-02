"""Phase 1: static map. The map is generated from config into src/Workspace/Map (.model.json) and
serialized by the real Rojo into the place, so it exists before any player joins."""
import json
import math
import sys
import unittest

from tests._common import ROOT, load_json, read

sys.path.insert(0, str(ROOT / "tools"))
import gen_static_map  # noqa: E402

MAP = ROOT / "src" / "Workspace" / "Map"


def walk(node):
    yield node
    for c in node.get("Children", []):
        yield from walk(c)


def child(node, name):
    for c in node.get("Children", []):
        if c.get("Name") == name:
            return c
    return None


class StaticMapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files = gen_static_map.generate()
        cls.data = {rel: json.loads(text) for rel, text in cls.files.items()}
        cls.game = load_json("GameConfig.json")
        cls.m = cls.game["Map"]

    def test_generated_files_are_up_to_date(self):
        for rel, text in self.files.items():
            self.assertTrue((MAP / rel).is_file(), rel)
            self.assertEqual((MAP / rel).read_text(encoding="utf-8"), text, "%s is stale" % rel)

    def test_project_maps_static_map_and_terrain(self):
        ws = json.loads(read("default.project.json"))["tree"]["Workspace"]
        self.assertEqual(ws["Map"]["$path"], "src/Workspace/Map")
        terrain = ws["Terrain"]
        self.assertEqual(terrain["$className"], "Terrain")
        self.assertIn("WaterColor", terrain["$properties"])

    def test_six_plot_islands(self):
        for i in range(1, 7):
            plot = self.data["Plots/Plot_%d.model.json" % i]
            self.assertEqual(plot["ClassName"], "Model")
            ground = child(plot, "Ground")
            self.assertEqual(ground["Attributes"]["PlotIndex"], i)
            exit_ = child(plot, "Exit")
            self.assertIsNotNone(exit_)
            self.assertIn(exit_["Attributes"]["ExitSide"], ("N", "E", "S", "W"))
            bridge = child(exit_, "Bridge")
            names = [c["Name"] for c in bridge["Children"]]
            for part in ("Deck", "Lane", "Rail", "Curb", "Post", "Pillar", "Lamp"):
                self.assertIn(part, names, "bridge %d lacks %s" % (i, part))
            self.assertIsNotNone(child(plot, "OwnerSign"))

    def test_big_central_island_and_distances(self):
        c = self.m["CentralIsland"]
        t = self.game["Territory"]
        self.assertGreaterEqual(c["Size"], 480, "central island must be big")
        island_half = t["Size"] / 2 + t["RimWidth"]
        old_gap = 300 - island_half - 180  # v0.2 layout: plot centre 300, central half 180
        for p in self.m["Plots"]:
            vx, vz = gen_static_map.SIDE[p["ExitSide"]]
            axis = p["CenterX"] if vx else p["CenterZ"]
            gap = abs(axis) - island_half - c["Size"] / 2
            self.assertGreaterEqual(gap, old_gap * 2.8, "plot %d gap %.0f" % (p["Index"], gap))
        plots = {p["Index"]: p for p in self.m["Plots"]}
        self.assertGreaterEqual(plots[2]["CenterX"] - plots[1]["CenterX"] - 2 * island_half, 200)

    def test_vegetation_rocks_and_paths(self):
        central = self.data["CentralIsland.model.json"]
        d = self.m["Decorations"]
        trees = child(central, "Trees")["Children"]
        bushes = child(central, "Bushes")["Children"]
        rocks = child(central, "Rocks")["Children"]
        paths = child(central, "Paths")["Children"]
        self.assertGreaterEqual(len(trees), d["Trees"] * 0.9)
        self.assertGreaterEqual(len(bushes), d["Bushes"] * 0.9)
        self.assertGreaterEqual(len(rocks), d["Rocks"] * 0.9)
        self.assertGreater(len([p for p in paths if p["Name"] == "Path"]), 6 * 8)
        for p in paths:
            self.assertEqual(p["Properties"]["Material"]["Enum"], gen_static_map.MAT["Ground"], "dirt paths")
            self.assertFalse(p["Properties"]["CanCollide"])
        self.assertIsNotNone(child(central, "LobbySpawn"))

    def test_invisible_boundaries_enclose_everything(self):
        b = self.data["Boundaries.model.json"]
        walls = b["Children"]
        self.assertEqual(sorted(w["Name"] for w in walls), ["East", "North", "South", "West"])
        for w in walls:
            self.assertEqual(w["Properties"]["Transparency"], 1)
            self.assertTrue(w["Properties"]["CanCollide"])
            self.assertFalse(w["Properties"]["CanQuery"])
        half = self.m["Boundary"]["HalfSize"]
        t = self.game["Territory"]
        island_half = t["Size"] / 2 + t["RimWidth"]
        for p in self.m["Plots"]:
            self.assertLess(abs(p["CenterX"]) + island_half + 40, half)
            self.assertLess(abs(p["CenterZ"]) + island_half + 40, half)
        self.assertGreater(self.m["Terrain"]["HalfSize"], half, "water continues beyond the walls")

    def test_part_encoding_matches_verified_rojo_format(self):
        for rel, node in self.data.items():
            for n in walk(node):
                if n.get("ClassName") != "Part":
                    continue
                props = n["Properties"]
                self.assertIn("Vector3", props["Size"], rel)
                self.assertIn("CFrame", props["CFrame"], rel)
                self.assertIn("Color3", props["Color"], rel)
                self.assertIn("Enum", props["Material"], rel)
                self.assertTrue(props["Anchored"], rel)
                o = props["CFrame"]["CFrame"]["orientation"]
                for row in o:
                    self.assertAlmostEqual(math.sqrt(sum(v * v for v in row)), 1, places=2)

    def test_world_service_does_not_generate_the_map(self):
        world = read("src/ServerScriptService/Systems/World/WorldService.luau")
        for gone in ("buildOcean", "buildCentralIsland", "buildPlot", "buildMap", "local function tree("):
            self.assertNotIn(gone, world)
        self.assertIn("FillBlock", world)
        self.assertIn("Enum.Material.Water", world)
        self.assertIn("validateStaticMap", world)
        self.assertIn("Players.PlayerAdded:Connect(hookCharacter)", world)


if __name__ == "__main__":
    unittest.main()

