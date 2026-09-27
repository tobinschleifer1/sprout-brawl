--!nocheck
-- Drawing kit characters, in two halves.
--
-- 1. Canvas2D.sprite, run against Lune's Roblox DOM with real Frames: every cell of a sprite lands
--    on screen exactly where the rectangle it came from would have - through rotation, and through
--    the mirror a facing of -1 puts in the transform, which a Frame cannot do and the sprite fakes
--    with a flipped layout. Then the reason it exists: drawing it again creates nothing, and only a
--    change of picture, mirror or alpha touches the children.
-- 2. Fighter2D with a kit character: seven sprites (head, torso, pelvis, two arms, two legs) in
--    place of the block body, the far limbs in their darkened copies, hanging from the rig's joints
--    - the neck at the head's height, the feet on the floor - and the half-resolution cut once a
--    cell is under a screen pixel and a third.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rbx = require("@lune/roblox")
local Loader = require("./loader")

-- ---------------------------------------------------------------- 1. the sprite ----
local Real = luau.load(fs.readFile("src/client/Canvas2D.luau"), { debugName = "Canvas2D", environment = {
	Instance = Rbx.Instance, UDim2 = Rbx.UDim2, UDim = Rbx.UDim, Vector2 = Rbx.Vector2, Color3 = Rbx.Color3,
}, injectGlobals = true })()

local root = Rbx.Instance.new("Frame")
local c = Real.inFrame(root)
local rects = {
	{ 0, 0, 2, 1, "#FF0000", 1 },     -- top-left of the art
	{ 3, 4, 1, 2, "#00FF00", 1 },
	{ 1, 5, 3, 1, "#0000FF", 0.5 },
}
local COLS, ROWS, PW, PH = 4, 6, 0.25, 0.3
local X0, Y1 = -0.5, 1.2

-- Where the rectangle's centre would be on screen, drawn with rect() in the same transform.
local function expected(m: any, r: any): (number, number)
	local x = X0 + (r[1] + r[3] / 2) * PW
	local y = Y1 - (r[2] + r[4] / 2) * PH
	return m.a * x + m.c * y + m.e, m.b * x + m.d * y + m.f
end
-- Where the sprite actually put it: the container's centre, plus the child's offset in the
-- container's own (rotated) frame.
local function actual(sp: any, child: any): (number, number)
	local f = sp.frame
	local W, H = f.Size.X.Offset, f.Size.Y.Offset
	local u = (child.Position.X.Scale + child.Size.X.Scale / 2 - 0.5) * W
	local v = (child.Position.Y.Scale + child.Size.Y.Scale / 2 - 0.5) * H
	local th = math.rad(f.Rotation)
	return f.Position.X.Offset + u * math.cos(th) - v * math.sin(th), f.Position.Y.Offset + u * math.sin(th) + v * math.cos(th)
end
local function only(canvas: any): any
	local found
	for _, sp in canvas.sprites do found = sp end
	return found
end

local cases = 0
for _, facing in { 1, -1 } do
	for _, rot in { 0, 0.7, -2.1, math.pi } do
		local cv = Real.inFrame(Rbx.Instance.new("Frame"))
		Real.setTransform(cv, 20, 0, 0, -20, 300, 200)      -- the world transform: y flips
		Real.translate(cv, 2, 1)
		Real.scale(cv, facing, 1)
		Real.rotate(cv, rot)
		local m = table.clone(cv.m)
		Real.sprite(cv, "t", rects, X0, Y1, PW, PH, COLS, ROWS)
		local sp = only(cv)
		for i, r in rects do
			local ex, ey = expected(m, r)
			local ax, ay = actual(sp, sp.children[i])
			-- 1.5 px: a container's position and size are whole pixels (UDim offsets are integers,
			-- in Roblox as in Lune), exactly as every rect() is. A wrong mirror is 10+ px out.
			assert(math.abs(ex - ax) < 1.5 and math.abs(ey - ay) < 1.5,
				`facing {facing}, rotation {rot}: cell {i} drawn at {ax},{ay}, its rectangle is at {ex},{ey}`)
			cases += 1
		end
	end
end

