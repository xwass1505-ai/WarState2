-- Countries: lookup helpers over the generated CountryRegistry (195 sovereign states).
-- Flags: FlagAsset is empty unless a real, verified Roblox asset id is provided.
-- When FlagAsset is empty the UI shows EmojiFallback.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Registry = require(Config:WaitForChild("CountryRegistry"))

local Countries = {}

Countries.Continents = Registry.Continents
Countries.List = Registry.Countries

local byId = {}
local byContinent = {}
for _, continent in ipairs(Registry.Continents) do
	byContinent[continent] = {}
end
for _, entry in ipairs(Registry.Countries) do
	byId[entry.Id] = entry
	local bucket = byContinent[entry.Continent]
	if bucket then
		table.insert(bucket, entry)
	end
end
for _, bucket in pairs(byContinent) do
	table.sort(bucket, function(a, b)
		return a.DisplayNameEN < b.DisplayNameEN
	end)
end

function Countries.get(id: string)
	return byId[id]
end

function Countries.forContinent(continent: string)
	return byContinent[continent] or {}
end

function Countries.count(): number
	return #Registry.Countries
end

function Countries.hasRealFlag(entry): boolean
	return entry ~= nil and type(entry.FlagAsset) == "string" and entry.FlagAsset ~= ""
end

-- Case-insensitive plain-text search over English names (secondary navigation).
function Countries.search(query: string, continent: string?)
	local q = string.lower(query or "")
	local results = {}
	local source = continent and Countries.forContinent(continent) or Registry.Countries
	for _, entry in ipairs(source) do
		if q == "" or string.find(string.lower(entry.DisplayNameEN), q, 1, true) then
			table.insert(results, entry)
		end
	end
	return results
end

return Countries
