--!nocheck
-- Reproducible client workload: 6 shipping fighters, Smeltworks' islands/sky/weather and
-- hazards, camera movement, changing poses/damage/stocks, weapon drops, projectiles, and a
-- repeating heavy-hit/finisher effect script. No simulation changes; inputs are view snapshots.
-- Repeats at 120 frames so a warm pass can measure an identical workload without startup art.
local Probe = require("./perf-probe")
local Scene = {}
Scene.W, Scene.H, Scene.PERIOD = 960, 540, 120

function Scene.new(native, sourceRef)
	local P = Probe.new(Scene.W, Scene.H, native, sourceRef)
	local function client(name) return P:load("src/client/" .. name) end
	local function shared(name) return P:load("src/shared/" .. name) end
	local Canvas, FightScene, Hud = client("Canvas2D"), client("FightScene"), client("Hud")
	Canvas.IMAGES = false
	local Fighter, Loadout, Snapshot = shared("Fighter"), shared("Loadout"), shared("Snapshot")
	local Effects, FxPlayer = client("Effects"), client("FxPlayer")
	local Stage, Stages, KIT = shared("Stage"), shared("Data/Stages"), shared("Data/AvatarKit")
	local stage = Stage.new(Stages.BY_ID.Smeltworks, 7)
	local chars, states, roster = {}, {}, {}
	local weapons = { "Sword", "Hammer", "Chakram", "RocketBoots", "Scythe", "Gauntlets" }
	for i, weapon in weapons do
		local char = Loadout.build(KIT.presets[(i - 1) % #KIT.presets + 1].code, weapon)
		chars[i] = char
		local f = Fighter.new({ index = i - 1, char = char, x = (i - 3.5) * 5, y = stage.main.top, stocks = 3 })
		f.onGround, f.invincible = true, 0
		states[i] = Snapshot.decode(Snapshot.encode(f))
		roster[i] = { index = i - 1, name = "CPU " .. i, weapon = weapon, height = char.height }
	end
	local root = P.new("Folder")
	local canvas, hud = Canvas.new(root), Hud.new(root)
	local cfg = { fighters = roster, timed = true, timeLimit = 180, stocks = 3 }
	hud:bind(roster, chars, 0, false)
	local fx, player = Effects.new(), FxPlayer.new()
	-- Render-side particles are seeded too, including those emitted by Fighter2D/World2D.
	client("Fighter2D").effects = fx
	client("World2D").effects = fx
	local world = { frame = 0, hazards = {
			vents = { positions = { -20, 20 }, armed = { -20, 20 }, width = 7, phase = "active", strength = 0.4 },
			slagfall = { x = -1, spread = 9, from = 14, drops = { { x = -2, y = 8 }, { x = 2, y = 5 } } },
		}, drops = { { x = 10, y = 0, life = 500, onGround = true, look = "Sword" } },
		summons = {}, bursts = {}, items = {
			{ id = "BlastKeg", x = -15, y = stage.main.top, onGround = true },
			{ id = "RivetGun", x = 7, y = stage.main.top, onGround = true },
		}, projectiles = {
			{ x = -8, y = 8, vx = 8, vy = 0, w = 0.6, h = 0.3, owner = 0, shape = "tracer" },
			{ x = 6, y = 7, vx = -6, vy = 0, w = 0.6, h = 0.3, owner = 1, shape = "tracer" },
		} }
	local S = { view = { x = 0, y = stage.main.top + 4.5, ppu = 18 }, shakeX = 0, shakeY = 0,
		stage = stage, scene = world, states = states, chars = chars, t = 0, fx = fx, player = player, startStocks = 3 }
	local snap = { state = "fight", time = 10 }
	for _, pair in {
		{ "Stage2D", "sky", "Sky" }, { "Stage2D", "draw", "Stage" },
		{ "RealmArt", "weather", "Weather" }, { "Fighter2D", "draw", "Fighters" },
		{ "HitReact", "draw", "Hit reactions" }, { "HazardArt", "draw", "Hazards" },
		{ "World2D", "entities", "World" }, { "UltWorld", "under", "Ultimate world" },
		{ "UltWorld", "over", "Ultimate world" }, { "FxPlayer", "draw", "Timed effects" },
		{ "Canvas2D", "finish", "Finish" }, { "Hud", "update", "HUD" },
		{ "Effects", "step", "Effect step" }, { "FxPlayer", "step", "Effect step" },
	} do P:wrap(client(pair[1]), pair[2], pair[3]) end
	local self = { probe = P, canvas = canvas, hud = hud, state = S, snap = snap, cfg = cfg,
		Canvas = Canvas, FightScene = FightScene, Effects = Effects, FxPlayer = FxPlayer }
	self.setup = { writes = P.total.writes, creates = P.total.creates, destroys = P.total.destroys, liveFrames = P:frames() }
	return setmetatable(self, { __index = Scene })
end

function Scene:prepare(frame)
	local S, n = self.state, (frame - 1) % Scene.PERIOD
	self.probe.now, S.t = 10 + n / 60, n / 60
	S.view.x = math.sin(n * math.pi / 60) * 1.2
	S.scene.frame, self.snap.time = n, 10 + n / 60
	for i, st in S.states do
		st.x = (if i <= 3 then -30 + i * 5 else -14 + i * 6) + math.sin(n * 0.04 + i) * 0.75
		st.y = S.stage.main.top
		st.facing = if (math.floor(n / 30) + i) % 2 == 0 then 1 else -1
		st.state, st.onGround = if i % 2 == 0 then "run" else "idle", true
		st.vx = if st.state == "run" then S.chars[i].runSpeed * st.facing else 0
		st.frameCount, st.sf = n, n % 24
		st.invincible = if i == 6 and n < 18 then 1 else 0
		st.percent, st.stocks, st.ultCharge = 18 * (i - 1) + math.floor(n / 20), if i == 6 then 1 else 3, (i * 3 + math.floor(n / 30)) % 21
	end
	S.scene.projectiles[1].x, S.scene.projectiles[2].x = -15 + n / 4, 14 - n / 5
	S.scene.hazards.vents.phase = if n < 40 then "warn" elseif n < 90 then "active" else "idle"
	for i, drop in S.scene.hazards.slagfall.drops do drop.y = 14 - ((n / 8 + i * 4) % 18) end
end

function Scene:draw(frame)
	local S, n = self.state, (frame - 1) % Scene.PERIOD
	self.probe.section = "Effects/other"
	if n % 12 == 0 then
		local attacker = (n // 12) % 6
		local victim = (attacker + 1) % 6
		local v = S.states[victim + 1]
		local event = { type = "hit", attacker = attacker, victim = victim, x = v.x, y = v.y + 2.5,
			damage = 12, angle = 45, facing = S.states[attacker + 1].facing, heavy = true, finisher = n == 60 }
		self.FightScene.spawn(S.fx, S.player, event, S.states, S.chars,
			function(i) return S.chars[(i or 0) + 1].weaponPalette.glow end, self.probe.math.random,
			function(i) return S.chars[(i or 0) + 1].height end, true)
		self.hud:comboEvent(event)
	end
	self.Effects.step(S.fx, 1 / 60)
	self.FxPlayer.step(S.player, 1 / 60)
	local banner = self.FightScene.draw(self.canvas, S)
	self.probe.section = "HUD"
	self.hud:ultBanner(banner, nil)
	self.canvas:finish()
	self.hud:update(S.states, self.snap, self.canvas, S.chars, self.cfg)
end

return Scene
