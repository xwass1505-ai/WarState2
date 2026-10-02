"""v0.4 Phases 2-6: economy, resources, traffic, railway, city stats / city map.

Static checks against the real configs and Luau sources (Studio-only behaviour is covered by
RuntimeSelfTest and is reported as STUDIO PLAY TEST = N/A when Studio is not available)."""
import json
import math
import re
import unittest

from tests._common import ROOT, load_json, read

SRC = ROOT / "src"


def luau(rel):
    return read("src/" + rel)


class Phase2EconomyTests(unittest.TestCase):
    def setUp(self):
        self.game = load_json("GameConfig.json")
        self.buildings = {b["Id"]: b for b in load_json("BuildingConfig.json")["Buildings"]}

    def test_treasury_and_population_start_at_zero(self):
        empty = self.game["EmptyCountry"]
        self.assertEqual(empty["Treasury"], 0)
        self.assertEqual(empty["Population"], 0)
        self.assertEqual(self.game["Economy"]["StartingTreasury"], 0)
        self.assertNotIn("StarterGrant", self.game["Economy"], "no $2500 starter grant")
        for rel in ("ServerScriptService/Systems/Country/CountryService.luau",
                    "ServerScriptService/Systems/Data/DataService.luau",
                    "ReplicatedStorage/Shared/Modules/DefaultCountry.luau"):
            self.assertNotIn("StarterGrant", luau(rel), rel)
            self.assertNotIn("2500", luau(rel), rel)

    def test_cycle_is_30_seconds(self):
        self.assertEqual(self.game["Economy"]["CycleSeconds"], 30)
        econ = luau("ServerScriptService/Systems/Economy/EconomyService.luau")
        self.assertIn("GameConfig.Economy.CycleSeconds", econ)
        self.assertIn("NextCycleAt", econ)

    def test_every_building_has_cost_income_expense(self):
        for b in self.buildings.values():
            self.assertIn("Treasury", b["Cost"], b["Id"])
            self.assertIsInstance(b["IncomePerCycle"], int, b["Id"])
            self.assertIsInstance(b["ExpensePerCycle"], int, b["Id"])
            self.assertIn("PopulationRequired", b, b["Id"])

    def test_businesses_earn_houses_cost(self):
        for b in self.buildings.values():
            if b["Category"] == "Business":
                self.assertGreater(b["IncomePerCycle"], b["ExpensePerCycle"], b["Id"])
            else:
                self.assertEqual(b["IncomePerCycle"], 0, b["Id"])
                self.assertGreater(b["ExpensePerCycle"], 0, b["Id"])

    def test_no_progression_deadlock(self):
        house = self.buildings["SmallHouse"]
        self.assertEqual(house["PopulationRequired"], 0)
        self.assertEqual(house["Cost"]["Treasury"], 0, "first house buildable with Treasury 0")
        # a first income source and basic utilities must be reachable without money
        shop = self.buildings["Shop"]
        self.assertEqual(shop["Cost"]["Treasury"], 0)
        self.assertLessEqual(shop["PopulationRequired"], house["HousingCapacity"])
        for util in ("WaterTower", "WindGenerator"):
            self.assertEqual(self.buildings[util]["PopulationRequired"], 0, util)
            self.assertEqual(self.buildings[util]["Cost"]["Treasury"], 0, util)

    def test_economy_rules_income_minus_expenses(self):
        rules = luau("ReplicatedStorage/Shared/Modules/EconomyRules.luau")
        self.assertIn("IncomePerCycle", rules)
        self.assertIn("ExpensePerCycle", rules)
        self.assertIn("result.net = result.income - result.expense", rules)

    def test_server_checks_population_unlock_and_cost(self):
        svc = luau("ServerScriptService/Systems/Buildings/BuildingService.luau")
        self.assertIn("PopulationRequired", svc + luau("ReplicatedStorage/Shared/Modules/EconomyRules.luau"))
        self.assertIn("canAfford", svc)

    def test_build_menu_cards_and_accents(self):
        menu = load_json("BuildMenuConfig.json")
        accents = {c["Id"]: c["Accent"] for c in menu["Categories"]}
        r, g, b = accents["CIVILIAN"]
        self.assertGreater(g, r)  # green
        r, g, b = accents["MILITARY"]
        self.assertGreater(r, g)  # red
        r, g, b = accents["RESEARCH"]
        self.assertGreater(b, g)  # blue / purple
        ui = luau("StarterGui/MainUI/Screens/BuildMenu.luau")
        for word in ("Income", "Expense", "Water", "Power", "PopulationRequired"):
            self.assertIn(word, ui)

    def test_hud_fields(self):
        hud = luau("StarterGui/MainUI/Screens/HUD.luau")
        for field in ("flagHolder", "popLabel", "treasuryLabel", "techLabel", "cycleLabel", "NextCycleAt"):
            self.assertIn(field, hud)


