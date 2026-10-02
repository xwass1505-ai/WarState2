"""Config-level gameplay checks (Python mirrors of the Luau geometry in Plots / PlacementRules)."""
import math
import unittest

from tests._common import load_json

SIDE = {"N": (0, -1), "E": (1, 0), "S": (0, 1), "W": (-1, 0)}


def rect(cx, cz, w, d):
    return (cx - w / 2, cx + w / 2, cz - d / 2, cz + d / 2)


def overlap(a, b):
    return a[0] < b[1] and a[1] > b[0] and a[2] < b[3] and a[3] > b[2]


class MapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.game = load_json("GameConfig.json")
        cls.placement = load_json("PlacementConfig.json")
        cls.map = cls.game["Map"]
        cls.t = cls.game["Territory"]
        c = cls.map["CentralIsland"]
        cls.central = rect(c["CenterX"], c["CenterZ"], c["Size"], c["Size"])
        island = cls.t["Size"] + 2 * cls.t["RimWidth"]
        cls.islands = {p["Index"]: rect(p["CenterX"], p["CenterZ"], island, island) for p in cls.map["Plots"]}

    def test_islands_do_not_overlap(self):
        ids = sorted(self.islands)
        for i in ids:
            self.assertFalse(overlap(self.islands[i], self.central), "plot %d overlaps central island" % i)
            for j in ids:
                if j > i:
                    self.assertFalse(overlap(self.islands[i], self.islands[j]), "%d/%d" % (i, j))

    def test_layout_around_central_island(self):
        plots = {p["Index"]: p for p in self.map["Plots"]}
        # P1 P2 on top, P3 left, P4 right, P5 P6 bottom
        self.assertLess(plots[1]["CenterZ"], 0)
        self.assertLess(plots[2]["CenterZ"], 0)
        self.assertLess(plots[1]["CenterX"], plots[2]["CenterX"])
        self.assertLess(plots[3]["CenterX"], 0)
        self.assertGreater(plots[4]["CenterX"], 0)
        self.assertGreater(plots[5]["CenterZ"], 0)
        self.assertGreater(plots[6]["CenterZ"], 0)

    def test_exit_faces_center_and_bridge_lands_on_central_island(self):
        c = self.map["CentralIsland"]
        half = c["Size"] / 2
        for p in self.map["Plots"]:
            vx, vz = SIDE[p["ExitSide"]]
            to_center = (c["CenterX"] - p["CenterX"], c["CenterZ"] - p["CenterZ"])
            self.assertGreater(vx * to_center[0] + vz * to_center[1], 0, "exit of plot %d must face the center" % p["Index"])
            # Bridge runs straight along the exit axis: the perpendicular coordinate must hit the island.
            perpendicular = p["CenterX"] if vx == 0 else p["CenterZ"]
            center_perp = c["CenterX"] if vx == 0 else c["CenterZ"]
            self.assertLess(abs(perpendicular - center_perp), half - self.map["BridgeWidth"], p["Index"])
            # Gap between island edge and central beach must be water (a real bridge, not overlap)
            island_edge = (p["CenterX"] if vx else p["CenterZ"]) + (vx or vz) * (self.t["Size"] / 2 + self.t["RimWidth"])
            central_edge = (c["CenterX"] if vx else c["CenterZ"]) - (vx or vz) * half
            self.assertGreater((central_edge - island_edge) * (vx or vz), 0)

    def test_plot_grid(self):
        self.assertEqual(self.t["Size"] % self.placement["RoadTileSize"], 0)
        self.assertEqual(self.t["Size"] % self.placement["GridSize"], 0)

    def test_v1_saves_fit_into_new_plot(self):
        old_size = 480  # schema 1 territory
        self.assertLessEqual(old_size * self.game["Migration"]["V1PositionScale"], self.t["Size"])
        # old grid 4 -> new grid 1, old road tile 8 -> new 2 (same cell indices)
        self.assertEqual(8 * self.game["Migration"]["V1PositionScale"], self.placement["RoadTileSize"])


class UtilityBalanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.buildings = {b["Id"]: b for b in load_json("BuildingConfig.json")["Buildings"]}
        cls.placement = load_json("PlacementConfig.json")

    def test_water_tower_can_serve_a_small_district(self):
        tower = self.buildings["WaterTower"]["Water"]
        house = self.buildings["SmallHouse"]["Water"]["Required"]
        self.assertGreaterEqual(tower["Production"] // house, 8)
        area_houses = math.pi * tower["Radius"] ** 2 / (2 * 2 * 3)  # rough density incl. roads
        self.assertGreater(area_houses, 8)

    def test_radius_reaches_beyond_road_access(self):
        for sid in ("WaterTower", "WindGenerator", "Substation"):
            spec = self.buildings[sid]["Water"] if sid == "WaterTower" else self.buildings[sid]["Power"]
            self.assertGreater(spec["Radius"], self.placement["MaxRoadDistance"] * 2, sid)

    def test_road_is_grey_everywhere(self):
        road = load_json("RoadConfig.json")["Types"][0]
        self.assertNotIn("Water", road)
        self.assertNotIn("Power", road)


if __name__ == "__main__":
    unittest.main()

