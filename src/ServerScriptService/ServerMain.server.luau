-- ServerMain: single server entry point. Requires every system, calls init() then start().
-- Systems never run from their own Script; order is explicit here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"):WaitForChild("Constants"))

local Systems = script.Parent:WaitForChild("Systems")

-- Remotes are defined in default.project.json (Rojo). If they are missing (e.g. playing without
-- Rojo), create them once. FindFirstChild guards prevent duplicates.
local function ensureRemotes()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	local remotes = {}
	for _, name in ipairs(Constants.RemoteFunctions) do
		local r = folder:FindFirstChild(name)
		if not r then
			r = Instance.new("RemoteFunction")
			r.Name = name
			r.Parent = folder
			warn("[ServerMain] Created missing RemoteFunction " .. name)
		end
		remotes[name] = r
	end
	for _, name in ipairs(Constants.RemoteEvents) do
		local r = folder:FindFirstChild(name)
		if not r then
			r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
			warn("[ServerMain] Created missing RemoteEvent " .. name)
		end
		remotes[name] = r
	end
	return remotes
end

local ORDER = {
	{ "Data", "DataService" },
	{ "World", "WorldService" },
	{ "Resources", "ResourceService" },
	{ "Roads", "RoadService" },
	{ "Buildings", "BuildingService" },
	{ "Railway", "RailService" },
	{ "Construction", "ConstructionService" },
	{ "Water", "WaterService" },
	{ "Power", "PowerService" },
	{ "Population", "PopulationService" },
	{ "Stats", "StatsService" },
	{ "Country", "CountryService" },
	{ "Research", "ResearchService" },
	{ "Production", "ProductionService" },
	{ "Economy", "EconomyService" },
	{ "Vehicles", "VehicleService" },
	{ "Military", "MilitaryService" },
}

local services = { Remotes = ensureRemotes() }
local loaded = {}

for _, entry in ipairs(ORDER) do
	local folderName, moduleName = entry[1], entry[2]
	local moduleScript = Systems:WaitForChild(folderName):WaitForChild(moduleName)
	local ok, result = pcall(require, moduleScript)
	if not ok then
		error(string.format("[ServerMain] Failed to load %s: %s", moduleName, tostring(result)))
	end
	services[moduleName] = result
	table.insert(loaded, result)
end

for _, service in ipairs(loaded) do
	service.init(services)
end
for _, service in ipairs(loaded) do
	service.start()
end

ReplicatedStorage:SetAttribute("WarStateServerReady", true)
print(string.format("[WarState] Server ready (%d systems)", #loaded))
