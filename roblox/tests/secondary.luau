--!nocheck
-- Direct secondary-motion properties, including the real Frame fallback. Each independent fault
-- in tools/mutate-movement.py must be rejected here; this is not a replay of another renderer.
local fs, luau, Rbx = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local Loader = require("./loader")
local Secondary = Loader.loadFrom("src/client/", "Secondary")
local Posture = Loader.loadFrom("src/client/", "Posture")
local Art = Loader.loadFrom("src/client/", "PostureArt")
local Compose = Loader.loadFrom("src/client/", "AvatarCompose")
local Channels = Loader.loadFrom("src/client/", "Channels")
local WeaponPose = Loader.loadFrom("src/client/", "WeaponPose")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Draw = Loader.loadFrom("src/client/", "Fighter2D")
local Kit, Fighter, Loadout, Snapshot = Loader.load("AvatarKit"), Loader.load("Fighter"), Loader.load("Loadout"), Loader.load("Snapshot")
local function near(a, b, label) assert(math.abs(a - b) < 1e-8, label) end
local function code(parts) return Kit.encode(Kit.sanitize({ parts = parts })) end
local function equalRects(a, b)
	if #a ~= #b then return false end
	for i, rect in a do for j, value in rect do if value ~= b[i][j] then return false end end end
	return true
end
local function painted(rects, x, y)
	for _, rect in rects do
		if x >= rect[1] and x < rect[1] + rect[3] and y >= rect[2] and y < rect[2] + rect[4] then return true end
	end
	return false
end
local function state(char, name, frame)
	local f = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
	f.state, f.sf, f.frameCount, f.invincible, f.facing = name, frame, frame, 0, 1
	f.onGround = name == "run" or name == "idle" or name == "shield"
	f.vx = if name == "run" then char.runSpeed else 0
	f.x = frame * f.vx / 60
	return Snapshot.decode(Snapshot.encode(f))
end
local function posing(char, s, art)
	local move = Fighter.moveOf(char, s.moveId)
	local ch = Channels.For(s, char, move, s.frameCount / 60)
	local p = Posture.For(ch, s, char, WeaponPose.For(s, char, move, s.frameCount / 60), move, s.frameCount / 60)
	table.freeze(s); table.freeze(ch); table.freeze(p)
	return Secondary.pose(art, p, ch, s, char), p, ch
end

local cases = {}
for _, hair in { "shoulder", "long", "wavy", "ponytail", "braid", "dreads", "mullet", "anime" } do
	table.insert(cases, { code = code({ hair = hair }), kind = "hair", changed = "head" })
end
for _, neck in { "scarf", "summitMantle" } do
	table.insert(cases, { code = code({ neck = neck, hair = "ponytail", top = "trench" }), kind = neck, changed = "chest" })
end
for _, top in { "trench", "robe" } do table.insert(cases, { code = code({ top = top, hair = "ponytail" }), kind = "coat", changed = "pelvis" }) end
for _, parts in { { hair = "bald" }, { hair = "crew" }, { top = "armor", neck = "tie" } } do
	assert(Secondary.art(code(parts)).full == nil, "rigid kit part grows a trailing sprite")
