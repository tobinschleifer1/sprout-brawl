--!nocheck
-- Every ultimate kills, and kills late: the web's check 13 (web/test/ultimate.test.mjs, "KILL
-- PERCENT, pinned"), ported to the Roblox build so the two Roblox-only weapons are held to the same
-- band. The ultimate is fired at a victim standing centre stage, and it counts only if the LAUNCH
-- takes them out: they leave the blast box within hitstun + 40 frames of the last hit. Anything
-- looser measures a dummy drifting off the edge, which every horizontal launch does eventually (an
-- earlier Rocket Boots check here passed at 90% that way).
--
--     lune run tests/ultimate-kills
local Loader = require("./loader")
local Match, Loadout, Input, Config = Loader.load("Match"), Loader.load("Loadout"), Loader.load("Input"), Loader.load("Config")
local Weapons = Loader.load("Weapons")
local Stages = Loader.load("Data/Stages").LIST

-- how far apart the two start (the web's RANGE_FOR, and the Roblox-only weapons')
local RANGE_FOR = { Sword = 3.0, Scythe = 4.0, Blasters = 12, Grimoire = 9, Axe = 4.0, Pike = 10, Gauntlets = 3.0, Hammer = 4.0,
	Longbow = 9, Flail = 5.0, Shield = 3.0, Daggers = 3.0, Whip = 7.2, Chakram = 6.0, RocketBoots = 3.0 }

local function press(ult: boolean, light: boolean?): any
	local f = Input.emptyFrame()
	f.ult, f.light = ult, light == true
	f.anyPress = ult or light == true
	return f
end

local function ultKills(weaponId: string, percent: number): boolean
	local frames: { [string]: any } = {}
	local input = { get = function(_, src) return frames[src] or Input.emptyFrame() end }
	local m = Match.new({ mode = "StockFFA", stage = Stages[1], seed = 1, items = false, stocks = 3, input = input,
		fighters = { { char = Loadout.build("Classic", weaponId), source = "p0", team = 0 },
			{ char = Loadout.build("Noir", "Sword"), source = "p1", team = 1 } } })
	m.state = "fight"
	for _ = 1, 120 do m:step() end
	local a, v = m.fighters[1], m.fighters[2]
	local d = RANGE_FOR[weaponId]
	a.x, v.x, a.facing, v.facing = -d / 2, d / 2, 1, -1
	for _, f in { a, v } do f.onGround = true; f.platform = m.stage.main; f.y = 0; f.vx = 0; f.vy = 0; f.invincible = 0 end
	v:setState("idle"); v.percent = percent
	a:setState("idle"); a.ultCharge = Config.ULTIMATE.hitsRequired
	local reflects = a.char.moves.Ultimate.kind == "reflect"
	frames.p0 = press(true)
	m:step()
	local pct, deadline = v.percent, -1
	for i = 0, 699 do
		-- the sniper needs a trigger pull per round, so the button is pressed again now and then
		frames.p0 = if i % 20 == 0 then press(true) else nil
		frames.p1 = if reflects and i < 120 and i % 10 == 0 then press(false, true) else nil
		m:step()
		if v.percent > pct then pct = v.percent; deadline = i + v.hitstun + 40 end
		if m.stage:outsideBlast(v) or v.stocks < 3 or not v.alive then return deadline >= 0 and i <= deadline end
		if deadline >= 0 and i > deadline and a.state ~= "attack" and v.onGround then return false end
	end
	return false
end
local function ultKo(weaponId: string): number?
	for p = 0, 400, 5 do
		if ultKills(weaponId, p) then
			for q = math.max(0, p - 4), p do if ultKills(weaponId, q) then return q end end
			return p
		end
	end
	return nil
end

-- [kill %] measured, then pinned, +/-18 (a few resolve through positioning). The 13 web weapons'
-- are the web's own pins; the Roblox-only two were measured here (2026-11-11, weapons round 2).
local EXPECT = { Sword = 134, Scythe = 161, Blasters = 131, Grimoire = 191, Axe = 155, Pike = 136,
	Gauntlets = 213, Hammer = 146, Longbow = 133, Flail = 148, Shield = 193, Daggers = 142, Whip = 148,
	Chakram = 164, RocketBoots = 142 }
local FLOOR, CEILING = 120, 260
local rows, bad = {}, {}
for _, w in Weapons.LIST do
	local k = ultKo(w.id)
	local want = EXPECT[w.id]
	table.insert(rows, `{w.moves.Ultimate.label} {if k then tostring(k) .. "%" else "NEVER"}`)
	if not k then table.insert(bad, `{w.id} cannot KO at all`)
	elseif k < FLOOR or k > CEILING then table.insert(bad, `{w.id} kills at {k}%, outside {FLOOR}-{CEILING}`)
	elseif not want then table.insert(bad, `{w.id} has no pinned kill percent (measured {k}%)`)
	elseif math.abs(k - want) > 18 then table.insert(bad, `{w.id} kills at {k}%, pinned at {want}%`) end
end
print(table.concat(rows, ", "))
assert(#bad == 0, table.concat(bad, "; "))
print(`PASS ultimate kills: every ultimate's launch kills, between {FLOOR}% and {CEILING}%, at its pinned percent`)
