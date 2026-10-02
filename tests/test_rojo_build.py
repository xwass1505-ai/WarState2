"""Place-file tests.

* StructureTreeTests: mirror of the instance tree via tools/rojo_build.py (structure only, runs anywhere).
* RealRojoBuildTests: inspects the place produced by the REAL `rojo build` (Rojo 7.7.0) in CI
  (env WARSTATE_ROJO_BUILD=build/WarState.rbxlx). This is the only build that counts as a Rojo PASS.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from tests import luau_parser
from tests._common import ROOT

sys.path.insert(0, str(ROOT / "tools"))
import rojo_build  # noqa: E402

REAL_BUILD = os.environ.get("WARSTATE_ROJO_BUILD")


def name_of(item):
    props = item.find("Properties")
    if props is None:
        return None
    for s in props:
        if s.get("name") == "Name":
            return s.text
    return None


class StructureTreeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp())
        cls.out = cls.tmp / "structure.rbxlx"
        cls.info = rojo_build.build_place(ROOT / "default.project.json", cls.out)
        cls.xml = ET.parse(cls.out).getroot()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def items(self, cls_name):
        return [i for i in self.xml.iter("Item") if i.get("class") == cls_name]

    def test_place_tree_has_scripts(self):
        self.assertEqual(len(self.items("Script")), 2)  # ServerMain + RuntimeSelfTest
        self.assertEqual(len(self.items("LocalScript")), 1)  # ClientMain
        self.assertGreater(len(self.items("ModuleScript")), 40)

    def test_remotes_built(self):
        names = {name_of(i) for i in self.items("RemoteFunction")}
        for n in ("CreateCountry", "ClaimPlot", "GetPlots", "PlaceRoadLine", "PlaceBuilding", "Demolish"):
            self.assertIn(n, names)
        events = {name_of(i) for i in self.items("RemoteEvent")}
        self.assertTrue({"StateChanged", "PlotsChanged", "Notify"} <= events)

    def test_main_ui_properties(self):
        gui = self.items("ScreenGui")[0]
        bools = {b.get("name"): b.text for b in gui.find("Properties").findall("bool")}
        self.assertEqual(bools.get("ResetOnSpawn"), "false")

    def test_json_modules_are_valid_luau(self):
        root = self.info["root"]
        for node in root.walk():
            if node.class_name in ("ModuleScript", "Script", "LocalScript") and node.source is not None:
                self.assertEqual(luau_parser.parse_luau(node.source), [], node.name)

    def test_expected_paths(self):
        paths = set(rojo_build.instance_paths(self.info["root"]))
        for p in (
            "ReplicatedStorage/Shared/Config/GameConfig",
            "ReplicatedStorage/Shared/Modules/UtilityGrid",
            "ServerScriptService/Systems/Water/WaterService",
            "ServerScriptService/Systems/Power/PowerService",
            "StarterGui/MainUI/Screens/StatsPanel",
            "StarterGui/MainUI/Screens/PlotScreen",
            "StarterPlayer/StarterPlayerScripts/Controllers/ConstructionBars",
            "Workspace/Map",
            "Workspace/Map/CentralIsland",
            "Workspace/Map/Boundaries",
            "Workspace/Map/Plots/Plot_1/Exit/Bridge",
        ):
            self.assertIn(p, paths)


@unittest.skipUnless(REAL_BUILD and Path(REAL_BUILD).is_file(), "real rojo build file not provided (CI sets WARSTATE_ROJO_BUILD)")
class RealRojoBuildTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = ET.parse(REAL_BUILD).getroot()
        cls.paths = {}

        def collect(item, prefix):
            path = (prefix + "/" if prefix else "") + (name_of(item) or "?")
            cls.paths[path] = item
            for c in item.findall("Item"):
                collect(c, path)

        for item in cls.root.findall("Item"):
            collect(item, "")

    def count(self, cls_name):
        return sum(1 for i in self.root.iter("Item") if i.get("class") == cls_name)

    def test_static_map_is_in_the_place(self):
        for p in ("Workspace/Map/CentralIsland/Ground", "Workspace/Map/CentralIsland/Trees", "Workspace/Map/CentralIsland/Paths",
                  "Workspace/Map/Boundaries/North", "Workspace/Map/CentralIsland/LobbySpawn"):
            self.assertIn(p, self.paths)
        for i in range(1, 7):
            self.assertIn("Workspace/Map/Plots/Plot_%d/Ground" % i, self.paths)
            self.assertIn("Workspace/Map/Plots/Plot_%d/Exit/Bridge" % i, self.paths)
        self.assertGreater(self.count("Part"), 800, "static map parts serialized by real Rojo")

    def test_part_properties_serialized(self):
        ground = self.paths["Workspace/Map/Plots/Plot_1/Ground"]
        props = {p.get("name"): p for p in ground.find("Properties")}
        self.assertIn("CFrame", props)
        self.assertEqual(props["Anchored"].text, "true")
        size = props.get("size") or props.get("Size")
        self.assertIsNotNone(size)
        self.assertEqual(size.find("X").text, "128")

    def test_terrain_water_properties(self):
        terrain = self.paths["Workspace/Terrain"]
        names = {p.get("name") for p in terrain.find("Properties")}
        self.assertIn("WaterColor", names)

    def test_scripts_and_remotes(self):
        self.assertEqual(self.count("Script"), 2)
        self.assertEqual(self.count("LocalScript"), 1)
        self.assertIn("ReplicatedStorage/Remotes/ClaimPlot", self.paths)

    @unittest.skipUnless(shutil.which("rojo"), "rojo binary not installed")
    def test_real_rojo_build_again(self):
        out = Path(tempfile.mkdtemp()) / "rojo.rbxlx"
        result = subprocess.run(["rojo", "build", str(ROOT / "default.project.json"), "-o", str(out)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
