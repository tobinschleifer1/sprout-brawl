--!strict
-- The shield as an energy shell, ported from web/src/render2d/shield.js - read that file.
-- Pure and deterministic; tests/shield-parity.luau holds it to the JavaScript.
local Shield = {}
Shield.RIM, Shield.VEINS, Shield.CRACKLE = 28, 7, 5

function Shield.hash(i: number, j: number): number
	return (((i * 7919 + j * 104729 + 12345) % 2147483647) * 16807 % 2147483647) / 2147483647
end

local function shape(...: any): { any }
	return { ... }
end

function Shield.shapes(x: number, cy: number, h: number, hp: number, frame: number, hit: any?): { any }
	local out = {}
	if not (hp > 0) then
		return out
	end
	local hash = Shield.hash
	local R = h * 0.62 * (0.55 + hp * 0.45)
	local flash = if hit then hit.k else 0
	local low = hp < 0.3
	local flicker = if low then 0.55 + 0.45 * (math.floor(frame / 3) % 2) else 1
	local tick = math.floor(frame / Shield.CRACKLE)
	local function P(a: number, r: number): (number, number)
		return x + math.cos(a) * r, cy + math.sin(a) * r
	end

	table.insert(out, shape("e", x, cy, R * 1.12, R * 1.12, "#3FB8FF", 0.12 * flicker))
	table.insert(out, shape("e", x, cy, R, R, "#4FC8FF", (0.28 + 0.2 * flash) * flicker))
	table.insert(out, shape("e", x, cy, R * 0.72, R * 0.72, "#BFF4FF", 0.08 * flicker))

	for v = 0, Shield.VEINS - 1 do
		local a = hash(v, tick) * math.pi * 2
		local px, py = P(a, R * 0.96)
		for leg = 1, 3 do
			a += (hash(v * 10 + leg, tick) - 0.5) * 0.9
			local qx, qy = P(a, R * (0.96 - leg * 0.2))
			table.insert(out, shape("l", px, py, qx, qy, 0.14, "#E6FDFF", 0.7 * flicker))
			px, py = qx, qy
		end
	end

	local gap = (1 - hp) * 0.55
	local hitA = if hit then math.atan2(hit.y - cy, hit.x - x) else 0
	for i = 0, Shield.RIM - 1 do
		if hash(i + 100, math.floor(frame / 6)) >= gap then
			local a0, a1 = (i / Shield.RIM) * math.pi * 2, ((i + 1) / Shield.RIM) * math.pi * 2
			local near = 0
			if hit then
				local mid = (a0 + a1) / 2
				local d = math.abs(math.atan2(math.sin(mid - hitA), math.cos(mid - hitA)))
				near = math.max(0, 1 - d / 0.7) * flash
			end
			local x0, y0 = P(a0, R * 1.06)
			local x1, y1 = P(a1, R * 1.06)
			table.insert(out, shape("l", x0, y0, x1, y1, 0.6, "#5FD0FF", 0.35 * flicker))
			local u0, v0 = P(a0, R)
			local u1, v1 = P(a1, R)
			table.insert(out, shape("l", u0, v0, u1, v1, 0.3 + 0.55 * near, if near > 0.3 then "#FFFFFF" else "#DFFBFF",
				math.min(1, 0.9 * flicker + near)))
		end
	end

	if hit and flash > 0 then
		local rr = R * (1 + (1 - flash) * 0.3)
		for s = -4, 3 do
			local a0 = hitA + s * 0.2
			local a1 = a0 + 0.2
			local x0, y0 = P(a0, rr)
			local x1, y1 = P(a1, rr)
			table.insert(out, shape("l", x0, y0, x1, y1, 0.26, "#FFFFFF", 0.8 * flash * (1 - math.abs(s + 0.5) / 4)))
		end
	end
	return out
end

return Shield
