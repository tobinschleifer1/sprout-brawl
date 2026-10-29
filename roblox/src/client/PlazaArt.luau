--!strict
-- The Skyhold Bazaar's props, as pixel art: built once in eighth-of-a-stud cells and drawn
-- as sprites (Canvas2D.sprite), so a stall of two hundred rectangles costs one Frame a frame.
--
-- Each builder draws in the prop's own cell space, y UP from the prop's base, x from its left edge,
-- with `r(x, y, w, h, hex, alpha)`; `done()` converts to the sprite convention (rows down from the
-- top). A prop is { rects, w, h } in cells; PlazaArt.draw places its base-centre at a world point.
--
-- Palette: daylight in the Skyhold Bazaar - see C below.

local Canvas2D = require(script.Parent.Canvas2D)

local PlazaArt = {}
PlazaArt.CELL = 1 / 8
-- the stall sign board's face, behind its lettering
PlazaArt.SIGN_FACE = "#2C3A58"

local C: { [string]: string } = {
	-- Daylight in the Skyhold Bazaar (Realms.LOBBY): warm timber, sun-bleached stone, bright
	-- awnings in the realms' reds, blues and golds. The names are where each colour sits, not what
	-- it is - `night` is a sign board's face, `tar` the paving, `pink` the red awning stripe.
	ink = "#120E16", night = "#2C3A58", slate = "#8C7B66", slateHi = "#B8A68A", tar = "#A89A86", tarHi = "#C4B8A2",
	steel = "#8A94A6", steelHi = "#C8D0DC", rust = "#B4462E", wood = "#A0683A", woodHi = "#D49A5C", woodDk = "#6B3F22",
	pink = "#E04848", pinkDk = "#8E2424", pinkDeep = "#4E1620", cyan = "#3A8AD8", cyanDk = "#1E4A8A", cyanDeep = "#14284E", amber = "#FFC83A", amberDk = "#C47A1A",
	lantern = "#FF7A3A", lanternHi = "#FFD27A", teal = "#2ECCAA", tealHi = "#8AF0D8", tealDk = "#1A7A66",
	indigo = "#464A96", indigoHi = "#7E82CC", indigoDk = "#2A2C5E", indigoWall = "#5A5C96", violet = "#9668FF", plaster = "#A7A9DA", plasterHi = "#CDCEF0", plasterDk = "#8F91C6", paper = "#F4ECD8", glass = "#3A5A7A", white = "#FFFFFF", green = "#5AB447",
}
PlazaArt.C = C

local function builder(w: number, h: number)
	local list: { any } = {}
	local b = {}
	function b.r(x: number, y: number, rw: number, rh: number, hex: string, alpha: number?)
		if rw <= 0 or rh <= 0 then return end
		table.insert(list, { x, h - y - rh, rw, rh, hex, alpha or 1 } :: { any })
	end
	-- `outlined`: an ink line a cell wide round the prop's silhouette, as the fighters and the
	-- islands have (and not under its base, which stands on the paving). Bare, the props were flat
	-- colour on the pale paving and sky with no edge - a second hand beside the outlined fighters.
	function b.done(outlined: boolean?): any
		if not outlined then return { rects = list, w = w, h = h } end
		return PlazaArt.outline({ rects = list, w = w, h = h })
	end
	return b
end

-- A prop's silhouette outlined in ink: one cell all round but the bottom, the prop moved in by a cell
-- and the outline merged into runs along each row. Cells under a mostly see-through rectangle (a
-- glow, a shadow) are not silhouette.
function PlazaArt.outline(prop: any): any
	local W, H = prop.w, prop.h
	local solid: { [number]: boolean } = {}
	for _, r in prop.rects do
		if (r[6] or 1) >= 0.8 then
			for y = r[2], r[2] + r[4] - 1 do
				for x = r[1], r[1] + r[3] - 1 do solid[y * W + x] = true end
			end
		end
	end
	local function at(x: number, y: number): boolean
		return x >= 0 and y >= 0 and x < W and y < H and solid[y * W + x] == true
	end
	local out: { any } = {}
	-- (rows top-down; the new sprite is a cell wider each side and a cell taller on top)
	for y = -1, H - 1 do
		local x = -1
		while x <= W do
			local edge = not at(x, y) and (at(x - 1, y) or at(x + 1, y) or at(x, y - 1) or at(x, y + 1))
			if edge then
				local run = 1
				while x + run <= W do
					local nx = x + run
					if at(nx, y) or not (at(nx - 1, y) or at(nx + 1, y) or at(nx, y - 1) or at(nx, y + 1)) then break end
					run += 1
				end
				table.insert(out, { x + 1, y + 1, run, 1, C.ink, 1 } :: { any })
				x += run
			else
				x += 1
			end
		end
	end
	for _, r in prop.rects do
		table.insert(out, { r[1] + 1, r[2] + 1, r[3], r[4], r[5], r[6] } :: { any })
	end
	return { rects = out, w = W + 2, h = H + 1 }
