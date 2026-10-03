--!strict
-- The ultimates' pixel-art effects, end to end: every ultimate played in a real Match, the scene
-- sent as the server sends it, its events released through FightScene.spawn, and every frame drawn
-- through FightScene.draw - the client's own draw - with the primitives counted.
--
-- What it holds:
--   * FxArt: every drawing, every frame, compiles to rectangles that repaint its grid exactly, the
--     same table comes back for the same drawing (Canvas2D.sprite's identity), ramps run dark to
--     light, opacity fades in a few steps;
--   * the state an ultimate's world layer needs reaches the client in the scene: the anchor, the
--     barrier's soak, the painted target, the bleed marks - and survives a remote's serialisation;
--   * every ultimate draws world/timed effects of its own, its projectiles as what they are, its
--     explosions in the caster's colour, and replaces (not doubles) the plain rings;
--   * what it all costs: Frames in the worst frame, and the sprites an ultimate builds once.
--
--     lune run tests/ult-fx

local Loader = require("./loader")
local serde = require("@lune/serde")
local Match = Loader.load("Match")
local Loadout = Loader.load("Loadout")
local Input = Loader.load("Input")
local Snapshot = Loader.load("Snapshot")
local SceneSnapshot = Loader.load("SceneSnapshot")
local Stage = Loader.load("Stage")
local Stages = Loader.load("Data/Stages")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local FxArt = Loader.loadFrom("src/client/", "FxArt")
local FxPlayer = Loader.loadFrom("src/client/", "FxPlayer")
local Effects = Loader.loadFrom("src/client/", "Effects")
local FightScene = Loader.loadFrom("src/client/", "FightScene")
local UltCinematic = Loader.loadFrom("src/client/", "UltCinematic")

local function fail(msg: string): never
	error(msg, 0)
end

-- ------------------------------------------------------------------ FxArt ----
local arts = 0
local widest = 0
for _, kind in FxArt.kinds() do
	for f = 0, FxArt.FRAMES[kind] - 1 do
		for _, ramp in { "#9FE8FF", "fire", "#FF4A6A" } do
			local art = FxArt.get(kind, f, ramp, nil, 3)
			if FxArt.get(kind, f, ramp, nil, 3) ~= art then fail(`{kind}/{f}: a second get built a new table`) end
			if #art.rects == 0 then fail(`{kind}/{f}: an empty drawing`) end
			widest = math.max(widest, #art.rects)
			-- the rectangles repaint the grid, tone for tone, with no overlaps and nothing extra
			local g = FxArt.paint(kind, f, 3)
			local got = table.create(g.w * g.h, 0)
			local A, B = FxArt.rampOf(ramp), FxArt.rampOf("earth")
			for _, r in art.rects do
				for y = r[2], r[2] + r[4] - 1 do
					for x = r[1], r[1] + r[3] - 1 do
						local i = y * g.w + x + 1
						if got[i] ~= 0 then fail(`{kind}/{f}: rectangles overlap at {x},{y}`) end
						got[i] = r
					end
				end
			end
			for i, tone in g.cells do
				local r = got[i]
				if tone == 0 then
					if r ~= 0 then fail(`{kind}/{f}: painted an empty cell`) end
				else
					if r == 0 then fail(`{kind}/{f}: dropped a pixel`) end
					local want = if tone <= 5 then A[tone] elseif tone <= 10 then B[tone - 5] else A[tone - 10]
					if r[5] ~= want then fail(`{kind}/{f}: tone {tone} drawn {r[5]}, want {want}`) end
					if r[6] ~= (if tone > 10 then 0.45 else 1) then fail(`{kind}/{f}: tone {tone} at alpha {r[6]}`) end
				end
			end
			if art.cols ~= g.w or art.rows ~= g.h then fail(`{kind}/{f}: art size differs from its grid`) end
			arts += 1
		end
	end
end
if widest > 260 then fail(`an effect drawing costs {widest} rectangles, over 260`) end
-- No variation of any drawing is empty: an empty sprite is a container Frame showing nothing.
for _, kind in FxArt.kinds() do
	for f = 0, FxArt.FRAMES[kind] - 1 do
		for seed = 1, 12 do
			if #FxArt.get(kind, f, "fire", nil, seed).rects == 0 then fail(`{kind}/{f} seed {seed} is empty`) end
		end
	end
end

-- Ramps: five tones, each lighter than the last, for every weapon's glow.
local function luma(hex: string): number
	local r = tonumber(string.sub(hex, 2, 3), 16) :: number
	local g = tonumber(string.sub(hex, 4, 5), 16) :: number
	local b = tonumber(string.sub(hex, 6, 7), 16) :: number
	return 0.299 * r + 0.587 * g + 0.114 * b
end
for _, w in Loader.load("Data/Weapons").LIST do
	local ramp = FxArt.ramp(w.palette.glow)
	if #ramp ~= 5 then fail(`{w.id}: ramp has {#ramp} tones`) end
	for i = 2, 5 do
		if luma(ramp[i]) <= luma(ramp[i - 1]) then fail(`{w.id}: ramp tone {i} {ramp[i]} is not lighter than {ramp[i - 1]}`) end
	end
	if luma(ramp[5]) < 235 then fail(`{w.id}: the core tone {ramp[5]} is not white-hot`) end
end
-- Fades step in sixths, so a fading sprite rewrites its children a handful of times.
local steps: { [number]: boolean } = {}
for i = 0, 100 do steps[FxArt.quantise(i / 100)] = true end
local nSteps = 0
for _ in steps do nSteps += 1 end
if nSteps ~= 7 then fail(`opacity takes {nSteps} values, not 7`) end

-- ------------------------------------------------------------------ the counting canvas ----
local frames, sprites = 0, 0
local keys: { [string]: number } = {}
local built: { [string]: number } = {}
local function count(c: any) frames += 1 end
Canvas.rect = function(c: any, x: number, y: number, w: number, h: number, _col: any, _a: number?)
	for _, v in { x, y, w, h } do
		if v ~= v or math.abs(v) == math.huge then fail("non-finite rect") end
	end
	count(c)
end
Canvas.ellipse = function(c: any) count(c) end
Canvas.circle = function(c: any) count(c) end
Canvas.sprite = function(c: any, key: string, rects: any)
	count(c)
	sprites += 1
	if string.sub(key, 1, 3) == "fx|" then
		local k = string.match(key, "^fx|(%a+)|") :: string
		keys[k] = (keys[k] or 0) + 1
		built[key] = #rects
	end
	if #rects == 0 then fail(`sprite {key} has no rectangles`) end
end
local function canvas(): any
	return setmetatable({ used = 0, stack = {}, alpha = 1, alphaStack = {}, m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 },
		gui = { AbsoluteSize = { X = 1280, Y = 720 } } }, { __index = Canvas })
end

-- ------------------------------------------------------------------ every ultimate, played ----
local stageData = Stages.LIST[1]
local peak, peakWhere = 0, ""
local report = {}
local function play(weapon: string, gap: number): any
	local held = false
	local input = { poll = function() end, get = function(_, source: string)
		local f = Input.emptyFrame()
		if source == "p1" and held then f.ult = true end
		return f
	end }
	local m = Match.new({ mode = "Training", stage = stageData, seed = 1, items = false, input = input, fighters = {
		{ char = Loadout.build("Classic", weapon), source = "p1", team = 0 },
		{ char = Loadout.build("Noir", "Sword"), source = "e1", team = 1 },
		{ char = Loadout.build("Classic", "Hammer"), source = "e2", team = 2 },
	} })
	m.state = "fight"
	local top = m.stage.main.top
	for i, f in m.fighters do
		f:reset(-5 + (i - 1) * gap, top, { state = "idle", invincible = 0 })
		f.onGround, f.platform, f.facing = true, m.stage.main, if i == 1 then 1 else -1
	end
	local chars = {}
	for i, f in m.fighters do chars[i] = f.char end
	local fx, player = Effects.new(), FxPlayer.new()
	local stage = Stage.new(stageData, 1)
	local seen: any = { fx = {}, ults = {}, bleed = 0, tgt = nil, abs = nil, anchor = nil, comets = 0, inUlt = 0, kinds = {} }
	table.clear(keys)
	table.clear(built)
	local ultFrame: number? = nil
	local rand = (function()
		local s = 11
		return function() s = (s * 48271) % 2147483647; return s / 2147483647 end
	end)()
	for frame = 0, 260 do
		if frame == 0 then m.fighters[1].ultCharge = 100 end
		held = frame == 0 or (frame % 20 == 0 and frame < 160)
		m:step()
		local states = {}
		for _, f in m.fighters do table.insert(states, Snapshot.decode(Snapshot.encode(f))) end
		-- through a remote's serialisation, as the client receives it
		local scene = serde.decode("json", serde.encode("json", SceneSnapshot.encode(m)))
		for _, u in scene.ults or {} do
			if u.i == 0 then
				if u.ax then seen.anchor = { u.ax, u.ay } end
				if u.abs then seen.abs = u.abs end
				if u.tgt then seen.tgt = u.tgt end
			end
		end
		seen.bleed = math.max(seen.bleed, #(scene.bleed or {}))
		for _, e in m.events do
			if e.type == "ultimate" and not ultFrame then ultFrame = frame end
			seen.kinds[e.type] = true
			FightScene.spawn(fx, player, e, states, chars, function(i) local ch = chars[(i or 0) + 1]; return ch and ch.weaponPalette.glow end,
				rand, function() return 5.2 end, true)
		end
		table.clear(m.events)
		Effects.step(fx, 1 / 60)
		FxPlayer.step(player, 1 / 60)
		local before = table.clone(keys)
		frames, sprites = 0, 0
		local c = canvas()
		local cine = UltCinematic.at(if ultFrame then frame - ultFrame else -1)
		FightScene.draw(c, { view = { x = 0, y = top + 6, ppu = 22 }, shakeX = 0, shakeY = 0, stage = stage, scene = scene,
			states = states, chars = chars, t = frame / 60, fx = fx, player = player, cine = cine,
			caster = if ultFrame then states[1] else nil, casterChar = chars[1],
			ult = { colour = chars[1].weaponPalette.glow, weapon = weapon } })
		if #c.stack ~= 0 then fail(`{weapon} frame {frame}: the scene left the transform stack at {#c.stack}`) end
		if frames > peak then peak, peakWhere = frames, `{weapon} frame {frame}` end
		if states[1].moveId == "Ultimate" then seen.inUlt += 1 end
		if (keys.comet or 0) > (before.comet or 0) then seen.comets += 1 end
	end
	local nBuilt, nRects = 0, 0
	for _, n in built do nBuilt += 1; nRects += n end
	seen.built, seen.rects = nBuilt, nRects
	seen.drew = table.clone(keys)
	seen.keys = table.clone(built)
	seen.glow = chars[1].weaponPalette.glow
	return seen
end

-- What each ultimate must be seen to draw: the FxArt drawings that are its signature.
local SIGNATURE: { [string]: { string } } = {
	Sword = { "crescent", "fissure", "flame", "burst" },
	Scythe = { "swirl", "burst", "crescent" },
	Blasters = { "reticle", "comet", "pop" },
	Grimoire = { "rune", "comet", "orb", "star" },
	Axe = { "cyclone", "crescent" },
	Pike = { "lance", "pop" },
	Gauntlets = { "pop", "burst" },
	Hammer = { "pillar", "fissure", "flame" },
	Longbow = { "lance", "orb", "ring" },
	Flail = { "rune", "burst", "bolt" },
	Shield = { "dome", "burst", "bolt" },
	Daggers = { "xslash", "sigil", "burst" },
}
local mostBuilt, mostBuiltWhere = 0, ""
local mostRects, mostRectsWhere = 0, ""
for _, w in Loader.load("Data/Weapons").LIST do
	local seen = play(w.id, if w.id == "Daggers" or w.id == "Gauntlets" then 3.5 else 7)
	if seen.inUlt < 20 then fail(`{w.id}: the ultimate never ran ({seen.inUlt} frames)`) end
	if (seen.drew.rune or 0) == 0 then fail(`{w.id}: no rune circle under the caster`) end
	for _, kind in SIGNATURE[w.id] do
		if (seen.drew[kind] or 0) == 0 then fail(`{w.id}: never drew its {kind}`) end
	end
	if seen.built > mostBuilt then mostBuilt, mostBuiltWhere = seen.built, w.id end
	if seen.rects > mostRects then mostRects, mostRectsWhere = seen.rects, w.id end
	if w.id == "Flail" and not seen.anchor then fail("Flail: the anchor never reached the scene") end
	-- the chain's anchor stands in a rune circle of its own, distinct from the caster's (variation 5)
	if w.id == "Flail" and not seen.keys[`fx|rune|0|{seen.glow}|-|5`] then fail("Flail: no chain or anchor drawn") end
	if w.id == "Shield" and seen.abs == nil then fail("Shield: Aegis's soak never reached the scene") end
	if w.id == "Blasters" and seen.tgt ~= 1 then fail(`Blasters: Deadeye painted {seen.tgt}, not the nearest enemy`) end
	if w.id == "Daggers" and seen.bleed == 0 then fail("Daggers: no bleed marks reached the scene") end
	if (w.id == "Blasters" or w.id == "Grimoire") and seen.comets == 0 then fail(`{w.id}: its projectiles were not drawn as comets`) end
	table.insert(report, `{w.id} {seen.built}/{seen.rects}`)
end
-- The sprites one ultimate builds the first time it is seen: a one-off cost, but a hitch if large.
if mostBuilt > 150 then fail(`{mostBuiltWhere} builds {mostBuilt} effect sprites, over 150`) end
-- The worst frame of the whole scene: every fighter, the stage, the world and the effects.
if peak > 1400 then fail(`{peakWhere} claims {peak} Frames, over 1400`) end

-- ------------------------------------------------------------------ attribution and rings ----
-- A greatsword crater burns in the caster's colour, and its plain gold rings are not drawn as well.
do
	local sword = Loadout.build("Classic", "Sword")
	local hammer = Loadout.build("Classic", "Hammer")
	local chars = { sword, hammer }
	local mid = sword.moves.Ultimate.startup + 2
	local states = {
		{ index = 0, x = 0, y = 0, alive = true, moveId = "Ultimate", moveFrame = mid, startupEff = sword.moves.Ultimate.startup },
		{ index = 1, x = 9, y = 0, alive = true, moveId = "SigDown", moveFrame = 31, startupEff = 30 },
	}
	local fx, player = Effects.new(), FxPlayer.new()
	local glowOf = function(i: number?) local ch = chars[(i or 0) + 1]; return ch and ch.weaponPalette.glow end
	local rand = function() return 0.5 end
	FightScene.spawn(fx, player, { type = "crater", x = 2, y = 0, radius = 3.4, first = true }, states, chars, glowOf, rand,
		function() return 5.2 end, true)
	if #fx.rings ~= 0 then fail(`the ultimate's crater kept {#fx.rings} plain rings under its own`) end
	if #fx.parts == 0 then fail("the ultimate's crater lost its sparks") end
	local coloured = false
	for _, it in player.items do
		if it.ramp == sword.weaponPalette.glow then coloured = true end
	end
	if not coloured then fail("the greatsword's crater is not in the greatsword's glow") end
	-- Earthshatter (not an ultimate) has no caster: its rings stay and its burst is plain fire.
	local fx2, player2 = Effects.new(), FxPlayer.new()
	FightScene.spawn(fx2, player2, { type = "crater", x = 9, y = 0, radius = 2.6, first = true }, { states[2] }, chars, glowOf, rand,
		function() return 5.2 end, true)
	if #fx2.rings == 0 then fail("Earthshatter's crater lost its rings") end
	for _, it in player2.items do
		if it.ramp ~= "fire" then fail(`Earthshatter burst in {tostring(it.ramp)}, not fire`) end
	end
	-- An event FxPlayer does not draw keeps Effects' rings untouched.
	local fx3, player3 = Effects.new(), FxPlayer.new()
	FightScene.spawn(fx3, player3, { type = "tech", x = 0, y = 0 }, states, chars, glowOf, rand, function() return 5.2 end, true)
	if #fx3.rings == 0 or #player3.items ~= 0 then fail("an ordinary event was taken over") end
	-- Predicted events (sparks = false) still get their drawn moment.
	local fx4, player4 = Effects.new(), FxPlayer.new()
	FightScene.spawn(fx4, player4, { type = "hit", attacker = 0, x = 1, y = 2, heavy = true }, states, chars, glowOf, rand,
		function() return 5.2 end, false)
	-- the greatsword's impact (FxPlayer.hit: a heavy blade hit is a cut, a spark and a cross-cut), and no
	-- Effects sparks on top of it
	local cut: { [string]: boolean } = {}
	for _, it in player4.items do cut[it.kind] = true end
	if #fx4.parts ~= 0 then fail("a predicted hit drew Effects' sparks when sparks are off") end
	if not (cut.crescent and cut.spark and cut.xslash) or #player4.items ~= 3 then
		fail("a heavy greatsword hit should draw its cut, spark and cross-cut when sparks are off")
	end
	-- The cap holds: a pile-up drops the oldest.
	for _ = 1, FxPlayer.MAX + 10 do FxPlayer.add(player4, "pop", 0, 0, 1, 1, nil) end
	if #player4.items ~= FxPlayer.MAX then fail(`FxPlayer holds {#player4.items}, cap is {FxPlayer.MAX}`) end
	-- Effects play once and are gone.
	FxPlayer.step(player4, 1.5)
	if #player4.items ~= 0 then fail("finished effects were not cleared") end
end

print(`PASS ult fx: {arts} effect drawings repaint their grids exactly (largest {widest} rectangles), ramps dark to light, fades in sixths`)
print(`PASS ult fx: all twelve ultimates played in real matches draw their signature effects; anchor, soak, target and bleed reach the client`)
print(`  worst frame {peak} Frames ({peakWhere}); most effect sprites built by one ultimate: {mostBuilt} ({mostBuiltWhere})`)
print(`  most rectangles built by one ultimate: {mostRects} ({mostRectsWhere})`)
print(`  sprites/rectangles built: {table.concat(report, ", ")}`)
