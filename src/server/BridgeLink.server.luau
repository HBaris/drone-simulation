--!strict
-- BridgeLink.server.luau
-- Relays the drone state between the client (where the drone is simulated) and the local MAVLink
-- bridge (tools/mavlink_bridge.py), and delivers ground-station commands back to the client.
--   client --BridgeState--> server --HTTP POST (5 Hz)--> bridge --MAVLink UDP--> TEI GCS / QGC
--   client <--BridgeCommands-- server <------ commands ------ bridge <------ GCS
-- Only works in Studio (the bridge listens on 127.0.0.1) with "Allow HTTP Requests" enabled.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DroneConfig = require(ReplicatedStorage:WaitForChild("DroneConfig"))

local B = DroneConfig.BRIDGE
local network = ReplicatedStorage:WaitForChild("DroneNetwork")

local stateEvent = Instance.new("RemoteEvent")
stateEvent.Name = "BridgeState"
stateEvent.Parent = network

local commandEvent = Instance.new("RemoteEvent")
commandEvent.Name = "BridgeCommands"
commandEvent.Parent = network

-- Link status for the HUD
local status = Instance.new("Configuration")
status.Name = "Bridge"
status:SetAttribute("Status", "KAPALI")
status:SetAttribute("GcsConnected", false)
status.Parent = ReplicatedStorage

local latestState: { [string]: any }? = nil
local latestPlayer: Player? = nil

stateEvent.OnServerEvent:Connect(function(player: Player, state: any)
	if type(state) == "table" then
		latestState = state
		latestPlayer = player
	end
end)

local function setStatus(text: string, gcs: boolean)
	if status:GetAttribute("Status") ~= text then
		print("[BridgeLink] " .. text)
	end
	status:SetAttribute("Status", text)
	status:SetAttribute("GcsConnected", gcs)
end

task.spawn(function()
	while true do
		local interval = 1 / B.RATE_HZ
		local state, player = latestState, latestPlayer
		if not B.ENABLED then
			setStatus("KAPALI (ayar)", false)
			interval = 5
		elseif not HttpService.HttpEnabled then
			setStatus("KAPALI (HTTP izni yok)", false)
			interval = 5
		elseif state and player then
			local ok, response = pcall(function()
				return HttpService:RequestAsync({
					Url = B.URL,
					Method = "POST",
					Headers = { ["Content-Type"] = "application/json" },
					Body = HttpService:JSONEncode(state),
				})
			end)
			if ok and response.Success then
				local reply = HttpService:JSONDecode(response.Body)
				if reply.commands and #reply.commands > 0 and player.Parent then
					commandEvent:FireClient(player, reply.commands)
				end
				local gcs = reply.gcs_connected == true
				setStatus(if gcs then "BAĞLI · yer istasyonu bağlı" else "BAĞLI · yer istasyonu bekleniyor", gcs)
			else
				setStatus("KÖPRÜ YOK (python tools/mavlink_bridge.py)", false)
				interval = B.RETRY_SEC
			end
		end
		task.wait(interval)
	end
end)
