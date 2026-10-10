--!strict
-- Instant hits and lag compensation, end to end (combat phase 4).
--
--     lune run tests/instant-hits
--
-- A real server Match and a real Predictor, joined by a connection LAG frames long each way: the
-- client sends each input with the snapshot frame it is drawing the foe at (INTERP frames behind
-- the newest), the server consumes it LAG frames later and rewinds the foe to that frame for the
-- local player's swings (Combat.rewindOf, as MatchService sets it), and the client reconciles
-- against snapshots LAG frames old. The local player walks at the foe AS DRAWN and swings when
-- close; the foe walks, jumps, shields and dodges on its own script and never attacks.
--
--   * a swing meeting the foe as drawn lands at once on the client - and the server lands the
--     same swing on the same frame, so the client's first guess at each frame is the server's
--     answer: with the rewind inside the cap, every predicted hit is confirmed except where the
--     foe was dodging or shielding on the server and not yet on screen (the defender's "now"), and
--     every hit the server lands was predicted;
--   * without lag compensation the server judges the swing against where the foe is now, and the
--     two disagree; without the instant hit every landed hit is a frozen frame the client got wrong;
--   * past the cap (a long connection) the rewind is partial and some predicted hits are taken
--     back, which inside the cap none are.
-- And HitConfirm: the server's copy of a predicted hit is not drawn again, unless it was the kill.
local Loader = require("./loader")
local Match = Loader.load("Match")
local Loadout = Loader.load("Loadout")
local Input = Loader.load("Input")
local Stage = Loader.load("Stage")
local Stages = Loader.load("Data/Stages")
local Snapshot = Loader.load("Snapshot")
local Config = Loader.load("Config")
local Predictor = Loader.loadFrom("src/client/", "Predictor")
local HitConfirm = Loader.loadFrom("src/client/", "HitConfirm")

local function fail(msg: string): never
	error(msg, 0)
end

local data = Stages.LIST[1]
for _, s in Stages.LIST do if s.id == "FoundryFloor" then data = s end end
local SEED = 7
local INTERP = 2
local KINDS = { hit = true, block = true, armor = true, crack = true, crackmark = true }

-- `policy`: "mixed" (walk in, jab and heavy on a clock, jump now and then - aerials), "timed" (every
-- link pressed the frame the last move lands, the way the combo system rewards: off the client's
-- own instant hits) or "heavy" (the same heavy again and again, so staling moves its freeze).
local function run(lag: number, opts: { lagComp: boolean, instant: boolean, weapon: string?, policy: string? }): any
	local frames = 3600
	local policy = opts.policy or "mixed"
	local myChar = Loadout.build("Classic", opts.weapon or "Sword")
	local foeChars = { Loadout.build("Noir", "Hammer"), Loadout.build("Ember", "Pike") }
	-- the foes' scripts: seeded walks, jumps, shield windows and dodges
	local rng = 12345
	local function rand(): number
		rng = (rng * 1103515245 + 12345) % 2147483648
		return rng / 2147483648
	end
	local foeX, shieldLeft = { 1, -1 }, { 0, 0 }
	local inbox: { any } = {}            -- p0's inputs that have reached the server
	local consumed, viewNow = 0, nil :: number?
	local foeNow = { Input.emptyFrame(), Input.emptyFrame() }
	local input = { poll = function() end, get = function(_, source: string): any
		if source == "p1" then return foeNow[1] end
		if source == "p2" then return foeNow[2] end
		local item = table.remove(inbox, 1)
		if not item then return Input.emptyFrame() end
		consumed += 1
		viewNow = item.view
		return item.frame
	end }
	local m = Match.new({ mode = "Training", stage = data, seed = SEED, items = false, input = input, fighters = {
		{ char = myChar, source = "p0", team = 0 },
		{ char = foeChars[1], source = "p1", team = 1 },
		{ char = foeChars[2], source = "p2", team = 2 },
	} })
	m.state = "fight"
	local top = m.stage.main.top
	local a = m.fighters[1]
	a:reset(-4, top, { state = "idle", invincible = 0 })
	m.fighters[2]:reset(4, top, { state = "idle", invincible = 0 })
	m.fighters[3]:reset(9, top, { state = "idle", invincible = 0 })
	for _, f in m.fighters do f.onGround, f.platform = true, m.stage.main end
	if opts.lagComp then
		m.combat.rewindOf = function(f: any): number
			return if f.index == 0 and viewNow then m.frame - viewNow else 0
		end
	end

	local pred = Predictor.new(myChar, 0, Stage.new(data, SEED))
	local toServer: { any } = {}
	local toClient: { any } = {}
	local snaps: { any } = {}            -- what the client has received, oldest first
	local guessed: { [number]: any } = {}   -- the client's first prediction of each frame
	local truth: { [number]: any } = {}
	local predicted: { [number]: { string } } = {}   -- "kind@victim"
	local landed: { [number]: { string } } = {}
	-- each foe's guard when a swing met them on the server, and as the client drew them
	local served: { [number]: { [number]: string } } = {}
	local drawn: { [number]: { [number]: string } } = {}
	local worst = 0
	local teamOf = function(i: number): any return i end
	local charOf = function(i: number): any return if i == 0 then myChar else foeChars[i] end
	local function guard(alive: boolean, untouchable: boolean, state: string): string
		return if not alive then "gone" elseif untouchable then "dodge" elseif state == "shield" then "shield" else "open"
	end
	for t = 1, frames do
		-- ---- client: what has arrived, the view, then this frame's input ----
		while toClient[1] and toClient[1].at <= t do
			local snap = table.remove(toClient, 1).snap
			table.insert(snaps, snap)
			local others = {}
			for _, st in snap.fighters do
				others[st.index] = { index = st.index, x = st.x, y = st.y, vx = st.vx, vy = st.vy, h = charOf(st.index).height,
					alive = st.alive, comboHits = st.comboHits or 0, onGround = st.onGround, hitlag = st.hitlag or 0 }
			end
			pred:reconcile(snap.fighters[1], snap.ack, snap.platforms, others)
			if (pred.lastCorrection or 0) > worst then worst = pred.lastCorrection end
			while #snaps > 16 do table.remove(snaps, 1) end
		end
		local view = snaps[math.max(1, #snaps - INTERP)]
		local frame = Input.emptyFrame()
		if view then
			local foes = Predictor.foes(view.fighters, 0, teamOf, charOf)
			if opts.instant then pred:look(view.frame, foes) end
			drawn[t] = {}
			for i = 1, 2 do
				local st = view.fighters[i + 1]
				local seen = nil
				for _, fo in foes do if fo.index == i then seen = fo end end
				drawn[t][i] = guard(st.alive, seen ~= nil and seen.untouchable, st.state)
			end
			-- the nearest foe as drawn
			local mine = pred:state()
			local foe, best = nil, math.huge
			for i = 2, 3 do
				local st = view.fighters[i]
				if st.alive and math.abs(st.x) < 17 and math.abs(st.x - mine.x) < best then foe, best = st, math.abs(st.x - mine.x) end
			end
			local dx = if foe then foe.x - mine.x else -mine.x
			local toward = if dx > 0 then 1 else -1
			if math.abs(mine.x) > 15 then frame.x = if mine.x > 0 then -1 else 1      -- never off the stage after them
			elseif not foe then frame.x = 0
			elseif policy == "timed" and mine.state == "attack" and mine.moveLanded and mine.moveId ~= "Finisher" then
				frame.light = true; frame.anyPress = true
			elseif math.abs(dx) > 2.2 then frame.x = toward
			elseif policy == "heavy" then
				if mine.state ~= "attack" and t % 4 == 0 then frame.heavy = true; frame.anyPress = true; frame.x = toward * 0.6 end
			elseif t % 16 == 0 then frame.light = true; frame.anyPress = true
				-- in the air, forward: the arc slash, which bounces its attacker on a hit
				if not mine.onGround then frame.x = toward end
			elseif t % 53 == 0 and policy == "mixed" then frame.heavy = true; frame.anyPress = true; frame.x = toward * 0.6 end
			if t % 97 == 0 then frame.jump = true; frame.jumpHeld = true end
		end
		pred:push(frame)
		guessed[t] = pred:state()
		for _, e in pred:drain() do
			if e.predicted then predicted[t] = predicted[t] or {}; table.insert(predicted[t], `{e.type}@{e.victim}`) end
		end
		table.insert(toServer, { at = t + lag, frame = frame, view = if view then view.frame else nil })

		-- ---- server ----
		for i = 1, 2 do
			local v = m.fighters[i + 1]
			local now = Input.emptyFrame()
			if rand() < 0.04 then foeX[i] = if rand() < 0.5 then -1 else 1 end
			if rand() < 0.03 then foeX[i] = 0 end
			now.x = foeX[i]
			if rand() < 0.015 then now.jump = true; now.jumpHeld = true end
			if shieldLeft[i] > 0 then shieldLeft[i] -= 1; now.guardHeld = true; now.x = 0
			elseif rand() < 0.012 then shieldLeft[i] = 25; now.guard = true; now.guardHeld = true; now.anyPress = true end
			if rand() < 0.01 then now.dodge = true; now.anyPress = true end
			-- keep them on the stage: walk back to the middle from the edges
			if v.x > 14 then now.x = -1 elseif v.x < -14 then now.x = 1 end
			foeNow[i] = now
		end
		while toServer[1] and toServer[1].at <= t do table.insert(inbox, table.remove(toServer, 1)) end
		local before = consumed
		m:step()
		if consumed > before then
			local seq = consumed
			truth[seq] = Snapshot.decode(Snapshot.encode(a))
			for _, e in m.events do
				if KINDS[e.type] and (e.attacker == 0 or (e.type == "block" and e.victim ~= 0)) then
					landed[seq] = landed[seq] or {}; table.insert(landed[seq], `{e.type}@{e.victim}`)
				end
			end
			-- after the step: a swing that met a dodge leaves them dodging, one that met a shield
			-- leaves them shielding, one that landed leaves them in hitstun
			served[seq] = {}
			for i = 1, 2 do
				local v = m.fighters[i + 1]
				served[seq][i] = guard(v.alive, v.untouchable, v.state)
			end
		end
		table.clear(m.events)
		local fighters = {}
		for i, f in m.fighters do fighters[i] = Snapshot.decode(Snapshot.encode(f)) end
		table.insert(toClient, { at = t + lag, snap = { frame = m.frame, fighters = fighters, ack = consumed, platforms = Stage.dynamicState(m.stage) } })
	end
	-- ---- the tally ----
	-- A hit judged differently because the foe's guard changed between the frame drawn and the
	-- server's now is the defender's "now" at work (Config.LAG_COMP), not a disagreement.
	local function guardMoved(seq: number, key: string): boolean
		local victim = tonumber(string.match(key, "@(%d+)")) :: number
		return (served[seq] or {})[victim] ~= (drawn[seq] or {})[victim]
	end
	local function same(seq: number): boolean
		local got, want = guessed[seq], truth[seq]
		if not got or not want then return false end
		for _, pair in Snapshot.FIELDS do
			local key = pair[1]
			local x, y = got[key], want[key]
			local ok = if type(x) == "number" and type(y) == "number" then math.abs(x - y) < 1e-9 else x == y
			if not ok then return false end
		end
		return true
	end
	local r = { predicted = 0, confirmed = 0, confirmedExact = 0, afterDefence = 0, deniedByDefence = 0, deniedOther = 0, landed = 0, unpredicted = 0,
		unpredictedByDefence = 0, frames = 0, exact = 0, worst = worst, misses = {}, perfect = 0 }
	-- A hit taken back by a dodge, or landed through one the client could not see, leaves the
	-- client's guess wrong until the correction carrying it arrives - a round trip and the view
	-- delay later. A confirmed hit inside that wake is not held to the frame; every other one is.
	local defence: { [number]: boolean } = {}
	for seq, list in predicted do
		for _, key in list do
			if not (landed[seq] and table.find(landed[seq], key)) and guardMoved(seq, key) then defence[seq] = true end
		end
	end
	for seq, list in landed do
		for _, key in list do
			if not (predicted[seq] and table.find(predicted[seq], key)) and guardMoved(seq, key) then defence[seq] = true end
		end
	end
	local wake = 2 * lag + INTERP + 2
	local function inWake(seq: number): boolean
		for k = seq - wake, seq do if defence[k] then return true end end
		return false
	end
	for seq, list in predicted do
		for _, key in list do
			r.predicted += 1
			local got = landed[seq]
			if got and table.find(got, key) then
				r.confirmed += 1
				if same(seq) then r.confirmedExact += 1
				elseif inWake(seq) then r.afterDefence += 1
				elseif #r.misses < 4 then
					local g, w = guessed[seq], truth[seq]
					local diff = {}
					for _, pair in Snapshot.FIELDS do
						local k = pair[1]
						if tostring(g[k]) ~= tostring(w[k]) then table.insert(diff, `{k} {tostring(g[k])}/{tostring(w[k])}`) end
					end
					table.insert(r.misses, `seq {seq} {key} confirmed but guessed differently: {table.concat(diff, ", ")}`)
				end
			elseif guardMoved(seq, key) then r.deniedByDefence += 1
			else r.deniedOther += 1; if #r.misses < 4 then table.insert(r.misses, `seq {seq} {key}: server {if got then table.concat(got, ",") else "nothing"}`) end end
		end
	end
	for seq, list in landed do
		for _, key in list do
			r.landed += 1
			if not (predicted[seq] and table.find(predicted[seq], key)) then
				if guardMoved(seq, key) then r.unpredictedByDefence += 1
				else r.unpredicted += 1; if #r.misses < 4 then table.insert(r.misses, `seq {seq} {key} not predicted`) end end
			end
		end
	end
	for seq in truth do
		if guessed[seq] then
			r.frames += 1
			if same(seq) then r.exact += 1 end
			if (truth[seq].perfectStreak or 0) > 0 then r.perfect += 1 end
		end
	end
	return r
end

local function show(name: string, r: any): string
	return `{name}: {r.predicted} predicted, {r.confirmed} confirmed ({r.confirmedExact} to the frame, {r.afterDefence} in a dodge's wake), {r.deniedByDefence} taken back by a dodge or shield, {r.deniedOther} otherwise; `
		.. `{r.landed} landed on the server, {r.unpredicted} not predicted (and {r.unpredictedByDefence} by a guard that moved); first guess right on {r.exact} of {r.frames} frames; worst correction {string.format("%.2f", r.worst)}`
end

-- ---- inside the cap: the instant hit is the server's ----
local within = {}
for _, case in {
	{ lag = 0 }, { lag = 1 }, { lag = 3 },
	-- strings timed off the instant hits, and the hammer's heavy again and again (staling)
	{ lag = 3, policy = "timed" }, { lag = 3, policy = "heavy", weapon = "Hammer" },
} do
	local lag = case.lag
	local name = `lag {lag} (rewind {2 * lag + INTERP}){if case.policy then ", " .. case.policy else ""}{if case.weapon then ", " .. case.weapon else ""}`
	local r = run(lag, { lagComp = true, instant = true, policy = case.policy, weapon = case.weapon })
	print(show(name, r))
	-- (a hammer's heavy is slow: fewer, but each one the same move again, staled)
	if r.landed < (if case.policy == "heavy" then 20 else 40) then fail(`{name}: only {r.landed} hits landed - the fight is not testing anything`) end
	if r.deniedOther > 0 then fail(`{name}: predicted hits the server did not land, with the foe not dodging: {table.concat(r.misses, "; ")}`) end
	if r.unpredicted > 0 then fail(`{name}: hits the server landed that the client did not see coming: {table.concat(r.misses, "; ")}`) end
	if r.confirmedExact + r.afterDefence < r.confirmed then fail(`{name}: confirmed hits the client guessed wrong: {table.concat(r.misses, "; ")}`) end
	-- (these foes dodge or shield about every forty frames, so a fair share are taken back)
	if r.confirmed < r.predicted * 0.8 then fail(`{name}: only {r.confirmed} of {r.predicted} predicted hits confirmed`) end
	if case.policy == "timed" and r.perfect < 30 then fail(`{name}: only {r.perfect} frames in a timed string - the policy is not timing links`) end
	if not case.policy then within[lag] = r end
end
print("PASS inside the rewind cap every predicted hit is the server's to the frame, but for the foes' own dodges and shields, and every hit the server lands was predicted")

-- ---- and without either half ----
do
	local base = within[3]
	local noComp = run(3, { lagComp = false, instant = true })
	local noInstant = run(3, { lagComp = true, instant = false })
	print(show("lag 3, no lag compensation", noComp))
	print(show("lag 3, no instant hit", noInstant))
	if noComp.deniedOther + noComp.unpredicted < 10 then fail("without lag compensation the server and the client still agree: the rewind is not what makes them") end
	if noInstant.exact > base.exact - noInstant.landed * 3 then
		fail(`without the instant hit the client's first guess is right on {noInstant.exact} frames against {base.exact}: the instant hit is not what makes them`)
	end
end
print("PASS without lag compensation the two disagree, and without the instant hit every landed hit is a frame guessed wrong")

-- ---- past the cap ----
do
	local r = run(5, { lagComp = true, instant = true })
	print(show(`lag 5 (rewind {2 * 5 + INTERP}, capped at {Config.LAG_COMP.maxFrames})`, r))
	if r.confirmed < r.predicted * 0.5 then fail(`past the cap only {r.confirmed} of {r.predicted} predicted hits held`) end
	-- inside the cap there were none of these: here the cap is what the two disagree on
	if r.deniedOther + r.unpredicted == 0 then fail("past the cap the server and the client still agree on every hit: the cap is not reached") end
end
print("PASS past the cap the rewind is partial: some instant hits are taken back, as agreed")

-- ---- every kind of instant hit, frame by frame ----
-- The fight above never puts a foe's heavy in the way, nor an aerial with no jumps left, nor a
-- multi-hit swing's freeze between its hits. Each of these is set up on a real server and on the
-- predictor alike, and run in lockstep - the view one frame behind, as the rewind - and the client's
-- first guess must be the server's on every frame: its kind of hit and the fighter it leaves,
-- what the wire carries and what the predictor keeps for itself.
local function lockstep(name: string, weapon: string, place: (any, any, any) -> (), press: (number) -> any, foeInput: ((number) -> any)?)
	local n = 0
	local script: { [number]: any } = {}
	local input = { poll = function() end, get = function(_, source: string): any
		if source == "p0" then return script[n] or Input.emptyFrame() end
		return if foeInput then foeInput(n) else Input.emptyFrame()
	end }
	local myChar, foeChar = Loadout.build("Classic", weapon), Loadout.build("Noir", "Hammer")
	local m = Match.new({ mode = "Training", stage = data, seed = SEED, items = false, input = input, fighters = {
		{ char = myChar, source = "p0", team = 0 }, { char = foeChar, source = "p1", team = 1 } } })
	m.state = "fight"
	local a, v = m.fighters[1], m.fighters[2]
	local top = m.stage.main.top
	a:reset(0, top, { state = "idle", invincible = 0 }); v:reset(2.2, top, { state = "idle", invincible = 0 })
	for _, f in m.fighters do f.onGround, f.platform = true, m.stage.main end
	a.facing, v.facing = 1, -1
	place(m, a, v)
	m.combat.rewindOf = function(f: any): number return if f.index == 0 then 1 else 0 end
	m.combat:recordHurtboxes()
	local pred = Predictor.new(myChar, 0, Stage.new(data, SEED))
	local others = {}
	for _, fi in m.fighters do
		others[fi.index] = { index = fi.index, x = fi.x, y = fi.y, vx = fi.vx, vy = fi.vy, h = fi.h, alive = fi.alive, comboHits = fi.comboHits, onGround = fi.onGround, hitlag = fi.hitlag }
	end
	pred:reconcile(Snapshot.decode(Snapshot.encode(a)), 0, nil, others)
	local p = pred.fighter
	p.jumpsLeft, p.airDodgeUsed = a.jumpsLeft, a.airDodgeUsed
	local kinds = {}
	for frame = 1, 70 do
		n = frame
		local f = press(frame) or Input.emptyFrame()
		script[frame] = f
		local seen = {}
		for i, fi in m.fighters do seen[i] = Snapshot.decode(Snapshot.encode(fi)) end
		pred:look(m.frame, Predictor.foes(seen, 0, function(i: number): any return i end, function(i: number): any return if i == 0 then myChar else foeChar end))
		pred:push(f)
		local mine = {}
		for _, e in pred:drain() do if e.predicted then table.insert(mine, e.type) end end
		m:step()
		local theirs = {}
		for _, e in m.events do
			if KINDS[e.type] and (e.attacker == 0 or (e.type == "block" and e.victim == 1)) then table.insert(theirs, e.type) end
		end
		table.clear(m.events)
		if table.concat(mine, ",") ~= table.concat(theirs, ",") then
			fail(`{name}, frame {frame}: predicted {table.concat(mine, ",")}, the server {table.concat(theirs, ",")}`)
		end
		for _, e in theirs do table.insert(kinds, e) end
		local got, want = pred:state(), Snapshot.decode(Snapshot.encode(a))
		for _, pair in Snapshot.FIELDS do
			local key = pair[1]
			local x, y = got[key], want[key]
			local ok = if type(x) == "number" and type(y) == "number" then math.abs(x - y) < 1e-9 else x == y
			if not ok then fail(`{name}, frame {frame}: {key} guessed {tostring(x)}, the server {tostring(y)}`) end
		end
		if p.jumpsLeft ~= a.jumpsLeft or p.airDodgeUsed ~= a.airDodgeUsed then
			fail(`{name}, frame {frame}: jumps {p.jumpsLeft}/{a.jumpsLeft}, air dodge used {tostring(p.airDodgeUsed)}/{tostring(a.airDodgeUsed)} (guessed/server)`)
		end
	end
	return kinds
end
local function tap(o: any): (number) -> any
	return function(frame: number): any
		if frame ~= 1 then return nil end
		local f = Input.emptyFrame()
		for k, val in o do (f :: any)[k] = val end
		f.anyPress = true
		return f
	end
end
local function airborne(a: any, v: any, dx: number, dy: number)
	for _, f in { a, v } do f.onGround, f.platform, f.vy = false, nil, 0; f:setState("air") end
	a.y = a.y + 6; v.x, v.y = a.x + dx, a.y + dy
	a.jumpsLeft, a.airDodgeUsed = 0, true
end
local cases = {
	{ "a clean hit", "Sword", function() end, tap({ light = true }), nil, "hit" },
	{ "into a shield", "Sword", function(_, _, v) v:setState("shield") end, tap({ light = true }),
		function(): any local f = Input.emptyFrame(); f.guardHeld = true; return f end, "block" },
	-- (facing away, so their heavy, once it comes out, does not land on us)
	{ "into a heavy's startup", "Sword", function(_, _, v) v.facing = 1; v:startMove(v.char.moves.SigSide) end, tap({ light = true }), nil, "armor" },
	{ "an up-aerial with no jumps left (it gives one back)", "Sword", function(_, a, v) airborne(a, v, 0.4, 3.4) end, tap({ light = true, y = 1 }), nil, "hit" },
	{ "a forward-aerial (it bounces its attacker)", "Sword", function(_, a, v) airborne(a, v, 3.4, 0.6) end, tap({ light = true, x = 1 }), nil, "hit" },
	{ "a multi-hit heavy, frozen between its hits", "Daggers", function(_, _, v) v.x = 1.8 end, tap({ heavy = true }), nil, "hit,hit,hit" },
	-- the bullwhip's tip twice: the first marks, the second cracks - its freeze from the cracked damage
	{ "a whip tip that marks, then one that cracks", "Whip", function(_, _, v) v.x = 6.2 end,
		function(frame: number): any
			if frame ~= 1 and frame ~= 34 then return nil end
			local f = Input.emptyFrame(); f.light = true; f.anyPress = true
			return f
		end, nil, "hit,crackmark,hit,crack" },
}
local shown = {}
for _, c in cases do
	local kinds = lockstep(c[1], c[2], c[3], c[4], c[5])
	local got = table.concat(kinds, ",")
	if string.sub(got, 1, #c[6]) ~= c[6] then fail(`{c[1]}: the server landed {got}, the case wants {c[6]} - it is not testing what it says`) end
	table.insert(shown, `{c[1]}: {got}`)
end
print(`PASS every kind of instant hit is the server's on every frame - {table.concat(shown, "; ")}`)

-- ---- the whip's mark from the wire ----
-- A mark the server took away (the whip user was hit, it faded, a crack spent it) is the server's
-- to say: the predictor takes the snapshot's mark over its own, or it would predict a crack the
-- server will not give.
do
	local char = Loadout.build("Classic", "Whip")
	local pred = Predictor.new(char, 0, Stage.new(data, SEED))
	local truth = Loader.load("Fighter").new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
	truth.mech.mark, truth.mech.expires = -1, 0
	pred.fighter.mech.mark, pred.fighter.mech.expires = 1, 400
	pred:reconcile(Snapshot.decode(Snapshot.encode(truth)), 0, nil, nil)
	if pred.fighter.mech.mark ~= -1 then fail(`the predictor kept its own mark ({pred.fighter.mech.mark}) over the server's none`) end
	truth.mech.mark, truth.mech.expires = 1, 333
	pred:reconcile(Snapshot.decode(Snapshot.encode(truth)), 0, nil, nil)
	if pred.fighter.mech.mark ~= 1 or pred.fighter.mech.expires ~= 333 then fail("the predictor did not take the server's mark") end
end
print("PASS the whip's mark is the server's: the predictor takes the snapshot's over its own")

-- ---- HitConfirm ----
do
	local c = HitConfirm.new()
	c:drawn({ type = "hit", victim = 1, predicted = true }, 0)
	if c:confirms({ type = "hit", attacker = 2, victim = 1 }, 0, 0.1) then fail("someone else's hit taken for ours") end
	if not c:confirms({ type = "hit", attacker = 0, victim = 1 }, 0, 0.2) then fail("the server's copy of a predicted hit is drawn again") end
	if c:confirms({ type = "hit", attacker = 0, victim = 1 }, 0, 0.25) then fail("one prediction confirmed two server hits") end
	c:drawn({ type = "block", victim = 1, predicted = true }, 1)
	if c:confirms({ type = "hit", attacker = 0, victim = 1 }, 0, 1.1) then fail("a predicted block confirmed a hit") end
	if not c:confirms({ type = "block", victim = 1 }, 0, 1.2) then fail("a predicted block not confirmed by the server's block") end
	c:drawn({ type = "hit", victim = 1, predicted = true }, 2)
	if c:confirms({ type = "hit", attacker = 0, victim = 1 }, 0, 2 + HitConfirm.WINDOW + 0.01) then fail("a prediction long past its window confirmed a hit") end
	if c:confirms({ type = "hit", attacker = 0, victim = 1 }, nil, 3) then fail("a spectator's client confirmed a hit") end
	c:drawn({ type = "crack", victim = 1, predicted = true }, 4)
	if c:confirms({ type = "crack", attacker = 2, victim = 1 }, 0, 4.1) then fail("someone else's crack taken for ours") end
	if not c:confirms({ type = "crack", attacker = 0, victim = 1 }, 0, 4.2) then fail("the server's copy of a predicted crack is drawn again") end
end
print("PASS HitConfirm: the server's copy of our predicted hit is not drawn twice; other hits, other kinds and stale predictions are")
