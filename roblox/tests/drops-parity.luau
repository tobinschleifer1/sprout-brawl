--!strict
-- Does the Luau run weapon drops the way web/src/engine does?
--
--   lune run tests/drops-parity
--
-- Replays tools/gen-drops-traces.mjs's matches (Match, Combat, Fighter with `weaponDrops` on) and
-- compares every frame: the drop clock, every drop (where, how fast, landed, life left, what it
-- looks like), every thrown weapon in flight, each fighter's hands (armed, nextArm, the weapon)
-- and what the weapon in hand decides (size, weight, jumps, mechanic), and the drop events.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Loader = require("./loader")

local Match = Loader.load("Match")
local Combat = Loader.load("Combat")
local Input = Loader.load("Input")
local Loadout = Loader.load("Loadout")
local StageData = Loader.load("Data/Stages")
local ItemData = Loader.load("Data/Items")

local T = serde.decode("json", fs.readFile("tests/trace-drops.json"))

local failures: { string } = {}
local checked = 0
local function fail(msg: string)
	if #failures < 10 then table.insert(failures, msg) end
end

local EPS = 1e-12
local function same(js: any, lua: any): boolean
	if js == nil or js == serde.decode("json", "null") then return lua == nil end
	if type(js) == "string" and type(lua) == "number" then
		local a = tonumber(js) :: number
		local d = math.abs(a - lua)
		return d <= EPS or d <= EPS * math.max(math.abs(a), math.abs(lua))
	end
	if type(js) == "string" and type(lua) == "boolean" then return js == tostring(lua) end
	return js == lua
end

local function frameFrom(input: any): any
	local fr = Input.emptyFrame()
	for k, v in input or {} do (fr :: any)[k] = v end
	return fr
end

local frames = 0
for _, spec in T.scenarios do
	local current: { [string]: any } = {}
	local input = { kb2Active = false, poll = function(_) end,
		get = function(_, source: string): any return current[source] or Input.emptyFrame() end }
	local fighters = {}
	for i, who in spec.who do
		local A = Loadout.buildArmed(who[1], who[2])
		table.insert(fighters, { char = A.char, kit = A.kit, fists = A.fists, skin = 0, team = i - 1,
			source = `p{i - 1}`, isBot = false, name = `P{i - 1}` })
	end
	local m = Match.new({ mode = spec.mode or "StockFFA", stage = StageData.BY_ID[spec.stage], input = input,
		seed = tonumber(spec.seed), stocks = if spec.stocks ~= nil then tonumber(spec.stocks) else 3,
		weaponDrops = true, fighters = fighters })
	for frame, want in spec.rows do
		local f0 = frame - 1                                -- the trace counts from 0
		for _, op in (spec.ops and spec.ops[tostring(f0)]) or {} do
			if op.set then
				for k, kv in op.set do
					for field, value in kv do m.fighters[(tonumber(k) :: number) + 1][field] = value end
				end
			end
			if op.drop then Combat.spawnDrop(m.combat, op.drop[1], op.drop[2]) end
			if op.dropAt ~= nil then
				local f = m.fighters[op.dropAt + 1]
				Combat.spawnDrop(m.combat, f.x + (if op.dx then tonumber(op.dx) :: number else 0), f.y + 0.5)
			end
			if op.item then
				local f = m.fighters[op.item[1] + 1]
				Combat.spawnItem(m.combat, ItemData.BY_ID[op.item[2]], f.x, f.y + 0.5)
			end
		end
		current = {}
		for k = 1, #m.fighters do
			local s = spec.script[f0 + 1] and spec.script[f0 + 1][k]
			current[`p{k - 1}`] = frameFrom(s)
		end
		table.clear(m.events)
		m:step()
		frames += 1
		local where = `{spec.name} frame {f0}`
		local function cmp(label: string, js: any, lua: any)
			checked += 1
			if not same(js, lua) then fail(`{where}: {label} = {tostring(lua)}, JS says {tostring(js)}`) end
		end
		cmp("state", want[1], m.state)
		cmp("dropTimer", want[2], m.combat.dropTimer)
		-- drops
		local jd = want[3]
		if #jd ~= #m.combat.drops then fail(`{where}: {#m.combat.drops} drops, JS has {#jd}`) end
		for i, d in m.combat.drops do
			local w = jd[i]
			if w then
				for j, v in { d.x, d.y, d.vx, d.vy, d.onGround, d.life, d.look } do cmp(`drop {i} [{j}]`, w[j], v) end
			end
		end
		-- thrown weapons in flight
		local flying = {}
		for _, p in m.combat.projectiles do if p.weaponDrop then table.insert(flying, p) end end
		if #flying ~= #want[4] then fail(`{where}: {#flying} thrown weapons, JS has {#want[4]}`) end
		for i, p in flying do
			local w = want[4][i]
			if w then
				for j, v in { p.x, p.y, p.vx, p.vy, p.life, p.weaponDrop } do cmp(`thrown {i} [{j}]`, w[j], v) end
			end
		end
		-- fighters
		for k, f in m.fighters do
			local w = want[4 + k]
			local got = { f.x, f.y, f.vx, f.vy, f.state, f.moveId, f.mf, f.armed, f.nextArm, f.char.weapon.id,
				f.r, f.h, f.weight, f.jumpsLeft, f.percent, f.stocks, f.mech.id, f.ultCharge }
			for j = 1, 18 do cmp(`P{k - 1} [{j}]`, w[j], got[j]) end
		end
		-- events
		local ev = {}
		local KEEP = { dropspawn = true, droptake = true, dropgone = true, arm = true, throwweapon = true,
			ultdenied = true, ko = true, respawn = true, pickup = true }
		for _, e in m.events do
			if KEEP[e.type] then table.insert(ev, { e.type, e.fighter, e.weapon, e.slot, e.reason }) end
		end
		local je = want[#want]
		if #ev ~= #je then
			fail(`{where}: events {#ev}, JS has {#je}`)
		else
			for i, e in ev do
				for j = 1, 5 do cmp(`event {i} [{j}]`, je[i][j], e[j]) end
			end
		end
		if #failures >= 10 then break end
	end
	if #failures >= 10 then break end
end

if #failures > 0 then
	print(`\n{#failures} MISMATCHES (first ten):`)
	for _, f in failures do print("  " .. f) end
	process.exit(1)
end
print(`replayed {frames} frames of weapon drops across {#T.scenarios} scenarios, {checked} values`)
print("Match/Combat/Fighter drops match web/src/engine exactly.")
