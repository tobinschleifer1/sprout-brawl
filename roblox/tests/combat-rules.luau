--!nocheck
-- The fight's rules as the combat review (docs/reviews/combat-round1-review.md) measured them:
--   1. a block freezes the defender as long as the attacker (both builds: it froze only the
--      attacker, so every move was 3-12 frames worse on shield than the game says);
--   2. against a wall there are no true combos (Roblox only, RobloxRules.WALL_STUN): a light
--      mashed into a 300% victim pinned against Saltflat's bunker strung 20-45 hits;
--   3. acting from the ledge ends the grab's invincibility (Roblox only): the first grab's getup
--      was invincible from start to end.
-- The Roblox-only two are also run with RobloxRules off, to show this test sees what they fix.
--
--     lune run tests/combat-rules
local Loader = require("./loader")
local Match, Loadout, Input = Loader.load("Match"), Loader.load("Loadout"), Loader.load("Input")
local Rules = Loader.load("RobloxRules")
local Stages = Loader.load("Data/Stages")
local saltflat
for _, s in Stages.LIST do if s.id == "Saltflat" then saltflat = s end end

local function match(stage: any, a: string, b: string): (any, any, any, any)
	local frames: { [string]: any } = {}
	local input = { get = function(_, src) return frames[src] or Input.emptyFrame() end }
	local m = Match.new({ mode = "StockFFA", stage = stage, seed = 1, items = false, stocks = 3, input = input,
		fighters = { { char = Loadout.build("Classic", a), source = "p0", team = 0 }, { char = Loadout.build("Noir", b), source = "p1", team = 1 } } })
	m.state = "fight"
	for _ = 1, 60 do m:step() end
	return m, m.fighters[1], m.fighters[2], frames
end

-- 1. A block freezes both.
do
	local m, a, v, frames = match(Stages.LIST[1], "Sword", "Sword")
	a.x, v.x, a.facing, v.facing = 0, 2.5, 1, -1
	for _, f in { a, v } do f.y, f.vx, f.vy, f.onGround, f.platform, f.invincible = 0, 0, 0, true, m.stage.main, 0 end
	a:setState("idle"); v:setState("idle")
	frames.p1 = (function() local f = Input.emptyFrame(); f.guard, f.guardHeld = true, true; return f end)()
	for _ = 1, 6 do m:step() end
	assert(v.state == "shield", `the defender is not shielding ({v.state})`)
	local press = Input.emptyFrame(); press.light, press.anyPress = true, true
	frames.p0 = press
	m:step(); frames.p0 = nil
	local blocked = false
	for _ = 1, 30 do
		m:step()
		if a.hitlag > 0 and v.blockstun > 0 then
			assert(v.hitlag == a.hitlag, `a block froze the attacker {a.hitlag} frames and the defender {v.hitlag}`)
			blocked = true
			break
		end
	end
	assert(blocked, "the jab was never blocked")
end

-- 2. No true combos against a wall.
local function wallCombo(): number
	local m, a, v, frames = match(saltflat, "Gauntlets", "Sword")
	local bunker
	for _, sp in m.stage.solids do if sp.x1 <= -19 and sp.x2 >= -13 and sp.top <= 5 then bunker = sp end end
	assert(bunker, "Saltflat's bunker is not where the review measured it")
	v.x, a.x = bunker.x2 + v.r, bunker.x2 + v.r + 2.6
	a.facing, v.facing = -1, 1
	for _, f in { a, v } do f.y, f.vx, f.vy, f.onGround, f.platform, f.invincible = 0, 0, 0, true, m.stage.main, 0 end
	a:setState("idle"); v:setState("idle")
	v.percent = 300
	local longest, chain, last, wasStunned = 0, 0, v.percent, false
	for i = 1, 600 do
		local press = Input.emptyFrame()
		if i % 2 == 0 then press.light, press.anyPress = true, true end
		frames.p0 = press
		m:step()
		if not v.alive or v.state == "ko" then break end
		if v.percent > last then
			chain = if wasStunned then chain + 1 else 1
			longest = math.max(longest, chain)
		end
		last = v.percent
		wasStunned = v.hitstun > 0 or v.state == "hitstun" or v.hitlag > 0
	end
	return longest
end
Rules.on = false
local locked = wallCombo()
Rules.on = true
local fixed = wallCombo()
assert(locked >= 10, `with the web's rules the wall strung only {locked} hits: this test no longer sees the lock`)
assert(fixed <= 4, `against a wall a mashed light still strings {fixed} true hits`)

-- 3. The ledge: acting ends the grab's invincibility.
local function getupInvincible(): number
	local m, a = match(Stages.LIST[1], "Sword", "Sword")
	local L = m.stage.ledges[1]
	a:grabLedge(L)
	assert(a.invincible >= 30, "the first grab gave no invincibility")
	a:_startLedgeAction("getup")
	return a.invincible
end
Rules.on = false
local webInv = getupInvincible()
Rules.on = true
local robloxInv = getupInvincible()
assert(webInv >= 30 and robloxInv == 0, `a getup kept {robloxInv} frames of the grab's invincibility (the web keeps {webInv})`)

print(`PASS combat rules: a block freezes both sides; against Saltflat's bunker a mashed light strings {fixed} true hits (the web's rules: {locked}); a getup drops the grab's {webInv} invincible frames`)
