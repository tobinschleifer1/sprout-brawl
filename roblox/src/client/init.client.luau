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
local Realms = require(Shared.Realms)
local InputClient = require(script.InputClient)
local Camera2D = require(script.Camera2D)
local Canvas2D = require(script.Canvas2D)
local UltCinematic = require(script.UltCinematic)
local FightScene = require(script.FightScene)
local FxPlayer = require(script.FxPlayer)
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
local Plaza2D = require(script.Plaza2D)
local AvatarEditor = require(script.AvatarEditor)
local LobbySocial = require(script.LobbySocial)
local ParkourView = require(script.ParkourView)
local ClimbRecords = require(script.ClimbRecords)
local Plaza = require(Shared.Plaza)
local PresenceCodec = require(Shared.PresenceCodec)
local SnapshotCodec = require(Shared.SnapshotCodec)
local SceneCodec = require(Shared.SceneCodec)
local PerfMonitor = require(script.PerfMonitor)
local Interp = require(script.Interp)
local SkipProducts = require(Shared.SkipProducts)
local MarketplaceService = game:GetService("MarketplaceService")
local UIS = game:GetService("UserInputService")

local FRAME = Config.FRAME
-- Two snapshots of buffer. Snapshots arrive at 30Hz but not evenly, and drawing the newest one the
-- instant it lands means every jittered packet is a visible stutter. Rendering two snapshots in
-- the past costs about 67ms on remote fighters; the local fighter still uses prediction.
-- (Now measured: see Interp. It starts here, at four frames, until snapshots give it something.)

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
-- The last snapshot received: what the server's next delta is made against (SnapshotCodec). Nil
-- until a keyframe arrives; a new match description clears it.
local snapBase: any = nil
-- Likewise the last scene (SceneCodec), the base its deltas apply to.
local sceneBase: any = nil
-- Draw cost and connection health (PerfMonitor): F3 shows it; attributes carry it to Studio.
local perf = PerfMonitor.new()
-- How far in the past other fighters are drawn, from how evenly snapshots arrive (Interp).
local interp = Interp.new(FRAME)
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
-- The ultimates' timed pixel-art effects - explosions, shockwaves, pillars, impact stars (FxPlayer).
local fxPlayer = FxPlayer.new()
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
local hub = Plaza2D.new(Players.LocalPlayer:WaitForChild("PlayerGui"))
-- The character studio. It owns nothing the server does not confirm: it sends a code and a name,
-- and the character you wear is whatever the server's AvatarView says.
local editor = AvatarEditor.new(Players.LocalPlayer:WaitForChild("PlayerGui"), {
	send = function(msg: any) Net.remote("Avatar"):FireServer(msg) end,
	weapon = function(): string return if select_ then select_.cfg.slots[1].weaponId else "Sword" end,
})
local function openStudio()
	if hub.active and not hub.room and not (select_ and select_.gui.Enabled) then editor:open() end
end
hub.onCharacter = openStudio
-- Stamps, quick messages, who is here, and warps (LobbySocial); the lobby draws what it hears.
local social = LobbySocial.new(Players.LocalPlayer:WaitForChild("PlayerGui"), {
	localId = Players.LocalPlayer.UserId,
	send = function(msg: any) Net.remote("Social"):FireServer(msg) end,
	requestMembers = function() Net.remote("Members"):FireServer() end,
	warp = function(id: string): boolean return hub.active and not hub.room and hub:warp(id) end,
	-- Next to a friend: beside them if there is floor there, on their spot if not.
	warpTo = function(m: any): boolean
		if not hub.active or hub.room or type(m.x) ~= "number" or type(m.z) ~= "number" then return false end
		local scene = hub.model.data
		for _, dx in { 2.5, -2.5, 0 } do
			if Plaza.walkable(scene, m.x + dx, m.z) then
				hub.model:setScene(scene, { x = m.x + dx, z = m.z })
				return true
			end
		end
		return false
	end,
})
hub.social, hub.localId = social, Players.LocalPlayer.UserId
-- The Skyline Climb. The climb runs here; the server keeps progress (ClimbProgress). Entering asks
-- the server where to start - the bottom, or the furthest checkpoint reached - and the answer
-- starts it.
local climbWanted = false
local function askClimb(from: any)
	climbWanted = true
	Net.remote("Climb"):FireServer({ action = "enter", from = from })
