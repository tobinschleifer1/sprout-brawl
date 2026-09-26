--!strict
-- Client entry point.
--
-- Predict the local fighter, interpolate remote fighters, and draw server-owned world effects.
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
local DisasterShapes = require(script.DisasterShapes)
local UltCinematic = require(script.UltCinematic)
local UltBanner = require(script.UltBanner)
local Effects = require(script.Effects)
local HudColors = require(script.HudColors)
local Callouts = require(Shared.Data.Callouts)
local Teams = require(Shared.Data.Teams)
local World2D = require(script.World2D)
local Fighter2D = require(script.Fighter2D)
local Predictor = require(script.Predictor)
local Hud = require(script.Hud)
local Select = require(script.RoomPanel)
local LaunchState = require(script.LaunchState)
local Hub2D = require(script.Hub2D)

local FRAME = Config.FRAME
-- Two snapshots of buffer. Snapshots arrive at 30Hz but not evenly, and drawing the newest one the
-- instant it lands means every jittered packet is a visible stutter. Rendering two snapshots in
-- the past costs about 67ms on remote fighters; the local fighter still uses prediction.
local INTERP_DELAY = FRAME * 4

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
-- The sim frame the drawn states stand for, fractional between two snapshots. Snapshots arrive at
-- 30Hz; timing the ultimate cutscene off whole snapshot frames would step it at half rate.
local drawnFrame = 0
-- The last ultimate activated: who, what, and on which frame. The cutscene is a pure function of
-- drawnFrame minus that frame (UltCinematic), so it lines up with the freeze the server runs.
local ult: any = nil
-- Sparks, impact rings and shake (Effects, held to web/src/render2d/effects.js). One state for the
-- session, cleared at each match; the fighter and world painters add their per-frame dirt and orb
-- sparks to it too.
local fx = Effects.new()
Fighter2D.effects = fx
World2D.effects = fx
-- Events wait here until the drawn picture reaches the frame they happened on: the world is drawn a
-- few frames behind the newest snapshot, and a spark that lands before the hit it belongs to reads
-- as the game guessing.
local pendingFx: { any } = {}
-- Your own fighter's movement is predicted, so its dust comes from the prediction the moment you
-- act; the server's copy of those events would arrive a round trip and an interpolation late.
local LOCAL_FX: { [string]: boolean } = { jump = true, doublejump = true, dash = true, dodge = true, land = true, ledge = true, tech = true }
local function heightOf(i: number?): number
	local entry = if i ~= nil then roster[i + 1] else nil
	return if entry and entry.height then entry.height else 5
end
local function glowOf(i: number?): string?
	local char = if i ~= nil then chars[i + 1] else nil
	local pal = char and (char.weaponPalette or char.palette)
	return pal and pal.glow or nil
end
-- Which fighter is ours, and the simulation that runs it ahead of the server. Everyone else is
-- drawn two frames in the past to smooth out jitter; ours is predicted, so it answers the frame
-- the input was sampled on rather than a round trip later.
local localIndex: number? = nil
local predictor: any = nil
local hud: any = nil
local select_: any = nil
local matchCfg: any = nil
local sawFirst = false
local acceptingSnapshots = false
local scenes: { any } = {}
local launch = LaunchState.new()
local hub = Hub2D.new(Players.LocalPlayer:WaitForChild("PlayerGui"))

-- ---------------------------------------------------------------- match setup ----
-- The server says "pick a match". It also says when it refused one, and why.
Net.remote("Select").OnClientEvent:Connect(function(msg: any)
	acceptingSnapshots = false
	predictor = nil
	launch:reset()
	buffer, scenes = {}, {}
	canvas:clear()
	if hud then hud.gui.Enabled = false end
	if not select_ then
		select_ = Select.new(Players.LocalPlayer:WaitForChild("PlayerGui"))
		select_.onAction = function(action: any)
			if action.action == "start" then
				if not launch:begin(os.clock()) then return end
				select_:waiting("Requesting your match…")
			end
			Net.remote("RoomAction"):FireServer(action)
		end
		hub.onInteract = function(station: any)
			if not select_.gui.Enabled then
				if station.kind == "Format" then
					select_:waiting("Joining " .. station.name .. "…")
					Net.remote("RoomAction"):FireServer({ action = "join", format = station.id })
				elseif station.kind == "Exit" then
					select_:send("leave")
				else
					select_:openStation(station.id)
				end
			end
		end
	end
	if msg and msg.last then
		-- Their previous picks, so a rematch does not mean choosing everything again.
		select_.cfg = msg.last
	end
	hub:show(select_.cfg)
	if msg and msg.error then
		select_:show(`That match could not be run: {msg.error}`)
	else
		select_:hide()
	end
end)

