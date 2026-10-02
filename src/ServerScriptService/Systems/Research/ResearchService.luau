-- ResearchService: PARTIAL. Research buildings (Research Center, Technology Laboratory, Engineering,
-- Military Research, Radar & Electronics Lab, Vehicle / Aircraft Research) generate research points
-- every economy cycle while completed and supplied (not RED on water/power). Points and the derived
-- research level are saved per country. The technology tree that spends points is PLANNED.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local BuildingConfig = require(Config:WaitForChild("BuildingConfig"))
local GameConfig = require(Config:WaitForChild("GameConfig"))

local ResearchService = {}
ResearchService.Name = "ResearchService"
ResearchService.Status = "PARTIAL"
ResearchService.Active = true
ResearchService.Description = "Research points per cycle from research buildings. Technology tree planned."

local defsById = {}
for _, def in ipairs(BuildingConfig.Buildings) do
	defsById[def.Id] = def
end

function ResearchService.pointsPerCycle(country): number
	local total = 0
	for _, record in pairs(country.Buildings or {}) do
		local def = defsById[record.Type]
		if def and (def.ResearchPerCycle or 0) > 0 and record.State == "COMPLETED"
			and record.WaterStatus ~= "RED" and record.PowerStatus ~= "RED" then
			total += def.ResearchPerCycle
		end
	end
	return total
end

function ResearchService.level(points: number): number
	return math.floor((points or 0) / math.max(1, GameConfig.Research.PointsPerLevel))
end

function ResearchService.cycle(_player: Player, country)
	country.Research = country.Research or { Points = 0 }
	local gained = ResearchService.pointsPerCycle(country)
	country.Research.Points = (country.Research.Points or 0) + gained
	country.Research.LastGain = gained
	country.Research.Level = ResearchService.level(country.Research.Points)
	return gained
end

function ResearchService.init(_services) end

function ResearchService.start() end

return ResearchService
