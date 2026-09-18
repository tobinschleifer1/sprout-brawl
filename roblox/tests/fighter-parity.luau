--!strict
-- Does Fighter.luau behave like web/src/engine/fighter.js, frame by frame?
--
--   lune run tests/fighter-parity
--
-- tools/gen-fighter-traces.mjs drives the REAL JavaScript Fighter through 31 scripted scenarios and
-- records every simulation field on every frame. This replays the same scripts - read out of the
-- same file, so the two harnesses cannot drift - and reports the FIRST frame that differs, which is
-- the one worth looking at.
--
-- ctx.combat is a stub on both sides and its call log is compared too: a state machine that reaches
-- the right positions while calling out to combat on the wrong frame is not a correct port.
--
-- Two things this deliberately does NOT cover, verified by mutation rather than assumed:
--
--   * `sign(0)`. Swapping the JavaScript helper for math.sign - which returns 0 where the helper
--     returns +1 - changes nothing, because every call site is already guarded by |x| > some
--     threshold. The helper stays correct anyway; the day a call site loses its guard, it matters.
--   * The traction and grip floors in _friction and _groundMove. They only differ from 1 when a
--     hazard writes to env, and hazards are Phase 2b, so 0.25 and 0.2 are indistinguishable here.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Loader = require("./loader")

local Fighter = Loader.load("Fighter")
local Stage = Loader.load("Stage")
local Input = Loader.load("Input")
local Loadout = Loader.load("Loadout")
local StageData = Loader.load("Data/Stages")

local T = serde.decode("json", fs.readFile("tests/trace-fighter.json"))

local failures: { string } = {}
local checked = 0

local function fail(msg: string)
	if #failures < 10 then
		table.insert(failures, msg)
	end
end

-- Same tolerance and the same reason as tests/stage-parity.luau: Math.sin and math.sin are not the
-- same function, and launch angles run through both.
local EPS = 1e-12
local function near(a: number, b: number): boolean
	local diff = math.abs(a - b)
	return diff <= EPS or diff <= EPS * math.max(math.abs(a), math.abs(b))
end