end

-- -------------------------------------------------------------------- stalls ----
-- A market stall in two halves, so a vendor can stand between them: the back (posts, awning,
-- lanterns, back shelf) and the front (the counter and its goods).
function PlazaArt.stallBack(stripeA: string, stripeB: string): any
	local W, H = 96, 84
	local b = builder(W, H)
	b.r(2, 0, 3, 70, C.woodDk); b.r(91, 0, 3, 70, C.woodDk)                -- posts
	b.r(3, 0, 1, 70, C.wood); b.r(92, 0, 1, 70, C.wood)
	b.r(6, 26, 84, 30, C.slate)                                            -- back wall
	for i = 0, 4 do b.r(10 + i * 16, 30 + (i % 2) * 8, 10, 12, C.woodDk) end -- shelves of jars
	b.r(8, 42, 80, 2, C.woodHi)
	b.r(0, 64, W, 12, stripeA)                                             -- awning
	for i = 0, 11 do
		if i % 2 == 1 then b.r(i * 8, 64, 8, 12, stripeB) end
		b.r(i * 8 + 2, 60, 4, 4, if i % 2 == 0 then stripeA else stripeB)  -- scalloped edge
	end
	b.r(0, 76, W, 2, C.ink, 0.6)
	-- (no board for the name: it is a kit sign, Plaza2D.placeSign, hung over the awning)
	for _, lx in { 18, 48, 78 } do                                         -- paper lanterns
		b.r(lx, 52, 1, 8, C.ink)
		b.r(lx - 3, 44, 7, 8, C.lantern)
		b.r(lx - 2, 45, 5, 6, C.lanternHi, 0.7)
		b.r(lx - 1, 43, 3, 1, C.ink)
	end
	return b.done(true)
end

function PlazaArt.stallFront(goods: string): any
	local W, H = 96, 30
	local b = builder(W, H)
	b.r(4, 0, 88, 22, C.wood)                                              -- counter
	for i = 0, 10 do b.r(6 + i * 8, 2, 1, 18, C.woodDk) end                -- planks
	b.r(2, 22, 92, 3, C.woodHi)                                            -- counter top
	b.r(2, 21, 92, 1, C.woodDk)
	b.r(4, 0, 88, 2, C.ink, 0.5)
	if goods == "bowls" then
		for i = 0, 3 do b.r(12 + i * 20, 25, 10, 4, C.white); b.r(13 + i * 20, 28, 8, 2, C.amber) end
	elseif goods == "masks" then
		for i = 0, 4 do
			local col = ({ C.white, C.pink, C.cyan, C.amber, C.green })[i + 1]
			b.r(10 + i * 16, 25, 9, 5, col); b.r(12 + i * 16, 27, 2, 1, C.ink); b.r(16 + i * 16, 27, 2, 1, C.ink)
		end
	elseif goods == "skewers" then
		b.r(14, 25, 40, 3, C.ink); b.r(15, 26, 38, 1, C.lantern, 0.8)          -- grill
		for i = 0, 5 do b.r(17 + i * 6, 28, 1, 2, C.woodHi); b.r(16 + i * 6, 29, 3, 1, C.amberDk) end
		b.r(62, 25, 14, 5, C.steel)
	else
		for i = 0, 3 do b.r(12 + i * 20, 25, 12, 5, C.steel); b.r(14 + i * 20, 27, 8, 2, C.cyan, 0.8) end
	end
	return b.done(true)
end

-- ------------------------------------------------------------------ fixtures ----
function PlazaArt.billboard(): any
	local W, H = 272, 150
	local b = builder(W, H)
	b.r(40, 0, 8, 56, C.steel); b.r(224, 0, 8, 56, C.steel)                 -- legs
	b.r(42, 0, 2, 56, C.steelHi); b.r(226, 0, 2, 56, C.steelHi)
	for i = 0, 5 do b.r(48, 6 + i * 9, 176, 2, C.steel, 0.8) end            -- lattice
	b.r(0, 52, W, 98, C.ink)                                                -- frame
	b.r(4, 56, W - 8, 90, C.steel)
	b.r(8, 60, W - 16, 82, C.glass)                                         -- screen (content is drawn live)
	b.r(0, 52, W, 2, C.pink); b.r(0, 148, W, 2, C.pink)
	b.r(0, 52, 2, 98, C.pink); b.r(W - 2, 52, 2, 98, C.pink)
	for i = 0, 8 do b.r(12 + i * 30, 146, 6, 4, C.amber) end                -- bulbs along the top
	return b.done(true)
