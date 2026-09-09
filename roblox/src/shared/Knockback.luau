--!strict
-- The whole damage model, ported 1:1 from web/src/engine/knockback.js.
--
-- Port this exactly or knockback feels different immediately. tests/parity.luau checks every
-- function here against a fixture generated from the JavaScript and fails on any drift.

local Config = require(script.Parent.Config)

local Knockback = {}

-- launch = (base + growth * damage * (percent/100 + 0.4)) * (100 / weight)
function Knockback.launchSpeed(base: number, growth: number, damage: number, percentAfterHit: number, weight: number): number
	local scaled = base + growth * damage * (percentAfterHit / 100 + 0.4)
	return scaled * (100 / weight)
end

function Knockback.hitstun(launch: number): number
	return math.min(6 + math.floor(launch * 0.4), Config.HITSTUN_CAP)
end

function Knockback.blockstun(damage: number): number
	return 4 + math.floor(damage * 0.8)
end

function Knockback.hitlag(damage: number, heavy: boolean?): number
	local bonus = if heavy then 2 else 0
	return math.min(3 + math.floor(damage * 0.35) + bonus, Config.HITLAG_CAP)
end

export type DI = { x: number, y: number }
export type Velocity = { vx: number, vy: number }

-- facing is +1/-1. di is the victim's stick in -1..1, or nil.
-- DI is read when hitlag ENDS, not when the hit lands, so holding a direction through the freeze is
-- what bends the angle. Whatever ports Fighter must preserve that ordering.
function Knockback.velocity(launch: number, angleDeg: number, facing: number, di: DI?): Velocity
	local angle = angleDeg
	if di then
		local rad = angleDeg * math.pi / 180
		-- the component of the stick perpendicular to the launch direction bends the angle
		local perpendicular = -di.x * facing * math.sin(rad) + di.y * math.cos(rad)
		angle += math.clamp(perpendicular, -1, 1) * Config.DI_MAX
	end
	local rad = angle * math.pi / 180
	return { vx = math.cos(rad) * launch * facing, vy = math.sin(rad) * launch }
end

-- On-block advantage for a move hitting on its first active frame (for the frame data screen).
function Knockback.onBlock(move: { damage: number, active: number, recovery: number }): number
	return Knockback.blockstun(move.damage) - ((move.active - 1) + move.recovery)
end

return Knockback
