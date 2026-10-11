--!nocheck
-- Drawing kit characters, in two halves.
--
-- 1. Canvas2D.sprite, run against Lune's Roblox DOM with real Frames: every cell of a sprite lands
--    on screen exactly where the rectangle it came from would have - through rotation, and through
--    the mirror a facing of -1 puts in the transform, which a Frame cannot do and the sprite fakes
--    with a flipped layout. Then the reason it exists: drawing it again creates nothing, and only a
--    change of picture, mirror or alpha touches the children.
-- 2. Fighter2D with a kit character: at full detail eleven sprites (head, torso, pelvis, and an
--    upper and lower segment of each arm and leg) in place of the block body, the far limbs in their
--    darkened copies - the neck at the head's height, every elbow and knee joined, the hand exactly on
--    the weapon's grip, the feet planted on the floor through the breathing. Below a screen pixel and
--    a third a cell, the seven one-piece pieces at half resolution.
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
local Weapons2D = Loader.loadFrom("src/client/", "Weapons2D")
local WeaponPose = Loader.loadFrom("src/client/", "WeaponPose")
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

-- Big on screen: full resolution - the jointed rig. `T` is a moment of the idle where the breathing
-- has the body well off its rest height, so a foot that rode the bob would be caught.
local T = 0.7
local ch = Channels.For(s, char, nil, T)
assert(math.abs(ch.bob) > 0.05, `the test's moment has too little bob ({ch.bob}) to tell a planted foot from one riding it`)
-- The weapon's frame as Weapons2D.draw is entered: Fighter2D has just translated to the grip.
local grip: any = nil
local weaponDraw = Weapons2D.draw
Weapons2D.draw = function(cv: any, ...)
	grip = { cv.m.e, cv.m.f }
	return weaponDraw(cv, ...)
end
table.clear(sprites); blocks = 0; blockHeads = 0; weapons = 0
Fighter2D.draw(canvas(24), s, char, T, 2)
Weapons2D.draw = weaponDraw
assert(weapons == 1, `the kit fighter's sword should be one sprite, drew {weapons}`)
assert(blockHeads == 0, "the kit fighter drew the block head or chest mark as well")
local by: any = {}
for _, sp in sprites do
	local piece = string.match(sp.key, "|(%a+)|")
	by[piece] = by[piece] or {}
	table.insert(by[piece], sp)
