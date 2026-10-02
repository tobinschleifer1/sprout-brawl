--!strict
-- The natural disasters, drawn in pixel art to fit the realm they strike - ROBLOX ONLY, like the
-- realms themselves. The simulation (Disasters.luau, held to web/src/engine/disasters.js) and its
-- view are untouched: every position and every moment drawn here comes from that view.
--
-- TWO RULES the art keeps, because they are the information a player acts on:
--   * Warnings are where the shared shape list (DisasterShapes, held to the web) puts them, when it
--     puts them, and in its cool cyan; damage is its hot orange. tests/disaster-art.luau holds the
--     markers to DisasterShapes' own.
--   * A disaster's SHAPE is the same on every map - a funnel is a funnel - while its MATERIAL is
--     the realm's: the tornado lifts that realm's earth, its debris is that realm's rock and timber,
--     a storm darkens that realm's clouds, a crater is scorched into that realm's stone.
--
-- `back` draws behind the fighters (water, lava, funnels, markers, craters); `front` over them, only
-- what is thin or brief enough never to hide a fighter (the bolts, the meteors in flight). One-off
-- moments - an impact, a dust burst - are handed to FxPlayer as they begin.
local Canvas2D = require(script.Parent.Canvas2D)
local PixelGrid = require(script.Parent.PixelGrid)
local FxArt = require(script.Parent.FxArt)
local FxPlayer = require(script.Parent.FxPlayer)
local RealmArt = require(script.Parent.RealmArt)
local DisasterShapes = require(script.Parent.DisasterShapes)

local DisasterArt = {}

local COOL, HOT = DisasterShapes.COOL, DisasterShapes.HOT
local WHITE = Color3.new(1, 1, 1)
local mix = RealmArt.mix
local hash = PixelGrid.hash
local put = PixelGrid.put
local sized = FxArt.sized
local P = 2                                 -- art pixels a stud for the big bodies (lava, water)

local function pulse(frame: number, period: number): number
	return 0.5 - 0.5 * math.cos((frame % period) / period * math.pi * 2)
end
local function hex(h: string): Color3
	return Canvas2D.hex(h, WHITE)
end

local function span(stage: any): (number, number)
	local lo, hi = math.huge, -math.huge
	for _, s in stage.solids do lo, hi = math.min(lo, s.x1), math.max(hi, s.x2) end
	return lo, hi
end

-- ------------------------------------------------------------------ art ----
local cache: { [string]: any } = {}
local function inks(): ((string, number?) -> number, { { any } })
	local list: { { any } } = {}
	local index: { [string]: number } = {}
	return function(h: string, a: number?): number
		local k = h .. "@" .. tostring(a or 1)
		if not index[k] then
			local entry: { any } = { h }
			entry[2] = a or 1
			table.insert(list, entry)
			index[k] = #list
		end
		return index[k]
	end, list
end
local function compile(key: string, g: PixelGrid.Grid, list: { { any } }, ax: number, ay: number): any
	local rects: { any } = {}
	for i, r in PixelGrid.merge(g) do
		local row: { any } = { r[1], r[2], r[3], r[4] }
		row[5], row[6] = list[r[5]][1], list[r[5]][2]
		rects[i] = row
	end
	local art = { key = key, rects = rects, cols = g.w, rows = g.h, ax = ax, ay = ay }
	cache[key] = art
	return art
end
local function draw(c: any, art: any, x: number, y: number, cell: number, alpha: number?)
	Canvas2D.sprite(c, art.key, art.rects, x - art.ax * cell, y + art.ay * cell, cell, cell, art.cols, art.rows,
		FxArt.quantise(alpha or 1), true)
end

