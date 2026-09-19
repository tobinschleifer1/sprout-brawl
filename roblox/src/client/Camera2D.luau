--!strict
-- The locked-plane camera, ported from web/src/render2d/renderer2d.js `_camera`.
--
-- The web build's camera works in pixels-per-unit against a fixed 270-pixel backbuffer. Roblox has
-- no orthographic camera, so the same framing is reproduced with a perspective camera pushed far
-- enough back that the world height it sees matches: at distance d and vertical field of view fov,
-- the visible height is 2 * d * tan(fov/2). Solve for d and the framing is identical; the only
-- difference is a little perspective on the stage's 8 studs of depth, which reads as thickness.
--
-- Everything the original does about framing carries over unchanged, including the two fixes that
-- are not obvious: the zoom floor is 2.0 (at 2.4 a chase to opposite blast zones no longer fits
-- since the blast boxes were widened) and the HUD band along the bottom is subtracted from the
-- usable height and half-added back to the centre, so fighters on the floor are not pushed behind
-- the HUD when somebody is launched high.

local BH = 270                -- the web backbuffer height, in "pixels". The unit ppu is measured in.
local FOV = 55                -- degrees, vertical
local ZOOM_MIN, ZOOM_MAX = 2.0, 7.2
local PAD = 20

local Camera2D = {}
Camera2D.__index = Camera2D

function Camera2D.new(camera: Camera): any
	local self = setmetatable({}, Camera2D)
	self.camera = camera
	self.x, self.y, self.ppu = 0, 10, 4
	self.safeBottom = 0        -- studs of screen the HUD covers, set by the HUD
	self.shake = 0
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FOV
	return self
end

-- `bodies` is a list of { x, y, h, alive }.
function Camera2D.update(self: any, bodies: { any }, dt: number, instant: boolean?)
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
	local vp = self.camera.ViewportSize
	local BW = BH * (if vp.Y > 0 then vp.X / vp.Y else 16 / 9)

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
	self:apply()
end

function Camera2D.apply(self: any)
	local visibleHeight = BH / self.ppu
	local dist = (visibleHeight / 2) / math.tan(math.rad(FOV) / 2)
	local sx, sy = 0, 0
	if self.shake > 0 then
		sx = (math.random() - 0.5) * self.shake * 2
		sy = (math.random() - 0.5) * self.shake * 2
	end
	-- +Z looking back toward the origin: with that orientation Roblox's +X is screen-right and +Y
	-- is screen-up, which is the web build's coordinate system with no sign flips anywhere.
	local pos = Vector3.new(self.x + sx, self.y + sy, dist)
	self.camera.CFrame = CFrame.lookAt(pos, Vector3.new(self.x + sx, self.y + sy, 0))
end

function Camera2D.snapTo(self: any, bodies: { any })
	Camera2D.update(self, bodies, 1, true)
end

return Camera2D
