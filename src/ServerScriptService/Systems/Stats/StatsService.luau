-- StatsService: builds the REAL statistics shown in the Stats panel and the 2D City Map.
-- Every number is derived from the authoritative country data (no fake values).
-- Sections: OVERVIEW (population, treasury, income, expenses), BUILDINGS (houses, businesses,
-- industry, infrastructure, military, research), UTILITIES (water, power), TRANSPORT (roads,
-- vehicles, railway), RESOURCES (coal, iron ore, crude oil, fuel, steel, supplies).
-- The City Map (GetCityMap remote) returns real plot-local coordinates of buildings, roads, rails,
-- water / power sources with their real coverage radii.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local BuildingConfig = require(Config:WaitForChild("BuildingConfig"))
local PlacementConfig = require(Config:WaitForChild("PlacementConfig"))
local Constants = require(Shared:WaitForChild("Constants"):WaitForChild("Constants"))
local GridMath = require(Shared:WaitForChild("Modules"):WaitForChild("GridMath"))
local UtilityGrid = require(Shared:WaitForChild("Modules"):WaitForChild("UtilityGrid"))

local StatsService = {}
StatsService.Name = "StatsService"
StatsService.RoadListLimit = 6
StatsService.BuildingListLimit = 60
StatsService.Groups = { "Houses", "Businesses", "Industry", "Infrastructure", "Military", "Research" }

local services
local remotes
local lastMapRequest = {}

local defsById = {}
for _, def in ipairs(BuildingConfig.Buildings) do
	defsById[def.Id] = def
end

local function idNumber(id: string): number
	return tonumber(string.match(id or "", "%d+")) or 0
end

local function resourcesOf(country, capacity)
	local list = {}
	for _, key in ipairs(GameConfig.Resources.Keys) do
		table.insert(list, {
			Key = key,
			Label = GameConfig.Resources.DisplayNames[key] or key,
			Amount = math.floor(country[key] or 0),
			Capacity = capacity,
			Produced = country.Production and country.Production.Produced and country.Production.Produced[key] or 0,
			Consumed = country.Production and country.Production.Consumed and country.Production.Consumed[key] or 0,
		})
	end
	return list
end

-- player is optional (pure country stats when nil, e.g. in tests).
function StatsService.build(country, player: Player?)
	local stats = {
		Population = country.Population or 0,
		HousingCapacity = country.HousingCapacity or 0,
		Workers = country.Workers or 0,
		Roads = 0,
		Buildings = 0,
		UnderConstruction = 0,
		WaterTowers = 0,
		PowerSources = 0,
		Producers = 0,
	}
	for _, group in ipairs(StatsService.Groups) do
		stats[group] = 0
	end
	local waterList, powerList = {}, {}
	local counters = {}
	local records = UtilityGrid.sortedRecords(country.Buildings)
	for _, record in ipairs(records) do
		local def = defsById[record.Type]
		if def then
			stats.Buildings += 1
			local completed = record.State == Constants.BuildState.Completed
			if not completed then
				stats.UnderConstruction += 1
			end
			if completed then
				local group = def.StatsGroup
				if group and stats[group] ~= nil then
					stats[group] += 1
				end
				if def.Water and (def.Water.Production or 0) > 0 then
					stats.WaterTowers += 1
				end
				if def.Power and (def.Power.Production or 0) > 0 then
					stats.PowerSources += 1
				end
				if def.Production then
					stats.Producers += 1
				end
			end
			local short = def.ShortName or def.DisplayName
			counters[short] = (counters[short] or 0) + 1
			local label = short .. " #" .. counters[short]
			if #waterList < StatsService.BuildingListLimit then
				table.insert(waterList, {
					Label = label,
					Id = record.Id,
					Status = record.WaterStatus or "GREY",
					Required = record.WaterRequired or 0,
					Supplied = record.WaterSupplied or 0,
					Pending = not completed,
				})
				table.insert(powerList, {
					Label = label,
					Id = record.Id,
					Status = record.PowerStatus or "GREY",
					Required = record.PowerRequired or 0,
					Supplied = record.PowerSupplied or 0,
					Pending = not completed,
				})
			end
		end
	end
	local roadCount = 0
	for _ in pairs(country.Roads or {}) do
		roadCount += 1
	end
	stats.Roads = roadCount
	local infra = country.Infrastructure or {}
	local water = infra.Water or {}
	local power = infra.Power or {}
	local shortage = infra.Shortage or {}
	local economy = country.Economy or {}
	local preview = nil
	local railway = { Tracks = 0, Stations = 0, Routes = 0, ActiveTrains = 0, Trips = 0, Delivered = 0 }
	local traffic = { ActiveCars = 0, LastWaveCars = 0, LastWaveHouses = 0 }
	local capacity = GameConfig.Resources.BaseStorage
	if player and services then
		preview = services.EconomyService.preview(player, country)
		railway = services.RailService.getStats(player, country)
		traffic = services.VehicleService.getTrafficStats(player)
		capacity = services.ProductionService.capacity(country)
	else
		for _ in pairs((country.Railway and country.Railway.Tracks) or {}) do
			railway.Tracks += 1
		end
	end
	local research = country.Research or {}
	return {
		Stats = stats,
		Overview = {
			Population = stats.Population,
			HousingCapacity = stats.HousingCapacity,
			Treasury = math.floor(country.Treasury or 0),
			Income = preview and preview.income or (economy.LastIncome or 0),
			Expenses = preview and preview.expense or (economy.LastExpense or 0),
			Net = preview and preview.net or (economy.LastNet or 0),
			LastNet = economy.LastNet or 0,
			Cycle = economy.Cycle or 0,
			CustomerEfficiency = preview and preview.efficiency or 1,
		},
		Water = {
			Production = water.Production or 0,
			Demand = water.Demand or 0,
			Supplied = water.Supplied or 0,
			Stored = water.Stored or 0,
			Capacity = water.Capacity or 0,
			Stage = shortage.Stage or Constants.ShortageStage.Normal,
			ShortageSeconds = shortage.Seconds or 0,
		},
		Power = {
			Production = power.Production or 0,
			Demand = power.Demand or 0,
			Supplied = power.Supplied or 0,
		},
		Transport = {
			Roads = roadCount,
			ActiveCars = traffic.ActiveCars,
			LastWaveCars = traffic.LastWaveCars,
			RailTracks = railway.Tracks,
			Stations = railway.Stations,
			RailRoutes = railway.Routes,
			ActiveTrains = railway.ActiveTrains,
			TrainTrips = railway.Trips,
			FreightDelivered = railway.Delivered,
		},
		Resources = resourcesOf(country, capacity),
		StorageCapacity = capacity,
		Research = { Points = research.Points or 0, Level = research.Level or 0, LastGain = research.LastGain or 0 },
		WaterList = waterList,
		PowerList = powerList,
		ExtraRoads = 0,
	}
