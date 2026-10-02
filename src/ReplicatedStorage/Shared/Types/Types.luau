-- Types: shared Luau type definitions (documentation + type checking only, no runtime logic).

export type BuildState = "PLANNED" | "UNDER_CONSTRUCTION" | "COMPLETED"
export type UtilityStatus = "GREEN" | "RED" | "GREY"

export type BuildingRecord = {
	Id: string,
	Type: string,
	Variant: string,
	X: number, -- plot-local center X
	Z: number, -- plot-local center Z
	Rotation: number, -- 0..3 quarter turns clockwise
	State: BuildState,
	PlannedElapsed: number,
	Progress: number, -- seconds of construction completed
	CreatedAt: number,
	WaterRequired: number,
	WaterSupplied: number,
	WaterStatus: UtilityStatus,
	PowerRequired: number,
	PowerSupplied: number,
	PowerStatus: UtilityStatus,
}

export type RoadSegment = {
	RoadId: string,
	Type: string, -- always "Straight" (junction visuals are derived automatically)
	Rotation: number, -- 0 = drawn along Z (N-S), 1 = drawn along X (E-W)
	Ix: number,
	Iz: number,
	Position: { X: number, Z: number }, -- plot-local tile center
	Neighbours: { string }, -- connected RoadIds (graph edges)
	Adjacent: { string }, -- touching RoadIds
	Connected: boolean,
	Openings: string, -- e.g. "NS", "NES" (derived)
	ExitConnected: boolean, -- tile touches the plot exit
}

export type Infrastructure = {
	Water: { Stored: number, Production: number, Demand: number },
	Power: { Production: number, Demand: number },
	Shortage: { Stage: string, Seconds: number },
}

export type Country = {
	SchemaVersion: number,
	SlotIndex: number,
	Name: string,
	FlagId: string,
	Continent: string,
	TechnologyBranch: string,
	CreatedAt: number,
	Treasury: number,
	Oil: number,
	Fuel: number,
	Steel: number,
	Supplies: number,
	Population: number,
	Workers: number,
	HousingCapacity: number,
	Buildings: { [string]: BuildingRecord },
	Roads: { [string]: RoadSegment },
	Military: { [string]: any },
	Infrastructure: Infrastructure,
	LastPlotIndex: number,
	NextBuildingId: number,
	NextRoadId: number,
}

export type SlotSummary = {
	Index: number,
	Locked: boolean,
	Empty: boolean,
	Name: string?,
	FlagId: string?,
	TechnologyBranch: string?,
	Population: number?,
}

export type PlotInfo = {
	Index: number,
	Free: boolean,
	OwnerName: string?,
	OwnerUserId: number?,
	CountryName: string?,
	FlagId: string?,
}

return {}
