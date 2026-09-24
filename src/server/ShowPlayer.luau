--!strict
-- ShowPlayer.luau
-- Plays a show file from tools/plan_show.py (collision-free, CAPT-assigned) exactly as the real drones
-- would fly it: straight lines between keyframes on one shared minimum-jerk time profile. Positions are
-- ENU meters from DroneConfig.HOME.SHOW_CENTER. Also measures live drone-to-drone separation.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DroneConfig = require(ReplicatedStorage:WaitForChild("DroneConfig"))
local DroneSpawner = require(script.Parent:WaitForChild("DroneSpawner"))

local S = DroneConfig.STUDS_PER_METER
local GROUND_OFFSET = 0.5 -- studs: pivot above the ground plane

local ShowPlayer = {}

type Keyframe = { Name: string, Color: Color3, TArrive: number, TDepart: number, Positions: { Vector3 } }
type Show = { N: number, Duration: number, Keyframes: { Keyframe } }

local current: { Show: Show, T: number, Models: { Model }, Parts: { BasePart }, Frame: number, ColorClock: number }? = nil

local function enuToWorld(p: { number }): Vector3
	local c = DroneConfig.HOME.SHOW_CENTER
	return Vector3.new(c.X + p[1] * S, c.Y + GROUND_OFFSET + p[3] * S, c.Z - p[2] * S)
end

function ShowPlayer.load(jsonText: string): Show
	local doc = HttpService:JSONDecode(jsonText)
	assert(doc.format == "drone-show", "not a drone-show file")
	local kfs: { Keyframe } = {}
	for i, k in ipairs(doc.keyframes) do
		local pos = table.create(#k.positions)
		for j, p in ipairs(k.positions) do
			pos[j] = enuToWorld(p)
		end
		kfs[i] = { Name = k.name, Color = Color3.fromHex(k.color), TArrive = k.t_arrive, TDepart = k.t_depart, Positions = pos }
	end
	return { N = doc.drones, Duration = doc.duration_s, Keyframes = kfs }
end

local function minjerk(tau: number): number
	return tau * tau * tau * (10 - 15 * tau + 6 * tau * tau)
end

-- Keyframes (a, b) around time t and the blend 0..1 between them
local function segment(show: Show, t: number): (Keyframe, Keyframe, number)
	local kfs = show.Keyframes
	for i = 1, #kfs - 1 do
		local a, b = kfs[i], kfs[i + 1]
		if t <= a.TDepart then
			return a, a, 0
		elseif t < b.TArrive then
			return a, b, minjerk((t - a.TDepart) / (b.TArrive - a.TDepart))
		end
	end
	local last = kfs[#kfs]
	return last, last, 0
end

local function paint(model: Model, color: Color3)
	local led = model:FindFirstChild("ShowLED") :: BasePart?
	if led then
		led.Color = color
		local light = led:FindFirstChild("LightSource") :: PointLight?
		if light then
			light.Color = color
		end
	end
end

function ShowPlayer.start(show: Show, folder: Folder)
	ShowPlayer.stop()
	local models, parts = table.create(show.N), table.create(show.N)
	local start = show.Keyframes[1]
	for i = 1, show.N do
		local model = DroneSpawner.createQuadcopterModel(1000 + i, show.N <= 200)
		model.Name = string.format("Show_%03d", i)
		model:PivotTo(CFrame.new(start.Positions[i]))
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		paint(model, start.Color)
		model.Parent = folder
		models[i], parts[i] = model, model.PrimaryPart :: BasePart
	end
	current = { Show = show, T = 0, Models = models, Parts = parts, Frame = 0, ColorClock = 0 }
	folder:SetAttribute("ShowName", "PLANLI ŞOV")
	folder:SetAttribute("ShowDuration", show.Duration)
end

function ShowPlayer.stop()
	if current then
		local folder = current.Models[1] and current.Models[1].Parent
		if folder then
			folder:SetAttribute("ShowPhase", nil)
			folder:SetAttribute("ShowTime", nil)
		end
		for _, m in current.Models do
			m:Destroy()
		end
		current = nil
	end
end

function ShowPlayer.isRunning(): boolean
	return current ~= nil
end

-- World positions of every show drone right now (for the separation monitor)
function ShowPlayer.positions(): { Vector3 }
	local out = {}
	if current then
		for i, p in current.Parts do
			out[i] = p.Position
		end
	end
	return out
end

function ShowPlayer.step(dt: number)
	local st = current
	if not st then
		return
	end
	local show = st.Show
	st.T = math.min(st.T + dt, show.Duration)
	local a, b, s = segment(show, st.T)
	local cfs = table.create(show.N)
	for i = 1, show.N do
		local pa, pb = a.Positions[i], b.Positions[i]
		local p = pa + (pb - pa) * s
		local v = pb - pa
		local flat = Vector3.new(v.X, 0, v.Z)
		cfs[i] = if flat.Magnitude > 0.1 then CFrame.lookAt(p, p + flat) else CFrame.new(p)
	end
	Workspace:BulkMoveTo(st.Parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)

	st.ColorClock += dt
	if st.ColorClock >= 0.2 then -- LED fades at 5 Hz, cheaper than every frame for 800 lights
		st.ColorClock = 0
		local color = a.Color:Lerp(b.Color, s)
		for _, m in st.Models do
			paint(m, color)
		end
	end
	local folder = st.Models[1] and st.Models[1].Parent
	if folder then
		folder:SetAttribute("ShowTime", st.T)
		folder:SetAttribute("ShowPhase", if s > 0 then a.Name .. " → " .. b.Name else a.Name)
	end
end

-- Closest pair among positions (meters) and number of pairs closer than minSep, via a spatial hash.
function ShowPlayer.separation(positions: { Vector3 }, minSep: number): (number, number)
	local cell = minSep * 1.5 * S -- exact for any pair closer than 1.5 x minSep
	local buckets: { [Vector3]: { number } } = {}
	for i, p in positions do
		local key = Vector3.new(math.floor(p.X / cell), math.floor(p.Y / cell), math.floor(p.Z / cell))
		local b = buckets[key]
		if b then
			table.insert(b, i)
		else
			buckets[key] = { i }
		end
	end
	local best, close = math.huge, 0
	for key, members in buckets do
		for dx = -1, 1 do
			for dy = -1, 1 do
				for dz = -1, 1 do
					local other = buckets[key + Vector3.new(dx, dy, dz)]
					if other then
						for _, i in members do
							for _, j in other do
								if j > i then
									local d = (positions[i] - positions[j]).Magnitude / S
									best = math.min(best, d)
									if d < minSep then
										close += 1
									end
								end
							end
						end
					end
				end
			end
		end
	end
	return best, close
end

return ShowPlayer
