--!strict
-- Roblox presentation only. The snapshot and authored channels are read-only. A gait is driven
-- by distance, not a lifetime timer multiplied by speed: changing speed cannot teleport a foot
-- through its cycle, and a support foot cancels the body's travel exactly, in either facing.
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Movement = {}
local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- The stride, in proportion to the fighter. The legs keep one length (`leg`) through the whole
-- cycle; the step is set so a planted foot never needs more than that: it lands `contact` ahead
-- of the hip and leaves after `support` of the step. The rest of each step is flight.
function Movement.gait(char: any): any
	local h = char.height
	return { step = h * 0.58, contact = h * 0.14, support = 0.62, leg = h * 0.34 }
end

-- The body's height through the stride, studs above its rest. A walk rides highest over the
-- passing leg and dips just after each contact; a run is the other way about, lowest in the middle
-- of the planted step (the "down", the knee taking the weight) and highest in the flight between
-- steps. A pure function of distance travelled, like the feet, so it lands on the footfalls.
function Movement.bob(s: any, char: any): number
	local h = char.height
	local speed = math.clamp(math.abs(s.vx) / char.runSpeed, 0, 1)
	local run = smooth((speed - 0.42) / 0.28)
	local q = ((s.strideDistance or s.x * s.facing) / Movement.gait(char).step) % 1
	local k = h / 5.2
	local passing = Movement.gait(char).support / 2
	local walk = k * (-0.03 + 0.035 * math.cos(2 * math.pi * (q - passing)))
	local runs = k * (-0.10 - 0.125 * math.cos(2 * math.pi * (q - 0.28)))
	return walk + (runs - walk) * run
end