end
local peak = 0
for _, case in cases do
	local before = Compose.sprites(case.code)
	local neutral = before.head.full[1][5]
	local art = Secondary.art(case.code)
	assert(art.full and #art.full > 0 and art.kind == case.kind, "catalogue tail missing or priority wrong")
	assert(Secondary.art(case.code) == art and Secondary.art(case.code).full == art.full, "secondary art rebuilt per call")
	assert(art.w * art.h <= 196 and #art.full <= 24, `trailing picture exceeds small-sprite budget: {case.code} {art.kind} {art.w}x{art.h}, {#art.full} rects`)
	assert(art.replacements[case.changed] and art.replacements[case.changed] ~= Art.sprites(case.code)[case.changed].full, "tail remains welded into its body picture")
	assert(not equalRects(art.replacements[case.changed], Art.sprites(case.code)[case.changed].full), "cut leaves a duplicate painted tail on the body")
	assert(Compose.sprites(case.code) == before and before.head.full[1][5] == neutral, "secondary cut mutated shared art")
	if art.replacements.head then
		local hurt = Secondary.head(art, "hurt")
		assert(hurt == Secondary.head(art, "hurt"), "expression cut rebuilt")
		assert(hurt ~= art.replacements.head, "cut head lost expressions")
		assert(not equalRects(hurt, art.replacements.head), "cut expression is visually neutral")
		local removed = 0
		for y = 0, Kit.KIT.parts.head.h - 1 do
			for x = 0, Kit.KIT.parts.head.w - 1 do
				if painted(before.head.full, x, y) and not painted(art.replacements.head, x, y) then
					assert(not painted(hurt, x, y), "expression repaints detached rear hair")
					removed += 1
				end
			end
		end
		assert(removed > 0, "hair cut removes no silhouette pixels")
	end
	peak = math.max(peak, #art.full)
end

-- Headwear can trim rear hair; the accessory cannot restore pixels the hat hid. Cover every
-- current headwear option instead of assuming a single cap's trim value.
for _, category in Kit.KIT.categories do
	if category.id ~= "headwear" then continue end
	for _, hat in category.options do
		local spec = Kit.sanitize({ parts = { hair = "ponytail", headwear = hat.id } })
		local a = Secondary.art(Kit.encode(spec))
		if a.full then assert(a.y >= (hat.trim or 0), "tail restores hair clipped by headwear") end
	end
end

-- The trailing rotation follows velocity with a real delay and settles AFTER the body stops.
local char = Loadout.build(cases[4].code, "Sword")
local art = Secondary.art(cases[4].code)
local rest = posing(char, state(char, "idle", 0), art)
local first = posing(char, state(char, "run", 1), art)
local moving
for frame = 2, 20 do moving = posing(char, state(char, "run", frame), art) end
assert(first.rot > moving.rot + 0.20 and moving.rot < -0.35, "tail has no delayed trail into movement")
local stop = state(char, "idle", 21); stop.stateFrame = 0
local after = posing(char, stop, art)
assert(after.rot < -0.25 and after.rot > moving.rot, "tail snaps still when movement stops")
local settled
for frame = 22, 48 do settled = posing(char, state(char, "idle", frame), art) end
assert(math.abs(settled.rot) < 0.10, "tail never settles")
near(posing(char, state(char, "run", 48), art).rot, settled.rot, "duplicate draw advances lag")
local replay = posing(char, state(char, "idle", 0), art)
near(replay.rot, rest.rot, "seek retains old secondary state")
for _, facing in { -1, 1 } do
	local mirrored = Loadout.build(cases[4].code, "Sword")
	local s = state(mirrored, "run", 20); s.facing, s.vx = facing, mirrored.runSpeed * facing
	assert(posing(mirrored, s, art).rot < -0.35, "tail leads motion when facing left")
end

-- Exercise the shipping draw, including strong squash and body rotations. The accessory root
-- is attached as a point, then rotates OUTSIDE the parent's axis scale (Frames cannot shear).
local tails, pictures, count, expectedRoot = 0, {}, 0, nil
Canvas.rect, Canvas.ellipse, Canvas.circle, Canvas.line, Canvas.tri = function() end, function() end, function() end, function() end, function() end
Canvas.sprite = function(cv, key, rects)
	local m = cv.m
	near(m.a * m.c + m.b * m.d, 0, "secondary draw shears a sprite")
	if string.find(key, "^secondary|") then
		tails += 1
		near(m.e, expectedRoot[1], "draw detached trailing root x")
		near(m.f, expectedRoot[2], "draw detached trailing root y")
		assert(not pictures[key] or pictures[key] == rects, "movement changes the trailing picture")
		pictures[key] = rects
	end
end
for _, case in cases do
	local c = Loadout.build(case.code, "Sword")
	local a = Secondary.art(case.code)
	for _, scale in { 5, 26 } do
		for _, facing in { -1, 1 } do
			for _, name in { "run", "jumpsquat", "air", "landing", "shield", "hitstun", "airdodge", "knockdown", "ledgeaction" } do
				for _, frame in { 1, 5, 15 } do
					local s = state(c, name, frame); s.facing = facing
					local trail, p, ch = posing(c, s, a)
					local pitch = if a.anchor == "head" then c.radius * 1.15 / 12 else c.height * 0.02
					local x, y, rot, sx, sy, ox, oy
					if a.anchor == "head" then x, y, rot, sx, sy, ox, oy = p.headX, p.headY, p.headRot, ch.sx, ch.sy, 9, 15.2
					elseif a.anchor == "pelvis" then x, y, rot, sx, sy, ox, oy = p.hipX, p.hipY, p.hipRot, 1, 1, 7, 2.5
					else x, y, rot, sx, sy, ox, oy = p.waistX, p.waistY, p.chestRot, p.chestSX, p.chestSY, 8, 11 end
					local dx, dy = (a.x - ox) * c.radius * 1.15 / 12 * sx, (oy - a.y) * pitch * sy
					near(trail.x, x + dx * math.cos(rot) - dy * math.sin(rot), "trailing root detached x")
					near(trail.y, y + dx * math.sin(rot) + dy * math.cos(rot), "trailing root detached y")
					tails = 0
					local angle = (p.rigRotZ or ch.rigRotZ) * facing
					local pv = c.height * (ch.rotPivot or 0.5)
					local qy = trail.y + ch.bob - pv
					expectedRoot = {
						scale * (s.x + ch.shakeX + facing * (trail.x * math.cos(angle) - qy * math.sin(angle))),
						-scale * (s.y + (p.yOff or ch.yOff) + trail.x * math.sin(angle) + qy * math.cos(angle) + pv),
					}
					local cv = { m = { a = scale, b = 0, c = 0, d = -scale, e = 0, f = 0 }, stack = {}, alpha = 1, alphaStack = {} }
					Draw.draw(cv, s, c, frame / 60)
					assert(tails == (if scale == 5 then 0 else 1), "expected exactly one tail at full detail and none at match LOD")
					assert(#cv.stack == 0, "secondary draw leaks transform")
					count += 1
				end
			end
		end
	end
end

local Real = luau.load(fs.readFile("src/client/Canvas2D.luau"), { debugName = "Canvas2D", environment = {
	Instance = Rbx.Instance, UDim2 = Rbx.UDim2, UDim = Rbx.UDim, Vector2 = Rbx.Vector2, Color3 = Rbx.Color3,
}, injectGlobals = true })()
for key, value in Real do Canvas[key] = value end
assert(not Canvas.imagesOn(), "benchmark is not the Frame fallback")
local roster = {}
for _, i in { 4, 6, 9, 10, 11, 12 } do table.insert(roster, Loadout.build(cases[i].code, "Sword")) end
for _, scale in { 5, 26 } do
	local root = Rbx.Instance.new("Frame")
	local cv = Canvas.inFrame(root)
	local ids, rebuilds, maxFrames, extra = {}, 0, 0, 0
	local start
	for frame = 1, 180 do
		if frame == 31 then start = os.clock() end
		for i, c in roster do
			local s = state(c, "run", frame)
			Canvas.setTransform(cv, scale, 0, 0, -scale, i * 180 - s.x * scale, 200)
			Draw.draw(cv, s, c, frame / 60)
		end
		local children, tailCount = 0, 0
		for key, sp in cv.sprites do
			children += #sp.children
			if string.find(key, "^secondary|") then tailCount += 1 end
			if ids[key] then
				assert(#ids[key] == #sp.children, "animation rebuilt Frame picture")
				for j, child in sp.children do assert(ids[key][j] == child, "animation replaced a child Frame") end
			else ids[key] = table.clone(sp.children) end
		end
		if frame > 30 then rebuilds += cv.built end
		maxFrames, extra = math.max(maxFrames, children), math.max(extra, tailCount)
		Canvas.finish(cv)
	end
	assert(rebuilds == 0, "warm movement rebuilds pictures")
	assert(extra == (if scale == 5 then 0 else 6), "six-fighter accessory budget exceeded")
	print(string.format("PASS secondary Frame fallback: six fighters, %s, %d child Frames, %d Instances, %d extra sprites, %d warm rebuilt rects, %.3f ms/frame (local Lune)", if scale == 5 then "match LOD" else "full", maxFrames, #root:GetDescendants(), extra, rebuilds, (os.clock() - start) * 1000 / 150))
end
-- Fill the new cache with distinct valid colours; it must evict old entries without corrupting
-- pictures already held by a canvas. Existing composer caches are outside this change's scope.
local retained = art.full
for i = 0, 95 do
	local spec = Kit.sanitize({ parts = { hair = "ponytail" }, colours = { top = i % 32, trim = math.floor(i / 32) } })
	Secondary.art(Kit.encode(spec))
end
assert(Secondary.cacheSize() <= Secondary.CACHE_MAX, "secondary cache is unbounded")
assert(art.full == retained and #retained > 0, "eviction mutates active art")
print(`PASS secondary: {count} shear-free draws; attached roots, lag/settle/mirror/seek, all rear hair, scarf, mantle, coat/robe; max {peak} tail rects; bounded cache`)
