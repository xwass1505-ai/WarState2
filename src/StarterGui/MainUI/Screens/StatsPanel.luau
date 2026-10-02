-- StatsPanel: right-side panel opened by the STATS button. Shows REAL server data only.
-- Tab STATS   : OVERVIEW / BUILDINGS / UTILITIES (water + power) / TRANSPORT / RESOURCES
--               (snapshot.Overview / Stats / Water / Power / Transport / Resources from StatsService).
-- Tab CITY MAP: real top-down 2D map of the plot (GetCityMap remote: plot-local building rects,
--               road tiles, rail tiles, exit, water / power source radii) with overlays
--               WATER / POWER / BUILDINGS / ROADS. GREEN = supplied, RED = shortage, GREY = not required.
-- Updates whenever the server pushes a new snapshot. Rebuilds only while open (no per-frame work).

local UIKit = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("UIKit"))

local C = UIKit.Theme.Colors
local T = UIKit.Theme

local StatsPanel = {}
StatsPanel.__index = StatsPanel

local WIDTH = 344
local MAP_SIZE = WIDTH - 28

local STAGE_LABEL = {
	NORMAL = { "Normal", "GREEN" },
	WARNING = { "Warning", "WARNING" },
	PROLONGED_SHORTAGE = { "Prolonged shortage", "RED" },
	POPULATION_PROBLEMS = { "Population problems", "RED" },
	GRADUAL_POPULATION_DECREASE = { "Population decreasing", "RED" },
}

local GLYPH = { GREEN = "✓", RED = "✕", GREY = "—" }

function StatsPanel.new(root: ScreenGui, callbacks)
	local self = setmetatable({}, StatsPanel)
	self.callbacks = callbacks or {}
	self.snapshot = nil
	self.panel = UIKit.panel({
		Name = "StatsPanel",
		Canvas = true,
		Radius = T.Radius.Large,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -76, 0.5, 0),
		Size = UDim2.new(0, WIDTH, 1, -150),
		Visible = false,
		Parent = root,
	})
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(WIDTH, 640)
	constraint.MinSize = Vector2.new(WIDTH, 240)
	constraint.Parent = self.panel
	UIKit.padding(self.panel, 14)

	local icon = UIKit.statsIcon(self.panel, 16, C.AccentDark)
	icon.Position = UDim2.fromOffset(0, 4)
	UIKit.label({
		Text = "STATS",
		Font = T.Fonts.Bold,
		TextSize = T.TextSize.Body,
		TextColor3 = C.Text,
		Position = UDim2.fromOffset(24, 0),
		Size = UDim2.new(1, -90, 0, 24),
		Parent = self.panel,
	})
	UIKit.button({
		Text = "Close",
		TextSize = T.TextSize.Tiny,
		Style = "ghost",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(56, 24),
		Radius = 999,
		Parent = self.panel,
		OnClick = function()
			self:hide()
		end,
	})
	self.tab = "STATS"
	self.overlay = "BUILDINGS"
	self.mapData = nil
	self.mapRequestedAt = 0
	local tabs = UIKit.new("Frame", {
		Name = "Tabs",
		BackgroundColor3 = C.SurfaceAlt,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 28),
		Parent = self.panel,
	})
	UIKit.corner(tabs, 999)
	UIKit.padding(tabs, 2)
	UIKit.list(tabs, Enum.FillDirection.Horizontal, 4)
	self.tabButtons = {}
	for i, id in ipairs({ "STATS", "CITY MAP" }) do
		self.tabButtons[id] = UIKit.button({
			Text = id,
			TextSize = T.TextSize.Tiny,
			Style = "ghost",
			Size = UDim2.new(0.5, -2, 1, 0),
			Radius = 999,
			LayoutOrder = i,
			Parent = tabs,
			OnClick = function()
				self:setTab(id)
			end,
		})
	end
	self.tabButtons.STATS.setSelected(true)
	self.scroll = UIKit.vScroll({
		Name = "Body",
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 1, -66),
		Parent = self.panel,
	})
	UIKit.list(self.scroll, Enum.FillDirection.Vertical, 8)
	UIKit.padding(self.scroll, 0, 2)
	return self
end

local function sectionTitle(parent, text, order)
	return UIKit.label({
		Text = text,
		Font = T.Fonts.Bold,
		TextSize = T.TextSize.Tiny,
		TextColor3 = C.AccentDark,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = order,
		Parent = parent,
	})
end

