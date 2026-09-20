--!strict
-- Client entry point.
--
-- The client simulates nothing. It samples input, ships it, and draws the snapshots that come back.
-- Drawing is a 2D canvas of pooled Frames, not 3D: see Canvas2D. Workspace is empty and the
-- Roblox camera is never touched.
-- That is a deliberate first step and not the end state: Fighter:snapshot()/restore() were built in
-- Phase 2 precisely so the client can later predict its own fighter and roll back on correction.
-- Doing that now would mean every bug had two possible homes before either half was known good.
--
-- The visible cost is that your own character responds a round-trip late. Expect it, and do not
-- "fix" it by moving authority to the client.


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Snapshot = require(Shared.Snapshot)
local Loadout = require(Shared.Loadout)
local Stages = require(Shared.Data.Stages)
local Stage = require(Shared.Stage)
local InputClient = require(script.InputClient)
local Camera2D = require(script.Camera2D)
local Canvas2D = require(script.Canvas2D)
local Stage2D = require(script.Stage2D)
local Fighter2D = require(script.Fighter2D)
local Predictor = require(script.Predictor)
local Hud = require(script.Hud)

local FRAME = Config.FRAME
-- Two frames of buffer. Snapshots arrive at 60Hz but not evenly, and drawing the newest one the
-- instant it lands means every jittered packet is a visible stutter. Rendering 2 frames in the
-- past costs 33ms of latency on other people's fighters and removes it.
local INTERP_DELAY = FRAME * 2

local input = InputClient.new()
local cam2d = Camera2D.new()
local canvas = Canvas2D.new(Players.LocalPlayer:WaitForChild("PlayerGui"))

local roster: { any } = {}
-- The client builds each fighter's character from the same Loadout the server used. The roster
-- carries the two ids that decide it, so the palette and proportions are derived rather than sent -
-- they never change during a match, and sending them every frame would be sixty copies a second of
-- a constant.
local chars: { any } = {}
local stageView: any = nil
local buffer: { any } = {}        -- snapshots, oldest first, each tagged with arrival time
local pendingFrames: { number } = {}
-- Posing errors are reported once per fighter. Reported every frame, a single broken rig produces
-- sixty lines a second and buries whatever else the console had to say.
local posedWarned: { [number]: boolean } = {}
local startedAt = os.clock()
local warnedSilent = false
-- The snapshot interpolate() based this frame on. The moving platforms are applied from the same
-- one, so a fighter and the raft they are standing on are drawn at the same instant - taking the
-- newest platform state while drawing bodies two frames back slides them across the deck.
local interpBase: any = nil
-- Which fighter is ours, and the simulation that runs it ahead of the server. Everyone else is
-- drawn two frames in the past to smooth out jitter; ours is predicted, so it answers the frame
-- the input was sampled on rather than a round trip later.
local localIndex: number? = nil
local predictor: any = nil
local hud: any = nil
local matchCfg: any = nil
local sawFirst = false

-- ---------------------------------------------------------------- match setup ----
Net.remote("Match").OnClientEvent:Connect(function(cfg: any)
	canvas:clear()
	posedWarned = {}
	buffer = {}
	roster = cfg.fighters
	chars = {}
	localIndex = nil
	for i, entry in roster do
		chars[i] = Loadout.build(entry.avatar, entry.weapon)
		if entry.userId and entry.userId == Players.LocalPlayer.UserId then
			localIndex = entry.index
		end
	end
	for _, data in Stages.LIST do
		if data.id == cfg.stage then
			-- A view-only Stage, built from the same data and seed as the server's, and never
			-- stepped. It exists to be READ for its geometry - platform extents, ledges - and it
			-- decides nothing.
			stageView = Stage.new(data, cfg.seed)
		end
	end
	matchCfg = cfg
	if not hud then
		hud = Hud.new(Players.LocalPlayer:WaitForChild("PlayerGui"))
	end
	hud:clearResults()
	hud:bind(roster, chars)

	predictor = nil
	if localIndex and stageView then
		predictor = Predictor.new(chars[localIndex + 1], localIndex, stageView)
	end
	print(`[Blockfall] match: {cfg.stage} seed={cfg.seed} fighters={#roster}`
		.. (if predictor then " (predicting)" else ""))
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
	-- Reconcile before the frame is drawn, not during the draw: a correction is simulation, and
	-- doing it inside RenderStepped would run it at the render rate rather than once per snapshot.
	if predictor and localIndex and snap.acks then
		for _, a in snap.acks do
			if a.i == localIndex then
				for i, entry in roster do
					if entry.index == localIndex then
						predictor:reconcile(Snapshot.decode(snap.fighters[i]), a.n)
					end
				end
			end
		end
	end
	while #buffer > 8 do
		table.remove(buffer, 1)
	end
end)

