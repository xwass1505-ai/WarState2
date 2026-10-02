-- PlotScreen: PLOT SELECTION. Shows the map (central island + 6 player islands) and lets the
-- player claim a FREE plot. Occupied plots cannot be selected. The server re-validates the claim.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("UIKit"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Countries = require(Shared:WaitForChild("Modules"):WaitForChild("Countries"))

local C = UIKit.Theme.Colors
local T = UIKit.Theme

local PlotScreen = {}
PlotScreen.__index = PlotScreen

local DESIGN_W, DESIGN_H = 580, 392
local MAP_PX = 320

function PlotScreen.new(root: ScreenGui, callbacks)
	local self = setmetatable({}, PlotScreen)
	self.callbacks = callbacks
	self.plots = {}
	self.selected = nil
	self.buttons = {}

	self.panel = UIKit.panel({
		Name = "PlotScreen",
		Canvas = true,
		Radius = T.Radius.Large,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(DESIGN_W, DESIGN_H),
		Visible = false,
		Parent = root,
	})
	UIKit.autoScale(self.panel, DESIGN_W, DESIGN_H)
	UIKit.padding(self.panel, 18)

	UIKit.label({
		Text = "Choose your plot",
		Font = T.Fonts.Bold,
		TextSize = T.TextSize.Header,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = self.panel,
	})
	self.subtitle = UIKit.label({
		Text = "Pick a free island. Your country will be built there.",
		TextColor3 = C.TextMuted,
		TextSize = T.TextSize.Small,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = self.panel,
	})

	-- Map ------------------------------------------------------------------------------------
	self.map = UIKit.new("Frame", {
		Name = "Map",
		BackgroundColor3 = Color3.fromRGB(214, 234, 250),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.fromOffset(MAP_PX, MAP_PX - 24),
		ClipsDescendants = true,
		Parent = self.panel,
	})
	UIKit.corner(self.map, T.Radius.Medium)
	UIKit.stroke(self.map, C.Stroke)

	local extent = 0
	for _, p in ipairs(GameConfig.Map.Plots) do
		extent = math.max(extent, math.abs(p.CenterX), math.abs(p.CenterZ))
	end
	local islandSize = GameConfig.Territory.Size + GameConfig.Territory.RimWidth * 2
	extent += islandSize / 2 + 20
	local mapW, mapH = MAP_PX, MAP_PX - 24
	local scale = math.min(mapW, mapH) / (extent * 2)
	local function toMap(x, z)
		return UDim2.fromOffset(mapW / 2 + x * scale, mapH / 2 + z * scale)
	end
	local central = GameConfig.Map.CentralIsland
	local centralFrame = UIKit.new("Frame", {
		Name = "CentralIsland",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = toMap(central.CenterX, central.CenterZ),
		Size = UDim2.fromOffset(central.Size * scale, central.Size * scale),
		BackgroundColor3 = Color3.fromRGB(196, 222, 184),
		BorderSizePixel = 0,
		Parent = self.map,
	})
	UIKit.corner(centralFrame, 18)
	UIKit.label({
		Text = "CENTRAL",
		Font = T.Fonts.Bold,
		TextSize = T.TextSize.Tiny,
		TextColor3 = Color3.fromRGB(96, 128, 90),
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = centralFrame,
	})

	for _, p in ipairs(GameConfig.Map.Plots) do
		local b
		b = UIKit.button({
			Name = "Plot" .. p.Index,
			Text = "",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = toMap(p.CenterX, p.CenterZ),
			Size = UDim2.fromOffset(islandSize * scale, islandSize * scale),
			Radius = 12,
			Style = "ghost",
			Parent = self.map,
			OnClick = function()
				self:select(p.Index)
			end,
		})
		local title = UIKit.label({
			Name = "Title",
			Text = "P" .. p.Index,
			Font = T.Fonts.Bold,
			TextSize = T.TextSize.Body,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 18),
			Parent = b.Instance,
		})
		local status = UIKit.label({
			Name = "Status",
			Text = "Free",
			TextSize = T.TextSize.Tiny,
			TextColor3 = C.Success,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(2, 28),
			Size = UDim2.new(1, -4, 0, 14),
			Parent = b.Instance,
		})
		self.buttons[p.Index] = { api = b, title = title, status = status }
	end

	-- Details --------------------------------------------------------------------------------
	local side = UIKit.new("Frame", {
		Name = "Details",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(MAP_PX + 16, 54),
		Size = UDim2.new(1, -(MAP_PX + 16), 1, -54),
		Parent = self.panel,
	})
	self.detailTitle = UIKit.label({
		Text = "No plot selected",
		Font = T.Fonts.Bold,
		TextSize = T.TextSize.Title,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = side,
	})
	self.detailStatus = UIKit.label({
		Text = "Tap an island on the map",
		TextColor3 = C.TextMuted,
		TextSize = T.TextSize.Small,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 34),
		Parent = side,
	})
	UIKit.label({
		Text = "Each plot has its own exit and bridge to the central island (future land battles).",
		TextColor3 = C.TextMuted,
		TextSize = T.TextSize.Tiny,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 0, 44),
		Parent = side,
	})
	self.error = UIKit.label({
		Text = "",
		TextColor3 = C.Danger,
		TextSize = T.TextSize.Small,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -92),
		Size = UDim2.new(1, 0, 0, 32),
		Parent = side,
	})
	self.claimButton = UIKit.button({
		Text = "Claim plot",
		Style = "primary",
		TextSize = T.TextSize.Small,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -46),
		Size = UDim2.new(1, 0, 0, 38),
		Radius = 999,
		Parent = side,
		OnClick = function()
			self:claim()
		end,
	})
	self.claimButton.setDisabled(true)
	UIKit.button({
		Text = "Back to menu",
		TextSize = T.TextSize.Small,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 36),
		Radius = 999,
		Style = "ghost",
		Parent = side,
		OnClick = function()
			if not self.claiming then
				self.callbacks.onBack()
			end
		end,
	})
	return self
