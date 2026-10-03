--!strict
-- How a fighter looks when they have been hit hard - ROBLOX ONLY, drawn behind the fighters from
-- the states being drawn: speed lines streaming off anyone flying fast in hitstun, and a trail of
-- smoke puffs behind anyone launched hard enough to be in danger of a KO, so a big hit reads at a
-- glance from across the stage. The hit itself (the impact) is FxPlayer.hit.
local Canvas2D = require(script.Parent.Canvas2D)
local FxArt = require(script.Parent.FxArt)

local HitReact = {}

HitReact.LINES = 22          -- studs a second: faster than this, in hitstun, and speed lines show
HitReact.SMOKE = 40          -- and faster than this, a smoke trail

local WHITE = Color3.new(1, 1, 1)
local trails: { [number]: { any } } = {}

local function flying(s: any): boolean
	return s.alive and (s.state == "hitstun" or s.tumbling) and not s.onGround
end

-- Draws every fighter's reaction. `t` is wall clock.
function HitReact.draw(c: any, states: { any }, chars: { any }, t: number)
	local seen: { [number]: boolean } = {}
	for _, s in states do
		local char = chars[s.index + 1]
		if not char then continue end
		local vx, vy = s.vx or 0, s.vy or 0
		local speed = math.sqrt(vx * vx + vy * vy)
		local list = trails[s.index]
		if flying(s) and speed > HitReact.LINES then
			seen[s.index] = true
			local h = char.height
			local cx, cy = s.x, s.y + h * 0.5
			local ux, uy = -vx / speed, -vy / speed               -- behind them
			local k = math.clamp((speed - HitReact.LINES) / 40, 0, 1)
			-- speed lines: streaks behind the fighter, longer the faster they go
			for i = 0, 4 do
				local off = (i - 2) * h * 0.18
				local px, py = cx + -uy * off, cy + ux * off
				local len = (2 + k * 4) * (1 - math.abs(i - 2) * 0.18)
				local from = 1.2 + ((t * 9 + i * 0.37) % 1) * 1.2
				Canvas2D.line(c, px + ux * from, py + uy * from, px + ux * (from + len), py + uy * (from + len), 0.14, WHITE, 0.35 + 0.35 * k)
			end
			-- smoke: a puff every few frames where they have been, while they are flying fast
			list = list or {}
			trails[s.index] = list
			local last = list[#list]
			if speed > HitReact.SMOKE and (not last or t - last.t > 0.045) then
				table.insert(list, { x = cx, y = cy, t = t })
			end
		end
		if list then
			for i = #list, 1, -1 do
				if t - list[i].t > 0.6 then table.remove(list, i) end
			end
			for i, p in list do
				local age = (t - p.t) / 0.6
				local b = FxArt.get("burst", 4 + math.floor(age * 2.99), "smoke", nil, (i % 4) + 1)
				FxArt.draw(c, b, p.x, p.y, FxArt.sized(b, 1.4 + age * 2.2), 0, 0.85 * (1 - age))
			end
			if #list == 0 and not seen[s.index] then trails[s.index] = nil end
		end
	end
end

function HitReact.clear()
	table.clear(trails)
end

return HitReact
