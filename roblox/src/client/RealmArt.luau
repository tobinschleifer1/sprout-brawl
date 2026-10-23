--!strict
-- The realms, drawn: Brawlhalla-style floating islands, the platforms that hang over them, and the
-- skies behind. ROBLOX ONLY - Realms.luau says why, and what a realm may and may not change.
--
-- EVERYTHING HERE IS A SPRITE. An island, a platform, a band of distant mountains is a pixel grid
-- generated once per match, merged into rectangles and drawn as ONE Canvas2D sprite: a container
-- Frame that moves with the camera over static children. The camera moves every frame, so a stage
-- drawn as loose rectangles re-placed every one of them every frame; drawn like this, a detailed
-- island costs one Frame write a frame, whatever is painted on it. Building is the expensive part
-- (~10us a cell, measured), so it happens once, when the stage is first drawn.
--
-- SCALES. Islands and platforms are 4 art pixels a stud (FxArt's effect density, half the
-- weapons'). Sky layers are drawn in the web's 270-pixel backbuffer units at 2 units an art pixel.
--
-- What is NOT here: anything a player reads to play. Ledge markers, the sinking warning, hazards
-- and the platforms' positions all come from the Stage, exactly as before (Stage2D, World2D). The
-- art only dresses geometry it is given; it never moves it.
local Canvas2D = require(script.Parent.Canvas2D)
local PixelGrid = require(script.Parent.PixelGrid)

local RealmArt = {}

RealmArt.PPU = 4
local SKY_PX = 2              -- backbuffer units an art pixel in the sky layers
local TILE_W, TILE_H = 480, 270
local OUTLINE = "#120E16"

local hash, noise = PixelGrid.hash, PixelGrid.noise
local put, get = PixelGrid.put, PixelGrid.get

-- ------------------------------------------------------------------ colour ----
local function rgb(hex: string): (number, number, number)
	local h = string.gsub(hex, "#", "")
	return tonumber(string.sub(h, 1, 2), 16) :: number, tonumber(string.sub(h, 3, 4), 16) :: number,
		tonumber(string.sub(h, 5, 6), 16) :: number
end
-- `a` blended `k` of the way to `b`
local function mix(a: string, b: string, k: number): string
	local r1, g1, b1 = rgb(a)
	local r2, g2, b2 = rgb(b)
	return string.format("#%02X%02X%02X", math.floor(r1 + (r2 - r1) * k + 0.5), math.floor(g1 + (g2 - g1) * k + 0.5),
		math.floor(b1 + (b2 - b1) * k + 0.5))
end
RealmArt.mix = mix

-- A drawing's own palette: colours are interned to small numbers, which is what a grid holds.
-- WCAG relative luminance of a hex colour
local function lum(hex: string): number
	local r, g, b = rgb(hex)
	local function ch(v: number): number
		local c = v / 255
		return if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
end
RealmArt.lum = lum
-- hue, saturation and value of a hex colour, and back
local function hsv(hex: string): (number, number, number)
	local r, g, b = rgb(hex)
	r, g, b = r / 255, g / 255, b / 255
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
	end
	return h / 6, if mx > 0 then d / mx else 0, mx
end
local function fromHsv(h: number, sat: number, v: number): string
	local i = math.floor(h * 6) % 6
	local f = h * 6 - math.floor(h * 6)
	local p, q, t = v * (1 - sat), v * (1 - f * sat), v * (1 - (1 - f) * sat)
	local r, g, b = v, t, p
	if i == 1 then r, g, b = q, v, p elseif i == 2 then r, g, b = p, v, t elseif i == 3 then r, g, b = p, q, v
	elseif i == 4 then r, g, b = t, p, v elseif i == 5 then r, g, b = v, p, q end
	return string.format("#%02X%02X%02X", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
RealmArt.hsv = hsv
-- A background colour put behind the play space: hazed a little toward the realm's mid sky, then
-- held under the island - no more saturated than its rock body, and no brighter - by lowering
-- saturation and value, keeping the hue (mixed toward the blue sky instead, the hall's gold roof went
-- grey; capped by the lit band instead of the body, the hall stood at twice the island's brightness)
function RealmArt.backdrop(realm: any, hex: string, amount: number): string
	local target = mix(realm.far, realm.sky[1], 0.5)
	local c = mix(hex, target, amount)
	local cap = lum(realm.rock[3])
	local _, capS = hsv(realm.rock[3])
	local h, sat, v = hsv(c)
	sat = math.min(sat, capS)
	c = fromHsv(h, sat, v)
	while lum(c) > cap and v > 0.02 do
		v *= 0.94
		c = fromHsv(h, sat, v)
	end
	return c
end

local function inks(): ((string, number?) -> number, { { any } })
	local list: { { any } } = {}
	local index: { [string]: number } = {}
	return function(hex: string, a: number?): number
		local k = hex .. "@" .. tostring(a or 1)
		local i = index[k]
		if not i then
			local entry: { any } = { hex }
			entry[2] = a or 1
			table.insert(list, entry)
			i = #list
			index[k] = i
		end
		return i
	end, list
end

export type Art = { key: string, rects: { any }, stackKey: string, stack: { any }, cols: number, rows: number, ax: number, ay: number }
local cache: { [string]: Art } = {}

local function compile(key: string, g: PixelGrid.Grid, list: { { any } }, ax: number, ay: number): Art
	local rects: { any } = {}
	for i, r in PixelGrid.merge(g) do
		local ink = list[r[5]]
		local row: { any } = { r[1], r[2], r[3], r[4] }
		row[5], row[6] = ink[1], ink[2]
		rects[i] = row
	end
	-- The same picture as overlapping layers, about a third fewer rectangles (PixelGrid.layers).
	-- Exact only at full opacity, which is how `place` uses it; `rects` stay the plain partition.
	local stack: { any } = {}
	for i, r in PixelGrid.layers(g, function(v: number): boolean return list[v][2] >= 1 end) do
		local ink = list[r[5]]
		local row: { any } = { r[1], r[2], r[3], r[4] }
		row[5], row[6] = ink[1], ink[2]
		stack[i] = row
	end
	local art = { key = key, rects = rects, stackKey = key .. "|L", stack = stack, cols = g.w, rows = g.h, ax = ax, ay = ay }
	cache[key] = art
	return art
end

-- Draws `art` with its anchor cell at (x, y), cells `cell` units on a side, in whatever space the
-- transform is (world for islands, backbuffer for the sky).
local function draw(c: any, art: Art, x: number, y: number, cell: number)
	if (c.alpha or 1) >= 1 then
		Canvas2D.sprite(c, art.stackKey, art.stack, x - art.ax * cell, y + art.ay * cell, cell, cell, art.cols, art.rows)
	else
		Canvas2D.sprite(c, art.key, art.rects, x - art.ax * cell, y + art.ay * cell, cell, cell, art.cols, art.rows)
	end
end
RealmArt.draw = draw

-- ------------------------------------------------------------------ islands ----
-- What dangles under an island, from the cell (x, y0) on its underside, `len` cells long.
local function hanging(g: PixelGrid.Grid, kind: string, x: number, y0: number, len: number, H1: number, H2: number,
	glow: number, seed: number)
	if kind == "roots" or kind == "vines" or kind == "seaweed" then
		local wob = 0
		for k = 0, len do
			-- it bends every third cell, so it hangs in short straight runs that merge
			if k % 3 == 0 then
				wob += (hash(x, k, seed) - 0.5) * (if kind == "seaweed" then 2.4 else 1.6)
				wob = math.clamp(wob, -2, 2)
			end
			local xx = x + math.floor(wob + 0.5)
			put(g, xx, y0 + k, if k < 2 then H2 else H1)
			if kind == "vines" and k % 4 == 2 then put(g, xx + (if k % 8 == 2 then 1 else -1), y0 + k, H2) end
			if kind == "roots" and k == math.floor(len * 0.5) then
				for j = 1, 3 do put(g, xx + j, y0 + k + j, H1) end
			end
		end
	elseif kind == "chains" then
		-- links as alternating two-cell runs, side-on and face-on
		for k = 0, len do
			if (k // 2) % 2 == 0 then put(g, x, y0 + k, H1) else put(g, x, y0 + k, H2) end
		end
		put(g, x - 1, y0 + len + 1, H2); put(g, x + 1, y0 + len + 1, H2); put(g, x, y0 + len + 2, H2)
	elseif kind == "lanterns" then
		local rope = math.max(3, len - 5)
		for k = 0, rope do put(g, x, y0 + k, H1) end
		PixelGrid.rect(g, x - 1, y0 + rope + 1, 3, 4, H1)
		put(g, x, y0 + rope + 2, glow); put(g, x, y0 + rope + 3, glow)
		put(g, x, y0 + rope + 5, H2)
	elseif kind == "crystals" then
		local w = 1 + math.floor(hash(x, 7, seed) * 2)
		for k = 0, len do
			local half = math.floor(w * (1 - k / (len + 1)) + 0.5)
			for o = -half, half do put(g, x + o, y0 + k, if o == -half then H2 else H1) end
		end
	elseif kind == "lava" then
		for k = 0, len do
			put(g, x, y0 + k, if k % 2 == 0 then H2 else H1)
		end
		put(g, x - 1, y0 + len, H1); put(g, x + 1, y0 + len, H1); put(g, x, y0 + len + 1, H2)
		put(g, x, y0 + len + 2, glow)
	end
end

-- A walled island `width` studs across: `thick` studs of wall, a tapering rocky underside and what
-- hangs from it. Two sprites: the BODY at half density (2 art pixels a stud - painted rock reads
-- as chunky masses, and half the density is a quarter of the rectangles) and the walking SURFACE
-- at full density, where the grass, sand or planks are, so the edge a player lands on stays crisp.
-- Both are anchored at the left end of the walking surface.
local BODY_PPU = 2
RealmArt.BODY_PPU = BODY_PPU
function RealmArt.island(realm: any, width: number, thick: number, seed: number): (Art, Art)
	local key = `realm|{realm.id}|island|{width}|{thick}|{seed}`
	-- Built once. (The first version looked the surface up under a key nothing stored, so it missed
	-- every time and rebuilt the island - and handed Canvas2D a new table, which rebuilt its sprite -
	-- every frame: 17ms a frame in the lobby, found with PerfMonitor's sections.)
	local hit = cache[key]
	if hit then return hit, RealmArt.surface(realm, width, seed) end
	local P = BODY_PPU
	local ink, list = inks()
	local O = ink(OUTLINE)
	local R = {}
	for i, hex in realm.rock do R[i] = ink(hex) end
	local H1, H2 = ink(realm.hangRamp[1]), ink(realm.hangRamp[2])
	local GLOW = ink(realm.glow)
	local W = math.floor(width * P + 0.5)
	local margin = 2
	local wallR = math.floor(thick * P + 0.5)
	local taperR = math.floor(math.clamp(width * 0.3, 4, 18) * P + 0.5)
	local hangR = 13
	local g = PixelGrid.new(W + margin * 2, wallR + taperR + hangR)
	local bottoms = table.create(W, 0)
	-- the courses under the lit band: three, each 3-6 rows deep at 2 cells a stud (scaled to P)
	local courseOf, seamRow = {}, {}
	do
		local y, c = math.floor(3 * P / 2), 1
		while c <= 3 and y < wallR do
			local depth = math.floor((3 + math.floor(hash(c, 20, seed) * 4)) * P / 2)
			for yy = y, math.min(wallR, y + depth - 1) do courseOf[yy] = c end
			seamRow[y + depth - 1] = true
			y += depth; c += 1
		end
	end
	for x = 0, W - 1 do
		-- the underside steps a whole stud (two cells) at a time: as jagged to the eye, and runs
		-- that match their neighbour merge, where a profile changing every cell cannot
		local xs = x - x % 2
		local u = (xs + 1) / W
		local prof = math.max(0, 1 - math.abs(2 * u - 1)) ^ 0.7
		local jag = ((noise(xs / 4, seed) - 0.5) * 4 + (hash(xs // 2, 1, seed) - 0.5) * 2) * prof
		local bottom = wallR + math.floor(taperR * prof + jag)
		bottoms[x + 1] = bottom
		-- (the UI's anatomy and the fighters' shading, in rock: a shine row and a lit band along the top,
		-- then three courses of blocks - seams in the soft tone, depths and joints varied so it reads as
		-- stone, not planks - and plain rock below them into a dark belly and lip; scaled to the density)
		local k = P / 2
		local belly = wallR + math.floor(taperR * prof * 0.55)
		for y = 0, bottom do
			local v = R[3]
			local c = courseOf[y] -- the course this row is in (nil below the third)
			if c then
				v = if c % 2 == 1 then R[3] else R[2]
				-- the seam closing a course one tone darker than it (in R[2] under an R[2] course, half
				-- the seams were invisible), and a few lit chips along each course's top
				if seamRow[y] and y > 3 * k then v = if c % 2 == 1 then R[2] else R[1] end
				if courseOf[y - 1] ~= c and hash(x // (2 * k), c, seed) > 0.86 then v = R[4] end
				-- the joints, in the top course only (each one splits every row it crosses, and in all three
				-- the fight's warm-up built a sprite over its per-tick budget): a soft column every 10-18
				-- cells, so the top course reads as blocks and the rest as strata
				if c == 1 then
					local pitch = math.floor((10 + hash(c, 21, seed) * 8) * k)
					local off = math.floor(hash(c, 22, seed) * pitch)
					if (x + off) % pitch == 0 and not seamRow[y] then v = R[2] end
				end
			end
			if y < k then v = R[5]                                 -- the shine along the top
			elseif y < 3 * k then v = R[4]                         -- the lit band under the surface
			elseif y >= bottom - k then v = R[1]                   -- the dark lip at the foot
			elseif y > belly then
				-- the belly: a mid-dark step, then dark (a dither here broke rows into single cells,
				-- and the fight's first frame went over its build budget)
				v = if y > belly + 2 * k then R[1] else R[2]
			end
			if x < k and y >= k then v = R[4] elseif x >= W - k and y >= k then v = R[1] end
			put(g, x + margin, y, v)
		end
	end
	-- cracks: only the lava realms' glowing seams now (the strata carry the rock's texture, and the
	-- plain dark cracks and lit stones they replace cost their rectangles twice over)
	for k = 0, if realm.hang == "lava" then math.max(2, W // 14) else -1 do
		local x = math.floor(hash(k, 3, seed) * (W - 6)) + 3
		local y = 3 + math.floor(hash(k, 4, seed) * math.max(1, wallR))
		local glowing = k % 2 == 0
		for _ = 1, 4 + math.floor(hash(k, 5, seed) * 6) do
			if y >= bottoms[math.clamp(x + 1, 1, W)] - 2 then break end
			put(g, x + margin, y, if glowing then GLOW else R[1])
			if not glowing then put(g, x + margin, y - 1, R[4]) end
			y += 1
			local jog = hash(x, y, seed)
			if jog > 0.82 then x += 1 elseif jog < 0.18 then x -= 1 end
			x = math.clamp(x, 1, W - 2)
		end
	end
	-- (no lit stones: see the cracks)
	for k = 0, -1 do
		local x = math.floor(hash(k, 6, seed) * (W - 4)) + 2
		local y = 3 + math.floor(hash(k, 7, seed) * math.max(1, bottoms[x + 1] - 6))
		put(g, x + margin, y, R[4]); put(g, x + margin + 1, y, R[4]); put(g, x + margin, y + 1, R[5])
	end
	PixelGrid.rim(g, O)
	-- what hangs from the underside, after the outline: thin dark things need none, and outlined a
	-- pixel at a time a root is three times the rectangles
	local x = 2 + math.floor(hash(1, 9, seed) * 3)
	while x < W - 2 do
		local y0 = bottoms[x + 1] + 2
		local len = 2 + math.floor(hash(x, 11, seed) * (if realm.hang == "lanterns" then 5 else 9))
		if y0 + len < g.h - 2 then hanging(g, realm.hang, x + margin, y0, len, H1, H2, GLOW, seed) end
		x += 4 + math.floor(hash(x, 13, seed) * 6)
	end
	local body = compile(key, g, list, margin, 0)
	return body, RealmArt.surface(realm, width, seed)
end

-- The walking surface of an island: the realm's material, a lip over each end, and the grass that
-- hangs over the rock below it. Full density; anchored at the left end of the surface.
function RealmArt.surface(realm: any, width: number, seed: number): Art
	local key = `realm|{realm.id}|surface|{width}|{seed}`
	local hit = cache[key]
	if hit then return hit end
	local P = RealmArt.PPU
	local ink, list = inks()
	local O = ink(OUTLINE)
	local T = {}
	for i, hex in realm.top do T[i] = ink(hex) end
	local GLOW = ink(realm.glow)
	local W = math.floor(width * P + 0.5)
	local margin = 2
	local top = 2
	local mat = realm.material
	local capR = if mat == "planks" then 4 else 3      -- (the shine replaces the top row: a row more cost the fight's Frame budget)
	local SHINE = ink(mix(realm.top[3], "#FFFFFF", 0.45))
	-- the rock's lit band and shine right under the cap, drawn here at full density (the fighters'
	-- pixel size) rather than in the half-density body: it is the rock a player sees most
	local RB, RS = ink(realm.rock[4]), ink(realm.rock[5])
	local g = PixelGrid.new(W + margin * 2, top + capR + 5)
	for x = 0, W - 1 do
		local gx = x + margin
		for k = 0, capR - 1 do
			-- (the top row lit almost to white: the light band a UI button wears)
			local v = if k == 0 then SHINE elseif k < capR - 1 then T[2] else T[1]
			if mat == "planks" and x % 9 == 0 and k > 0 then v = T[1] end
			if mat == "flagstone" and (x + (if k > 1 then 5 else 0)) % 11 == 0 and k > 0 then v = T[1] end
			if (mat == "ash" or mat == "cavestone") and k > 0 and hash(x, k, seed) > 0.93 then v = GLOW end
			put(g, gx, top + k, v)
		end
		-- grass and sand hang a little over the rock
		if (mat == "grass" or mat == "jade" or mat == "scrub" or mat == "sand") and hash(x // 2, 2, seed) > 0.5 then
			local drip = 1 + math.floor(hash(x // 2, 3, seed) * (if mat == "sand" then 2 else 4))
			for k = 0, drip - 1 do put(g, gx, top + capR + k, T[1]) end
		end
		-- tufts, never more than a pixel high: the surface must still read flat
		if (mat == "grass" or mat == "jade" or mat == "scrub") and hash(x, 4, seed) > 0.75 then
			put(g, gx, top - 1, T[2])
		end
		if mat == "light" then
			-- the Bifrost's deck carries a band of every colour along its edge
			local bands = { "#FF5A5A", "#FFB34A", "#FFE45A", "#5AE08A", "#4AB4FF", "#9A6AFF" }
			put(g, gx, top + capR, ink(bands[(x // 6) % 6 + 1]))
		end
	end
	for k = 0, capR - 1 do
		put(g, margin - 1, top + k, T[2]); put(g, margin + W, top + k, T[2])
	end
	PixelGrid.rim(g, O)
	-- the rock's band after the outline, so no ink line runs under it (with one, the band read as a
	-- board laid on the rock, not the rock's own light band); only where nothing hangs over it
	for x = 0, W - 1 do
		-- (two rows of the lit tone, no shine row: the shine there outshone the walking face above it on
		-- the dark realms, and the top read as two stacked trims)
		local _ = RS
		for k, v in { RB, RB } do
			if get(g, x + margin, top + capR + k - 1) == 0 or get(g, x + margin, top + capR + k - 1) == O then
				put(g, x + margin, top + capR + k - 1, v)
			end
		end
	end
	return compile(key, g, list, margin, top)
end

-- A paved plaza `width` x `depth` studs seen from above at the lobby's angle: rows of flagstones in
-- staggered courses with darker joints and the odd lighter stone, a grass verge along the back.
-- Half density. Anchored at its front-left corner (the bottom-left of the grid).
function RealmArt.paving(realm: any, width: number, depth: number, seed: number): Art
	local key = `realm|{realm.id}|paving|{width}|{depth}|{seed}`
	local hit = cache[key]
	if hit then return hit end
	local P = BODY_PPU
	local ink, list = inks()
	local base, light, joint = ink(mix(realm.rock[4], "#E8DCC4", 0.5)), ink(mix(realm.rock[5], "#FFF4DC", 0.45)),
		ink(mix(realm.rock[4], "#E8DCC4", 0.25))
	local grass, grassL = ink(realm.top[2]), ink(realm.top[3])
	local W, H = math.floor(width * P + 0.5), math.floor(depth * P + 0.5)
	local g = PixelGrid.new(W, H)
	-- broad, low-contrast flagstones: wide stones in deep courses read as a floor seen from above,
	-- where narrow ones in shallow courses read as a wall facing the camera
	local course = 5
	for y = 0, H - 1 do
		local row = y // course
		local off = math.floor(hash(row, 2, seed) * 12)
		for x = 0, W - 1 do
			local stone = (x + off) // 14
			local v = base
			if y % course == course - 1 or (x + off) % 14 == 13 then v = joint
			elseif hash(stone, row, seed) > 0.75 then v = light end
			put(g, x, y, v)
		end
	end
	for x = 0, W - 1 do
		put(g, x, 0, grassL); put(g, x, 1, grass)
		if hash(x, 1, seed) > 0.6 then put(g, x, 2, grass) end
	end
	return compile(key, g, list, 0, H)
end

-- ------------------------------------------------------------------ platforms ----
-- A drop-through platform `width` studs across and `thick` deep, in the realm's style. The anchor
-- is its left end at the walking surface.
function RealmArt.shelf(realm: any, width: number, thick: number, style: string?): Art
	local kind = style or realm.shelf
	local key = `realm|{realm.id}|shelf|{kind}|{width}|{thick}`
	local hit = cache[key]
	if hit then return hit end
	local P = RealmArt.PPU
	local ink, list = inks()
	local O = ink(OUTLINE)
	local S1, S2, S3 = ink(realm.shelfRamp[1]), ink(realm.shelfRamp[2]), ink(realm.shelfRamp[3])
	local A, GLOW = ink(realm.accent), ink(realm.glow)
	local W = math.floor(width * P + 0.5)
	-- (at least 6 rows: a face, a light band and shine over it, a dark lip under it - a UI button's
	-- anatomy - where 4 rows read as a thin stick against the sky)
	-- (a forge's iron girders stay thin: their truss pattern grows a row of rectangles with every row)
	local T = math.max(if kind == "iron" then 4 else 6, math.floor(thick * P + 0.5))
	local m = 2
	local below = 9
	local g = PixelGrid.new(W + m * 2, 1 + T + below)
	local y0 = 1
	local SH, LIP = ink(mix(realm.shelfRamp[3], "#FFFFFF", 0.4)), ink(mix(realm.shelfRamp[1], "#000000", 0.25))
	PixelGrid.rect(g, m, y0, W, T, S2)
	PixelGrid.rect(g, m, y0, W, 1, SH)
	PixelGrid.rect(g, m, y0 + 1, W, 1, S3)
	PixelGrid.rect(g, m, y0 + T - 1, W, 1, LIP)
	if kind == "wood" or kind == "minecart" then
		for x = 0, W - 1 do
			if (x + (x // 23)) % 8 == 0 then
				for y = y0 + 1, y0 + T - 2 do put(g, m + x, y, S1) end
			elseif x % 8 == 3 then
				put(g, m + x, y0 + 1, S3)
			end
		end
		-- brackets under each end
		for _, bx in { m + 3, m + W - 4 } do
			for k = 0, 4 do
				put(g, bx + (if bx < m + W / 2 then k else -k), y0 + T + k, S1)
				put(g, bx, y0 + T + k, S1)
			end
		end
		if kind == "minecart" then
			-- the lift rides on a rail: wheels under each end
			for _, wx in { m + 6, m + W - 7 } do
				PixelGrid.ellipse(g, wx, y0 + T + 3, 3, 3, S1)
				put(g, wx, y0 + T + 3, S3)
			end
			PixelGrid.rect(g, m + 2, y0 + T, W - 4, 1, O)
		end
	elseif kind == "stone" or kind == "sandstone" then
		for x = 0, W - 1 do
			if (x + 6) % 12 == 0 then
				for y = y0 + 1, y0 + T - 2 do put(g, m + x, y, S1) end
			end
			if kind == "sandstone" and x % 12 == 3 and T > 4 then put(g, m + x, y0 + 2, A) end
		end
		for _, bx in { m + 2, m + W - 5 } do
			PixelGrid.rect(g, bx, y0 + T, 3, 3, S1)
			PixelGrid.rect(g, bx + 1, y0 + T + 3, 1, 2, S1)
		end
	elseif kind == "iron" then
		-- (the light band kept, rivets on it: a dark row over it left the girder a thin line)
		for x = 0, W - 1, 6 do put(g, m + x + 2, y0 + 1, S1) end
		for x = 0, W - 1 do
			local d = x % 8
			if T > 4 then put(g, m + x, y0 + 2 + math.min(d, 7 - d) * (T - 4) // 4, S1) end
		end
		-- chains up from each end: a girder hung from the forge's cranes
		for _, bx in { m + 2, m + W - 3 } do
			put(g, bx, 0, S1)
		end
	elseif kind == "temple" then
		PixelGrid.rect(g, m, y0, W, 1, A)
		-- the eaves turn up at each end
		put(g, m - 1, y0 - 1 + 1, A); put(g, m - 2, y0 - 1, A); put(g, m + W, y0, A); put(g, m + W + 1, y0 - 1, A)
		for x = 6, W - 6, 10 do
			for k = 0, 3 do put(g, m + x, y0 + T + k, A) end
			put(g, m + x, y0 + T + 4, GLOW)
		end
	elseif kind == "obsidian" then
		for x = 0, W - 1 do
			if x % 9 < 2 then put(g, m + x, y0 + 1 + (x % 9), S3) end
		end
		for x = 4, W - 4, 13 do
			put(g, m + x, y0 + T - 2, GLOW); put(g, m + x + 1, y0 + T - 2, GLOW)
		end
	end
	PixelGrid.rim(g, O)
	return compile(key, g, list, m, y0)
end

-- ------------------------------------------------------------------ the stage ----
-- The stage in its realm. Solids are islands, everything else is a platform; ledges, the sinking
-- warning and where everything is are the Stage's (see Stage2D, which calls this).
function RealmArt.stage(c: any, stage: any, realm: any)
	local P = RealmArt.PPU
	local cell = 1 / P
	for i, sp in stage.solids do
		local w = sp.x2 - sp.x1
		local body, surface = RealmArt.island(realm, w, math.max(sp.thickness or 6, if sp == stage.main then 7 else 4), i)
		draw(c, body, sp.x1, sp.top, 1 / BODY_PPU)
		draw(c, surface, sp.x1, sp.top, cell)
	end
	for _, pl in stage.platforms do
		if not pl.solid then
			local style = if pl.moving and pl.moving.x and realm.shelf == "minecart" then "minecart"
				elseif realm.shelf == "minecart" then "wood" else nil
			local art = RealmArt.shelf(realm, pl.x2 - pl.x1, pl.thickness or 1, style)
			draw(c, art, pl.x1, pl.top, cell)
		end
	end
end

-- ------------------------------------------------------------------ skies ----
-- A sky layer is a 240 x 135 grid (one backbuffer tile at SKY_PX) that tiles sideways.
local SW, SH = TILE_W // SKY_PX, TILE_H // SKY_PX

-- A seamless ridge line: a sum of whole sine periods across the tile, so the two ends meet.
local function ridge(x: number, seed: number, base: number, amp: number): number
	local v = 0
	for k = 1, 4 do
		local ph = hash(k, 1, seed) * math.pi * 2
		v += math.sin(x / SW * math.pi * 2 * k + ph) * amp / k
	end
	return base - v
end

local function cloud(g: PixelGrid.Grid, cx: number, cy: number, size: number, C: { number }, seed: number)
	local puffs = 3 + math.floor(hash(cx, cy, seed) * 3)
	for i = 0, puffs - 1 do
		local px = cx + (i - (puffs - 1) / 2) * size * 0.7
		local r = size * (0.55 + 0.45 * math.sin((i + 0.5) / puffs * math.pi))
		PixelGrid.ellipse(g, px, cy - r * 0.35, r, r * 0.8, C[2])
	end
	-- shadow along the bottom, light along the top
	for x = math.floor(cx - size * puffs * 0.5), math.ceil(cx + size * puffs * 0.5) do
		local topY, botY = -1, -1
		for y = 0, SH - 1 do
			if get(g, (x % SW), y) == C[2] then
				if topY < 0 then topY = y end
				botY = y
			end
		end
		if topY >= 0 and botY - topY > 2 then
			put(g, x % SW, botY, C[1]); put(g, x % SW, botY - 1, C[1])
			put(g, x % SW, topY, C[3])
		end
	end
end

-- A distant floating island, as a silhouette with a lit top.
local function farIsland(g: PixelGrid.Grid, cx: number, cy: number, w: number, body: number, lit: number, topC: number, seed: number)
	for x = math.floor(cx - w / 2), math.floor(cx + w / 2) do
		local u = (x - (cx - w / 2)) / w
		local prof = (1 - math.abs(2 * u - 1)) ^ 0.7
		local depth = math.floor(3 + w * 0.45 * prof + (hash(x, 1, seed) - 0.5) * 3 * prof)
		-- (one flat tone: with a lit row and a surface colour, a distant island under a landmark read
		-- as more stage - on TheSpan flush with the deck, on Foundry joining two platforms into a floor)
		local _ = lit; local _ = topC
		for y = 0, depth do put(g, x % SW, cy + y, body) end
	end
end

-- Each landmark is drawn into the middle of its tile, standing on y = base.
local landmarks: { [string]: (PixelGrid.Grid, (string, number?) -> number, any, number) -> () } = {}

landmarks.hall = function(g, ink, realm, base)
	local isle = ink(mix(realm.far, realm.sky[3], 0.2))
	farIsland(g, 120, base, 120, isle, ink(mix(realm.rock[4], realm.sky[3], 0.3)), ink(mix(realm.top[2], realm.sky[3], 0.3)), 4)
	local wood, gold, goldL, dark = ink(mix("#7A4A2A", realm.sky[3], 0.25)), ink(mix("#E8A61C", realm.sky[3], 0.2)),
		ink(mix("#FFE07A", realm.sky[3], 0.2)), ink(mix("#3A2416", realm.sky[3], 0.25))
	-- a great hall: timber walls, a golden roof with crossed gable horns, shields along the wall
	PixelGrid.rect(g, 78, base - 26, 84, 26, wood)
	for x = 80, 160, 6 do PixelGrid.rect(g, x, base - 26, 1, 26, dark) end
	PixelGrid.poly(g, { { 68, base - 24 }, { 120, base - 58 }, { 172, base - 24 } }, gold)
	PixelGrid.line(g, 70, base - 25, 120, base - 57, goldL)
	PixelGrid.line(g, 70, base - 24, 170, base - 24, dark)
	PixelGrid.line(g, 108, base - 66, 120, base - 57, dark); PixelGrid.line(g, 132, base - 66, 120, base - 57, dark)
	PixelGrid.rect(g, 112, base - 16, 16, 16, dark)
	PixelGrid.rect(g, 115, base - 13, 10, 13, ink(mix(realm.glow, realm.sky[3], 0.1)))
	for i, col in { "#C43A3A", "#3A6AC4", "#E8A61C", "#C43A3A", "#3A6AC4", "#E8A61C" } do
		local x = 86 + (i - 1) * 12 + (if i > 3 then 20 else 0)
		PixelGrid.ellipse(g, x, base - 14, 4, 4, ink(mix(col, realm.sky[3], 0.2)))
		put(g, x, base - 14, ink(mix("#E8E0D0", realm.sky[3], 0.2)))
	end
	for _, px in { 60, 180 } do
		PixelGrid.rect(g, px, base - 40, 1, 40, dark)
		PixelGrid.poly(g, { { px + 1, base - 40 }, { px + 10, base - 40 }, { px + 10, base - 26 }, { px + 5, base - 29 }, { px + 1, base - 26 } },
			ink(mix(realm.accent, realm.sky[3], 0.2)))
	end
end

landmarks.rainbow = function(g, ink, realm, base)
	local bands = { "#FF5A5A", "#FFB34A", "#FFE45A", "#5AE08A", "#4AB4FF", "#9A6AFF" }
	-- in rows of two: an arc is a staircase either way, and pairs of rows merge into half the
	-- rectangles
	for y = 0, SH - 1, 2 do
		for x = 0, SW - 1 do
			local d = math.sqrt((x - 120) ^ 2 + (y + 1 - 150) ^ 2)
			local b = math.floor((d - 92) / 3)
			if b >= 0 and b < 6 then
				local v = ink(mix(bands[6 - b], realm.sky[2], 0.35), 0.85)
				put(g, x, y, v); put(g, x, y + 1, v)
			end
		end
	end
	-- the aurora above it
	for x = 0, SW - 1, 2 do
		local y = math.floor(22 + math.sin(x / SW * math.pi * 4) * 6 + math.sin(x / SW * math.pi * 2 + 1) * 4)
		for k = 0, 5 do
			local v = ink(mix(realm.glow, realm.sky[1], k / 7), 0.4)
			put(g, x, y + k, v); put(g, x + 1, y + k, v)
		end
	end
	-- (no flanking islands: they sat flush with the deck and read as more stage)
end

landmarks.forge = function(g, ink, realm, base)
	local mount, lit = ink(mix("#2A1418", realm.sky[3], 0.15)), ink(mix("#5A2A2A", realm.sky[3], 0.15))
	PixelGrid.poly(g, { { 50, base + 20 }, { 104, base - 52 }, { 124, base - 46 }, { 146, base - 58 }, { 196, base + 20 } }, mount)
	PixelGrid.line(g, 104, base - 52, 124, base - 46, lit); PixelGrid.line(g, 124, base - 46, 146, base - 58, lit)
	local door, hot = ink("#FF8A3A"), ink("#FFE0A0")
	for _, dx in { 100, 136 } do
		PixelGrid.ellipse(g, dx, base - 6, 6, 8, door)
		PixelGrid.rect(g, dx - 6, base - 6, 13, 9, door)
		PixelGrid.ellipse(g, dx, base - 4, 3, 4, hot)
	end
	local smoke = ink(mix("#5A4A4A", realm.sky[2], 0.4), 0.8)
	for _, cx in { 116, 132 } do
		PixelGrid.rect(g, cx, base - 70, 5, 16, mount)
		for k = 0, 3 do PixelGrid.ellipse(g, cx + 2 + k * 5, base - 76 - k * 9, 5 + k * 2, 4 + k, smoke) end
	end
	PixelGrid.rect(g, 0, base + 18, SW, 2, ink("#FF8A3A", 0.8))
end

landmarks.pagoda = function(g, ink, realm, base)
	local isle = ink(mix(realm.far, realm.sky[3], 0.25))
	farIsland(g, 120, base, 70, isle, ink(mix(realm.rock[4], realm.sky[3], 0.3)), ink(mix(realm.top[2], realm.sky[3], 0.3)), 7)
	local wall, roof, roofL = ink(mix("#E8D8B8", realm.sky[3], 0.25)), ink(mix("#B8322A", realm.sky[3], 0.2)), ink(mix("#E8584A", realm.sky[3], 0.2))
	for tier = 0, 2 do
		local w = 34 - tier * 8
		local y = base - 2 - tier * 16
		PixelGrid.rect(g, 120 - w / 2 + 4, y - 10, w - 8, 10, wall)
		PixelGrid.poly(g, { { 120 - w / 2 - 6, y - 10 }, { 120 + w / 2 + 6, y - 10 }, { 120 + w / 2 - 2, y - 15 }, { 120 - w / 2 + 2, y - 15 } }, roof)
		PixelGrid.line(g, 120 - w / 2 - 6, y - 10, 120 - w / 2 - 8, y - 12, roof)
		PixelGrid.line(g, 120 + w / 2 + 6, y - 10, 120 + w / 2 + 8, y - 12, roof)
		PixelGrid.line(g, 120 - w / 2 + 2, y - 15, 120 + w / 2 - 2, y - 15, roofL)
	end
	PixelGrid.rect(g, 119, base - 56, 2, 8, roof)
	local pink, pinkL, trunk = ink(mix("#F29AB8", realm.sky[3], 0.2)), ink(mix("#FFD2E0", realm.sky[3], 0.2)), ink(mix("#5A3A2A", realm.sky[3], 0.25))
	for _, tx in { 88, 152 } do
		PixelGrid.rect(g, tx, base - 12, 2, 12, trunk)
		PixelGrid.ellipse(g, tx + 1, base - 16, 9, 6, pink)
		PixelGrid.ellipse(g, tx - 2, base - 19, 4, 3, pinkL)
	end
end

landmarks.pyramid = function(g, ink, realm, base)
	local lit, shade = ink(mix("#E8B878", realm.sky[3], 0.25)), ink(mix("#B07A48", realm.sky[3], 0.25))
	local lit2, shade2 = ink(mix("#E8B878", realm.sky[3], 0.45)), ink(mix("#B07A48", realm.sky[3], 0.45))
	PixelGrid.poly(g, { { 140, base + 4 }, { 176, base - 34 }, { 212, base + 4 } }, shade2)
	PixelGrid.poly(g, { { 140, base + 4 }, { 176, base - 34 }, { 170, base + 4 } }, lit2)
	PixelGrid.poly(g, { { 48, base + 6 }, { 104, base - 54 }, { 160, base + 6 } }, shade)
	PixelGrid.poly(g, { { 48, base + 6 }, { 104, base - 54 }, { 94, base + 6 } }, lit)
	PixelGrid.rect(g, 99, base - 8, 8, 14, ink(mix("#3A2416", realm.sky[3], 0.3)))
	local trunk, frond = ink(mix("#6A4A2A", realm.sky[3], 0.2)), ink(mix("#3E8A3A", realm.sky[3], 0.2))
	for _, px in { 30, 222 } do
		for k = 0, 22 do put(g, px + math.floor(k / 8), base + 6 - k, trunk) end
		for a = 0, 4 do
			local ang = (a / 4) * math.pi + math.pi
			PixelGrid.line(g, px + 3, base - 17, px + 3 + math.cos(ang) * 10, base - 17 + math.sin(ang) * -4 + 4, frond)
		end
	end
	PixelGrid.rect(g, 0, base + 6, SW, SH - base - 6, ink(mix(realm.top[2], realm.sky[3], 0.35)))
end

landmarks.longship = function(g, ink, realm, base)
	local mount = ink(mix("#4A6A8A", realm.sky[3], 0.3))
	for x = 0, SW - 1 do
		local y = math.floor(ridge(x, 12, base - 26, 18))
		for yy = y, base + 4 do put(g, x, yy, mount) end
		put(g, x, y, ink(mix("#E8F0F8", realm.sky[3], 0.2)))
	end
	local sea, foam = ink(mix("#2E6A9A", realm.sky[3], 0.15)), ink(mix("#A8D8EC", realm.sky[3], 0.1))
	PixelGrid.rect(g, 0, base + 4, SW, SH - base - 4, sea)
	for x = 0, SW - 1, 6 do put(g, x + (x // 6) % 3, base + 8 + (x // 6) % 5 * 4, foam) end
	local hull, sail, sailS = ink(mix("#5A3A22", realm.sky[3], 0.2)), ink(mix("#F2ECE0", realm.sky[3], 0.15)), ink(mix("#C43A3A", realm.sky[3], 0.15))
	for _, sx in { 70, 170 } do
		PixelGrid.poly(g, { { sx - 22, base }, { sx + 22, base }, { sx + 16, base + 6 }, { sx - 16, base + 6 } }, hull)
		PixelGrid.line(g, sx + 22, base, sx + 26, base - 7, hull); PixelGrid.line(g, sx - 22, base, sx - 25, base - 6, hull)
		PixelGrid.rect(g, sx, base - 26, 1, 26, hull)
		PixelGrid.rect(g, sx - 10, base - 24, 21, 15, sail)
		for k = 0, 2 do PixelGrid.rect(g, sx - 10, base - 22 + k * 5, 21, 2, sailS) end
		for k = -16, 14, 6 do PixelGrid.ellipse(g, sx + k, base + 1, 2, 2, sailS) end
	end
end

landmarks.crystals = function(g, ink, realm, base)
	local function spire(cx: number, h: number, w: number, col: string)
		local body, lit, dark = ink(mix(col, realm.sky[2], 0.3)), ink(mix("#FFFFFF", col, 0.4)), ink(mix(col, "#000000", 0.35))
		PixelGrid.poly(g, { { cx - w, base + 6 }, { cx - w, base - h + w }, { cx, base - h }, { cx + w, base - h + w }, { cx + w, base + 6 } }, body)
		PixelGrid.poly(g, { { cx - w, base + 6 }, { cx - w, base - h + w }, { cx, base - h }, { cx - w * 0.3, base + 6 } }, lit)
		PixelGrid.line(g, cx + w, base - h + w, cx + w, base + 6, dark)
	end
	spire(80, 62, 9, "#3AC8E8")
	spire(98, 40, 6, "#9A6AFF")
	spire(146, 74, 11, "#7A5AFF")
	spire(170, 44, 7, "#3AE8C8")
	spire(40, 30, 5, "#9A6AFF")
	spire(206, 36, 6, "#3AC8E8")
	PixelGrid.rect(g, 0, base + 6, SW, SH - base - 6, ink(realm.near))
end

landmarks.storm = function(g, ink, realm, base)
	local rock, lit = ink(mix("#7A3A24", realm.sky[3], 0.3)), ink(mix("#C46A3A", realm.sky[3], 0.3))
	for _, m in { { 50, 60, 44 }, { 150, 48, 70 }, { 214, 30, 36 } } do
		local cx, h, w = m[1], m[2], m[3]
		PixelGrid.poly(g, { { cx - w / 2 - 6, base + 10 }, { cx - w / 2, base - h }, { cx + w / 2, base - h }, { cx + w / 2 + 6, base + 10 } }, rock)
		PixelGrid.rect(g, cx - w / 2, base - h, w, 2, lit)
		PixelGrid.rect(g, cx - w / 2 + 2, base - h + 12, w - 4, 1, lit)
	end
	local storm = ink(mix(realm.cloud[1], realm.sky[1], 0.3), 0.85)
	for x = 0, SW - 1 do
		local y = math.floor(ridge(x, 21, 18, 7))
		for yy = 0, y do put(g, x, yy, storm) end
	end
end

landmarks.volcano = function(g, ink, realm, base)
	local cone, lit = ink(mix("#2A1414", realm.sky[3], 0.1)), ink(mix("#5A2A22", realm.sky[3], 0.1))
	PixelGrid.poly(g, { { 30, base + 10 }, { 104, base - 66 }, { 136, base - 66 }, { 210, base + 10 } }, cone)
	PixelGrid.poly(g, { { 30, base + 10 }, { 104, base - 66 }, { 112, base - 66 }, { 70, base + 10 } }, lit)
	local lava, hot = ink("#FF6A2A"), ink("#FFD27A")
	PixelGrid.rect(g, 104, base - 68, 33, 3, hot)
	for _, path in { { 110, 0.7 }, { 128, -0.5 } } do
		local x = path[1]
		-- (down the upper cone only: to its foot, the streaks ran behind the centre platform)
		for y = base - 65, base - 34 do
			put(g, math.floor(x), y, lava)
			x += path[2] * 0.4 + (hash(y, 1, 9) - 0.5) * 0.8
		end
	end
	local smoke = ink(mix("#3A2A2A", realm.sky[2], 0.3), 0.85)
	for k = 0, 5 do PixelGrid.ellipse(g, 120 + k * 6, base - 76 - k * 9, 8 + k * 2, 5 + k, smoke) end
end

-- The sky's tiled layers for a realm: far ridge, landmark, near islands, clouds. Each is an Art
-- whose cells are SKY_PX backbuffer units.
local function layer(realm: any, which: string): Art
	local key = `realm|{realm.id}|sky|{which}`
	local hit = cache[key]
	if hit then return hit end
	local ink, list = inks()
	local g = PixelGrid.new(SW, SH)
	local base = 96
	if which == "far" then
		-- (through RealmArt.backdrop, as every layer behind the fight: hazed to the mid sky, never lighter
		-- than the island's lit rock; one flat tone - its lit edge cost a rectangle a step, and the fight's
		-- warm-up went over its per-tick budget)
		local col = ink(RealmArt.backdrop(realm, realm.far, 0.2))
		for x = 0, SW - 1 do
			local y = math.floor(ridge(x, 3, base - 6, 14))
			for yy = y, SH - 1 do put(g, x, yy, col) end
		end
	elseif which == "landmark" then
		-- hazed (RealmArt.backdrop): the landmark is scenery, and at full strength - or hazed toward the
		-- pale horizon - it was the brightest thing on screen, brighter than the island the fight is on
		local fn = landmarks[realm.landmark]
		local haze = function(hex: string, a: number?): number return ink(RealmArt.backdrop(realm, hex, 0.35), a) end
		if fn then fn(g, haze, realm, base + 8) end
	elseif which == "near" then
		-- (none now: drawn as islands they read as platforms at play height, the same three in all nine
		-- skies; as hazed silhouettes they hung behind the high platforms. The far ridge and the
		-- landmark carry the depth.)
		local _ = farIsland
	elseif which == "storm" then
		-- a lid of storm cloud across the top of the sky: the realm's own cloud colours, darkened,
		-- for a disaster that comes from above (DisasterArt)
		local C = { ink(mix(realm.cloud[1], "#14141E", 0.65)), ink(mix(realm.cloud[1], "#24243A", 0.45)),
			ink(mix(realm.cloud[2], "#3A3A54", 0.45)) }
		for x = 0, SW - 1 do
			local y = math.floor(ridge(x, 41, 26, 6))
			for yy = 0, y do put(g, x, yy, if yy >= y - 1 then C[3] elseif yy > y - 5 then C[2] else C[1]) end
		end
		for k = 0, 7 do cloud(g, 15 + k * 30, 30 + (k % 3) * 4, 6 + (k % 2) * 2, C, 30 + k) end
	elseif which == "clouds" then
		local C = { ink(realm.cloud[1]), ink(realm.cloud[2]), ink(realm.cloud[3]) }
		-- placed by the realm (the same four clouds were in all nine skies, one behind the fighters'
		-- heads), and all above the band the fight is seen against
		local h = 0
		for k = 1, #realm.id do h = (h * 37 + string.byte(realm.id, k)) % 9973 end
		-- (sizes and rows varied per realm too: one triad shifted sideways read as the same sky; three,
		-- since a fourth cloud took the fight's warm-up over its per-tick budget)
		local n = 3
		for k = 1, n do
			local x = math.floor((k - 0.5 + (hash(k, 31, h) - 0.5) * 0.6) * SW / n)
			cloud(g, x, 16 + math.floor(hash(k, 32, h) * 32), 6 + math.floor(hash(k, 33, h) * 7), C, k)
		end
	end
	return compile(key, g, list, 0, 0)
end
RealmArt.layer = layer

-- name, parallax (backbuffer units per stud of camera), drift (units a second)
local tiles: (any, Art, number, number) -> ()
-- (no "near" floating islands: see layer)
local LAYERS: { { any } } = { { "far", 0.03, 0 }, { "landmark", 0.06, 0 }, { "clouds", 0.15, 2.4 } }

-- One sky layer tiled across the screen, shifted `shift` backbuffer units, in backbuffer units with
-- y up from the bottom of the screen.
tiles = function(c: any, art: Art, shift: number, alpha: number)
	if #art.rects == 0 or alpha <= 0 then return end
	local vp = Canvas2D.viewport(c)
	local s = vp.Y / TILE_H
	local width = vp.X / s
	Canvas2D.setTransform(c, s, 0, 0, -s, 0, vp.Y)
	local x = math.floor(shift / TILE_W) * TILE_W - shift
	while x < width do
		-- overlapping layers only add up exactly at full opacity (a storm lid fading in is not)
		if alpha >= 1 and (c.alpha or 1) >= 1 then
			Canvas2D.sprite(c, art.stackKey, art.stack, x, TILE_H, SKY_PX, SKY_PX, art.cols, art.rows, alpha)
		else
			Canvas2D.sprite(c, art.key, art.rects, x, TILE_H, SKY_PX, SKY_PX, art.cols, art.rows, alpha)
		end
		x += TILE_W
	end
end

-- The realm's sky, behind everything: the gradient and the sun in screen space, then the tiled
-- layers, each parallaxed to the camera (and the clouds drifting on their own).
local SKY_BANDS = 30
local gradients: { [any]: { Color3 } } = setmetatable({}, { __mode = "k" }) :: any
local function gradient(stops: { string }): { Color3 }
	local hit = gradients[stops]
	if hit then return hit end
	local colours: { Color3 } = {}
	for i = 0, SKY_BANDS - 1 do
		local at = (i + 0.5) / SKY_BANDS * (#stops - 1)
		local k = math.min(#stops - 1, math.floor(at) + 1)
		colours[i + 1] = Canvas2D.hex(mix(stops[k], stops[k + 1], at - (k - 1)), Color3.new(1, 1, 1))
	end
	gradients[stops] = colours
	return colours
end

function RealmArt.sky(c: any, realm: any, camX: number, t: number?)
	local vp = Canvas2D.viewport(c)
	if vp.Y <= 0 then return end
	local now = t or 0
	Canvas2D.screen(c)
	-- The palette is immutable realm data. Camera and viewport changes only place these bands;
	-- there is no need to mix hex strings and parse the same colours every render frame.
	local colours, N = gradient(realm.sky), SKY_BANDS
	for i = 0, N - 1 do
		Canvas2D.rect(c, 0, i * vp.Y / N, vp.X, vp.Y / N + 1, colours[i + 1])
	end
	local s = vp.Y / TILE_H
	local width = vp.X / s
	local sun = realm.sun
	local sx = (sun.x * width - camX * 0.01) * s
	local sy = sun.y * vp.Y
	Canvas2D.ellipse(c, sx, sy, sun.r * 2.4 * s, sun.r * 2.4 * s, Canvas2D.hex(sun.glow, Color3.new(1, 1, 1)), 0.22)
	Canvas2D.ellipse(c, sx, sy, sun.r * 1.5 * s, sun.r * 1.5 * s, Canvas2D.hex(sun.glow, Color3.new(1, 1, 1)), 0.35)
	Canvas2D.ellipse(c, sx, sy, sun.r * s, sun.r * s, Canvas2D.hex(sun.colour, Color3.new(1, 1, 1)), 1)
	for _, L in LAYERS do
		tiles(c, layer(realm, L[1]), camX * L[2] + now * L[3], 1)
	end
	Canvas2D.screen(c)
end

-- A sky layer over the scene, faded in by `alpha`: a disaster's storm lid. Leaves the screen
-- transform installed; the caller restores its own.
function RealmArt.overlay(c: any, realm: any, which: string, camX: number, t: number, alpha: number)
	if Canvas2D.viewport(c).Y <= 0 then return end
	tiles(c, layer(realm, which), camX * 0.12 + t * 1.5, alpha)
	Canvas2D.screen(c)
end

-- ------------------------------------------------------------------ weather ----
-- Each realm's air: a few dozen particles drifting through the fight, anchored to the world (they
-- wrap round a box about the camera, so the density never changes and nothing is stuck to the
-- screen). The web build's stages name an ambient kind; Roblox never drew one until the realms.
--   colours, count, velocity (studs/s), size, sway, twinkle
local AIR: { [string]: any } = {
	FoundryFloor = { colours = { "#FFE07A", "#FFF4C4" }, n = 22, vx = 0.6, vy = 1.2, w = 0.25, h = 0.25, sway = 0.6, twinkle = true },
	TheSpan = { colours = { "#FF5A5A", "#FFE45A", "#5AE08A", "#4AB4FF", "#9A6AFF", "#FFFFFF" }, n = 24, vx = 3, vy = 0.3,
		w = 0.3, h = 0.3, sway = 0.4, twinkle = true },
	Smeltworks = { colours = { "#FFB43C", "#FF7A3C", "#FFE89A" }, n = 26, vx = 0.8, vy = 3, w = 0.22, h = 0.3, sway = 0.8 },
	Rooftops = { colours = { "#F29AB8", "#FFD2E0", "#E87AA0" }, n = 22, vx = 2.2, vy = -1.6, w = 0.4, h = 0.24, sway = 1.2 },
	Saltflat = { colours = { "#E8C877", "#D2A04E", "#FFE8AA" }, n = 30, vx = 9, vy = -0.3, w = 0.7, h = 0.12, sway = 0.2 },
	Undertow = { colours = { "#FFFFFF", "#D8F0FA" }, n = 22, vx = 1.6, vy = 0.5, w = 0.2, h = 0.2, sway = 0.5, twinkle = true },
	FreightLift = { colours = { "#3AE8C8", "#9A6AFF", "#C8FAFF" }, n = 22, vx = 0.3, vy = 0.5, w = 0.25, h = 0.25, sway = 0.3, twinkle = true },
	Faultline = { colours = { "#B46E46", "#D89466", "#8A4E32" }, n = 26, vx = 7, vy = -0.4, w = 0.6, h = 0.14, sway = 0.3 },
	AshfallSummit = { colours = { "#8A7670", "#5E4E4A", "#FF9A3A" }, n = 30, vx = 0.9, vy = -1.4, w = 0.3, h = 0.3, sway = 0.8 },
}
RealmArt.AIR = AIR

-- Draws the realm's weather in world space round (cx, cy), over a view `w` x `h` studs.
function RealmArt.weather(c: any, realm: any, cx: number, cy: number, w: number, h: number, t: number)
	local air = AIR[realm.id]
	if not air then return end
	local W, H = w + 6, h + 6
	local x0, y0 = cx - W / 2, cy - H / 2
	for i = 0, air.n - 1 do
		local u, v = hash(i, 1, 11), hash(i, 2, 11)
		local speed = 0.6 + hash(i, 3, 11) * 0.8
		local x = x0 + (((u * W + air.vx * speed * t - x0) % W) + W) % W
		local y = y0 + (((v * H + air.vy * speed * t - y0) % H) + H) % H
		x += math.sin(t * 1.3 + i) * air.sway
		local alpha = if air.twinkle then 0.35 + 0.65 * math.max(0, math.sin(t * 2.5 + i * 1.7)) else 0.85
		local col = Canvas2D.hex(air.colours[(i % #air.colours) + 1], Color3.new(1, 1, 1))
		Canvas2D.rect(c, x, y, air.w, air.h, col, alpha)
	end
end

-- Builds every sprite a realm's stage will draw, so the first frame of a match does not pay for it.
function RealmArt.warm(realm: any, stage: any)
	for _, which in LAYERS do layer(realm, which[1]) end
	for i, sp in stage.solids do
		RealmArt.island(realm, sp.x2 - sp.x1, math.max(sp.thickness or 6, if sp == stage.main then 7 else 4), i)
	end
	for _, pl in stage.platforms do
		if not pl.solid then RealmArt.shelf(realm, pl.x2 - pl.x1, pl.thickness or 1) end
	end
end

return RealmArt