end

function PlotScreen:setPlots(plots)
	self.plots = {}
	for _, info in ipairs(plots or {}) do
		self.plots[info.Index] = info
	end
	for index, entry in pairs(self.buttons) do
		local info = self.plots[index]
		local free = info == nil or info.Free
		entry.api.setDisabled(not free)
		entry.api.setSelected(free and self.selected == index)
		if free then
			entry.status.Text = "Free"
			entry.status.TextColor3 = C.Success
			entry.title.TextColor3 = C.Text
		else
			local flag = Countries.get(info.FlagId or "")
			entry.status.Text = (flag and flag.EmojiFallback .. " " or "") .. tostring(info.OwnerName or "Taken")
			entry.status.TextColor3 = C.TextMuted
			entry.title.TextColor3 = C.TextMuted
		end
	end
	if self.selected and not (self.plots[self.selected] == nil or self.plots[self.selected].Free) then
		self.selected = nil
		self:setError("That plot was just taken. Pick another one.")
	end
	self:renderDetails()
end

function PlotScreen:setError(text: string?)
	self.error.Text = text or ""
end

function PlotScreen:renderDetails()
	local index = self.selected
	if not index then
		self.detailTitle.Text = "No plot selected"
		self.detailStatus.Text = "Tap a free island on the map"
		self.claimButton.setDisabled(true)
		return
	end
	self.detailTitle.Text = "Plot " .. index
	self.detailStatus.Text = "Free · ready to claim"
	self.claimButton.setDisabled(self.claiming == true)
end

function PlotScreen:select(index: number)
	local info = self.plots[index]
	if info and not info.Free then
		self:setError("Plot " .. index .. " is owned by " .. tostring(info.OwnerName))
		return
	end
	self:setError(nil)
	self.selected = index
	for i, entry in pairs(self.buttons) do
		entry.api.setSelected(i == index)
	end
	self:renderDetails()
end

function PlotScreen:claim()
	if self.claiming or not self.selected then
		return
	end
	self.claiming = true
	self.claimButton.setText("Claiming...")
	self.claimButton.setDisabled(true)
	local index = self.selected
	task.spawn(function()
		local result = self.callbacks.onClaim(index)
		self.claiming = false
		self.claimButton.setText("Claim plot")
		if result and result.ok then
			self:hide()
		else
			self:setError(result and result.error or "Could not claim plot")
			if result and result.plots then
				self:setPlots(result.plots)
			end
			self:renderDetails()
		end
	end)
end

function PlotScreen:show(plots, preferredIndex: number?)
	self.selected = nil
	self.claiming = false
	self:setError(nil)
	self:setPlots(plots)
	if preferredIndex and self.plots[preferredIndex] and self.plots[preferredIndex].Free then
		self:select(preferredIndex)
	end
	UIKit.open(self.panel, 16)
end

function PlotScreen:hide()
	UIKit.close(self.panel, 16)
end

function PlotScreen:isOpen(): boolean
	return self.panel.Visible
end

return PlotScreen
