--!strict
-- The locked-plane camera, ported from web/src/render2d/renderer2d.js `_camera`.
--
-- The framing works in pixels-per-unit against the JavaScript's fixed 270-pixel backbuffer, and
-- keeps the two fixes in it that are not obvious: a low zoom floor (at 2.4 a chase to opposite
-- blast zones no longer fit once the blast boxes were widened) and the HUD band along the bottom
-- is subtracted from the usable height and half-added back to the centre, so fighters on the floor
-- are not pushed behind the HUD when somebody is launched high.
--
-- THE UNIT, and the bug it was. The framing below works in the web's 270-pixel backbuffer, but the
-- canvas draws in SCREEN pixels, and for a long time the backbuffer ppu went to the canvas as if it
-- were screen pixels: at 1080p a fight showed ~150 studs top to bottom instead of ~37, and a fighter
-- stood 3% of the screen tall. `ppu` is now screen pixels a stud: the backbuffer framing scaled by
-- viewport height / 270, so the framing is the same picture at every resolution.
--
-- THE FRAMING is Roblox's own, closer than the web's: Brawlhalla holds two fighters in a scrap at
-- around a fifth of the screen's height and only pulls out as they separate. ZOOM_MAX 11.5 with
-- tighter padding puts a fighter at ~22% when the fight is close (the web's 7.2 is 14%). The floor
-- is 1.6, not the web's 2.0: Roblox also runs in 4:3 windows and on tablets, where 2.0 lost a
-- fighter off the edge in a chase 95 studs out either side (tests/camera.luau).
local BH = 270                -- the web backbuffer height: the unit the framing is worked out in
local ZOOM_MIN, ZOOM_MAX = 1.6, 11.5
local PAD = 12                -- studs kept clear either side of the outermost fighters
local MIN_W, MIN_H = 30, 21   -- the least world the camera will show, in studs

local Camera2D = {}
Camera2D.__index = Camera2D
Camera2D.ZOOM_MIN, Camera2D.ZOOM_MAX, Camera2D.BH = ZOOM_MIN, ZOOM_MAX, BH

function Camera2D.new(): any
	local self = setmetatable({}, Camera2D)
	self.x, self.y, self.ppu = 0, 10, 16
	self.safeBottom = 0        -- backbuffer pixels the HUD covers, set by the HUD
	self.shake = 0
	self.shakeX, self.shakeY = 0, 0
	return self
end

-- `bodies` is a list of { x, y, h, alive }. `viewport` is the canvas size in pixels.
function Camera2D.update(self: any, bodies: { any }, dt: number, viewport: Vector2, instant: boolean?)
	local src = {}
	for _, b in bodies do
		if b.alive then
			table.insert(src, b)
		end
	end
	if #src == 0 then
		src = bodies
	end
	local x0, x1 = math.huge, -math.huge
	local y0, y1 = math.huge, -math.huge
	for _, b in src do
		x0 = math.min(x0, b.x); x1 = math.max(x1, b.x)
		y0 = math.min(y0, b.y); y1 = math.max(y1, b.y + b.h)
	end
	if x0 == math.huge then
		x0, x1, y0, y1 = 0, 0, 0, 10
	end

	-- The web backbuffer is 480x270 and its width varies with the window; here the width that
	-- matters is the viewport's own, expressed in the same 270-tall units. Hard-coding 480 would
	-- frame an ultrawide monitor as if it were 16:9 and zoom out for room it already had.
	local BW = BH * (if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9)

	local w = math.max(MIN_W, x1 - x0 + PAD * 2)
	local band = math.clamp(self.safeBottom, 0, BH * 0.45)
	local usable = BH - band
	local hgt = math.max(MIN_H, y1 - y0 + PAD)
	local ppu = math.clamp(math.min(BW / w, usable / hgt), ZOOM_MIN, ZOOM_MAX)

	local tx = (x0 + x1) / 2
	local ty = (y0 + y1) / 2 + 2 - band / (2 * ppu)
	ppu *= (if viewport.Y > 0 then viewport.Y else BH) / BH     -- backbuffer -> screen pixels
	-- Frame-rate independent smoothing: the same 0.0025-per-second constant the web build uses, so
	-- the camera has the same weight at 60 and at 144.
	local k = if instant then 1 else 1 - 0.0025 ^ dt
	self.x += (tx - self.x) * k
	self.y += (ty - self.y) * k
	self.ppu += (ppu - self.ppu) * k
	Camera2D.apply(self)
end

-- Shake is resolved here rather than inside the transform so that every draw in a frame shares one
-- offset. Resolving it per primitive would shake the fighters apart from the stage.
function Camera2D.apply(self: any)
	if self.shake > 0 then
		self.shakeX = (math.random() - 0.5) * self.shake * 2
		self.shakeY = (math.random() - 0.5) * self.shake * 2
	else
		self.shakeX, self.shakeY = 0, 0
	end
end

function Camera2D.snapTo(self: any, bodies: { any }, viewport: Vector2)
	Camera2D.update(self, bodies, 1, viewport, true)
end

return Camera2D
