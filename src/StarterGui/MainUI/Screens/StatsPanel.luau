-- StatsPanel: right-side panel opened by the STATS button. Shows REAL server data only
-- (snapshot.Stats / Water / Power / WaterList / PowerList built by StatsService).
-- Updates whenever the server pushes a new snapshot (build, demolish, completion, new source,
-- coverage or consumption change). Rebuilds only while open.

local UIKit = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("UIKit"))

local C = UIKit.Theme.Colors
local T = UIKit.Theme

local StatsPanel = {}
StatsPanel.__index = StatsPanel

local WIDTH = 300

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
	constraint.MaxSize = Vector2.new(WIDTH, 560)
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
	self.scroll = UIKit.vScroll({
		Name = "Body",
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 1, -32),
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

local function meter(parent, label, value, maxValue, order, fillColor)
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
		Text = tostring(value),
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

function StatsPanel:render()
	for _, child in ipairs(self.scroll:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local s = self.snapshot
	if not s or not s.Active or not s.Stats then
		sectionTitle(self.scroll, "NO ACTIVE COUNTRY", 1)
		return
	end
	local st, water, power = s.Stats, s.Water or {}, s.Power or {}
	sectionTitle(self.scroll, "OVERVIEW", 1)
	statGrid(self.scroll, {
		{ "Population", string.format("%d / %d", st.Population, st.HousingCapacity) },
		{ "Buildings", st.Buildings },
		{ "Houses", st.Houses },
		{ "Businesses", st.Businesses },
		{ "Factories", st.Factories },
		{ "Roads", st.Roads },
		{ "Water Towers", st.WaterTowers },
		{ "Power Sources", st.PowerSources },
	}, 2)

	sectionTitle(self.scroll, "WATER", 10)
	local stage = STAGE_LABEL[water.Stage or "NORMAL"] or STAGE_LABEL.NORMAL
	local chip = UIKit.new("Frame", {
		BackgroundColor3 = stage[2] == "GREEN" and C.SuccessSoft or (stage[2] == "WARNING" and C.WarningSoft or C.DangerSoft),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 11,
		Parent = self.scroll,
	})
	UIKit.corner(chip, 999)
	UIKit.label({
		Text = "Supply status: " .. stage[1],
		Font = T.Fonts.Bold,
		TextSize = T.TextSize.Tiny,
		TextColor3 = stage[2] == "GREEN" and C.Success or (stage[2] == "WARNING" and C.Warning or C.Danger),
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = chip,
	})
	local waterMax = math.max(water.Production or 0, water.Demand or 0, 1)
	meter(self.scroll, "Water Production", water.Production or 0, waterMax, 12, C.Accent)
	meter(self.scroll, "Water Demand", water.Demand or 0, waterMax, 13, C.GrayDark)
	meter(self.scroll, string.format("Water Stored (cap %d)", water.Capacity or 0), math.floor(water.Stored or 0), math.max(water.Capacity or 0, 1), 14, C.AccentDark)
	statusList(self.scroll, s.WaterList or {}, 15, s.ExtraRoads)

	sectionTitle(self.scroll, "POWER", 20)
	local powerMax = math.max(power.Production or 0, power.Demand or 0, 1)
	meter(self.scroll, "Power Production", power.Production or 0, powerMax, 21, C.Warning)
	meter(self.scroll, "Power Demand", power.Demand or 0, powerMax, 22, C.GrayDark)
	statusList(self.scroll, s.PowerList or {}, 23, s.ExtraRoads)

	local legend = UIKit.label({
		Text = "✓ green = supplied · ✕ red = problem · — grey = not required",
		TextSize = T.TextSize.Tiny,
		TextColor3 = C.TextMuted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 30,
		Parent = self.scroll,
	})
	legend.Name = "Legend"
end

function StatsPanel:update(snapshot)
	self.snapshot = snapshot
	if self.panel.Visible then
		self:render()
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