local function statGrid(parent, entries, order)
	local grid = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, math.ceil(#entries / 2) * 50 - 6),
		LayoutOrder = order,
		Parent = parent,
	})
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.5, -3, 0, 44)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for i, e in ipairs(entries) do
		local cell = UIKit.new("Frame", {
			BackgroundColor3 = C.Surface,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = grid,
		})
		UIKit.corner(cell, T.Radius.Small)
		UIKit.stroke(cell, C.Stroke)
		UIKit.padding(cell, 5, 9)
		UIKit.label({
			Text = e[1],
			TextSize = T.TextSize.Tiny,
			TextColor3 = C.TextMuted,
			Size = UDim2.new(1, 0, 0, 14),
			Parent = cell,
		})
		UIKit.label({
			Text = tostring(e[2]),
			Font = T.Fonts.Bold,
			TextSize = T.TextSize.Body,
			TextColor3 = C.Text,
			Position = UDim2.fromOffset(0, 16),
			Size = UDim2.new(1, 0, 0, 18),
			Parent = cell,
		})
	end
	return grid
end

local function meter(parent, label, value, maxValue, order, fillColor, displayText)
	local holder = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.label({
		Text = label,
		TextSize = T.TextSize.Tiny,
		TextColor3 = C.TextMuted,
		Size = UDim2.new(0.6, 0, 0, 14),
		Parent = holder,
	})
	UIKit.label({
		Text = displayText or tostring(value),
		Font = T.Fonts.Bold,
		TextSize = T.TextSize.Tiny,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.4, 0, 0, 14),
		Parent = holder,
	})
	local track = UIKit.new("Frame", {
		BackgroundColor3 = C.Gray,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 6),
		Parent = holder,
	})
	UIKit.corner(track, 999)
	local fraction = (maxValue > 0) and math.clamp(value / maxValue, 0, 1) or 0
	local fill = UIKit.new("Frame", {
		BackgroundColor3 = fillColor or C.Accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	})
	UIKit.corner(fill, 999)
	UIKit.tween(fill, T.Motion.Slow, { Size = UDim2.fromScale(fraction, 1) })
	return holder
end

local function statusList(parent, rows, order, extraRoads)
	local list = UIKit.new("Frame", {
		BackgroundColor3 = C.Surface,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.corner(list, T.Radius.Small)
	UIKit.stroke(list, C.Stroke)
	UIKit.padding(list, 6, 10)
	UIKit.list(list, Enum.FillDirection.Vertical, 2)
	if #rows == 0 then
		UIKit.label({
			Text = "Nothing built yet",
			TextSize = T.TextSize.Tiny,
			TextColor3 = C.TextMuted,
			Size = UDim2.new(1, 0, 0, 18),
			Parent = list,
		})
	end
	for i, row in ipairs(rows) do
		local line = UIKit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = i,
			Parent = list,
		})
		local status = row.Pending and "GREY" or row.Status
		local color = UIKit.statusColor(status)
		local dot = UIKit.statusDot(line, color, 7)
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.fromScale(0, 0.5)
		UIKit.label({
			Text = GLYPH[status] or "—",
			Font = T.Fonts.Bold,
			TextSize = T.TextSize.Tiny,
			TextColor3 = color,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(0, 14, 1, 0),
			Parent = line,
		})
		UIKit.label({
			Text = row.Label,
			TextSize = T.TextSize.Tiny,
			TextColor3 = C.Text,
			Position = UDim2.fromOffset(28, 0),
			Size = UDim2.new(1, -96, 1, 0),
			Parent = line,
		})
		local right
		if row.Pending then
			right = "building"
		elseif (row.Required or 0) > 0 then
			right = string.format("%d / %d", row.Supplied or 0, row.Required)
		else
			right = "not required"
		end
		UIKit.label({
			Text = right,
			TextSize = T.TextSize.Tiny,
			TextColor3 = C.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 70, 1, 0),
			Parent = line,
		})
	end
	if (extraRoads or 0) > 0 then
		UIKit.label({
			Text = string.format("+ %d more road tiles (not required)", extraRoads),
			TextSize = T.TextSize.Tiny,
			TextColor3 = C.TextMuted,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = #rows + 1,
			Parent = list,
		})
	end
	return list
end