Net.remote("RoomView").OnClientEvent:Connect(function(view: any)
	if not select_ then return end
	if view.error then launch:reset() end
	select_:update(view, Players.LocalPlayer.UserId)
	if view.left then launch:reset() end
	hub:configure(select_.cfg)
	hub:setRoom(view)
end)
Net.remote("HubPresence").OnClientEvent:Connect(function(peers: any)
	hub:setPeers(peers, Players.LocalPlayer.UserId)
end)

Net.remote("Match").OnClientEvent:Connect(function(cfg: any)
	launch:accept(os.clock())
	if select_ then
		select_:waiting("Loading arena and fighters…")
	end
	canvas:clear()
	acceptingSnapshots = true
	pendingFrames = {}
	input:reset()
	startedAt = os.clock()
	warnedSilent = false
	sawFirst = false
	posedWarned = {}
	buffer = {}
	scenes = {}
	ult = nil
	fx.parts, fx.rings, fx.shake, fx.shields = {}, {}, 0, {}
	pendingFx = {}
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
	hud.gui.Enabled = true
	hud:clearResults()
	if stageView then hud:announce("stage", stageView.data.name) end
	-- In a team match every fighter stands in their team's colour.
	Fighter2D.teamColours = nil
	if string.find(cfg.mode or "", "Teams", 1, true) then
		local teams = {}
		for _, entry in roster do
			local hex = Teams.colours[(entry.team or 0) + 1]
			if hex then teams[entry.index] = Canvas2D.hex(hex, Color3.new(1, 1, 1)) end
		end
		Fighter2D.teamColours = teams
	end
	hud:bind(roster, chars, localIndex, string.find(cfg.mode or "", "Teams", 1, true) ~= nil)

	predictor = nil
	if localIndex and stageView then
		-- Rendering interpolates an older world. Prediction needs its own latest-snapshot
		-- geometry, otherwise drawing a sinking/moving platform rewinds our collision floor.
		predictor = Predictor.new(chars[localIndex + 1], localIndex, Stage.new(stageView.data, cfg.seed))
	end
	print(`[Blockfall] match: {cfg.stage} seed={cfg.seed} fighters={#roster}`
		.. (if predictor then " (predicting)" else ""))
end)

