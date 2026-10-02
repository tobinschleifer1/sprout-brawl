--!strict
-- Pixel-art effects, drawn in code: explosions, shockwaves, slash crescents, lightning, flame,
-- energy orbs, rune circles, vortices, rock pillars, comets, barriers and sight reticles.
--
-- WHY GENERATED, NOT UPLOADED. Every effect is a small pixel grid built by a function below,
-- merged into rectangles and drawn as ONE Canvas2D sprite - a container Frame that moves, holding
-- static children - exactly like the weapons and the kit characters. Nothing is uploaded, nothing
-- waits on moderation or a download, and every effect takes the caster's own weapon colour: a grid
-- stores TONES (1 darkest .. 5 white-hot), and a tone becomes a colour only when the grid is
-- compiled against a ramp. One explosion design serves twelve weapons and any palette.
--
-- THE STYLE. Hand-drawn 2D fighters animate effects as flipbooks, not as tweens: a burst is seven
-- distinct drawings (flash, fireball, hollowing, breaking ring, fragments) rather than one disc that
-- grows and fades. So each generator takes a frame number and returns a different drawing, and
-- the size of the drawing stays fixed while its contents change. Hue-shifted ramps (shadows lean
-- cool, highlights run to white) are what make five flat colours read as light.
--
-- COST. A compiled grid is typically 20-90 rectangles. Canvas2D.sprite builds them once per key
-- and afterwards moves one container per draw; alpha is quantised (FxArt.draw) so a fade rewrites
-- the children a handful of times rather than every frame.

local Canvas2D = require(script.Parent.Canvas2D)
local PixelGrid = require(script.Parent.PixelGrid)

local FxArt = {}

-- Art pixels per stud. Weapons are 8; effects are drawn chunkier on purpose, at half that, which
-- is the look of the reference sheets and halves the rectangle count of anything large.
FxArt.PPU = 4

-- ------------------------------------------------------------------ colour ----
local function parse(hex: string): (number, number, number)
	local h = string.gsub(hex, "#", "")
	return tonumber(string.sub(h, 1, 2), 16) :: number / 255,
		tonumber(string.sub(h, 3, 4), 16) :: number / 255,
		tonumber(string.sub(h, 5, 6), 16) :: number / 255
end

local function format(r: number, g: number, b: number): string
	local function byte(v: number): number
		return math.clamp(math.floor(v * 255 + 0.5), 0, 255)
	end
	return string.format("#%02X%02X%02X", byte(r), byte(g), byte(b))
end

local function toHsv(r: number, g: number, b: number): (number, number, number)
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then
			h = ((g - b) / d) % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	return h, if mx > 0 then d / mx else 0, mx
end

local function fromHsv(h: number, s: number, v: number): (number, number, number)
	h = (h % 1) * 6
	local i = math.floor(h)
	local f = h - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	if i == 0 then return v, t, p
	elseif i == 1 then return q, v, p
	elseif i == 2 then return p, v, t
	elseif i == 3 then return p, q, v
	elseif i == 4 then return t, p, v
	end
	return v, p, q
end

-- Move hue `h` toward `to` by `amount` of a turn, the short way round.
local function shiftHue(h: number, to: number, amount: number): number
	local d = ((to - h + 0.5) % 1) - 0.5
	if math.abs(d) < amount then return to end
	return (h + amount * (if d < 0 then -1 else 1)) % 1
end

local COOL = 0.70      -- shadows lean toward blue-violet
local rampCache: { [string]: { string } } = {}