-- A tileable band of liquid, 32 studs wide: a rolling surface (frame 0-3 moves the swell along by
-- a quarter wavelength), and a body. `kind` "lava" crusts over and glows through its cracks;
-- "water" carries foam on the crest and light under it. Anchored at the surface's left end.
local TILE = 32
local function liquid(kind: string, frame: number, tint: { string }): any
	local key = `disaster|{kind}|{frame}|{tint[1]}`
	if cache[key] then return cache[key] end
	local ink, list = inks()
	local W, H = TILE * P, 10 * P
	local g = PixelGrid.new(W, H + 4)
	local crest, hi, body, low, crust = ink(tint[5]), ink(tint[4]), ink(tint[3]), ink(tint[2]), ink(tint[1])
	for x = 0, W - 1 do
		-- two whole swells across the tile, so tiles meet; the frame walks them along
		local phase = (x / W + frame / 8) * math.pi * 4
		local top = 2 + math.floor(math.sin(phase) * 1.6 + 0.5)
		for y = top, H + 3 do
			local d = y - top
			local v = if d == 0 then crest elseif d <= 1 then hi elseif d < H * 0.55 then body else low
			if kind == "lava" and d > 1 then
				-- crust: dark rafts of cooled rock drifting on the flow, ragged-edged, with the
				-- molten glow showing between them - noise, not a grid, or it reads as brickwork
				local fx = (x + frame * 2) % W
				local n = PixelGrid.noise(fx / 6, 3) * 0.6 + PixelGrid.noise(y / 3 + fx / 11, 7) * 0.4
				if n > 0.62 then v = crust elseif n > 0.57 then v = hi end
			elseif kind == "water" and d > 2 and hash(x // 3, y // 2 + frame, 5) > 0.93 then
				v = hi                                    -- light glancing under the surface
			end
			put(g, x, y, v)
		end
		if kind == "water" and math.sin(phase) > 0.75 then put(g, x, top - 1, crest) end   -- foam on the swell
	end
	return compile(key, g, list, 0, 2)
end

-- The tsunami's wall: a breaking wave 12 studs wide and as tall as its crest, curling toward +x,
-- with foam on its lip and spray thrown off ahead of it. Anchored at its foot, front edge.
-- `back` is how high the water behind the crest stands, as a fraction of `height`: the wave climbs
-- out of it rather than standing up off the sea floor like a wall.
local function curl(frame: number, tint: { string }, height: number, back: number): any
	local key = `disaster|curl|{frame}|{tint[1]}|{height}|{back}`
	if cache[key] then return cache[key] end
	local ink, list = inks()
	local W = 20 * P
	local H = math.floor(height * P + 0.5) + 4
	local over = 9                                     -- how far the lip throws out past the face
	local g = PixelGrid.new(W + over + 4, H)
	local foam, light, body, deep, dark = ink(tint[5]), ink(tint[4]), ink(tint[3]), ink(tint[2]), ink(tint[1])
	local function smooth(e0: number, e1: number, v: number): number
		local k = math.clamp((v - e0) / (e1 - e0), 0, 1)
		return k * k * (3 - 2 * k)
	end
	local top = 0
	for x = 0, W - 1 do
		local u = x / (W - 1)                          -- 0 at the back, 1 at the front face
		local tall = math.floor((H - 2) * (back + (1 - back) * smooth(0.05, 1, u) ^ 1.6) + 0.5)
		local y0 = H - tall
		if x == W - 1 then top = y0 end
		for y = y0, H - 1 do
			local f = (y - y0) / math.max(1, tall)
			local v = if y - y0 < 1 then foam elseif f < 0.28 then light elseif f < 0.62 then body elseif f < 0.88 then deep else dark
			-- streaks of foam running down the face, slanted with the water
			if y - y0 > 1 and (x + y + frame) % 7 == 0 and u > 0.35 then v = light end
			put(g, x, y, v)
		end
	end
	-- the lip: thrown forward from the top of the face and curling down over a dark tube
	for k = 0, over do
		local y = top + math.floor((k / over) ^ 2 * 5 + 0.5)
		put(g, W - 1 + k, y, foam); put(g, W - 1 + k, y + 1, light); put(g, W - 1 + k, y + 2, body)
	end
	for k = 0, 6 do put(g, W - 1 + over - math.floor(k / 3), top + 5 + k, if k < 4 then light else foam) end
	for y = top + 3, top + 12 do
		for x = W - 5, W - 2 do put(g, x, y, if (x + y) % 3 == 0 then deep else dark) end   -- the tube under the lip
	end
	-- spray thrown up and ahead of the wall
	for k = 0, 8 do
		put(g, W + math.floor(hash(k, frame, 11) * (over + 3)), math.max(0, top - 1 + math.floor(hash(k, frame + 1, 11) * 6)), foam)
	end
	return compile(key, g, list, W, H)
end

-- The tornado's funnel, as pixel tornadoes are drawn: a stack of tilted bands, wide at the top and
-- pinched at the floor, alternately lit and shaded, swaying and crawling round as the frames turn.
-- `tint` is the realm's dust (a FxArt ramp). Anchored at its foot.
local function funnel(frame: number, tint: { string }, width: number, height: number): any
	local key = `disaster|funnel|{frame}|{tint[1]}|{width}|{height}`
	if cache[key] then return cache[key] end
	local ink, list = inks()
	local Q = 4
	local W, H = math.floor(width * Q + 0.5), math.floor(height * Q + 0.5)
	local g = PixelGrid.new(W + 6, H + 2)
	local C = { ink(tint[1]), ink(tint[2]), ink(tint[3]), ink(tint[4]), ink(tint[5], 0.9) }
	local c = (W + 6) / 2
	for y = 0, H - 1 do
		local up = 1 - y / (H - 1)                          -- 0 at the floor, 1 at the top
		local hw = (0.12 + 0.88 * up ^ 1.25) * W / 2
		local sway = math.sin(up * 4.2 + frame * 1.57) * W * 0.06 * up
		local band = math.floor((y + frame * 2) / 3) % 4
		for x = math.floor(c + sway - hw), math.ceil(c + sway + hw) do
			local u = (x - (c + sway)) / math.max(1, hw)           -- -1 left edge .. 1 right edge
			if math.abs(u) <= 1 then
				-- lit on the left, shaded on the right, the band colour stepping round the funnel
				local shade = if u < -0.55 then 1 elseif u < 0.2 then 0 elseif u < 0.7 then -1 else -2
				local tone = math.clamp((if band % 2 == 0 then 4 else 3) + shade, 1, 5)
				if math.abs(u) > 0.92 and hash(x, y, frame) > 0.5 then continue end   -- a ragged edge
				put(g, x, y, C[tone])
			end
		end
	end
	return compile(key, g, list, math.floor(c), H)
end

-- A meteor crater burned into a realm's stone: a scorched bowl with embers in it. Anchored at the
-- centre of its rim.
local function crater(realm: any, frame: number): any
	local key = `disaster|crater|{realm.id}|{frame}`
	if cache[key] then return cache[key] end
	local ink, list = inks()
	local g = PixelGrid.new(28, 8)
	local rim, char, scorch = ink(realm.rock[2]), ink(mix(realm.rock[1], "#100806", 0.5)), ink("#1A0E08")
	PixelGrid.ellipse(g, 14, 3, 13, 3.5, rim)
	PixelGrid.ellipse(g, 14, 3.5, 10, 2.6, char)
	PixelGrid.ellipse(g, 14, 4, 7, 1.8, scorch)
	for k = 0, 5 do
		local x = 6 + math.floor(hash(k, 1, 3) * 16)
		local y = 3 + math.floor(hash(k, 2, 3) * 3)
		put(g, x, y, ink(if (k + frame) % 3 == 0 then "#FFD27A" else HOT))
	end
	return compile(key, g, list, 14, 2)
end

-- ------------------------------------------------------------------ helpers ----
local function realmWater(realm: any): { string }
	-- the sea, leaning toward the realm's sky
	local base = mix("#2E8AB8", realm.sky[2], 0.25)
	return { mix(base, "#0A1E2E", 0.6), mix(base, "#0E2E44", 0.3), base, mix(base, "#BFF4FF", 0.45), "#F4FCFF" }
end
local LAVA = { "#4A1408", "#8A2A12", "#E8541A", "#FFB43C", "#FFE89A" }

-- A dashed line where something WILL be: chunky cool dashes, a lit pixel at each end.
local function dashes(c: any, x1: number, x2: number, y: number, alpha: number)
	local col = hex(COOL)
	local x = x1
	while x < x2 do
		Canvas2D.rect(c, x, y - 0.15, math.min(1.2, x2 - x), 0.3, col, alpha)
		x += 2
	end
end

-- An up-pointing chevron: the lava will come up to here.
local function chevron(c: any, x: number, y: number, s: number, colour: Color3, alpha: number, dir: number?)
	local d = dir or 0
	if d == 0 then
		Canvas2D.line(c, x - s, y - s * 0.6, x, y, 0.3, colour, alpha)
		Canvas2D.line(c, x, y, x + s, y - s * 0.6, 0.3, colour, alpha)
	else
		Canvas2D.line(c, x - d * s * 0.6, y + s, x, y, 0.3, colour, alpha)
		Canvas2D.line(c, x, y, x - d * s * 0.6, y - s, 0.3, colour, alpha)
	end
end

-- A target on the floor, the size of what is coming: a flattened ring that pulses (FxArt reticle)
-- and a pin at its centre.
local function target(c: any, x: number, y: number, width: number, alpha: number)
	local ret = FxArt.get("reticle", 0, COOL)
	FxArt.draw(c, ret, x, y + 0.1, sized(ret, width), 0, alpha, 0.3)
	Canvas2D.rect(c, x - 0.3, y, 0.6, 0.25, hex(COOL), math.min(1, alpha + 0.3))
end

-- Remembers which one-off moments have already been handed to FxPlayer, per event.
local fired: { [string]: boolean } = {}
local firedEvent: any = nil
local function once(view: any, id: string): boolean
	local event = `{view.type}|{view.warn}|{view.total}`
	if firedEvent ~= event or (view.frame or 0) < 2 then
		table.clear(fired)
		firedEvent = event
	end
	if fired[id] then return false end
	fired[id] = true
	return true
end
DisasterArt.resetMoments = function() table.clear(fired); firedEvent = nil end

-- ------------------------------------------------------------------ the six ----
local BACK: { [string]: (any, any, any, any, number, any) -> () } = {}
local FRONT: { [string]: (any, any, any, any, number, any) -> () } = {}
-- Where the camera is, for the storm lid's parallax; set by `back` each frame.
local camX = 0

BACK.lavasurge = function(c, v, stage, realm, t, _player)
	local lo, hi = span(stage)
	local warn = v.phase == "warn"
	dashes(c, lo - 8, hi + 8, v.line, if warn then 0.5 + 0.5 * pulse(v.frame, 30) else 0.35)
	if warn then
		for x = lo, hi, 12 do chevron(c, x, v.line + 1.2 + pulse(v.frame + x, 30) * 0.8, 0.8, hex(COOL), 0.8) end
	end
	if v.level > stage.blast.bottom then
		local frame = math.floor(v.frame / 6) % 8
		local art = liquid("lava", frame, LAVA)
		local bottom = stage.blast.bottom - 5
		local x0 = math.floor((lo - 40) / TILE) * TILE
		local depth = 10
		if v.level - depth > bottom then
			Canvas2D.rect(c, lo - 40, bottom, hi - lo + 80, v.level - depth - bottom + 0.1, hex(LAVA[2]), 1)
		end
		local x = x0
		while x < hi + 40 do
			draw(c, art, x, v.level + 1, 1 / P)
			x += TILE
		end
		-- bubbles that swell and pop along the surface, and embers lifting off it
		for i = 0, 8 do
			local cyc = (v.frame * 0.02 + i * 0.37) % 1
			local bx = lo + ((i * 11.3 + v.frame * 0.15) % (hi - lo))
			if cyc < 0.8 then
				-- a bubble swelling on the surface...
				FxArt.draw(c, FxArt.get("orb", 0, "fire"), bx, v.level + 0.5 + cyc * 0.4, 0.5 + cyc * 1.1, 0, 0.9)
			else
				-- ...and bursting
				FxArt.draw(c, FxArt.get("ring", math.floor((cyc - 0.8) * 25), "fire"), bx, v.level + 0.8, 2.2, 0, 1, 0.6)
			end
		end
		for i = 0, 6 do
			local cyc = (t * 0.6 + i / 7) % 1
			local ex = lo + ((i * 17.7 + t * 2) % (hi - lo))
			FxArt.draw(c, FxArt.get("spark", if cyc > 0.7 then 2 else 0, "fire"), ex + math.sin(t * 2 + i) * 0.6,
				v.level + 1 + cyc * 9, 0.6, 0, 1 - cyc)
		end
	end
end

BACK.lightning = function(c, v, _stage, realm, t, player)
	-- the storm lid rolls in over the realm's own sky while the event runs
	local k = if v.phase == "warn" then v.k elseif v.phase == "after" then 1 - v.k else 1
	if k > 0 then
		local m = c.m
		RealmArt.overlay(c, realm, "storm", camX, t, k * 0.9)
		Canvas2D.setTransform(c, m.a, m.b, m.c, m.d, m.e, m.f)
	end
	for _, s in v.strikes or {} do
		if not s.live then
			-- the marker: a target that tightens as the bolt gets closer, and a faint shaft of
			-- where it will come down
			local tighten = pulse(v.frame, 20)
			target(c, s.x, s.y, 5 - tighten * 1.2, 0.35 + 0.4 * tighten)
			Canvas2D.rect(c, s.x - 0.15, s.y, 0.3, 40, hex(COOL), 0.08 + 0.1 * tighten)
		else
			if player and once(v, `bolt{s.x}`) then
				FxPlayer.add(player, "burst", s.x, s.y + 1, 4.2, 0.36, "volt")
				FxPlayer.add(player, "ring", s.x, s.y + 0.15, 9, 0.32, COOL, { sy = 0.28 })
				FxPlayer.add(player, "burst", s.x, s.y + 0.4, 3.2, 2.4, "smoke", { fadeAt = 0.4, delay = 0.25 })
				player.flash = math.max(player.flash, 0.18)
				player.flashColour = COOL
			end
		end
	end
end

FRONT.lightning = function(c, v, _stage, _realm, t, _player)
	for _, s in v.strikes or {} do
		if s.live then
			-- the bolt: jagged segments from the sky to the strike, white-hot inside a cool halo,
			-- a fresh strike every few frames
			local seg = 7.5
			local n = 7
			local flick = math.floor(t * 30)
			Canvas2D.rect(c, s.x - 0.8, s.y, 1.6, seg * n, hex(COOL), 0.25)
			for i = 0, n - 1 do
				local y = s.y + i * seg
				local art = FxArt.get("bolt", (flick + i) % 4, COOL, nil, (i % 4) + 1)
				FxArt.draw(c, art, s.x + (hash(i, flick, 7) - 0.5) * 1.2, y + seg, sized(art, seg * 1.05), -math.pi / 2, 1)
			end
			FxArt.draw(c, FxArt.get("pop", flick % 3, COOL, nil, 2), s.x, s.y + 0.6, 2.4, 0, 1)
		end
	end
end

BACK.tornado = function(c, v, _stage, realm, t, _player)
	local k = if v.phase == "warn" then v.k elseif v.phase == "after" then 1 - v.k else 1
	-- the funnel lifts the realm's own earth: its rock tone, banded light and dark
	local dust = mix(realm.rock[4], realm.top[2], 0.25)
	local ramp = FxArt.ramp(dust)
	local f = math.floor(t * 12) % 4
	local art = funnel(f, ramp, v.radiusTop * 2 * 1.2, v.height * 1.05)
	draw(c, art, v.x, v.floor, 1 / 4, (0.35 + 0.6 * k))
	-- a skirt of dust churning at its foot
	for i = 0, 2 do
		local cyc = (t * 1.4 + i / 3) % 1
		local b = FxArt.get("burst", 4 + math.floor(cyc * 3), dust, nil, i + 1)
		FxArt.draw(c, b, v.x + (i - 1) * 1.8, v.floor + 0.6, sized(b, 3.2 + cyc * 2), 0, k * (1 - cyc) * 0.9, 0.45)
	end
	-- debris: the realm's rock and timber, whirled up and round
	local rock, wood = hex(realm.rock[2]), hex(realm.shelfRamp[2])
	for i = 0, 7 do
		local a = t * (3 + i * 0.3) + i * 1.3
		local up = ((t * 0.35 + i / 8) % 1)
		local r = (v.radiusFloor + (v.radiusTop - v.radiusFloor) * up) * 1.15
		local x = v.x + math.cos(a) * r
		local y = v.floor + up * v.height
		local size = 0.35 + (i % 3) * 0.15
		Canvas2D.rect(c, x - size / 2, y - size / 2, size, size, if i % 3 == 0 then wood else rock, k * (0.55 + 0.45 * math.sin(a) ^ 2))
	end
	if v.phase == "warn" then
		Canvas2D.rect(c, v.x - 0.2, v.floor, 0.4, v.height, hex(COOL), 0.5 * v.k)
		target(c, v.x, v.floor, 4, 0.3 + 0.5 * v.k)
	end
end

BACK.tsunami = function(c, v, stage, realm, t, _player)
	local lo, hi = span(stage)
	local water = realmWater(realm)
	if v.phase == "warn" then
		-- the horizon swells, and chevrons point in from the side it comes from
		local art = liquid("water", math.floor(v.frame / 8) % 8, water)
		local x = math.floor((lo - 40) / TILE) * TILE
		while x < hi + 40 do
			draw(c, art, x, v.base + v.k * 2, 1 / P, 0.5)
			x += TILE
		end
		local edge = if v.dir > 0 then lo - 6 else hi + 6
		local a = 0.5 + 0.5 * pulse(v.frame, 24)
		for i = 0, 2 do chevron(c, edge + v.dir * i * 1.6, v.crest * 0.5, 1.2, hex(COOL), a, v.dir) end
		return
	end
	local fade = if v.phase == "after" then 1 - v.k else 1
	-- the backwash: the sea it leaves behind, sinking away after
	local back = if v.dir > 0 then stage.blast.left else v.x
	local front = if v.dir > 0 then v.x else stage.blast.right
	if front > back then
		local art = liquid("water", math.floor(t * 8) % 8, water)
		local x = math.floor(back / TILE) * TILE
		while x < front do
			draw(c, art, x, v.base + v.crest * 0.5 * (0.6 + 0.4 * fade), 1 / P, 0.85 * fade)
			x += TILE
		end
	end
	if v.phase == "strike" then
		local h = v.crest - v.base
		local art = curl(math.floor(t * 10) % 3, water, h, math.floor((v.crest * 0.5 - v.base) / h * 20) / 20)
		Canvas2D.save(c)
		Canvas2D.translate(c, v.x + v.dir * v.width / 2, v.base)
		Canvas2D.scale(c, v.dir, 1)
		draw(c, art, 0, 0, 1 / P, 1)
		Canvas2D.restore(c)
	end
end

BACK.earthquake = function(c, v, _stage, realm, t, player)
	local warn = v.phase == "warn"
	local seam = if warn then 0.4 + 0.6 * pulse(v.frame, 16) else 0.85
	local plates = v.plates or {}
	for i, p in plates do
		for j, x in { p.x1, p.x2 } do
			-- a jagged crack down the plate's edge, cool while it gives, hot once it has gone
			local crack = FxArt.get("bolt", (math.floor(v.frame / 8) + j) % 4, if warn then COOL else HOT, nil, i + j)
			FxArt.draw(c, crack, x, p.top, sized(crack, 4.5), -math.pi / 2, seam)
			-- grit trickling out of it
			for k = 0, 2 do
				local cyc = (t * 1.3 + k / 3 + x * 0.1) % 1
				Canvas2D.rect(c, x - 0.15 + (k - 1) * 0.3, p.top - 1 - cyc * 5, 0.3, 0.3, hex(realm.rock[3]), seam * (1 - cyc))
			end
		end
		if warn then
			-- pebbles hopping on the plate as it shivers
			for k = 0, 4 do
				local x = p.x1 + (p.x2 - p.x1) * (k + 0.5) / 5
				local hop = math.max(0, math.sin(v.frame * 0.9 + k * 2.1)) * 0.6 * v.k
				Canvas2D.rect(c, x - 0.2, p.top + hop, 0.4, 0.35, hex(realm.rock[2]), 0.9)
			end
		else
			Canvas2D.rect(c, p.x1, p.top - 0.3, p.x2 - p.x1, 0.3, hex(HOT), 0.35)
			if player and once(v, `plate{i}`) then
				local dust = mix(realm.rock[4], realm.top[2], 0.3)
				for d = 0, 3 do
					FxPlayer.add(player, "burst", p.x1 + (p.x2 - p.x1) * (d + 0.5) / 4, p.top + 1, 6, 0.7, dust, { delay = d * 0.04 })
				end
				FxPlayer.add(player, "ring", (p.x1 + p.x2) / 2, p.top + 0.1, (p.x2 - p.x1) * 1.3, 0.4, HOT, { sy = 0.25 })
			end
		end
	end
	if #plates == 0 and warn then
		-- a tremor: a ripple of dust runs along the whole floor
		for x = -60, 60, 3 do
			local h = math.max(0, math.sin(x * 0.4 - v.frame * 0.5)) * 0.5
			Canvas2D.rect(c, x, -0.4 + h, 1.6, 0.3, hex(COOL), 0.3 + 0.4 * pulse(v.frame, 10))
		end
	end
end

BACK.meteor = function(c, v, _stage, realm, t, player)
	local k = if v.phase == "warn" then v.k elseif v.phase == "after" then 1 - v.k else 1
	if k > 0 then
		-- the sky reddens with the fire coming down through it
		local vp = Canvas2D.viewport(c)
		local m = c.m
		Canvas2D.screen(c)
		Canvas2D.rect(c, 0, 0, vp.X, vp.Y * 0.45, hex("#FF5A2A"), 0.12 * k)
		Canvas2D.rect(c, 0, 0, vp.X, vp.Y * 0.2, hex("#FF8A3A"), 0.1 * k)
		Canvas2D.setTransform(c, m.a, m.b, m.c, m.d, m.e, m.f)
	end
	for i, r in v.rocks or {} do
		if r.shadow > 0 then
			Canvas2D.ellipse(c, r.x, r.y + 0.1, 0.6 + 4.4 * r.shadow, 0.4 + 0.5 * r.shadow, Color3.new(0, 0, 0), 0.45)
			target(c, r.x, r.y, 10, 0.3 * r.shadow + 0.2)
		end
		if r.live and player and once(v, `rock{i}`) then
			FxPlayer.add(player, "burst", r.x, r.y + 1.5, 9, 0.45, "fire")
			FxPlayer.add(player, "ring", r.x, r.y + 0.2, 12, 0.34, HOT, { sy = 0.28 })
			FxPlayer.add(player, "burst", r.x, r.y + 1, 4, 1.6, mix(realm.rock[3], "#3A2A22", 0.5), { fadeAt = 0.3, delay = 0.2 })
			player.flash = math.max(player.flash, 0.12)
			player.flashColour = HOT
		end
		if r.live then Canvas2D.ellipse(c, r.x, r.y + 1, 5, 4, hex(HOT), 0.5) end
		if r.burning then
			draw(c, crater(realm, math.floor(t * 6) % 3), r.x, r.y + 0.05, 1 / 4, 1)
			local fl = FxArt.get("flame", math.floor(t * 10 + i) % 6, "fire", nil, (i % 4) + 1)
			FxArt.draw(c, fl, r.x + (hash(i, 1, 2) - 0.5) * 2, r.y + 0.3, sized(fl, 1.1), 0, 0.6 + 0.4 * pulse(v.frame, 12))
		end
	end
end

FRONT.meteor = function(c, v, _stage, realm, t, _player)
	for i, r in v.rocks or {} do
		if r.shadow > 0 then
			-- falling in along its line, a burning rock of the realm's own stone
			local h = 40 * (1 - r.shadow)
			local x, y = r.x - h * 0.3, r.y + h
			local a = math.atan2(-1, -0.3)
			local comet = FxArt.get("comet", math.floor(t * 20 + i) % 3, "fire", nil, (i % 4) + 1)
			FxArt.draw(c, comet, x, y, sized(comet, 10), a, math.min(1, r.shadow * 1.6))
			Canvas2D.circle(c, x, y, 1.0, hex(realm.rock[2]), math.min(1, r.shadow * 1.6))
			Canvas2D.circle(c, x - 0.3, y + 0.3, 0.4, hex(realm.rock[4]), math.min(1, r.shadow * 1.6))
		end
	end
end

-- The disaster behind the fighters. `realm` is the stage's (Realms.of); `player` the FxPlayer state
-- one-off moments go to (nil in a tool that does not want them).
function DisasterArt.back(c: any, view: any, stage: any, realm: any, t: number, player: any?, cameraX: number?)
	camX = cameraX or 0
	local fn = view and BACK[view.type]
	if fn then fn(c, view, stage, realm, t, player) end
end

-- The disaster over the fighters: only what is thin or brief.
function DisasterArt.front(c: any, view: any, stage: any, realm: any, t: number, player: any?)
	local fn = view and FRONT[view.type]
	if fn then fn(c, view, stage, realm, t, player) end
end

-- How hard the camera should shake for this disaster right now (Effects' shake units): an
-- earthquake rumbles as it warns and jolts as the plates go; a meteor's impact thumps.
function DisasterArt.shake(view: any): number
	if not view then return 0 end
	if view.type == "earthquake" then
		if view.phase == "warn" then return 0.12 + 0.25 * view.k end
		if view.phase == "strike" and (view.frame - view.warn) < 14 then return 0.9 end
	elseif view.type == "meteor" then
		for _, r in view.rocks or {} do
			if r.live then return 0.5 end
		end
	elseif view.type == "lightning" then
		for _, s in view.strikes or {} do
			if s.live then return 0.35 end
		end
	end
	return 0
end

-- The bodies, for the hazards that are the same stuff on a smaller scale (HazardArt): the tide is
-- the tsunami's sea, the rogue wave a smaller breaker, the dust devil a smaller funnel.
DisasterArt.liquid, DisasterArt.curl, DisasterArt.funnel = liquid, curl, funnel
DisasterArt.realmWater, DisasterArt.LAVA, DisasterArt.TILE, DisasterArt.P = realmWater, LAVA, TILE, P
DisasterArt.draw, DisasterArt.chevron, DisasterArt.target = draw, chevron, target

DisasterArt.KINDS = { "lavasurge", "lightning", "tornado", "tsunami", "earthquake", "meteor" }

return DisasterArt
