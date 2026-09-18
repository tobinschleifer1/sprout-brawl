--!strict
-- Do the Luau hazards do what web/src/engine/hazards.js does, frame by frame?
--
--   lune run tests/hazard-parity
--
-- Hazards are pure force: they write to each fighter's `env` bag and occasionally call hazardHit.
-- So this replays four pinned probes through every hazard-carrying stage and compares every env
-- value, every position, the whole visual bag, and the hazardHit log - because a hazard that
-- damages the right person on the wrong frame is not a correct port.
--
-- Two things this cannot cover, established by mutation rather than assumed:
--
--   * The antenna arc's per-fighter cooldown. It is 30 frames and the arc is only live for 22
--     (`arc: 22` on Rooftops), so no fighter can ever be hit twice inside it - shortening the
--     cooldown to 20 passes everything. It is unreachable defensive code with the current stage
--     data, and would start mattering the moment `arc` went above 30.
--   * The sprinkler's jsRound. See the note in Hazards.luau: it only differs from math.round at an
--     exact half, which a smoothstepped sweep does not produce.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Loader = require("./loader")

local Fighter = Loader.load("Fighter")
local Stage = Loader.load("Stage")
local Input = Loader.load("Input")
local Loadout = Loader.load("Loadout")
local StageData = Loader.load("Data/Stages")

local T = serde.decode("json", fs.readFile("tests/trace-hazard.json"))

local failures: { string } = {}
local checked = 0

local function fail(msg: string)
	if #failures < 10 then
		table.insert(failures, msg)
	end
end

-- Same tolerance and the same reason as the other replay tests: Math.sin and math.sin differ in
-- the last two bits, and half the hazards in here run on a sine.
local EPS = 1e-12
local function near(a: number, b: number): boolean
	local diff = math.abs(a - b)
	return diff <= EPS or diff <= EPS * math.max(math.abs(a), math.abs(b))
end

local function num(v: any): number
	return tonumber(v) :: number
end

-- combat.hazardHit, matching the recorder's stub, which is combat.js's own four lines.
local function stubCombat(log: { string }): any
	return {
		hazardHit = function(_, f: any, p: any)
			if f.untouchable then
				return
			end
			local d = f.x - p.x
			local facing = if (if d ~= 0 then d else 1) < 0 then -1 else 1
			f:applyHit({ damage = p.damage, launch = p.launch, angle = p.angle, facing = facing,
				attacker = nil, hitlag = 6 })
			table.insert(log, `{f.index}:{p.damage}:{p.launch}:{p.angle}`)
		end,
	}
end

local function sweepAt(stage: any, i: number, frame: number): (number, number)
	local m = stage.main
	local span = m.x2 - m.x1
	local t = ((frame * 0.013) + i * 0.37) % 1
	return m.x1 + span * t, m.top + (if i == 0 then 1.0 else 16.0)
end

-- The visual bag, flattened exactly as the recorder flattens it: sorted key paths, values as
-- numbers so they go through `near` rather than a string compare.
local function flatten(v: any, p: string, out: { any })
	if v == nil then
		return
	end
	if typeof(v) == "table" then
		-- an array if it has a [1]; the recorder distinguishes the same way
		if v[1] ~= nil or next(v) == nil then
			for i, x in ipairs(v) do
				flatten(x, `{p}[{i - 1}]`, out)
			end
			if next(v) ~= nil and v[1] ~= nil then
				return
			end
		end
		local keys = {}
		for k in v do
			if typeof(k) == "string" then
				table.insert(keys, k)
			end
		end
		table.sort(keys)
		for _, k in keys do
			flatten(v[k], `{p}.{k}`, out)
		end
		return
	end
	table.insert(out, { p, v })
end

local CHARS = { { "Classic", "Sword" }, { "Noir", "Pike" }, { "Ember", "Hammer" },
	{ "Moss", "Daggers" }, { "Vapor", "Longbow" } }

