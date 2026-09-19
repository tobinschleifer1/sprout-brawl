--!strict
-- Client entry point.
--
-- The client simulates nothing. It samples input, ships it, and draws the snapshots that come back.
-- That is a deliberate first step and not the end state: Fighter:snapshot()/restore() were built in
-- Phase 2 precisely so the client can later predict its own fighter and roll back on correction.
-- Doing that now would mean every bug had two possible homes before either half was known good.
--
-- The visible cost is that your own character responds a round-trip late. Expect it, and do not
-- "fix" it by moving authority to the client.


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Snapshot = require(Shared.Snapshot)
local InputClient = require(script.InputClient)
local Camera2D = require(script.Camera2D)
local Rigs = require(script.Rigs)

local FRAME = Config.FRAME
-- Two frames of buffer. Snapshots arrive at 60Hz but not evenly, and drawing the newest one the
-- instant it lands means every jittered packet is a visible stutter. Rendering 2 frames in the
-- past costs 33ms of latency on other people's fighters and removes it.
local INTERP_DELAY = FRAME * 2

local camera = Workspace.CurrentCamera

local input = InputClient.new()
local cam2d = Camera2D.new(camera)
local rigsFolder = Instance.new("Folder")
rigsFolder.Name = "Fighters"
rigsFolder.Parent = Workspace
local rigs = Rigs.new(rigsFolder)

local roster: { any } = {}
local buffer: { any } = {}        -- snapshots, oldest first, each tagged with arrival time
local pendingFrames: { number } = {}
-- Posing errors are reported once per fighter. Reported every frame, a single broken rig produces
-- sixty lines a second and buries whatever else the console had to say.
local posedWarned: { [number]: boolean } = {}
local startedAt = os.clock()
local warnedSilent = false
local sawFirst = false

-- ---------------------------------------------------------------- match setup ----
Net.remote("Match").OnClientEvent:Connect(function(cfg: any)
	rigs:clear()
	posedWarned = {}
	buffer = {}
	roster = cfg.fighters
	for _, entry in roster do
		rigs:spawn(entry)
	end
	print(`[Blockfall] match: {cfg.stage} seed={cfg.seed} fighters={#roster}`)
end)

Net.remote("Snapshot").OnClientEvent:Connect(function(snap: any)
	-- Unreliable delivery is unordered as well as lossy. A snapshot older than one already held is
	-- not useful for anything and would rewind the interpolation if it were kept.
	local newest = buffer[#buffer]
	if newest and snap.frame <= newest.frame then
		return
	end
	snap.t = os.clock()
	table.insert(buffer, snap)
	while #buffer > 8 do
		table.remove(buffer, 1)
	end
end)

Net.remote("Events").OnClientEvent:Connect(function(events: { any })
	for _, e in events do
		if e.type == "count" then
			print(`[Blockfall] {e.n}`)
		elseif e.type == "go" then
			print("[Blockfall] GO")
		elseif e.type == "ko" then
			cam2d.shake = 1.2
		end
	end
end)

-- ---------------------------------------------------------------- interpolation ----
local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Returns the fighter states to draw, interpolated between the two snapshots bracketing `at`,
-- and decoded: past this point nothing in the client knows the wire's field names.
local function interpolate(at: number): { any }?
	if #buffer == 0 then
		return nil
	end
	local a, b = buffer[1], nil
	for i = 1, #buffer - 1 do
		if buffer[i].t <= at and buffer[i + 1].t >= at then
			a, b = buffer[i], buffer[i + 1]
			break
		end
	end
	if not b then
		-- Ahead of the newest snapshot, which happens whenever a packet is late. Hold the last
		-- known state rather than extrapolating: a guess that has to be taken back is a rubber band.
		a = buffer[#buffer]
	end
	local span = if b then math.max(1e-6, b.t - a.t) else 1
	local t = if b then math.clamp((at - a.t) / span, 0, 1) else 0

	local out = {}
	for i, wa in a.fighters do
		local wb = if b then b.fighters[i] else nil
		-- The newer sample wins outright at the halfway mark, and only then are the continuous
		-- fields blended back in. Decoding the nearer snapshot whole, rather than copying field
		-- by field, is what stops a field added later from being silently left behind.
		local s = Snapshot.decode(if wb and t >= 0.5 then wb else wa)
		if wb then
			local da, db = Snapshot.decode(wa), Snapshot.decode(wb)
			for _, key in Snapshot.CONTINUOUS do
				s[key] = lerp(da[key], db[key], t)
			end
		end
		out[i] = s
	end
	return out
end

-- ---------------------------------------------------------------- loop ----
RunService.RenderStepped:Connect(function(dt: number)
	-- Sample and ship. Frames are batched into whatever the render step covered, so a 144Hz client
	-- usually sends nothing and sometimes sends one, and a 30Hz client sends two.
	for _, f in input:sample(dt, FRAME) do
		table.insert(pendingFrames, Net.packFrame(f))
	end
	if #pendingFrames > 0 then
		Net.remote("Input"):FireServer(pendingFrames)
		pendingFrames = {}
	end

	local states = interpolate(os.clock() - INTERP_DELAY)
	if not states then
		-- A black screen has several causes that look identical, so say which one this is. Without
		-- this the first question after every failed playtest is "is the server even running?".
		if not warnedSilent and os.clock() - startedAt > 5 then
			warnedSilent = true
			warn(`[Blockfall] no snapshots after 5s. roster={#roster}. `
				.. `If roster is 0 the server never started a match; if it is not 0 the match `
				.. `started and the Snapshot remote is not arriving.`)
		end
		return
	end
	if not sawFirst then
		sawFirst = true
		print(`[Blockfall] first snapshot: {#states} fighters, drawing`)
	end

	-- Camera FIRST, and rigs after, and this order is load-bearing. It used to be the other way
	-- round, and when Rigs.pose threw on one fighter the whole RenderStepped callback unwound -
	-- so the camera never moved and the screen was black. A renderer bug should cost you the thing
	-- that is broken, not the view of the world.
	local bodies = {}
	for _, s in states do
		local entry = roster[s.index + 1]
		if entry then
			table.insert(bodies, { x = s.x, y = s.y, h = entry.height, alive = s.alive })
		end
	end
	if #bodies > 0 then
		cam2d:update(bodies, dt)
	end

	-- Each rig is posed in isolation for the same reason. A rig that fails is one missing body,
	-- reported once; it is not the other three fighters disappearing too.
	for _, s in states do
		if roster[s.index + 1] then
			local ok, err = pcall(rigs.pose, rigs, s.index, s)
			if not ok and not posedWarned[s.index] then
				posedWarned[s.index] = true
				warn(`[Blockfall] rig {s.index} failed to pose, and will not be reported again: {err}`)
			end
		end
	end

	if cam2d.shake > 0 then
		cam2d.shake = math.max(0, cam2d.shake - dt * 4)
	end
end)

-- ---------------------------------------------------------------- go ----
Lighting.Ambient = Color3.fromRGB(120, 124, 132)
Lighting.ClockTime = 14

Net.remote("Hello"):FireServer()
print("[Blockfall] client ready")