Net.remote("Snapshot").OnClientEvent:Connect(function(snap: any)
	if not acceptingSnapshots or not matchCfg or snap.id ~= matchCfg.id then
		return
	end
	-- Retain the stale-frame guard across rejoin/retry as well as ordinary delivery.
	local newest = buffer[#buffer]
	if newest and snap.frame <= newest.frame then
		return
	end
	if launch.phase ~= "playing" then
		launch:ready()
		if select_ then select_:hide() end
		hub:hide()
	end
	snap.t = os.clock()
	table.insert(buffer, snap)
	-- Reconcile before the frame is drawn, not during the draw: a correction is simulation, and
	-- doing it inside RenderStepped would run it at the render rate rather than once per snapshot.
	if predictor and localIndex and snap.acks then
		for _, a in snap.acks do
			if a.i == localIndex and (a.e or 0) == (matchCfg.inputEpoch or 0) then
				for i, entry in roster do
					if entry.index == localIndex then
						predictor:reconcile(Snapshot.decode(snap.fighters[i]), a.n, snap.platforms)
					end
				end
			end
		end
	end
	while #buffer > 8 do
		table.remove(buffer, 1)
	end
end)

Net.remote("Scene").OnClientEvent:Connect(function(scene: any)
	if not acceptingSnapshots or not matchCfg or scene.id ~= matchCfg.id then return end
	table.insert(scenes, scene)
	while #scenes > 8 do table.remove(scenes, 1) end
end)

-- The final scoreboard, once and reliably. The snapshot stream stops with the match, so without
-- this the client would sit on the last frame with no idea the match had ended.
Net.remote("Results").OnClientEvent:Connect(function(res: any)
	acceptingSnapshots = false
	predictor = nil
	launch:reset()
	if select_ then select_:hide() end
	if hud then
		hud:showResults(res, chars)
	end
	print(`[Blockfall] --- results ({res.mode}, {res.frames} frames, {string.format("%.1f", res.time)}s) ---`)
	for place, row in res.rows do
		print(`[Blockfall]   {place}. {row.name} ({row.avatar}/{row.weapon}) `
			.. `stocks={row.stocks} kos={row.kos} falls={row.falls} dmg={row.damage} pct={math.floor(row.percent)}`)
	end
end)

Net.remote("Events").OnClientEvent:Connect(function(events: { any }, frame: number?)
	for _, e in events do
		if hud then hud:abilityEvent(e) end
		if e.type == "ultimate" and frame then
			local char = chars[(e.fighter or 0) + 1]
			local pal = char and (char.weaponPalette or char.palette)
			ult = { frame = frame, fighter = e.fighter, label = e.label or "ULTIMATE", weapon = e.weapon,
				name = (roster[(e.fighter or 0) + 1] or {}).name or "",
				colour = pal and (pal.glow or pal.accent) or "#FFFFFF" }
		end
		if e.type == "count" then
			print(`[Blockfall] {e.n}`)
		elseif e.type == "go" then
			print("[Blockfall] GO")
		end
		table.insert(pendingFx, { frame = frame or 0, e = e })
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
	drawnFrame = a.frame + (if b then (b.frame - a.frame) * t else 0)
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
local poseElapsed = 0
RunService.Heartbeat:Connect(function(dt: number)
	if launch:expired(os.clock()) and select_ then
		select_:show("Arena delayed. Rejoining your match…")
		Net.remote("Hello"):FireServer()
	end
	if hub.active then
		hub:step(dt, select_ ~= nil and select_.gui.Enabled)
		poseElapsed += dt
		if poseElapsed >= 0.1 then
			poseElapsed = 0
			local f = hub.model.fighter
			Net.remote("HubPose"):FireServer({ area = if hub.room then hub.room.id else 0,
				x = f.x, y = f.y, facing = f.facing, moving = math.abs(f.vx) > 0.1 })
		end
	end
	if not acceptingSnapshots or not matchCfg then
		return
	end
	for _, f in input:sample(dt, FRAME) do
		table.insert(pendingFrames, Net.packFrame(f))
		-- Simulated here, immediately. The server counts exactly the frames we send, so this has
		-- to see every one of them and no others or the replay window drifts.
		if predictor then
			predictor:push(f)
			for _, e in predictor:drain() do
				if LOCAL_FX[e.type] then Effects.spawn(fx, e, glowOf, math.random, heightOf) end
			end
		end
	end
	if #pendingFrames > 0 then
		Net.remote("Input"):FireServer(pendingFrames, matchCfg.id, matchCfg.inputEpoch or 0)
		pendingFrames = {}
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	if select_ then select_:drawPreviews() end
	if hub.active then
		hub:draw(canvas, dt)
		return
	end
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
		if acceptingSnapshots and not warnedSilent and os.clock() - startedAt > 5 then
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
		cam2d.shake = fx.shake * canvas:viewport().Y / 270
		cam2d:update(bodies, dt, canvas:viewport())
	end

	-- The client does NOT step stageView, and must not. Stage.step is simulation: it advances
	-- moving platforms off its own clock and draws hazard RNG from the seeded generator. Running it
	-- here would run it once per RENDER frame rather than once per sim frame, so within seconds the
	-- platforms would be somewhere the server does not agree with and the shared seed would be
	-- consumed a different number of times. Static geometry is correct on the two stages in play;
	-- moving platforms need the server to send their offsets in the snapshot, which is the next
	-- thing to add to Snapshot.FIELDS.
	-- The ultimate's cutscene, timed from the frame its event names. The camera punch is applied to
	-- what is drawn, never to cam2d, so the follow-camera resumes from where it was.
	local cine = UltCinematic.at(if ult then drawnFrame - ult.frame else -1)
	if ult and UltCinematic.over(drawnFrame - ult.frame) then ult = nil end
	local caster: any = nil
	if ult then
		for _, st in states do
			if st.index == ult.fighter then caster = st end
		end
	end
	local casterChar = if caster then chars[caster.index + 1] else nil
	local view = { x = cam2d.x, y = cam2d.y, ppu = cam2d.ppu }
	if cine.active and caster and casterChar then
		view = UltCinematic.punch(cam2d.x, cam2d.y, cam2d.ppu, caster.x, caster.y + casterChar.height * 0.5, cine.zoom)
	end
	Stage2D.sky(canvas, stageView or { data = {} }, view.x)
	canvas:world(view.x, view.y, view.ppu, cam2d.shakeX, cam2d.shakeY)
	if stageView then
		-- The view-only Stage is never stepped; the server sends what it cannot derive. `moving` is
		-- a function of stage time and `sinking` is a function of who is standing on it, and only
		-- the server knows the second.
		Stage.applyDynamicState(stageView, interpBase and interpBase.platforms)
		Stage2D.draw(canvas, stageView)
	end
	local scene = scenes[1]
	for _, candidate in scenes do
		if interpBase and candidate.frame <= interpBase.frame then scene = candidate end
	end
	-- Natural disasters, behind the fighters as on the web, from the shape list both builds share
	-- (DisasterShapes). The server's view rides in the scene stream with the hazard visuals.
	local disaster = if scene and scene.hazards then scene.hazards.disaster else nil
	if disaster and stageView then
		for _, sh in DisasterShapes.shapes(disaster, stageView) do
			local colour = Canvas2D.hex(sh[6], Color3.new(1, 1, 1))
			if sh[1] == "r" then
				Canvas2D.rect(canvas, sh[2], sh[3], sh[4], sh[5], colour, sh[7])
			else
				Canvas2D.ellipse(canvas, sh[2], sh[3], sh[4], sh[5], colour, sh[7])
			end
		end
	end
	if hud then hud.disasterView = disaster end
	for _, st in states do
		local char = chars[st.index + 1]
		if char and not (cine.active and st == caster) then
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
	if scene and stageView then
		World2D.hazards(canvas, scene.hazards or {}, stageView, scene.frame * FRAME)
		World2D.entities(canvas, scene, chars, states, scene.frame * FRAME)
	end
	-- Sparks and rings, from the shape list both builds draw.
	-- (Released anyway past 64 waiting, so a stalled clock can never make them pile up.)
	while pendingFx[1] and (pendingFx[1].frame <= drawnFrame + 0.5 or #pendingFx > 64) do
		local item = table.remove(pendingFx, 1) :: any
		local e = item.e
		if not (predictor and LOCAL_FX[e.type] and e.fighter == localIndex) then
			Effects.spawn(fx, e, glowOf, math.random, heightOf)
		end
		-- and the words that go with it, on the same frame (web/src/main.js does the same)
		if hud then
			if e.type == "ko" then
				local entry = roster[(e.fighter or 0) + 1]
				hud:announce("ko", `{Callouts.ko.text}  {HudColors.MARKS[((e.fighter or 0) % 8) + 1]} {if entry then entry.name else ""}`)
			elseif e.type == "suddendeath" or e.type == "shrink" or e.type == "game" then
				hud:announce(e.type)
			end
		end
	end
	local fxOk, fxErr = pcall(function()
	Effects.step(fx, dt)
	for _, sh in Effects.shapes(fx) do
		if sh[1] == "r" then
			Canvas2D.rect(canvas, sh[2], sh[3], sh[4], sh[5], Canvas2D.hex(sh[6], Color3.new(1, 1, 1)), sh[7])
		else
			local dx, dy = sh[4] - sh[2], sh[5] - sh[3]
			Canvas2D.save(canvas)
			Canvas2D.translate(canvas, sh[2], sh[3])
			Canvas2D.rotate(canvas, math.atan2(dy, dx))
			Canvas2D.rect(canvas, 0, -sh[6] / 2, math.sqrt(dx * dx + dy * dy), sh[6], Canvas2D.hex(sh[7], Color3.new(1, 1, 1)), sh[8])
			Canvas2D.restore(canvas)
		end
	end
	end)
	if not fxOk and not posedWarned[-2] then
		posedWarned[-2] = true
		fx.parts, fx.rings = {}, {}
		warn(`[Blockfall] effects failed to draw, and will not be reported again: {fxErr}`)
	end
	-- Everything but the caster falls into shadow; the caster stands in gold for exactly the frames
	-- they cannot be hit, then is drawn on top of it all, then the banner crosses the screen.
	local banner = nil
	if caster and casterChar and (cine.active or cine.glow) then
		local ok, err = pcall(function()
			if cine.dim > 0 then
				local vp = canvas:viewport()
				Canvas2D.screen(canvas)
				Canvas2D.rect(canvas, 0, 0, vp.X, vp.Y, Color3.fromRGB(5, 6, 10), cine.dim)
				canvas:world(view.x, view.y, view.ppu, cam2d.shakeX, cam2d.shakeY)
			end
			for _, sh in UltCinematic.glowShapes(cine, caster.x, caster.y, casterChar.height) do
				Canvas2D.ellipse(canvas, sh[2], sh[3], sh[4], sh[5], Canvas2D.hex(sh[6], Color3.new(1, 1, 1)), sh[7])
			end
			if cine.active then
				local surface = if stageView then Stage.surfaceUnder(stageView, caster.x, caster.y + 0.1) else nil
				Fighter2D.draw(canvas, caster, casterChar, drawAt, if surface then surface.top else nil)
				local vp = canvas:viewport()
				banner = UltCinematic.bannerLayout(cine, vp.X, vp.Y)
				if banner then UltBanner.paint(canvas, banner, ult.colour, ult.weapon, caster, casterChar, drawAt) end
			end
		end)
		if not ok and not posedWarned[-1] then
			posedWarned[-1] = true
			warn(`[Blockfall] the ultimate cutscene failed to draw, and will not be reported again: {err}`)
		end
		canvas:world(view.x, view.y, view.ppu, cam2d.shakeX, cam2d.shakeY)
	end
	if hud then hud:ultBanner(banner, ult) end
	canvas:finish()
	if hud then
		hud:update(states, buffer[#buffer], canvas, chars, matchCfg)
	end

end)

-- ---------------------------------------------------------------- go ----
Net.remote("Hello"):FireServer()
print("[Blockfall] client ready")