local function chip(parent, text, kind, order)
	local bg = kind == "GREEN" and C.SuccessSoft or (kind == "WARNING" and C.WarningSoft or C.DangerSoft)
	local fg = kind == "GREEN" and C.Success or (kind == "WARNING" and C.Warning or C.Danger)
	local frame = UIKit.new("Frame", {
		BackgroundColor3 = bg,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.corner(frame, 999)
	UIKit.label({
		Text = text,
		Font = T.Fonts.Bold,
		TextSize = T.TextSize.Tiny,
		TextColor3 = fg,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	})
	return frame
end

local function money(n)
	n = math.floor(n or 0)
	local sign = n < 0 and "-" or ""
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return sign .. "$" .. out
end

local function signedMoney(n)
	n = math.floor(n or 0)
	return (n >= 0 and "+" or "") .. money(n)
end

local function clear(container)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- STATS TAB ----------------------------------------------------------------------------------
function StatsPanel:renderStats()
	local s = self.snapshot
	local st, water, power = s.Stats, s.Water or {}, s.Power or {}
	local ov = s.Overview or {}
	local tr = s.Transport or {}

	sectionTitle(self.scroll, "OVERVIEW", 1)
	statGrid(self.scroll, {
		{ "Population", string.format("%d / %d", ov.Population or st.Population or 0, ov.HousingCapacity or st.HousingCapacity or 0) },
		{ "Treasury", money(ov.Treasury or s.Treasury) },
		{ "Income / cycle", "+" .. money(ov.Income) },
		{ "Expenses / cycle", "-" .. money(ov.Expenses) },
	}, 2)
	chip(self.scroll, "Net change next cycle: " .. signedMoney(ov.Net), (ov.Net or 0) >= 0 and "GREEN" or "RED", 3)

	sectionTitle(self.scroll, "BUILDINGS", 10)
	statGrid(self.scroll, {
		{ "Houses", st.Houses or 0 },
		{ "Businesses", st.Businesses or 0 },
		{ "Industry", st.Industry or 0 },
		{ "Infrastructure", st.Infrastructure or 0 },
		{ "Military", st.Military or 0 },
		{ "Research", st.Research or 0 },
	}, 11)
	if (st.UnderConstruction or 0) > 0 then
		chip(self.scroll, string.format("%d under construction", st.UnderConstruction), "WARNING", 12)
	end

	sectionTitle(self.scroll, "UTILITIES · WATER", 20)
	local stage = STAGE_LABEL[water.Stage or "NORMAL"] or STAGE_LABEL.NORMAL
	chip(self.scroll, "Supply status: " .. stage[1], stage[2], 21)
	local waterMax = math.max(water.Production or 0, water.Demand or 0, 1)
	meter(self.scroll, "Water Production", water.Production or 0, waterMax, 22, C.Accent)
	meter(self.scroll, "Water Demand", water.Demand or 0, waterMax, 23, C.GrayDark)
	meter(self.scroll, string.format("Water Stored (cap %d)", water.Capacity or 0), math.floor(water.Stored or 0), math.max(water.Capacity or 0, 1), 24, C.AccentDark)
	statusList(self.scroll, s.WaterList or {}, 25, s.ExtraRoads)

	sectionTitle(self.scroll, "UTILITIES · POWER", 30)
	local powerMax = math.max(power.Production or 0, power.Demand or 0, 1)
	local powerOk = (power.Production or 0) >= (power.Demand or 0)
	chip(self.scroll, powerOk and "Power supply: OK" or "Power supply: shortage", powerOk and "GREEN" or "RED", 31)
	meter(self.scroll, "Power Production", power.Production or 0, powerMax, 32, C.Warning)
	meter(self.scroll, "Power Demand", power.Demand or 0, powerMax, 33, C.GrayDark)
	statusList(self.scroll, s.PowerList or {}, 34, s.ExtraRoads)

	sectionTitle(self.scroll, "TRANSPORT", 40)
	statGrid(self.scroll, {
		{ "Road tiles", tr.Roads or st.Roads or 0 },
		{ "Cars on roads", tr.ActiveCars or 0 },
		{ "Last traffic wave", tr.LastWaveCars or 0 },
		{ "Rail tiles", tr.RailTracks or 0 },
		{ "Stations", tr.Stations or 0 },
		{ "Trains running", tr.ActiveTrains or 0 },
		{ "Train trips", tr.TrainTrips or 0 },
		{ "Freight delivered", tr.FreightDelivered or 0 },
	}, 41)

	sectionTitle(self.scroll, "RESOURCES", 50)
	local resources = s.Resources or {}
	for i, r in ipairs(resources) do
		local cap = math.max(r.Capacity or 0, 1)
		local label = r.Label
		if (r.Produced or 0) > 0 or (r.Consumed or 0) > 0 then
			label = string.format("%s  (+%d / -%d per cycle)", r.Label, r.Produced or 0, r.Consumed or 0)
		end
		meter(self.scroll, label, r.Amount or 0, cap, 50 + i, C.AccentDark, string.format("%d / %d", r.Amount or 0, r.Capacity or 0))
	end

	local legend = UIKit.label({
		Text = "✓ green = supplied · ✕ red = shortage · — grey = not required",
		TextSize = T.TextSize.Tiny,
		TextColor3 = C.TextMuted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 90,
		Parent = self.scroll,
	})
	legend.Name = "Legend"
end

-- CITY MAP TAB -------------------------------------------------------------------------------
local OVERLAYS = { "WATER", "POWER", "BUILDINGS", "ROADS" }
local MENU_COLORS = {
	CIVILIAN = Color3.fromRGB(72, 178, 112),
	MILITARY = Color3.fromRGB(222, 92, 92),
	RESEARCH = Color3.fromRGB(128, 104, 226),
}
local ROAD_COLOR = Color3.fromRGB(138, 145, 156)
local RAIL_COLOR = Color3.fromRGB(122, 92, 70)
local GROUND_COLOR = Color3.fromRGB(226, 240, 222)

local function mapRect(parent, x, z, w, d, scale, color, transparency, z_index)
	local f = UIKit.new("Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x * scale, z * scale),
		Size = UDim2.fromOffset(math.max(w * scale, 2), math.max(d * scale, 2)),
		ZIndex = z_index or 2,
		Parent = parent,
	})
	return f
end

local function radiusRing(parent, x, z, radius, scale, color)
	local ring = UIKit.new("Frame", {
		Name = "Radius",
		BackgroundColor3 = color,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x * scale, z * scale),
		Size = UDim2.fromOffset(radius * 2 * scale, radius * 2 * scale),
		ZIndex = 1,
		Parent = parent,
	})
	UIKit.corner(ring, 999)
	UIKit.stroke(ring, color, 1, 0.25)
	return ring
