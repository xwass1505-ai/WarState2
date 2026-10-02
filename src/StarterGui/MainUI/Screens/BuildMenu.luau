-- BuildMenu: wide panel that opens from the BOTTOM. Main categories run VERTICALLY on the left and are
-- ONLY: CIVILIAN (green accent), MILITARY (red accent), RESEARCH (blue/purple accent).
-- Each category has sub-groups (chips) and horizontally scrolling building cards:
--   model preview, name, cost, income, expense, population / water / power requirement.
-- Locked cards show "Population X required"; the small BUILD button (hammer icon, hover + press)
-- is disabled while locked or unaffordable. The server re-checks everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("UIKit"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Modules = Shared:WaitForChild("Modules")
local BuildMenuConfig = require(Config:WaitForChild("BuildMenuConfig"))
local BuildingConfig = require(Config:WaitForChild("BuildingConfig"))
local RoadConfig = require(Config:WaitForChild("RoadConfig"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local BuildingModels = require(Modules:WaitForChild("BuildingModels"))
local RoadModels = require(Modules:WaitForChild("RoadModels"))
local VehicleModels = require(Modules:WaitForChild("VehicleModels"))
local EconomyRules = require(Modules:WaitForChild("EconomyRules"))
require(Modules:WaitForChild("ExtraModels"))

local C = UIKit.Theme.Colors
local T = UIKit.Theme

local BuildMenu = {}
BuildMenu.__index = BuildMenu

local DESIGN_W, DESIGN_H = 800, 268
local SIDE_W = 138
local CARD_W, CARD_H = 140, 196

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function resourceLabel(key: string): string
	if key == "Treasury" then
		return "$"
	end
	return (GameConfig.Resources.DisplayNames[key] or key) .. " "
end

local function costText(cost, multiplierText: string?): string
	local parts = {}
	local treasury = cost and cost.Treasury or 0
	if treasury > 0 then
		table.insert(parts, "$" .. tostring(treasury))
	end
	for key, amount in pairs(cost or {}) do
		if key ~= "Treasury" and amount > 0 then
			table.insert(parts, resourceLabel(key) .. tostring(amount))
		end
	end
	if #parts == 0 then
		return "Free" .. (multiplierText or "")
	end
	return table.concat(parts, " · ") .. (multiplierText or "")
end

local function itemsForGroup(groupId: string)
	local items = {}
	for _, tool in ipairs(BuildMenuConfig.DrawTools) do
		if tool.Group == groupId then
			if tool.Kind == "Road" then
				local road = RoadConfig.Types[1]
				table.insert(items, {
					Kind = "Road",
					Id = road.Id,
					Name = road.DisplayName,
					Cost = road.Cost,
					PerTile = true,
					Expense = string.format("-1 per %d tiles", GameConfig.Economy.RoadTilesPerExpense),
				})
			elseif tool.Kind == "Rail" then
				local track = GameConfig.Railway.Track
				table.insert(items, {
					Kind = "Rail",
					Id = track.Id,
					Name = track.DisplayName,
					Cost = track.Cost,
					PerTile = true,
					Expense = string.format("-1 per %d tiles", GameConfig.Economy.RailTilesPerExpense),
				})
			end
		end
	end
	for _, def in ipairs(BuildingConfig.Buildings) do
		if def.Category == groupId and def.Active then
			table.insert(items, { Kind = "Building", Id = def.Id, Name = def.DisplayName, Cost = def.Cost, Def = def })
		end
	end
	return items
end

local function viewport(parent, item)
	local frame = UIKit.new("ViewportFrame", {
		BackgroundColor3 = C.SurfaceAlt,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 66),
		Ambient = Color3.fromRGB(205, 210, 220),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -2, -1),
		Parent = parent,
	})
	UIKit.corner(frame, 8)
	local model
	if item.Kind == "Road" then
		model = RoadModels.build(item.Id, "NS")
	elseif item.Kind == "Rail" then
		model = VehicleModels.railTile("NS")
	else
		model = BuildingModels.build(item.Def, item.Def.Variants[1])
	end
	model.Parent = frame
	local cf, size = model:GetBoundingBox()
	local radius = math.max(size.Magnitude / 2, 0.5)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local direction = Vector3.new(1, 0.9, 1.2).Unit
	camera.CFrame = CFrame.lookAt(cf.Position + direction * radius * 3.4, cf.Position)
	camera.Parent = frame
	frame.CurrentCamera = camera
	return frame
end

-- Small BUILD button with a hammer icon (hover tilts the hammer, press squishes).
local function buildButton(parent, onClick)
	local b = UIKit.button({
		Name = "BuildButton",
		Text = "",
		Style = "primary",
		Size = UDim2.fromOffset(74, 24),
		Radius = 999,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Parent = parent,
		OnClick = onClick,
	})
	local icon = UIKit.hammerIcon(b.Instance, 13, C.TextOnAccent)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 10, 0.5, 0)
	local caption = UIKit.label({
		Text = "BUILD",
		Font = T.Fonts.Bold,
		TextSize = T.TextSize.Tiny,
		TextColor3 = C.TextOnAccent,
		Position = UDim2.fromOffset(27, 0),
		Size = UDim2.new(1, -30, 1, 0),
		Parent = b.Instance,
	})
	b.Instance.MouseEnter:Connect(function()
		if not b.isDisabled() then
			UIKit.tween(icon, T.Motion.Normal, { Rotation = -22 }, Enum.EasingStyle.Back)
		end
	end)
	b.Instance.MouseLeave:Connect(function()
		UIKit.tween(icon, T.Motion.Normal, { Rotation = 0 })
	end)
	b.Instance.Activated:Connect(function()
		if not b.isDisabled() then
			icon.Rotation = -35
			UIKit.tween(icon, T.Motion.Slow, { Rotation = 0 }, Enum.EasingStyle.Back)
		end
	end)
	b.caption = caption
	b.icon = icon
	return b
