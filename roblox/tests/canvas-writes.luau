--!nocheck
-- Canvas2D writes only what changed, and nothing it cannot see.
--
-- Every property write to a Frame crosses into the engine; a draw re-places every Frame every frame,
-- so the canvas remembers what it last wrote and skips the rest (measured in Studio: 24 people in
-- the lobby went from 9.0ms to 6.1ms of script a frame, and the end-of-frame hide pass from 1.8ms
-- to 0.9ms). This counts the writes on stub Instances: a repeated frame writes nothing, a change
-- writes only itself, and after all the skipping every Frame still holds exactly what an uncached
-- canvas would have written - a skipped write that was needed is a picture left behind.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rbx = require("@lune/roblox")

local writes: { [string]: number } = {}
local total = 0
local VIEW = Rbx.Vector2.new(800, 600)
local function instance(class: string): any
	local props: any = { ClassName = class, Visible = true, AbsoluteSize = VIEW }
	local children = {}
	local self: any
	props.Destroy = function() props.destroyed = true end
	self = setmetatable({}, { __index = props, __newindex = function(_, key, value)
		props[key] = value
		writes[key] = (writes[key] or 0) + 1
		total += 1
		if key == "Parent" and value then table.insert(children, self) end
	end })
	return self
end
local Canvas = luau.load(fs.readFile("src/client/Canvas2D.luau"), { debugName = "Canvas2D", environment = {
	Instance = { new = instance }, UDim2 = Rbx.UDim2, UDim = Rbx.UDim, Vector2 = Rbx.Vector2, Color3 = Rbx.Color3,
	Enum = { ZIndexBehavior = { Sibling = "Sibling" } },
}, injectGlobals = true })()

local RED, BLUE = Rbx.Color3.new(1, 0, 0), Rbx.Color3.new(0, 0, 1)
local ART = { { 0, 0, 2, 2, "#FF0000", 1 }, { 2, 0, 2, 2, "#00FF00", 0.5 } }
local c = Canvas.new(instance("PlayerGui"))
local function frame(camX: number, colour: Color3, extra: boolean)
	c:world(camX, 0, 20, 0, 0)
	c:rect(-1, -1, 2, 2, colour)
	c:circle(3, 0, 1, BLUE, 0.5)
	c:rect(5, 0, 1, 3, RED)
	c:sprite("art", ART, -8, 2, 0.5, 0.5, 4, 2)
	if extra then c:rect(-6, 1, 1, 1, RED) end
	c:finish()
end
local function reset() table.clear(writes); total = 0 end
local function snapshot(): { any }
	local out = {}
	for i, f in c.pool do
		out[i] = { f.Visible, f.Position, f.Size, f.Rotation, f.BackgroundColor3, f.BackgroundTransparency, f.ZIndex,
			c.poolState[i].corner.CornerRadius }
	end
	return out
end
local function same(a: { any }, b: { any }): boolean
	if #a ~= #b then return false end
	for i = 1, #a do for k = 1, 8 do if a[i][k] ~= b[i][k] then return false end end end
	return true
end

-- 1. The same frame twice: the second writes nothing at all.
frame(0, RED, true)
local first = snapshot()
reset()
frame(0, RED, true)
local names = {} for k, n in writes do table.insert(names, `{k}={n}`) end
assert(total == 0, `a repeated frame wrote {total} properties: {table.concat(names, ", ")}`)

-- 2. One colour changed: one write, and only that one.
reset()
frame(0, BLUE, true)
assert(total == 1 and writes.BackgroundColor3 == 1, `changing one colour wrote {total} properties`)

-- 3. The camera moves: positions change, nothing else does.
reset()
frame(1, BLUE, true)
assert(writes.Position and writes.Position >= 4 and total == writes.Position, `a camera move wrote more than positions ({total} writes)`)

-- 4. A frame with one primitive fewer hides the spare Frame once, and not again.
reset()
frame(1, BLUE, false)
assert(writes.Visible == 1, `dropping a primitive hid {writes.Visible or 0} Frames`)
reset()
frame(1, BLUE, false)
assert(total == 0, `a Frame already hidden was written again ({total} writes)`)

-- 5. After all that skipping, the canvas holds exactly what it held when first drawn this way.
frame(0, RED, true)
assert(same(snapshot(), first), "a skipped write left the picture different from a fresh draw")

