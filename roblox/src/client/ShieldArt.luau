--!strict
-- The shield, drawn as a pixel-art shell in the fighter's colour - ROBLOX ONLY. Shield.luau (held
-- to web/src/render2d/shield.js) is still the rule for what the shield IS: its centre, how big it
-- is at a given strength (it shrinks as it weakens), that it flickers below 30%, and where it was
-- last struck. This draws those same facts in the realms' style: a lattice shell with a bright
-- rim, cracks that spread as it weakens, and a flare and a ripple where a hit lands.
local PixelGrid = require(script.Parent.PixelGrid)
local FxArt = require(script.Parent.FxArt)
local Effects = require(script.Parent.Effects)

local ShieldArt = {}

local put, hash = PixelGrid.put, PixelGrid.hash

-- The shell's radius at strength `hp` for a fighter `h` tall: Shield.luau's own rule.
function ShieldArt.radius(h: number, hp: number): number
	return h * 0.62 * (0.55 + hp * 0.45)
end

-- The fighter's colour: their team's in a team match (`teams`, index -> Color3), otherwise their
-- player colour.
function ShieldArt.colourOf(index: number?, teams: any?): string
	local team = teams and index ~= nil and teams[index]
	if team then
		return string.format("#%02X%02X%02X", math.floor(team.R * 255 + 0.5), math.floor(team.G * 255 + 0.5), math.floor(team.B * 255 + 0.5))
	end
	return Effects.PLAYER_TINT[((index or 0) % #Effects.PLAYER_TINT) + 1]
end

-- The shell at crack level `level` (0 whole .. 3 nearly gone), in tones of `ramp`: a soft fill, a
-- triangle lattice, a two-pixel rim lit on the upper left, and cracks running in from the rim.
local cache: { [string]: any } = {}
local function shell(colour: string, level: number): any
	local key = `shield|{colour}|{level}`
	if cache[key] then return cache[key] end
	local S = 32
	local g = PixelGrid.new(S, S)
	local c = S / 2
	local R = c - 1
	for y = 0, S - 1 do
		for x = 0, S - 1 do
			local dx, dy = x + 0.5 - c, y + 0.5 - c
			local d = math.sqrt(dx * dx + dy * dy)
			if d <= R then
				local lit = dx + dy < -R * 0.5
				if d > R - 1 then put(g, x, y, if lit then 5 else 4)
				elseif d > R - 2 then put(g, x, y, 3)
				elseif ((x + y) % 6 == 0 or (x - y + 60) % 6 == 0) and d < R - 3 then put(g, x, y, 13)
				elseif (x + y) % 2 == 0 then put(g, x, y, 12) end
			end
		end
	end
	-- a glint on the upper left
	put(g, math.floor(c - R * 0.55), math.floor(c - R * 0.55), 5)
	put(g, math.floor(c - R * 0.55) + 1, math.floor(c - R * 0.55), 5)
	-- cracks: zig-zags from the rim inward, more and longer as it weakens
	for k = 1, level * 2 do
		local a = hash(k, level, 7) * math.pi * 2
		local x, y = c + math.cos(a) * (R - 1), c + math.sin(a) * (R - 1)
		for step = 1, 4 + level * 2 do
			put(g, x, y, 5)
			a += (hash(k, step, 9) - 0.5) * 1.2
			x -= math.cos(a) * 1.2
			y -= math.sin(a) * 1.2
		end
	end
	local A = FxArt.ramp(colour)
	local rects: { any } = {}
	for i, r in PixelGrid.merge(g) do
		local t = r[5]
		local row: { any } = { r[1], r[2], r[3], r[4] }
		if t <= 5 then row[5], row[6] = A[t], 1 else row[5], row[6] = A[t - 10], 0.3 end
		rects[i] = row
	end
	local art = { key = key, rects = rects, cols = S, rows = S, ax = c, ay = c, ppu = FxArt.PPU }
	cache[key] = art
	return art
end
ShieldArt.shell = shell

-- Draws the shield of a fighter centred at (x, cy), `h` tall, at strength `hp` (0..1), on sim frame
-- `frame`; `hit` is Effects.shieldHit's { k, x, y } for a recent impact, or nil. Draws nothing at
-- no strength, exactly as Shield.shapes does.
function ShieldArt.draw(c: any, x: number, cy: number, h: number, hp: number, frame: number, hit: any?, colour: string)
	if not (hp > 0) then return end
	local R = ShieldArt.radius(h, hp)
	local level = if hp > 0.75 then 0 elseif hp > 0.5 then 1 elseif hp > 0.3 then 2 else 3
	-- Shield.shapes' flicker below 30%: on for three frames, dimmed for three
	local flicker = if hp < 0.3 then (0.55 + 0.45 * (math.floor(frame / 3) % 2)) else 1
	local art = shell(colour, level)
	local flash = if hit then hit.k else 0
	FxArt.draw(c, art, x, cy, FxArt.sized(art, R * 2), 0, math.min(1, (0.8 + 0.2 * flash) * flicker))
	if hit and flash > 0 then
		-- where it was struck: a flare on the rim and a ripple spreading from it
		local a = math.atan2(hit.y - cy, hit.x - x)
		local px, py = x + math.cos(a) * R, cy + math.sin(a) * R
		local pop = FxArt.get("pop", math.floor((1 - flash) * 4.99), colour, nil, 2)
		FxArt.draw(c, pop, px, py, FxArt.sized(pop, 1.4 + flash * 1.6), 0, 1)
		local ring = FxArt.get("ring", math.floor((1 - flash) * 5.99), colour)
		FxArt.draw(c, ring, px, py, FxArt.sized(ring, R * 1.2), 0, flash)
	end
end

return ShieldArt
