-- DefaultCountry: creates an EMPTY country from GameConfig.EmptyCountry and migrates old saves.
-- No starting resources, citizens, houses, roads, infrastructure or economy are ever granted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))

local DefaultCountry = {}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = deepCopy(v)
	end
	return copy
end

DefaultCountry.deepCopy = deepCopy

-- Fill missing keys recursively (never overwrites existing values).
local function fillDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if target[key] == nil then
			target[key] = deepCopy(value)
		elseif type(value) == "table" and type(target[key]) == "table" and next(value) ~= nil then
			fillDefaults(target[key], value)
		end
	end
end

function DefaultCountry.new(slotIndex: number, name: string, flagId: string, continent: string, technologyBranch: string)
	local country = deepCopy(GameConfig.EmptyCountry)
	country.SchemaVersion = GameConfig.SchemaVersion
	country.SlotIndex = slotIndex
	country.Name = name
	country.FlagId = flagId
	country.Continent = continent
	country.TechnologyBranch = technologyBranch
	country.CreatedAt = os.time()
	country.NextBuildingId = 1
	country.NextRoadId = 1
	country.Railway.NextTrackId = 1
	return country
end

local UTILITY_DEFAULTS = {
	WaterRequired = 0,
	WaterSupplied = 0,
	WaterStatus = "GREY",
	PowerRequired = 0,
	PowerSupplied = 0,
	PowerStatus = "GREY",
}

-- v1 -> v2: buildings/roads were 4x larger (8-stud houses on a 480-stud plot with 8-stud road tiles).
-- Scaling positions by Migration.V1PositionScale maps the old layout exactly onto the new grid.
local function migrateV1(country)
	local scale = GameConfig.Migration.V1PositionScale
	if country.Money ~= nil then
		if country.Treasury == nil then
			country.Treasury = country.Money
		end
		country.Money = nil
	end
	for _, record in pairs(country.Buildings or {}) do
		if type(record.X) == "number" then
			record.X *= scale
		end
		if type(record.Z) == "number" then
			record.Z *= scale
		end
	end
	for _, segment in pairs(country.Roads or {}) do
		if type(segment.Position) == "table" then
			segment.Position.X = (segment.Position.X or 0) * scale
			segment.Position.Z = (segment.Position.Z or 0) * scale
		end
		-- Only the Straight Road type exists now; junctions are derived automatically.
		if segment.Type ~= "Straight" then
			segment.Rotation = 0
		end
		segment.Type = "Straight"
		segment.Openings = nil
	end
	country.MigratedFromSchema = country.SchemaVersion or 1
end

-- v2 -> v3 (v0.4): economy cycles, resources (Coal, Iron Ore), research points, railway.
-- Every new field comes from GameConfig.EmptyCountry (all zero / empty), so nothing is granted.
-- Old saves keep their buildings, roads, treasury and population.
local function migrateV2(country)
	country.MigratedFromSchema = country.MigratedFromSchema or (country.SchemaVersion or 2)
	if type(country.Railway) ~= "table" then
		country.Railway = nil
	end
	if type(country.Economy) ~= "table" then
		country.Economy = nil
	end
end

-- Fill missing fields for older saves without granting anything.
function DefaultCountry.migrate(country)
	local version = tonumber(country.SchemaVersion) or 1
	if version < 2 then
		migrateV1(country)
	end
	if version < 3 then
		migrateV2(country)
	end
	if country.Money ~= nil and country.Treasury == nil then
		country.Treasury = country.Money
	end
	country.Money = nil
	fillDefaults(country, GameConfig.EmptyCountry)
	for _, record in pairs(country.Buildings) do
		for key, value in pairs(UTILITY_DEFAULTS) do
			if record[key] == nil then
				record[key] = value
			end
		end
	end
	country.NextBuildingId = country.NextBuildingId or 1
	country.NextRoadId = country.NextRoadId or 1
	country.Railway.Tracks = country.Railway.Tracks or {}
	country.Railway.NextTrackId = country.Railway.NextTrackId or 1
	country.SchemaVersion = GameConfig.SchemaVersion
	return country
end

return DefaultCountry
