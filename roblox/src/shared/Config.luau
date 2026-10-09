--!strict
-- Global simulation constants. Frames are at 60 Hz. Distances in studs (1 stud ~= 0.28 m).
-- Ported 1:1 from web/src/config.js. Every number here must stay identical to that file; the
-- cross-check in tests/parity.luau fails the build if they drift.

local Config = {}

Config.FRAME = 1 / 60
Config.GRAVITY = 150        -- studs/s^2, combat gravity
Config.LAUNCH_DRAG = 0.985  -- horizontal drag per frame while in hitstun/tumble
Config.TUMBLE_THRESHOLD = 45
Config.HITSTUN_CAP = 60
Config.HITLAG_CAP = 12
Config.DI_MAX = 12          -- degrees of directional influence

-- The launch curve, and the hitstun curve, deliberately separate. `slope` is how far a hit sends
-- you; `stunSlope` is how long you cannot act. They were one number in both builds, and flattening
-- the launch to stop players dying at 97% also shortened hitstun at high percent, which deleted the
-- guaranteed kill confirm of seven of the twelve weapons. Anything here that launches must compute
-- BOTH and carry both into the hit it applies.
Config.KNOCKBACK = { slope = 1 / 120, stunSlope = 1 / 100, floor = 0.4 }

Config.MOVE = {
	groundAccelFrames = 6,
	groundStopFrames = 6,
	airAccelFrames = 10,
	airDrag = 0.995,
	shortHopMul = 0.6,
	shortHopWindow = 4,
	fastFallMul = 1.6,
	jumpsquat = 3,
	turnFrames = 0,
}

Config.SHIELD = { max = 50, regenPerSec = 8, drainPerSec = 1.5, damageMul = 1.2, breakStun = 90, resetHp = 25, perfectFrames = 4, dropFrames = 4 }

Config.LEDGE = {
	maxGrabs = 3,
	invinc = { 30, 15, 0 },
	hangMax = 180,
	grabReach = 3.0,
	grabDepth = 6.0,
	hangOffsetX = 1.4,
	hangOffsetY = -3.2,
	options = {
		getup = { frames = 24, inv = { 1, 12 }, distance = 2.5 },
		roll = { frames = 36, inv = { 4, 20 }, distance = 8 },
		attack = { frames = 30, inv = { 1, 8 }, distance = 2.5, damage = 7, base = 16, growth = 1.6, angle = 45,
			hitbox = { frames = { 12, 16 }, offset = { 2.6, 2.4 }, size = { 4.5, 2.6 } } },
	},
}

Config.DASH = { frames = 18, speedMul = 1.6, cancelLightFrom = 6, cancelShieldFrom = 10 }
Config.SPOT_DODGE = { frames = 24, inv = { 3, 14 } }
Config.AIR_DODGE = { frames = 28, inv = { 3, 13 }, distance = 6 }

Config.GROUND_POUND = {
	hang = 8, speed = 70, landingLag = 22,
	dive = { damage = 10, base = 20, growth = 2.6, angle = 275, hitbox = { offset = { 0, 0.6 }, size = { 2.6, 3.2 } } },
	shock = { damage = 5, base = 12, growth = 1.0, angle = 70, radius = 4, frames = 3 },
}

Config.GRAB = {
	startup = 7, active = 3, whiffRecovery = 26, holdFrames = 14,
	hitbox = { offset = { 2.2, 2.5 }, size = { 3.4, 3.2 } },
	throws = {
		forward = { damage = 7, base = 20, growth = 2.4, angle = 40 },
		back = { damage = 7, base = 20, growth = 2.4, angle = 40, behind = true },
		up = { damage = 6, base = 18, growth = 2.2, angle = 88 },
		down = { damage = 8, base = 14, growth = 1.8, angle = 30 },
	},
}

