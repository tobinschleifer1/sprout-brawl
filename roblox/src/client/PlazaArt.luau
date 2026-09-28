--!strict
-- The rooftop night market's props, as pixel art: built once in eighth-of-a-stud cells and drawn
-- as sprites (Canvas2D.sprite), so a stall of two hundred rectangles costs one Frame a frame.
--
-- Each builder draws in the prop's own cell space, y UP from the prop's base, x from its left edge,
-- with `r(x, y, w, h, hex, alpha)`; `done()` converts to the sprite convention (rows down from the
-- top). A prop is { rects, w, h } in cells; PlazaArt.draw places its base-centre at a world point.
--
-- Palette: the arenas' steel greys and warm lantern light; the accents are rust, amber and a
-- muted teal (named pink and cyan below for where they sit, not what they are).

local Canvas2D = require(script.Parent.Canvas2D)

local PlazaArt = {}
PlazaArt.CELL = 1 / 8

local C: { [string]: string } = {
	-- The arenas' steels (Data/Stages palettes: #3E4450, #6E7788, #8A94A6) with their one warm accent,
	-- rather than neon: the lobby should look like it belongs to the same game as the maps.
	ink = "#0F1218", night = "#1A1E26", slate = "#262B35", slateHi = "#3E4450", tar = "#20242C", tarHi = "#2C313B",
	steel = "#6E7788", steelHi = "#8A94A6", rust = "#7A4432", wood = "#6B4A36", woodHi = "#8C6448", woodDk = "#463126",
	pink = "#C8643C", pinkDk = "#6E3524", cyan = "#7FA8B8", cyanDk = "#3E5A66", amber = "#E8A24A", amberDk = "#9A6424",
	lantern = "#D07040", lanternHi = "#EDB27A", paper = "#D9CDB2", glass = "#1E2733", white = "#E6E1D6", green = "#7FA06A",
}
PlazaArt.C = C

local function builder(w: number, h: number)
	local list: { any } = {}
	local b = {}
	function b.r(x: number, y: number, rw: number, rh: number, hex: string, alpha: number?)
		if rw <= 0 or rh <= 0 then return end
		table.insert(list, { x, h - y - rh, rw, rh, hex, alpha or 1 } :: { any })
	end
	function b.done(): any
		return { rects = list, w = w, h = h }
	end
	return b
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
	b.r(30, 76, 36, 8, C.ink)                                              -- sign board (text is a label)
	b.r(31, 77, 34, 6, C.night)
	for _, lx in { 18, 48, 78 } do                                         -- paper lanterns
		b.r(lx, 52, 1, 8, C.ink)
		b.r(lx - 3, 44, 7, 8, C.lantern)
		b.r(lx - 2, 45, 5, 6, C.lanternHi, 0.7)
		b.r(lx - 1, 43, 3, 1, C.ink)
	end
	return b.done()
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
	return b.done()
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
	return b.done()
end

function PlazaArt.kiosk(): any
	local W, H = 64, 60
	local b = builder(W, H)
	b.r(4, 0, 56, 10, C.slate); b.r(4, 10, 56, 2, C.slateHi)
	b.r(12, 12, 40, 6, C.steel); b.r(24, 18, 16, 26, C.steel); b.r(26, 18, 4, 26, C.steelHi)
	b.r(16, 44, 32, 6, C.ink); b.r(18, 46, 28, 3, C.cyan)                  -- the projector dish
	b.r(4, 4, 56, 2, C.cyan, 0.6)
	return b.done()
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
	return b.done()
end

function PlazaArt.acUnit(): any
	local W, H = 40, 26
	local b = builder(W, H)
	b.r(0, 0, W, 24, C.steel); b.r(0, 22, W, 4, C.steelHi)
	b.r(4, 4, 18, 16, C.ink); for i = 0, 3 do b.r(5, 6 + i * 4, 16, 1, C.steel) end
	b.r(26, 6, 10, 12, C.slate)
	return b.done()
end

function PlazaArt.noticeBoard(): any
	local W, H = 64, 60
	local b = builder(W, H)
	b.r(6, 0, 4, 44, C.woodDk); b.r(54, 0, 4, 44, C.woodDk)
	b.r(0, 20, W, 36, C.wood); b.r(2, 22, W - 4, 32, C.woodDk)
	local papers: { { any } } = { { 5, 38, C.paper }, { 17, 32, C.amber }, { 29, 40, C.paper }, { 41, 30, C.cyan }, { 50, 38, C.pink }, { 8, 25, C.paper }, { 31, 24, C.paper } }
	for _, p in papers do b.r(p[1], p[2], 10, 12, p[3]); b.r(p[1] + 4, p[2] + 10, 2, 2, C.lantern) end
	b.r(0, 56, W, 4, C.woodHi)
	return b.done()
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
	return b.done()
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

