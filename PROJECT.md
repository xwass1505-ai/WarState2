# WAR STATE - PROJECT.md (LIVE)

**Version 0.4.0 · branch `wip/v0.4` · Rojo 7.7.0 (real `rojo build` in GitHub Actions) · save schema 3.**
Status columns: **Code** = implemented in source and covered by automated tests in CI.
**Studio** = verified in Roblox Studio Play. Studio is not available in the CI / AI build environment,
so every v0.4 item is **N/A** until it is checked in Studio (`RuntimeSelfTest` prints the result).

## Build pipeline (source of truth = GitHub)
```
GitHub push -> GitHub Actions (.github/workflows/build.yml, windows-latest)
  -> unpack rojo-7.7.0-windows-x86_64.zip (committed) + prebuild: tools/gen_static_map.py (static map sources)
  -> rojo --version (must be 7.7.0)
  -> rojo build default.project.json -o build/WarState.rbxlx      (REAL Rojo, fresh every run)
  -> tools/verify_build.py (fresh file, required instances: static map, remotes, v0.4 systems/screens)
  -> python -m unittest discover -s tests -t .  (incl. real-build XML checks via WARSTATE_ROJO_BUILD)
  -> tools/make_release_zip.py -> WarState_READY_BUILD.zip -> uploaded as workflow artifact
```
`tools/rojo_build.py` is only a structure mirror for unit tests and is **never** reported as a Rojo build.
Build outputs, ZIPs and the generated map are not committed (`.gitignore`). The release ZIP excludes every
`*.zip` (no old WIP / nested ZIPs, no Rojo archive), `__pycache__`, `*.rbxlx.lock`, `ci_logs/`.
Local: `python build_war_state.py` (generates the map, runs tests, runs the real `rojo build`).

## Game flow
MAIN MENU (WAR STATE + 3 slots) -> CREATE COUNTRY (Name -> Continent -> Flag (195) -> Technology -> Review)
-> PLOT SELECTION (6 plots, occupied ones disabled) -> spawn on the claimed plot. No plot is ever auto-assigned.
Owner sign: PLAYER NAME / FLAG / COUNTRY NAME (no technology branch).

## Feature status
| Feature | Code | Studio | Notes |
|---|---|---|---|
| 195 countries, flags, 6 continents, technology branches, 3 slots | IMPLEMENTED | VERIFIED (v0.2) | unchanged |
| Plot selection, server claim, ownership, owner sign | IMPLEMENTED | VERIFIED (v0.2) | sign on static `OwnerSign` |
| **Phase 1** static map (central island 520, 6 islands, boundaries, trees/bushes/rocks/paths, bridges, exits) | IMPLEMENTED | N/A | no PlayerAdded generation; terrain water filled once at server start |
| **Phase 2** Build Menu: wide bottom sheet, vertical categories CIVILIAN / MILITARY / RESEARCH only | IMPLEMENTED | N/A | accents green / red / purple; groups inside categories |
| Phase 2 building cards (preview, name, cost, income, expense, population, water, power, locked state) | IMPLEMENTED | N/A | `BuildMenu.luau` |
| Phase 2 HUD (flag, country, population, Treasury, technology, cycle, next-cycle timer) | IMPLEMENTED | N/A | timer from ReplicatedStorage `EconomyNextCycleAt` |
| Phase 2 economy: Treasury 0, population 0, 30 s cycles, Income - Expenses = Net | IMPLEMENTED | N/A | `EconomyService` + `EconomyRules` (server only) |
| Phase 2 population unlocks, no deadlock (Small House, Shop, Water Tower, Wind Generator free at pop 0-4) | IMPLEMENTED | N/A | checked server side on placement |
| **Phase 3** Coal Mine, Iron Mine, Oil Well, Refinery (Oil -> Fuel), Steel Factory (Coal + Iron Ore -> Steel), Warehouse | IMPLEMENTED | N/A | `ProductionService` + `ProductionRules`, storage via `ResourceService` |
| **Phase 4** civilian traffic every 60 s, ceil(Houses / 2) cars (cap 12), House -> Shop / Gas Station / Office -> despawn | IMPLEMENTED | N/A | real RoadGraph path, TweenService per straight stretch, no car if no destination |
| **Phase 5** Rail Track (drag build), Railway Station, Freight Trains (Coal / Iron Ore / Oil / Steel / Fuel / Supplies) | IMPLEMENTED | N/A | client drag = Road drag flow -> `PlaceRailLine`; trains every 45 s on RailGraph waypoints |
| **Phase 6** Stats: OVERVIEW / BUILDINGS / UTILITIES / TRANSPORT / RESOURCES | IMPLEMENTED | N/A | `StatsPanel` tab STATS |
| Phase 6 2D CITY MAP with WATER / POWER / BUILDINGS / ROADS overlays + real radii | IMPLEMENTED | N/A | `GetCityMap` -> `StatsPanel` tab CITY MAP |
| Water (Tower production / capacity / radius, shortage stages, gradual decrease) | IMPLEMENTED | VERIFIED (v0.2) | unchanged logic |
| Power (Wind small / cheap, Substation big / Steel cost / Fuel upkeep) | IMPLEMENTED | VERIFIED (v0.2) | upkeep offline state added in v0.4 |
| Save / load (schema 3, migrations v1 -> v2 -> v3, defaults for new fields) | IMPLEMENTED | N/A | railway, economy, resources, research saved |