end

function PlazaArt.kiosk(): any
	local W, H = 64, 60
	local b = builder(W, H)
	b.r(4, 0, 56, 10, C.slate); b.r(4, 10, 56, 2, C.slateHi)
	b.r(12, 12, 40, 6, C.steel); b.r(24, 18, 16, 26, C.steel); b.r(26, 18, 4, 26, C.steelHi)
	b.r(16, 44, 32, 6, C.ink); b.r(18, 46, 28, 3, C.cyan)                  -- the projector dish
	b.r(4, 4, 56, 2, C.cyan, 0.6)
	return b.done(true)
end

function PlazaArt.waterTower(): any
	local W, H = 72, 112
	local b = builder(W, H)
	for _, x in { 6, 30, 58 } do b.r(x, 0, 5, 50, C.woodDk) end
	b.r(6, 24, 58, 3, C.woodDk)
	b.r(2, 48, 68, 50, C.rust)
	for i = 0, 5 do b.r(2, 52 + i * 8, 68, 2, C.woodDk) end
	b.r(6, 48, 4, 50, C.wood, 0.5)
	b.r(0, 98, W, 4, C.woodDk); b.r(8, 102, 56, 6, C.rust); b.r(26, 108, 20, 4, C.woodDk)
	return b.done(true)
end

function PlazaArt.acUnit(): any
	local W, H = 40, 26
	local b = builder(W, H)
	b.r(0, 0, W, 24, C.steel); b.r(0, 22, W, 4, C.steelHi)
	b.r(4, 4, 18, 16, C.ink); for i = 0, 3 do b.r(5, 6 + i * 4, 16, 1, C.steel) end
	b.r(26, 6, 10, 12, C.slate)
	return b.done(true)
end

function PlazaArt.mapSign(): any
	local W, H = 64, 60
	local b = builder(W, H)
	b.r(29, 0, 6, 26, C.steel)
	b.r(0, 24, W, 34, C.ink); b.r(2, 26, W - 4, 30, C.night)
	b.r(0, 56, W, 2, C.cyan); b.r(0, 24, W, 2, C.cyan)
	-- the four districts, west to east, and the bridges between
	local ds: { { any } } = { { 5, C.pink }, { 18, C.amber }, { 35, C.cyan }, { 50, C.green } }
	for i, d in ds do
		b.r(d[1], 36, if i == 2 then 14 else 10, 12, d[2], 0.85)
		if i < 4 then b.r(d[1] + (if i == 2 then 14 else 10), 41, 3, 2, C.paper, 0.7) end
	end
	return b.done(true)
end

