import re
import unittest

from tests._common import load_json, read


class GameConfigTests(unittest.TestCase):
    def setUp(self):
        self.game = load_json("GameConfig.json")

    def test_exactly_three_slots(self):
        slots = self.game["Slots"]
        self.assertEqual(self.game["SlotCount"], 3)
        self.assertEqual(len(slots), 3)
        self.assertEqual([s["Unlocked"] for s in slots], [True, False, False])
        self.assertEqual([s["Label"] for s in slots], ["FREE", "LOCKED", "LOCKED"])

    def test_empty_country_defaults(self):
        empty = self.game["EmptyCountry"]
        for key in ("Treasury", "Oil", "Fuel", "Steel", "Supplies", "Population", "Workers", "HousingCapacity"):
            self.assertEqual(empty[key], 0, key)
        for key in ("Buildings", "Roads", "Military"):
            self.assertEqual(empty[key], {}, key)
        self.assertNotIn("Money", empty, "Money was renamed to Treasury (migrated)")
        infra = empty["Infrastructure"]
        self.assertEqual(infra["Water"]["Stored"], 0)
        self.assertEqual(infra["Shortage"]["Stage"], "NORMAL")

    def test_no_granted_resources(self):
        def walk(value):
            if isinstance(value, dict):
                for v in value.values():
                    yield from walk(v)
            elif isinstance(value, (int, float)) and not isinstance(value, bool):
                yield value
        self.assertTrue(all(v == 0 for v in walk(self.game["EmptyCountry"])))

    def test_schema_and_datastore_kept(self):
        self.assertGreaterEqual(self.game["SchemaVersion"], 2)
        self.assertEqual(self.game["DataStoreName"], "WarState_Slots_v1", "keep the store so old saves load")

    def test_six_plots(self):
        plots = self.game["Map"]["Plots"]
        self.assertEqual([p["Index"] for p in plots], [1, 2, 3, 4, 5, 6])
        self.assertEqual(self.game["Territory"]["MaxPlots"], 6)
        for p in plots:
            self.assertIn(p["ExitSide"], ("N", "E", "S", "W"))


class BuildingConfigTests(unittest.TestCase):
    def setUp(self):
        self.buildings = load_json("BuildingConfig.json")["Buildings"]
        self.placement = load_json("PlacementConfig.json")
        self.models = read("src/ReplicatedStorage/Shared/Modules/BuildingModels.luau")
        self.extra_models = read("src/ReplicatedStorage/Shared/Modules/ExtraModels.luau")

    def test_residential_types(self):
        ids = [b["Id"] for b in self.buildings if b["Category"] == "Residential"]
        self.assertEqual(ids[:3], ["SmallHouse", "MediumHouse", "LargeHouse"])
        self.assertIn("Apartment", ids)

    def test_categories_exist_in_menu(self):
        menu = {c["Id"]: c for c in load_json("BuildMenuConfig.json")["Categories"]}
        for b in self.buildings:
            self.assertIn(b["MenuCategory"], menu, b["Id"])
            self.assertIn(b["Category"], menu[b["MenuCategory"]]["Groups"], b["Id"])

    def test_building_fields(self):
        grid = self.placement["GridSize"]
        for b in self.buildings:
            self.assertGreater(b["BuildTimeSeconds"], 0)
            self.assertEqual(len(b["Footprint"]), 2)
            for side in b["Footprint"]:
                self.assertEqual(side % grid, 0, b["Id"])
            self.assertIn("Water", b)
            self.assertIn("Power", b)
            self.assertIn("Cost", b)
            if b["Category"] == "Residential":
                self.assertGreater(b["HousingCapacity"], 0)

    def test_buildings_are_small(self):
        # Base buildings ~2 studs; larger ones slightly bigger, never giant.
        by_id = {b["Id"]: b for b in self.buildings}
        self.assertEqual(by_id["SmallHouse"]["Footprint"], [2, 2])
        for b in self.buildings:
            self.assertLessEqual(max(b["Footprint"]), 4, b["Id"])
            self.assertLessEqual(b["ModelScale"], 0.25, b["Id"])

    def test_variants_exist_in_models(self):
        defined = set(re.findall(r"^Variants\.(\w+) = function", self.models, re.M))
        defined |= set(re.findall(r"^Variants\.(\w+) = function", self.extra_models, re.M))
        for b in self.buildings:
            self.assertGreaterEqual(len(b["Variants"]), 4, b["Id"])
            for v in b["Variants"]:
                self.assertIn(v, defined)

    def test_no_permanent_labels_on_buildings(self):
        self.assertNotIn("BillboardGui", self.models)

    def test_water_and_power_sources(self):
        by_id = {b["Id"]: b for b in self.buildings}
        tower = by_id["WaterTower"]["Water"]
        for key in ("Production", "Capacity", "Radius"):
            self.assertGreater(tower[key], 0, key)
        wind = by_id["WindGenerator"]["Power"]
        sub = by_id["Substation"]["Power"]
        self.assertLess(wind["Production"], sub["Production"])
        self.assertLess(wind["Radius"], sub["Radius"])
        self.assertLessEqual(by_id["WindGenerator"]["Cost"]["Treasury"], by_id["Substation"]["Cost"]["Treasury"])
        self.assertLessEqual(sum(wind["Upkeep"].values()), sum(sub["Upkeep"].values()))
        consumers = [b for b in self.buildings if b["Category"] in ("Residential", "Business", "Industry")]
        for b in consumers:
            self.assertGreater(b["Water"]["Required"], 0, b["Id"])
            self.assertGreater(b["Power"]["Required"], 0, b["Id"])


