--!strict
-- Team play (combat phase 3) through the real Combat and Match, against tools/gen-team-fixture.mjs:
-- four fighters, scripted hits, clock gaps, KOs and combos ending. Every hit's team-combo flag and
-- combo count, every KO's credit and assists, and every fighter's KOs, assists and meter after each
-- step match web/src/engine/combat.js and match.js - including a hit exactly at the assist window.
--
--     lune run tests/team-parity
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")
local Match = Loader.load("Match")
local Loadout = Loader.load("Loadout")
local Stages = Loader.load("Data/Stages")
local Input = Loader.load("Input")
local T = serde.decode("json", fs.readFile("tests/team-fixture.json"))

local data
for _, s in Stages.LIST do if s.id == "FoundryFloor" then data = s end end
-- scripted input, held per source until released (the web harness's FakeInput)
local held: { [string]: any } = {}
local idle = { kb2Active = false, poll = function() end, get = function(_, s: string) return held[s] or Input.emptyFrame() end }
local function frameOf(over: any): any
	local f = Input.emptyFrame()
	for k, v in over do (f :: any)[k] = v end
	return f
end
local checked = 0
for n, sc in T.scripts do
	local fighters = {}
	for i, look in { "Classic", "Noir", "Ember", "Moss" } do
		table.insert(fighters, { char = Loadout.build(look, "Sword"), skin = 0, team = i - 1, source = `p{i - 1}`, isBot = false, name = `P{i}` })
	end
	local m = Match.new({ mode = if sc.teams then "StockTeams" else "StockFFA", stage = data, input = idle, seed = 1, stocks = 3, fighters = fighters })
	while m.state == "countdown" do m:step() end
	if sc.teams then
		for i, f in m.fighters do f.team = sc.teams[i] end
	end
	for k, step in sc.steps do
		local kind, x, y = step[1], step[2], step[3]
		table.clear(m.combat.events)
		table.clear(m.events)
		local got: { any }
		if kind == "hit" then
			for i, f in m.fighters do
				f.x, f.y, f.vx, f.vy, f.onGround, f.platform, f.invincible = -6 + (i - 1) * 3, 0, 0, 0, true, m.stage.main, 0
			end
			local a, v = m.fighters[x + 1], m.fighters[y + 1]
			a.moveSerial += 1
			v.hitlag = 0
			if v.state ~= "hitstun" then v:setState("idle") end
			m.combat:resolveHit(a, v, a.char.moves.LightNeutral1, nil, nil, {})
			local e = nil
			for _, ev in m.combat.events do if ev.type == "hit" then e = ev; break end end
			got = { kind, if e then e.team else nil, if e then tostring(e.combo) else nil }
		elseif kind == "wait" then
			local f = m.fighters[x + 1]
			f.frameCount += y
			got = { kind }
		elseif kind == "launch" then
			local c, v = m.fighters[1], m.fighters[x + 1]
			v.x, v.y, v.onGround, v.platform = c.x + y, c.y + step[4], false, nil
			v:setState("hitstun")
			v.hitstun, v.tumbling, v.vx, v.vy, v.jumpsLeft = 30, true, 60, 30, 0
			got = { kind }
		elseif kind == "air" then
			local c = m.fighters[x + 1]
			c.y, c.onGround, c.platform = 6, false, nil
			c:setState("air")
			c.vy = 0
			got = { kind }
		elseif kind == "catch" then
			local c = m.fighters[x + 1]
			c.buffer.grab = 8
			c:step({ stage = m.stage, combat = m.combat, fighters = m.fighters })
			local e = nil
			for _, ev in m.combat.events do if ev.type == "catch" then e = ev end end
			local caught = e ~= nil
			local states = {}
			for _, f in m.fighters do
				table.insert(states, table.concat({ f.state, string.format("%.6f", f.vx), string.format("%.6f", f.vy), tostring(f.invincible),
					tostring(f.jumpsLeft), tostring(f.tumbling), tostring(f.lag) }, ":"))
			end
			got = { kind, tostring(if caught then 1 else 0), if e then tostring(e.ally) else nil, table.concat(states, " ") }
			c:setState("idle")
			c.lag, c.y, c.onGround, c.platform = 0, 0, true, m.stage.main
		elseif kind == "place" then
			for i, f in m.fighters do
				f.x, f.y, f.vx, f.vy, f.onGround, f.platform, f.invincible = x[i], 0, 0, 0, true, m.stage.main, 0
				f:setState("idle")
				f.facing = if i == 1 then 1 else -1
			end
			got = { kind }
		elseif kind == "spent" then
			local f = m.fighters[x + 1]
			f.jumpsLeft, f.airDodgeUsed, f.recoveryUsed = 0, true, true
			got = { kind }
		elseif kind == "hold" then
			local over = table.clone(y)
			over.anyPress = false
			held[`p{x}`] = frameOf(over)
			got = { kind }
		elseif kind == "release" then
			held[`p{x}`] = nil
			got = { kind }
		elseif kind == "press" or kind == "run" then
			if kind == "press" then
				local over = table.clone(y)
				over.anyPress = true
				held[`p{x}`] = frameOf(over)
			end
			local n = if kind == "press" then 1 else x
			local seen = {}
			local WATCH = { hit = true, teamboost = true, teamfling = true, grabhit = true, block = true, armor = true }
			for _ = 1, n do
				m:step()
				for _, e in m.events do if WATCH[e.type] then table.insert(seen, e.type) end end
				table.clear(m.events)
			end
			if kind == "press" then held[`p{x}`] = nil end
			local states = {}
			for _, f in m.fighters do
				table.insert(states, table.concat({ f.state, string.format("%.6f", f.x), string.format("%.6f", f.y), string.format("%.6f", f.vx),
					string.format("%.6f", f.vy), tostring(f.percent), tostring(f.jumpsLeft), tostring(f.recoveryUsed) }, ":"))
			end
			got = { kind, table.concat(seen, ","), table.concat(states, " ") }
		elseif kind == "respawn" then
			local f = m.fighters[x + 1]
			m:respawn(f)
			f:setState("idle")
			f.invincible = 0
			got = { kind, tostring(if f.alive then 1 else 0), nil }
		elseif kind == "free" then
			local v = m.fighters[x + 1]
			v:setState("idle")
			v:step({ stage = m.stage, combat = m.combat, fighters = m.fighters })
			got = { kind, tostring(v.comboHits), tostring(v.comboBy) }
		else
			m:knockOut(m.fighters[x + 1])
			local e = nil
			for _, ev in m.events do if ev.type == "ko" then e = ev end end
			got = { kind, tostring((e :: any).by), table.concat((e :: any).assists, ",") }
		end
		local tally = {}
		for _, f in m.fighters do table.insert(tally, `{f.stats.kos}/{f.stats.assists}/{f.ultCharge}`) end
		-- the tally is the last value: 2nd after a wait, 4th otherwise (a missed hit's nils hold 2-3)
		local last = if kind == "wait" or kind == "launch" or kind == "air" or kind == "place" or kind == "hold" or kind == "release" or kind == "spent" then 2
			elseif kind == "catch" then 5 else 4
		got[last] = table.concat(tally, " ")
		local want = sc.rows[k]
		for j = 1, last do
			local v, w = got[j], want[j]
			assert(tostring(v) == tostring(w), `script {n} step {k} ({kind}) value {j}: Luau {tostring(v)}, JS {tostring(w)}`)
			checked += 1
		end
	end
end
print(`team: {checked} values across {#T.scripts} scripts match web/src/engine/combat.js and match.js`)