## Economy (Phase 2)
* Start: Treasury 0, population 0, all resources 0. No starter grant. Debt allowed (`Economy.AllowDebt`),
  but anything with a Treasury cost needs Treasury >= cost.
* Cycle = `Economy.CycleSeconds` = 30 s. Per cycle per plot owner: production -> upkeep -> Income - Expenses = Net
  -> Treasury -> research. Business income x min(1, Population / Customers); a business with RED water or power
  earns `UtilityPenalty` (50 %). Gas Stations also sell Fuel. Roads / rails cost 1 per 10 tiles.
* Every building: `Cost`, `IncomePerCycle`, `ExpensePerCycle`, `PopulationRequired`, `Water`, `Power` in `BuildingConfig.json`.

## Resources / industry (Phase 3)
Coal Mine -> Coal, Iron Mine -> Iron Ore, Oil Well -> Crude Oil, Oil Refinery Oil 2 -> Fuel 2,
Steel Factory Coal 2 + Iron Ore 2 -> Steel 1, Workshop / Factory -> Supplies. Storage = `Resources.BaseStorage`
+ Warehouse `StorageCapacity`. Producers need power/water; a railway-connected producer gets `Railway.RailBonus`.

## Traffic (Phase 4)
`VehicleService` every `Traffic.IntervalSeconds` (60 s): H = completed houses, cars = min(ceil(H / 2), 12).
Origins = houses, destinations = Shops / Gas Stations / Offices with road access. Path = RoadGraph (real tiles),
right-hand lane offset, TweenService moves one anchored root per straight stretch, car despawns at the destination.
No destination or no road path -> no car. Lifetime cap 40 s.

## Railway (Phase 5)
Rail Track: hold-drag-release like roads (client preview with `PlacementRules.validateRailLine`, server re-validates
ownership, plot bounds, collisions with buildings / roads, cost). Stations connect tracks; `RailGraph` finds station
routes; a Freight Train (1-3 wagons, 20 units each) runs every 45 s carrying Coal / Iron Ore / Oil / Steel / Fuel / Supplies.

## City Stats (Phase 6)
STATS tab: OVERVIEW (Population, Treasury, Income, Expenses, Net), BUILDINGS (Houses, Businesses, Industry,
Infrastructure, Military, Research), UTILITIES (Water + Power meters and per-building GREEN / RED / GREY list),
TRANSPORT (Roads, cars, rail tiles, stations, trains), RESOURCES (Coal, Iron Ore, Oil, Fuel, Steel, Supplies vs storage).
CITY MAP tab: top-down plot map from `GetCityMap` (plot-local building rects, road tiles, rail tiles, exit) with overlays
WATER / POWER (building status colors + real coverage radius rings), BUILDINGS (category colors), ROADS.
Fetched only while the tab is open (rate-limited client + server).

