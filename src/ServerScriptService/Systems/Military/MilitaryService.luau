-- MilitaryService: PLANNED placeholder.
-- Future military layer (units, military UI/data). No combat or weapons are implemented.
-- Future ground vehicles will leave the plot through its exit (see VehicleService / Plots.getExit)
-- and fight on the central island. This module intentionally contains NO gameplay mechanics.

local MilitaryService = {}
MilitaryService.Name = "MilitaryService"
MilitaryService.Status = "PLANNED"
MilitaryService.Active = false
MilitaryService.Description = "Future military layer (units, military UI/data). No combat or weapons are implemented."

function MilitaryService.init(_services) end

function MilitaryService.start() end

return MilitaryService
