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
	self.poolState = {} :: { any }   -- what was last written to each pooled Frame (see take)
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
	return setmetatable({ gui = frame, layer = frame, pool = {}, poolState = {}, used = 0, z = 0,
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
	self.vpW, self.vpH = vp.X, vp.Y        -- for culling (see offscreen)
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
--
-- The second thing is writing properties. Every write to a Frame crosses into the engine, even
-- when the value is the one it already has - and a draw re-places every Frame, every frame. So
-- each pooled Frame (and each sprite container) keeps what was last written to it in a plain
-- table, and a property is written only when its value changes. Measured in Studio with 24 people
-- in the lobby, the end-of-frame hide pass alone was 1.8ms a frame: it re-hid every sprite on the
-- whole street, most of which had been hidden for minutes.
local function take(self: any): (Frame, any)
	self.used += 1
	local f = self.pool[self.used]
	local st: any
	if not f then
		f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundTransparency = 0
		f.Visible = false
		local corner = Instance.new("UICorner")
		corner.Name = "Corner"
		corner.CornerRadius = UDim.new(0, 0)
		corner.Parent = f
		f.Parent = self.layer
		self.pool[self.used] = f
		st = { corner = corner, round = false, vis = false }
		self.poolState[self.used] = st
	else
		st = self.poolState[self.used]
	end
	if not st.vis then
		f.Visible = true
		st.vis = true
	end
	self.z += 1
	if st.z ~= self.z then
		f.ZIndex = self.z
		st.z = self.z
	end
	return f, st
end

-- Called at the end of a frame: anything the draw did not claim is hidden rather than destroyed.
-- `purge` destroys the sprites this frame did not draw straight away instead of after ten seconds:
-- for a canvas drawn once per change (a creator thumbnail), where anything not drawn now is a
-- picture that will never come back.
function Canvas2D.finish(self: any, purge: boolean?)
	-- what this frame drew, for the performance monitor
	self.lastUsed = self.used
	local sprites = 0
	for _, k in self.spriteUse or {} do sprites += k end
	self.lastSprites = sprites
	for i = self.used + 1, #self.pool do
		local st = self.poolState[i]
		if not st.vis then
			break            -- everything past the first hidden frame was hidden last time too
		end
		self.pool[i].Visible = false
		st.vis = false
	end
	self.used = 0
	self.z = 0
	-- Sprites nobody drew this frame are hidden; ones nobody has drawn for ten seconds (a player
	-- who left, a character that was changed) are destroyed, because they are not reusable by
	-- anything else - their children are one particular picture.
	if self.sprites then
		for key, sp in self.sprites do
			if sp.seen ~= self.frameNo then
				if sp.vis then
					sp.frame.Visible = false
					sp.vis = false
				end
				if purge or self.frameNo - sp.seen > 600 then
					sp.frame:Destroy()
					self.sprites[key] = nil
				end
			end
		end
		table.clear(self.spriteUse)
		self.frameNo += 1
		self.built = 0
	end
end

function Canvas2D.clear(self: any)
	for i, f in self.pool do
		f.Visible = false
		self.poolState[i].vis = false
	end
	self.used = 0
	self.z = 0
	if self.sprites then
		for _, sp in self.sprites do
			sp.frame.Visible = false
			sp.vis = false
		end
		table.clear(self.spriteUse)
	end
end

-- Where a Frame goes, written only where it moved: Position, Size and Rotation.
local function place(f: Frame, st: any, sx: number, sy: number, w: number, h: number, rot: number)
	if st.px ~= sx or st.py ~= sy then
		f.Position = UDim2.fromOffset(sx, sy)
		st.px, st.py = sx, sy
	end
	if st.w ~= w or st.h ~= h then
		f.Size = UDim2.fromOffset(w, h)
		st.w, st.h = w, h
	end
	if st.rot ~= rot then
		f.Rotation = rot
		st.rot = rot
	end
end

-- A box centred on (sx, sy) in screen pixels, sizeX by sizeY at any rotation, lies wholly outside
-- the viewport: nothing of it would show, so it is not placed at all (finish hides what it held).
-- Half the sum of the sides bounds half the diagonal, so nothing partly on screen is ever culled.
-- The lobby is a street 440 studs long and a screen shows about 70 of it. A canvas that has not had
-- `world` called (a portrait tile) knows no viewport and culls nothing.
local function offscreen(self: any, sx: number, sy: number, sizeX: number, sizeY: number): boolean
	local W, H = self.vpW, self.vpH
	if not W then return false end
	local r = (sizeX + sizeY) * 0.5
	return sx + r < 0 or sx - r > W or sy + r < 0 or sy - r > H
end
Canvas2D.offscreen = offscreen

-- ---------------------------------------------------------------- primitives ----
-- A rectangle in the current transform's space, with its corner at (x, y) and extending by (w, h) -
-- the same convention as fillRect, including negative sizes.
-- `round` makes it an ellipse (see Canvas2D.ellipse); decided here, so a round Frame is not squared
-- and rounded again every frame.
local function box(self: any, x: number, y: number, w: number, h: number, colour: Color3, alpha: number?, round: boolean)
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
	if offscreen(self, sx, sy, sizeX, sizeY) then
		return
	end
	local f, st = take(self)
	place(f, st, sx, sy, math.max(1, sizeX), math.max(1, sizeY), math.deg(math.atan2(ay, ax)))
	if st.colour ~= colour then
		f.BackgroundColor3 = colour
		st.colour = colour
	end
	local transparency = 1 - (alpha or 1) * self.alpha
	if st.tr ~= transparency then
		f.BackgroundTransparency = transparency
		st.tr = transparency
	end
	if st.round ~= round then
		st.corner.CornerRadius = if round then UDim.new(0.5, 0) else UDim.new(0, 0)
		st.round = round
	end
end

function Canvas2D.rect(self: any, x: number, y: number, w: number, h: number, colour: Color3, alpha: number?)
	box(self, x, y, w, h, colour, alpha, false)
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

-- BUILDING is the expensive part: measured in Studio, about 10 microseconds a child, so a 200-cell
-- explosion costs 2ms the first time it is seen, and an impact that starts four effects at once
-- could spend 5ms in one frame. A `deferrable` sprite (an effect, never a body part or a weapon) is
-- therefore built only while this frame has built fewer than BUILD_PER_FRAME children; past that it
-- waits a frame. An effect a frame late is invisible; a hitch is not.
Canvas2D.BUILD_PER_FRAME = 360

-- IMAGES. Where the engine allows it, a sprite is not a container of Frames at all but ONE
-- ImageLabel showing an EditableImage the rectangles were painted into, pixel for pixel (one art
-- cell, one pixel; Pixelated resampling keeps it crisp at any size). Measured in Studio: fifty
-- 64x64 images built in 2ms, where one 200-cell sprite of Frames took 2ms by itself - and an image
-- is one Instance for the engine to lay out each time the camera moves, not two hundred, and its
-- fade is one property rather than a write to every child. A mirrored drawing is its own image
-- (the rows reversed, as the Frame path does under the container's half turn).
--
-- EditableImage can be unavailable (an experience without the permission, a device out of image
-- memory, outside Roblox): creation is tried once, and on failure - or for a picture larger than an
-- EditableImage can be - the sprite falls back to Frames, unchanged. Canvas2D.IMAGES = false forces
-- Frames everywhere.
Canvas2D.IMAGES = nil :: boolean?
Canvas2D.MAX_IMAGE = 1024
local assetService: any = nil
local function imagesOn(): boolean
	if Canvas2D.IMAGES == nil then
		local ok = pcall(function()
			assetService = game:GetService("AssetService")
			local probe = assetService:CreateEditableImage({ Size = Vector2.new(1, 1) })
			probe:Destroy()
		end)
		Canvas2D.IMAGES = ok
	end
	return Canvas2D.IMAGES == true
end
Canvas2D.imagesOn = imagesOn

-- Paints `rects` (as Canvas2D.sprite takes them) into an RGBA buffer cols x rows, rows down from the
-- top, later rectangles over earlier ones with their own alpha. Pure: the test reads it back.
function Canvas2D.paint(rects: { any }, cols: number, rows: number, flip: boolean): buffer
	local buf = buffer.create(cols * rows * 4)
	for _, r in rects do
		local c = Canvas2D.hex(r[5], Color3.new(1, 0, 1))
		local R, G, B = math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)
		-- RGBA in memory order is a little-endian u32 of ABGR: one write a pixel when opaque
		local word = bit32.bor(R, bit32.lshift(G, 8), bit32.lshift(B, 16), bit32.lshift(255, 24))
		local a = r[6]
		local row0 = if flip then rows - r[2] - r[4] else r[2]
		for y = math.max(0, row0), math.min(rows, row0 + r[4]) - 1 do
			for x = math.max(0, r[1]), math.min(cols, r[1] + r[3]) - 1 do
				local i = (y * cols + x) * 4
				if a >= 1 then
					buffer.writeu32(buf, i, word)
				else
					-- source over what is already there, as a translucent Frame over another would be
					local da = buffer.readu8(buf, i + 3) / 255
					local oa = a + da * (1 - a)
					local function mixc(src: number, dst: number): number
						return if oa > 0 then math.floor((src * a + dst * da * (1 - a)) / oa + 0.5) else 0
					end
					buffer.writeu8(buf, i, mixc(R, buffer.readu8(buf, i)))
					buffer.writeu8(buf, i + 1, mixc(G, buffer.readu8(buf, i + 1)))
					buffer.writeu8(buf, i + 2, mixc(B, buffer.readu8(buf, i + 2)))
					buffer.writeu8(buf, i + 3, math.floor(oa * 255 + 0.5))
				end
			end
		end
	end
	return buf
end

-- The image for a picture, built once per rects table and facing (weak-keyed: a picture nobody
-- holds any more takes its images with it). Nil when an image cannot be had.
local images: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
local function imageFor(rects: { any }, cols: number, rows: number, flip: boolean): any
	if cols > Canvas2D.MAX_IMAGE or rows > Canvas2D.MAX_IMAGE or cols < 1 or rows < 1 then return nil end
	local entry = images[rects]
	if not entry then
		entry = {}
		images[rects] = entry
	end
	local side = if flip then "f" else "n"
	if entry[side] == nil then
		local ok, content = pcall(function()
			local img = assetService:CreateEditableImage({ Size = Vector2.new(cols, rows) })
			img:WritePixelsBuffer(Vector2.zero, Vector2.new(cols, rows), Canvas2D.paint(rects, cols, rows, flip))
			return { image = img, content = Content.fromObject(img) }
		end)
		entry[side] = if ok then content else false
	end
	return entry[side] or nil
end

-- `rects` with every colour replaced by `hex` and every alpha kept: a silhouette, for a hit flash
-- drawn over a sprite. Cached, so the same table comes back (the sprite's identity).
local tints: { [any]: { [string]: { any } } } = setmetatable({}, { __mode = "k" }) :: any
function Canvas2D.tinted(rects: { any }, hex: string): { any }
	local byHex: { [string]: { any } } = tints[rects] or {}
	tints[rects] = byHex
	local cached = byHex[hex]
	if cached then return cached end
	local out: { any } = {}
	for i, r in rects do
		local row: { any } = { r[1], r[2], r[3], r[4] }
		row[5], row[6] = hex, r[6]
		out[i] = row
	end
	byHex[hex] = out
	return out
end

function Canvas2D.sprite(self: any, key: string, rects: { any }, x0: number, y1: number, pw: number, ph: number,
	cols: number, rows: number, alpha: number?, deferrable: boolean?)
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
	-- Counted before culling, so the n-th draw of a key keeps its slot whatever is off screen.
	if offscreen(self, sx, sy, sizeX, sizeY) then
		return
	end
	local slot = key .. "#" .. n
	local sp = self.sprites[slot]
	if deferrable and (not sp or sp.rects ~= rects) and (self.built or 0) >= Canvas2D.BUILD_PER_FRAME then
		return
	end
	local image = if imagesOn() then imageFor(rects, cols, rows, flip) else nil
	if sp and (sp.image ~= nil) ~= (image ~= nil) then
		-- the picture changed between an image and Frames (too big for an image, or the image
		-- failed): start this slot again in the other form
		sp.frame:Destroy()
		self.sprites[slot] = nil
		sp = nil
	end
	if not sp then
		local f: GuiObject
		if image then
			local label = Instance.new("ImageLabel")
			label.BackgroundTransparency = 1
			label.ResampleMode = Enum.ResamplerMode.Pixelated
			label.ScaleType = Enum.ScaleType.Stretch
			f = label
		else
			f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundTransparency = 1
		end
		f.Name = "Sprite"
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Parent = self.layer
		sp = { frame = f, children = {}, seen = self.frameNo, image = if image then true else nil }
		self.sprites[slot] = sp
	end
	if image then
		if sp.content ~= image.content then
			(sp.frame :: any).ImageContent = image.content
			sp.content = image.content
			-- an image costs its painting, about a hundredth of a Frame a pixel
			if sp.rects ~= rects then self.built = (self.built or 0) + cols * rows / 100 end
			sp.rects = rects
		end
		local a = (alpha or 1) * self.alpha
		if sp.alpha ~= a then
			(sp.frame :: any).ImageTransparency = 1 - a
			sp.alpha = a
		end
	else
		if sp.rects ~= rects then
			for _, child in sp.children do
				child:Destroy()
			end
			table.clear(sp.children)
			self.built = (self.built or 0) + #rects
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
	end
	local f = sp.frame
	place(f, sp, sx, sy, math.max(1, sizeX), math.max(1, sizeY), math.deg(math.atan2(ay, ax)))
	self.z += 1
	if sp.z ~= self.z then
		f.ZIndex = self.z
		sp.z = self.z
	end
	if not sp.vis then
		f.Visible = true
		sp.vis = true
	end
	sp.seen = self.frameNo
end

-- An ellipse centred on (x, y). UICorner at half the smaller side rounds a Frame into a capsule,
-- and into an ellipse when the sides are equal, which covers every arc this renderer draws.
function Canvas2D.ellipse(self: any, x: number, y: number, rx: number, ry: number, colour: Color3, alpha: number?)
	box(self, x - rx, y - ry, rx * 2, ry * 2, colour, alpha, true)
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
