--!strict
-- Depth (combat phase 2) through the real Combat, against tools/gen-depth-fixture.mjs.
--
-- Staling (Config.STALE): the same
-- sequences of probe moves - repeats, a mix of four, the memory forgetting, hits inside one swing,
-- blocked hits, the ultimate, small hits that round - deal the same damage and launch, and leave
-- the same memory, as web/src/engine/combat.js.
--
-- Armour: a light and a heavy landed on every frame of every weapon's heavies' startups, and just
-- past them, are absorbed - or not - on exactly the same frames.
--
--     lune run tests/depth-parity
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")
local Match = Loader.load("Match")
local Loadout = Loader.load("Loadout")
local Stages = Loader.load("Data/Stages")
local Input = Loader.load("Input")
local T = serde.decode("json", fs.readFile("tests/depth-fixture.json"))

local data
for _, s in Stages.LIST do if s.id == "FoundryFloor" then data = s end end
local idle = { kb2Active = false, poll = function() end, get = function() return Input.emptyFrame() end }
local checked = 0
for n, case in T.cases do
	local fighters = {}
	for i, look in { "Classic", "Noir" } do
		table.insert(fighters, { char = Loadout.build(look, "Sword"), skin = 0, team = i - 1, source = `p{i - 1}`, isBot = false, name = `P{i}` })
	end
	local m = Match.new({ mode = "StockFFA", stage = data, input = idle, seed = 1, stocks = 3, fighters = fighters })
	while m.state == "countdown" do m:step() end
	local a, v = m.fighters[1], m.fighters[2]
	for k, step in case.seq do
		local id, damage, same, shield = step[1], step[2], step[3], step[4]
		a.x, v.x, a.facing, v.facing = 0, 2, 1, -1
		for _, f in { a, v } do
			f.y, f.vx, f.vy, f.onGround, f.platform, f.invincible = 0, 0, 0, true, m.stage.main, 0
		end
		if not same then a.moveSerial += 1 end
		v.percent, v.comboHits, v.comboKey, v.hitlag = 50, 0, -1, 0
		if shield then v:setState("shield"); v.sf = 30; v.shield = 50 else v:setState("idle") end
		table.clear(m.combat.events)
		m.combat:resolveHit(a, v, { id = id, damage = damage, base = 12, growth = 1.0, angle = 45, startup = 3, active = 3, recovery = 10, kind = "melee" }, nil, nil, {})
		local hit = nil
		for _, e in m.combat.events do if e.type == "hit" then hit = e; break end end
		local want = case.rows[k]
		local where = `sequence {n} hit {k} ({id})`
		assert(math.abs((v.percent - 50) - tonumber(want[1]) :: number) < 1e-9, `{where}: dealt {v.percent - 50}, JS {want[1]}`)
		if want[2] == nil then
			assert(hit == nil, `{where}: a hit, JS none`)
		else
			assert(hit and math.abs(hit.launch - tonumber(want[2]) :: number) < 1e-9 * math.abs(tonumber(want[2]) :: number), `{where}: launch differs`)
		end
		assert(table.concat(a.staleMoves, ",") == want[3], `{where}: remembers {table.concat(a.staleMoves, ",")}, JS {want[3]}`)
		checked += 3
	end
end
print(`staling: {checked} values across {#T.cases} sequences match web/src/engine/combat.js`)

local absorbed, probes = 0, 0
for _, row in T.armour do
	local weapon, id, by, mf, wantArmour, wantState, wantPct = row[1], row[2], row[3], row[4], row[5] == 1, row[6], row[7]
	local fighters = {}
	for i, w in { "Sword", weapon } do
		table.insert(fighters, { char = Loadout.build(if i == 1 then "Classic" else "Noir", w), skin = 0, team = i - 1, source = `p{i - 1}`, isBot = false, name = `P{i}` })
	end
	local m = Match.new({ mode = "StockFFA", stage = data, input = idle, seed = 1, stocks = 3, fighters = fighters })
	while m.state == "countdown" do m:step() end
	local a, v = m.fighters[1], m.fighters[2]
	a.x, v.x, a.facing, v.facing = 0, 2, 1, -1
	for _, f in { a, v } do
		f.y, f.vx, f.vy, f.onGround, f.platform, f.invincible = 0, 0, 0, true, m.stage.main, 0
		f:setState("idle")
	end
	v:startMove(v.char.moves[id])
	v.mf = mf
	table.clear(m.combat.events)
	m.combat:resolveHit(a, v, a.char.moves[by], nil, nil, {})
	local got = false
	for _, e in m.combat.events do if e.type == "armor" then got = true end end
	local where = `{weapon} {id} hit by {by} at frame {mf}`
	assert(got == wantArmour, `{where}: armour {got}, JS {wantArmour}`)
	assert(v.state == wantState, `{where}: victim {v.state}, JS {wantState}`)
	assert(math.abs(v.percent - tonumber(wantPct) :: number) < 1e-9, `{where}: percent {v.percent}, JS {wantPct}`)
	probes += 1
	if got then absorbed += 1 end
end
assert(absorbed > 0 and absorbed < probes, "the armour probes must hold both answers")
print(`armour: {probes} probes ({absorbed} absorbed) on every weapon's heavies match web/src/engine/combat.js`)