end
assert(#sprites == 11, `a kit fighter at full detail should be eleven sprites, drew {#sprites}`)
assert(#by.head == 1 and #by.torso == 1 and #by.pelvis == 1, "not one head, torso and pelvis")
local kitBlocks = blocks
-- Each segment once near and once far (darkened), in its own picture cut from the limb.
local seg: any = {}
for _, id in { "upperarm", "forearm", "thigh", "shin" } do
	assert(by[id] and #by[id] == 2, `{id}: expected two, drew {if by[id] then #by[id] else 0}`)
	seg[id] = {}
	for _, sp in by[id] do
		if sp.list == art[id].farFull then seg[id].far = sp elseif sp.list == art[id].full then seg[id].near = sp end
	end
	assert(seg[id].far and seg[id].near, `{id}: expected one far (darkened) and one near copy`)
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
-- A segment's root (its joint) and its far end, in world pixels.
local function root(sp: any, id: string): (number, number)
	local P = KIT.parts[id]
	return sp.P(sp.x0 + P.ox * sp.pw, sp.y1 - P.oy * sp.ph)
end
local function tip(sp: any, id: string): (number, number)
	local P = KIT.parts[id]
	return sp.P(sp.x0 + P.ox * sp.pw, sp.y1 - (P.oy + P.span) * sp.ph)
end
-- The joints hold: each upper segment ends exactly where its lower one hangs from.
for _, pair in { { "upperarm", "forearm" }, { "thigh", "shin" } } do
	for _, side in { "near", "far" } do
		local ex, ey = tip(seg[pair[1]][side], pair[1])
		local jx, jy = root(seg[pair[2]][side], pair[2])
		assert(math.abs(ex - jx) < 1e-9 and math.abs(ey - jy) < 1e-9,
			`{side} {pair[1]} ends at ({ex}, {ey}), its {pair[2]} hangs from ({jx}, {jy})`)
	end
end
-- The hand is the grip: the near forearm ends exactly where the sword is drawn from.
assert(grip, "the weapon was never drawn")
local gx, gy = tip(seg.forearm.near, "forearm")
assert(math.abs(gx - grip[1]) < 1e-9 and math.abs(gy - grip[2]) < 1e-9, `the hand is at ({gx}, {gy}), the grip at ({grip[1]}, {grip[2]})`)
-- And the elbow bends: the elbow is off the straight line from shoulder to hand.
local sx, sy = root(seg.upperarm.near, "upperarm")
local ex, ey = tip(seg.upperarm.near, "upperarm")
local cross = (gx - sx) * (ey - sy) - (gy - sy) * (ex - sx)
assert(math.abs(cross) / math.sqrt((gx - sx) ^ 2 + (gy - sy) ^ 2) > 2, "the front arm is straight: no elbow at rest")
-- The feet are planted: each shin ends where the one-piece leg's foot would without the bob - on
-- the floor, lifted only by the stance's leg angle - not riding the breathing up and down.
for side, rot in { far = ch.legL, near = ch.legR } do
	local _, fy = tip(seg.shin[side], "shin")
	local want = s.y + char.height * 0.34 * (1 - math.cos(rot))
	assert(math.abs(fy / 24 - want) < 1e-9, `the {side} foot is at y {fy / 24}, planted it is at {want} (bob {ch.bob})`)
end
-- Running too: the run writes its arm swing into armR.x, which the weapon never had - an armed arm
-- that kept it swung a hand-width off its own grip.
do
	local runner: any = Fighter.new({ index = 1, char = char, x = 3, y = 2, stocks = 3 })
	runner.state, runner.onGround, runner.vx = "run", true, 22
	for _, fc in { 6, 27, 48 } do
		runner.frameCount = fc
		local rs = Snapshot.decode(Snapshot.encode(runner))
		local rc = Channels.For(rs, char, nil, fc / 60)
		assert(fc ~= 27 or math.abs(rc.armR.x) > 0.1, `the run's arm swing is too small at this moment ({rc.armR.x}) to test`)
		grip = nil
		Weapons2D.draw = function(cv: any, ...)
			grip = { cv.m.e, cv.m.f }
			return weaponDraw(cv, ...)
		end
		table.clear(sprites)
		Fighter2D.draw(canvas(24), rs, char, fc / 60, 2)
		Weapons2D.draw = weaponDraw
		local fore
		for _, sp in sprites do if sp.list == art.forearm.full then fore = sp end end
		local rx, ry = tip(fore, "forearm")
		assert(grip and math.abs(rx - grip[1]) < 1e-9 and math.abs(ry - grip[2]) < 1e-9,
			`a running hand (frame {fc}) is at ({rx}, {ry}), its grip at ({grip and grip[1]}, {grip and grip[2]})`)
	end
end
-- What Roblox can actually draw: a Frame rotates and scales, it cannot shear. Every limb segment
-- must reach Canvas2D as a rotation and a scale (its matrix's columns at right angles), or the
-- picture on screen is not the one these joint checks measured - the elbow came apart by a stud in
-- a recovery, whose spin squeezes the torso to an eighth of its width. Checked across poses that
-- lean, squash and spin, with the joints and the grip held in each.
do
	local poses = {
		{ "recovery", false, 3 }, { "recovery", false, 6 }, { "idle", true, 0 }, { "run", true, 0 },
		{ "landing", true, 1 }, { "hitstun", false, 2 }, { "jumpsquat", true, 3 }, { "air", false, 5 },
	}
	local SEG = { upperarm = true, forearm = true, thigh = true, shin = true }
	local checked = 0
	for _, pose in poses do
		local pf: any = Fighter.new({ index = 1, char = char, x = 3, y = 2, stocks = 3 })
		-- `sf`, the Fighter's own field: Snapshot.encode reads it (as `stateFrame` on the wire), and a
		-- `stateFrame` set on the Fighter is dropped - which left every pose here at frame 0, so the
		-- recovery never spun and this sweep never saw the squash it was written for.
		pf.state, pf.onGround, pf.sf, pf.vx, pf.frameCount = pose[1], pose[2], pose[3], (if pose[1] == "run" then 22 else 0), 17
		local ps = Snapshot.decode(Snapshot.encode(pf))
		grip = nil
		Weapons2D.draw = function(cv: any, ...)
			grip = { cv.m.e, cv.m.f }
			return weaponDraw(cv, ...)
		end
		table.clear(sprites)
		Fighter2D.draw(canvas(24), ps, char, 0.3, 2)
		Weapons2D.draw = weaponDraw
		local got: any = {}
		for _, sp in sprites do
			local id = string.match(sp.key, "|(%a+)|")
			if SEG[id] then
				local m = { sp.P(1, 0) }
				local o = { sp.P(0, 0) }
				local u = { sp.P(0, 1) }
				local ax, ay, cx, cy = m[1] - o[1], m[2] - o[2], u[1] - o[1], u[2] - o[2]
				local skew = math.abs(ax * cx + ay * cy) / (math.sqrt(ax * ax + ay * ay) * math.sqrt(cx * cx + cy * cy))
				assert(skew < 1e-9, `{pose[1]} {pose[3]}: the {id} reaches Canvas2D sheared ({skew}), which a Frame cannot draw`)
				local far = sp.list == art[id].farFull
				got[id .. (if far then "F" else "N")] = sp
				checked += 1
			end
		end
		for _, side in { "N", "F" } do
			for _, pair in { { "upperarm", "forearm" }, { "thigh", "shin" } } do
				local ex, ey = tip(got[pair[1] .. side], pair[1])
				local jx, jy = root(got[pair[2] .. side], pair[2])
				assert(math.abs(ex - jx) < 1e-9 and math.abs(ey - jy) < 1e-9, `{pose[1]} {pose[3]}: a {pair[1]} ends off its {pair[2]}`)
			end
		end
		local hx2, hy2 = tip(got.forearmN, "forearm")
		assert(grip and math.abs(hx2 - grip[1]) < 1e-9 and math.abs(hy2 - grip[2]) < 1e-9, `{pose[1]} {pose[3]}: the hand is off the grip`)
		-- And at half detail: the one-piece limbs are shear-free too, and the near arm ends on the grip
		-- (its cells are handed over twice the size; the limb's length in studs is unchanged).
		grip = nil
		Weapons2D.draw = function(cv: any, ...)
			grip = { cv.m.e, cv.m.f }
			return weaponDraw(cv, ...)
		end
		table.clear(sprites)
		Fighter2D.draw(canvas(8), ps, char, 0.3, 2)
		Weapons2D.draw = weaponDraw
		local nearArm
		for _, sp in sprites do
			local id = string.match(sp.key, "|(%a+)|")
			if id == "arm" or id == "leg" then
				local o, m, u = { sp.P(0, 0) }, { sp.P(1, 0) }, { sp.P(0, 1) }
				local ax, ay, cx, cy = m[1] - o[1], m[2] - o[2], u[1] - o[1], u[2] - o[2]
				local skew = math.abs(ax * cx + ay * cy) / (math.sqrt(ax * ax + ay * ay) * math.sqrt(cx * cx + cy * cy))
				assert(skew < 1e-9, `{pose[1]} {pose[3]}: a half-detail {id} reaches Canvas2D sheared ({skew})`)
				if id == "arm" and sp.list == art.arm.half then nearArm = sp end
			end
		end
		local ax3, ay3 = nearArm.P(0, nearArm.y1 - (KIT.parts.arm.oy + KIT.parts.arm.span) * nearArm.ph / 2)
		assert(grip and math.abs(ax3 - grip[1]) < 1e-9 and math.abs(ay3 - grip[2]) < 1e-9,
			`{pose[1]} {pose[3]}: a half-detail hand is at ({ax3}, {ay3}), the grip at ({grip and grip[1]}, {grip and grip[2]})`)
	end
	assert(checked == #poses * 8, `{checked} segments checked, want {#poses * 8}`)
end
-- The weapon, drawn the way a Frame can draw it. It used to be drawn inside the torso's squash and
-- turned by its own angle there - a sheared transform, whose shear Canvas2D.sprite dropped, so the
-- sword sat up to 1.7 studs from the web's in an air neutral. Now, on every frame of every move of
-- every weapon, both facings: the weapon sprite reaches Canvas2D as a rotation and a uniform scale -
-- its own scale, never the body's squash, because a prop does not stretch - with its grip on the
-- hand and pointing where its angle points in the torso's frame, carried through the lean and the
-- squash. Every rectangle the weapon's drawing puts down (the trail, the lash, an ultimate's
-- afterimages and effects) is shear-free too, the axe's afterimages point where theirs do, and the
-- swing trail sweeps about the carried shoulder and ends on the blade's carried angle.
do
	local UltimateVfx = Loader.loadFrom("src/client/", "UltimateVfx")
	local WEAPONS = {
		"Sword", "Scythe", "Blasters", "Grimoire", "Axe", "Pike",
		"Gauntlets", "Hammer", "Longbow", "Flail", "Shield", "Daggers", "Whip",
	}
	local SCALE = 24
	local function skewOf(m: any): number
		return math.abs(m.a * m.c + m.b * m.d) / (math.sqrt(m.a * m.a + m.b * m.b) * math.sqrt(m.c * m.c + m.d * m.d))
	end
	local function unit(x: number, y: number): (number, number)
		local l = math.sqrt(x * x + y * y)
		return x / l, y / l
	end
	local function copy(m: any): any return { a = m.a, b = m.b, c = m.c, d = m.d, e = m.e, f = m.f } end
	local inWeapon = 0
	local weaponM, torsoM, foreSp, rectSkew, rectWhere, ghosts, trailM = nil, nil, nil, 0, "", {}, nil
	local inTrail = false
	local saved = { Canvas.sprite, Canvas.rect, Weapons2D.draw, Weapons2D.drawTrail, UltimateVfx.drawUltimate, UltimateVfx.drawMuzzle }
	local function inside(fn: any): any
		return function(...)
			inWeapon += 1
			local r = fn(...)
			inWeapon -= 1
			return r
		end
	end
	local trailDraw = inside(saved[4])
	Weapons2D.draw = inside(saved[3])
	Weapons2D.drawTrail = function(...)
		inTrail = true
		trailDraw(...)
		inTrail = false
	end
	UltimateVfx.drawUltimate, UltimateVfx.drawMuzzle = inside(saved[5]), inside(saved[6])
	Canvas.sprite = function(cv: any, key: string, list: any, x0: number, y1: number, pw: number, ph: number)
		if string.sub(key, 1, 6) == "weapon" then
			weaponM = copy(cv.m)
		elseif string.find(key, "|torso|", 1, true) then
			torsoM = copy(cv.m)
		elseif list == art.forearm.full then
			local m = cv.m
			foreSp = { x0 = x0, y1 = y1, pw = pw, ph = ph, P = function(x: number, y: number) return m.a * x + m.c * y + m.e, m.b * x + m.d * y + m.f end }
		end
		if inWeapon > 0 and skewOf(cv.m) > rectSkew then rectSkew, rectWhere = skewOf(cv.m), key end
	end
	Canvas.rect = function(cv: any, x: number, y: number, w: number)
		if inWeapon > 0 and skewOf(cv.m) > rectSkew then rectSkew, rectWhere = skewOf(cv.m), "a rectangle" end
		-- the axe's afterimage: its haft is the one rectangle 3.55 studs long (UltimateVfx axeGhost)
		if inWeapon > 0 and w == 3.55 then table.insert(ghosts, copy(cv.m)) end
		-- the trail's last step, the one on the blade: in a frame turned to its angle about the shoulder
		if inTrail then trailM = copy(cv.m) end
	end
	local poses, squeezed, ghostsChecked, trails = 0, 0, 0, 0
	for _, weaponId in WEAPONS do
		local wchar = Loadout.build(code, weaponId)
		for id, m in wchar.moves do
			for mf = 1, m.startup + m.active + m.recovery do
				local facing = if mf % 2 == 1 then 1 else -1
				local pf: any = Fighter.new({ index = 1, char = wchar, x = 3, y = 2, stocks = 3 })
				pf.state, pf.moveId, pf.sf, pf.mf, pf.frameCount = "attack", id, mf, mf, mf
				pf.startupEff, pf.charge, pf.facing = m.startup, 0, facing
				pf.onGround = string.sub(id, 1, 3) ~= "Air"
				local ps = Snapshot.decode(Snapshot.encode(pf))
				local pc = Channels.For(ps, wchar, m, 0.3)
				local wp = WeaponPose.For(ps, wchar, m, 0.3)
				if wp.hide then continue end
				weaponM, torsoM, foreSp, rectSkew, ghosts, trailM = nil, nil, nil, 0, {}, nil
				Fighter2D.draw(canvas(SCALE), ps, wchar, 0.3, 2)
				local where = `{weaponId} {id} f{mf} (facing {facing}, sx {pc.sx}, sy {pc.sy}, lean {pc.lean})`
				assert(weaponM and torsoM and foreSp, `{where}: the weapon, torso or near forearm was not drawn`)
				assert(rectSkew < 1e-9, `{where}: {rectWhere} in the weapon's drawing reaches Canvas2D sheared ({rectSkew})`)
				local M = weaponM
				assert(skewOf(M) < 1e-9, `{where}: the weapon reaches Canvas2D sheared ({skewOf(M)}), which a Frame cannot draw`)
				local sc = if wp.scale ~= 1 then wp.scale else 1
				for _, n in { math.sqrt(M.a * M.a + M.b * M.b), math.sqrt(M.c * M.c + M.d * M.d) } do
					assert(math.abs(n - SCALE * sc) < 1e-9, `{where}: the weapon is drawn at scale {n / SCALE}, its own is {sc} - squashed with the body`)
				end
				local function pointsAlong(m: any, a: number, what: string)
					local wx, wy = unit(torsoM.a * math.cos(a) + torsoM.c * math.sin(a), torsoM.b * math.cos(a) + torsoM.d * math.sin(a))
					local gx2, gy2 = unit(m.a, m.b)
					assert(math.abs(wx - gx2) < 1e-9 and math.abs(wy - gy2) < 1e-9,
						`{where}: {what} points ({gx2}, {gy2}), its angle in the torso's frame points ({wx}, {wy})`)
				end
				pointsAlong(M, wp.angle, "the weapon")
				-- The weapon's frame has its grip at the origin; the sprite is drawn past its offset and scale.
				local gx, gy = M.a * (-wp.ox / sc) + M.c * (-wp.oy / sc) + M.e, M.b * (-wp.ox / sc) + M.d * (-wp.oy / sc) + M.f
				local hx, hy = tip(foreSp, "forearm")
				assert(math.abs(gx - hx) < 1e-9 and math.abs(gy - hy) < 1e-9, `{where}: the grip is at ({gx}, {gy}), the hand at ({hx}, {hy})`)
				if weaponId == "Axe" and wp.ult and wp.ult.blur then
					assert(#ghosts == #wp.ult.blur, `{where}: {#ghosts} afterimages drawn, {#wp.ult.blur} posed`)
					for i, a in wp.ult.blur do
						pointsAlong(ghosts[i], a, `afterimage {i}`)
						ghostsChecked += 1
					end
				end
				-- The swing trail: steps about the shoulder, the last on the blade's angle, both carried
				-- out of the squash like the weapon's.
				if wp.trail then
					assert(trailM, `{where}: no trail drawn`)
					local sx, sy = wchar.radius * 0.55, wchar.height * 0.36
					local ox, oy = torsoM.a * sx + torsoM.c * sy + torsoM.e, torsoM.b * sx + torsoM.d * sy + torsoM.f
					assert(math.abs(trailM.e - ox) < 1e-9 and math.abs(trailM.f - oy) < 1e-9,
						`{where}: the trail sweeps about ({trailM.e}, {trailM.f}), the shoulder is at ({ox}, {oy})`)
					pointsAlong(trailM, wp.trail.to, "the trail's end")
					trails += 1
				end
				poses += 1
				if math.min(pc.sx / pc.sy, pc.sy / pc.sx) < 0.2 and pc.lean ~= 0 then squeezed += 1 end
			end
		end
	end
	Canvas.sprite, Canvas.rect, Weapons2D.draw, Weapons2D.drawTrail, UltimateVfx.drawUltimate, UltimateVfx.drawMuzzle = table.unpack(saved)
	assert(squeezed > 0, `the sweep never reached a pose that both leans and squeezes the torso to a fifth ({poses} poses)`)
	assert(ghostsChecked > 0, "the sweep never checked an axe afterimage")
	assert(trails > 0, "the sweep never checked a swing trail")
	print(`  weapon sweep: {poses} poses, {trails} trails, {ghostsChecked} axe afterimages, {squeezed} poses leaning and squeezed below a fifth`)
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
-- And the half-detail feet are planted too: the one-piece legs end on the floor through the bob,
-- or the feet would jump as a fighter crosses the detail threshold.
table.clear(sprites)
Fighter2D.draw(canvas(8), s, char, T, 2)
local halfLegs = 0
for _, sp in sprites do
	if string.match(sp.key, "|(%a+)|") == "leg" then
		-- a half-detail sprite is handed cells twice the size; the limb's length in studs is unchanged
		local _, fy = sp.P(0, sp.y1 - (KIT.parts.leg.oy + KIT.parts.leg.span) * sp.ph / 2)
		local rot = if sp.list == art.leg.farHalf then ch.legL else ch.legR
		local want = s.y + char.height * 0.34 * (1 - math.cos(rot))
		assert(math.abs(fy / 8 - want) < 1e-9, `a half-detail foot is at y {fy / 8}, planted it is at {want} (bob {ch.bob})`)
		halfLegs += 1
	end
end
assert(halfLegs == 2, `{halfLegs} half-detail legs checked`)
local pwCell = char.radius * 1.15 / 12
assert(pwCell * 8 < Fighter2D.KIT_LOD_PX and pwCell * 24 >= Fighter2D.KIT_LOD_PX, "the test's two zooms do not straddle the threshold")

-- The presets are kit characters under their old ids (docs/briefs/character-rework-plan.md, phase
-- 1): every one draws the eleven-piece kit body and no block body, and "Classic" draws exactly the pictures its
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
	assert(#keys == 11 and blockHeads == 0, `preset {preset.id} drew {#keys} sprites and {blockHeads} block head pieces, want a kit body`)
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
assert(#tinted == 11, `a flashing kit fighter drew {#tinted} flash pieces, want one per piece (11)`)
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

print(`PASS kit fighter: eleven jointed sprites at full detail (neck at the head, every elbow and knee joined, the hand on the grip, feet planted through the bob), seven below it, far limbs darkened, half resolution below {Fighter2D.KIT_LOD_PX} px a cell; every preset a kit body, a body with no kit the block rig; hit flash a silhouette of each piece`)