end

-- 2D city map data (plot-local studs). Overlays are drawn on the client from these real values.
function StatsService.buildMap(player: Player)
	local country = services.DataService.getCountry(player)
	local bounds = services.WorldService.getBounds(player)
	if not country or not bounds then
		return { ok = false, error = "No plot" }
	end
	local buildings = {}
	for _, record in ipairs(UtilityGrid.sortedRecords(country.Buildings)) do
		local def = defsById[record.Type]
		if def then
			local w, d = GridMath.rotatedSize(def.Footprint[1], def.Footprint[2], record.Rotation or 0)
			table.insert(buildings, {
				Id = record.Id,
				Name = def.DisplayName,
				Group = def.StatsGroup,
				Menu = def.MenuCategory,
				X = record.X,
				Z = record.Z,
				W = w,
				D = d,
				State = record.State,
				WaterStatus = record.WaterStatus or "GREY",
				PowerStatus = record.PowerStatus or "GREY",
				WaterRadius = (def.Water and (def.Water.Production or 0) > 0) and def.Water.Radius or 0,
				PowerRadius = (def.Power and (def.Power.Production or 0) > 0 and not record.PowerOffline) and def.Power.Radius or 0,
			})
		end
	end
	local roads = {}
	for _, segment in pairs(country.Roads or {}) do
		table.insert(roads, { segment.Ix, segment.Iz })
	end
	local rails = {}
	for _, track in pairs((country.Railway and country.Railway.Tracks) or {}) do
		table.insert(rails, { track.Ix, track.Iz })
	end
	local exit = services.WorldService.getExit(player)
	return {
		ok = true,
		PlotSize = bounds.size,
		Tile = PlacementConfig.RoadTileSize,
		ExitSide = bounds.exitSide,
		Exit = exit and { exit.ix, exit.iz } or nil,
		Buildings = buildings,
		Roads = roads,
		Rails = rails,
	}
end

local function handleGetCityMap(player)
	local now = os.clock()
	if lastMapRequest[player] and now - lastMapRequest[player] < 0.5 then
		return { ok = false, error = "Too fast" }
	end
	lastMapRequest[player] = now
	return StatsService.buildMap(player)
end

StatsService.idNumber = idNumber

function StatsService.init(allServices)
	services = allServices
	remotes = allServices.Remotes
end

function StatsService.start()
	remotes[Constants.Remotes.GetCityMap].OnServerInvoke = handleGetCityMap
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastMapRequest[player] = nil
	end)
end

return StatsService
