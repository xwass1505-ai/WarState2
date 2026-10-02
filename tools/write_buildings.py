#!/usr/bin/env python3
"""Writes src/ReplicatedStorage/Shared/Config/BuildingConfig.json and BuildMenuConfig.json (v0.4).

    python tools/write_buildings.py          # write
    python tools/write_buildings.py --check  # exit 1 when the committed files differ

All balance numbers (cost, income, expense, population unlocks, production, utilities) live HERE.
Main build-menu categories are ONLY: CIVILIAN, MILITARY, RESEARCH (groups are sub-tabs).
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "src" / "ReplicatedStorage" / "Shared" / "Config"
V = ["A", "B", "C", "D"]

MENU = {
    "Categories": [
        {"Id": "CIVILIAN", "DisplayName": "Civilian", "Accent": [72, 178, 112],
         "Groups": ["Roads", "Residential", "Business", "Utilities", "Resources", "Industry", "Storage", "Transport"]},
        {"Id": "MILITARY", "DisplayName": "Military", "Accent": [222, 92, 92],
         "Groups": ["Production", "Army", "Defense", "Air", "Logistics"]},
        {"Id": "RESEARCH", "DisplayName": "Research", "Accent": [128, 104, 226],
         "Groups": ["Research"]},
    ],
    "Groups": {
        "Roads": "Roads", "Residential": "Houses", "Business": "Business", "Utilities": "Water & Power",
        "Resources": "Resources", "Industry": "Industry", "Storage": "Storage", "Transport": "Railway",
        "Production": "Production", "Army": "Army", "Defense": "Air Defense", "Air": "Air", "Logistics": "Storage",
        "Research": "Research",
    },
    "DrawTools": [
        {"Kind": "Road", "Id": "Straight", "Group": "Roads"},
        {"Kind": "Rail", "Id": "RailTrack", "Group": "Transport"},
    ],
}


def b(id, name, short, menu, cat, group, fp, bt, cost, pop, income=0, expense=0, housing=0,
      water=0, power=0, **extra):
    d = {
        "Id": id, "DisplayName": name, "ShortName": short, "MenuCategory": menu, "Category": cat,
        "StatsGroup": group, "Footprint": fp, "ModelScale": 0.25, "HousingCapacity": housing,
        "BuildTimeSeconds": bt, "Variants": [id + "_" + v for v in V], "Active": True,
        "PopulationRequired": pop, "Cost": cost if isinstance(cost, dict) else {"Treasury": cost},
        "IncomePerCycle": income, "ExpensePerCycle": expense,
        "Water": {"Required": water}, "Power": {"Required": power},
    }
    for k, v in extra.items():
        if k in ("WaterSpec", "PowerSpec"):
            d[k[:-4]].update(v)
        else:
            d[k] = v
    return d


C, M, R = "CIVILIAN", "MILITARY", "RESEARCH"
BUILDINGS = [
    # CIVILIAN / Residential (expenses only)
    b("SmallHouse", "Small House", "House", C, "Residential", "Houses", [2, 2], 12, 0, 0, expense=1, housing=4, water=1, power=1),
    b("MediumHouse", "Medium House", "House", C, "Residential", "Houses", [3, 2], 18, 150, 16, expense=2, housing=8, water=2, power=2),
    b("LargeHouse", "Large House", "House", C, "Residential", "Houses", [4, 3], 26, 380, 40, expense=4, housing=14, water=3, power=3),
    b("Apartment", "Apartments", "Apartments", C, "Residential", "Houses", [3, 3], 34, 900, 80, expense=7, housing=32, water=5, power=5),
    # CIVILIAN / Business (income; Customers = population needed to run at full income)
    b("Shop", "Corner Shop", "Shop", C, "Business", "Businesses", [2, 2], 14, 0, 4, income=10, expense=1, water=1, power=2,
      Customers=4, TrafficDestination=True),
    b("GasStation", "Gas Station", "Gas Station", C, "Business", "Businesses", [3, 2], 18, 220, 20, income=16, expense=2, water=1, power=2,
      Customers=8, TrafficDestination=True, FuelSale={"Fuel": 1, "Income": 8}),
    b("Office", "Office", "Office", C, "Business", "Businesses", [3, 3], 22, 520, 50, income=36, expense=4, water=2, power=4,
      Customers=16, TrafficDestination=True),
    # CIVILIAN / Utilities
    b("WaterTower", "Water Tower", "Water Tower", C, "Utilities", "Infrastructure", [2, 2], 16, 0, 0, expense=2,
      WaterSpec={"Production": 24, "Capacity": 120, "Radius": 20, "Tier": "Basic"}),
    b("WindGenerator", "Wind Generator", "Wind Generator", C, "Utilities", "Infrastructure", [2, 2], 16, 0, 0, expense=1,
      PowerSpec={"Production": 12, "Radius": 16, "Tier": "Small", "Upkeep": {"Fuel": 0}}),
    b("Substation", "Substation", "Substation", C, "Utilities", "Infrastructure", [3, 3], 32, {"Treasury": 600, "Steel": 10}, 30, expense=6,
      PowerSpec={"Production": 60, "Radius": 36, "Tier": "Advanced", "Upkeep": {"Fuel": 1}}),
    # CIVILIAN / Resources (raw production per cycle)
    b("CoalMine", "Coal Mine", "Coal Mine", C, "Resources", "Industry", [3, 3], 24, 160, 12, expense=3, water=1, power=2,
      Production={"Inputs": {}, "Outputs": {"Coal": 4}}),
    b("IronMine", "Iron Mine", "Iron Mine", C, "Resources", "Industry", [3, 3], 24, 200, 16, expense=3, water=1, power=2,
      Production={"Inputs": {}, "Outputs": {"IronOre": 4}}),
    b("OilWell", "Oil Well", "Oil Well", C, "Resources", "Industry", [2, 2], 20, 300, 24, expense=4, water=1, power=3,
      Production={"Inputs": {}, "Outputs": {"Oil": 3}}),
    # CIVILIAN / Industry (processing chains)
    b("OilRefinery", "Oil Refinery", "Refinery", C, "Industry", "Industry", [4, 3], 30, 600, 36, expense=6, water=2, power=6,
      Production={"Inputs": {"Oil": 2}, "Outputs": {"Fuel": 2}}),
    b("SteelMill", "Steel Factory", "Steel Factory", C, "Industry", "Industry", [4, 3], 30, 650, 40, expense=6, water=3, power=8,
      Production={"Inputs": {"Coal": 2, "IronOre": 2}, "Outputs": {"Steel": 1}}),
    b("Workshop", "Workshop", "Workshop", C, "Industry", "Industry", [3, 2], 20, 260, 30, expense=3, water=2, power=4,
      Production={"Inputs": {"Steel": 1}, "Outputs": {"Supplies": 2}}),
    b("Factory", "Factory", "Factory", C, "Industry", "Industry", [4, 3], 30, 900, 60, expense=7, water=3, power=8,
      Production={"Inputs": {"Steel": 2, "Fuel": 1}, "Outputs": {"Supplies": 5}}),
    # CIVILIAN / Storage + Transport
    b("Warehouse", "Warehouse", "Warehouse", C, "Storage", "Infrastructure", [3, 2], 16, 140, 10, expense=1, water=0, power=1,
      StorageCapacity=200),
    b("RailwayStation", "Railway Station", "Station", C, "Transport", "Infrastructure", [3, 2], 22, 350, 30, expense=3, water=1, power=2,
      RailStation=True),
    # MILITARY (foundation: real placement, cost, upkeep; unit production is planned)
    b("MilitaryFactory", "Military Factory", "Military Factory", M, "Production", "Military", [4, 3], 34, {"Treasury": 1200, "Steel": 20}, 90,
      expense=12, water=3, power=8, Upkeep={"Supplies": 1}),
    b("VehicleFactory", "Vehicle Factory", "Vehicle Factory", M, "Production", "Military", [4, 3], 36, {"Treasury": 1500, "Steel": 30}, 110,
      expense=14, water=3, power=8, Upkeep={"Supplies": 1}),
    b("TankFactory", "Tank Factory", "Tank Factory", M, "Production", "Military", [4, 4], 40, {"Treasury": 2200, "Steel": 50}, 150,
      expense=18, water=3, power=10, Upkeep={"Supplies": 2}),
    b("Barracks", "Barracks", "Barracks", M, "Army", "Military", [3, 3], 26, 700, 70, expense=8, water=2, power=3, Upkeep={"Supplies": 1}),
    b("ArtilleryBase", "Artillery Base", "Artillery", M, "Army", "Military", [3, 3], 28, {"Treasury": 950, "Steel": 15}, 100,
      expense=9, water=1, power=3, Upkeep={"Supplies": 1}),
    b("AirDefense", "Air Defense", "Air Defense", M, "Defense", "Military", [2, 2], 24, {"Treasury": 700, "Steel": 10}, 90,
      expense=7, water=1, power=4),
    b("SAMSite", "SAM Site", "SAM Site", M, "Defense", "Military", [3, 3], 30, {"Treasury": 1700, "Steel": 25}, 150,
      expense=14, water=1, power=6),
    b("MissileFacility", "Missile Facility", "Missiles", M, "Defense", "Military", [4, 3], 38, {"Treasury": 2600, "Steel": 40}, 190,
      expense=20, water=2, power=10, Upkeep={"Fuel": 1}),
    b("UAVFacility", "UAV Facility", "UAV Facility", M, "Air", "Military", [3, 3], 30, {"Treasury": 1400, "Steel": 20}, 130,
      expense=12, water=1, power=6, Upkeep={"Fuel": 1}),
    b("AirBase", "Air Base", "Air Base", M, "Air", "Military", [4, 4], 42, {"Treasury": 3000, "Steel": 60}, 220,
      expense=24, water=3, power=10, Upkeep={"Fuel": 2}),
    b("MilitaryWarehouse", "Military Warehouse", "Mil. Warehouse", M, "Logistics", "Military", [3, 2], 20, 500, 70,
      expense=4, water=0, power=1, StorageCapacity=150),
    # RESEARCH (research points per cycle)
    b("ResearchCenter", "Research Center", "Research Center", R, "Research", "Research", [3, 3], 26, 450, 30, expense=4, water=2, power=4,
      ResearchPerCycle=2),
    b("TechnologyLab", "Technology Laboratory", "Tech Lab", R, "Research", "Research", [3, 2], 26, 750, 50, expense=6, water=2, power=5,
      ResearchPerCycle=4),
    b("EngineeringInstitute", "Engineering Institute", "Engineering", R, "Research", "Research", [3, 3], 30, 950, 70, expense=7, water=2, power=5,
      ResearchPerCycle=5),
    b("MilitaryResearch", "Military Research", "Military Research", R, "Research", "Research", [3, 3], 30, 1200, 90, expense=8, water=2, power=6,
      ResearchPerCycle=6),
    b("ElectronicsLab", "Radar & Electronics Lab", "Electronics Lab", R, "Research", "Research", [3, 2], 30, 1300, 110, expense=8, water=1, power=7,
      ResearchPerCycle=6),
    b("VehicleResearch", "Vehicle Research", "Vehicle Research", R, "Research", "Research", [4, 3], 34, 1400, 120, expense=9, water=2, power=7,
      ResearchPerCycle=7),
    b("AircraftResearch", "Aircraft Research", "Aircraft Research", R, "Research", "Research", [4, 3], 36, 1700, 150, expense=10, water=2, power=8,
      ResearchPerCycle=8),
]


def dump_buildings():
    lines = ['{', '  "Buildings": [']
    for i, d in enumerate(BUILDINGS):
        lines.append("    " + json.dumps(d, ensure_ascii=False) + ("," if i < len(BUILDINGS) - 1 else ""))
    lines += ['  ]', '}', '']
    return "\n".join(lines)


def dump_menu():
    return json.dumps(MENU, ensure_ascii=False, indent=2) + "\n"


def main():
    files = {CONFIG / "BuildingConfig.json": dump_buildings(), CONFIG / "BuildMenuConfig.json": dump_menu()}
    if "--check" in sys.argv:
        bad = [p.name for p, text in files.items() if not p.is_file() or p.read_text(encoding="utf-8") != text]
        if bad:
            print("OUT OF DATE: " + ", ".join(bad))
            return 1
        print("building configs up to date")
        return 0
    for p, text in files.items():
        p.write_text(text, encoding="utf-8")
        print("wrote " + str(p.relative_to(ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
