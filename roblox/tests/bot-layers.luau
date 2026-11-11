--!nocheck
-- The bots' Roblox-only layers (src/shared/BotLayers.luau, applied in Ai.computeBotInput while
-- RobloxRules is on), each against the finding it answers (docs/reviews/bots-round1-review.md).
-- Played layered against the shipping bot (tools/bot-ab, 36 hard matches a weapon) they won 304
-- of 540 where the same seeds give 264 of 531 with neither layered; matches ended 0 times in
-- timeouts against 9. Those are measurements, not checks; this holds what each layer does.
--
--     lune run tests/bot-layers
local Loader = require("./loader")
local Match, Loadout, Input, Weapons = Loader.load("Match"), Loader.load("Loadout"), Loader.load("Input"), Loader.load("Weapons")
local BotLayers, Ai, Rules = Loader.load("BotLayers"), Loader.load("Ai"), Loader.load("RobloxRules")
local Stages = Loader.load("Data/Stages")
local function stageNamed(id) for _, s in Stages.LIST do if s.id == id then return s end end end

local function bots(stage: any, a: string, b: string): (any, any, any)
	local m = Match.new({ mode = "StockFFA", stage = stage, seed = 5, items = false, stocks = 3,
		fighters = { { char = Loadout.build("Classic", a), isBot = true, botLevel = "hard", team = 0 },
			{ char = Loadout.build("Noir", b), isBot = true, botLevel = "hard", team = 1 } } })
	m.state = "fight"
	for _ = 1, 30 do m:step() end
	return m, m.fighters[1], m.fighters[2]
end
local L = Ai.LEVELS.hard
local function liveView(v) return v end
local function never() return 1 end -- (no chance-gated layer fires)

-- 1. The kill press: Scattergun for the Blasters (Full Auto, the side heavy, launches 21 at 100%),
--    the side heavy where it can finish.
local blasters, sword = Loadout.build("Classic", "Blasters"), Loadout.build("Classic", "Sword")
local pick = BotLayers.killSignature(blasters, 3, 120)
assert(pick and pick.id == "SigDown", `the Blasters' kill press is {pick and pick.id}, not Scattergun`)
pick = BotLayers.killSignature(sword, 3, 120)
assert(pick and pick.id == "SigSide", `the Sword's kill press moved off its side heavy, to {pick and pick.id}`)
do
	local m, f, foe = bots(Stages.LIST[1], "Blasters", "Sword")
	f.x, foe.x, foe.percent = 0, 3, 120
	f.onGround, f.state = true, "idle"
	local frame = Input.emptyFrame(); frame.heavy, frame.x = true, 1
	frame = BotLayers.apply(f, m, frame, L, liveView, never)
	assert(frame.heavy and frame.y == -1 and frame.x == 0, `the Blasters bot pressed heavy with x {frame.x}, y {frame.y}, not down`)
end

-- 5. An airborne heavy outside the recovery branch becomes a light; the recovery's own does not.
do
	local m, f, foe = bots(Stages.LIST[1], "Grimoire", "Sword")
	f.onGround, f.state, f.y, foe.x = false, "air", 4, f.x + 8
	f.ai.noFumble = false
	local frame = Input.emptyFrame(); frame.heavy, frame.x = true, 1
	frame = BotLayers.apply(f, m, frame, L, liveView, never)
	assert(frame.light and not frame.heavy, "a zoning heavy in the air was left a heavy: the recovery, spent")
	f.ai.noFumble = true
	frame = Input.emptyFrame(); frame.heavy, frame.y = true, 1
	f.x, f.y = m.stage.main.x2 + 6, -4
	frame = BotLayers.apply(f, m, frame, L, liveView, never)
	assert(frame.heavy and frame.y == 1, "a real recovery was taken away")
end

-- 6. A neutral combo press in the air stays neutral (it reaches the air finisher).
do
	local m, f = bots(Stages.LIST[1], "Chakram", "Sword")
	f.onGround, f.state, f.ai.combo = false, "attack", { dir = "neutral", press = "light" }
	local frame = Input.emptyFrame(); frame.light, frame.x = true, 0.6
	frame = BotLayers.apply(f, m, frame, L, liveView, never)
	assert(frame.x == 0, `a neutral air combo press drifted ({frame.x}): it reads as a side press`)
end

-- 2. With nobody left, a bot off the stage comes home.
do
	local m, f, foe = bots(Stages.LIST[1], "Sword", "Sword")
	foe.alive = false
	local main = m.stage.main
	f.onGround, f.state, f.x, f.y, f.vy, f.jumpsLeft = false, "air", main.x2 + 8, -3, -6, 1
	f.ai.layerCd = 0
	local frame = BotLayers.apply(f, m, Input.emptyFrame(), L, liveView, never)
	assert(frame.x < 0 and frame.jump, `a bot off the stage with no foe pressed x {frame.x}, jump {tostring(frame.jump)}`)
end

-- 3. In water a bot swims for the nearest ledge.
do
	local m, f, foe = bots(stageNamed("Undertow"), "Flail", "Sword")
	local main = m.stage.main
	f.onGround, f.state, f.inWater, f.x, f.y = false, "air", true, main.x2 + 10, -5
	foe.x = main.x1 + 2
	local frame = Input.emptyFrame(); frame.x = 1; frame.heavy = true
	frame = BotLayers.apply(f, m, frame, L, liveView, never)
	local ledge = m.stage:nearestLedge(f.x, f.cy).ledge
	assert(frame.x == (if ledge.x < f.x then -1 else 1) and not frame.heavy, `a swimming bot pressed x {frame.x} (the ledge is at {ledge.x}), heavy {tostring(frame.heavy)}`)
end

-- 7. The Shield answers a swing in reach with Counterguard, not only the shield (on its chance).
do
	local m, f, foe = bots(Stages.LIST[1], "Shield", "Sword")
	f.onGround, f.state, f.x, foe.x, foe.y, f.y = true, "shield", 0, 3, 0, 0
	local seenFoe = { x = 3, y = 0, state = "attack", percent = 0 }
	local frame = Input.emptyFrame(); frame.guard, frame.guardHeld = true, true
	frame = BotLayers.apply(f, m, frame, L, function() return seenFoe end, function() return 0 end)
	assert(frame.heavy and frame.x == 0 and frame.y == 0 and not frame.guardHeld, "the Shield bot only shielded against a swing in reach")
end

-- And off, nothing: with RobloxRules off the bot's input is the replayed bot's own.
do
	local function play(on: boolean): number
		Rules.on = on
		local m = bots(Stages.LIST[1], "Blasters", "Sword")
		for _ = 1, 600 do m:step() end
		local sum = 0
		for _, f in m.fighters do sum += f.x * 7 + f.percent end
		Rules.on = true
		return sum
	end
	local off1, off2, on = play(false), play(false), play(true)
	assert(off1 == off2 and on ~= off1, "the layers do not switch off with RobloxRules (or never act)")
end
print("PASS bot layers: the Blasters' kill press is Scattergun and the Sword's stays its side heavy; an air heavy outside the recovery is a light, the recovery stays; a neutral air combo press stays neutral; with nobody left a bot comes home; a swimming bot heads for the ledge; the Shield counters a swing in reach; off with RobloxRules")
