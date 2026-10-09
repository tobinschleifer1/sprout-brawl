--!strict
-- Lag compensation (Config.LAG_COMP) through the real Combat and Match, against
-- tools/gen-lagcomp-fixture.mjs: one jab or one grab at a victim moving along a path, the attacker
-- looking 0..13 frames back, the victim sometimes KO'd and respawned in the window, invincible or
-- shielding at the swing - landed, blocked or missed on the same probes, for the same damage, as
-- web/src/engine/combat.js.
--
--     lune run tests/lagcomp-parity
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")
local Match = Loader.load("Match")
local Loadout = Loader.load("Loadout")
local Stages = Loader.load("Data/Stages")
local Input = Loader.load("Input")
local T = serde.decode("json", fs.readFile("tests/lagcomp-fixture.json"))

local data
for _, s in Stages.LIST do if s.id == "FoundryFloor" then data = s end end
local guard = false
local input = { kb2Active = false, poll = function() end, get = function(_, source: string): any
	local f = Input.emptyFrame()
	if guard and source == "p1" then f.guardHeld = true end
	return f
end }

local landed = 0
for n, p in T.probes do
	guard = false
	local fighters = {}
	for i, look in { "Classic", "Noir" } do
		table.insert(fighters, { char = Loadout.build(look, "Sword"), skin = 0, team = i - 1, source = `p{i - 1}`, isBot = false, name = `P{i}` })
	end
	local m = Match.new({ mode = "StockFFA", stage = data, input = input, seed = 1, stocks = 3, fighters = fighters })
	while m.state == "countdown" do m:step() end
	local a, v = m.fighters[1], m.fighters[2]
	for _, f in { a, v } do
		f.y, f.vx, f.vy, f.onGround, f.platform, f.invincible = 0, 0, 0, true, m.stage.main, 0
		f:setState("idle")
	end
	a.x, a.facing, v.facing = 0, 1, -1
	m.combat.rewindOf = function(f: any): number return if f == a then p.rewind else 0 end
	local function hold(t: number)
		v.x, v.y, v.vx, v.vy = p.path[t + 1], 0, 0, 0
		if p.now ~= "invincible" then v.invincible = 0 end
	end
	for t = 0, T.history - 1 do
		if p.dead and t == p.dead[1] then m:knockOut(v) end
		if p.dead and t == p.dead[2] then
			m:respawn(v); v:setState("idle"); v.onGround = true; v.platform = m.stage.main
		end
		hold(t); m:step()
	end
	if p.now == "invincible" then v.invincible = 40 end
	if p.now == "shield" then guard = true; v:setState("shield"); v.shield = 50; v.sf = 30 end
	hold(T.history)
	table.clear(m.events)
	local seen = {}
	if p.kind == "grab" then
		m.combat:checkGrab(a)
		table.insert(seen, v.state)
	else
		a:startMove(a.char.moves.LightNeutral1)
		for t = T.history, T.history + T.after - 1 do
			if v.state ~= "hitstun" then hold(t) end
			m:step()
			for _, e in m.events do if e.victim == v.index then table.insert(seen, e.type) end end
			table.clear(m.events)
		end
	end
	local want = T.rows[n]
	local got = table.concat(seen, ",")
	local where = `probe {n} ({p.kind}, looking {p.rewind} back{if p.dead then ", KO'd in the window" else ""}{if p.now then ", " .. p.now .. " now" else ""})`
	assert(got == want[1], `{where}: {got}, JS {want[1]}`)
	assert(math.abs(v.percent - (tonumber(want[2]) :: number)) < 1e-9, `{where}: victim at {v.percent}%, JS {want[2]}`)
	assert(v.state == want[3], `{where}: victim {v.state}, JS {want[3]}`)
	if got:find("hit") or got:find("grabbed") then landed += 1 end
end
print(`lag compensation: {#T.probes} probes ({landed} landed) judged as web/src/engine/combat.js judges them`)