end

function StatsPanel:renderMap()
	local overlayBar = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = 1,
		Parent = self.scroll,
	})
	UIKit.list(overlayBar, Enum.FillDirection.Horizontal, 4)
	for i, id in ipairs(OVERLAYS) do
		local b = UIKit.button({
			Text = id,
			TextSize = T.TextSize.Tiny,
			Style = self.overlay == id and "soft" or "ghost",
			Size = UDim2.new(0.25, -3, 1, 0),
			Radius = 999,
			LayoutOrder = i,
			Parent = overlayBar,
			OnClick = function()
				self.overlay = id
				self:render()
			end,
		})
		b.setSelected(self.overlay == id)
	end

	local frame = UIKit.new("Frame", {
		Name = "CityMap",
		BackgroundColor3 = GROUND_COLOR,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromOffset(MAP_SIZE, MAP_SIZE),
		LayoutOrder = 2,
		Parent = self.scroll,
	})
	UIKit.corner(frame, T.Radius.Small)
	UIKit.stroke(frame, C.Stroke)
	local data = self.mapData
	if not data or not data.ok then
		UIKit.label({
			Text = (data and data.error) or "Loading map…",
			TextSize = T.TextSize.Tiny,
			TextColor3 = C.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Parent = frame,
		})
		return
	end
	local plotSize = math.max(data.PlotSize or 128, 1)
	local tile = data.Tile or 2
	local scale = MAP_SIZE / plotSize
	local overlay = self.overlay
	local emphasizeRoads = overlay == "ROADS"
	-- Roads + rails (real tiles)
	for _, cell in ipairs(data.Roads or {}) do
		mapRect(frame, (cell[1] + 0.5) * tile, (cell[2] + 0.5) * tile, tile, tile, scale, ROAD_COLOR, emphasizeRoads and 0 or 0.35, 2)
	end
	for _, cell in ipairs(data.Rails or {}) do
		mapRect(frame, (cell[1] + 0.5) * tile, (cell[2] + 0.5) * tile, tile, tile, scale, RAIL_COLOR, emphasizeRoads and 0 or 0.35, 2)
	end
	if data.Exit then
		local ex = mapRect(frame, (data.Exit[1] + 0.5) * tile, (data.Exit[2] + 0.5) * tile, tile * 1.6, tile * 1.6, scale, C.Accent, 0, 4)
		UIKit.corner(ex, 999)
	end
	-- Coverage radii (real config radius of each active source)
	for _, b in ipairs(data.Buildings or {}) do
		if overlay == "WATER" and (b.WaterRadius or 0) > 0 then
			radiusRing(frame, b.X, b.Z, b.WaterRadius, scale, C.Accent)
		elseif overlay == "POWER" and (b.PowerRadius or 0) > 0 then
			radiusRing(frame, b.X, b.Z, b.PowerRadius, scale, C.Warning)
		end
	end
	-- Buildings
	for _, b in ipairs(data.Buildings or {}) do
		local color
		local transparency = 0
		if overlay == "WATER" then
			color = (b.WaterRadius or 0) > 0 and C.AccentDark or UIKit.statusColor(b.WaterStatus)
		elseif overlay == "POWER" then
			color = (b.PowerRadius or 0) > 0 and C.Warning or UIKit.statusColor(b.PowerStatus)
		elseif overlay == "ROADS" then
			color = C.GrayDark
			transparency = 0.3
		else
			color = MENU_COLORS[b.Menu] or C.Accent
		end
		if b.State ~= "COMPLETED" then
			transparency = math.max(transparency, 0.55)
		end
		local r = mapRect(frame, b.X, b.Z, b.W, b.D, scale, color, transparency, 3)
		UIKit.corner(r, 2)
	end

	local legendText = {
		WATER = "Blue rings = water tower radius · ■ green supplied · ■ red shortage · ■ grey not required",
		POWER = "Orange rings = power source radius · ■ green supplied · ■ red shortage · ■ grey not required",
		BUILDINGS = "■ green civilian · ■ red military · ■ purple research · faded = under construction",
		ROADS = "■ grey road tiles · ■ brown rail track · ● blue = plot exit",
	}
	UIKit.label({
		Text = legendText[overlay],
		TextSize = T.TextSize.Tiny,
		TextColor3 = C.TextMuted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 3,
		Parent = self.scroll,
	})
	local counts = string.format(
		"%d buildings · %d road tiles · %d rail tiles",
		#(data.Buildings or {}),
		#(data.Roads or {}),
		#(data.Rails or {})
	)
	UIKit.label({
		Text = counts,
		Font = T.Fonts.Bold,
		TextSize = T.TextSize.Tiny,
		TextColor3 = C.Text,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 4,
		Parent = self.scroll,
	})
