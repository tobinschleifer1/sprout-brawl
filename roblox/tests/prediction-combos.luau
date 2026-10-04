--!strict
-- Combos predicted on the server's frames (Config.COMBO, Snapshot's combo fields).
--
--     lune run tests/prediction-combos
--
-- The chase is the one inexact thing: it aims at another fighter, whom the client knows only from a
-- snapshot and can only extrapolate (it cannot see their launch out of a freeze). Up to 6 frames of
-- lag it is exact; past that a few reconciles may disagree, and no correction may be big enough
-- to need more than easing (a quarter of Predictor.SNAP_STUDS).
--
-- The predicting client never sees its own hits land - its combat is a stub - so before the
-- snapshot carried `moveLanded` it could not predict a chain at all: every follow-up of a string
-- arrived a round trip late as a correction. This runs a real server Match with the local fighter
-- playing a timed string, and a Predictor fed the same inputs and reconciled against snapshots
-- LAG frames old. After every reconcile the predicted fighter must be exactly where the server's
-- was on the same frame: same move, same state, same move frame, same position. Two strings:
--   * Slash > Backslash > Cross Cut > Judgement, every link timed (the finisher opens only off the
--     streak, so the streak and depth have to be right too);
--   * Rising Cut, jump-cancelled into an aerial that chases (the cancel flag, the chase window and
--     the fighter it chases have to be right).
local Loader = require("./loader")
local Match = Loader.load("Match")
local Loadout = Loader.load("Loadout")
local Input = Loader.load("Input")
local Stage = Loader.load("Stage")
local Stages = Loader.load("Data/Stages")
local Snapshot = Loader.load("Snapshot")
local Predictor = Loader.loadFrom("src/client/", "Predictor")

local function fail(msg: string): never
	error(msg, 0)
end

local data = Stages.LIST[1]
for _, s in Stages.LIST do if s.id == "FoundryFloor" then data = s end end
local SEED = 7
local CHASE_TOLERANCE = 0.1
local worstChase = 0