class RoadAndPlacementTests(unittest.TestCase):
    def setUp(self):
        self.roads = load_json("RoadConfig.json")
        self.placement = load_json("PlacementConfig.json")

    def test_single_road_type(self):
        ids = [t["Id"] for t in self.roads["Types"]]
        self.assertEqual(ids, ["Straight"])
        self.assertEqual(self.roads["Types"][0]["Openings"], ["N", "S"])
        self.assertTrue(self.roads["AutoConnect"])

    def test_road_tile_matches_grid(self):
        self.assertEqual(self.roads["TileSize"], self.placement["RoadTileSize"])
        self.assertEqual(self.placement["RoadTileSize"] % self.placement["GridSize"], 0)
        self.assertLess(self.roads["RoadWidth"], self.roads["TileSize"])
        self.assertLessEqual(self.roads["TileSize"], 2, "roads must be small")
        self.assertGreater(self.roads["CurbWidth"], 0)
        self.assertGreater(self.roads["CurbHeight"], 0)

    def test_placement_config(self):
        self.assertGreater(self.placement["MaxRoadDistance"], 0)
        self.assertTrue(self.placement["RequireRoadAccess"])
        self.assertGreater(self.placement["MaxRoadDragTiles"], 1)
        game = load_json("GameConfig.json")
        self.assertEqual(game["Territory"]["Size"] % self.placement["RoadTileSize"], 0)


class MenuAndTechTests(unittest.TestCase):
    def test_build_menu_categories(self):
        # Only three main categories; everything peaceful is CIVILIAN.
        cats = [c["Id"] for c in load_json("BuildMenuConfig.json")["Categories"]]
        self.assertEqual(cats, ["CIVILIAN", "MILITARY", "RESEARCH"])
        for forbidden in ("Business", "Industry", "Infrastructure", "Transport", "Utilities"):
            self.assertNotIn(forbidden, cats)

    def test_technology_branches(self):
        branches = load_json("TechnologyConfig.json")["Branches"]
        self.assertEqual([b["DisplayName"] for b in branches], ["USSR / Russia", "USA", "Germany"])


if __name__ == "__main__":
    unittest.main()

