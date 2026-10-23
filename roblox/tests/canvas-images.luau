--!strict
-- Canvas2D's image sprites: a sprite painted once into an EditableImage and shown as ONE
-- ImageLabel, instead of a container of Frames - and the fall back to Frames when an image cannot
-- be had. EditableImage does not exist outside Roblox, so AssetService, Content and Instance are
-- stand-ins here that record what Canvas2D asks of them; the pixels are Canvas2D's own.
--
-- What it holds:
--   * the painted pixels are the rectangles: colour, alpha, later over earlier, a translucent
--     cell blended over what is under it, a mirrored drawing's rows reversed;
--   * a sprite is one ImageLabel with no children; drawing it again builds nothing; a fade writes
--     one property; turning to face the other way swaps to the mirrored image;
--   * one picture is one image however many sprites show it;
--   * a picture too big for an image, or an engine that refuses one, falls back to Frames.
--
--     lune run tests/canvas-images
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rbx = require("@lune/roblox")

local function fail(msg: string): never
	error(msg, 0)
end

-- ------------------------------------------------------------------ the stand-ins ----
local created = 0
local refuse = false
local writes: { [string]: number } = {}
local function instance(class: string): any
	created += 1
	-- properties live in `props`, so every assignment - not just the first - reaches __newindex
	local props: any = { ClassName = class, children = {}, Visible = true }
	local obj: any = {}
	props.Destroy = function(self: any)
		props.destroyed = true
		local parent = props.Parent
		if parent then
			local i = table.find(parent.children, self)
			if i then table.remove(parent.children, i) end
		end
	end
	return setmetatable(obj, {
		__index = props,
		__newindex = function(t: any, k: string, v: any)
			writes[k] = (writes[k] or 0) + 1
			if k == "Parent" and v then table.insert(v.children, t) end
			props[k] = v
		end,
	})
end
local images = 0
-- `denied`: what Roblox does without the EditableImage permission - the image is created (with a
-- warning) and its first write is refused.
local denied = false
local AssetService = {
	CreateEditableImage = function(_, opts: any): any
		if refuse then error("out of image memory") end
		images += 1
		return { size = opts.Size, Destroy = function() end,
			WritePixelsBuffer = function(self: any, _origin: any, size: any, buf: buffer)
				if denied then error("EditableImage is not accessible") end
				self.pixels, self.written = buf, size
			end }
	end,
}
local Content = { fromObject = function(img: any): any return { image = img } end }
local codes = setmetatable({}, { __index = function(_, k) return k end })
local Canvas2D = luau.load(fs.readFile("src/client/Canvas2D.luau"), { environment = {
	game = { GetService = function(_, name: string): any
		if name == "AssetService" then return AssetService end
		error("no service " .. name)
	end },
	Instance = { new = instance },
	Content = Content,
	Enum = setmetatable({}, { __index = function() return codes end }),
	Color3 = Rbx.Color3, Vector2 = Rbx.Vector2, UDim2 = Rbx.UDim2, UDim = Rbx.UDim,
}, injectGlobals = true })()

local function canvas(): any
	local layer = instance("Frame")
	return Canvas2D.inFrame(layer)
end
local function pixel(buf: buffer, cols: number, x: number, y: number): (number, number, number, number)
	local i = (y * cols + x) * 4
	return buffer.readu8(buf, i), buffer.readu8(buf, i + 1), buffer.readu8(buf, i + 2), buffer.readu8(buf, i + 3)
end

-- ------------------------------------------------------------------ painting ----
-- a 4 x 3 picture: red over the whole of the top row, a blue 2 x 2 bottom-left, and a white cell
-- at half alpha over the blue's corner
local PIC = { { 0, 0, 4, 1, "#FF0000", 1 }, { 0, 1, 2, 2, "#0000FF", 1 }, { 1, 1, 1, 1, "#FFFFFF", 0.5 } }
local buf = Canvas2D.paint(PIC, 4, 3, false)
local function expect(x: number, y: number, r: number, g: number, b: number, a: number, why: string)
	local R, G, B, A = pixel(buf, 4, x, y)
	if math.abs(R - r) > 1 or math.abs(G - g) > 1 or math.abs(B - b) > 1 or math.abs(A - a) > 1 then
		fail(`{why}: pixel ({x},{y}) is {R},{G},{B},{A}, want {r},{g},{b},{a}`)
	end
end
expect(3, 0, 255, 0, 0, 255, "the top row is red")
expect(0, 2, 0, 0, 255, 255, "the bottom-left is blue")
expect(1, 1, 128, 128, 255, 255, "the half-white cell is blended over the blue")
expect(3, 2, 0, 0, 0, 0, "an empty cell is transparent")
-- alone over nothing, a translucent cell keeps its own colour at its own alpha
local lone = Canvas2D.paint({ { 0, 0, 1, 1, "#FFFFFF", 0.5 } }, 1, 1, false)
local _, _, _, la = pixel(lone, 1, 0, 0)
if math.abs(la - 128) > 1 then fail(`a lone half-alpha cell has alpha {la}`) end
-- mirrored: the rows run the other way
buf = Canvas2D.paint(PIC, 4, 3, true)
expect(3, 2, 255, 0, 0, 255, "mirrored, the red row is at the bottom")
expect(0, 0, 0, 0, 255, 255, "mirrored, the blue is at the top")

