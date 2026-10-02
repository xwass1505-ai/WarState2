-- WarStateBridge (Studio plugin, OPTIONAL)
-- Talks ONLY to the local Python bridge at http://127.0.0.1:<port>. It accepts a fixed whitelist of
-- READ-ONLY structured commands ("ping", "verify_structure"). It never edits your place and never
-- executes arbitrary code. Its only job is to let build_war_state.py --verify-studio check that
-- Studio actually received the Rojo-synced project.

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

if RunService:IsRunning() then
	return -- edit mode only, never during Play
end

local PORT = 34873
local BASE = "http://127.0.0.1:" .. PORT
local POLL_SECONDS = 2
local ALLOWED = { ping = true, verify_structure = true }

local toolbar = plugin:CreateToolbar("War State")
local toggle = toolbar:CreateButton("Bridge", "Toggle the War State local verification bridge", "")
toggle.ClickableWhenViewportHidden = true

local enabled = plugin:GetSetting("WarStateBridgeEnabled")
if enabled == nil then
	enabled = true
end
toggle:SetActive(enabled)

toggle.Click:Connect(function()
	enabled = not enabled
	plugin:SetSetting("WarStateBridgeEnabled", enabled)
	toggle:SetActive(enabled)
	print("[WarStateBridge] " .. (enabled and "enabled" or "disabled"))
end)

local function request(method: string, path: string, body)
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = BASE .. path,
			Method = method,
			Headers = { ["Content-Type"] = "application/json" },
			Body = body and HttpService:JSONEncode(body) or nil,
		})
	end)
	if not ok or not response.Success then
		return nil
	end
	local decoded
	local decodeOk = pcall(function()
		decoded = HttpService:JSONDecode(response.Body)
	end)
	return decodeOk and decoded or nil
end

-- path like "ReplicatedStorage/Shared/Config/GameConfig"
local function resolve(path: string)
	local current: Instance? = nil
	for segment in string.gmatch(path, "[^/]+") do
		if current == nil then
			local okService, service = pcall(function()
				return game:GetService(segment)
			end)
			current = okService and service or game:FindFirstChild(segment)
		else
			current = current:FindFirstChild(segment)
		end
		if current == nil then
			return nil
		end
	end
	return current
end

local function handle(command)
	if type(command) ~= "table" or not ALLOWED[command.type] then
		return nil
	end
	if command.type == "ping" then
		return { id = command.id, type = "ping", ok = true }
	end
	local missing, found = {}, 0
	local paths = type(command.paths) == "table" and command.paths or {}
	for i, path in ipairs(paths) do
		if i > 2000 then
			break
		end
		if type(path) == "string" then
			if resolve(path) then
				found += 1
			else
				table.insert(missing, path)
			end
		end
	end
	return {
		id = command.id,
		type = "verify_structure",
		ok = #missing == 0,
		found = found,
		missing = missing,
	}
end

task.spawn(function()
	local announced = false
	while true do
		task.wait(POLL_SECONDS)
		if enabled then
			local hello = request("POST", "/v1/hello", {
				placeName = game.Name,
				placeId = game.PlaceId,
			})
			if hello and hello.ok then
				if not announced then
					announced = true
					print("[WarStateBridge] Connected to local build script")
				end
				local command = request("GET", "/v1/command", nil)
				if command and command.type and command.type ~= "none" then
					local result = handle(command)
					if result then
						request("POST", "/v1/result", result)
					end
				end
			else
				announced = false
			end
		end
	end
end)
