-- WorldService: owns the STATIC map and plot ownership.
-- The map (central island, 6 player islands, exits, bridges, trees, bushes, rocks, dirt paths,
-- invisible boundaries, lobby spawn) is part of the place file: tools/gen_static_map.py writes it
-- to src/Workspace/Map and the real `rojo build` puts it into build/WarState.rbxlx.
-- Nothing is generated on PlayerAdded. At server start (before any player can join) this service
-- only: fills real Terrain water (Rojo cannot serialize terrain voxels), validates the static map
-- and attaches the owner panels (BillboardGui) to the static OwnerSign anchors.
-- Plots are NEVER auto-assigned: the player picks a free plot after creating/loading a country.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Theme = require(Config:WaitForChild("ThemeConfig"))
local Constants = require(Shared:WaitForChild("Constants"):WaitForChild("Constants"))
local Plots = require(Shared:WaitForChild("Modules"):WaitForChild("Plots"))
local Countries = require(Shared:WaitForChild("Modules"):WaitForChild("Countries"))

local WorldService = {}
WorldService.Name = "WorldService"

local services
local remotes
local plotOwners = {} -- [index] = { player = Player, countryName = string, flagId = string }
local playerPlots = {} -- [Player] = index
local plotModels = {} -- [index] = Model (static, from the place file)
local signs = {} -- [index] = { gui, name, flag, flagImage, country }
local mapReport = { ok = false, missing = {} }

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- Runtime containers only (buildings / roads / vehicles / NPCs). Declared in default.project.json,
-- created here only when the place was opened without Rojo.
local function rootFolders()
	return {
		Buildings = ensureFolder(Workspace, "Buildings"),
		Roads = ensureFolder(Workspace, "Roads"),
		Vehicles = ensureFolder(Workspace, "Vehicles"),
		NPCs = ensureFolder(Workspace, "NPCs"),
	}
end

-- TERRAIN WATER -------------------------------------------------------------------------------
-- Real Roblox Terrain water + sand seabed, filled once at server start in 256-stud chunks.
function WorldService.fillTerrainWater()
	if Workspace:GetAttribute("WarStateWaterFilled") then
		return
	end
	local cfg = GameConfig.Map.Terrain
	local terrain = Workspace.Terrain
	local half = cfg.HalfSize
	local top, bottom = cfg.WaterTopY, cfg.SeabedY
	local sand = cfg.SeabedThickness
	local chunk = 256
	local x = -half
	while x < half do
		local sx = math.min(chunk, half - x)
		local z = -half
		while z < half do
			local sz = math.min(chunk, half - z)
			local cx, cz = x + sx / 2, z + sz / 2
			terrain:FillBlock(CFrame.new(cx, bottom - sand / 2, cz), Vector3.new(sx, sand, sz), Enum.Material.Sand)
			terrain:FillBlock(CFrame.new(cx, (top + bottom) / 2, cz), Vector3.new(sx, top - bottom, sz), Enum.Material.Water)
			z += chunk
		end
		x += chunk
	end
	Workspace:SetAttribute("WarStateWaterFilled", true)
	Workspace:SetAttribute("WarStateWaterTopY", top)
end

