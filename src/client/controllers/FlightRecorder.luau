--!strict
-- FlightRecorder.luau
-- Blackbox recorder for manual flights: samples the drone at a fixed rate, replays the
-- recording in the simulator, and encodes it for the real drone (FlightPackage).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DroneConfig = require(ReplicatedStorage:WaitForChild("DroneConfig"))
local FlightPackage = require(ReplicatedStorage:WaitForChild("FlightPackage"))

local SAMPLE_DT = 1 / DroneConfig.RECORDER.SAMPLE_RATE_HZ

local FlightRecorder = {}
FlightRecorder.__index = FlightRecorder

export type Recorder = typeof(setmetatable(
	{} :: {
		Samples: { FlightPackage.RecordedSample },
		IsRecording: boolean,
		IsReplaying: boolean,
		Elapsed: number,
		NextSampleAt: number,
		ReplayTime: number,
		ReplayIndex: number,
	},
	FlightRecorder
))

function FlightRecorder.new(): Recorder
	return setmetatable({
		Samples = {},
		IsRecording = false,
		IsReplaying = false,
		Elapsed = 0,
		NextSampleAt = 0,
		ReplayTime = 0,
		ReplayIndex = 1,
	}, FlightRecorder)
end

function FlightRecorder.start(self: Recorder)
	table.clear(self.Samples)
	self.IsRecording = true
	self.IsReplaying = false
	self.Elapsed = 0
	self.NextSampleAt = 0
end

function FlightRecorder.stop(self: Recorder): number
	self.IsRecording = false
	return #self.Samples
end

-- Call every frame while recording. Returns false once the duration limit stopped the recording.
function FlightRecorder.step(self: Recorder, dt: number, pos: Vector3, yaw: number, pitch: number, roll: number): boolean
	if not self.IsRecording then
		return false
	end
	if self.Elapsed >= self.NextSampleAt then
		table.insert(self.Samples, { t = self.Elapsed, Position = pos, Yaw = yaw, Pitch = pitch, Roll = roll })
		self.NextSampleAt += SAMPLE_DT
	end
	self.Elapsed += dt
	if self.Elapsed > DroneConfig.RECORDER.MAX_DURATION_SEC then
		self:stop()
		return false
	end
	return true
end

function FlightRecorder.hasRecording(self: Recorder): boolean
	return #self.Samples >= 2
end

function FlightRecorder.duration(self: Recorder): number
	local n = #self.Samples
	return if n > 0 then self.Samples[n].t else 0
end

function FlightRecorder.startReplay(self: Recorder): boolean
	if self.IsRecording or not self:hasRecording() then
		return false
	end
	self.IsReplaying = true
	self.ReplayTime = 0
	self.ReplayIndex = 1
	return true
end

function FlightRecorder.stopReplay(self: Recorder)
	self.IsReplaying = false
end

local function lerpAngle(a: number, b: number, alpha: number): number
	local diff = (b - a + 180) % 360 - 180
	return a + diff * alpha
end

-- Advances the replay and returns the interpolated pose, plus true when the replay finished.
function FlightRecorder.stepReplay(self: Recorder, dt: number): (Vector3, number, number, number, boolean)
	local samples = self.Samples
	self.ReplayTime += dt
	while self.ReplayIndex < #samples - 1 and samples[self.ReplayIndex + 1].t <= self.ReplayTime do
		self.ReplayIndex += 1
	end

	local a = samples[self.ReplayIndex]
	local b = samples[self.ReplayIndex + 1]
	local span = b.t - a.t
	local alpha = if span > 0 then math.clamp((self.ReplayTime - a.t) / span, 0, 1) else 1
	local finished = self.ReplayTime >= samples[#samples].t

	return a.Position:Lerp(b.Position, alpha),
		lerpAngle(a.Yaw, b.Yaw, alpha),
		a.Pitch + (b.Pitch - a.Pitch) * alpha,
		a.Roll + (b.Roll - a.Roll) * alpha,
		finished
end

function FlightRecorder.encode(self: Recorder): string
	return FlightPackage.encodeRecording(self.Samples, DroneConfig.RECORDER.SAMPLE_RATE_HZ)
end

return FlightRecorder