-- ------------------------------------------------------------------ sprites ----
local c = canvas()
if not Canvas2D.imagesOn() then fail("images were not detected as available") end   -- the one-off probe
created, images = 0, 0
Canvas2D.sprite(c, "pic", PIC, 0, 3, 1, 1, 4, 3)
local sp = c.sprites["pic#1"] or fail("no sprite slot")
if sp.frame.ClassName ~= "ImageLabel" then fail(`a sprite is a {sp.frame.ClassName}, not an ImageLabel`) end
if #sp.frame.children ~= 0 then fail("an image sprite has children") end
if images ~= 1 or created ~= 1 then fail(`the first draw made {images} images and {created} Instances, want 1 and 1`) end
local content = sp.frame.ImageContent
if not content or content.image.written.X ~= 4 or content.image.written.Y ~= 3 then fail("the image was not painted at the picture's size") end
-- again: nothing new, nothing rewritten but where it is
Canvas2D.finish(c)
table.clear(writes)
Canvas2D.sprite(c, "pic", PIC, 0, 3, 1, 1, 4, 3)
if images ~= 1 or created ~= 1 then fail("drawing the same sprite again built something") end
if writes.ImageContent or writes.ImageTransparency then fail("drawing the same sprite again rewrote its image") end
-- a fade: one property
Canvas2D.finish(c)
table.clear(writes)
Canvas2D.sprite(c, "pic", PIC, 0, 3, 1, 1, 4, 3, 0.5)
if writes.ImageTransparency ~= 1 or math.abs(sp.frame.ImageTransparency - 0.5) > 1e-9 then fail("a fade did not write one transparency") end
-- the other way round: the mirrored image (a second image, built once)
Canvas2D.finish(c)
Canvas2D.scale(c, -1, 1)
Canvas2D.sprite(c, "pic", PIC, 0, 3, 1, 1, 4, 3, 0.5)
if images ~= 2 then fail(`facing the other way built {images - 1} new images, want 1`) end
if sp.frame.ImageContent == content then fail("facing the other way kept the unmirrored image") end
Canvas2D.scale(c, -1, 1)
Canvas2D.finish(c)
-- a second sprite of the same picture shares its image
Canvas2D.sprite(c, "pic", PIC, 0, 3, 1, 1, 4, 3)
Canvas2D.sprite(c, "pic", PIC, 5, 3, 1, 1, 4, 3)
if images ~= 2 then fail("a second sprite of the same picture built its own image") end
if c.sprites["pic#2"].frame.ImageContent ~= c.sprites["pic#1"].frame.ImageContent then fail("two sprites of one picture show different images") end
Canvas2D.finish(c)

-- too big for an image: Frames, as before
local big = { { 0, 0, 1200, 2, "#00FF00", 1 } }
Canvas2D.sprite(c, "big", big, 0, 2, 1, 1, 1200, 2)
local bs = c.sprites["big#1"] or fail("no big sprite")
if bs.frame.ClassName ~= "Frame" or #bs.frame.children ~= 1 then fail("a picture too big for an image is not drawn as Frames") end
Canvas2D.finish(c)

-- an engine that refuses an image: Frames for that picture
refuse = true
local other = { { 0, 0, 2, 2, "#123456", 1 } }
Canvas2D.sprite(c, "refused", other, 0, 2, 1, 1, 2, 2)
local rs = c.sprites["refused#1"] or fail("no refused sprite")
if rs.frame.ClassName ~= "Frame" or #rs.frame.children ~= 1 then fail("a refused image did not fall back to Frames") end
refuse = false
Canvas2D.finish(c)
-- and that one refusal ends images for the session: every later picture asked again and logged
-- Roblox's warning, a console flood all game long without the permission
do
	local before = images
	local third = { { 0, 0, 1, 1, "#654321", 1 } }
	Canvas2D.sprite(c, "after", third, 0, 1, 1, 1, 1, 1)
	if images ~= before or Canvas2D.IMAGES ~= false then fail(`a picture after a refused image asked for another image ({images - before})`) end
	Canvas2D.IMAGES = true
	Canvas2D.finish(c)
end

-- and the switch off: Frames everywhere
Canvas2D.IMAGES = false
local c2 = canvas()
Canvas2D.sprite(c2, "pic", PIC, 0, 3, 1, 1, 4, 3)
if c2.sprites["pic#1"].frame.ClassName ~= "Frame" or #c2.sprites["pic#1"].frame.children ~= #PIC then fail("IMAGES = false still drew an image") end

-- Without the permission (images are created but every write is refused), the probe finds out once:
-- images are off, every picture is Frames, and no further image is ever attempted.
denied = true
Canvas2D.IMAGES = nil
if Canvas2D.imagesOn() then fail("images taken as available when every write is refused") end
local before = images
local c3 = canvas()
Canvas2D.sprite(c3, "pic", PIC, 0, 3, 1, 1, 4, 3)
Canvas2D.sprite(c3, "other", { { 0, 0, 1, 1, "#FFFFFF", 1 } }, 0, 1, 1, 1, 1, 1)
if images ~= before then fail(`{images - before} images attempted after the probe found them refused`) end
if c3.sprites["pic#1"].frame.ClassName ~= "Frame" then fail("a refused-permission picture did not fall back to Frames") end
denied = false

print("PASS canvas images: images refused without the permission are found by one probe, and never attempted again; pixels are the rectangles (blended, mirrored), one ImageLabel a sprite, nothing rebuilt on redraw, a fade is one write, one image a picture, Frames when an image cannot be had")
