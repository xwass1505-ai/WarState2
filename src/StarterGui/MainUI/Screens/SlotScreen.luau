-- SlotScreen: exactly 3 save slot cards (Slot 1 FREE, slots 2-3 LOCKED, no monetization yet).
-- Rendered inside the MainMenu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("UIKit"))
local Countries = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("Countries"))
local TechnologyConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("TechnologyConfig"))

local C = UIKit.Theme.Colors
local T = UIKit.Theme

local SlotScreen = {}
SlotScreen.__index = SlotScreen

local ROW_H = 64

local function techName(id)
	for _, branch in ipairs(TechnologyConfig.Branches) do
		if branch.Id == id then
			return branch.DisplayName
		end
	end
	return id or ""
end

function SlotScreen.new(parent: GuiObject, callbacks)
	local self = setmetatable({}, SlotScreen)
	self.callbacks = callbacks
	self.panel = UIKit.new("Frame", {
		Name = "SlotScreen",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})
	UIKit.label({
		Text = "SELECT A SAVE SLOT",
		Font = T.Fonts.Bold,
		TextSize = T.TextSize.Tiny,
		TextColor3 = C.AccentDark,
		Size = UDim2.new(1, 0, 0, 16),
		Parent = self.panel,
	})
	self.rows = UIKit.new("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 3 * ROW_H + 2 * 8),
		Parent = self.panel,
	})
	UIKit.list(self.rows, Enum.FillDirection.Vertical, 8)
	self.note = UIKit.label({
		Text = "",
		TextColor3 = C.TextMuted,
		TextSize = T.TextSize.Tiny,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 22 + 3 * ROW_H + 2 * 8 + 8),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = self.panel,
	})
	self.rowFrames = {}
	return self
end

function SlotScreen:render(profile)
	for _, child in ipairs(self.rows:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	self.rowFrames = {}
	for _, slot in ipairs(profile.slots) do
		local row = UIKit.new("CanvasGroup", {
			Name = "Slot" .. slot.Index,
			BackgroundColor3 = slot.Locked and C.Surface or C.Background,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, ROW_H),
			LayoutOrder = slot.Index,
			Parent = self.rows,
		})
		UIKit.corner(row, T.Radius.Medium)
		local rowStroke = UIKit.stroke(row, C.Stroke)
		UIKit.padding(row, 10, 14)
		table.insert(self.rowFrames, row)
		row.MouseEnter:Connect(function()
			if not slot.Locked then
				UIKit.tween(rowStroke, T.Motion.Fast, { Color = C.Accent })
			end
		end)
		row.MouseLeave:Connect(function()
			UIKit.tween(rowStroke, T.Motion.Fast, { Color = C.Stroke })
		end)

		local title = "SLOT " .. slot.Index
		local subtitle
		if slot.Locked then
			subtitle = "Locked"
		elseif slot.Empty then
			subtitle = "Free · Empty"
		else
			subtitle = string.format("%s · Pop %d", techName(slot.TechnologyBranch), slot.Population or 0)
			title = slot.Name or title
		end

		local flagEntry = (not slot.Empty) and Countries.get(slot.FlagId or "") or nil
		local textX = 0
		if flagEntry then
			local flag = UIKit.flag(row, flagEntry, 26)
			flag.AnchorPoint = Vector2.new(0, 0.5)
			flag.Position = UDim2.fromScale(0, 0.5)
			textX = 46
		else
			local badge = UIKit.new("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.fromOffset(36, 36),
				BackgroundColor3 = slot.Locked and C.Gray or C.AccentSoft,
				BorderSizePixel = 0,
				Parent = row,
			})
			UIKit.corner(badge, 10)
			UIKit.label({
				Text = tostring(slot.Index),
				Font = T.Fonts.Bold,
				TextColor3 = slot.Locked and C.TextMuted or C.AccentDark,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.fromScale(1, 1),
				Parent = badge,
			})
			textX = 48
		end
		UIKit.label({
			Text = title,
			Font = T.Fonts.Bold,
			Position = UDim2.fromOffset(textX, 4),
			Size = UDim2.new(1, -(textX + 150), 0, 20),
			TextColor3 = slot.Locked and C.TextMuted or C.Text,
			Parent = row,
		})
		UIKit.label({
			Text = subtitle,
			TextColor3 = C.TextMuted,
			TextSize = T.TextSize.Small,
			Position = UDim2.fromOffset(textX, 24),
			Size = UDim2.new(1, -(textX + 150), 0, 16),
			Parent = row,
		})

		if slot.Locked then
			local lock = UIKit.button({
				Text = "Locked",
				TextSize = T.TextSize.Small,
				Size = UDim2.fromOffset(84, 32),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Parent = row,
			})
			lock.setDisabled(true)
		elseif slot.Empty then
			UIKit.button({
				Text = "Create",
				Style = "primary",
				TextSize = T.TextSize.Small,
				Size = UDim2.fromOffset(84, 32),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Radius = 999,
				Parent = row,
				OnClick = function()
					self.callbacks.onCreate(slot.Index)
				end,
			})
		else
			UIKit.button({
				Text = "Play",
				Style = "primary",
				TextSize = T.TextSize.Small,
				Size = UDim2.fromOffset(64, 32),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Radius = 999,
				Parent = row,
				OnClick = function()
					self.callbacks.onPlay(slot.Index)
				end,
			})
			local armed = false
			local delete
			delete = UIKit.button({
				Text = "Delete",
				Style = "danger",
				TextSize = T.TextSize.Tiny,
				Size = UDim2.fromOffset(70, 32),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -72, 0.5, 0),
				Radius = 999,
				Parent = row,
				OnClick = function()
					if not armed then
						armed = true
						delete.setText("Confirm")
						task.delay(3, function()
							armed = false
							if delete.Instance.Parent then
								delete.setText("Delete")
							end
						end)
					else
						self.callbacks.onDelete(slot.Index)
					end
				end,
			})
		end
	end
	if profile.persistent then
		self.note.Text = "Progress is saved to your slots."
	else
		self.note.Text = "Saving is OFF this session (Studio API access disabled or DataStore unavailable)."
	end
end

-- Staggered slide + fade of the slot cards.
function SlotScreen:reveal(delay: number?)
	for i, row in ipairs(self.rowFrames) do
		row.GroupTransparency = 1
		task.delay((delay or 0) + (i - 1) * 0.07, function()
			if row.Parent then
				UIKit.tween(row, T.Motion.Slow, { GroupTransparency = 0 })
			end
		end)
	end
end

function SlotScreen:show(profile)
	self:render(profile)
	self:reveal(0)
end

function SlotScreen:hide() end

return SlotScreen