end

function StatsPanel:requestMap()
	local fetch = self.callbacks.fetchCityMap
	if not fetch or self.mapLoading then
		return
	end
	local now = os.clock()
	if now - self.mapRequestedAt < 0.6 then
		self.mapPending = true
		return
	end
	self.mapRequestedAt = now
	self.mapLoading = true
	task.spawn(function()
		local result = fetch()
		self.mapLoading = false
		if type(result) == "table" and (result.ok or not self.mapData) then
			self.mapData = result
		end
		if self.panel.Visible and self.tab == "CITY MAP" then
			self:render()
		end
		if self.mapPending then
			self.mapPending = false
			task.delay(0.7, function()
				if self.panel.Visible and self.tab == "CITY MAP" then
					self:requestMap()
				end
			end)
		end
	end)
end

function StatsPanel:setTab(id)
	self.tab = id
	for key, button in pairs(self.tabButtons) do
		button.setSelected(key == id)
	end
	if id == "CITY MAP" then
		self:requestMap()
	end
	self:render()
end

function StatsPanel:render()
	clear(self.scroll)
	local s = self.snapshot
	if not s or not s.Active or not s.Stats then
		sectionTitle(self.scroll, "NO ACTIVE COUNTRY", 1)
		return
	end
	if self.tab == "CITY MAP" then
		self:renderMap()
	else
		self:renderStats()
	end
end

function StatsPanel:update(snapshot)
	self.snapshot = snapshot
	if self.panel.Visible then
		if self.tab == "CITY MAP" then
			self:requestMap()
		else
			self:render()
		end
	end
end

function StatsPanel:toggle()
	if self.panel.Visible then
		self:hide()
	else
		self:show()
	end
end

function StatsPanel:show()
	if self.tab == "CITY MAP" then
		self:requestMap()
	end
	self:render()
	UIKit.open(self.panel, 0, 40)
end

function StatsPanel:hide()
	UIKit.close(self.panel, 0, nil, 40)
end

function StatsPanel:isOpen(): boolean
	return self.panel.Visible
end

return StatsPanel