for _, spec in T.scenarios do
	local data = StageData.BY_ID[spec.id]
	local stage = Stage.new(data, num(spec.seed))
	local hitLog: { string } = {}
	local combat = stubCombat(hitLog)
	local fighters = {}
	for i = 1, 5 do
		local f = Fighter.new({ index = i - 1, char = Loadout.build(CHARS[i][1], CHARS[i][2]),
			x = data.spawns[((i - 1) % #data.spawns) + 1], y = 2, stocks = 99, name = `P{i - 1}` })
		f:setState("idle")
		f.invincible = 0
		fighters[i] = f
	end
	local match = { fighters = fighters, frame = 0, combat = combat }
	local ctx = { stage = stage, combat = combat, fighters = fighters }
	local empty = Input.emptyFrame()

	local broke = false
	for frame = 0, spec.frames - 1 do
		match.frame = frame
		for i = 1, 5 do
			local f = fighters[i]
			local x, y
			if i == 5 then
				x, y = num(spec.hold[1]), num(spec.hold[2])
			elseif i <= 2 then
				x, y = sweepAt(stage, i - 1, frame)
			elseif #spec.points > 0 then
				local p = spec.points[(math.floor(frame / 45) + (i - 3) * 3) % #spec.points + 1]
				x, y = num(p[1]), num(p[2]) + (if i == 4 then 3 else 0)
			else
				x, y = sweepAt(stage, i - 3, frame)
			end
			f.x = x; f.y = y; f.vx = 0; f.vy = 0
			f.onGround = (i - 1) % 2 == 0
			f.platform = if (i - 1) % 2 == 0 then stage.main else nil
			f.percent = 0; f.hitstun = 0; f.hitlag = 0; f.tumbling = false
			f:setState(if (i - 1) % 2 == 0 then "idle" else "air")
		end
		Stage.step(stage, match)
		for _, f in fighters do
			table.clear(f.events)
			f:applyInput(empty)
			f:step(ctx)
		end

		local want = spec.rows[frame + 1]
		local at = 0
		local function want_next(): any
			at += 1
			return want[at]
		end
		for _, f in fighters do
			local vals = { f.env.updraft, f.env.windX, f.env.traction, f.env.grip, f.env.damp }
			for _, v in vals do
				checked += 1
				local w = want_next()
				if not near(v, num(w)) then
					fail(string.format("%s frame %d fighter %d env: Luau %.17g, JS %s",
						spec.id, frame, f.index, v, tostring(w))); broke = true; break
				end
			end
			if broke then break end
			local pairsToCheck: { any } = { { f.inWater, "inWater", false }, { f.x, "x", true },
				{ f.y, "y", true }, { f.vx, "vx", true }, { f.vy, "vy", true },
				{ f.percent, "percent", true }, { f.state, "state", false },
				{ f.onGround, "onGround", false } }
			for _, pc in pairsToCheck do
				checked += 1
				local w = want_next()
				local ok = if pc[3] then near(pc[1], num(w)) else pc[1] == w
				if not ok then
					fail(string.format("%s frame %d fighter %d %s: Luau %s, JS %s",
						spec.id, frame, f.index, pc[2], tostring(pc[1]), tostring(w))); broke = true; break
				end
			end
			if broke then break end
		end
		if broke then break end
		checked += 1
		local wl = want_next()
		if wl == nil then
			if stage.waterLevel ~= nil then
				fail(`{spec.id} frame {frame} waterLevel: Luau {stage.waterLevel}, JS nil`); broke = true
			end
		elseif stage.waterLevel == nil or not near(stage.waterLevel, num(wl)) then
			fail(`{spec.id} frame {frame} waterLevel: Luau {tostring(stage.waterLevel)}, JS {tostring(wl)}`)
			broke = true
		end
		if broke then break end

		local wantVisual = want_next()
		if wantVisual ~= nil then
			local got: { any } = {}
			flatten(stage.visual, "", got)
			checked += 1
			if #got ~= #wantVisual then
				fail(string.format("%s frame %d visual: %d entries, JS had %d",
					spec.id, frame, #got, #wantVisual)); broke = true
			else
				for i, entry in wantVisual do
					checked += 1
					local g = got[i]
					local okPath = g[1] == entry[1]
					local okVal
					if typeof(g[2]) == "number" then
						okVal = near(g[2], num(entry[2]))
					else
						okVal = g[2] == entry[2]
					end
					if not okPath or not okVal then
						fail(string.format("%s frame %d visual %s=%s, JS %s=%s", spec.id, frame,
							tostring(g[1]), tostring(g[2]), tostring(entry[1]), tostring(entry[2])))
						broke = true
						break
					end
				end
			end
		end
		if broke then break end
	end

	if not broke then
		checked += 1
		if #hitLog ~= #spec.hitLog then
			fail(string.format("%s: %d hazard hits, JS had %d", spec.id, #hitLog, #spec.hitLog))
		else
			for i, w in spec.hitLog do
				if hitLog[i] ~= w then
					fail(string.format("%s: hazard hit %d was %s, JS %s", spec.id, i, hitLog[i], w))
					break
				end
			end
		end
	end
end

local hits = 0
for _, s in T.scenarios do
	hits += #s.hitLog
end
print(string.format("replayed %d hazard values across %d stages (%d hazard hits)",
	checked, #T.scenarios, hits))
if #failures > 0 then
	print(string.format("\n%d MISMATCHES:", #failures))
	for _, f in failures do
		print("  " .. f)
	end
	process.exit(1)
end
print(string.format("Hazards.luau matches web/src/engine/hazards.js to within %g relative.", EPS))
