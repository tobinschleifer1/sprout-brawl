--!strict
-- Does Disasters.luau do what web/src/engine/disasters.js does, inside a real Match?
--
--   lune run tests/disaster-parity
--
-- Replays tests/trace-disaster.json (tools/gen-disaster-traces.mjs): each disaster forced in a real
-- match with two pinned probes and one free fighter, plus a long chaos run on the real scheduler.
-- Every frame compares all three fighters (position, velocity, percent, state, stocks, the wind a
-- disaster puts on them), the ledge lock, the whole disaster view flattened to numbers, and every
-- disaster event - hits, blocks, chips - with its launch speed.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Loader = require("./loader")

local Match = Loader.load("Match")
local Input = Loader.load("Input")
local Loadout = Loader.load("Loadout")
local StageData = Loader.load("Data/Stages")

local T = serde.decode("json", fs.readFile("tests/trace-disaster.json"))

local failures: { string } = {}
local checked = 0
local function fail(msg: string)
	if #failures < 12 then table.insert(failures, msg) end
end

local EPS = 1e-12
local function same(expected: any, got: any): boolean
	if type(expected) == "string" then
		local e = tonumber(expected)
		if e ~= nil and type(got) == "number" then
			local d = math.abs(e - got)
			return d <= EPS or d <= EPS * math.max(math.abs(e), math.abs(got))
		end
		if type(got) == "boolean" then return expected == tostring(got) end
		return expected == got
	end
	if expected == nil then return got == nil end
	return expected == got
end

-- The JavaScript's `flatten`: arrays by index, objects by sorted key, leaves as [path, value].
local function flatten(v: any, p: string, out: { any }): { any }
	if v == nil then return out end
	if type(v) == "table" then
		if #v > 0 then
			for i, x in v do flatten(x, `{p}[{i - 1}]`, out) end
		else
			local keys = {}
			for k in v do table.insert(keys, k) end
			table.sort(keys)
			for _, k in keys do flatten(v[k], `{p}.{k}`, out) end
		end
		return out
	end
	table.insert(out, { p, v })
	return out
end

local function probeAt(stage: any, i: number, frame: number): (number, number)
	local m = stage.main
	local span = m.x2 - m.x1
	if i == 0 then
		return m.x1 + 2 + (span - 4) * ((frame * 0.009) % 1), m.top + 0.6
	end
	return m.x1 + span / 3, m.top + 0.3
end

local WHO = { { "Classic", "Sword" }, { "Noir", "Axe" }, { "Ember", "Blasters" } }

for _, spec in T.scenarios do
	local script: { [string]: any } = {}
	local input = { kb2Active = false, poll = function(_) end,
		get = function(_, source: string): any return script[source] or Input.emptyFrame() end }
	local fighters = {}
	for i, who in WHO do
		table.insert(fighters, { char = Loadout.build(who[1], who[2]), skin = 0, team = i - 1,
			source = `p{i - 1}`, isBot = false, name = `P{i - 1}` })
	end
	local m = Match.new({ mode = "StockFFA", stage = StageData.BY_ID[spec.stage], input = input,
		seed = spec.seed, stocks = 3, timeLimit = 600, items = false, fighters = fighters,
		disasters = spec.mode, forceDisaster = spec.force, disasterFirstAt = spec.firstAt })
	local placed = false
	for frame = 0, #spec.rows - 1 do
		local want = spec.rows[frame + 1]
		for k = 0, 2 do
			local inp = Input.emptyFrame()
			if frame < 4 then inp.anyPress = true end
			if k == 2 and spec.shield and frame > 230 then
				inp.guardHeld = true
				if frame % 90 == 0 then inp.guard = true end
			end
			if k == 2 and spec.guardAt ~= nil and frame >= spec.guardAt then
				inp.guardHeld = true
				if frame == spec.guardAt then inp.guard = true end
			end
			script[`p{k}`] = inp
		end
		if spec.place and m.state == "fight" and not placed then
			local f = m.fighters[3]
			f.x, f.y, f.vx, f.vy = spec.place[1], spec.place[2], 0, 0
			placed = true
		end
		if m.state == "fight" then
			for i = 0, 1 do
				local f = m.fighters[i + 1]
				if f.alive then
					f.x, f.y = probeAt(m.stage, i, frame)
					f.vx, f.vy = 0, 0
				end
			end
		end
		table.clear(m.events)
		Match.step(m)

		local got: { any } = { m.state, m.frame, (m.stage :: any).ledgesLocked == true }
		for _, f in m.fighters do
			for _, v in { f.x, f.y, f.vx, f.vy, f.percent, f.state, f.stocks, f.alive, f.env.windX, f.onGround } do
				table.insert(got, v)
			end
		end
		local where = `{spec.name} frame {frame}`
		for i = 1, #got do
			if not same(want[i], got[i]) then
				fail(`{where} field {i}: JS {tostring(want[i])}, Luau {tostring(got[i])}`)
			end
			checked += 1
		end
		-- the disaster view
		local view = flatten(m.stage.visual.disaster, "d", {})
		local wantView = want[#got + 1]
		if #view ~= #wantView then
			fail(`{where}: disaster view has {#view} values, JS has {#wantView} ({wantView[1] and wantView[1][1] or "none"})`)
		else
			for i, pair in wantView do
				if pair[1] ~= view[i][1] or not same(pair[2], view[i][2]) then
					fail(`{where}: {pair[1]} JS {tostring(pair[2])}, Luau {view[i][1]} {tostring(view[i][2])}`)
				end
				checked += 1
			end
		end
		-- the disaster events
		local evs = {}
		for _, e in m.events do
			if e.disaster or e.type == "disaster" then table.insert(evs, e) end
		end
		local wantEv = want[#got + 2]
		if #evs ~= #wantEv then
			fail(`{where}: {#evs} disaster events, JS had {#wantEv}`)
		else
			for i, w in wantEv do
				local e = evs[i]
				local fields = { e.type, e.victim, e.damage, e.disaster, e.launch, e.angle, e.facing,
					if e.perfect == nil then nil else tostring(e.perfect) }
				for j = 1, 8 do
					if not same(w[j], fields[j]) then
						fail(`{where} event {i} field {j}: JS {tostring(w[j])}, Luau {tostring(fields[j])}`)
					end
					checked += 1
				end
			end
		end
	end
end

if #failures > 0 then
	print("FAIL disaster parity:")
	for _, f in failures do print("  " .. f) end
	process.exit(1)
end
local frames = 0
for _, s in T.scenarios do frames += #s.rows end
print(`replayed {checked} disaster values across {#T.scenarios} scenarios, {frames} frames`)
print("Disasters.luau matches web/src/engine/disasters.js to within 1e-12 relative.")