-- The final scoreboard, once and reliably. The snapshot stream stops with the match, so without
-- this the client would sit on the last frame with no idea the match had ended.
Net.remote("Results").OnClientEvent:Connect(function(res: any)
	if hud then
		hud:showResults(res)
	end
	print(`[Blockfall] --- results ({res.mode}, {res.frames} frames, {string.format("%.1f", res.time)}s) ---`)
	for place, row in res.rows do
		print(`[Blockfall]   {place}. {row.name} ({row.avatar}/{row.weapon}) `
			.. `stocks={row.stocks} kos={row.kos} falls={row.falls} dmg={row.damage} pct={math.floor(row.percent)}`)
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

	interpBase = a
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
-- Input is sampled on HEARTBEAT, not on the render step. The accumulator in InputClient already
-- stopped a 144Hz client flooding the queue, but it did nothing about the other end: driven by
-- RenderStepped, a client rendering at 15Hz called this once every 66ms and emitted four frames
-- that all sampled the same instant of keyboard state - so the input was both stale and
-- duplicated. Heartbeat runs at 60Hz whether or not the frame was drawn, which is the rate the
-- simulation consumes, and it is measurably what the README always said this did.
RunService.Heartbeat:Connect(function(dt: number)
	for _, f in input:sample(dt, FRAME) do
		table.insert(pendingFrames, Net.packFrame(f))
		-- Simulated here, immediately. The server counts exactly the frames we send, so this has
		-- to see every one of them and no others or the replay window drifts.
		if predictor then
			predictor:push(f)
		end
	end
	if #pendingFrames > 0 then
		Net.remote("Input"):FireServer(pendingFrames)
		pendingFrames = {}
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	local drawAt = os.clock()
	local states = interpolate(drawAt - INTERP_DELAY)
	-- Our own fighter, predicted. Interpolation exists to hide other people's packet jitter, and
	-- applying it to the local fighter cost INTERP_DELAY on top of the round trip. This is the
	-- fighter as our own inputs have already taken it, corrected against the server on every
	-- snapshot - so it answers on the frame the key went down.
	if states and predictor and predictor.ready then
		for i, st in states do
			if st.index == localIndex then
				states[i] = predictor:state()
				break
			end
		end
	end
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

	-- Camera first, then the draw. It used to be the other way round, and when a renderer error
	-- threw, the whole RenderStepped callback unwound - so the camera never moved and the screen
	-- was black. A renderer bug should cost you the thing that is broken, not the view of the world.
	local bodies = {}
	for _, st in states do
		local entry = roster[st.index + 1]
		if entry then
			table.insert(bodies, { x = st.x, y = st.y, h = entry.height, alive = st.alive })
		end
	end
	if #bodies > 0 then
		cam2d:update(bodies, dt, canvas:viewport())
	end

	-- The client does NOT step stageView, and must not. Stage.step is simulation: it advances
	-- moving platforms off its own clock and draws hazard RNG from the seeded generator. Running it
	-- here would run it once per RENDER frame rather than once per sim frame, so within seconds the
	-- platforms would be somewhere the server does not agree with and the shared seed would be
	-- consumed a different number of times. Static geometry is correct on the two stages in play;
	-- moving platforms need the server to send their offsets in the snapshot, which is the next
	-- thing to add to Snapshot.FIELDS.
	Stage2D.sky(canvas, stageView or { data = {} })
	canvas:world(cam2d.x, cam2d.y, cam2d.ppu, cam2d.shakeX, cam2d.shakeY)
	if stageView then
		-- The view-only Stage is never stepped; the server sends what it cannot derive. `moving` is
		-- a function of stage time and `sinking` is a function of who is standing on it, and only
		-- the server knows the second.
		Stage.applyDynamicState(stageView, interpBase and interpBase.platforms)
		Stage2D.draw(canvas, stageView)
	end
	for _, st in states do
		local char = chars[st.index + 1]
		if char then
			local ok, err = pcall(function()
				local surface = if stageView then Stage.surfaceUnder(stageView, st.x, st.y + 0.1) else nil
				Fighter2D.draw(canvas, st, char, drawAt, if surface then surface.top else nil)
			end)
			if not ok and not posedWarned[st.index] then
				posedWarned[st.index] = true
				warn(`[Blockfall] fighter {st.index} failed to draw, and will not be reported again: {err}`)
			end
		end
	end
	canvas:finish()
	if hud then
		hud:update(states, buffer[#buffer], canvas, chars, matchCfg)
	end

	if cam2d.shake > 0 then
		cam2d.shake = math.max(0, cam2d.shake - dt * 4)
	end
end)

-- ---------------------------------------------------------------- go ----
Net.remote("Hello"):FireServer()
print("[Blockfall] client ready")