Config.TECH = { window = 8, inPlace = { frames = 30, inv = { 1, 14 } }, roll = { frames = 30, inv = { 1, 14 }, distance = 8 } }
Config.KNOCKDOWN = { frames = 26, getupInv = { 1, 10 } }
Config.TAUNT_FRAMES = 90
Config.RESPAWN = { delay = 2.0, invinc = 120, height = 14 }
-- spawnEvery was 25 seconds and despawnAfter 20, which in a three-minute match is about seven
-- items, most of which timed out untouched. 14 seconds keeps one in play most of the time without
-- the match becoming about the floor.
Config.ITEMS = { spawnEvery = 14, despawnAfter = 22, knockOutDamage = 12 }
-- Weapon drops: see web/src/config.js DROPS, which says what each of these is.
Config.DROPS = {
	firstAt = 2, spawnEvery = 5, despawnAfter = 14, reach = { 3, 3.5 },
	throwMove = { startup = 4, active = 1, recovery = 12 },
	thrown = { speed = 46, vy = 6, gravity = 40, lifetime = 50, damage = 7, base = 15, growth = 1.4, angle = 42, size = { 2.4, 1.2 } },
}
-- How many drops may lie about at once, by fighters in the match.
function Config.dropsOnStage(fighters: number): number
	return math.min(4, 1 + fighters // 2)
end
Config.SUDDEN_DEATH = { percent = 300, shrinkEvery = 10, shrinkFactor = 0.8 }
Config.INPUT_BUFFER = 6

-- Combos that reward timing: see web/src/config.js COMBO and docs/briefs/combo-system-plan.md.
-- A follow-up pressed during the previous move's strike (first active frame to `perfectLate` after
-- its last), with no press of that button in the wind-up, is a timed link. Damage scales down from
-- the `scaleFrom`th hit of a combo (knockback does not); from the `breakFrom`th the victim can break
-- out with a Dodge during that hit's freeze. A timed link into an aerial, or the first aerial after a
-- cancel, chases the fighter just hit (see Fighter._chase).
-- The kill hit (readability): a hit whose launch, left alone, carries its victim past a side or the
-- top blast line. Marks the hit event (`kill`) and changes nothing else. See config.js beside
-- KILL_HIT for the measurements behind `drift`, and why there is no extra freeze.
Config.KILL_HIT = { drift = 10 }

-- Staling (depth): a move you keep landing does less - the last `memory` landed, `step` off per
-- repeat among them, down to `floor`. Throws and the ultimate never stale. config.js says why.
-- Bounces (depth): launched into a wall or ceiling faster than `speed`, rebound at `restitution`
-- of it, still launched; a tech on contact saves them. config.js says more.
Config.BOUNCE = { speed = 30, restitution = 0.6 }

-- Team play (phase 3): assists - anyone besides the KO'er who hit the victim within
-- `assistWindow` frames - are credited and get `assistMeter` ultimate charge. config.js says more.
Config.TEAM = { assistWindow = 480, assistMeter = 3 }

Config.STALE = { memory = 8, step = 0.05, floor = 0.6 }
function Config.staleMul(landed: { string }, id: string): number
	local n = 0
	for _, m in landed do
		if m == id then n += 1 end
	end
	return math.max(Config.STALE.floor, 1 - Config.STALE.step * n)
end

Config.COMBO = {
	perfectLate = 4, perfectStartupCut = 2, perfectMinStartup = 2, perfectDamage = 1, perfectCharge = 1.25,
	scaleFrom = 3, scaleStep = 0.08, scaleFloor = 0.5,
	breakFrom = 4, breakFrames = 16, breakInv = 20, breakPush = 30, breakCooldown = 360,
	chaseFrames = 24, chaseSpeed = 48,
}
-- The share of a hit's damage that lands as the `hits`th hit of a combo.
function Config.comboScale(hits: number): number
	local C = Config.COMBO
	if hits < C.scaleFrom then return 1 end
	return math.max(C.scaleFloor, 1 - C.scaleStep * (hits - C.scaleFrom + 1))
end

-- Ultimates. Charge by landing hits; spend the whole meter in one activation. The meter is wiped
-- when you lose a stock, so an ultimate is a reward for a run of pressure, not a consolation prize
-- for dying. invincibleFrames is 22, not 30, because the activation freeze does not tick timers:
-- 30 would have covered Colossus's entire active window, making the biggest commitment in the game
-- untradeable. 22 runs out before the blade does.
Config.ULTIMATE = { hitsRequired = 20, freezeFrames = 26, invincibleFrames = 22 }

function Config.WEIGHT_CLASS(w: number): string
	if w <= 90 then return "Light" elseif w <= 105 then return "Mid" else return "Heavy" end
end

return Config