-- Five tones from one colour: deep shadow, shadow, the colour itself, light, and white-hot core.
-- A light glow colour (most weapon glows are pastel) is pushed to full saturation for the body
-- tone, so the effect still reads as coloured light rather than as grey against a dark stage.
function FxArt.ramp(base: string): { string }
	local cached = rampCache[base]
	if cached then return cached end
	local h, s, v = toHsv(parse(base))
	-- Pastel glows (most weapons') would leave light and core both near white, so the steps are
	-- taken from the saturated body tone rather than from the input.
	local sb = math.clamp(s * 1.3 + 0.25, 0, 1)
	local body = { fromHsv(h, sb, math.max(v, 0.92)) }
	local light = { fromHsv(shiftHue(h, 0.15, 0.03), sb * 0.48, 1) }
	local core = { fromHsv(h, sb * 0.10, 1) }
	local dark = { fromHsv(shiftHue(h, COOL, 0.05), math.clamp(s * 1.1 + 0.25, 0, 1), v * 0.58) }
	local deep = { fromHsv(shiftHue(h, COOL, 0.10), math.clamp(s * 1.0 + 0.35, 0, 1), v * 0.26) }
	local out = { format(table.unpack(deep)), format(table.unpack(dark)), format(table.unpack(body)),
		format(table.unpack(light)), format(table.unpack(core)) }
	rampCache[base] = out
	return out
end

-- Fixed elemental ramps, for effects whose material is not the weapon: fire is fire whatever
-- colour the blade glows, and rock is rock.
FxArt.RAMPS = {
	fire = { "#3B0A0A", "#A3290F", "#F2621B", "#FFB93F", "#FFF4C8" },
	void = { "#0B0614", "#33135C", "#8A3FE0", "#CB9EFF", "#F6EDFF" },
	blood = { "#260309", "#7A0E22", "#D6213F", "#FF6F82", "#FFE3E7" },
	volt = { "#071638", "#1450C8", "#2FA8FF", "#9BE8FF", "#F4FEFF" },
	earth = { "#17110D", "#3F3126", "#6E5A47", "#A38C70", "#D9CCB4" },
	gold = { "#382004", "#985C0C", "#E8A61C", "#FFE07A", "#FFFBE2" },
	star = { "#0C0A2C", "#36289A", "#7A5CFF", "#C2AEFF", "#FFFFFF" },
	wind = { "#141A24", "#3A4656", "#8C9CB2", "#D4DEEC", "#FFFFFF" },
	red = { "#2A0606", "#8A1414", "#FF3A3A", "#FF9A8A", "#FFF0EC" },
	smoke = { "#0E0D12", "#24222B", "#3C3946", "#5E5A68", "#8A8694" },
}

function FxArt.rampOf(name: string?): { string }
	if not name then return FxArt.RAMPS.wind end
	local fixed = (FxArt.RAMPS :: any)[name]
	if fixed then return fixed end
	return FxArt.ramp(name)
end

-- ------------------------------------------------------------------ grids ----
-- PixelGrid holds the machinery. Here a cell is a TONE: 1-5 index the primary ramp, 6-10 a second
-- ramp (rock under glowing cracks), 11-15 the primary ramp at half opacity (soft glow).
type Grid = PixelGrid.Grid
local hash = PixelGrid.hash
FxArt.hash = hash
local noise1 = PixelGrid.noise
local grid = PixelGrid.new
local put = PixelGrid.put
local get = PixelGrid.get
local lift = PixelGrid.lift
local line = PixelGrid.line
local rim = PixelGrid.rim
local merge = PixelGrid.merge
FxArt.merge = merge

-- ------------------------------------------------------------------ the drawings ----
-- Each returns a grid and its anchor (the pixel that lands on the effect's position), and takes
-- the flipbook frame. FxArt.FRAMES says how many frames each has.
local gen: { [string]: (number, number) -> (Grid, number, number) } = {}
FxArt.FRAMES = {
	burst = 7, ring = 6, star = 4, crescent = 5, bolt = 4, flame = 6, orb = 4, rune = 1, swirl = 1,
	pillar = 6, fissure = 2, comet = 3, xslash = 4, dome = 1, reticle = 1, sigil = 1, cyclone = 4,
	spark = 3, lance = 3, pop = 5,
}

-- EXPLOSION. Flash, fireball, hot core cooling outward, hollowing into a ring of smoke, the ring
-- breaking into chunks, scattered fragments, a few last embers.
gen.burst = function(f: number, seed: number)
	local S = 28
	local g = grid(S, S)
	local c = S / 2
	local R = ({ 0.34, 0.62, 0.82, 0.93, 0.98, 1.0, 1.0 })[f + 1] * c * 0.9
	for y = 0, S - 1 do
		for x = 0, S - 1 do
			local dx, dy = x + 0.5 - c, y + 0.5 - c
			local d = math.sqrt(dx * dx + dy * dy)
			local a = math.atan2(dy, dx)
			local lobe = 1 + 0.10 * math.sin(a * 7 + seed) + 0.07 * math.sin(a * 11 + seed * 2.3)
				+ (hash(x, y, seed + f) - 0.5) * 0.10
			local rr = d / (R * lobe)
			local t = 0
			if f == 0 then
				if rr < 1 then t = if rr < 0.6 then 5 else 4 end
			elseif f == 1 then
				if rr < 1 then t = if rr < 0.5 then 5 elseif rr < 0.8 then 4 else 3 end
			elseif f == 2 then
				if rr < 1 then t = if rr < 0.28 then 5 elseif rr < 0.58 then 4 elseif rr < 0.84 then 3 else 2 end
			elseif f == 3 then
				if rr < 1 then
					if rr < 0.42 then
						t = if (x + y) % 2 == 0 and hash(x, y, seed) > 0.35 then 1 else 0
					elseif rr < 0.56 then t = 2
					elseif rr < 0.78 then t = 4
					elseif rr < 0.92 then t = 3
					else t = 2 end
				end
			elseif f == 4 then
				local seg = math.floor((a + math.pi) / (2 * math.pi) * 11)
				if rr > 0.68 and rr < 1 and hash(seg, 3, seed) > 0.28 then
					t = if rr < 0.8 then 3 elseif rr < 0.92 then 2 else 1
				elseif rr < 0.6 and (x + y) % 2 == 0 and hash(x, y, seed + 9) > 0.78 then
					t = 1
				end
			elseif f == 5 then
				if rr > 0.82 and rr < 1.06 and hash(x, y, seed + 5) > 0.80 then
					t = if hash(x, y, seed + 6) > 0.5 then 3 else 2
				end
			else
				if rr > 0.92 and rr < 1.12 and hash(x, y, seed + 7) > 0.92 then t = 2 end
			end
			if t > 0 then put(g, x, y, t) end
		end
	end
	if f == 0 then
		-- the flash frame throws a four-point glint past the fireball's edge
		for k = -1, 1, 2 do
			line(g, c, c, c + k * c * 0.95, c, 4, true)
			line(g, c, c, c, c + k * c * 0.95, 4, true)
		end
	end
	if f >= 1 and f <= 3 then rim(g, 1) end
	return g, c, c
end

-- SHOCKWAVE. A thin ring racing outward: white leading edge, colour behind it, breaking into
-- segments as it spends itself.
gen.ring = function(f: number, seed: number)
	local S = 32
	local g = grid(S, S)
	local c = S / 2
	local r = c * (0.28 + 0.70 * f / 5) - 0.5
	local th = ({ 3, 3, 2.6, 2, 1.6, 1.2 })[f + 1]
	local dim = if f >= 4 then 1 else 0
	for y = 0, S - 1 do
		for x = 0, S - 1 do
			local dx, dy = x + 0.5 - c, y + 0.5 - c
			local d = math.sqrt(dx * dx + dy * dy)
			local e = r - d
			if e >= 0 and e < th then
				local a = math.atan2(dy, dx)
				local seg = math.floor((a + math.pi) / (2 * math.pi) * 16)
				if hash(seg, 1, seed) >= f * 0.11 then
					put(g, x, y, (if e < 1 then 5 elseif e < 2 then 4 else 3) - dim)
				end
			end
		end
	end
	return g, c, c
end

-- SPARKLE. A four-point glint: blink in, flare with diagonals, settle, wink out.
gen.star = function(f: number, _seed: number)
	local S = 15
	local g = grid(S, S)
	local c = 7
	local L = ({ 3, 7, 6, 2 })[f + 1]
	for k = -L, L do
		local a = math.abs(k)
		local t = if a <= 1 then 5 elseif a <= L * 0.5 then 4 else 3
		lift(g, c + k, c, t)
		lift(g, c, c + k, t)
	end
	if f == 1 or f == 2 then
		local D = if f == 1 then 2 else 3
		for k = 1, D do
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do lift(g, c + sx * k, c + sy * k, if k == 1 then 4 else 3) end
			end
		end
		put(g, c - 1, c, 5); put(g, c + 1, c, 5); put(g, c, c - 1, 5); put(g, c, c + 1, 5)
	end
	return g, c, c
end

-- SLASH. A crescent - two circles, the inner one offset - opening toward -x, so it is drawn about
-- the pivot of the swing and rotated to the blade. Thin to thick to broken.
gen.crescent = function(f: number, seed: number)
	local S = 32
	local g = grid(S, S)
	local c = S / 2
	local Ro = c - 1
	local off = ({ 2.0, 4.5, 6.0, 5.0, 3.5 })[f + 1]
	local Ri = Ro - 1
	for y = 0, S - 1 do
		for x = 0, S - 1 do
			local dx, dy = x + 0.5 - c, y + 0.5 - c
			local d = math.sqrt(dx * dx + dy * dy)
			local ix = dx + off
			local di = math.sqrt(ix * ix + dy * dy)
			if d <= Ro and di > Ri and dx > -2 then
				local a = math.abs(math.atan2(dy, dx))
				local edge = Ro - d
				local t = if edge < 1 then 5 elseif edge < 2.2 then 4 else 3
				if a > 1.15 then t = math.max(2, t - 2) end
				if f >= 3 then
					local seg = math.floor(a * 9)
					if hash(seg, 2, seed + f) < (f - 2) * 0.32 then t = 0 end
					t = math.max(0, t - (f - 2))
				end
				if t > 0 then put(g, x, y, t) end
			end
		end
	end
	return g, c, c
end

-- LIGHTNING. A jagged bolt along +x with a forked branch; every frame is a new strike.
gen.bolt = function(f: number, seed: number)
	local W, H = 34, 17
	local g = grid(W, H)
	local cy = H / 2
	local pts = { { 0, cy } }
	local y = cy
	local x = 0
	while x < W - 1 do
		x = math.min(W - 1, x + 2 + math.floor(hash(x, f, seed) * 3))
		y = math.clamp(y + (hash(x, f + 1, seed) - 0.5) * 9, 2, H - 3)
		table.insert(pts, { x, y })
	end
	for i = 1, #pts - 1 do
		line(g, pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2], 5)
	end
	local b = pts[math.clamp(math.floor(#pts * 0.45), 2, #pts)]
	local bx, by = b[1], b[2]
	local dir = if hash(f, 7, seed) > 0.5 then 1 else -1
	for k = 1, 6 do
		local nx, ny = bx + 2, math.clamp(by + dir * (1 + hash(k, f, seed) * 2), 0, H - 1)
		line(g, bx, by, nx, ny, 4, true)
		bx, by = nx, ny
	end
	-- the halo: colour around the white core
	local core = {}
	for yy = 0, H - 1 do
		for xx = 0, W - 1 do
			if get(g, xx, yy) >= 4 then table.insert(core, { xx, yy }) end
		end
	end
	for _, p in core do
		for _, o in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			if get(g, p[1] + o[1], p[2] + o[2]) == 0 then put(g, p[1] + o[1], p[2] + o[2], 3) end
		end
	end
	rim(g, 2)
	return g, 0, math.floor(cy)
end

-- FLAME. A column of fire licking upward, anchored at its base; loops over six frames.
gen.flame = function(f: number, seed: number)
	local W, H = 14, 24
	local g = grid(W, H)
	local half = W / 2
	for x = 0, W - 1 do
		local cw = 1 - math.abs(x + 0.5 - half) / half
		local top = H * (0.30 + 0.62 * cw ^ 1.15) * (0.78 + 0.44 * noise1(x * 0.7 + f * 1.9, seed))
		for yy = 0, math.floor(top) do
			local u = yy / math.max(1, top)
			local t = if u < 0.28 and cw > 0.62 then 5 elseif u < 0.55 and cw > 0.36 then 4 elseif u < 0.82 then 3 else 2
			put(g, x, H - 1 - yy, t)
		end
		-- a tongue torn loose above the column
		if hash(x, f, seed) > 0.72 then
			local ty = H - 1 - math.floor(top) - 2 - math.floor(hash(x, f + 3, seed) * 3)
			put(g, x, ty, 3)
			put(g, x, ty - 1, 2)
		end
	end
	for k = 0, 1 do
		local ex = math.floor(hash(k, f, seed + 4) * W)
		local ey = math.floor(hash(k, f + 9, seed + 4) * H * 0.35)
		put(g, ex, ey, 4)
	end
	rim(g, 1)
	return g, half, H - 1
end

-- ENERGY ORB. Hot core, highlight, a dithered corona that breathes.
gen.orb = function(f: number, _seed: number)
	local S = 18
	local g = grid(S, S)
	local c = S / 2
	local R = 5.6 + ({ 0, 0.5, 0.9, 0.5 })[f + 1]
	for y = 0, S - 1 do
		for x = 0, S - 1 do
			local dx, dy = x + 0.5 - c, y + 0.5 - c
			local d = math.sqrt(dx * dx + dy * dy)
			if d < R * 0.32 then put(g, x, y, 5)
			elseif d < R * 0.6 then put(g, x, y, 4)
			elseif d < R * 0.85 then put(g, x, y, 3)
			elseif d < R then put(g, x, y, 2)
			elseif d < R + 2.2 and (x + y + f) % 2 == 0 then put(g, x, y, 12)
			end
		end
	end
	put(g, c - 2, c - 3, 5); put(g, c - 3, c - 2, 5)
	return g, c, c
end

-- RUNE CIRCLE. Two rings, a band of glyphs between them, a hexagram inside. Static: it turns
-- by rotating the sprite, which costs nothing.
gen.rune = function(_f: number, seed: number)
	local S = 40
	local g = grid(S, S)
	local c = S / 2
	local function circle(r: number, tone: number)
		local n = math.ceil(r * 7)
		for i = 0, n - 1 do
			local a = i / n * math.pi * 2
			put(g, c + math.cos(a) * r, c + math.sin(a) * r, tone)
		end
	end
	circle(c - 1.5, 3)
	circle(c - 5.5, 4)
	local N = 12
	for i = 0, N - 1 do
		local a = i / N * math.pi * 2
		local r = c - 3.5
		local x, y = c + math.cos(a) * r, c + math.sin(a) * r
		local kind = math.floor(hash(i, 0, seed) * 3)
		put(g, x, y, 5)
		if kind == 0 then
			put(g, x + 1, y, 4); put(g, x, y + 1, 4)
		elseif kind == 1 then
			put(g, x + math.cos(a), y + math.sin(a), 4); put(g, x - math.cos(a), y - math.sin(a), 4)
		else
			put(g, x - math.sin(a), y + math.cos(a), 4); put(g, x + math.sin(a), y - math.cos(a), 4)
		end
	end
	local R = c - 7
	for t = 0, 1 do
		local pts = {}
		for k = 0, 2 do
			local a = (k / 3) * math.pi * 2 + t * math.pi / 3 - math.pi / 2
			table.insert(pts, { c + math.cos(a) * R, c + math.sin(a) * R })
		end
		for k = 1, 3 do
			local p, q = pts[k], pts[k % 3 + 1]
			line(g, p[1], p[2], q[1], q[2], 3, true)
		end
	end
	put(g, c, c, 5); put(g, c - 1, c, 4); put(g, c, c - 1, 4)
	return g, c, c
end

-- VORTEX. Three spiral arms around a black eye. Static; spun by rotating the sprite.
gen.swirl = function(_f: number, seed: number)
	local S = 34
	local g = grid(S, S)
	local c = S / 2
	for y = 0, S - 1 do
		for x = 0, S - 1 do
			local dx, dy = x + 0.5 - c, y + 0.5 - c
			local d = math.sqrt(dx * dx + dy * dy)
			if d < c - 0.5 then
				local a = math.atan2(dy, dx)
				local arm = ((a + math.log(d + 1) * 2.1 + seed * 0.1) * 3 / (2 * math.pi)) % 1
				local width = 0.34 - d / c * 0.12
				if d < 2.6 then
					put(g, x, y, 1)
				elseif arm < width then
					local t = if arm < width * 0.25 then 5 elseif arm < width * 0.55 then 4 else 3
					if d > c * 0.78 then t = math.max(2, t - 2) end
					put(g, x, y, t)
				elseif d < c * 0.45 and (x + y) % 2 == 0 then
					put(g, x, y, 1)
				end
			end
		end
	end
	return g, c, c
end

-- ROCK PILLAR. Bursts up from the floor and settles: rock in the second ramp, a glowing seam up
-- its middle in the first, chunks thrown off the top while it rises. Anchored at its base.
gen.pillar = function(f: number, seed: number)
	local W, H = 12, 34
	local g = grid(W, H)
	local rise = ({ 0.28, 0.72, 1.0, 0.94, 0.97, 0.97 })[f + 1]
	local body = math.floor((H - 6) * rise)
	for x = 1, W - 2 do
		local jag = math.floor(hash(x, 0, seed) * 3)
		local top = body - jag
		for yy = 0, top do
			local y = H - 1 - yy
			local t = 8
			if x == 1 then t = 9 elseif x == W - 2 then t = 7 end
			if yy % 6 == 5 and hash(x, yy, seed) > 0.3 then t = 7 end
			put(g, x, y, t)
		end
	end
	-- the seam: a zig-zag up the middle, white-hot while it is still rising
	local sx = W / 2
	for yy = 0, body - 2 do
		local x = sx + math.floor(math.sin(yy * 0.9 + seed) * 1.5)
		put(g, x, H - 1 - yy, if f <= 2 then 5 else 4)
		if hash(yy, 1, seed) > 0.6 then put(g, x + 1, H - 1 - yy, 3) end
	end
	if f >= 1 and f <= 3 then
		for k = 0, 2 + f do
			local cx = math.floor(hash(k, f, seed) * (W - 2)) + 1
			local cy = H - 1 - body - 2 - math.floor(hash(k, f + 5, seed) * 4 * f)
			put(g, cx, cy, 8); put(g, cx + 1, cy, 9); put(g, cx, cy + 1, 7)
		end
	end
	rim(g, 6)
	return g, W / 2, H - 1
end

-- FISSURE. A crack across the floor glowing from below, with short forks. Anchored at its centre.
gen.fissure = function(f: number, seed: number)
	local W, H = 48, 7
	local g = grid(W, H)
	local y = 2
	for x = 0, W - 1 do
		if hash(x, 0, seed) > 0.62 then y = math.clamp(y + (if hash(x, 1, seed) > 0.5 then 1 else -1), 1, H - 3) end
		local edgeFade = math.min(x, W - 1 - x) < 4
		put(g, x, y, if edgeFade then 3 elseif f == 0 then 5 else 4)
		if not edgeFade then put(g, x, y + 1, 3) end
		if hash(x, 2, seed) > 0.9 then
			put(g, x + 1, y + 2, 3); put(g, x + 2, y + 3, 2)
		end
	end
	rim(g, 1)
	return g, W / 2, 2
end

-- COMET. A projectile head with its tail running back along -x: a falling star, a tracer round,
-- an arrow of light. Anchored at the head.
gen.comet = function(f: number, seed: number)
	local W, H = 28, 11
	local g = grid(W, H)
	local cy = H / 2
	local hx = W - 5.5
	local tail = W - 7
	for x = 0, tail do
		local u = x / tail
		local half = 0.6 + 2.6 * u * u
		for y = 0, H - 1 do
			local dy = math.abs(y + 0.5 - cy)
			if dy <= half and hash(x, y, seed + f) >= (1 - u) * 0.55 then
				local t = if dy < half * 0.35 and u > 0.55 then 4 elseif u > 0.3 then 3 else 2
				put(g, x, y, t)
			end
		end
	end
	for y = 0, H - 1 do
		for x = math.floor(hx - 4), W - 1 do
			local dx, dy = x + 0.5 - hx, y + 0.5 - cy
			local d = math.sqrt(dx * dx + dy * dy)
			if d < 1.6 then put(g, x, y, 5) elseif d < 2.7 then put(g, x, y, 4) elseif d < 3.6 then lift(g, x, y, 3) end
		end
	end
	for k = 0, 2 do
		local x = math.floor(hash(k, f, seed) * tail * 0.8)
		local y = if hash(k, f + 1, seed) > 0.5 then 0 else H - 1
		put(g, x, y, 4)
	end
	rim(g, 1)
	return g, math.floor(hx), math.floor(cy)
end

-- CROSS SLASH. Two cuts in an X: one, both, flared, broken.
gen.xslash = function(f: number, seed: number)
	local S = 26
	local g = grid(S, S)
	local th = ({ 1.2, 1.8, 2.6, 1.4 })[f + 1]
	local function cut(x0: number, y0: number, x1: number, y1: number)
		local n = 40
		local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
		local px, py = -(y1 - y0) / len, (x1 - x0) / len
		for i = 0, n do
			local u = i / n
			local w = th * (1 - math.abs(u - 0.5) * 1.7)
			if w > 0 and not (f == 3 and hash(math.floor(u * 9), 4, seed) < 0.4) then
				local x, y = x0 + (x1 - x0) * u, y0 + (y1 - y0) * u
				for o = -math.floor(w), math.floor(w) do
					local t = if o == 0 then 5 elseif math.abs(o) <= 1 then 4 else 3
					if f == 3 then t -= 1 end
					lift(g, x + o * px, y + o * py, t)
				end
			end
		end
	end
	cut(2, 2, S - 3, S - 3)
	if f >= 1 then cut(S - 3, 2, 2, S - 3) end
	rim(g, 1)
	return g, S / 2, S / 2
end

-- BARRIER. A tall shell of light with a lattice through it and a bright rim.
gen.dome = function(_f: number, _seed: number)
	local W, H = 22, 36
	local g = grid(W, H)
	local cx, cy = W / 2, H / 2
	local rx, ry = cx - 0.5, cy - 0.5
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
			local rr = math.sqrt(dx * dx + dy * dy)
			if rr <= 1 then
				local px = x + 0.5
				local py = (y + 0.5) * 0.577
				local onLattice = (math.floor(px) % 6 == 0) or (math.floor(px * 0.5 + py) % 6 == 0)
					or (math.floor(px * 0.5 - py + 100) % 6 == 0)
				if rr > 0.9 then put(g, x, y, if rr > 0.95 then 5 else 4)
				elseif onLattice and (rr > 0.55 or (x + y) % 2 == 0) then put(g, x, y, 14)
				elseif (x + y) % 2 == 0 and rr > 0.6 then put(g, x, y, 13) end
			end
		end
	end
	return g, cx, cy
end

-- SIGHT. A broken circle, four ticks and a pin.
gen.reticle = function(_f: number, _seed: number)
	local S = 21
	local g = grid(S, S)
	local c = 10
	local n = 64
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		local q = (a / (math.pi / 2)) % 1
		if q > 0.12 and q < 0.88 then put(g, c + 0.5 + math.cos(a) * 8, c + 0.5 + math.sin(a) * 8, 3) end
	end
	for k = 5, 10 do
		put(g, c, c - k, 4); put(g, c, c + k, 4); put(g, c - k, c, 4); put(g, c + k, c, 4)
	end
	put(g, c, c, 5)
	return g, c, c
end

-- BLEED MARK. A blood droplet: what a stacked Exsanguinate mark looks like over its victim.
gen.sigil = function(_f: number, _seed: number)
	local rows = {
		"...3...",
		"...3...",
		"..343..",
		"..343..",
		".34443.",
		"3445443",
		"3455543",
		"3444443",
		".34443.",
		"..333..",
	}
	local g = grid(7, #rows)
	for y, row in rows do
		for x = 1, 7 do
			local ch = string.sub(row, x, x)
			if ch ~= "." then put(g, x - 1, y - 1, tonumber(ch) :: number) end
		end
	end
	rim(g, 1)
	return g, 3, 5
end

-- CYCLONE. A funnel of wind, narrow at the floor, banded so the bands crawl as it turns.
-- Anchored at its base.
gen.cyclone = function(f: number, seed: number)
	local W, H = 30, 30
	local g = grid(W, H)
	local c = W / 2
	for y = 0, H - 1 do
		local up = 1 - y / (H - 1)
		local hw = 2.5 + 11.5 * up ^ 0.9
		local ox = math.sin(y * 0.33 + f * 1.57) * 1.8
		for x = 0, W - 1 do
			local u = (x + 0.5 - c - ox) / hw
			if math.abs(u) <= 1 then
				-- streaks wrap the funnel: the phase runs across it as an angle round the axis and
				-- climbs with height, so each streak is a slanted band that crawls as frames advance
				local phase = math.asin(u) / math.pi + y * 0.11 + f * 0.25
				local band = phase * 3 % 1
				local t = 0
				if band < 0.30 then
					t = if math.abs(u) > 0.86 then 5 elseif u > -0.2 then 4 else 3
				elseif band < 0.42 then
					t = 2
				elseif (x + y) % 2 == 0 and hash(x, y, seed + f) > 0.72 then
					t = 12
				end
				if t > 0 then put(g, x, y, t) end
			end
		end
	end
	return g, c, H - 1
end

-- SPARK. A little cross of light thrown off a hit, three frames to vanish.
gen.spark = function(f: number, _seed: number)
	local g = grid(5, 5)
	if f == 0 then
		put(g, 2, 2, 5); put(g, 1, 2, 4); put(g, 3, 2, 4); put(g, 2, 1, 4); put(g, 2, 3, 4)
		put(g, 0, 2, 3); put(g, 4, 2, 3); put(g, 2, 0, 3); put(g, 2, 4, 3)
	elseif f == 1 then
		put(g, 2, 2, 4); put(g, 1, 2, 3); put(g, 3, 2, 3); put(g, 2, 1, 3); put(g, 2, 3, 3)
	else
		put(g, 2, 2, 3)
	end
	return g, 2, 2
end

-- LANCE. A shaft of light ending in a spearhead, along +x: the pike's thrusts and the arrow's
-- flight. Anchored at its tail; the drawing is stretched along x to the reach it has.
gen.lance = function(f: number, seed: number)
	local W, H = 32, 9
	local g = grid(W, H)
	local cy = 4
	for x = 0, W - 8 do
		local u = x / (W - 8)
		local half = if u < 0.15 then 0 else 1
		for o = -half, half do
			local t = if o == 0 then (if hash(x, f, seed) > 0.85 then 4 else 5) else 3
			put(g, x, cy + o, t)
		end
		if f == 1 and x % 6 == 3 then put(g, x, cy - 2, 2); put(g, x, cy + 2, 2) end
	end
	for k = 0, 7 do
		local x = W - 8 + k
		local half = math.floor((7 - k) * 0.5 + 0.5)
		for o = -half, half do
			put(g, x, cy + o, if o == 0 then 5 elseif math.abs(o) == half then 3 else 4)
		end
	end
	rim(g, 1)
	return g, 0, cy
end

-- POP. A short, punchy impact star: eight spikes of uneven length round a white disc. What a
-- landed blow looks like in a fighting game.
gen.pop = function(f: number, seed: number)
	local S = 24
	local g = grid(S, S)
	local c = S / 2
	local scale = ({ 0.55, 1.0, 0.95, 0.75, 0.5 })[f + 1]
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2 + seed * 0.37
		local L = (c - 1) * scale * (if k % 2 == 0 then 1 else 0.62 + hash(k, 0, seed) * 0.2)
		local n = math.ceil(L)
		for i = 0, n do
			local u = i / n
			local w = (1 - u) * (if f <= 1 then 2.2 else 1.4)
			for o = -math.floor(w), math.floor(w) do
				local x = c + math.cos(a) * i - math.sin(a) * o * 0.8
				local y = c + math.sin(a) * i + math.cos(a) * o * 0.8
				local t = if u < 0.35 and math.abs(o) < 1 then 5 elseif u < 0.7 then 4 else 3
				if f >= 3 then t = math.max(2, t - 1) end
				lift(g, x, y, t)
			end
		end
	end
	if f <= 2 then
		local r = ({ 3.2, 4.2, 3.0 })[f + 1]
		for y = 0, S - 1 do
			for x = 0, S - 1 do
				local dx, dy = x + 0.5 - c, y + 0.5 - c
				if dx * dx + dy * dy < r * r then put(g, x, y, 5) end
			end
		end
	end
	if f >= 3 then
		-- the last frames hollow out from the middle
		for y = 0, S - 1 do
			for x = 0, S - 1 do
				local dx, dy = x + 0.5 - c, y + 0.5 - c
				local hollow = (f - 2) * 2 + 1
				if dx * dx + dy * dy < hollow * hollow then put(g, x, y, 0) end
			end
		end
	end
	rim(g, 1)
	return g, c, c
end

-- ------------------------------------------------------------------ compile + cache ----
export type Art = { key: string, rects: { any }, cols: number, rows: number, ax: number, ay: number, ppu: number }

local cache: { [string]: Art } = {}
local function tone(t: number, A: { string }, B: { string }): (string, number)
	if t <= 5 then return A[t], 1 end
	if t <= 10 then return B[t - 5], 1 end
	return A[t - 10], 0.45
end

-- The drawing `kind` at flipbook frame `f`, coloured by ramp A (and B for two-material art),
-- varied by `seed`. Built once; the same table comes back every time, which is what lets
-- Canvas2D.sprite recognise it.
function FxArt.get(kind: string, f: number, a: string?, b: string?, seed: number?): Art
	local n = FxArt.FRAMES[kind] or 1
	local frame = math.clamp(math.floor(f), 0, n - 1)
	local s = seed or 1
	local key = `fx|{kind}|{frame}|{a or "-"}|{b or "-"}|{s}`
	local hit = cache[key]
	if hit then return hit end
	local fn = gen[kind]
	assert(fn, `no effect drawing called {kind}`)
	local g, ax, ay = fn(frame, s)
	local A, B = FxArt.rampOf(a), FxArt.rampOf(b or "earth")
	local rects: { any } = {}
	for i, r in merge(g) do
		local hex, alpha = tone(r[5], A, B)
		local row: { any } = { r[1], r[2], r[3], r[4] }
		row[5], row[6] = hex, alpha
		rects[i] = row
	end
	local art = { key = key, rects = rects, cols = g.w, rows = g.h, ax = ax, ay = ay, ppu = FxArt.PPU }
	cache[key] = art
	return art
end

-- The raw tone grid behind a drawing, for the tests: what the rectangles must reproduce.
function FxArt.paint(kind: string, f: number, seed: number?): (Grid, number, number)
	local n = FxArt.FRAMES[kind] or 1
	return gen[kind](math.clamp(math.floor(f), 0, n - 1), seed or 1)
end

-- Every drawing kind there is, for the sheet tool and the tests.
function FxArt.kinds(): { string }
	local out = {}
	for k in gen do table.insert(out, k) end
	table.sort(out)
	return out
end

-- The scale FxArt.draw needs for `art` to be `width` studs across.
function FxArt.sized(art: Art, width: number): number
	return width * art.ppu / art.cols
end

-- A palette's glow colour (its accent if it has none), and a character's weapon glow: the colour an
-- ultimate's effects are drawn in. Nil when there is none, so the caller picks the fallback.
function FxArt.glow(palette: any): string?
	return if palette then (palette.glow or palette.accent) else nil
end
function FxArt.glowOf(char: any): string?
	return FxArt.glow(char and (char.weaponPalette or char.palette))
end

-- Opacity in sixths: a sprite rewrites every child when its alpha changes, so a fade is a few
-- steps rather than sixty. Pixel art fades in steps anyway.
local function quantise(a: number): number
	return math.clamp(math.floor(a * 6 + 0.5) / 6, 0, 1)
end
FxArt.quantise = quantise

-- Draws `art` with its anchor at (x, y), `scale` times its native size (PPU art pixels a stud),
-- turned by `rot`. `sy` squashes it vertically (a ring lying on the floor).
function FxArt.draw(c: any, art: Art, x: number, y: number, scale: number, rot: number?, alpha: number?, sy: number?)
	local a = quantise(alpha or 1)
	if a <= 0 then return end
	local pw = scale / art.ppu
	Canvas2D.save(c)
	Canvas2D.translate(c, x, y)
	if rot and rot ~= 0 then Canvas2D.rotate(c, rot) end
	if sy and sy ~= 1 then Canvas2D.scale(c, 1, sy) end
	Canvas2D.sprite(c, art.key, art.rects, -art.ax * pw, art.ay * pw, pw, pw, art.cols, art.rows, a, true)
	Canvas2D.restore(c)
end

return FxArt
