--!nonstrict
-- Bot behaviour, ported 1:1 from web/src/engine/ai.js.
--
-- Difficulty here is PERCEPTION, not behaviour. Cranking aggression produced a stock ratio of 1.09
-- between the best bot and the worst; handicapping how many frames STALE a bot's view of its
-- opponent is produces a real ladder, because a bot that sees late is worse at everything at once.
-- `sight` is that delay in frames, `slip` is the chance of fumbling an input outright, and `chains`
-- is how many committed multi-frame sequences the level knows.
--
-- Three Luau traps in this file, none visible on a read:
--   * `st.ultCd-- <= 0` tests the OLD value and then decrements; `--ch.t <= 0` decrements first.
--     Getting either backwards shifts a stance's firing rate by a frame.
--   * `buf.shift()` is `table.remove(buf, 1)`, and the ring is walked from the END, so the index
--     arithmetic in `seen` is off by one from the JavaScript's.
--   * `enemies[0]` is `enemies[1]`, and the order of that list decides which target a bot picks
--     when two are equidistant.

local Input = require(script.Parent.Input)
local Config = require(script.Parent.Config)
local COMBO = Config.COMBO

local Ai = {}

-- combo / timing / cancel / breakOut: how well each level strings, times, cancels and breaks out
-- (Config.COMBO) - see ai.js. arm / throws: how eagerly a bot on fists goes for a weapon drop, and
-- how often it throws the one in hand (Config.DROPS).
Ai.LEVELS = {
	dummy = nil,
	easy = { sight = 26, reaction = 22, commit = 20, aggression = 0.35, defence = 0.15, kill = 0.5, dodge = 0.1, ult = 0.2, edge = 0.0, slip = 0.30, chains = 0, combo = 0.2, timing = 0.1, cancel = 0, breakOut = 0, arm = 0.5, throws = 0.05, catch = 0.04 },
	normal = { sight = 15, reaction = 12, commit = 16, aggression = 0.55, defence = 0.35, kill = 0.7, dodge = 0.25, ult = 0.5, edge = 0.15, slip = 0.15, chains = 1, combo = 0.5, timing = 0.35, cancel = 0.15, breakOut = 0.1, arm = 0.7, throws = 0.12, catch = 0.12 },
	hard = { sight = 9, reaction = 6, commit = 13, aggression = 0.7, defence = 0.55, kill = 0.9, dodge = 0.4, ult = 0.75, edge = 0.4, slip = 0.07, chains = 2, combo = 0.75, timing = 0.7, cancel = 0.5, breakOut = 0.35, arm = 0.85, throws = 0.2, catch = 0.25 },
	elite = { sight = 5, reaction = 3, commit = 11, aggression = 0.85, defence = 0.7, kill = 1.0, dodge = 0.6, ult = 0.9, edge = 0.65, slip = 0.03, chains = 3, combo = 0.9, timing = 0.85, cancel = 0.75, breakOut = 0.6, arm = 0.95, throws = 0.3, catch = 0.4 },
	impossible = { sight = 2, reaction = 1, commit = 9, aggression = 0.95, defence = 0.85, kill = 1.0, dodge = 0.8, ult = 1.0, edge = 0.8, slip = 0.01, chains = 3, combo = 1.0, timing = 0.95, cancel = 0.9, breakOut = 0.85, arm = 1.0, throws = 0.35, catch = 0.55 },
	just_dont = { sight = 0, reaction = 1, commit = 8, aggression = 1.0, defence = 1.0, kill = 1.0, dodge = 1.0, ult = 1.0, edge = 0.95, slip = 0.0, chains = 3, combo = 1.0, timing = 1.0, cancel = 1.0, breakOut = 1.0, arm = 1.0, throws = 0.4, catch = 0.65 },
}
Ai.LEVELS.imposible = Ai.LEVELS.impossible     -- the misspelling is in the JavaScript too

local LEVELS = Ai.LEVELS

local function sign(v: number): number
	return if v < 0 then -1 else 1
end

-- The generator every decision draws from, swapped in at the top of computeBotInput. Module-scoped
-- for the same reason as the JavaScript: threading it through 33 call sites buys nothing, and the
-- simulation is single-threaded with no yields, so whoever is mid-call owns it.
local RNG: () -> number = math.random
local function chance(p: number): boolean
	return RNG() < p
end

-- ---------------------------------------------------------------- perception ----
-- One ring of snapshots per match, written once per frame by whichever bot runs first and read by
-- all of them. A bot reads its OPPONENT through this ring at its own `sight` delay; its own state
-- is always current, because you always know where you are standing.
local SIGHT_MAX = 30