function Movement.For(ch: any, s: any, char: any): any
	local h, r, state, sf = char.height, char.radius, s.state, s.stateFrame
	local m: any = { feet = nil, hipX = 0, hipY = 0, chest = 0, head = 0, back = nil, armLength = 0.30 }
	local function feet(x1: number, y1: number, b1: number, x2: number, y2: number, b2: number)
		m.feet = { { x = x1, y = y1, bend = b1 }, { x = x2, y = y2, bend = b2 } }
	end
	local function plant(width: number, bend: number)
		feet(-r * width, -ch.bob, bend, r * width, -ch.bob, bend)
	end
	if state == "run" and s.onGround then
		local speed = math.clamp(math.abs(s.vx) / char.runSpeed, 0, 1)
		local run = smooth((speed - 0.42) / 0.28)
		local G = Movement.gait(char)
		local S, x0, DP = G.step, G.contact, G.support
		-- The plaza supplies distance along its two-dimensional floor (and to its fixed mirror).
		-- Match snapshots keep using their actual horizontal travel, preserving planted feet.
		local base = (s.strideDistance or s.x * s.facing) / S
		local q = base % 1
		m.phase = base * math.pi + math.pi / 2 -- chest/hips counter the same stride as the feet
		m.bob = Movement.bob(s, char)
		m.feet = {}
		local heelMax = h * 0.04
		for i = 1, 2 do
			-- c runs 0-2 per foot: planted from its contact (0) to toe-off (DP), then the swing.
			local c = (base + (i - 1)) % 2
			local x, y, support
			if c < DP then
				-- Planted: it moves back exactly as far as the body travels forward, so it never
				-- slides. Late in the step the heel peels up, as the toe pushes off.
				x = x0 - S * c
				y = heelMax * smooth((c - DP * 0.6) / (DP * 0.4))
				support = y == 0
			else
				-- The swing, classic style: the heel kicks up behind first (the lift peaks before
				-- the passing point), then the leg unfolds and reaches forward into the next contact.
				local u = (c - DP) / (2 - DP)
				local xl = x0 - S * DP
				x = xl + (x0 - xl) * smooth(u)
				y = heelMax * (1 - u) ^ 2 + h * (0.087 + 0.07 * run) * math.sin(math.pi * u ^ 0.8)
				support = false
			end
			local lane = math.clamp(x / x0, -1, 1)
			m.feet[i] = { x = x, y = y - m.bob, len = G.leg, rootX = lane * r * 0.30, lane = lane, support = support }
		end
		m.back = -math.clamp(m.feet[1].x / x0, -1.4, 1.4) * (0.32 + 0.38 * run) - 0.12
		m.head = -0.025 * math.sin(q * 2 * math.pi - 0.8)
	elseif state == "jumpsquat" then
		local load = smooth(sf / Config.MOVE.jumpsquat)
		plant(0.65, 12 + 50 * load)
		m.hipY, m.chest, m.back = -h * 0.018 * load, -0.12 * load, -0.65 * load
	elseif state == "landing" then
		local load = math.clamp((1 - ch.sy) / 0.20, 0, 1)
		plant(0.65, 10 + 65 * load)
		m.chest, m.back, m.head = -0.10 * load, 0.4 * load, 0.08 * load
	elseif state == "air" and not s.tumbling then
		local rise = smooth(s.vy / 24)
		local fall = smooth(-s.vy / 24)
		local hang = 1 - math.max(rise, fall)
		if s.fastFalling then
			feet(-r * 0.32, -h * 0.035, 8, r * 0.32, -h * 0.035, 8)
			m.chest, m.head, m.back = -0.13, -0.08, -0.35
		else
			feet(-h * (0.10 + 0.08 * rise), h * (0.025 * rise + 0.12 * hang), 18 + 34 * hang,
				h * 0.10, h * (0.21 * rise + 0.16 * hang), 14 + 78 * rise + 46 * hang)
			m.chest = -0.06 * rise + 0.08 * fall
			m.back = -0.45 * rise + 1.4 * hang + 0.7 * fall
		end
	elseif state == "shield" or state == "shielddrop" then
		local brace = if state == "shield" then smooth(sf / 4) else 1 - smooth(sf / Config.SHIELD.dropFrames)
		plant(0.72, 12 + 36 * brace)
		m.hipY, m.chest, m.back = -h * 0.018 * brace, -0.16 * brace, 1.25 * brace
	elseif state == "spotdodge" then
		local duck = math.sin(math.pi * math.clamp(sf / 10, 0, 1))
		plant(0.65, 10 + 68 * duck)
		m.hipX, m.hipY, m.chest, m.back = -r * 0.18 * duck, -h * 0.045 * duck, 0.10 * duck, 0.9 * duck
	elseif state == "hitstun" and not s.tumbling then
		local fresh = 1 - smooth(sf / 12)
		local away = (if s.vx < 0 then -1 else 1) * s.facing
		m.hipX, m.head = h * 0.075 * away * fresh, 0.12 * away * fresh
	elseif state == "knockdown" then
		local getup = smooth((sf - Config.KNOCKDOWN.frames * 0.5) / (Config.KNOCKDOWN.frames * 0.5))
		m.rigRotZ = ch.rigRotZ * (1 - getup)
		m.yOff = math.max(ch.yOff * (1 - getup), math.abs(math.sin(m.rigRotZ)) * r * 0.65)
		plant(0.65, 60 * (1 - getup) + 10)
		-- The get-up turns the body around its feet, not the feet through the floor. Carry the
		-- fixed ground targets back through that cosmetic root rotation before solving the knees.
		local angle = m.rigRotZ * s.facing
		for _, foot in m.feet do
			local x = foot.x
			foot.x = math.cos(angle) * x - math.sin(angle) * m.yOff
			foot.y = -math.sin(angle) * x - math.cos(angle) * m.yOff - ch.bob
		end
		m.back, m.chest, m.head = 1.3 * (1 - getup), -0.12 * math.sin(getup * math.pi), 0.08 * (1 - getup)
	elseif state == "ledge" then
		feet(-r * 0.55, h * 0.03, 24, r * 0.65, h * 0.17, 76)
		m.chest, m.head = -0.06, -0.05
	elseif state == "ledgeaction" and s.ledgeAction ~= "roll" then
		-- Fighter._stepLedgeAction reaches the platform on 8 (attack) / 10 (getup), before
		-- either action ends. Plant at that arrival, so the attack's active frames read grounded.
		local onStage = if s.ledgeAction == "attack" then 8 else 10
		-- Hold the climbing knee during the initial pull, then plant by platform arrival.
		local climb = smooth((sf - 3) / (onStage - 3))
		feet(-r * 0.55, h * 0.02 * (1 - climb), 18, r * 0.65, h * 0.22 * (1 - climb), 16 + 68 * (1 - climb))
		m.chest, m.head = -0.1 * (1 - climb), -0.05 * (1 - climb)
	end
	-- These rotations remain the authored rotations: only the limbs collect around their centre.
	local rolling = state == "airdodge" or (state == "tech" and s.techRoll ~= 0)
		or (state == "ledgeaction" and s.ledgeAction == "roll")
	local tumble = s.tumbling and (state == "air" or state == "hitstun")
	if rolling or tumble then
		local tuck = if tumble then smooth(math.max(0, s.frameCount - s.lastHitFrame) / 6) else 1
		feet(-r * 0.22, h * 0.20 * tuck, 12 + 86 * tuck, r * 0.5, h * 0.24 * tuck, 12 + 90 * tuck)
		m.back, m.armLength, m.chest, m.head = 0.75 * tuck, 0.30 - 0.10 * tuck, -0.13 * tuck, -0.12 * tuck
	elseif state == "tech" then
		local load = 1 - smooth(sf / Config.TECH.inPlace.frames)
		plant(0.65, 10 + 62 * load)
		m.back = 0.6 * load
	end
	return m
end

return Movement
