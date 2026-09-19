--!strict
-- The locked-plane camera, ported from web/src/render2d/renderer2d.js `_camera`.
--
-- The camera is pixels-per-unit against a fixed 270-pixel backbuffer, which is what it is in the
-- JavaScript too. It briefly had to fake that with a perspective camera pushed far enough back that
-- the world height matched; drawing to a canvas instead means ppu means exactly what it says again,
-- and this file is now a straight port with no conversion in it at all.
--
-- Everything the original does about framing carries over unchanged, including the two fixes that
-- are not obvious: the zoom floor is 2.0 (at 2.4 a chase to opposite blast zones no longer fits
-- since the blast boxes were widened) and the HUD band along the bottom is subtracted from the
-- usable height and half-added back to the centre, so fighters on the floor are not pushed behind
-- the HUD when somebody is launched high.

local BH = 270                -- the web backbuffer height, in "pixels". The unit ppu is measured in.
local ZOOM_MIN, ZOOM_MAX = 2.0, 7.2
local PAD = 20

local Camera2D = {}
Camera2D.__index = Camera2D

function Camera2D.new(): any
	local self = setmetatable({}, Camera2D)
	self.x, self.y, self.ppu = 0, 10, 4
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

	local w = math.max(42, x1 - x0 + PAD * 2)
	local band = math.clamp(self.safeBottom, 0, BH * 0.45)
	local usable = BH - band
	local hgt = math.max(28, y1 - y0 + PAD)
	local ppu = math.clamp(math.min(BW / w, usable / hgt), ZOOM_MIN, ZOOM_MAX)

	local tx = (x0 + x1) / 2
	local ty = (y0 + y1) / 2 + 2 - band / (2 * ppu)
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