end

function BuildMenu.new(root: ScreenGui, callbacks)
	local self = setmetatable({}, BuildMenu)
	self.callbacks = callbacks
	self.state = { Population = 0, Treasury = 0 }
	self.categoryButtons = {}
	self.groupButtons = {}
	self.cards = {}
	self.currentCategory = BuildMenuConfig.Categories[1].Id
	self.currentGroup = nil

	self.panel = UIKit.panel({
		Name = "BuildMenu",
		Radius = T.Radius.Large,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(DESIGN_W, DESIGN_H),
		Visible = false,
		Parent = root,
	})
	UIKit.autoScale(self.panel, DESIGN_W, DESIGN_H + 40)

	-- LEFT: vertical main categories -----------------------------------------------------------
	self.side = UIKit.new("Frame", {
		Name = "Categories",
		BackgroundColor3 = C.Surface,
		BorderSizePixel = 0,
		Size = UDim2.new(0, SIDE_W, 1, 0),
		Parent = self.panel,
	})
	UIKit.corner(self.side, T.Radius.Large)
	UIKit.padding(self.side, 10, 10)
	UIKit.list(self.side, Enum.FillDirection.Vertical, 8)
	local badge = UIKit.new("Frame", {
		BackgroundColor3 = C.AccentSoft,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 0,
		Parent = self.side,
	})
	UIKit.corner(badge, 999)
	local icon = UIKit.hammerIcon(badge, 14, C.AccentDark)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 10, 0.5, 0)
	UIKit.label({
		Text = "BUILD",
		Font = T.Fonts.Bold,
		TextSize = T.TextSize.Tiny,
		TextColor3 = C.AccentDark,
		Position = UDim2.fromOffset(30, 0),
		Size = UDim2.new(1, -32, 1, 0),
		Parent = badge,
	})
	for i, category in ipairs(BuildMenuConfig.Categories) do
		local accent = rgb(category.Accent)
		local b = UIKit.button({
			Name = category.Id,
			Text = "",
			Style = "ghost",
			Size = UDim2.new(1, 0, 0, 52),
			Radius = T.Radius.Medium,
			LayoutOrder = i,
			Parent = self.side,
			OnClick = function()
				self:selectCategory(category.Id)
			end,
		})
		local bar = UIKit.new("Frame", {
			Name = "Accent",
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Size = UDim2.fromOffset(4, 26),
			Parent = b.Instance,
		})
		UIKit.corner(bar, 999)
		UIKit.label({
			Text = string.upper(category.DisplayName),
			Font = T.Fonts.Bold,
			TextSize = T.TextSize.Small,
			TextColor3 = C.Text,
			Position = UDim2.fromOffset(18, 8),
			Size = UDim2.new(1, -22, 0, 18),
			Parent = b.Instance,
		})
		UIKit.label({
			Text = string.format("%d groups", #category.Groups),
			TextSize = T.TextSize.Tiny,
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(18, 27),
			Size = UDim2.new(1, -22, 0, 14),
			Parent = b.Instance,
		})
		self.categoryButtons[category.Id] = { api = b, bar = bar, accent = accent }
	end

	-- RIGHT: groups + cards ----------------------------------------------------------------------
	self.body = UIKit.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(SIDE_W + 10, 10),
		Size = UDim2.new(1, -SIDE_W - 20, 1, -20),
		Parent = self.panel,
	})
	UIKit.button({
		Text = "Close",
		TextSize = T.TextSize.Small,
		Style = "ghost",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(60, 28),
		Radius = 999,
		Parent = self.body,
		OnClick = function()
			self:hide()
			self.callbacks.onClose()
		end,
	})
	self.groups = UIKit.hScroll({
		Name = "Groups",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, -70, 0, 30),
		Spacing = 6,
		Parent = self.body,
	})
	self.items = UIKit.hScroll({
		Name = "Items",
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		Spacing = 8,
		Parent = self.body,
	})
	return self