-- Reuse: the second draw creates nothing, and a change of alpha or mirror touches only what it must.
Real.setTransform(c, 20, 0, 0, -20, 300, 200)
Real.sprite(c, "hero|head", rects, X0, Y1, PW, PH, COLS, ROWS)
local sp = only(c)
local first = sp.children[2]
local count = #sp.frame:GetChildren()
Real.finish(c)
Real.setTransform(c, 20, 0, 0, -20, 330, 190)
Real.sprite(c, "hero|head", rects, X0, Y1, PW, PH, COLS, ROWS)
assert(#sp.frame:GetChildren() == count and sp.children[2] == first, "drawing the same sprite again rebuilt its children")
assert(sp.frame.Position.X.Offset ~= 300 and sp.frame.Visible, "the container did not move")
assert(math.abs(sp.children[3].BackgroundTransparency - 0.5) < 1e-9, "a half-alpha cell lost its alpha")
Real.finish(c)
c.alpha = 0.5
Real.sprite(c, "hero|head", rects, X0, Y1, PW, PH, COLS, ROWS)
assert(math.abs(sp.children[3].BackgroundTransparency - 0.75) < 1e-9 and math.abs(sp.children[1].BackgroundTransparency - 0.5) < 1e-9,
	"the canvas alpha did not reach the children")
c.alpha = 1
Real.finish(c)
-- Two fighters wearing the same character get two containers.
Real.sprite(c, "hero|head", rects, X0, Y1, PW, PH, COLS, ROWS)
Real.sprite(c, "hero|head", rects, X0 + 3, Y1, PW, PH, COLS, ROWS)
local n = 0
for _ in c.sprites do n += 1 end
assert(n == 2, `two fighters in one character share {n} container(s)`)
-- Not drawn: hidden at the end of the frame; not drawn for ten seconds: destroyed.
Real.finish(c)
Real.finish(c)
assert(not sp.frame.Visible, "a sprite nobody drew stayed on screen")
for _ = 1, 601 do Real.finish(c) end
assert(next(c.sprites) == nil, "sprites nobody draws are never destroyed")
print(`PASS sprite: {cases} cells land where their rectangles would, through rotation and both facings; redraws create nothing; alpha reaches the children; unused sprites hide, then go`)

-- ---------------------------------------------------------------- 2. the fighter ----
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Fighter2D = Loader.loadFrom("src/client/", "Fighter2D")
local Compose = Loader.loadFrom("src/client/", "AvatarCompose")
local Channels = Loader.loadFrom("src/client/", "Channels")
local Fighter = Loader.load("Fighter")
local Snapshot = Loader.load("Snapshot")
local Loadout = Loader.load("Loadout")
local AvatarKit = Loader.load("AvatarKit")
local KIT = Loader.load("Data/AvatarKit")

-- The block body's head and chest mark come from Avatar2D; a kit fighter must not call either.
local Avatar2D = Loader.loadFrom("src/client/", "Avatar2D")
local blockHeads = 0
local drawHead, drawMark = Avatar2D.drawHead, Avatar2D.drawTorsoMark
Avatar2D.drawHead = function(...) blockHeads += 1; return drawHead(...) end
Avatar2D.drawTorsoMark = function(...) blockHeads += 1; return drawMark(...) end

local sprites, blocks = {}, 0
Canvas.rect = function() blocks += 1 end
Canvas.ellipse = function() end
Canvas.tri = function() end
Canvas.line = function() end
Canvas.sprite = function(cv: any, key: string, list: any, x0: number, y1: number, pw: number, ph: number, cols: number, rows: number)
	local m = cv.m
	local function P(x: number, y: number) return m.a * x + m.c * y + m.e, m.b * x + m.d * y + m.f end
	table.insert(sprites, { key = key, list = list, x0 = x0, y1 = y1, pw = pw, ph = ph, cols = cols, rows = rows, P = P })
end
local function canvas(scale: number): any
	return setmetatable({ m = { a = scale, b = 0, c = 0, d = scale, e = 0, f = 0 }, stack = {}, alpha = 1, alphaStack = {} }, { __index = Canvas })
end

local code
for _, p in KIT.presets do if p.id == "knight" then code = p.code end end
local char = Loadout.build(code, "Sword")
assert(char.avatar.kit, "Loadout.build did not resolve the kit code")
local f: any = Fighter.new({ index = 1, char = char, x = 3, y = 2, stocks = 3 })
f.state, f.onGround = "idle", true
local s = Snapshot.decode(Snapshot.encode(f))
local art = Compose.sprites(code)

-- Big on screen: full resolution.
table.clear(sprites); blocks = 0; blockHeads = 0
Fighter2D.draw(canvas(24), s, char, 0, 2)
assert(blockHeads == 0, "the kit fighter drew the block head or chest mark as well")
local by: any = {}
for _, sp in sprites do
	local piece = string.match(sp.key, "|(%a+)|")
	by[piece] = by[piece] or {}
	table.insert(by[piece], sp)
end
assert(#sprites == 7, `a kit fighter should be seven sprites, drew {#sprites}`)
assert(#by.head == 1 and #by.torso == 1 and #by.pelvis == 1 and #by.arm == 2 and #by.leg == 2, "not one head, torso and pelvis and two arms and legs")
local kitBlocks = blocks
for _, id in { "arm", "leg" } do
	local far, near = 0, 0
	for _, sp in by[id] do
		if sp.list == art[id].farFull then far += 1 elseif sp.list == art[id].full then near += 1 end
	end
	assert(far == 1 and near == 1, `{id}: expected one far (darkened) and one near copy, got {far} and {near}`)
end
-- Square cells a twelfth of the head wide, on every piece - the pixels are one size across the body.
local PWANT = char.radius * 1.15 / 12
for _, sp in sprites do
	assert(math.abs(sp.pw - PWANT) < 1e-12, `{sp.key}: cells {sp.pw} wide, a twelfth of the head is {PWANT}`)
end
assert(math.abs(by.head[1].ph - PWANT) < 1e-12, "the head's cells are not square")
-- The neck joint: the head sprite's pivot, in world space.
local head = by.head[1]
local hx, hy = head.P(head.x0 + KIT.parts.head.ox * head.pw, head.y1 - KIT.parts.head.oy * head.ph)
assert(math.abs(hx / 24 - s.x) < 0.3 and math.abs(hy / 24 - (s.y + char.height * 0.78)) < 0.35,
	`the head hangs from ({hx / 24}, {hy / 24}), the neck is at ({s.x}, {s.y + char.height * 0.78})`)
-- The feet: the bottom of each leg's span is where the block rig's leg ends - the floor, lifted by
-- the idle breathing (`bob`) and the stance's leg angles, as the block legs are.
local ch = Channels.For(s, char, nil, 0)
for _, leg in by.leg do
	local _, fy = leg.P(0, leg.y1 - KIT.parts.leg.span * leg.ph)
	local rot = if leg.list == art.leg.farFull then ch.legL else ch.legR
	local want = s.y + ch.bob + char.height * 0.34 * (1 - math.cos(rot))
	assert(math.abs(fy / 24 - want) < 1e-6, `a foot ends at y {fy / 24}, the block leg ends at {want}`)
end
-- The torso fills hip to shoulder.
local torso = by.torso[1]
assert(math.abs(torso.y1 - KIT.parts.torso.span * torso.ph) < 1e-9 and math.abs(torso.y1 - char.height * 0.36) < 1e-9, "the torso does not span hip to shoulder")

-- Small on screen: half resolution, same places.
table.clear(sprites)
Fighter2D.draw(canvas(8), s, char, 0, 2)
local halfCount = 0
for _, sp in sprites do
	if string.find(sp.key, "h$") then halfCount += 1 end
	local piece = string.match(sp.key, "|(%a+)|")
	local list = sp.list
	local ok = list == art[piece].half or list == art[piece].farHalf
	assert(ok, `{sp.key}: not the half-resolution picture at 8 px per stud`)
end
assert(halfCount == 7, `{halfCount} of 7 pieces switched to half resolution`)
local pwCell = char.radius * 1.15 / 12
assert(pwCell * 8 < Fighter2D.KIT_LOD_PX and pwCell * 24 >= Fighter2D.KIT_LOD_PX, "the test's two zooms do not straddle the threshold")

-- A preset character with the same weapon draws the block body and no sprites; the kit character
-- drew none of that body (the rectangles it did draw are the sword's).
table.clear(sprites); blocks = 0; blockHeads = 0
Fighter2D.draw(canvas(24), s, Loadout.build("Classic", "Sword"), 0, 2)
assert(#sprites == 0, "a preset character drew sprites")
assert(blockHeads == 2, "a preset character stopped drawing its head and chest mark")
assert(blocks - kitBlocks >= 7, `the kit fighter drew the block body as well ({kitBlocks} rectangles against the preset's {blocks})`)
print(`PASS kit fighter: seven sprites on the rig's joints (neck at the head, feet where the block legs end), far limbs darkened, half resolution below {Fighter2D.KIT_LOD_PX} px a cell; presets unchanged`)
