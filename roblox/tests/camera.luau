--!strict
-- The fight camera's framing, at the resolutions players actually have.
--
-- It holds: a close fight fills the screen the same way at every resolution (the camera's ppu is
-- SCREEN pixels - it was the 270-pixel backbuffer's for a long time, which at 1080p showed a fight
-- from four times too far away); a close fight is Brawlhalla-close, a fighter about a fifth of the
-- screen tall; fighters who separate, even to opposite blast zones or one launched high, all stay on
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
	-- close: Brawlhalla-close, a fighter about a fifth of the screen tall
	if frac < 0.18 or frac > 0.30 then
		fail(`{w}x{h}: a close fight shows a fighter {string.format("%.1f", frac * 100)}% of the screen tall, want 18-30%`)
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
-- the same framing at every 16:9 resolution: the unit is screen pixels, scaled to the window
local a, b = frame(close, 1920, 1080), frame(close, 1280, 720)
if math.abs(a.ppu / 1080 - b.ppu / 720) > 1e-9 then fail("1080p and 720p frame a fight differently") end
print(`PASS camera: {checked} framings on screen at five resolutions; a close fight is {table.concat(fractions, ", ")} a fighter tall`)