end

local function categoryById(id: string)
	for _, category in ipairs(BuildMenuConfig.Categories) do
		if category.Id == id then
			return category
		end
	end
	return BuildMenuConfig.Categories[1]
end

function BuildMenu:selectCategory(categoryId: string)
	self.currentCategory = categoryId
	local category = categoryById(categoryId)
	for id, entry in pairs(self.categoryButtons) do
		local selected = id == categoryId
		entry.api.setSelected(selected)
		UIKit.tween(entry.bar, T.Motion.Normal, { Size = UDim2.fromOffset(4, selected and 36 or 22) })
	end
	for _, child in ipairs(self.groups:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	self.groupButtons = {}
	for i, groupId in ipairs(category.Groups) do
		local b = UIKit.button({
			Text = BuildMenuConfig.Groups[groupId] or groupId,
			TextSize = T.TextSize.Tiny,
			Size = UDim2.fromOffset(96, 26),
			Radius = 999,
			LayoutOrder = i,
			Parent = self.groups,
			OnClick = function()
				self:selectGroup(groupId)
			end,
		})
		self.groupButtons[groupId] = b
	end
	self:selectGroup(category.Groups[1])
end

function BuildMenu:cardState(item)
	local population = self.state.Population or 0
	if item.Def and not EconomyRules.isUnlocked(item.Def, population) then
		return "locked", EconomyRules.unlockText(item.Def)
	end
	local ok, missing = EconomyRules.canAfford(self.state, item.Cost or {}, 1)
	if not ok then
		return "poor", "Not enough " .. (GameConfig.Resources.DisplayNames[missing or ""] or missing or "Treasury")
	end
	return "ok", nil
end

local function infoLine(parent, text, y, color)
	return UIKit.label({
		Text = text,
		TextColor3 = color or C.TextMuted,
		TextSize = T.TextSize.Tiny,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = parent,
	})
end

function BuildMenu:makeCard(item, order: number)
	local card = UIKit.new("Frame", {
		Name = item.Id,
		BackgroundColor3 = C.Background,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		LayoutOrder = order,
		Parent = self.items,
	})
	UIKit.corner(card, T.Radius.Medium)
	local stroke = UIKit.stroke(card, C.Stroke)
	UIKit.padding(card, 7)
	local scale = Instance.new("UIScale")
	scale.Parent = card
	card.MouseEnter:Connect(function()
		UIKit.tween(scale, T.Motion.Fast, { Scale = 1.02 })
		UIKit.tween(stroke, T.Motion.Fast, { Color = C.Accent })
	end)
	card.MouseLeave:Connect(function()
		UIKit.tween(scale, T.Motion.Fast, { Scale = 1 })
		UIKit.tween(stroke, T.Motion.Fast, { Color = C.Stroke })
	end)
	viewport(card, item)
	UIKit.label({
		Text = item.Name,
		Font = T.Fonts.Bold,
		TextSize = T.TextSize.Small,
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = card,
	})
	local def = item.Def
	local cost = infoLine(card, "Cost " .. costText(item.Cost, item.PerTile and " / tile" or ""), 88, C.Text)
	if def then
		local income = def.IncomePerCycle or 0
		local expense = def.ExpensePerCycle or 0
		infoLine(card, string.format("Income +%d · Expense -%d", income, expense), 102, income > 0 and C.Success or C.TextMuted)
		infoLine(card, string.format("Pop %d · Water %d · Power %d", def.PopulationRequired or 0, def.Water.Required or 0, def.Power.Required or 0), 116)
		local extra = ""
		if def.HousingCapacity and def.HousingCapacity > 0 then
			extra = string.format("+%d homes", def.HousingCapacity)
		elseif def.Water and (def.Water.Production or 0) > 0 then
			extra = string.format("Water %d · radius %d", def.Water.Production, def.Water.Radius)
		elseif def.Power and (def.Power.Production or 0) > 0 then
			extra = string.format("Power %d · radius %d", def.Power.Production, def.Power.Radius)
		elseif def.Production then
			local outs = {}
			for key, amount in pairs(def.Production.Outputs) do
				table.insert(outs, string.format("+%d %s", amount, GameConfig.Resources.DisplayNames[key] or key))
			end
			extra = table.concat(outs, ", ") .. " / cycle"
		elseif (def.ResearchPerCycle or 0) > 0 then
			extra = string.format("+%d research / cycle", def.ResearchPerCycle)
		elseif (def.StorageCapacity or 0) > 0 then
			extra = string.format("+%d storage", def.StorageCapacity)
		end
		infoLine(card, extra .. (extra ~= "" and " · " or "") .. tostring(def.BuildTimeSeconds) .. "s", 130)
	else
		infoLine(card, "Expense " .. (item.Expense or "-"), 102)
		infoLine(card, "Hold + drag to draw", 116)
	end
	local lockLabel = infoLine(card, "", 146, C.Danger)
	lockLabel.Font = T.Fonts.Bold
	local button = buildButton(card, function()
		local state = self:cardState(item)
		if state == "ok" then
			self:hide()
			self.callbacks.onSelect(item.Kind, item.Id)
		end
	end)
	local entry = { item = item, card = card, cost = cost, lock = lockLabel, button = button, scale = scale }
	self.cards[item.Id] = entry
	self:refreshCard(entry)
	scale.Scale = 0.86
	task.delay(0.025 * order, function()
		if card.Parent then
			UIKit.tween(scale, T.Motion.Normal, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end)
	return entry
end

function BuildMenu:refreshCard(entry)
	local state, reason = self:cardState(entry.item)
	entry.lock.Text = reason or ""
	entry.button.setDisabled(state ~= "ok")
	entry.button.caption.TextColor3 = state == "ok" and C.TextOnAccent or C.TextMuted
	entry.card.BackgroundColor3 = state == "locked" and C.Surface or C.Background
	entry.cost.TextColor3 = state == "poor" and C.Danger or C.Text
end

function BuildMenu:selectGroup(groupId: string)
	self.currentGroup = groupId
	for id, b in pairs(self.groupButtons) do
		b.setSelected(id == groupId)
	end
	for _, child in ipairs(self.items:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	self.cards = {}
	self.items.CanvasPosition = Vector2.new(0, 0)
	local items = itemsForGroup(groupId)
	if #items == 0 then
		UIKit.label({
			Text = "Nothing here yet",
			TextColor3 = C.TextMuted,
			TextSize = T.TextSize.Small,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(DESIGN_W - SIDE_W - 40, 120),
			Parent = self.items,
		})
		return
	end
	for i, item in ipairs(items) do
		self:makeCard(item, i)
	end
end

-- Snapshot from the server (population / treasury / resources) -> lock + affordability states.
function BuildMenu:setState(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	self.state = snapshot
	if self.panel.Visible then
		for _, entry in pairs(self.cards) do
			self:refreshCard(entry)
		end
	end
end

function BuildMenu:show(categoryId: string?)
	self:selectCategory(categoryId or self.currentCategory)
	UIKit.open(self.panel, 30)
end

function BuildMenu:hide()
	UIKit.close(self.panel, 30)
end

function BuildMenu:isOpen(): boolean
	return self.panel.Visible
end

return BuildMenu
