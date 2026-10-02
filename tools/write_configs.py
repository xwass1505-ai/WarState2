import json
C = "src/ReplicatedStorage/Shared/Config/"
def w(name, data):
    with open(C + name, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

w("GameConfig.json", {
  "SchemaVersion": 2,
  "DataStoreName": "WarState_Slots_v1",
  "DataStoreRetries": 3,
  "AutosaveSeconds": 60,
  "SlotCount": 3,
  "Slots": [
    {"Index": 1, "Unlocked": True, "Label": "FREE"},
    {"Index": 2, "Unlocked": False, "Label": "LOCKED"},
    {"Index": 3, "Unlocked": False, "Label": "LOCKED"}
  ],
  "CountryName": {"MinLength": 3, "MaxLength": 24},
  "Territory": {
    "Size": 128, "SurfaceY": 0, "Thickness": 4, "RimWidth": 14, "MaxPlots": 6,
    "BorderWidth": 0.4,
    "Color": [0.55, 0.74, 0.47], "BorderColor": [0.47, 0.66, 0.41], "SandColor": [0.93, 0.87, 0.72]
  },
  "Map": {
    "WaterSize": 1400, "WaterLevel": -0.6, "SeabedY": -9,
    "WaterColor": [0.55, 0.78, 0.93], "SeabedColor": [0.86, 0.8, 0.64],
    "CentralIsland": {"CenterX": 0, "CenterZ": 0, "Size": 360, "BeachWidth": 18, "Color": [0.58, 0.76, 0.5]},
    "BridgeWidth": 4, "BridgeColor": [0.62, 0.64, 0.67], "BridgeRailColor": [0.9, 0.92, 0.94],
    "Plots": [
      {"Index": 1, "CenterX": -140, "CenterZ": -300, "ExitSide": "S"},
      {"Index": 2, "CenterX": 140, "CenterZ": -300, "ExitSide": "S"},
      {"Index": 3, "CenterX": -300, "CenterZ": 0, "ExitSide": "E"},
      {"Index": 4, "CenterX": 300, "CenterZ": 0, "ExitSide": "W"},
      {"Index": 5, "CenterX": -140, "CenterZ": 300, "ExitSide": "N"},
      {"Index": 6, "CenterX": 140, "CenterZ": 300, "ExitSide": "N"}
    ],
    "Decorations": {"Trees": 18, "Rocks": 10, "Seed": 7},
    "LobbySpawn": [0, 1, 0]
  },
  "Population": {"TickSeconds": 4, "GrowthFraction": 0.15, "MinGrowth": 1, "WorkerRatio": 0.5},
  "Construction": {"PlannedSeconds": 2, "TickSeconds": 0.5, "GhostTransparency": 0.8, "ProgressBarMaxDistance": 140},
  "Utilities": {
    "TickSeconds": 5,
    "Shortage": {
      "ProlongedSeconds": 60, "ProblemsSeconds": 150, "DecreaseSeconds": 240,
      "DecreaseFraction": 0.05, "RecoveryMultiplier": 2
    }
  },
  "Economy": {"ChargeCosts": False, "Currency": "Treasury"},
  "Migration": {"V1PositionScale": 0.25},
  "EmptyCountry": {
    "Treasury": 0, "Oil": 0, "Fuel": 0, "Steel": 0, "Supplies": 0,
    "Population": 0, "Workers": 0, "HousingCapacity": 0,
    "Buildings": {}, "Roads": {}, "Military": {},
    "Infrastructure": {
      "Water": {"Stored": 0, "Production": 0, "Demand": 0},
      "Power": {"Production": 0, "Demand": 0},
      "Shortage": {"Stage": "NORMAL", "Seconds": 0}
    },
    "LastPlotIndex": 0
  }
})

w("PlacementConfig.json", {
  "GridSize": 1, "RoadTileSize": 2, "MaxRoadDistance": 3, "RequireRoadAccess": True,
  "OverlapTolerance": 0.02, "MaxPlacementRayDistance": 1500,
  "PreviewTransparency": 0.45, "PreviewValidColor": [110, 176, 240], "PreviewInvalidColor": [235, 96, 96],
  "RequestCooldown": 0.12, "MaxRoadDragTiles": 64
})

w("RoadConfig.json", {
  "TileSize": 2, "RoadWidth": 1.6, "CurbWidth": 0.2, "CurbHeight": 0.16, "AsphaltHeight": 0.08,
  "AutoConnect": True,
  "Colors": {"Asphalt": [124, 128, 134], "Curb": [212, 215, 219], "Marking": [242, 242, 238]},
  "Types": [
    {"Id": "Straight", "DisplayName": "Straight Road", "Openings": ["N", "S"], "Active": True, "Cost": {"Treasury": 0}}
  ]
})

w("BuildMenuConfig.json", {"Categories": [
  {"Id": "Roads", "DisplayName": "Roads", "Status": "IMPLEMENTED"},
  {"Id": "Residential", "DisplayName": "Residential", "Status": "IMPLEMENTED"},
  {"Id": "Business", "DisplayName": "Business", "Status": "IMPLEMENTED"},
  {"Id": "Industry", "DisplayName": "Industry", "Status": "IMPLEMENTED"},
  {"Id": "Infrastructure", "DisplayName": "Infrastructure", "Status": "IMPLEMENTED"},
  {"Id": "Military", "DisplayName": "Military", "Status": "PLANNED"},
  {"Id": "Services", "DisplayName": "Services", "Status": "PLANNED"},
  {"Id": "Agriculture", "DisplayName": "Agriculture", "Status": "PLANNED"},
  {"Id": "Resources", "DisplayName": "Resources", "Status": "PLANNED"},
  {"Id": "Other", "DisplayName": "Other", "Status": "PLANNED"}
]})

def b(id, name, short, cat, group, fp, bt, variants, housing=0, water=None, power=None, cost=0):
    d = {"Id": id, "DisplayName": name, "ShortName": short, "Category": cat, "StatsGroup": group,
         "Footprint": fp, "ModelScale": 0.25, "HousingCapacity": housing, "BuildTimeSeconds": bt,
         "Variants": [id + "_" + v for v in variants], "Active": True, "Cost": {"Treasury": cost}}
    d["Water"] = water or {"Required": 0}
    d["Power"] = power or {"Required": 0}
    return d
V = ["A", "B", "C", "D"]
w("BuildingConfig.json", {"Buildings": [
  b("SmallHouse", "Small House", "House", "Residential", "Houses", [2, 2], 12, V, 4, {"Required": 1}, {"Required": 1}, 0),
  b("MediumHouse", "Medium House", "House", "Residential", "Houses", [3, 2], 18, V, 8, {"Required": 2}, {"Required": 2}, 0),
  b("LargeHouse", "Large House", "House", "Residential", "Houses", [4, 3], 26, V, 14, {"Required": 3}, {"Required": 3}, 0),
  b("Shop", "Corner Shop", "Business", "Business", "Businesses", [2, 2], 14, V, 0, {"Required": 1}, {"Required": 2}, 0),
  b("Office", "Office", "Business", "Business", "Businesses", [3, 3], 22, V, 0, {"Required": 2}, {"Required": 4}, 0),
  b("Workshop", "Workshop", "Factory", "Industry", "Factories", [3, 2], 20, V, 0, {"Required": 2}, {"Required": 4}, 0),
  b("Factory", "Factory", "Factory", "Industry", "Factories", [4, 3], 30, V, 0, {"Required": 3}, {"Required": 8}, 0),
  b("WaterTower", "Water Tower", "Water Tower", "Infrastructure", "WaterTowers", [2, 2], 16, V, 0,
    {"Required": 0, "Production": 24, "Capacity": 120, "Radius": 20}, {"Required": 0}, 0),
  b("WindGenerator", "Wind Generator", "Wind Generator", "Infrastructure", "PowerSources", [2, 2], 16, V, 0,
    {"Required": 0}, {"Required": 0, "Production": 12, "Radius": 16, "Tier": "Small", "Upkeep": {"Fuel": 0}}, 0),
  b("Substation", "Substation", "Substation", "Infrastructure", "PowerSources", [3, 3], 32, V, 0,
    {"Required": 0}, {"Required": 0, "Production": 60, "Radius": 36, "Tier": "Advanced", "Upkeep": {"Fuel": 1}}, 0)
]})

w("TechnologyConfig.json", {
  "Branches": [
    {"Id": "USSR", "DisplayName": "USSR / Russia", "Description": "Soviet / Russian equipment line. Research tree planned.", "Active": True},
    {"Id": "USA", "DisplayName": "USA", "Description": "American equipment line. Research tree planned.", "Active": True},
    {"Id": "Germany", "DisplayName": "Germany", "Description": "German equipment line. Research tree planned.", "Active": True}
  ],
  "ResearchSystemStatus": "PLANNED"
})