-- `policy(f, n)` is the local player's input on frame n, decided from the server's own fighter
-- the way a player decides from what is on screen.
local function run(name: string, percent: number, policy: (any, number) -> any, want: { string }, lag: number, allowed: number?, forget: boolean?): number
	local script: { [number]: any } = {}
	local n = 0
	local input = { poll = function() end, get = function(_, source: string)
		if source == "p0" then return script[n] or Input.emptyFrame() end
		return Input.emptyFrame()
	end }
	local char = Loadout.build("Classic", "Sword")
	local m = Match.new({ mode = "Training", stage = data, seed = SEED, items = false, input = input, fighters = {
		{ char = char, source = "p0", team = 0 },
		{ char = Loadout.build("Noir", "Sword"), source = "p1", team = 1 },
	} })
	m.state = "fight"
	local top = m.stage.main.top
	local a, v = m.fighters[1], m.fighters[2]
	a:reset(-1.2, top, { state = "idle", invincible = 0 })
	v:reset(1.2, top, { state = "idle", invincible = 0 })
	for _, f in m.fighters do f.onGround, f.platform = true, m.stage.main end
	a.facing, v.facing = 1, -1
	v.percent = percent

	local pred = Predictor.new(char, 0, Stage.new(data, SEED))
	local wire: { [number]: any } = {}
	local others: { [number]: any } = {}
	local seen: { [string]: boolean } = {}
	local mismatches, compared, unseen = 0, 0, 0
	local chased, worst = false, 0
	local hitAt: { [number]: boolean } = {}
	local first: string? = nil
	for frame = 1, 140 do
		n = frame
		local f = policy(a, frame) or Input.emptyFrame()
		script[frame] = f
		m:step()
		for _, e in m.events do
			if e.type == "hit" and e.attacker == 0 then hitAt[frame] = true end
			if e.type == "chase" and e.fighter == 0 then chased = true end
		end
		table.clear(m.events)
		pred:push(f)
		if a.moveId then seen[a.moveId] = true end
		wire[frame] = Snapshot.decode(Snapshot.encode(a))
		local snap = {}
		for _, fi in m.fighters do
			snap[fi.index] = { index = fi.index, x = fi.x, y = fi.y, vx = fi.vx, vy = fi.vy, h = fi.h, alive = fi.alive, comboHits = fi.comboHits, onGround = fi.onGround, hitlag = fi.hitlag }
		end
		others[frame] = snap
		if frame > lag and frame % 2 == 0 then
			-- `forget`: no local history to roll back to (the first snapshot, or after a gap), so
			-- the wire alone has to carry the string's state
			if forget then pred.snaps[frame - lag] = nil end
			pred:reconcile(wire[frame - lag], frame - lag, nil, others[frame - lag])
			local p = pred.fighter
			-- A hit the server landed after this snapshot was taken cannot be known yet (the
			-- client's combat is a stub): its freeze is a correction the next snapshot brings,
			-- whatever is on the wire. Everything else must be exact.
			local hidden = false
			for k = frame - lag + 1, frame do if hitAt[k] then hidden = true end end
			if hidden then unseen += 1; continue end
			compared += 1
			-- A chase aims at the other fighter, whom the client knows only as of the snapshot - it
			-- cannot replay their launch - so once a chase is under way the position may be off by
			-- a sliver (CHASE_TOLERANCE, far under Predictor.SNAP_STUDS, and eased out in ~70ms).
			-- Everything else is exact.
			local tol = if chased then CHASE_TOLERANCE else 1e-6
			local d = math.max(math.abs(p.x - a.x), math.abs(p.y - a.y))
			worst = math.max(worst, d)
			local ok = p.moveId == a.moveId and p.state == a.state and p.mf == a.mf and d < tol
			if d >= Predictor.SNAP_STUDS / 4 then
				fail(`{name} at lag {lag}, frame {frame}: a {d}-stud correction - too big to ease over`)
			end
			if not ok then
				mismatches += 1
				first = first or `frame {frame}: predicted {p.state}/{tostring(p.moveId)}@{p.mf} at ({p.x}, {p.y}), server {a.state}/{tostring(a.moveId)}@{a.mf} at ({a.x}, {a.y})`
			end
		end
	end
	for _, id in want do
		if not seen[id] then fail(`{name}: the server never reached {id} - the script is not exercising the route`) end
	end
	if mismatches > (allowed or 0) * compared then fail(`{name} at lag {lag}: {mismatches} of {compared} reconciles disagreed with the server; first, {first}`) end
	if chased then worstChase = math.max(worstChase, worst) end
	if compared < 40 then fail(`{name} at lag {lag}: only {compared} reconciles were comparable`) end
	return compared
end

local function press(o: any): any
	local f = Input.emptyFrame()
	for k, val in o do (f :: any)[k] = val end
	f.anyPress = true
	return f
end

local total = 0
for _, lag in { 0, 3, 6, 10 } do
	-- every link pressed while the previous move lands
	total += run("timed string into Judgement", 100, function(a: any, frame: number)
		if frame == 2 then return press({ light = true }) end
		if a.state == "attack" and a.moveLanded and a.moveId ~= "Finisher" then return press({ light = true }) end
		return nil
	end, { "LightNeutral2", "LightNeutral3", "Finisher" }, lag)
	-- Rising Cut, jump-cancelled once it lands, then an up-aerial pressed until it comes out
	total += run("jump cancel into a chase", 200, function(a: any, frame: number)
		if frame == 2 then return press({ light = true, y = 1 }) end
		if a.state == "attack" and a.moveLanded and a.moveId == "LightUp" then return press({ jump = true, jumpHeld = true }) end
		if a.state == "jumpsquat" or (a.state == "air" and not a.move) then return press({ light = true, y = 1 }) end
		return nil
	end, { "LightUp", "AirUp" }, lag, if lag > 6 then 0.05 else 0)
end

-- The local player as the VICTIM, pressing Dodge in the freeze of the fourth hit: the break is
-- predicted on the server's frame only if the combo count and breakability arrive on the wire,
-- because hits write them and the client's combat is a stub. Then the same string ending in a
-- finisher, which cannot be broken: the predicted Dodge must not break it either.
local function victimRun(name: string, ending: string, lag: number): number
	local script: { [number]: any } = {}
	local n = 0
	local attacker: any = nil
	local input = { poll = function() end, get = function(_, source: string)
		if source == "p0" then return script[n] or Input.emptyFrame() end
		local a = attacker
		if not a then return Input.emptyFrame() end
		if n == 2 then return press({ light = true }) end
		if a.state == "attack" and a.moveLanded and a.moveId == "LightNeutral3" then
			return press(if ending == "heavy" then { heavy = true, heavyHeld = true, y = -1 } else { light = true })
		end
		if a.state == "attack" and a.moveLanded and (a.moveId == "LightNeutral1" or a.moveId == "LightNeutral2") then return press({ light = true }) end
		return Input.emptyFrame()
	end }
	local char = Loadout.build("Noir", "Sword")
	local m = Match.new({ mode = "Training", stage = data, seed = SEED, items = false, input = input, fighters = {
		{ char = char, source = "p0", team = 0 },
		{ char = Loadout.build("Classic", "Sword"), source = "p1", team = 1 },
	} })
	m.state = "fight"
	local top = m.stage.main.top
	local v, a = m.fighters[1], m.fighters[2]
	attacker = a
	v:reset(1.2, top, { state = "idle", invincible = 0 })
	a:reset(-1.2, top, { state = "idle", invincible = 0 })
	for _, f in m.fighters do f.onGround, f.platform = true, m.stage.main end
	a.facing, v.facing = 1, -1
	v.percent = 150
	local pred = Predictor.new(char, 0, Stage.new(data, SEED))
	local wire, others = {}, {}
	local broke, compared, hitAt = false, 0, {}
	for frame = 1, 120 do
		n = frame
		-- the victim reads the fourth hit's freeze and presses Dodge once
		local f = if v.state == "hitstun" and v.hitlag > 0 and v.comboHits >= 4 and not broke and frame > 1 then press({ dodge = true }) else Input.emptyFrame()
		if f.dodge then broke = true end
		script[frame] = f
		m:step()
		for _, e in m.events do if e.type == "hit" then hitAt[frame] = true end end
		table.clear(m.events)
		pred:push(f)
		wire[frame] = Snapshot.decode(Snapshot.encode(v))
		local snap = {}
		for _, fi in m.fighters do snap[fi.index] = { index = fi.index, x = fi.x, y = fi.y, vx = fi.vx, vy = fi.vy, h = fi.h, alive = fi.alive, comboHits = fi.comboHits, onGround = fi.onGround, hitlag = fi.hitlag } end
		others[frame] = snap
		if frame > lag and frame % 2 == 0 then
			pred:reconcile(wire[frame - lag], frame - lag, nil, others[frame - lag])
			local hidden = false
			for k = frame - lag + 1, frame do if hitAt[k] then hidden = true end end
			if not hidden then
				compared += 1
				local p = pred.fighter
				-- A victim's launch out of a freeze is not on the wire (it is the existing limit of
				-- prediction: a hit fighter snaps), so positions are compared only once the snapshot
				-- is past the freeze. The state and cooldown - whether the break happened - always.
				local pastFreeze = (wire[frame - lag].hitlag or 0) == 0
				local off = pastFreeze and (math.abs(p.x - v.x) > 1e-6 or math.abs(p.y - v.y) > 1e-6)
				if p.state ~= v.state or p.breakCooldown ~= v.breakCooldown or off then
					fail(`{name} at lag {lag}, frame {frame}: predicted {p.state} (cooldown {p.breakCooldown}) at ({p.x}, {p.y}), server {v.state} (cooldown {v.breakCooldown}) at ({v.x}, {v.y})`)
				end
			end
		end
	end
	if not broke then fail(`{name}: the victim never got to press Dodge in a fourth hit's freeze`) end
	local didBreak = v.breakCooldown > 0
	if (ending == "heavy") ~= didBreak then fail(`{name}: the server {if didBreak then "broke" else "did not break"} - the script is not testing what it says`) end
	return compared
end
for _, lag in { 3, 6 } do
	total += victimRun("a predicted break", "heavy", lag)
	total += victimRun("a predicted finisher, unbroken", "light", lag)
end

print(`PASS prediction of combos: {total} reconciles at lags 0-10 frames. A timed string into a finisher: exact on the server's every frame. A cancelled, chasing aerial: exact to 6 frames of lag; at 10, under 5% off and {string.format("%.3f", worstChase)} studs at worst, eased not snapped. The victim's Dodge: a break predicted exactly, and a finisher predicted unbroken`)