-- The arcade's canopy: posts and a roof beam across the whole district. (The sign is a label.)
function PlazaArt.canopy(span: number): any
	local W, H = span, 120
	local b = builder(W, H)
	local posts = math.floor(span / 160)
	for i = 0, posts do
		local x = math.floor(i * (span - 8) / posts)
		b.r(x, 0, 8, 110, C.steel); b.r(x + 2, 0, 2, 110, C.steelHi)
	end
	b.r(0, 106, W, 10, C.ink); b.r(0, 110, W, 2, C.pink); b.r(0, 106, W, 2, C.cyan)
	b.r(0, 116, W, 4, C.slate)
	return b.done()
end

-- A pair of arcade cabinets back to back, seen from the side: each faces out toward its seat.
function PlazaArt.cabinetPair(): any
	local W, H = 64, 56
	local b = builder(W, H)
	for _, side in { -1, 1 } do
		local function sx(x: number, w: number): number
			return if side < 0 then 32 - x - w else 32 + x
		end
		b.r(sx(0, 20), 0, 20, 22, C.night)                                   -- body
		b.r(sx(20, 6), 18, 6, 6, C.slateHi)                                  -- control panel, out toward the seat
		b.r(sx(21, 4), 23, 4, 1, C.pink)                                     -- buttons
		b.r(sx(2, 18), 24, 18, 20, C.night)                                  -- screen housing
		b.r(sx(16, 3), 26, 3, 16, C.cyan, 0.85)                              -- screen glow seen edge-on
		b.r(sx(0, 20), 44, 20, 10, C.ink)                                    -- marquee
		b.r(sx(2, 16), 46, 16, 6, if side < 0 then C.pink else C.cyan, 0.9)
		b.r(sx(0, 2), 0, 2, 54, C.slate)                                     -- the seam between them
	end
	return b.done()
end

function PlazaArt.stool(): any
	local b = builder(12, 16)
	b.r(0, 12, 12, 3, C.pink); b.r(5, 0, 2, 12, C.steel); b.r(2, 0, 8, 2, C.steel)
	return b.done()
end

function PlazaArt.lift(colour: string): any
	local W, H = 88, 104
	local b = builder(W, H)
	b.r(0, 0, W, 96, C.ink)
	b.r(6, 0, 76, 86, C.slate)
	b.r(8, 0, 35, 84, C.steel); b.r(45, 0, 35, 84, C.steel)                 -- doors
	b.r(43, 0, 2, 84, C.ink)
	for i = 0, 5 do b.r(10, 8 + i * 13, 31, 1, C.slate); b.r(47, 8 + i * 13, 31, 1, C.slate) end
	b.r(0, 86, W, 2, colour); b.r(0, 0, 2, 96, colour); b.r(W - 2, 0, 2, 96, colour)
	b.r(26, 96, 36, 8, C.ink); b.r(28, 98, 32, 4, colour, 0.9)             -- the floor light
	return b.done()
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
	return b.done()
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
	return b.done()
end

function PlazaArt.couch(colour: string): any
	local b = builder(56, 22)
	b.r(0, 0, 56, 12, colour); b.r(0, 12, 56, 8, colour); b.r(0, 12, 4, 10, C.ink, 0.4); b.r(52, 12, 4, 10, C.ink, 0.4)
	b.r(4, 10, 48, 2, C.ink, 0.35); b.r(2, 0, 4, 2, C.woodDk); b.r(50, 0, 4, 2, C.woodDk)
	return b.done()
end

function PlazaArt.plant(): any
	local b = builder(20, 30)
	b.r(4, 0, 12, 9, C.rust); b.r(3, 8, 14, 2, C.woodDk)
	b.r(8, 10, 3, 12, "#2E6B3E"); b.r(2, 14, 8, 6, "#3E8A4E"); b.r(10, 18, 9, 7, "#3E8A4E"); b.r(6, 24, 7, 6, "#4FA05E")
	return b.done()
end

-- A stamp (Data/Plaza stamps) as sprite rectangles: each row cut into runs of one colour. Rows
-- are already top-down, which is the sprite convention.
local STAMPS: { [string]: any } = {}
function PlazaArt.stamp(st: any): any
	local hit = STAMPS[st.id]
	if hit then return hit end
	local rects: { any } = {}
	local w = 0
	for r, row in st.rows do
		w = math.max(w, #row)
		local c = 1
		while c <= #row do
			local ch = string.sub(row, c, c)
			local run = 1
			while c + run <= #row and string.sub(row, c + run, c + run) == ch do run += 1 end
			if ch ~= "." then table.insert(rects, { c - 1, r - 1, run, 1, st.ink[ch], 1 } :: { any }) end
			c += run
		end
	end
	hit = { rects = rects, w = w, h = #st.rows }
	STAMPS[st.id] = hit
	return hit
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
