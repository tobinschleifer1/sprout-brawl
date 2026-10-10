--!strict
-- Danger (readability): a fighter close to being KO'd smokes. Ported from
-- web/src/render2d/danger.js, which says how "close" is measured; held to it by
-- tests/danger-parity.luau. Pure and deterministic on the match frame.
local Shared = game:GetService("ReplicatedStorage").Shared
local Knockback = require(Shared.Knockback)

local Danger = {}
-- REF is tuned to the percent real KOs happen at (danger.js says how it was measured).
Danger.DANGER = { ref = { damage = 15, base = 30, growth = 8.5, angle = 45 }, lead = 20, span = 60, puffs = 6, rise = 3.4 }

-- a shape row; `any` because strict mode would type a literal mixing strings and numbers as strings
local function shape(...: any): any
	return { ... }
end

local cache: { [string]: number } = {}
function Danger.percent(weight: number, blast: any): number
	local key = `{weight}|{blast.left}|{blast.right}|{blast.top}`
	local hit = cache[key]
	if hit then return hit end
	local R = Danger.DANGER.ref
	local found = 999
	for p = 0, 400 do
		local after = p + R.damage
		local v = Knockback.velocity(Knockback.launchSpeed(R.base, R.growth, R.damage, after, weight), R.angle, 1, nil)
		if Knockback.carriesOut(0, 0, v.vx, v.vy, Knockback.hitstun(Knockback.stunSpeed(R.base, R.growth, R.damage, after, weight)), blast) then
			found = p
			break
		end
	end
	cache[key] = found
	return found
end

function Danger.level(percent: number, at: number): number
	local k = (percent - (at - Danger.DANGER.lead)) / Danger.DANGER.span
	return if k < 0 then 0 elseif k > 1 then 1 else k
end

function Danger.shapes(x: number, y: number, h: number, k: number, frame: number): { any }
	local out: { any } = {}
	if k <= 0 then return out end
	local D = Danger.DANGER
	local n = 1 + math.floor((D.puffs - 1) * k + 0.5)
	for i = 0, n - 1 do
		local phase = (frame * 0.018 * (1 + k) + i / n) % 1
		local px = x + math.sin(phase * 6 + i * 2.1) * 0.45
		local py = y + h * 0.95 + phase * D.rise
		local s = 0.7 + 0.8 * phase
		table.insert(out, shape("r", px - s / 2, py - s / 2, s, s, "#9C9790", (1 - phase) * (0.35 + 0.45 * k)))
		if k > 0.66 and i % 2 == 0 then
			table.insert(out, shape("r", px - 0.13, py + 0.1, 0.26, 0.26, "#FF7A3A", (1 - phase) * 0.9))
		end
	end
	return out
end

-- The bullwhip's mark (danger.js markShapes): a gold crack-sigil over the head of the fighter its
-- tip marked, blinking through its last second. `left` is frames until it fades.
Danger.MARK = { lift = 1.0, blinkFrom = 60 }
function Danger.markShapes(x: number, y: number, h: number, left: number, frame: number): { any }
	local out: { any } = {}
	if not (left > 0) then return out end
	local M = Danger.MARK
	local a = if left < M.blinkFrom and math.floor(frame / 4) % 2 == 1 then 0.35 else 1
	local cx, cy = x, y + h + M.lift
	local s = 0.45 + 0.06 * math.sin(frame * 0.3)
	for _, layer in { { colour = "#120E16", pad = 0.1 }, { colour = "#FFD25A", pad = 0 } } do
		local colour, pad = layer.colour, layer.pad
		table.insert(out, shape("r", cx - 0.11 - pad, cy - s - pad, 0.22 + 2 * pad, 2 * s + 2 * pad, colour, a))
		table.insert(out, shape("r", cx - s - pad, cy - 0.11 - pad, 2 * s + 2 * pad, 0.22 + 2 * pad, colour, a))
	end
	table.insert(out, shape("r", cx - 0.08, cy - 0.08, 0.16, 0.16, "#FFFFFF", a))
	return out
end

return Danger