-- STATIC MAP ----------------------------------------------------------------------------------
local function validateStaticMap()
	local missing = {}
	local map = Workspace:FindFirstChild("Map")
	if not map then
		table.insert(missing, "Workspace.Map")
	else
		for _, name in ipairs({ "CentralIsland", "Boundaries", "Plots" }) do
			if not map:FindFirstChild(name) then
				table.insert(missing, "Map." .. name)
			end
		end
		local plotsFolder = map:FindFirstChild("Plots")
		for index = 1, Plots.maxPlots() do
			local model = plotsFolder and plotsFolder:FindFirstChild("Plot_" .. index)
			if not model then
				table.insert(missing, "Map.Plots.Plot_" .. index)
			else
				plotModels[index] = model
				local ground = model:FindFirstChild("Ground")
				if ground and ground:IsA("BasePart") then
					model.PrimaryPart = ground
				else
					table.insert(missing, "Plot_" .. index .. ".Ground")
				end
				if not model:FindFirstChild("Exit") then
					table.insert(missing, "Plot_" .. index .. ".Exit")
				end
			end
		end
	end
	mapReport = { ok = #missing == 0, missing = missing }
	if #missing > 0 then
		warn(
			"[WorldService] Static map incomplete: "
				.. table.concat(missing, ", ")
				.. ". Run `python tools/gen_static_map.py` and rebuild with `rojo build`."
		)
	end
	return mapReport
end

function WorldService.getMapReport()
	return mapReport
end

-- OWNER PANELS --------------------------------------------------------------------------------
local function createSign(index: number, plotModel: Model, bounds)
	local anchor = plotModel:FindFirstChild("OwnerSign")
	if not anchor then
		anchor = Instance.new("Part")
		anchor.Name = "OwnerSign"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.CFrame = CFrame.new(bounds.centerX, bounds.surfaceY + 20, bounds.centerZ)
		anchor.Parent = plotModel
	end
	local old = anchor:FindFirstChild("OwnerPanel")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "OwnerPanel"
	gui.Size = UDim2.fromOffset(190, 88)
	gui.MaxDistance = 900
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	gui.Adornee = anchor
	gui.Parent = anchor

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Theme.Colors.Background
	card.BackgroundTransparency = 0.04
	card.BorderSizePixel = 0
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Accent
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = card

	local function text(name, y, h, font, size, col)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.new(0, 8, 0, y)
		l.Size = UDim2.new(1, -16, 0, h)
		l.Font = font
		l.TextSize = size
		l.TextColor3 = col
		l.TextTruncate = Enum.TextTruncate.AtEnd
		l.Text = ""
		l.Parent = card
		return l
	end
	local nameLabel = text("PlayerName", 6, 18, Theme.Fonts.Bold, 14, Theme.Colors.Text)
	local flagLabel = text("Flag", 25, 28, Theme.Fonts.Regular, 24, Theme.Colors.Text)
	local flagImage = Instance.new("ImageLabel")
	flagImage.Name = "FlagImage"
	flagImage.BackgroundTransparency = 1
	flagImage.AnchorPoint = Vector2.new(0.5, 0)
	flagImage.Position = UDim2.new(0.5, 0, 0, 27)
	flagImage.Size = UDim2.fromOffset(36, 24)
	flagImage.ScaleType = Enum.ScaleType.Crop
	flagImage.Visible = false
	flagImage.Parent = card
	local countryLabel = text("CountryName", 60, 20, Theme.Fonts.Medium, 13, Theme.Colors.AccentDark)
	signs[index] = { gui = gui, name = nameLabel, flag = flagLabel, flagImage = flagImage, country = countryLabel }
end

local function updateSign(index: number)
	local sign = signs[index]
	if not sign then
		return
	end
	local owner = plotOwners[index]
	if owner then
		sign.name.Text = owner.player.Name
		local entry = Countries.get(owner.flagId or "")
		if entry and Countries.hasRealFlag(entry) then
			sign.flagImage.Image = entry.FlagAsset
			sign.flagImage.Visible = true
			sign.flag.Text = ""
		else
			sign.flagImage.Visible = false
			sign.flag.Text = entry and entry.EmojiFallback or ""
		end
		sign.country.Text = owner.countryName or ""
	else
		sign.name.Text = "PLOT " .. index
		sign.flagImage.Visible = false
		sign.flag.Text = ""
		sign.country.Text = "Free"
	end
end

-- OWNERSHIP ----------------------------------------------------------------------------------
local function createPlotFolders(index: number, owner: Player)
	local folders = rootFolders()
	for _, key in ipairs({ "Buildings", "Roads", "Vehicles" }) do
		local plotFolderName = "Plot_" .. index
		local old = folders[key]:FindFirstChild(plotFolderName)
		if old then
			old:Destroy()
		end
		local folder = Instance.new("Folder")
		folder.Name = plotFolderName
		folder:SetAttribute(Constants.Attributes.PlotIndex, index)
		folder:SetAttribute(Constants.Attributes.OwnerUserId, owner.UserId)
		folder.Parent = folders[key]
	end
end

local function destroyPlotFolders(index: number)
	local folders = rootFolders()
	for _, key in ipairs({ "Buildings", "Roads", "Vehicles" }) do
		local inst = folders[key]:FindFirstChild("Plot_" .. index)
		if inst then
			inst:Destroy()
		end
	end
end

local function broadcast()
	if remotes and remotes[Constants.Remotes.PlotsChanged] then
		remotes[Constants.Remotes.PlotsChanged]:FireAllClients(WorldService.listPlots())
	end
end

function WorldService.listPlots()
	local list = {}
	for index = 1, Plots.maxPlots() do
		local owner = plotOwners[index]
		table.insert(list, {
			Index = index,
			Free = owner == nil,
			OwnerName = owner and owner.player.Name or nil,
			OwnerUserId = owner and owner.player.UserId or nil,
			CountryName = owner and owner.countryName or nil,
			FlagId = owner and owner.flagId or nil,
		})
	end
	return list
end

function WorldService.isPlotFree(index: number): boolean
	return Plots.isValidIndex(index) and plotOwners[index] == nil
end

function WorldService.getOwner(index: number): Player?
	local owner = plotOwners[index]
	return owner and owner.player or nil
end

function WorldService.getPlotIndex(player: Player): number?
	return playerPlots[player]
end

function WorldService.getBounds(player: Player)
	local index = playerPlots[player]
	if not index then
		return nil
	end
	return Plots.getBounds(index)
end

function WorldService.getExit(player: Player)
	local index = playerPlots[player]
	return index and Plots.getExit(index) or nil
end

function WorldService.getPlotFolder(player: Player, kind: string): Folder?
	local index = playerPlots[player]
	if not index then
		return nil
	end
	local root = Workspace:FindFirstChild(kind)
	return root and root:FindFirstChild("Plot_" .. index) or nil
end

-- All players that currently own a plot (used by the economy / traffic / railway cycles).
function WorldService.getPlotOwners()
	local list = {}
	for player in pairs(playerPlots) do
		table.insert(list, player)
	end
	return list
end

local function spawnCFrame(index: number)
	local bounds = Plots.getBounds(index)
	local v = Plots.SideVector[bounds.exitSide]
	local offset = bounds.size / 2 - 6
	local pos = Vector3.new(bounds.centerX + v[1] * offset, bounds.surfaceY + 4, bounds.centerZ + v[2] * offset)
	return CFrame.lookAt(pos, Vector3.new(bounds.centerX, pos.Y, bounds.centerZ))
end

function WorldService.teleportToPlot(player: Player)
	local index = playerPlots[player]
	local character = player.Character
	if index and character then
		character:PivotTo(spawnCFrame(index))
	end
end

function WorldService.teleportToLobby(player: Player)
	local lobby = GameConfig.Map.LobbySpawn
	local character = player.Character
	if character then
		character:PivotTo(CFrame.new(lobby[1], lobby[2] + 4, lobby[3]))
	end
end

-- Server-authoritative claim. Returns ok, error.
function WorldService.claim(player: Player, index: any, country): (boolean, string?)
	if not Plots.isValidIndex(index) then
		return false, "Invalid plot"
	end
	if playerPlots[player] then
		return false, "You already own a plot"
	end
	if plotOwners[index] ~= nil then
		return false, "This plot is already taken"
	end
	plotOwners[index] = {
		player = player,
		countryName = country and country.Name or "",
		flagId = country and country.FlagId or "",
	}
	playerPlots[player] = index
	createPlotFolders(index, player)
	local model = plotModels[index]
	if model then
		model:SetAttribute("OwnerUserId", player.UserId)
		model:SetAttribute("OwnerName", player.Name)
		model:SetAttribute("CountryName", country and country.Name or "")
	end
	player:SetAttribute(Constants.Attributes.PlotIndex, index)
	updateSign(index)
	broadcast()
	return true, nil
end

function WorldService.release(player: Player)
	local index = playerPlots[player]
	if not index then
		return
	end
	destroyPlotFolders(index)
	plotOwners[index] = nil
	playerPlots[player] = nil
	local model = plotModels[index]
	if model then
		model:SetAttribute("OwnerUserId", 0)
		model:SetAttribute("OwnerName", nil)
		model:SetAttribute("CountryName", nil)
	end
	if player.Parent then
		player:SetAttribute(Constants.Attributes.PlotIndex, nil)
	end
	updateSign(index)
	broadcast()
end

-- Kept for older callers: plots are no longer assigned automatically.
function WorldService.leave(player: Player)
	WorldService.release(player)
end

-- Runs at server start, before players join: no map geometry is created here.
function WorldService.init(allServices)
	services = allServices
	remotes = allServices.Remotes
	rootFolders()
	WorldService.fillTerrainWater()
	validateStaticMap()
	for index, model in pairs(plotModels) do
		model:SetAttribute("OwnerUserId", 0)
		createSign(index, model, Plots.getBounds(index))
		updateSign(index)
	end
	Workspace:SetAttribute("WarStateMapReady", mapReport.ok)
end

local function hookCharacter(player: Player)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			if playerPlots[player] then
				WorldService.teleportToPlot(player)
			end
		end)
	end)
end

function WorldService.start()
	remotes[Constants.Remotes.GetPlots].OnServerInvoke = function(_player)
		return { ok = true, plots = WorldService.listPlots() }
	end
	-- Character hook only (teleport back to the owned plot on respawn). No map work here.
	Players.PlayerAdded:Connect(hookCharacter)
	for _, player in ipairs(Players:GetPlayers()) do
		hookCharacter(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		WorldService.release(player)
	end)
end

return WorldService
