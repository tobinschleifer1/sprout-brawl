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
-- Effects (deferrable) build at most BUILD_PER_FRAME children a frame; the rest wait a frame and are
-- then built. Body parts and weapons are never deferred.
do
	local big = {}
	for i = 1, 100 do big[i] = { i % COLS, 0, 1, 1, "#FFFFFF", 1 } end
	local cap = Real.BUILD_PER_FRAME
	local want = math.ceil(cap / 100) + 2
	local function built(): number
		local k = 0
		for _ in c.sprites do k += 1 end
		return k
	end
	Real.finish(c)
	for _ = 1, 602 do Real.finish(c) end
	for i = 1, want do Real.sprite(c, "fx|" .. i, big, X0, Y1, PW, PH, COLS, ROWS, 1, true) end
	local first = built()
	assert(first == math.ceil(cap / 100), `one frame built {first} effects of 100 cells, cap {cap}`)
	Real.sprite(c, "hero|body", big, X0, Y1, PW, PH, COLS, ROWS)
	assert(built() == first + 1, "a body part was deferred behind the effects")
	Real.finish(c)
	for i = 1, want do Real.sprite(c, "fx|" .. i, big, X0, Y1, PW, PH, COLS, ROWS, 1, true) end
	assert(built() == want + 1, `the deferred effects were not built the next frame ({built()})`)
	Real.finish(c)
	for _ = 1, 602 do Real.finish(c) end
end
print(`PASS sprite: {cases} cells land where their rectangles would, through rotation and both facings; redraws create nothing; alpha reaches the children; unused sprites hide, then go; effects build {Real.BUILD_PER_FRAME} cells a frame at most`)

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
local Avatars = Loader.load("Data/Avatars")

-- The block body's head and chest mark come from Avatar2D; a kit fighter must not call either.
local Avatar2D = Loader.loadFrom("src/client/", "Avatar2D")
local blockHeads = 0
local drawHead, drawMark = Avatar2D.drawHead, Avatar2D.drawTorsoMark
Avatar2D.drawHead = function(...) blockHeads += 1; return drawHead(...) end
Avatar2D.drawTorsoMark = function(...) blockHeads += 1; return drawMark(...) end

local sprites, blocks, weapons = {}, 0, 0
Canvas.rect = function() blocks += 1 end
Canvas.ellipse = function() end
Canvas.tri = function() end
Canvas.line = function() end
Canvas.sprite = function(cv: any, key: string, list: any, x0: number, y1: number, pw: number, ph: number, cols: number, rows: number)
	local m = cv.m
	local function P(x: number, y: number) return m.a * x + m.c * y + m.e, m.b * x + m.d * y + m.f end
	-- The weapon is a sprite too (one Frame for the whole weapon); counted apart from the body.
	if string.sub(key, 1, 7) == "weapon|" then weapons += 1; return end
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
table.clear(sprites); blocks = 0; blockHeads = 0; weapons = 0
Fighter2D.draw(canvas(24), s, char, 0, 2)
assert(weapons == 1, `the kit fighter's sword should be one sprite, drew {weapons}`)
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

-- The presets are kit characters under their old ids (docs/briefs/character-rework-plan.md, phase
-- 1): every one draws seven sprites and no block body, and "Classic" draws exactly the pictures its
-- own kit code draws.
local function keysOf(avatarId: string): { string }
	table.clear(sprites); blocks = 0; blockHeads = 0; weapons = 0
	Fighter2D.draw(canvas(24), s, Loadout.build(avatarId, "Sword"), 0, 2)
	local keys = {}
	for _, sp in sprites do table.insert(keys, sp.key) end
	return keys
end
for _, preset in Avatars.LIST do
	local keys = keysOf(preset.id)
	assert(#keys == 7 and blockHeads == 0, `preset {preset.id} drew {#keys} sprites and {blockHeads} block head pieces, want a kit body`)
end
local classic, byCode = keysOf("Classic"), keysOf(Loadout.kitCodeOf("Classic") :: string)
assert(table.concat(classic, ",") == table.concat(byCode, ","), "Classic does not draw what its kit code draws")
-- A body with no kit still takes the block rig: the web keeps it for characters from the original
-- creator, and the two renderers stay one rig. No Roblox avatar resolves to it any more.
local bare = Loadout.build("Classic", "Sword")
bare.avatar = table.clone(bare.avatar)
bare.avatar.kit = nil
table.clear(sprites); blocks = 0; blockHeads = 0; weapons = 0
Fighter2D.draw(canvas(24), s, bare, 0, 2)
assert(#sprites == 0, "a body with no kit drew body sprites")
assert(weapons == 1, "a body with no kit's sword is one sprite as well")
assert(blockHeads == 2, "a body with no kit stopped drawing its head and chest mark")
assert(blocks - kitBlocks >= 7, `the kit fighter drew the block body as well ({kitBlocks} rectangles against the block body's {blocks})`)
-- The hit flash on a kit fighter is the fighter: every piece drawn again over itself in the flash
-- colour, the same shape (a silhouette, not a box), and the same silhouette table every frame -
-- a sprite's identity is its rects table, so a fresh one each frame would rebuild the image.
local flashes, flashBlocks = {}, 0
Canvas.rect = function() flashBlocks += 1 end
Canvas.sprite = function(_: any, key: string, list: any, _x0: number, _y1: number, _pw: number, _ph: number, _c: number, _r: number, alpha: number?)
	if string.sub(key, 1, 7) == "weapon|" then return end
	table.insert(flashes, { key = key, list = list, alpha = alpha })
end
local chilled = table.clone(s)
chilled.chillStacks = 2
local want = "#A9D8F0"
local function flashDraw(): { any }
	table.clear(flashes)
	Fighter2D.draw(canvas(24), chilled, char, 0, 2)
	local tinted = {}
	for _, sp in flashes do if string.find(sp.key, "|" .. want, 1, true) then table.insert(tinted, sp) end end
	return tinted
end
local tinted = flashDraw()
assert(#tinted == 7, `a flashing kit fighter drew {#tinted} flash pieces, want one per piece (7)`)
for _, sp in tinted do
	local base
	for _, other in flashes do if other.key .. "|" .. want == sp.key then base = other end end
	assert(base, `{sp.key}: a flash with no piece under it`)
	assert(#sp.list == #base.list, `{sp.key}: the flash is not the piece's shape`)
	for i, r in sp.list do
		local b = base.list[i]
		assert(r[1] == b[1] and r[2] == b[2] and r[3] == b[3] and r[4] == b[4] and r[6] == b[6], `{sp.key}: flash rectangle {i} differs from the piece`)
		assert(r[5] == want, `{sp.key}: flash drawn {r[5]}, want {want}`)
	end
	assert(sp.alpha and sp.alpha > 0 and sp.alpha < 1, `{sp.key}: the flash hides the piece under it (alpha {sp.alpha})`)
end
local again = flashDraw()
for i, sp in again do assert(sp.list == tinted[i].list, "the flash silhouette was rebuilt on the next frame") end
-- a fighter not flashing draws no flash
chilled.chillStacks = 0
assert(#flashDraw() == 0, "a fighter with no flash drew flash pieces")

print(`PASS kit fighter: seven sprites on the rig's joints (neck at the head, feet where the block legs end), far limbs darkened, half resolution below {Fighter2D.KIT_LOD_PX} px a cell; every preset a kit body, a body with no kit the block rig; hit flash a silhouette of each piece`)