end
-- The climb's leaderboards: from the CLIMB RECORDS board at its foot, or the climb's RECORDS button.
local records = ClimbRecords.new(Players.LocalPlayer:WaitForChild("PlayerGui"), { localId = Players.LocalPlayer.UserId })
Net.remote("ClimbBoards").OnClientEvent:Connect(function(view: any)
	records:set(view)
	-- The board in the lobby shows who leads, so the boards are worth walking over to.
	local top = type(view) == "table" and type(view.speed) == "table" and view.speed[1]
	local high = type(view) == "table" and type(view.levels) == "table" and view.levels[1]
	hub.recordsLine = if top then `FASTEST  {top.name}  {ClimbRecords.clock(top.frames)}`
		elseif high then `HIGHEST  {high.name}  ·  {ClimbRecords.reach(high.best, high.summits)}` else nil
end)
-- Paid skips (SkipProducts). The price shown is the product's own once Marketplace answers - it is
-- what the player is charged - and the configured one until then. While the purchase prompt is up
-- the climb holds still, so nobody climbs past the checkpoint they are paying to skip.
local skipPrompt = false
local skipPrices: { [number]: any } = {}
local function skipPrice(index: number): number?
	local id, price = SkipProducts.forCheckpoint(index)
	if id and skipPrices[index] == nil then
		skipPrices[index] = false
		task.spawn(function()
			local ok, info = pcall(function() return MarketplaceService:GetProductInfo(id, Enum.InfoType.Product) end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then skipPrices[index] = info.PriceInRobux end
		end)
	end
	return skipPrices[index] or price
end
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number)
	if userId == Players.LocalPlayer.UserId then skipPrompt = false end