-- An independent deep copy, used to prove a snapshot does not alias the fighter it came from.
local function deepCopy(v: any): any
	if typeof(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

-- Where two trees first differ, or nil. Tables reached by REFERENCE on purpose (the char, a move,
-- a platform) are compared by identity, which is what deepCopy preserves for them anyway.
local function firstDifference(a: any, b: any, path: string): string?
	if typeof(a) ~= typeof(b) then
		return path
	end
	if typeof(a) ~= "table" then
		return if a == b then nil else path
	end
	for k, v in a do
		local d = firstDifference(v, b[k], `{path}.{tostring(k)}`)
		if d then
			return d
		end
	end
	for k in b do
		if a[k] == nil then
			return `{path}.{tostring(k)}`
		end
	end
	return nil
end

-- The stub, matching tools/gen-fighter-traces.mjs exactly - including what it logs.
local function stubCombat(fighters: any): any
	local log: { string } = {}
	local function rec(name: string, extra: any?)
		table.insert(log, if extra == nil then name else `{name}:{extra}`)
	end
	return {
		fighters = fighters, log = log,
		useItem = function(_, f, kind) rec("useItem", kind) end,
		dropItem = function(_, f, thrown) rec("dropItem", tostring(thrown)) end,
		itemNear = function(_) rec("itemNear") return nil end,
		pickupItem = function(_) rec("pickupItem") end,
		hasFruit = function(_) rec("hasFruit") return false end,
		fruiting = function(_) rec("fruiting") end,
		nearestNode = function(_) rec("nearestNode") return nil end,
		removeSummon = function(_) rec("removeSummon") end,
		onMoveActive = function(_, f, m) rec("onMoveActive", m.id) end,
		onMoveActiveFrame = function(_, f, m) rec("onMoveActiveFrame", `{m.id}@{f.mf}`) end,
		spawnBurst = function(_, f, b) rec("spawnBurst", b.id or "shock") end,
		checkGrab = function(_) rec("checkGrab") end,
		resolveThrow = function(_, a, v, td) rec("resolveThrow", tostring(td.angle)) end,
	}
end

local function frameFrom(input: any): any
	local fr = Input.emptyFrame()
	for k, v in input do
		(fr :: any)[k] = v
	end
	return fr
end

-- Mirrors `snap` in the recorder. Numbers are stringified the same way on both sides.
--
-- Written with explicit indices, not table.insert. `table.insert(row, nil)` inserts NOTHING, so a
-- nil moveId silently shifted every later column left and the first run reported forty scenarios
-- failing on a field that was actually correct.
local function snap(f: any, fields: { string }, buffers: { string }): { any }
	local row = {}
	local at = 0
	local function put(v: any)
		at += 1
		row[at] = v
	end
	for _, k in fields do
		put(f[k])
	end
	put(if f.platform then f.platform.id else nil)
	local bufs = {}
	for _, b in buffers do
		table.insert(bufs, tostring(f.buffer[b]))
	end
	put(table.concat(bufs, ","))
	local keys = {}
	for k, v in f.mech do
		if typeof(v) ~= "table" then
			table.insert(keys, k)
		end
	end
	table.sort(keys)
	local mech = {}
	for _, k in keys do
		table.insert(mech, `{k}={tostring(f.mech[k])}`)
	end
	put(table.concat(mech, ","))
	local e = f.effects
	put(table.concat({
		tostring(e.chill.stacks), tostring(e.chill.timer), tostring(e.tangle.stacks),
		tostring(e.tangle.timer), tostring(e.grit.hide), tostring(e.grit.slow),
		tostring(e.slow), tostring(e.frozenBonus), tostring(e.lodestone), tostring(e.bleed),
	}, ","))
	put(if f.ledge then `{f.ledge.x}:{f.ledge.side}` else nil)
	put(if f.la then f.la.kind else nil)
	put(if f.tether then `{f.tether.tx}:{f.tether.ty}` else nil)
	local types = {}
	for _, ev in f.events do
		table.insert(types, ev.type)
	end
	put(table.concat(types, ","))
	-- The computed properties, which Combat will read in Phase 3 and which no raw field implies.
	put(f.cy)
	put(f.untouchable)
	put(f:isDodgeInvincible())
	put(f.moveActive)
	put(f.grabActive)
	put(f.busy)
	put(f.ultReady)
	put(f.ultMeter)
	put(f.moveFrameAbs)
	put(f.isInvincible)
	put(f.inHitstun)
	local hb = f.hurtbox
	put(hb.x1)
	put(hb.x2)
	put(hb.y1)
	put(hb.y2)
	return row
end

local LABELS = {}
for i, k in T.fields do
	LABELS[i] = k
end
local EXTRA = { "platform", "buffer", "mech", "effects", "ledge", "la", "tether", "events",
	"cy", "untouchable", "isDodgeInvincible", "moveActive", "grabActive", "busy", "ultReady",
	"ultMeter", "moveFrameAbs", "isInvincible", "inHitstun",
	"hurtbox.x1", "hurtbox.x2", "hurtbox.y1", "hurtbox.y2" }
for i, k in EXTRA do
	LABELS[#T.fields + i] = k
end

for _, spec in T.scenarios do
	local data = table.clone(StageData.BY_ID[spec.stage])
	data.hazards = {}
	local stage = Stage.new(data)
	local char = Loadout.build(spec.avatar, spec.weapon)
	local f = Fighter.new({ index = 0, char = char, x = tonumber(spec.x), y = tonumber(spec.y),
		stocks = 3, name = "P" })
	if not spec.keepRespawn then
		f:setState("air")
		f.invincible = 0
	end
	local combat = stubCombat({ f })
	local ctx = { stage = stage, combat = combat, fighters = { f } }
	local events: { [number]: any } = {}
	for _, e in spec.events or {} do
		events[tonumber(e.frame) :: number] = e
	end

	local frame = 0
	local broke = false
	for _, seg in spec.segments do
		if broke then break end
		for _ = 1, seg.frames do
			local ev = events[frame]
			if ev then
				local k = ev.kind
				if k == "hit" then
					f:applyHit({ damage = tonumber(ev.damage), launch = tonumber(ev.launch),
						stun = tonumber(ev.stun), angle = tonumber(ev.angle),
						facing = tonumber(ev.facing), attacker = nil, hitlag = tonumber(ev.hitlag),
						extraHitstun = tonumber(ev.extraHitstun) or 0 })
				elseif k == "freeze" then f:freeze(tonumber(ev.frames) :: number)
				elseif k == "launchNoStun" then f:launchNoStun(tonumber(ev.vx) :: number, tonumber(ev.vy) :: number)
				elseif k == "knockOut" then f:knockOut()
				elseif k == "respawn" then f:respawn(tonumber(ev.x) :: number, {})
				elseif k == "block" then
					f:applyBlock({ damage = tonumber(ev.damage), facing = tonumber(ev.facing),
						perfect = not not ev.perfect })
				elseif k == "charge" then f:chargeUltimate(tonumber(ev.n) :: number)
				elseif k == "landed" then f.moveLanded = true
				elseif k == "carry" then
					f.carryX = tonumber(ev.carryX)
					f.snaredBy = tonumber(ev.snaredBy) or 0
				end
			end
			table.clear(f.events)
			f:applyInput(frameFrom(seg.input))
			Stage.step(stage, { fighters = { f } })
			f:step(ctx)

			local got = snap(f, T.fields, T.buffers)
			local want = spec.rows[frame + 1]
			for i = 1, #T.fields + #EXTRA do
				local g, w = got[i], want[i]
				checked += 1
				local ok
				if typeof(g) == "number" then
					ok = w ~= nil and near(g, tonumber(w) :: number)
				else
					ok = (g == w) or (g == nil and w == nil)
				end
				if not ok then
					fail(string.format("%s frame %d: %s = %s, JS says %s",
						spec.name, frame, tostring(LABELS[i]), tostring(g), tostring(w)))
					broke = true
					break
				end
			end
			if broke then break end
			frame += 1
		end
	end

	-- The call log: right values AND right frames.
	if not broke then
		checked += 1
		if #combat.log ~= #spec.log then
			fail(string.format("%s: combat called %d times, JS called %d", spec.name, #combat.log, #spec.log))
		else
			for i, want in spec.log do
				if combat.log[i] ~= want then
					fail(string.format("%s: combat call %d was %s, JS made %s", spec.name, i,
						tostring(combat.log[i]), tostring(want)))
					break
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- rollback ----
-- snapshot -> run on -> restore -> replay. The replayed frames must still equal the JavaScript's,
-- which is exactly what client-side prediction needs: re-simulating from a restored state has to
-- land in the same place as simulating straight through. A field left out of snapshot() shows up
-- here as the first frame that drifts after the restore.
--
-- FoundryFloor only. The stage keeps stepping while the fighter is rolled back, so this needs a
-- stage whose geometry does not move; restoring the fighter alone onto a raft that has slid on
-- would be measuring the stage, not the snapshot.
local rollbacks = 0
for _, spec in T.scenarios do
	if spec.stage == "FoundryFloor" and #spec.rows > 60 then
		local data = table.clone(StageData.BY_ID[spec.stage])
		data.hazards = {}
		local stage = Stage.new(data)
		local char = Loadout.build(spec.avatar, spec.weapon)
		local f = Fighter.new({ index = 0, char = char, x = tonumber(spec.x), y = tonumber(spec.y),
			stocks = 3, name = "P" })
		if not spec.keepRespawn then
			f:setState("air")
			f.invincible = 0
		end
		local ctx = { stage = stage, combat = stubCombat({ f }), fighters = { f } }
		local events: { [number]: any } = {}
		for _, e in spec.events or {} do
			events[tonumber(e.frame) :: number] = e
		end
		-- flatten the segments so a frame can be replayed by index
		local inputs = {}
		for _, seg in spec.segments do
			for _ = 1, seg.frames do
				table.insert(inputs, seg.input)
			end
		end

		local function drive(i: number)
			local ev = events[i - 1]
			if ev then
				local k = ev.kind
				if k == "hit" then
					f:applyHit({ damage = tonumber(ev.damage), launch = tonumber(ev.launch),
						stun = tonumber(ev.stun), angle = tonumber(ev.angle),
						facing = tonumber(ev.facing), attacker = nil, hitlag = tonumber(ev.hitlag),
						extraHitstun = tonumber(ev.extraHitstun) or 0 })
				elseif k == "freeze" then f:freeze(tonumber(ev.frames) :: number)
				elseif k == "launchNoStun" then f:launchNoStun(tonumber(ev.vx) :: number, tonumber(ev.vy) :: number)
				elseif k == "knockOut" then f:knockOut()
				elseif k == "respawn" then f:respawn(tonumber(ev.x) :: number, {})
				elseif k == "block" then
					f:applyBlock({ damage = tonumber(ev.damage), facing = tonumber(ev.facing),
						perfect = not not ev.perfect })
				elseif k == "charge" then f:chargeUltimate(tonumber(ev.n) :: number)
				elseif k == "landed" then f.moveLanded = true
				elseif k == "carry" then
					f.carryX = tonumber(ev.carryX)
					f.snaredBy = tonumber(ev.snaredBy) or 0
				end
			end
			table.clear(f.events)
			f:applyInput(frameFrom(inputs[i]))
			Stage.step(stage, { fighters = { f } })
			f:step(ctx)
		end

		local at = math.floor(#inputs * 0.4)
		for i = 1, at do
			drive(i)
		end
		local snapshot = f:snapshot()

		-- STRUCTURAL: every field the fighter owns has to be in the snapshot. A behavioural test
		-- can only catch a missing field if the scenario happens to depend on it - dropping `vx`
		-- fails loudly, dropping a rarely-read counter does not - and "rarely read" is exactly
		-- what a desync under packet loss is made of.
		for k, v in f do
			checked += 1
			if snapshot[k] == nil and v ~= nil and typeof(v) ~= "function" then
				fail(string.format("%s: snapshot() omits the field %q", spec.name, tostring(k)))
			end
		end

		-- ALIASING: the snapshot must be independent of the live fighter. `s.buffer = self.buffer`
		-- instead of a clone reads back whatever the buffer became, not what it was, and no
		-- scenario here notices because the buffers happen to be zero at the snapshot point.
		local frozen = deepCopy(snapshot)

		-- Scribble on every table the fighter owns, IMMEDIATELY.
		--
		-- Running the fighter on and looking for drift is not enough, twice over. effects.chill,
		-- stats and mech.hits never change during the window in any of these scenarios. And di and
		-- mech.hits are REPLACED each frame rather than mutated, so a snapshot aliasing them is
		-- pointing at a table nothing touches again - poking after the run-on hits the new table
		-- and misses the aliased one entirely. Poking right away tests the property that actually
		-- matters: the snapshot is independent of the fighter, whatever the fighter does next.
		--
		-- These frames are not compared against the JavaScript, so corrupting them is free; the
		-- restore below wipes all of it, which is the other half of what is being tested.
		f.buffer.jump = 99
		f.effects.chill.stacks = 3
		f.effects.tangle.timer = 123
		f.effects.grit.hide = 45
		f.stats.kos = 77
		f.di.x = 9
		f.env.grip = 0.01
		f.input.x = 9
		f.hitVictims[999] = true
		table.insert(f.ultHeld, "junk")
		if f.mech.hits then
			table.insert(f.mech.hits, -1)
		end
		if f.hold then f.hold.frames = 999 end
		if f.tether then f.tether.speed = 999 end
		if f.la then f.la.kind = "junk" end
		if f.pendingLaunch then f.pendingLaunch.launch = 999 end

		for i = at + 1, math.min(#inputs, at + 25) do
			drive(i)
		end

		checked += 1
		local drift = firstDifference(snapshot, frozen, "")
		if drift then
			fail(string.format("%s: snapshot aliases live state -%s changed with the fighter",
				spec.name, drift))
		end

		f:restore(snapshot)
		rollbacks += 1

		-- restore() must clone too. Handing the fighter the snapshot's own tables works exactly
		-- once: the second rollback to the same frame restores whatever the first one left behind.
		f.effects.chill.stacks = 2
		f.stats.falls = 55
		f.buffer.dodge = 88
		f.di.y = 7
		checked += 1
		local back = firstDifference(snapshot, frozen, "")
		if back then
			fail(string.format("%s: restore() aliased the snapshot -%s followed the fighter",
				spec.name, back))
		end
		f:restore(snapshot)

		local bad = false
		for i = at + 1, #inputs do
			drive(i)
			local got = snap(f, T.fields, T.buffers)
			local want = spec.rows[i]
			for k = 1, #T.fields + #EXTRA do
				local g, w = got[k], want[k]
				checked += 1
				local ok
				if typeof(g) == "number" then
					ok = w ~= nil and near(g, tonumber(w) :: number)
				else
					ok = (g == w) or (g == nil and w == nil)
				end
				if not ok then
					fail(string.format("%s ROLLBACK frame %d: %s = %s, JS says %s",
						spec.name, i - 1, tostring(LABELS[k]), tostring(g), tostring(w)))
					bad = true
					break
				end
			end
			if bad then break end
		end
	end
end

print(string.format("replayed %d fighter values across %d scenarios (%d with a snapshot/restore)",
	checked, #T.scenarios, rollbacks))
if #failures > 0 then
	print(string.format("\n%d MISMATCHES:", #failures))
	for _, f in failures do
		print("  " .. f)
	end
	process.exit(1)
end
print(string.format("Fighter.luau matches web/src/engine/fighter.js to within %g relative.", EPS))