class Phase3ResourceTests(unittest.TestCase):
    def setUp(self):
        self.buildings = {b["Id"]: b for b in load_json("BuildingConfig.json")["Buildings"]}

    def test_chains(self):
        out = lambda i: self.buildings[i]["Production"]["Outputs"]
        inp = lambda i: self.buildings[i]["Production"]["Inputs"]
        self.assertIn("Coal", out("CoalMine"))
        self.assertIn("IronOre", out("IronMine"))
        self.assertIn("Oil", out("OilWell"))
        self.assertIn("Oil", inp("OilRefinery"))
        self.assertIn("Fuel", out("OilRefinery"))
        self.assertEqual(set(inp("SteelMill")), {"Coal", "IronOre"})
        self.assertIn("Steel", out("SteelMill"))
        self.assertGreater(self.buildings["Warehouse"]["StorageCapacity"], 0)

    def test_uses_existing_services(self):
        prod = luau("ServerScriptService/Systems/Production/ProductionService.luau")
        self.assertIn("ProductionRules", prod)
        files = [p.name for p in (SRC / "ServerScriptService" / "Systems").rglob("*.luau")]
        self.assertEqual(files.count("ResourceService.luau"), 1)
        self.assertEqual(files.count("ProductionService.luau"), 1)


class Phase4TrafficTests(unittest.TestCase):
    def test_interval_and_formula(self):
        game = load_json("GameConfig.json")
        self.assertEqual(game["Traffic"]["IntervalSeconds"], 60)
        rules = luau("ReplicatedStorage/Shared/Modules/TrafficRules.luau")
        self.assertIn("math.ceil(houses / 2)", rules)
        for houses, cars in ((5, 3), (10, 5), (1, 1), (0, 0)):
            self.assertEqual(min(math.ceil(houses / 2), game["Traffic"]["MaxCarsPerWave"]), cars)

    def test_destinations_and_real_road_movement(self):
        buildings = {b["Id"]: b for b in load_json("BuildingConfig.json")["Buildings"]}
        for d in ("Shop", "GasStation", "Office"):
            self.assertTrue(buildings[d].get("TrafficDestination"), d)
        svc = luau("ServerScriptService/Systems/Vehicles/VehicleService.luau")
        self.assertIn("TweenService", svc)
        self.assertIn("planTrips", svc)
        self.assertNotIn("RenderStepped", svc)


class Phase5RailwayTests(unittest.TestCase):
    def test_server_rail(self):
        rail = luau("ServerScriptService/Systems/Railway/RailService.luau")
        self.assertIn("PlaceRailLine", rail)
        self.assertIn("getBounds(player)", rail, "server-side plot ownership")
        self.assertIn("canAfford", rail)
        game = load_json("GameConfig.json")
        for cargo in ("Coal", "IronOre", "Oil", "Steel"):
            self.assertIn(cargo, game["Railway"]["Cargo"])

    def test_client_rail_drag(self):
        pc = luau("StarterPlayer/StarterPlayerScripts/Controllers/PlacementController.luau")
        self.assertIn("Constants.Remotes.PlaceRailLine", pc)
        self.assertIn("validateRailLine", pc)
        menu = load_json("BuildMenuConfig.json")
        self.assertIn("Rail", [t["Kind"] for t in menu["DrawTools"]])


class Phase6StatsTests(unittest.TestCase):
    def test_sections(self):
        panel = luau("StarterGui/MainUI/Screens/StatsPanel.luau")
        for section in ("OVERVIEW", "BUILDINGS", "UTILITIES", "TRANSPORT", "RESOURCES", "CITY MAP"):
            self.assertIn('"' + section, panel)
        for overlay in ("WATER", "POWER", "BUILDINGS", "ROADS"):
            self.assertIn('"%s"' % overlay, panel)
        self.assertIn("WaterRadius", panel)
        self.assertIn("PowerRadius", panel)
        self.assertIn("fetchCityMap", luau("StarterPlayer/StarterPlayerScripts/ClientMain.client.luau"))

    def test_city_map_endpoint(self):
        stats = luau("ServerScriptService/Systems/Stats/StatsService.luau")
        self.assertIn("Remotes.GetCityMap", stats)
        for key in ("WaterStatus", "PowerStatus", "WaterRadius", "PowerRadius", "Roads", "Rails"):
            self.assertIn(key, stats)

    def test_remotes_declared(self):
        project = json.loads(read("default.project.json"))
        remotes = project["tree"]["ReplicatedStorage"]["Remotes"]
        for name in ("PlaceRailLine", "GetCityMap"):
            self.assertEqual(remotes[name]["$className"], "RemoteFunction")


class SaveLoadTests(unittest.TestCase):
    def test_new_state_is_saved_with_defaults(self):
        empty = load_json("GameConfig.json")["EmptyCountry"]
        for key in ("Treasury", "Population", "Buildings", "Roads", "Infrastructure", "Railway", "Economy",
                    "Coal", "IronOre", "Oil", "Fuel", "Steel"):
            self.assertIn(key, empty)
        default = luau("ReplicatedStorage/Shared/Modules/DefaultCountry.luau")
        self.assertIn("Railway", default)


if __name__ == "__main__":
    unittest.main()
