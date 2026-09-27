--!strict
-- A 2D canvas built out of Roblox UI.
--
-- web/src/render2d/* is a Canvas2D renderer: it pushes transforms, fills rectangles and arcs, and
-- pops. Roblox has no such API, so this provides one - the same transform stack, the same
-- primitives - backed by pooled Frames in a ScreenGui. Everything above this file can then be a
-- close translation of the JavaScript instead of a reinvention, which is the only way the two
-- builds stay recognisably the same game.
--
-- WHAT A FRAME CAN AND CANNOT DO. A Frame is a rectangle with one rotation about its centre, so an
-- affine transform made of translation, rotation, mirroring and uniform scale reproduces exactly.
-- A non-uniform scale applied BEFORE a rotation shears, and a sheared rectangle is not a Frame.
-- `rect` decomposes the current matrix and a shear is dropped rather than approximated - the size
-- comes out right and the skew does not happen. Squash-and-stretch during a rotated pose is
-- therefore slightly less extreme here than on the web. Nothing else in the renderer shears.
--
-- Arbitrary polygons are not drawable at all, which is why `tri` exists: it staircases. On art this
-- blocky a six-step triangle reads as a triangle, and it costs six Frames and no uploaded assets.

local Canvas2D = {}
Canvas2D.__index = Canvas2D

-- A 2x3 affine matrix, as Canvas2D stores one: screen = (a*x + c*y + e, b*x + d*y + f).
type Matrix = { a: number, b: number, c: number, d: number, e: number, f: number }

local function identity(): Matrix
	return { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 }
end

local function mul(m: Matrix, n: Matrix): Matrix
	-- n applied first, then m - the order a canvas composes in, so translate/rotate/scale read the
	-- same way round as they do in the JavaScript.
	return {
		a = m.a * n.a + m.c * n.b,
		b = m.b * n.a + m.d * n.b,
		c = m.a * n.c + m.c * n.d,
		d = m.b * n.c + m.d * n.d,
		e = m.a * n.e + m.c * n.f + m.e,
		f = m.b * n.e + m.d * n.f + m.f,
	}
end

function Canvas2D.new(parent: Instance): any
	local self = setmetatable({}, Canvas2D)

	local gui = Instance.new("ScreenGui")
	gui.Name = "Blockfall"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10
	gui.Parent = parent
	self.gui = gui

	local world = Instance.new("Frame")
	world.Name = "World"
	world.Size = UDim2.fromScale(1, 1)
	world.BackgroundTransparency = 1
	world.Parent = gui
	self.layer = world

	self.pool = {} :: { Frame }
	self.used = 0
	self.z = 0
	self.m = identity()
	self.stack = {} :: { Matrix }
	self.alpha = 1
	self.alphaStack = {} :: { number }
	self.sprites = {} :: { [string]: any }
	self.spriteUse = {} :: { [string]: number }
	self.frameNo = 0
	return self
end

-- Palette entries arrive from the shared data layer as the CSS hex strings the web build uses.
-- Embedded canvases reuse the exact same weapon art inside loadout cards.
function Canvas2D.inFrame(frame: Frame): any
	return setmetatable({ gui = frame, layer = frame, pool = {}, used = 0, z = 0,
		m = identity(), stack = {}, alpha = 1, alphaStack = {}, sprites = {}, spriteUse = {}, frameNo = 0 }, Canvas2D)
end

-- Parsed rather than converted at generation time, so the two builds read the same data file.
local HEX_CACHE: { [string]: Color3 } = {}
function Canvas2D.hex(s: string?, fallback: Color3): Color3
	if type(s) ~= "string" then
		return fallback
	end
	local hit = HEX_CACHE[s]
	if hit then
		return hit
	end
	local ok, c = pcall(Color3.fromHex, s)
	if not ok then
		return fallback
	end
	HEX_CACHE[s] = c
	return c
end

-- ---------------------------------------------------------------- transform stack ----
function Canvas2D.save(self: any)
	table.insert(self.stack, table.clone(self.m))
	table.insert(self.alphaStack, self.alpha)
end

function Canvas2D.restore(self: any)
	local m = table.remove(self.stack)
	if m then
		self.m = m
	end
	local a = table.remove(self.alphaStack)
	if a then
		self.alpha = a
	end
end

function Canvas2D.translate(self: any, x: number, y: number)
	self.m = mul(self.m, { a = 1, b = 0, c = 0, d = 1, e = x, f = y })
end

function Canvas2D.rotate(self: any, rad: number)
	local c, s = math.cos(rad), math.sin(rad)
	self.m = mul(self.m, { a = c, b = s, c = -s, d = c, e = 0, f = 0 })
end

function Canvas2D.scale(self: any, sx: number, sy: number)
	self.m = mul(self.m, { a = sx, b = 0, c = 0, d = sy, e = 0, f = 0 })
end

-- Replaces the matrix outright. Used once a frame to install the world transform, and again to go
-- back to screen space for anything measured in pixels.
function Canvas2D.setTransform(self: any, a: number, b: number, c: number, d: number, e: number, f: number)
	self.m = { a = a, b = b, c = c, d = d, e = e, f = f }
end

-- The camera, expressed exactly as web/src/render2d/renderer2d.js `_world` expresses it: world
-- units scale by ppu, Y flips, and the camera centre lands in the middle of the viewport.
function Canvas2D.world(self: any, camX: number, camY: number, ppu: number, shakeX: number, shakeY: number)
	local vp = self.gui.AbsoluteSize
	Canvas2D.setTransform(self, ppu, 0, 0, -ppu,
		vp.X / 2 - camX * ppu + shakeX, vp.Y / 2 + camY * ppu + shakeY)
end

function Canvas2D.screen(self: any)
	Canvas2D.setTransform(self, 1, 0, 0, 1, 0, 0)
end

-- A world point in screen pixels, through whatever matrix is currently installed. The HUD floats
-- a percent over each fighter's head and lives in its own ScreenGui, so it needs the renderer's
-- camera without a second copy of the camera's arithmetic - which is the kind of duplicate that
-- stays right until somebody changes one of them.
function Canvas2D.project(self: any, x: number, y: number): Vector2
	local m = self.m
	return Vector2.new(m.a * x + m.c * y + m.e, m.b * x + m.d * y + m.f)
end

function Canvas2D.viewport(self: any): Vector2
	return self.gui.AbsoluteSize
end

-- ---------------------------------------------------------------- frame pool ----
-- Frames are reused between draws and never destroyed. Creating and destroying a few hundred
-- Instances per frame is the one thing guaranteed to make a UI renderer unusable.
local function take(self: any): Frame
	self.used += 1
	local f = self.pool[self.used]
	if not f then
		f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundTransparency = 0
		local corner = Instance.new("UICorner")
		corner.Name = "Corner"
		corner.CornerRadius = UDim.new(0, 0)
		corner.Parent = f
		f.Parent = self.layer
		self.pool[self.used] = f
	end
	f.Visible = true
	self.z += 1
	f.ZIndex = self.z
	return f
end

-- Called at the end of a frame: anything the draw did not claim is hidden rather than destroyed.
-- `purge` destroys the sprites this frame did not draw straight away instead of after ten seconds:
-- for a canvas drawn once per change (a creator thumbnail), where anything not drawn now is a
-- picture that will never come back.
function Canvas2D.finish(self: any, purge: boolean?)
	for i = self.used + 1, #self.pool do
		local f = self.pool[i]
		if not f.Visible then
			break            -- everything past the first hidden frame was hidden last time too
		end
		f.Visible = false
	end
	self.used = 0
	self.z = 0
	-- Sprites nobody drew this frame are hidden; ones nobody has drawn for ten seconds (a player
	-- who left, a character that was changed) are destroyed, because they are not reusable by
	-- anything else - their children are one particular picture.
	if self.sprites then
		for key, sp in self.sprites do
			if sp.seen ~= self.frameNo then
				sp.frame.Visible = false
				if purge or self.frameNo - sp.seen > 600 then
					sp.frame:Destroy()
					self.sprites[key] = nil
				end
			end
		end
		table.clear(self.spriteUse)
		self.frameNo += 1
	end
end

function Canvas2D.clear(self: any)
	for _, f in self.pool do
		f.Visible = false
	end
	self.used = 0
	self.z = 0
	if self.sprites then
		for _, sp in self.sprites do
			sp.frame.Visible = false
		end
		table.clear(self.spriteUse)
	end
end

-- ---------------------------------------------------------------- primitives ----
-- A rectangle in the current transform's space, with its corner at (x, y) and extending by (w, h) -
-- the same convention as fillRect, including negative sizes.
function Canvas2D.rect(self: any, x: number, y: number, w: number, h: number, colour: Color3, alpha: number?)
	local m = self.m
	local cx, cy = x + w / 2, y + h / 2
	local sx = m.a * cx + m.c * cy + m.e
	local sy = m.b * cx + m.d * cy + m.f
	-- Column lengths are the scale along each axis; the rotation is the angle of the x axis. Roblox
	-- UI rotates clockwise and screen Y already points down, so the angle needs no sign flip.
	local ax, ay = m.a * w, m.b * w
	local bx, by = m.c * h, m.d * h
	local sizeX = math.sqrt(ax * ax + ay * ay)
	local sizeY = math.sqrt(bx * bx + by * by)
	if sizeX < 0.5 and sizeY < 0.5 then
		return          -- smaller than a pixel: drawing it costs a Frame and shows nothing
	end
	local f = take(self)
	f.Position = UDim2.fromOffset(sx, sy)
	f.Size = UDim2.fromOffset(math.max(1, sizeX), math.max(1, sizeY))
	f.Rotation = math.deg(math.atan2(ay, ax))
	f.BackgroundColor3 = colour
	f.BackgroundTransparency = 1 - (alpha or 1) * self.alpha
	;(f:FindFirstChild("Corner") :: UICorner).CornerRadius = UDim.new(0, 0)
end

-- ---------------------------------------------------------------- sprites ----
-- A picture made of many rectangles that always move together: a kit character's head, a limb.
--
-- Drawing each rectangle with `rect` would re-place every one of them every frame - a character is
-- well over a hundred - so a sprite is ONE container Frame placed exactly like a rect, holding its
-- rectangles as children laid out in scale units. Per frame only the container moves; the
-- children are touched when the picture changes, when the drawing mirrors, or when the alpha does.
--
-- `rects` are { col, row, w, h, hex, alpha } in cells of a `cols` x `rows` canvas whose top-left
-- corner is at (x0, y1) in the current transform's space, with cells `pw` wide and `ph` tall and
-- rows running DOWN from y1 (the art's rows) while the space's y runs up. The same `rects` table
-- must come back for the same key each frame: identity is how a sprite knows it is unchanged.
--
-- Mirroring: a Frame can rotate but not flip. The container's x axis follows the transform's; if
-- the transform is orientation-preserving on screen (det > 0 - the world flips y, so this is a
-- facing of -1) the art's rows have to run up the container instead of down, and a vertical flip
-- under the container's 180-degree turn is exactly the horizontal mirror the facing asked for.
function Canvas2D.eachSpriteRect(rects: { any }, x0: number, y1: number, pw: number, ph: number,
	fn: (number, number, number, number, string, number) -> ())
	for _, r in rects do
		fn(x0 + r[1] * pw, y1 - (r[2] + r[4]) * ph, r[3] * pw, r[4] * ph, r[5], r[6])
	end
end

function Canvas2D.sprite(self: any, key: string, rects: { any }, x0: number, y1: number, pw: number, ph: number,
	cols: number, rows: number, alpha: number?)
	local m = self.m
	local w, h = cols * pw, rows * ph
	local cx, cy = x0 + w / 2, y1 - h / 2
	local sx = m.a * cx + m.c * cy + m.e
	local sy = m.b * cx + m.d * cy + m.f
	local ax, ay = m.a * w, m.b * w
	local bx, by = m.c * h, m.d * h
	local sizeX = math.sqrt(ax * ax + ay * ay)
	local sizeY = math.sqrt(bx * bx + by * by)
	if sizeX < 0.5 and sizeY < 0.5 then
		return
	end
	local flip = m.a * m.d - m.b * m.c > 0
	local n = (self.spriteUse[key] or 0) + 1
	self.spriteUse[key] = n
	local slot = key .. "#" .. n
	local sp = self.sprites[slot]
	if not sp then
		local f = Instance.new("Frame")
		f.Name = "Sprite"
		f.BorderSizePixel = 0
		f.BackgroundTransparency = 1
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Parent = self.layer
		sp = { frame = f, children = {}, seen = self.frameNo }
		self.sprites[slot] = sp
	end
	if sp.rects ~= rects then
		for _, child in sp.children do
			child:Destroy()
		end
		table.clear(sp.children)
		for i, r in rects do
			local child = Instance.new("Frame")
			child.BorderSizePixel = 0
			child.BackgroundColor3 = Canvas2D.hex(r[5], Color3.new(1, 0, 1))
			child.ZIndex = i
			child.Parent = sp.frame
			sp.children[i] = child
		end
		sp.rects, sp.flip, sp.alpha = rects, nil, nil
	end
	if sp.flip ~= flip then
		for i, r in rects do
			local row = if flip then rows - r[2] - r[4] else r[2]
			sp.children[i].Position = UDim2.fromScale(r[1] / cols, row / rows)
			sp.children[i].Size = UDim2.fromScale(r[3] / cols, r[4] / rows)
		end
		sp.flip = flip
	end
	local a = (alpha or 1) * self.alpha
	if sp.alpha ~= a then
		for i, r in rects do
			sp.children[i].BackgroundTransparency = 1 - r[6] * a
		end
		sp.alpha = a
	end
	local f = sp.frame
	f.Position = UDim2.fromOffset(sx, sy)
	f.Size = UDim2.fromOffset(math.max(1, sizeX), math.max(1, sizeY))
	f.Rotation = math.deg(math.atan2(ay, ax))
	self.z += 1
	f.ZIndex = self.z
	f.Visible = true
	sp.seen = self.frameNo
end

-- An ellipse centred on (x, y). UICorner at half the smaller side rounds a Frame into a capsule,
-- and into an ellipse when the sides are equal, which covers every arc this renderer draws.
function Canvas2D.ellipse(self: any, x: number, y: number, rx: number, ry: number, colour: Color3, alpha: number?)
	local before = self.used
	Canvas2D.rect(self, x - rx, y - ry, rx * 2, ry * 2, colour, alpha)
	if self.used > before then
		local f = self.pool[self.used]
		;(f:FindFirstChild("Corner") :: UICorner).CornerRadius = UDim.new(0.5, 0)
	end
end

-- A line segment of the given width, as a rotated rectangle: what a canvas stroke is here.
function Canvas2D.line(self: any, x0: number, y0: number, x1: number, y1: number, width: number, colour: Color3, alpha: number?)
	local dx, dy = x1 - x0, y1 - y0
	Canvas2D.save(self)
	Canvas2D.translate(self, x0, y0)
	Canvas2D.rotate(self, math.atan2(dy, dx))
	Canvas2D.rect(self, 0, -width / 2, math.sqrt(dx * dx + dy * dy), width, colour, alpha)
	Canvas2D.restore(self)
end

function Canvas2D.circle(self: any, x: number, y: number, r: number, colour: Color3, alpha: number?)
	Canvas2D.ellipse(self, x, y, r, r, colour, alpha)
end

-- A triangle, staircased. (x0, y0) is the apex; the base runs from (x1, y1) to (x2, y2) - which is
-- the shape every polygon in avatar2d.js reduces to. See the note at the top of this file: Roblox
-- UI cannot fill a polygon, and stepping it suits art this blocky better than an uploaded sprite.
local TRI_STEPS = 6
function Canvas2D.tri(self: any, x0: number, y0: number, x1: number, y1: number, x2: number, y2: number,
	colour: Color3, alpha: number?)
	for i = 0, TRI_STEPS - 1 do
		local t0 = i / TRI_STEPS
		local t1 = (i + 1) / TRI_STEPS
		-- Each step is the quad between two slices of the triangle, drawn as the rectangle that
		-- spans the wider of the two. Walking apex to base keeps the silhouette's outer edge exact.
		local ax0, ay0 = x1 + (x0 - x1) * (1 - t1), y1 + (y0 - y1) * (1 - t1)
		local bx0, by0 = x2 + (x0 - x2) * (1 - t1), y2 + (y0 - y2) * (1 - t1)
		local ax1, ay1 = x1 + (x0 - x1) * (1 - t0), y1 + (y0 - y1) * (1 - t0)
		local left = math.min(ax0, bx0, ax1)
		local right = math.max(ax0, bx0, ax1)
		local top = math.min(ay0, by0, ay1)
		local bottom = math.max(ay0, by0, ay1)
		Canvas2D.rect(self, left, top, right - left, bottom - top, colour, alpha)
	end
end

return Canvas2D
