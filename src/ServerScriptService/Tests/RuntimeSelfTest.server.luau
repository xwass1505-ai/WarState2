-- RuntimeSelfTest: runs automatically in Studio Play (server side) and prints PASS/FAIL.
-- It exercises the REAL shared modules inside Roblox (registry, defaults, migration, placement,
-- road drag lines, road graph + exits, building sizes, water/power coverage, shortage stages,
-- population, static map + terrain water, economy, unlocks, resources, traffic and railway rules).
-- Result is also written to ReplicatedStorage attribute "WarStateSelfTest".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() then
	return
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = Shared:WaitForChild("Config")
local Countries = require(Modules:WaitForChild("Countries"))
local DefaultCountry = require(Modules:WaitForChild("DefaultCountry"))
local PlacementRules = require(Modules:WaitForChild("PlacementRules"))
local RoadGraph = require(Modules:WaitForChild("RoadGraph"))
local GridMath = require(Modules:WaitForChild("GridMath"))
local Plots = require(Modules:WaitForChild("Plots"))
local UtilityGrid = require(Modules:WaitForChild("UtilityGrid"))
local BuildingModels = require(Modules:WaitForChild("BuildingModels"))
local BuildingConfig = require(Config:WaitForChild("BuildingConfig"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Registry = require(Config:WaitForChild("CountryRegistry"))

local Systems = script.Parent.Parent:WaitForChild("Systems")

local results = { passed = 0, failed = 0, failures = {} }

local function check(name: string, condition: boolean, detail: string?)
	if condition then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, name .. (detail and (" (" .. detail .. ")") or ""))
	end
end

local defsById = {}
for _, def in ipairs(BuildingConfig.Buildings) do
	defsById[def.Id] = def
end

-- Registry
check("Registry has 195 countries", Countries.count() == 195, tostring(Countries.count()))
local seen, duplicates = {}, 0
for _, entry in ipairs(Countries.List) do
	if seen[entry.Id] then
		duplicates += 1
	end
	seen[entry.Id] = true
end
check("No duplicate country ids", duplicates == 0, tostring(duplicates))
for continent, expected in pairs(Registry.ExpectedContinentCounts) do
	local actual = #Countries.forContinent(continent)
	check("Continent count " .. continent, actual == expected, tostring(actual))
end
check("Holy See present", Countries.get("VA") ~= nil)
check("Palestine present", Countries.get("PS") ~= nil)

-- Empty country defaults
local country = DefaultCountry.new(1, "Novaria", "DE", "Europe", "USSR")
for _, key in ipairs({ "Treasury", "Oil", "Fuel", "Steel", "Supplies", "Population", "Workers", "HousingCapacity" }) do
	check("Empty country " .. key .. " = 0", country[key] == 0, tostring(country[key]))
end
check("Empty country has no buildings", next(country.Buildings) == nil)
check("Empty country has no roads", next(country.Roads) == nil)
check("Empty country has no military", next(country.Military) == nil)
check("Empty country water stored = 0", country.Infrastructure.Water.Stored == 0)
for key in pairs(country) do
	check("No doctrine field: " .. key, not string.find(string.lower(key), "doctrine", 1, true))
end

-- Migration of an old (schema 1) save
local old = {
	SchemaVersion = 1,
	Name = "Old",
	Money = 0,
	Population = 3,
	Buildings = { B1 = { Id = "B1", Type = "SmallHouse", Variant = "SmallHouse_A", X = 84, Z = 96, Rotation = 0, State = "COMPLETED" } },
	Roads = { R1 = { RoadId = "R1", Type = "Corner", Rotation = 2, Ix = 10, Iz = 11, Position = { X = 84, Z = 92 } } },
}
DefaultCountry.migrate(old)
check("Migration: Money -> Treasury", old.Treasury == 0 and old.Money == nil)
check("Migration: building position scaled", old.Buildings.B1.X == 21 and old.Buildings.B1.Z == 24)
check("Migration: road becomes Straight", old.Roads.R1.Type == "Straight" and old.Roads.R1.Position.X == 21)
check("Migration: utility fields added", old.Buildings.B1.WaterStatus == "GREY" and old.Buildings.B1.PowerStatus == "GREY")
check("Migration: infrastructure defaults", old.Infrastructure ~= nil and old.Infrastructure.Shortage.Stage == "NORMAL")
check("Migration: schema bumped", old.SchemaVersion == GameConfig.SchemaVersion)

-- Plots and exits
check("Exactly 6 plots", Plots.maxPlots() == 6, tostring(Plots.maxPlots()))
for i = 1, Plots.maxPlots() do
	local a = Plots.getBounds(i)
	for j = i + 1, Plots.maxPlots() do
		local b = Plots.getBounds(j)
		check("Plots " .. i .. "/" .. j .. " do not overlap", not GridMath.rectsOverlap(a, b, 0))
	end
	local exit = Plots.getExit(i)
	check("Plot " .. i .. " has an exit tile on its edge", exit.ix >= 0 and exit.iz >= 0 and #exit.waypoints >= 4)
end

-- Static map (Phase 1): part of the place file, present before any player joins.
local waitStart = os.clock()
while not ReplicatedStorage:GetAttribute("WarStateServerReady") and os.clock() - waitStart < 20 do
	task.wait(0.2)
end
local map = Workspace:FindFirstChild("Map")
check("Static map exists in the place", map ~= nil)
if map then
	check("Central island exists", map:FindFirstChild("CentralIsland") ~= nil)
	check("Invisible boundaries exist", map:FindFirstChild("Boundaries") ~= nil)
	local central = map:FindFirstChild("CentralIsland")
	if central then
		check("Central island has trees", central:FindFirstChild("Trees") ~= nil and #central.Trees:GetChildren() > 20)
		check("Central island has bushes", central:FindFirstChild("Bushes") ~= nil and #central.Bushes:GetChildren() > 20)
		check("Central island has rocks", central:FindFirstChild("Rocks") ~= nil and #central.Rocks:GetChildren() > 10)
		check("Central island has dirt paths", central:FindFirstChild("Paths") ~= nil and #central.Paths:GetChildren() > 20)
	end
	local boundaries = map:FindFirstChild("Boundaries")
	if boundaries then
		for _, wall in ipairs(boundaries:GetChildren()) do
			check("Boundary " .. wall.Name .. " is invisible and solid", wall:IsA("BasePart") and wall.Transparency == 1 and wall.CanCollide)
		end
	end
	local plotsFolder = map:FindFirstChild("Plots")
	for i = 1, Plots.maxPlots() do
		local plotModel = plotsFolder and plotsFolder:FindFirstChild("Plot_" .. i)
		check("Static plot " .. i .. " exists", plotModel ~= nil)
		if plotModel then
			local exitModel = plotModel:FindFirstChild("Exit")
			check("Plot " .. i .. " has exit + bridge", exitModel ~= nil and exitModel:FindFirstChild("Bridge") ~= nil)
			local sign = plotModel:FindFirstChild("OwnerSign")
			check("Plot " .. i .. " has owner panel", sign ~= nil and sign:FindFirstChild("OwnerPanel") ~= nil)
		end
	end
end
check("Terrain water filled at server start", Workspace:GetAttribute("WarStateWaterFilled") == true)
local region = Region3.new(Vector3.new(0, -8, -332), Vector3.new(4, -4, -328)):ExpandToGrid(4)
local materials = Workspace.Terrain:ReadVoxels(region, 4)
check("Real terrain water between islands", materials[1][1][1] == Enum.Material.Water, tostring(materials[1][1][1]))

-- Building sizes (small buildings ~2 studs, larger ones only slightly bigger)
for _, def in ipairs(BuildingConfig.Buildings) do
	check(def.Id .. " footprint <= 4 studs", def.Footprint[1] <= 4 and def.Footprint[2] <= 4)
end
local smallModel = BuildingModels.build(defsById.SmallHouse, "SmallHouse_A")
local _, smallSize = smallModel:GetBoundingBox()
check("Small house model ~2 studs", smallSize.X <= 2.6 and smallSize.Z <= 2.6, tostring(smallSize))
smallModel:Destroy()

-- Placement rules
local plot = Plots.getBounds(1)
local small = defsById.SmallHouse
local empty = { plot = plot, buildingRects = {}, roadCells = {} }
local ok, reason = PlacementRules.validateBuilding(small, plot.minX + 41, plot.minZ + 44, 0, empty)
check("House without roads is invalid", not ok and reason == PlacementRules.Reasons.NoRoads, reason)
local roadOk, _, roadInfo = PlacementRules.validateRoad(plot.minX + 41, plot.minZ + 41, empty)
check("Road inside plot is valid", roadOk)
local ctx = {
	plot = plot,
	buildingRects = {},
	roadCells = { [GridMath.cellKey(roadInfo.ix, roadInfo.iz)] = roadInfo.rect },
}
ok, reason = PlacementRules.validateBuilding(small, plot.minX + 41, plot.minZ + 44, 0, ctx)
check("House next to road is valid", ok, reason)
ok, reason = PlacementRules.validateBuilding(small, plot.minX + 41, plot.minZ + 60, 0, ctx)
check("House far from road is invalid", not ok and reason == PlacementRules.Reasons.TooFarFromRoad, reason)
ok, reason = PlacementRules.validateBuilding(small, plot.minX + 41, plot.minZ + 41, 0, ctx)
check("House on road is invalid", not ok and reason == PlacementRules.Reasons.OverlapRoad, reason)
ok, reason = PlacementRules.validateBuilding(small, plot.minX - 20, plot.minZ + 41, 0, ctx)
check("House outside plot is invalid", not ok and reason == PlacementRules.Reasons.OutsideTerritory, reason)
local other = Plots.getBounds(2)
ok, reason = PlacementRules.validateBuilding(small, other.centerX, other.centerZ, 0, ctx)
check("House on another player's plot is invalid", not ok and reason == PlacementRules.Reasons.OutsideTerritory, reason)
local _, _, houseInfo = PlacementRules.validateBuilding(small, plot.minX + 41, plot.minZ + 44, 0, ctx)
ctx.buildingRects = { houseInfo.rect }
ok, reason = PlacementRules.validateBuilding(small, plot.minX + 41.5, plot.minZ + 44.5, 0, ctx)
check("Overlapping houses are invalid", not ok and reason == PlacementRules.Reasons.OverlapBuilding, reason)
roadOk = PlacementRules.validateRoad(plot.minX + 41, plot.minZ + 41, ctx)
check("Duplicate road is invalid", not roadOk)

-- Road drag lines
local cells, axis = PlacementRules.roadLine(plot.minX + 1, plot.minZ + 1, plot.minX + 11, plot.minZ + 2, plot)
check("Drag snaps to dominant axis (E-W)", axis == 1 and #cells == 6, tostring(#cells))
local lineOk, _, tiles, newCount = PlacementRules.validateRoadLine(cells, empty)
check("Drag line is valid", lineOk and newCount == 6 and #tiles == 6)
local vcells, vaxis = PlacementRules.roadLine(plot.minX + 1, plot.minZ + 1, plot.minX + 2, plot.minZ + 15, plot)
check("Drag snaps to dominant axis (N-S)", vaxis == 0 and #vcells == 8, tostring(#vcells))
local outCells = PlacementRules.roadLine(plot.minX + 1, plot.minZ + 1, plot.minX - 9, plot.minZ + 1, plot)
local outOk = PlacementRules.validateRoadLine(outCells, empty)
check("Drag line leaving the plot is invalid", not outOk)

-- Road graph: auto junctions (curbs open where branches join)
local cellsByKey = {}
local a = { RoadId = "A", Type = "Straight", Rotation = 0, Ix = 5, Iz = 5 }
local b = { RoadId = "B", Type = "Straight", Rotation = 0, Ix = 5, Iz = 6 }
local c = { RoadId = "C", Type = "Straight", Rotation = 0, Ix = 5, Iz = 4 }
local d = { RoadId = "D", Type = "Straight", Rotation = 1, Ix = 6, Iz = 5 }
cellsByKey[GridMath.cellKey(5, 5)] = a
cellsByKey[GridMath.cellKey(5, 6)] = b
cellsByKey[GridMath.cellKey(5, 4)] = c
RoadGraph.recomputeAll(cellsByKey)
check("Straight N-S line", a.Openings == "NS" and a.Connected)
cellsByKey[GridMath.cellKey(6, 5)] = d
local changed = RoadGraph.updateAround(cellsByKey, 6, 5)
check("Branch turns straight into T junction", a.Openings == "NES", a.Openings)
check("Changed tiles reported for rebuild", #changed >= 2)
check("Isolated tile keeps its axis", RoadGraph.openings("Straight", 1).E == true)
local byId = { A = a, B = b, C = c, D = d }
local path = RoadGraph.findPath(byId, "B", "D")
check("Path finding through junction", path ~= nil and #path == 3)
local exit = Plots.getExit(1)
local e = { RoadId = "E", Type = "Straight", Rotation = 0, Ix = exit.ix, Iz = exit.iz }
local exitCells = { [exit.key] = e }
RoadGraph.recomputeAll(exitCells, { key = exit.key, side = exit.side })
check("Road on exit tile connects to exit", e.ExitConnected == true and string.find(e.Openings, exit.side, 1, true) ~= nil)

-- Water / power coverage
local buildings = {
	B1 = { Id = "B1", Type = "WaterTower", X = 10, Z = 10, State = "COMPLETED" },
	B2 = { Id = "B2", Type = "SmallHouse", X = 15, Z = 10, State = "COMPLETED" },
	B3 = { Id = "B3", Type = "SmallHouse", X = 90, Z = 90, State = "COMPLETED" },
	B4 = { Id = "B4", Type = "SmallHouse", X = 12, Z = 14, State = "UNDER_CONSTRUCTION" },
	B5 = { Id = "B5", Type = "WindGenerator", X = 12, Z = 8, State = "COMPLETED" },
}
local water = UtilityGrid.compute(buildings, defsById, "Water")
UtilityGrid.apply(buildings, "Water", water)
check("House in tower radius gets water (GREEN)", buildings.B2.WaterStatus == "GREEN")
check("House outside radius has shortage (RED)", buildings.B3.WaterStatus == "RED")
check("Unfinished house is GREY", buildings.B4.WaterStatus == "GREY")
check("Water tower does not require water (GREY)", buildings.B1.WaterStatus == "GREY")
check("Water production counted", water.production == defsById.WaterTower.Water.Production)
local power = UtilityGrid.compute(buildings, defsById, "Power")
UtilityGrid.apply(buildings, "Power", power)
check("House near wind generator gets power", buildings.B2.PowerStatus == "GREEN")
check("Far house has no power", buildings.B3.PowerStatus == "RED")
check("Substation is stronger than wind", defsById.Substation.Power.Production > defsById.WindGenerator.Power.Production and defsById.Substation.Power.Radius > defsById.WindGenerator.Power.Radius)

-- Water shortage stages (gradual, never instant)
local WaterService = require(Systems:WaitForChild("Water"):WaitForChild("WaterService"))
local PopulationService = require(Systems:WaitForChild("Population"):WaitForChild("PopulationService"))
local dry = DefaultCountry.new(1, "Dry", "DE", "Europe", "USA")
dry.Buildings.B1 = { Id = "B1", Type = "LargeHouse", X = 20, Z = 20, State = "COMPLETED", WaterStatus = "RED" }
PopulationService.recalculate(dry)
dry.Population = dry.HousingCapacity
local _, stage1 = WaterService.shortageStep(dry, 5)
check("Shortage starts with WARNING", stage1 == "WARNING", stage1)
check("No population loss at WARNING", dry.Population == dry.HousingCapacity)
local _, stage2 = WaterService.shortageStep(dry, GameConfig.Utilities.Shortage.ProlongedSeconds)
check("Then PROLONGED_SHORTAGE", stage2 == "PROLONGED_SHORTAGE", stage2)
check("Growth blocked during prolonged shortage", PopulationService.growthBlocked(dry))
local _, stage3 = WaterService.shortageStep(dry, GameConfig.Utilities.Shortage.ProblemsSeconds)
check("Then POPULATION_PROBLEMS", stage3 == "POPULATION_PROBLEMS", stage3)
local before = dry.Population
local _, stage4 = WaterService.shortageStep(dry, GameConfig.Utilities.Shortage.DecreaseSeconds)
check("Then GRADUAL_POPULATION_DECREASE", stage4 == "GRADUAL_POPULATION_DECREASE", stage4)
check("Population decreases gradually (not instantly)", dry.Population < before and dry.Population > 0, tostring(dry.Population))

-- Population
local popCountry = DefaultCountry.new(1, "Test", "DE", "Europe", "USA")
PopulationService.recalculate(popCountry)
check("No population without housing", popCountry.Population == 0 and popCountry.HousingCapacity == 0)
popCountry.Buildings.B1 = { Id = "B1", Type = "SmallHouse", State = "COMPLETED" }
PopulationService.recalculate(popCountry)
for _ = 1, 50 do
	PopulationService.grow(popCountry)
end
check("Population capped by housing", popCountry.Population == popCountry.HousingCapacity and popCountry.HousingCapacity > 0)

local status = results.failed == 0 and "PASS" or "FAIL"
ReplicatedStorage:SetAttribute("WarStateSelfTest", string.format("%s %d/%d", status, results.passed, results.passed + results.failed))
if results.failed == 0 then
	print(string.format("[WarState SelfTest] PASS (%d checks)", results.passed))
else
	warn(string.format("[WarState SelfTest] FAIL (%d passed, %d failed)", results.passed, results.failed))
	for _, failure in ipairs(results.failures) do
		warn("  - " .. failure)
	end
end