-- Strung lights between two poles `span` cells apart, sagging in the middle.
function PlazaArt.stringLights(span: number): any
	local W, H = span + 8, 80
	local b = builder(W, H)
	b.r(0, 0, 4, 76, C.steel); b.r(W - 4, 0, 4, 76, C.steel)
	local colours = { C.amber, C.pink, C.cyan, C.lanternHi, C.green }
	local n = math.floor(span / 6)
	for i = 0, n do
		local t = i / n
		local x = 4 + t * span
		local y = 72 - math.sin(t * math.pi) * 16
		b.r(math.floor(x), math.floor(y), 6, 1, C.ink)
		if i % 2 == 0 then b.r(math.floor(x) + 2, math.floor(y) - 3, 2, 3, colours[(i // 2) % #colours + 1]) end
	end
	return b.done()
end

-- One pennant, its top edge's centre at (x, y), `size` cells wide, pointing down: an ink outline, a
-- band narrowing to a point (the lounge's wall).
local function pennant(b: any, x: number, y: number, size: number, col: string)
	local rows = math.ceil(size / 2)
	for k = 0, rows - 1 do
		local half = math.floor(size / 2) - k
		b.r(x - half - 1, y - 2 - k * 2, half * 2 + 2, 2, C.ink)
		if half > 0 then b.r(x - half, y - 2 - k * 2, half * 2, 2, col) end
	end
end

-- A lounge's back wall, `w` x `h` cells: the kit's anatomy - ink top, light band, a pale plaster face,
-- and a deep indigo wainscot `low` cells tall under the stations - with windows at `windows` (cell
-- x's: the gaps between the stations) onto the sky, and pointed pennants along its top. (All deep
-- indigo, the couches sat on it at 1.13:1 and the map board read as one more window.)
function PlazaArt.loungeWall(w: number, h: number, windows: { number }, sky: string, low: number, skyLow: string?): any
	local b = builder(w, h)
	b.r(0, 0, w, h, C.indigoDk)
	b.r(0, 3, w, h - 7, C.plaster)
	-- plaster in courses of panels, as the islands' stone is in courses (one flat colour was 53% of the
	-- band behind the stations)
	for y = low + 18, h - 30, 24 do
		b.r(0, y, w, 1, C.plasterDk)
		local off = ((y // 24) % 2) * 32
		for x = off, w, 64 do b.r(x, y + 1, 1, 23, C.plasterDk) end
		b.r(0, y + 1, w, 1, C.plasterHi)
	end
	-- a terrace parapet for its top, not an interior cornice: a striped awning edge, as the stalls'
	b.r(0, h - 12, w, 9, C.pinkDk)
	for x = 0, w - 1, 16 do b.r(x, h - 12, 8, 9, C.paper) end
	for x = 0, w - 1, 16 do b.r(x + 2, h - 15, 4, 3, C.paper) end
	b.r(0, h - 3, w, 3, C.ink)
	-- the skirting from the wall's foot (the fill's dark showed under it, 1.47:1 to the couches' ink),
	-- in the light indigo (5.4:1 to ink) with a mid rail
	b.r(0, 0, w, low + 3, C.indigoHi)
	b.r(0, low + 3, w, 3, C.indigoWall)
	for _, cx in windows do
		local x0, y0, ww, wh = math.floor(cx) - 18, low + 14, 37, h - low - 44
		b.r(x0 - 2, y0 - 2, ww + 4, wh + 4, C.ink)
		b.r(x0, y0, ww, wh, sky)
		-- the view: the paler sky low down, a far island most of the pane wide and a cloud, so the window
		-- says "high up" (a 15 x 5 chip of island read as a speck)
		local lowH = math.floor(wh * 0.4)
		b.r(x0, y0, ww, lowH, skyLow or C.plasterHi)
		local iy = y0 + lowH - 6
		b.r(x0 + 4, iy - 1, ww - 8, 9, C.ink)                                      -- the island's rim
		b.r(x0 + 5, iy, ww - 10, 3, C.green); b.r(x0 + 7, iy + 3, ww - 14, 4, C.slate)
		b.r(x0 + 12, iy + 7, ww - 24, 2, C.slate)
		b.r(x0 + 6, y0 + wh - 14, 12, 4, C.white); b.r(x0 + 9, y0 + wh - 17, 7, 3, C.white)
		b.r(x0, y0 + math.floor(wh * 0.6), ww, 2, C.ink)
		b.r(x0 + 17, y0, 2, wh, C.ink)
		b.r(x0 - 4, y0 - 4, ww + 8, 2, C.indigoHi)                              -- its sill and lintel
	end
	local colours = { C.cyan, C.lantern, C.violet, C.green, C.pink }
	local n = 0
	for x = 12, w - 12, 24 do
		n += 1
		pennant(b, x, h - 15, 10, colours[(n - 1) % #colours + 1])
	end
	return b.done(true)
end

function PlazaArt.boutique(): any
	local W, H = 136, 110
	local b = builder(W, H)
	b.r(0, 0, W, 90, C.night)
	b.r(0, 88, W, 6, C.pinkDk)
	for i = 0, 16 do b.r(i * 8, 94, 8, 10, if i % 2 == 0 then C.pink else C.white) end  -- awning
	for i = 0, 16 do b.r(i * 8 + 2, 90, 4, 4, if i % 2 == 0 then C.pink else C.white) end
	b.r(46, 4, 44, 76, C.cyan)                                              -- the mirror
	b.r(49, 7, 38, 70, C.glass)
	b.r(8, 0, 30, 4, C.steelHi); b.r(98, 0, 30, 4, C.steelHi)               -- mannequin plinths
	b.r(4, 82, 128, 2, C.steelHi)                                           -- rail
	for i = 0, 7 do b.r(10 + i * 16, 74, 1, 8, C.steelHi); b.r(6 + i * 16, 64, 9, 10, ({ C.pink, C.cyan, C.amber, C.green })[i % 4 + 1], 0.8) end
	return b.done(true)
end

-- The foot of the Skyline Climb: a scaffold tower with a ladder and a flag at the top.
function PlazaArt.climbGate(): any
	local W, H = 96, 150
	local b = builder(W, H)
	for _, x in { 4, 44, 88 } do b.r(x, 0, 4, 138, C.steel); b.r(x + 1, 0, 1, 138, C.steelHi) end
	for i = 0, 5 do
		local y = 16 + i * 22
		b.r(4, y, 88, 3, C.steel)
		b.r(8, y + 3, 32, 2, C.woodDk); b.r(48, y + 3, 40, 2, C.woodDk)          -- deck planks
		if i % 2 == 0 then b.r(8, y - 18, 3, 18, C.steel, 0.6) else b.r(80, y - 18, 3, 18, C.steel, 0.6) end
	end
	b.r(56, 0, 3, 128, C.woodHi); b.r(70, 0, 3, 128, C.woodHi)               -- the ladder
	for y = 4, 124, 8 do b.r(56, y, 17, 2, C.woodHi) end
	b.r(44, 138, 3, 12, C.steelHi)
	b.r(47, 141, 18, 8, C.amber)                                             -- the flag
	b.r(0, 0, W, 3, C.ink, 0.6)
	return b.done()
end

-- The climb's leaderboard: a lit scoreboard on steel legs, two columns of names under an amber
-- header, a gold, a silver and a bronze at the top of each (the names themselves are labels).
function PlazaArt.recordBoard(): any
	local W, H = 60, 76
	local b = builder(W, H)
	b.r(8, 0, 4, 30, C.steel); b.r(48, 0, 4, 30, C.steel)
	b.r(9, 0, 1, 30, C.steelHi); b.r(49, 0, 1, 30, C.steelHi)
	b.r(0, 26, W, 46, C.ink); b.r(2, 28, W - 4, 42, C.night)
	b.r(2, 62, W - 4, 8, C.amberDk); b.r(4, 64, W - 8, 4, C.amber)          -- header strip
	b.r(29, 30, 2, 30, C.slateHi)                                           -- column divider
	local medals: { string } = { C.amber, C.steelHi, C.rust }
	for col = 0, 1 do
		local x = 5 + col * 27
		for row = 0, 5 do
			local y = 55 - row * 4
			b.r(x, y, 2, 2, medals[row + 1] or C.slateHi)
			b.r(x + 4, y, 12 - (row * 3) % 5, 2, if row < 3 then C.paper else C.steel, if row < 3 then 0.9 else 0.6)
			b.r(x + 18, y, 4, 2, C.cyan, 0.7)
		end
	end
	b.r(0, 72, W, 4, C.steelHi)
	b.r(0, 0, W, 2, C.ink, 0.6)
	return b.done(true)
end

function PlazaArt.couch(colour: string): any
	local b = builder(56, 22)
	b.r(0, 0, 56, 12, colour); b.r(0, 12, 56, 8, colour); b.r(0, 12, 4, 10, C.ink, 0.4); b.r(52, 12, 4, 10, C.ink, 0.4)
	b.r(4, 10, 48, 2, C.ink, 0.35); b.r(2, 0, 4, 2, C.woodDk); b.r(50, 0, 4, 2, C.woodDk)
	return b.done(true)
end

function PlazaArt.plant(): any
	local b = builder(20, 30)
	b.r(4, 0, 12, 9, C.rust); b.r(3, 8, 14, 2, C.woodDk)
	b.r(8, 10, 3, 12, "#2E6B3E"); b.r(2, 14, 8, 6, "#3E8A4E"); b.r(10, 18, 9, 7, "#3E8A4E"); b.r(6, 24, 7, 6, "#4FA05E")
	return b.done(true)
end

-- Cached props, keyed by name + arguments.
local CACHE: { [string]: any } = {}
function PlazaArt.get(key: string, make: () -> any): any
	local hit = CACHE[key]
	if not hit then
		hit = make()
		CACHE[key] = hit
	end
	return hit
end

-- Draw a prop with its base-centre at world (x, y), `scale` times its authored size.
function PlazaArt.draw(c: any, key: string, prop: any, x: number, y: number, scale: number?)
	local k = (scale or 1) * PlazaArt.CELL
	Canvas2D.sprite(c, "prop|" .. key, prop.rects, x - prop.w * k / 2, y + prop.h * k, k, k, prop.w, prop.h)
end

return PlazaArt