-- 5b. Two hundred random frames - everything moving, turning, resizing, fading, recolouring,
--     reordering, rects and ellipses trading slots, sprites fading - and after each one, every
--     visible Frame holds exactly what a brand-new canvas drawing the same frame holds. A write the
--     cache skipped that was needed cannot hide from this.
do
	local seed = 7
	local function rnd(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local COLOURS = { RED, BLUE, Rbx.Color3.new(0, 1, 0) }
	local function draw(cv: any, spec: any)
		cv:world(spec.camX, spec.camY, 20, 0, 0)
		for _, p in spec.prims do
			if p.kind == "sprite" then
				cv:sprite("art", ART, p.x, p.y, 0.5, 0.5, 4, 2, p.a)
			else
				cv:save()
				cv:translate(p.x, p.y)
				cv:rotate(p.rot)
				if p.kind == "rect" then cv:rect(0, 0, p.w, p.h, p.colour, p.a) else cv:ellipse(0, 0, p.w, p.h, p.colour, p.a) end
				cv:restore()
			end
		end
		cv:finish()
	end
	local function visible(cv: any): { string }
		local out = {}
		for i, f in cv.pool do
			if cv.poolState[i].vis then
				table.insert(out, `{f.ZIndex}|{f.Position}|{f.Size}|{f.Rotation}|{f.BackgroundColor3}|{f.BackgroundTransparency}|{cv.poolState[i].corner.CornerRadius}`)
			end
		end
		for key, sp in cv.sprites do
			if sp.vis then
				local kids = {}
				for _, child in sp.children do table.insert(kids, tostring(child.BackgroundTransparency)) end
				table.insert(out, `{key}|{sp.frame.ZIndex}|{sp.frame.Position}|{sp.frame.Size}|{sp.frame.Rotation}|{table.concat(kids, ",")}`)
			end
		end
		table.sort(out)
		return out
	end
	local live = Canvas.new(instance("PlayerGui"))
	local prev: any = nil
	-- Half the frames change ONE thing about the last frame - only the camera's height, only sizes,
	-- only turns, only fades, only colours - since a real frame often does, and a cache that checks
	-- the wrong half of a pair (x but not y, width but not height) only shows when the other half
	-- changes alone.
	local ONE = { "camY", "h", "w", "rot", "a", "colour", "y" }
	for n = 1, 200 do
		local spec = { camX = (rnd() - 0.5) * 30, camY = (rnd() - 0.5) * 20, prims = {} }
		if prev and rnd() < 0.5 then
			local what = ONE[1 + math.floor(rnd() * #ONE)]
			spec.camX, spec.camY = prev.camX, prev.camY + (if what == "camY" then 1.5 else 0)
			for _, p in prev.prims do
				local q = table.clone(p)
				if what == "h" then q.h += 0.5 elseif what == "w" then q.w += 0.5 elseif what == "rot" then q.rot += 0.3
				elseif what == "a" then q.a = if q.a == 1 then 0.5 else 1 elseif what == "colour" then q.colour = if q.colour == RED then BLUE else RED
				elseif what == "y" then q.y += 1 end
				table.insert(spec.prims, q)
			end
		end
		for _ = 1, if #spec.prims > 0 then 0 else 3 + math.floor(rnd() * 6) do
			local r = rnd()
			table.insert(spec.prims, {
				kind = if r < 0.5 then "rect" elseif r < 0.8 then "ellipse" else "sprite",
				x = (rnd() - 0.5) * 60, y = (rnd() - 0.5) * 40, w = 0.5 + rnd() * 4, h = 0.5 + rnd() * 4,
				rot = (rnd() - 0.5) * 6, a = if rnd() < 0.5 then 1 else math.floor(rnd() * 4) / 4,
				colour = COLOURS[1 + math.floor(rnd() * #COLOURS)],
			})
		end
		prev = spec
		draw(live, spec)
		local fresh = Canvas.new(instance("PlayerGui"))
		draw(fresh, spec)
		-- The fresh canvas is the reference, so it must have written everything it shows.
		for i, f in fresh.pool do
			if fresh.poolState[i].vis then
				assert(f.Position and f.Size and f.Rotation and f.ZIndex and f.BackgroundColor3 and f.BackgroundTransparency,
					`frame {n}: a Frame shown with a property never written`)
			end
		end
		local a, b = visible(live), visible(fresh)
		assert(#a == #b, `frame {n}: {#a} Frames shown, a fresh canvas shows {#b}`)
		for i = 1, #a do assert(a[i] == b[i], `frame {n}: {a[i]}\n  a fresh canvas has {b[i]}`) end
	end
end

-- 6. An ellipse and a rectangle swapping slots get their corners right both ways.
c:world(0, 0, 20, 0, 0)
c:circle(0, 0, 1, RED)
c:finish()
assert(c.poolState[1].corner.CornerRadius == Rbx.UDim.new(0.5, 0), "an ellipse is round")
c:world(0, 0, 20, 0, 0)
c:rect(0, 0, 1, 1, RED)
c:finish()
assert(c.poolState[1].corner.CornerRadius == Rbx.UDim.new(0, 0), "the rectangle drawn in its slot next is square again")

-- 7. Off screen is not drawn; partly on screen is.
local ok = Canvas.new(instance("PlayerGui"))
ok:world(0, 0, 20, 0, 0)                 -- 800 px wide: x from -20 to 20 studs on screen
ok:rect(30, 0, 2, 2, RED)                -- wholly off the right edge
ok:rect(-24, 0, 2, 2, RED)               -- wholly off the left
ok:rect(19.5, 0, 2, 2, RED)              -- straddles the right edge
ok:rect(-21.5, 0, 2, 2, RED)             -- straddles the left edge
ok:sprite("far", ART, 40, 2, 0.5, 0.5, 4, 2)
assert(ok.used == 2, `{ok.used} Frames used; only the two rectangles straddling an edge should be`)
local drawn = 0
for _ in ok.sprites do drawn += 1 end
assert(drawn == 0, "a sprite off screen is not made")
ok:finish()
-- A sprite that walks off screen is hidden, and comes back when it returns.
ok:world(0, 0, 20, 0, 0)
ok:sprite("walker", ART, 0, 2, 0.5, 0.5, 4, 2)
ok:finish()
local walker = ok.sprites["walker#1"]
assert(walker and walker.frame.Visible, "on screen: shown")
ok:world(-100, 0, 20, 0, 0)
ok:sprite("walker", ART, 0, 2, 0.5, 0.5, 4, 2)
ok:finish()
assert(not walker.frame.Visible, "off screen: hidden")
ok:world(0, 0, 20, 0, 0)
ok:sprite("walker", ART, 0, 2, 0.5, 0.5, 4, 2)
ok:finish()
assert(walker.frame.Visible, "back on screen: shown again")
-- A canvas with no world transform (a portrait tile) knows no viewport and culls nothing.
local tile = Canvas.inFrame(instance("Frame"))
tile:rect(5000, 5000, 1, 1, RED)
assert(tile.used == 1, "a tile canvas culls nothing")
-- A frame drawn into twice - a Locker card reused for another item as you scroll - shows only the
-- second picture: what the first drew and the second did not is hidden (a new canvas each time left
-- the first picture under the second: a posing fighter over every weapon).
do
	local card = instance("Frame")
	local first = Canvas.inFrame(card)
	Canvas.setTransform(first, 2, 0, 0, -2, 10, 40)          -- (as a weapon's art is fitted)
	first:rect(0, 0, 4, 4, RED); first:rect(4, 0, 4, 4, RED); first:rect(8, 0, 4, 4, RED)
	first:finish(true)
	local second = Canvas.inFrame(card)
	second:rect(0, 8, 2, 2, BLUE)
	second:finish(true)
	local shown = 0
	for _, f in first.pool do if f.Visible then shown += 1 end end
	if second ~= first then for _, f in second.pool do if f.Visible then shown += 1 end end end
	assert(shown == 1, `a card drawn twice shows {shown} shapes: the first picture is left under the second`)
	assert(second.m.a == 1 and second.m.e == 0 and #second.stack == 0, "a card's canvas keeps the last draw's transform")
end
print("PASS canvas writes: a repeated frame writes nothing, a change writes only itself, spares hidden once, off-screen skipped, the picture unchanged")