## Architecture / files
```
ReplicatedStorage/Shared
  Config/  GameConfig (Map, Economy, Traffic, Railway, Resources, EmptyCountry, Migration), BuildingConfig (37 buildings),
           BuildMenuConfig (3 categories + groups + draw tools Road/Rail), PlacementConfig, RoadConfig, TechnologyConfig,
           CountryRegistry, ThemeConfig
  Modules/ GridMath, Plots, PlacementRules (roads, rails, buildings), RoadGraph, RailGraph, RoadModels, BuildingModels,
           ExtraModels (v0.4 models), VehicleModels (cars, trains, rail tiles), UtilityGrid, EconomyRules, ProductionRules,
           TrafficRules, Countries, DefaultCountry
ServerScriptService/Systems  Data, World, Country, Buildings, Construction, Roads, Railway, Vehicles, Water, Power,
                             Population, Resources, Production, Economy, Research, Stats, Military
ServerScriptService/Tests/RuntimeSelfTest (Studio only)
StarterPlayerScripts  ClientMain, Controllers/ClientState, PlacementController (building / road / rail / demolish), ConstructionBars
StarterGui/MainUI     Components/UIKit, Screens/MainMenu, SlotScreen, CreateStateScreen, PlotScreen, HUD, BuildMenu,
                      PlacementBar, StatsPanel (stats + city map), Toast
Workspace  Terrain, Map (static), Buildings/Plot_n (buildings + rail tiles), Roads/Plot_n, Vehicles/Plot_n, NPCs
tools/  gen_static_map.py, ci_unpack_rojo.py, verify_build.py (+ required_build_paths.txt), make_release_zip.py,
        rojo_build.py (structure mirror), countries.py, write_configs.py, write_buildings.py, rojo_probe/
tests/  test_config, test_countries, test_structure, test_luau_static, test_gameplay_rules, test_security,
        test_static_map, test_rojo_build (structure + REAL build XML), test_no_doctrine, test_phases_v04
```

## Remotes
RemoteFunctions: GetProfile, CreateCountry, LoadSlot, DeleteSlot, LeaveState, SaveNow, GetPlots, ClaimPlot,
PlaceRoad, PlaceRoadLine, PlaceBuilding, Demolish (building / road / rail), PlaceRailLine, GetCityMap.
RemoteEvents: StateChanged, PlotsChanged, Notify. Constants.luau and default.project.json are checked against each other.

## Security (server)
Every request is validated on the server: plot ownership (only the requester's plot bounds and records), placement
rules, collisions, costs, population unlocks, resources, demolish ownership, road / rail lines; rate limits and NaN guards.
The client only previews and requests.

## Save data (schema 3)
Country, flag, continent, technology, plot, Treasury, population / workers / housing, Coal / IronOre / Oil / Fuel / Steel /
Supplies, buildings (state, water / power status), roads, Railway{Tracks, NextTrackId, Delivered}, Infrastructure{Water,
Power, Shortage}, Economy{Cycle, LastIncome, LastExpense, LastNet}, Research. Migration fills defaults; nothing is granted.

## Tests & verification
* Automated: 101 Python tests (96 run everywhere, 5 real-build XML tests run only with the CI Rojo build).
* Real Rojo 7.7.0 build + verify + tests + ZIP run in GitHub Actions on every push.
* Studio Play test: **N/A** (no Roblox Studio in the build environment). Run the checklist below.

## Known limitations
* Terrain water is filled at server start (Rojo cannot serialize terrain voxels).
* No DataStore session locking (last write wins). Construction / production advance only while the owner is online.
* Flags are emoji fallbacks (no verified image ids).
* `.github/workflows/restore-v04-wip.yml` (one-time WIP restore helper) still triggers on push and fails harmlessly
  because the WIP ZIP was removed; delete it in the GitHub UI (the connected token has no `workflow` scope).

## Studio checklist (v0.4)
Play -> `[WarState] Server ready` + `[WarState SelfTest] PASS` -> create country -> claim plot -> HUD shows flag / name /
pop 0 / $0 / tech / cycle timer -> Build -> CIVILIAN: Small House + Shop + Water Tower + Wind Generator (free) -> roads
(drag) -> wait 30 s: Net applied -> population grows -> unlock Gas Station / Office -> 60 s: cars drive House -> Shop
-> mines + refinery + steel factory -> Rail Track (drag) + 2 stations -> freight train -> Stats: all sections + CITY MAP
overlays -> Save -> leave -> Load -> everything restored.