local function history(match: any): any
	local H = match._aiHist
	if not H then
		H = { frame = -1, ring = {} }
		match._aiHist = H
	end
	if H.frame == match.frame then
		return H
	end
	H.frame = match.frame
	for _, v in match.fighters do
		local buf = H.ring[v]
		if not buf then
			buf = {}
			H.ring[v] = buf
		end
		table.insert(buf, { x = v.x, y = v.y, cy = v.cy, vx = v.vx, vy = v.vy, state = v.state,
			percent = v.percent, onGround = v.onGround, alive = v.alive, facing = v.facing,
			tumbling = v.tumbling })
		if #buf > SIGHT_MAX then
			table.remove(buf, 1)
		end
	end
	return H
end

-- What this bot currently believes about a fighter. Returns a SNAPSHOT, never the fighter itself,
-- so nothing downstream can accidentally read a live value and quietly cheat.
local function seen(H: any, v: any, sight: number): any
	local buf = H.ring[v]
	if not buf or #buf == 0 then
		return v
	end
	-- JS: buf[max(0, buf.length - 1 - sight)] on a 0-indexed array.
	return buf[math.max(0, #buf - 1 - sight) + 1]
end

-- ---------------------------------------------------------------- execution ----
-- Seeing late is only half of being worse. A weak player also fumbles: drops the button, holds the
-- wrong way, lets go of shield early. Ground game only - a bot that fumbles its recovery dies to
-- nothing at all, and a level that mostly kills itself is not an easier opponent, it is an absent
-- one.
local function fumble(frame: any, L: any, st: any): any
	if L.slip == 0 or st.noFumble or not chance(L.slip) then
		return frame
	end
	local r = RNG()
	if r < 0.45 then
		frame.light = false; frame.heavy = false; frame.grab = false; frame.anyPress = false
	elseif r < 0.8 then
		frame.x = -frame.x
	else
		frame.jump = false; frame.dodge = false; frame.guardHeld = false; frame.guard = false
	end
	return frame
end

-- ---------------------------------------------------------------- chains ----
-- A chain is a short sequence of inputs the bot commits to and does NOT re-decide part way
-- through, the way a human executes a known option rather than reconsidering every frame.
Ai.CHAINS = {
	-- Close the gap at a run, then hit. The most basic thing a human does and the bot never did.
	dashIn = { need = 1, steps = {
		{ n = 10, f = function(fr, c) fr.x = c.dir end },
		{ n = 2, f = function(fr, c) fr.x = c.dir; fr.light = true end },
	} },
	-- Shield the thing coming at you, then take the free grab.
	shieldGrab = { need = 2, steps = {
		{ n = 11, f = function(fr) fr.guardHeld = true end },
		{ n = 2, f = function(fr, c) fr.x = c.dir; fr.grab = true end },
	} },
	-- Walk backwards out of range, wait for them to over-commit, then punish.
	bait = { need = 3, steps = {
		{ n = 12, f = function(fr, c) fr.x = -c.dir end },
		{ n = 6, f = function(fr, c) fr.x = c.dir end },
		{ n = 3, f = function(fr, c) fr.x = c.dir; fr.heavy = true end },
	} },
}
local CHAINS = Ai.CHAINS

local function startChain(st: any, name: string)
	st.chain = { name = name, i = 1, t = CHAINS[name].steps[1].n }
end

-- Run the current chain for one frame. Returns false when it is finished or was interrupted.
local function runChain(frame: any, st: any, c: any): boolean
	local ch = st.chain
	if not ch then
		return false
	end
	local def = CHAINS[ch.name]
	local step = def.steps[ch.i]
	if not step then
		st.chain = nil
		return false
	end
	step.f(frame, c)
	ch.t -= 1                                   -- JS `--ch.t <= 0`: decrement, then test
	if ch.t <= 0 then
		ch.i += 1
		ch.t = if def.steps[ch.i] then def.steps[ch.i].n else 0
		if not def.steps[ch.i] then
			st.chain = nil
		end
	end
	return true
end

-- Should this bot spend its ultimate right now? Each ultimate wants a different situation, and the
-- numbers come from the moves' own data rather than taste.
local function wantsUltimate(f: any, tv: any, L: any, adx: number, dy: number, enemies: { any }): boolean
	if not f.ultReady then
		return false
	end
	local U = f.char.moves.Ultimate
	if not U then
		return false
	end
	if U.grounded and not f.onGround then
		return false
	end
	-- A sloppy bot just throws it out; a good one waits for the shape the move wants.
	if not chance(L.ult) then
		return chance(0.02)
	end
	if U.kind == "slam" then
		local reach = if U.crater then U.crater.step * (U.crater.count - 1) else 8
		return adx < reach * 0.7 and math.abs(dy) < 6 and tv.onGround
	elseif U.kind == "vortex" then
		return adx < (if U.vortex then U.vortex.range else 17) * 0.8 and math.abs(dy) < 8
	elseif U.kind == "sniper" then
		-- No range condition: the round steers. What it wants is not being hit mid-stance.
		return f.onGround and not (tv.state == "attack" and adx < 8)
	elseif U.kind == "starfall" then
		return #enemies > 0 and (#enemies > 1 or tv.percent > 40)
	end
	return adx < 10
end

-- ---------------------------------------------------------------- items ----
-- Each item has one verb, so this is a table rather than a policy: the AI does not need to be
-- clever about a Blast Keg, it needs to throw it at somebody and not be standing next to it.
local function itemAction(f: any, match: any, L: any, st: any, tv: any, dir: number, adx: number, frame: any): boolean
	if not match.itemsOn or not f.onGround then
		return false
	end
	local C = match.combat
	local held = f.item

	if not held then
		-- The FETCH TIMEOUT is not decoration. Without it two bots that each wanted an item on a
		-- ledge they could not reach would walk at it until the clock ran out, which turned a
		-- one-stock four-bot match into a five-minute stalemate about one run in ten.
		if st.fetchCd > 0 then
			st.fetchCd -= 1
			return false
		end
		if adx < 5 then
			return false                        -- somebody is on top of you; fight first
		end
		local greed = 0.25 + L.aggression * 0.75
		local best, bd = nil, 1e9
		for _, it in C.items do
			if not it.held then
				local d, dy2 = math.abs(it.x - f.x), math.abs(it.y - f.y)
				if d <= 20 and dy2 <= 4 and d < bd then
					bd = d
					best = it
				end
			end
		end
		if not best or not chance(greed) then
			st.fetch = 0
			return false
		end
		if bd < 2.6 then
			frame.pickup = true; frame.anyPress = true; st.chain = nil; st.fetch = 0
			return true
		end
		-- Give up on an item you are not getting closer to.
		st.fetch = (st.fetch or 0) + 1
		if st.fetch > 100 then
			st.fetch = 0
			st.fetchCd = 180
			return false
		end
		frame.x = sign(best.x - f.x)
		st.chain = nil
		return true
	end
	st.fetch = 0

	local def = held.def
	local faces = sign(tv.x - f.x) == f.facing or adx < 3

	if def.kind == "hold" then
		if held.hp <= 0 then
			frame.heavy = true; frame.anyPress = true
			return true
		end
		if adx < 4 and chance(L.aggression * 0.5) then
			frame.light = true; frame.anyPress = true
			return true
		end
		return false                            -- otherwise just carry it: the guard is passive
	end
	if def.kind == "place" then
		-- Put it down where it is worth something: near the edge you keep getting knocked off.
		local main = match.stage.main
		local nearEdge = math.min(math.abs(f.x - main.x1), math.abs(f.x - main.x2)) < 12
		if nearEdge or chance(0.02) then
			frame.light = true; frame.anyPress = true
			return true
		end
		frame.x = sign((if f.x < main.cx then main.x1 else main.x2) - f.x)
		return true
	end
	if def.kind == "shoot" then
		if adx < 30 and math.abs(tv.y - f.y) < 4 and faces then
			frame.light = true; frame.anyPress = true
			return true
		end
		frame.x = dir
		return true
	end
	if def.kind == "throw" then
		-- A keg wants an arc, so it is thrown from further out than the Lodestone, which flies flat.
		local lo, hi = if def.explode then 6 else 3, if def.explode then 22 else 26
		if adx > lo and adx < hi and math.abs(tv.y - f.y) < 6 and faces then
			frame.light = true; frame.anyPress = true
			return true
		end
		frame.x = dir
		return true
	end
	return false
end

-- ------------------------------------------------------------------------ weapon drops ----
-- On fists, a weapon is the plan: go to the nearest drop and take it, stepping up via a platform
-- in between for one too high to jump to, dropping through a soft platform for one below. Armed,
-- throw now and then. The same draws in the same order as ai.js weaponAction, and none at all
-- unless drops are on.
local function weaponAction(f: any, match: any, L: any, st: any, tv: any, adx: number, dy: number, frame: any): boolean
	if not match.dropsOn or not f.kit then
		return false
	end
	local DROPS = Config.DROPS
	if f.armed < 0 then
		if st.dropCd > 0 then st.dropCd -= 1; return false end
		if not st.wantArm then
			if not chance(L.arm) then st.dropCd = 30; return false end
			st.wantArm = true
		end
		local best, bd = nil, 1e9
		for _, d in match.combat.drops do
			local ddx, ddy = math.abs(d.x - f.x), d.y - f.y
			if not (ddx > 40 or ddy < -20 or ddy > 30) then
				local cost = ddx + math.abs(ddy) * 1.2
				if cost < bd then bd = cost; best = d end
			end
		end
		if not best then st.dropFetch = 0; return false end
		if adx < 4 and bd > 6 then return false end
		local ddx, ddy = math.abs(best.x - f.x), best.y - f.y
		if ddx < DROPS.reach[1] * 0.8 and math.abs(ddy) < DROPS.reach[2] then
			frame.pickup = true; frame.anyPress = true; st.chain = nil; st.dropFetch = 0; st.wantArm = false
			return true
		end
		st.dropFetch = (st.dropFetch or 0) + 1
		if st.dropFetch > 150 then st.dropFetch = 0; st.dropCd = 120; st.wantArm = false; return false end
		local gx, gy = best.x, best.y
		if ddy > 12 then
			local step, sd = nil, 1e9
			for _, p in match.stage.platforms do
				if not (p.top < f.y + 4 or p.top > best.y - 2) then
					local sx = math.max(p.x1 + 1, math.min(p.x2 - 1, f.x))
					if math.abs(sx - f.x) < sd then sd = math.abs(sx - f.x); step = { x = sx, y = p.top } end
				end
			end
			if step then gx = step.x; gy = step.y end
		end
		local gdx, gdy = math.abs(gx - f.x), gy - f.y
		frame.x = if gdx > 0.6 then sign(gx - f.x) else 0
		if gdy > 2.5 and gdx < 8 and st.jumpCd <= 0 then
			if f.onGround then frame.jump = true; st.jumpCd = 18
			elseif f.jumpsLeft > 0 and f.vy < 2 and f.y < gy then frame.jump = true; st.jumpCd = 14 end
		end
		if ddy < -2.5 and ddx < 4 and f.onGround and f.platform and f.platform.soft then
			frame.y = -1; frame.downTap = true
		end
		st.chain = nil
		return true
	end
	st.wantArm = false
	if st.throwCd > 0 then st.throwCd -= 1; return false end
	st.throwCd = 30
	local T = f.char.weapon.thrown or DROPS.thrown
	if sign(tv.x - f.x) ~= f.facing or adx < 7 or adx > 26 or math.abs(dy) > 5 then
		return false
	end
	local kills = T.growth >= 5 and tv.percent >= 150
	if not chance(L.throws * (if kills then 2 else 1)) then
		return false
	end
	frame.pickup = true; frame.anyPress = true; st.chain = nil
	return true
end

local decide

local computeBotInput: (any, any) -> any
-- A Chakram bot (Roblox only) never asks for a throw it cannot make: every tactic below can press
-- heavy - a kill attempt, an edge-guard, a recovery - and with no ring in hand that is a refused
-- throw and a wasted frame. Empty-handed, heavy becomes light (the normals need no ring). (No bot
-- tactic presses a neutral heavy, so the Halo - which needs both rings - is never asked for with
-- one: tests/chakram holds a bot at one ring for 20 s to keep that true.) Every other weapon's
-- input passes through untouched.
function Ai.computeBotInput(f: any, match: any): any
	local frame = computeBotInput(f, match)
	if frame and frame.heavy and f.mech and f.mech.id == "Return" and (f.mech.rings or 0) <= 0 then
		frame.heavy, frame.heavyHeld, frame.light = false, false, true
	end
	-- Rocket Boots (Roblox only), the same rule: a heavy on the ground is a signature, and below the
	-- dearest signature's fuel it becomes a kick. Up + heavy in the air is the recovery, which an empty
	-- tank still does (weakly), so that is left alone.
	if frame and frame.heavy and f.mech and f.mech.id == "ThrustFuel" and (f.onGround or (frame.y or 0) <= 0.5) then
		local dearest = 0
		for _, m in f.char.moves do if m.fuelCost and m.fuelCost > dearest then dearest = m.fuelCost end end
		if (f.mech.fuel or 0) < dearest then
			frame.heavy, frame.heavyHeld, frame.light = false, false, true
		end
	end
	return frame
end
function computeBotInput(f: any, match: any): any
	-- Draw from the match's own generator, so a bot match replays from its seed.
	RNG = (if match.stage then match.stage.rng else nil) or math.random
	if f.botLevel == "dummy" then
		return Input.emptyFrame()               -- dummy stands still
	end
	local L = LEVELS[f.botLevel] or LEVELS.normal
	if not f.ai then
		f.ai = { timer = 0, plan = "approach", hold = 0, jumpCd = 0, lastState = "", ultCd = 0,
			defCd = 0, punish = 0, chain = nil, noFumble = false, fetch = 0, fetchCd = 0,
			comboMove = -1, combo = nil, airFollow = 0, breakTry = -9999,
			dropCd = 0, dropFetch = 0, wantArm = false, throwCd = 0 }
	end
	f.ai.noFumble = false
	return fumble(decide(f, match, L, f.ai), L, f.ai)
end

-- ---------------------------------------------------------------------------- combos ----
-- Once per landed move, what follows it, and whether it is pressed on the strike (timed) or late.
-- The same draws in the same order as ai.js planCombo.
local DIRS = { "neutral", "side", "up", "down" }
local function dirOf(map: any): string?
	if not map then return nil end
	if type(map) == "string" then return "neutral" end
	for _, k in DIRS do
		if map[k] then return k end
	end
	return nil
end
local function planCombo(f: any, L: any, tv: any): any
	local m = f.move
	if not chance(L.combo) then return nil end
	local timed = chance(L.timing)
	if m.finishers and m.finishers.neutral and timed and f.perfectStreak == f.chainDepth then
		return { press = "light", dir = "neutral", timed = true }
	end
	if m.chainsHeavy and tv.percent >= 100 then return { press = "heavy", dir = dirOf(m.chainsHeavy), timed = timed } end
	local light = dirOf(m.chains) or (if m.chainsTo then "neutral" else nil)
	if light then return { press = "light", dir = light, timed = timed } end
	if m.cancels and chance(L.cancel) then
		local jump = m.cancels.jump and (tv.y > f.y + 1 or not m.cancels.dodge)
		return { press = if jump then "jump" else "dodge", dir = "side", cancel = true }
	end
	if m.chainsHeavy then return { press = "heavy", dir = dirOf(m.chainsHeavy), timed = timed } end
	return nil
end
local function comboInput(frame: any, f: any, plan: any, dir: number)
	local m = f.move
	local late = f.mf >= f.startupEff + m.active + COMBO.perfectLate
	if plan.cancel then
		if f.mf <= f.startupEff + m.active then return end
	elseif not (plan.timed or late) then
		return
	end
	frame[plan.press] = true
	frame.anyPress = true
	if plan.press == "heavy" then frame.heavyHeld = true end
	if plan.press == "jump" then frame.jumpHeld = true end
	if plan.dir == "side" then frame.x = dir
	elseif plan.dir == "up" then frame.y = 1
	elseif plan.dir == "down" then frame.y = -1 end
end

function decide(f: any, match: any, L: any, st: any): any
	local frame = Input.emptyFrame()
	-- Bound once because nothing inside a single decision changes the fighter's state. Typed `any`
	-- on purpose: as a `string` the analyser follows the recovery guard below, narrows it to the
	-- literal "tether", and then rejects every later comparison as impossible.
	local state: any = f.state
	st.timer -= 1
	st.jumpCd -= 1
	local stage, main = match.stage, match.stage.main
	local enemies = {}
	for _, v in match.fighters do
		if v ~= f and v.alive and v.team ~= f.team then
			table.insert(enemies, v)
		end
	end
	if #enemies == 0 then
		return frame
	end
	-- Everything this bot knows about anyone else is read through here, `sight` frames late.
	local H = history(match)
	local target, tv = enemies[1], seen(H, enemies[1], L.sight)
	for _, e in enemies do
		local ev = seen(H, e, L.sight)
		if math.abs(ev.x - f.x) < math.abs(tv.x - f.x) then
			target = e
			tv = ev
		end
	end
	local dx, dy = tv.x - f.x, tv.y - f.y
	local adx, dir = math.abs(dx), sign(dx)
	local offStage = f.x < main.x1 - 0.5 or f.x > main.x2 + 0.5
	local toStage = if f.x < main.cx then 1 else -1

	if state == "respawn" then
		st.noFumble = true
		if st.timer <= 0 then
			frame.jump = true
			st.timer = 20
		end
		return frame
	end
	if state == "ko" or state == "grabbed" or state == "frozen" or state == "stunned" then
		if state == "frozen" or state == "grabbed" then
			frame.light = chance(0.5)
		end
		return frame
	end

	-- ---- recovery ----
	-- The state clause is hoisted into a boolean rather than written inline. Inline, the analyser
	-- works out that the only way this guard can fail by that clause is state == "tether" - the
	-- ledge case having already returned above - narrows `state` to that literal, and then rejects
	-- every comparison after this block as impossible.
	local canRecover = state ~= "ledge" and state ~= "tether"
	if not f.onGround and (offStage or f.y < -6) and canRecover then
		-- Never fumbled, and no chain survives being knocked off: getting home is not a difficulty
		-- lever.
		st.noFumble = true
		st.chain = nil
		frame.x = toStage
		local nearLedge = stage:nearestLedge(f.x, f.cy)
		if state == "hitstun" then
			frame.x = toStage; frame.y = 1
			return frame
		end
		if state == "helpless" then
			if nearLedge.dist < 8 then
				frame.guard = chance(0.5)
			end
			return frame
		end
		local belowLedge = f.y < -2
		if f.jumpsLeft > 0 and f.vy < 0 and (belowLedge or nearLedge.dist > 14) and st.jumpCd <= 0 then
			frame.jump = true; st.jumpCd = 14
			return frame
		end
		if f.jumpsLeft == 0 and not f.recoveryUsed and f.vy < 2 and (belowLedge or nearLedge.dist > 6) then
			frame.heavy = true; frame.y = 1
			return frame
		end
		if nearLedge.dist < 6 and f.vy < 0 then
			frame.guard = true
		end
		if f.tumbling and chance(0.3) then
			frame.dodge = true
		end
		return frame
	end
	-- ---- ledge ----
	if state == "ledge" then
		if st.timer <= 0 then
			local r = RNG()
			local enemyNear = adx < 10
			if r < 0.3 and not enemyNear then
				frame.x = -f.ledge.side
			elseif r < 0.55 then
				frame.dodge = true
			elseif r < 0.8 and enemyNear then
				frame.light = true
			else
				frame.jump = true
			end
			st.timer = 30
		end
		return frame
	end
	-- ---- hitstun / tumble / knockdown ----
	if state == "hitstun" then
		st.noFumble = true
		st.chain = nil
		frame.x = -sign(if f.vx ~= 0 then f.vx else 1) * 0.6
		frame.y = if f.vy > 0 then -0.5 else 0.5
		-- the combo break: one try per freeze that allows it
		if f.hitlag > 0 and f.comboHits >= COMBO.breakFrom and f.breakable and f.breakCooldown == 0
			and not f.breakLocked and st.breakTry ~= f.lastHitFrame then
			st.breakTry = f.lastHitFrame
			if chance(L.breakOut) then
				frame.dodge = true
				frame.anyPress = true
			end
		end
		return frame
	end
	-- after a jump cancel: an aerial at them while the chase window is open
	if st.airFollow > 0 then
		st.airFollow -= 1
		if not f.onGround and state == "air" then
			frame.light = true
			frame.anyPress = true
			frame.x = dir
			frame.y = if dy > 2 then 1 else 0
			return frame
		end
	end
	if f.tumbling and not f.onGround then
		if f.y < 4 and f.vy < 0 then
			frame.guard = true
		elseif chance(0.2) then
			frame.jump = true
		end
		return frame
	end
	if state == "knockdown" then
		return frame
	end
	-- Deadeye is a stance: it holds three rounds and spends one per press. A bot that pressed once
	-- fired one bullet and threw the other two away, so the stance keeps being fed here.
	if f.ultActive ~= 0 and f.move and f.move.kind == "sniper" and f.ultShots > 0 then
		frame.ult = st.ultCd <= 0               -- JS `st.ultCd-- <= 0`: test, then decrement
		st.ultCd -= 1
		if frame.ult then
			st.ultCd = (f.move.sniper.reload or 16) + 2
			frame.anyPress = true
		end
		return frame
	end
	if state == "attack" or state == "holding" or state == "grab" then
		if state == "holding" then
			local r = RNG()
			frame.x = if r < 0.4 then f.facing elseif r < 0.6 then -f.facing else 0
			frame.y = if r > 0.8 then 1 else 0
		end
		if f.move and f.move.charge and state == "attack" then
			frame.heavyHeld = f.charge < (f.move.charge.maxHold * 0.6)
		end
		if state == "attack" and f.move and f.moveLanded then
			if st.comboMove ~= f.moveSerial then
				st.comboMove = f.moveSerial
				st.combo = planCombo(f, L, tv)
			end
			if st.combo then
				comboInput(frame, f, st.combo, dir)
				if st.combo.press == "jump" and frame.jump then st.airFollow = COMBO.chaseFrames end
			end
		end
		if state == "attack" and f.move and not f.onGround then
			frame.x = dir * 0.6
		end
		return frame
	end

	-- ---- threat reaction ----
	local threat = tv.state == "attack" and adx < 8 and math.abs(dy) < 6
	local incomingProjectile = false
	for _, p in match.combat.projectiles do
		if p.owner ~= f and math.abs(p.x - f.x) < 12
			and sign(p.vx) == -sign(if f.x - p.x ~= 0 then f.x - p.x else 1)
			and math.abs(p.y - f.cy) < 4 then
			incomingProjectile = true
			break
		end
	end
	-- Defence has to convert into offence, or it is just time spent not playing. At defence 1.0 the
	-- top difficulty spent 11% of the match in spot-dodge and attacked LESS than Normal, which is
	-- how the hardest bot lost to the easiest on stocks.
	st.defCd -= 1
	if (threat or incomingProjectile) and st.timer <= 0 and st.defCd <= 0 and chance(L.defence) then
		st.plan = if chance(L.dodge * 0.45) then "dodge" else "shield"
		st.timer = L.reaction + 10
		st.hold = 16
		st.defCd = 30
		st.punish = L.aggression                -- what to do the moment the defence is over
		-- Shield-grab is chosen HERE, not in the tactic block below, because a defensive plan is
		-- set from this branch and returns before that block ever runs.
		if st.plan == "shield" and CHAINS.shieldGrab.need <= L.chains and f.onGround and adx < 7
			and chance(0.45) then
			startChain(st, "shieldGrab")
		end
	end

	-- the save (Config.TEAM.catch): a tumbling teammate in reach, caught - drawn only when possible
	if match.combat:allyToCatch(f) and chance(L.catch) then
		frame.grab = true; frame.anyPress = true
		return frame
	end

	if wantsUltimate(f, tv, L, adx, dy, enemies) then
		frame.ult = true; frame.anyPress = true
		st.ultCd = 0; st.plan = "approach"
		return frame
	end

	-- ---- items ----
	if itemAction(f, match, L, st, tv, dir, adx, frame) then
		return frame
	end
	if weaponAction(f, match, L, st, tv, adx, dy, frame) then
		return frame
	end

	-- A chain in progress owns the next few frames outright - that is the whole point of it.
	if st.chain and runChain(frame, st, { dir = dir, tv = tv, f = f }) then
		return frame
	end

	if st.timer <= 0 then
		-- COMMIT, not reaction. Re-rolling the plan on the reaction clock meant the best bots
		-- re-decided every frame and thrashed; measured, maximum difficulty lost to `easy`.
		st.timer = L.commit
		local arche = f.char.archetype
		local inRange = adx < 6 and math.abs(dy) < 5
		local r = RNG()
		-- The archetype strings come from the WEAPON, and there are exactly four.
		if inRange then
			st.plan = if r < L.aggression + 0.25 then "attack" elseif r < 0.85 then "shield" else "retreat"
		elseif arche == "Zoner" then
			st.plan = if adx > 10 and adx < 34 and math.abs(dy) < 5 and r < 0.6 then "zone" else "approach"
		elseif arche == "Heavy zoner" then
			st.plan = if adx > 12 and math.abs(dy) < 8 and r < 0.55 then "zone" else "approach"
		elseif arche == "Reach / combo" then
			st.plan = if adx > 6 and adx < 14 and r < 0.4 then "lasso" else "approach"
		-- The Chakram (Roblox only, not one of the web's four): throw from inside the ring's 22-stud
		-- range, and only with a ring in hand - an empty-handed throw is refused and wastes the plan.
		elseif arche == "Returning zoner" then
			st.plan = if adx > 8 and adx < 22 and math.abs(dy) < 5 and r < 0.55 and (f.mech.rings or 0) > 0 then "zone" else "approach"
		else
			st.plan = if r < 0.15 then "retreat" else "approach"
		end
		st.hold = if st.plan == "attack" then 6 else 14

		-- Tactic chosen; now pick the chain that executes it, if this level knows one.
		if L.chains > 0 and f.onGround and f.ultActive == 0 then
			if st.plan == "approach" and adx > 7 and adx < 22 and math.abs(dy) < 4
				and chance(L.aggression * 0.5) then
				startChain(st, "dashIn")
			elseif st.plan == "shield" and CHAINS.shieldGrab.need <= L.chains and adx < 7
				and chance(0.5) then
				startChain(st, "shieldGrab")
			elseif st.plan == "attack" and CHAINS.bait.need <= L.chains and adx < 9
				and tv.state ~= "attack" and chance(0.22) then
				startChain(st, "bait")
			end
			if st.chain then
				st.timer = 24
				runChain(frame, st, { dir = dir, tv = tv, f = f })
				return frame
			end
		end
	end

	local plan = st.plan
	if plan == "shield" then
		frame.guardHeld = true
		-- drop the shield the instant the threat is over and take the punish
		st.hold -= 1
		if st.hold <= 0 or tv.state ~= "attack" then
			st.timer = 0
			st.plan = if chance(st.punish or 0) then "attack" else "approach"
		end
		if adx < 3 and chance(0.1) then
			frame.light = true
		end
		return frame
	end
	if plan == "dodge" then
		frame.dodge = true
		st.plan = if chance(st.punish or 0) then "attack" else "approach"
		st.timer = 0
		return frame
	end
	if plan == "retreat" then
		frame.x = -dir
		if f.onGround and chance(0.03) then
			frame.jump = true
		end
		st.hold -= 1
		if st.hold <= 0 then
			st.timer = 0
		end
		return frame
	end
	if plan == "zone" then
		frame.x = dir; frame.heavy = true; frame.heavyHeld = true; st.plan = "approach"
		return frame
	end
	if plan == "setup" then
		frame.y = -1; frame.heavy = true; st.plan = "approach"
		return frame
	end
	if plan == "lasso" then
		frame.x = dir; frame.heavy = true; st.plan = "approach"
		return frame
	end
	if plan == "attack" then
		if not f.onGround then
			if dy < -3 then frame.y = -1 else frame.x = dir end
			frame.light = true; st.plan = "approach"
			return frame
		end
		local wantsKill = tv.percent > 90 and chance(L.kill)
		if f.char.archetype == "Heavy zoner" and tv.state == "attack" and chance(0.4) then
			frame.y = -1; frame.heavy = true; st.plan = "approach"
			return frame
		end
		if f.char.archetype == "Reach / combo" and chance(0.35) then
			frame.grab = true; st.plan = "approach"
			return frame
		end
		if wantsKill then
			frame.x = dir; frame.heavy = true
		elseif tv.state == "shield" and chance(0.6) then
			frame.grab = true
		elseif dy > 4 and chance(0.6) then
			frame.jump = true; st.hold = 8
		else
			local r = RNG()
			frame.x = dir
			if r < 0.45 then
				frame.light = true
			elseif r < 0.75 then
				frame.x = 0; frame.light = true
			else
				frame.y = -1; frame.x = 0; frame.light = true
			end
		end
		st.plan = "approach"
		return frame
	end
	-- ---- edgeguard ----
	-- Most of a platform fighter's stocks are taken off the stage, and nothing here used to go
	-- after somebody who was already out there.
	local targetOff = tv.x < main.x1 - 1 or tv.x > main.x2 + 1
	-- Only chase what can be chased AND returned from.
	local canComeBack = f.jumpsLeft > 0 and math.abs(tv.x - main.cx) < math.abs(main.x2 - main.cx) + 16
	if targetOff and canComeBack and f.onGround and not offStage and chance(L.edge) then
		local outward = sign(tv.x - main.cx)
		-- Ranged weapons cover the ledge from safety; melee has to commit to the chase.
		if f.char.archetype == "Zoner" or f.char.archetype == "Heavy zoner" then
			frame.x = outward; frame.heavy = true; st.plan = "approach"
			return frame
		end
		if math.abs(f.x - main.cx) > math.abs(main.x2 - main.cx) - 6 and tv.y < f.y - 1 then
			-- standing on the lip and they are below it: a down-air is the kill, but only commit
			-- when there is a real chance of getting back
			if f.jumpsLeft > 1 and chance(0.5) then
				frame.jump = true; st.plan = "chase"; st.hold = 10
				return frame
			end
			frame.y = -1; frame.light = true
			return frame
		end
		frame.x = outward
		return frame
	end
	if plan == "chase" then
		frame.x = sign(tv.x - f.x)
		if math.abs(dy) < 4 and adx < 5 then
			frame.y = -1; frame.light = true; st.plan = "approach"
			return frame
		end
		st.hold -= 1
		if st.hold <= 0 or f.y < tv.y - 4 then
			st.plan = "approach"
		end
		return frame
	end

	-- approach
	frame.x = dir
	if adx > 20 and f.onGround and chance(0.06) then
		frame.dodge = true
	end
	if dy > 6 and f.onGround and st.jumpCd <= 0 and chance(0.15) then
		frame.jump = true; st.jumpCd = 20
	end
	if not f.onGround and dy > 3 and f.jumpsLeft > 0 and st.jumpCd <= 0 and chance(0.1) then
		frame.jump = true; st.jumpCd = 20
	end
	if not f.onGround and adx < 5 and dy < -2 and chance(0.3) then
		frame.y = -1; frame.light = true
	end
	if not f.onGround and adx < 5 and math.abs(dy) < 3 and chance(0.4) then
		frame.light = true
	end
	if f.onGround and adx < 3 and chance(0.02) then
		frame.taunt = target.stocksLeft ~= nil and target:stocksLeft() == 0
	end
	return frame
end

return Ai