end)
local parkour: any
parkour = ParkourView.new(Players.LocalPlayer:WaitForChild("PlayerGui"), {
	send = function(msg: any) Net.remote("Climb"):FireServer(msg) end,
	records = function() records:toggle() end,
	price = skipPrice,
	skip = function(index: number)
		local id = SkipProducts.forCheckpoint(index)
		if not id then
			-- In Studio, for testing the course before its products exist: free, and the server moves
			-- you exactly as a bought skip would. A live server refuses it (init.server "studioSkip").
			if RunService:IsStudio() then
				Net.remote("Climb"):FireServer({ action = "studioSkip" })
				parkour:say("SKIPPING · FREE IN STUDIO", Color3.fromRGB(138, 148, 166))
				return
			end
			parkour:say("SKIPS ARE NOT ON SALE YET", Color3.fromRGB(138, 148, 166))
			return
		end
		skipPrompt = true
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, id)
	end,
	restart = function() askClimb(0) end,
	leave = function()
		records:close()
		Net.remote("Climb"):FireServer({ action = "leave" })
		if select_ then hub:show(select_.cfg) end
	end,
})
Net.remote("ClimbView").OnClientEvent:Connect(function(view: any)
	parkour:setProgress(view)
	records:setMine(view)
	-- A bought skip, granted and saved: stand on it now.
	if type(view.skipTo) == "number" and parkour.active then parkour:skipTo(view.skipTo) end
	if climbWanted and type(view.start) == "number" and select_ then
		climbWanted = false
		hub:hide()
		social:setEnabled(false)
		editor.gui.Enabled = false
		parkour:start(select_.cfg.slots[1].avatarId, view.start)
	end
end)
Net.remote("SocialEvent").OnClientEvent:Connect(function(ev: any) social:onEvent(ev) end)
-- The arcade: sit, stand, vs CPU, watch. The server decides; the lobby draws what it says.
hub.onCabinet = function(intent: any) Net.remote("CabinetAction"):FireServer(intent) end
Net.remote("Cabinets").OnClientEvent:Connect(function(views: any, why: string?)
	hub:setCabinets(views, Players.LocalPlayer.UserId)
	if why then social:addLog(why, Color3.fromRGB(255, 181, 71)) end
end)
-- Watching a cabinet fight: the match plays with no fighter of our own; this is the way out.
local watchGui = Instance.new("ScreenGui")
watchGui.Name, watchGui.ResetOnSpawn, watchGui.DisplayOrder, watchGui.Enabled = "BlockfallWatching", false, 14, false
watchGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local stopWatching = Instance.new("TextButton")
stopWatching.Name, stopWatching.Text, stopWatching.Font, stopWatching.TextSize = "StopWatching", "STOP WATCHING", Enum.Font.GothamBold, 15
stopWatching.AnchorPoint, stopWatching.Position, stopWatching.Size = Vector2.new(1, 0), UDim2.new(1, -16, 0, 12), UDim2.fromOffset(170, 38)
stopWatching.BackgroundColor3, stopWatching.TextColor3, stopWatching.BorderSizePixel = Color3.fromRGB(28, 24, 44), Color3.fromRGB(255, 79, 163), 0
stopWatching.Parent = watchGui
stopWatching.Activated:Connect(function() Net.remote("CabinetAction"):FireServer({ action = "unwatch" }) end)
Net.remote("Members").OnClientEvent:Connect(function(list: any) social:setMembers(list) end)
Net.remote("AvatarView").OnClientEvent:Connect(function(view: any)
	editor:setView(view)
	local worn = view.slots and view.slots[view.active]
	if worn and select_ then
		select_.cfg.slots[1].avatarId = worn.code
		hub:configure(select_.cfg)
	end
end)
UIS.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if records:key(input.KeyCode) then return end
	if hub.active and not editor:isOpen() and not (select_ and select_.gui.Enabled) and not UIS:GetFocusedTextBox() then
		social:key(input.KeyCode)
	end
	editor:key(input.KeyCode, UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
		or UIS:IsKeyDown(Enum.KeyCode.LeftMeta) or UIS:IsKeyDown(Enum.KeyCode.RightMeta))
end)

