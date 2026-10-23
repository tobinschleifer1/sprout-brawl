--!strict
-- The fight camera's framing, at the resolutions players actually have.
--
-- It holds: a close fight fills the screen the same way at every resolution (the camera's ppu is
-- SCREEN pixels - it was the 270-pixel backbuffer's for a long time, which at 1080p showed a fight
-- from four times too far away); a close fight frames a fighter at about a sixth of the screen
-- (22% was tried and played too tight; the web's 14% too far); fighters who separate, even to opposite blast zones or one launched high, all stay on
-- screen; and the camera never zooms past its limit.
--
--     lune run tests/camera
local Loader = require("./loader")
local Camera2D = Loader.loadFrom("src/client/", "Camera2D")

local function fail(msg: string): never
	error(msg, 0)
end

local H = 5.2   -- a fighter's height in studs
local function frame(bodies: { any }, w: number, h: number): any
	local cam = Camera2D.new()
	Camera2D.snapTo(cam, bodies, { X = w, Y = h } :: any)
	return cam
end
-- where a world point lands on the screen, as Canvas2D.world maps it
local function screen(cam: any, w: number, h: number, x: number, y: number): (number, number)
	return w / 2 + (x - cam.x) * cam.ppu, h / 2 - (y - cam.y) * cam.ppu
end
local function body(x: number, y: number): any
	return { x = x, y = y, h = H, alive = true }
end

local checked = 0
local close = { body(-4, 0), body(4, 0) }
local fractions = {}
for _, size in { { 1920, 1080 }, { 1280, 720 }, { 2560, 1080 }, { 812, 375 }, { 1024, 768 } } do
	local w, h = size[1], size[2]
	local cam = frame(close, w, h)
	local frac = H * cam.ppu / h
	table.insert(fractions, string.format("%dx%d %.0f%%", w, h, frac * 100))
	-- close: a fighter about a sixth of the screen tall - near enough to read, far enough to see
	-- the stage round the fight
	if frac < 0.145 or frac > 0.19 then
		fail(`{w}x{h}: a close fight shows a fighter {string.format("%.1f", frac * 100)}% of the screen tall, want 14.5-19%`)
	end
	if cam.ppu / h * Camera2D.BH > Camera2D.ZOOM_MAX + 1e-9 then fail(`{w}x{h}: zoomed past the limit`) end
	-- separated, launched, and at opposite blast zones: everybody stays on screen
	for _, spread in { { body(-30, 0), body(30, 0) }, { body(-3, 0), body(5, 32) }, { body(-95, 4), body(95, 4) },
		{ body(-6, -18), body(6, 40) } } do
		local c = frame(spread, w, h)
		for _, b in spread do
			for _, y in { b.y, b.y + b.h } do
				local sx, sy = screen(c, w, h, b.x, y)
				if sx < 0 or sx > w or sy < 0 or sy > h then
					fail(`{w}x{h}: a fighter at ({b.x}, {y}) is off screen at ({sx}, {sy})`)
				end
				-- and not jammed against the side, where the next step takes them out of view
				if sx < w * 0.03 or sx > w * 0.97 then
					fail(`{w}x{h}: a fighter at x {b.x} is drawn at the very edge of the screen ({sx})`)
				end
			end
		end
		checked += 1
	end
	checked += 1
end
-- with the HUD's card band set, fighters on the floor stay above it when someone is launched high
-- (nothing set the band, so a floor fight went behind the HUD's cards whenever one fighter flew)
for _, size in { { 1280, 720 }, { 1920, 1080 }, { 812, 375 } } do
	local w, h = size[1], size[2]
	local band = 94 * h / 720
	local cam = Camera2D.new()
	Camera2D.setHudBand(cam, band, h)
	local bodies = { body(-6, 0), body(5, 0), body(2, 34) }
	Camera2D.snapTo(cam, bodies, { X = w, Y = h } :: any)
	local _, feet = screen(cam, w, h, -6, 0)
	if feet > h - band then fail(`{w}x{h}: a fighter on the floor is drawn at {feet}, behind the HUD's cards (from {h - band})`) end
	checked += 1
end
-- the top band too: a fighter launched high stays below the clock and key hints (they went behind them)
-- and a fight on the floor keeps two studs of the island in view above the cards (the camera's own
-- padding holds it: a floor rule added for it changed nothing, and went)
for _, size in { { 1280, 720 }, { 1920, 1080 } } do
	local w, h = size[1], size[2]
	local bottom, top = 94 * h / 720, 92 * h / 720
	local cam = Camera2D.new()
	Camera2D.setHudBand(cam, bottom, h, top)
	Camera2D.snapTo(cam, { body(-6, 0), body(5, 0), body(2, 36) }, { X = w, Y = h } :: any)
	local _, head = screen(cam, w, h, 2, 36 + H)
	-- (clear of the clock, the hints and the ULTIMATE READY banner under them: 128 px at 720)
	local banner = 128 * h / 720
	if head < banner then fail(`{w}x{h}: a fighter launched high is drawn at {head}, behind the top of the HUD (to {banner})`) end
	local floor = Camera2D.new()
	Camera2D.setHudBand(floor, bottom, h, top)
	-- (two just over it, mid-hop, and one launched high pulling the camera up: framed by their bodies
	-- alone, the floor fell under the cards)
	Camera2D.snapTo(floor, { body(-4, 0.5), body(4, 1), body(2, 28) }, { X = w, Y = h } :: any)
	local _, under = screen(floor, w, h, 0, -2)
	if under > h - bottom + 0.5 then fail(`{w}x{h}: two studs under the floor are at {under}, behind the cards (from {h - bottom})`) end
	checked += 2
end
-- the main floor stays above the cards while the fight is on the platforms over it: framed by bodies
-- alone, Foundry's floor sat wholly under the cards in the maps' round 2 renders (my first test of this
-- stood the fighters on the floor, where the padding already showed it, and missed the case)
for _, size in { { 1280, 720 }, { 1920, 1080 } } do
	local w, h = size[1], size[2]
	local bottom = 94 * h / 720
	local cam = Camera2D.new()
	Camera2D.setHudBand(cam, bottom, h, 92 * h / 720)
	Camera2D.setFloor(cam, 0)
	Camera2D.snapTo(cam, { body(-8, 9), body(8, 9), body(0, 20) }, { X = w, Y = h } :: any)
	local _, floorY = screen(cam, w, h, 0, 0)
	if floorY > h - bottom - 8 then fail(`{w}x{h}: the main floor is drawn at {floorY}, under the cards (from {h - bottom})`) end
	checked += 1
end
-- the same framing at every 16:9 resolution: the unit is screen pixels, scaled to the window
local a, b = frame(close, 1920, 1080), frame(close, 1280, 720)
if math.abs(a.ppu / 1080 - b.ppu / 720) > 1e-9 then fail("1080p and 720p frame a fight differently") end
print(`PASS camera: {checked} framings on screen at five resolutions; a close fight is {table.concat(fractions, ", ")} a fighter tall`)