-- ---------------------------------------------------------------- match setup ----
-- The server says "pick a match". It also says when it refused one, and why.
Net.remote("Select").OnClientEvent:Connect(function(msg: any)
	watchGui.Enabled = false
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
				if station.kind == "Wardrobe" then
					openStudio()
				elseif station.kind == "Parkour" then
					askClimb(if parkour.progress.best > 0 then "best" else 0)
				elseif station.kind == "Records" then
					records:toggle()
				elseif station.kind == "Members" then
					social:toggle("People")
				elseif station.kind == "Warp" then
					social:toggle("Map")
				elseif station.kind == "Format" then
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
-- Who is where in the lobby: positions every tenth of a second, who they are only when it changes.
local presenceRoster: { [number]: any } = {}
Net.remote("HubPresence").OnClientEvent:Connect(function(positions: any, roster: any)
	if roster then presenceRoster = PresenceCodec.index(roster) end
	hub:setPeers(PresenceCodec.decode(positions, presenceRoster), Players.LocalPlayer.UserId)
end)

Net.remote("Match").OnClientEvent:Connect(function(cfg: any)
	launch:accept(os.clock())
	editor.gui.Enabled = false             -- a fight starting closes the studio
	records:close()
	if select_ then
		select_:waiting("Loading arena and fighters…")
	end
	canvas:clear()
	snapBase = nil
	sceneBase = nil
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
	FxPlayer.clear(fxPlayer)
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
	watchGui.Enabled = localIndex == nil      -- no fighter of ours: we are watching
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
	if stageView then hud:announce("stage", Realms.name(stageView.data)) end
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

Net.remote("Snapshot").OnClientEvent:Connect(function(packed: any)
	local snap = SnapshotCodec.decode(packed, snapBase)
	if not snap then
		return            -- a delta we have no base for: the next keyframe is at most a second away
	end
	snapBase = snap
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
		social:setEnabled(false)
	end
	snap.t = os.clock()
	interp:arrive(snap.t)
	perf:arrival(snap.t, SnapshotCodec.size(packed))
	table.insert(buffer, snap)
	-- Reconcile before the frame is drawn, not during the draw: a correction is simulation, and
	-- doing it inside RenderStepped would run it at the render rate rather than once per snapshot.
	if predictor and localIndex and snap.acks then
		for _, a in snap.acks do
			if a.i == localIndex and (a.e or 0) == (matchCfg.inputEpoch or 0) then
				for i, entry in roster do
					if entry.index == localIndex then
						predictor:reconcile(Snapshot.decode(snap.fighters[i]), a.n, snap.platforms)
						if (predictor.lastCorrection or 0) > 0.05 then perf:correction(os.clock(), predictor.lastCorrection) end
					end
				end
			end
		end
	end
	while #buffer > 8 do
		table.remove(buffer, 1)
	end
end)

Net.remote("Scene").OnClientEvent:Connect(function(packet: any)
	-- a delta against the last scene, or a keyframe (SceneCodec)
	local scene = SceneCodec.decode(packet, sceneBase)
	if not scene then return end
	sceneBase = scene
	perf:received(os.clock(), 0)
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
	if records:isOpen() then records:tick() end
	if parkour.active then parkour:step(dt, records:isOpen() or skipPrompt) end
	if hub.active then
		hub:step(dt, (select_ ~= nil and select_.gui.Enabled) or editor:isOpen() or records:isOpen())
		if not social.enabled then social:setEnabled(true) end
		poseElapsed += dt
		if poseElapsed >= 0.1 then
			poseElapsed = 0
			local f = hub.model.p
			Net.remote("HubPose"):FireServer({ area = if hub.room then hub.room.id else 0,
				x = f.x, z = f.z, y = f.y, facing = f.facing, moving = f.state == "run" })
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

-- The F3 overlay (PerfMonitor): draw cost, connection health and the server's numbers.
local perfLabel = Instance.new("TextLabel")
perfLabel.Name = "PerfOverlay"
perfLabel.BackgroundColor3 = Color3.fromRGB(12, 10, 18)
perfLabel.BackgroundTransparency = 0.25
perfLabel.TextColor3 = Color3.fromRGB(230, 240, 255)
perfLabel.Font = Enum.Font.Code
perfLabel.TextSize = 14
perfLabel.TextXAlignment = Enum.TextXAlignment.Left
perfLabel.TextYAlignment = Enum.TextYAlignment.Top
perfLabel.Position = UDim2.fromOffset(8, 64)
perfLabel.Size = UDim2.fromOffset(560, 74)
perfLabel.ZIndex = 1000000
perfLabel.Visible = false
perfLabel.Parent = canvas.gui
UIS.InputBegan:Connect(function(io: InputObject)
	if io.KeyCode == Enum.KeyCode.F3 and not UIS:GetFocusedTextBox() then perfLabel.Visible = not perfLabel.Visible end
end)
local function measured(dt: number, began: number)
	perf.interp = interp.delay
	local ok, ping = pcall(function() return Players.LocalPlayer:GetNetworkPing() end)
	if ok then perf.ping = ping end
	perf:frame(dt, os.clock() - began, canvas.lastUsed or 0, canvas.lastSprites or 0)
	local s = perf:publish(canvas.gui, os.clock())
	if s and perfLabel.Visible then
		perfLabel.Text = PerfMonitor.describe(s, { stepMs = ReplicatedStorage:GetAttribute("ServerStepMs"),
			outKBs = ReplicatedStorage:GetAttribute("ServerOutKBs") })
	end
end

-- Where a frame's time goes, section by section, published with the rest (PerfSection*).
local function section(name: string, t0: number): number
	local now = os.clock()
	perf:section(name, now - t0)
	return now
end

RunService.RenderStepped:Connect(function(dt: number)
	local began = os.clock()
	local mark = began
	if select_ then select_:drawPreviews() end
	mark = section("Previews", mark)
	if parkour.active then
		parkour:draw(canvas, dt)
		section("Climb", mark)
		measured(dt, began)
		return
	end
	if hub.active then
		hub:draw(canvas, dt)
		mark = section("Lobby", mark)
		editor:draw(os.clock())
		section("Editor", mark)
		measured(dt, began)
		return
	end
	local drawAt = os.clock()
	local states = interpolate(drawAt - interp.delay)
	-- Our own fighter, predicted. Interpolation exists to hide other people's packet jitter, and
	-- applying it to the local fighter cost the interpolation delay on top of the round trip. This is the
	-- fighter as our own inputs have already taken it, corrected against the server on every
	-- snapshot - so it answers on the frame the key went down.
	if states and predictor and predictor.ready then
		for i, st in states do
			if st.index == localIndex then
				-- eased from the last correction rather than jumping to it (Predictor.visual)
				states[i] = predictor:visual(dt)
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
	local scene = scenes[1]
	for _, candidate in scenes do
		if interpBase and candidate.frame <= interpBase.frame then scene = candidate end
	end
	-- Events wait until the drawn picture reaches the frame they happened on, then set off their
	-- sparks (Effects) and their drawn moments (FxPlayer), and the words that go with them.
	-- (Released anyway past 64 waiting, so a stalled clock can never make them pile up.)
	while pendingFx[1] and (pendingFx[1].frame <= drawnFrame + 0.5 or #pendingFx > 64) do
		local item = table.remove(pendingFx, 1) :: any
		local e = item.e
		local sparks = not (predictor and LOCAL_FX[e.type] and e.fighter == localIndex)
		local ok, err = pcall(FightScene.spawn :: any, fx, fxPlayer, e, states, chars, glowOf, math.random, heightOf, sparks)
		if not ok and not posedWarned[-4] then
			posedWarned[-4] = true
			warn(`[Blockfall] an ultimate effect failed to start, and will not be reported again: {err}`)
		end
		-- (web/src/main.js puts the words up on the same frame)
		if hud then
			if e.type == "ko" then
				local entry = roster[(e.fighter or 0) + 1]
				hud:announce("ko", `{Callouts.ko.text}  {HudColors.MARKS[((e.fighter or 0) % 8) + 1]} {if entry then entry.name else ""}`)
			elseif e.type == "suddendeath" or e.type == "shrink" or e.type == "game" then
				hud:announce(e.type)
			end
		end
	end
	Effects.step(fx, dt)
	FxPlayer.step(fxPlayer, dt)
	if hud then
		hud.disasterView = if scene and scene.hazards then scene.hazards.disaster else nil
	end
	local fightMark = os.clock()
	local banner = FightScene.draw(canvas, {
		view = view, shakeX = cam2d.shakeX, shakeY = cam2d.shakeY,
		stage = stageView, platforms = interpBase and interpBase.platforms,
		scene = scene, states = states, chars = chars, t = drawAt, fx = fx, player = fxPlayer,
		cine = cine, caster = caster, casterChar = casterChar, ult = ult,
		report = function(key: number, err: string)
			if posedWarned[key] then return end
			posedWarned[key] = true
			if key == -2 then fx.parts, fx.rings = {}, {} end
			warn(`[Blockfall] {err}, and will not be reported again`)
		end,
	})
	fightMark = section("Fight", fightMark)
	if hud then hud:ultBanner(banner, ult) end
	canvas:finish()
	fightMark = section("Finish", fightMark)
	if hud then
		hud:update(states, buffer[#buffer], canvas, chars, matchCfg)
	end
	section("Hud", fightMark)
	measured(dt, began)

end)

-- ---------------------------------------------------------------- go ----
Net.remote("Hello"):FireServer()
print("[Blockfall] client ready")
