--!nocheck
-- Direct geometric/presentation properties, not parity with another implementation. Run via
-- check.sh. See docs/reviews/roblox-posture.md for the deliberate failures used to validate them.
local fs, luau, Rbx = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local Loader = require("./loader")
local Posture = Loader.loadFrom("src/client/", "Posture")
local Art = Loader.loadFrom("src/client/", "PostureArt")
local Compose = Loader.loadFrom("src/client/", "AvatarCompose")
local Channels = Loader.loadFrom("src/client/", "Channels")
local WeaponPose = Loader.loadFrom("src/client/", "WeaponPose")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Draw = Loader.loadFrom("src/client/", "Fighter2D")
local Weapons = Loader.loadFrom("src/client/", "Weapons2D")
local Fighter, Loadout, Snapshot = Loader.load("Fighter"), Loader.load("Loadout"), Loader.load("Snapshot")
local Kits, WeaponData = Loader.load("Data/AvatarKit"), Loader.load("Data/Weapons")
local function near(a, b, label) assert(math.abs(a - b) < 1e-8, `{label}: {a} != {b}`) end
local function bend(x, y, L)
	local ux, uy, vx, vy = L.jx - x, L.jy - y, L.ex - L.jx, L.ey - L.jy
	return math.deg(math.acos(math.clamp((ux * vx + uy * vy) / math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy)), -1, 1)))
end
local function setup(char, state, frame, ground)
	local f = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
	f.state, f.sf, f.frameCount, f.onGround, f.invul = state, frame, frame, ground, 0
	f.vx = if state == "run" then char.runSpeed else 0
	return f
end
local function posture(s, char, t)
	local move = Fighter.moveOf(char, s.moveId)
	local ch = Channels.For(s, char, move, t)
	-- View-only means no edits even to the channel bag handed to the layer.
	table.freeze(ch.armL); table.freeze(ch.armR); table.freeze(ch)
	local p = Posture.For(ch, s, char, WeaponPose.For(s, char, move, t), move, t)
	return p, ch
end
local char = Loadout.build("Classic", "Sword")
assert(Art.sprites(char.avatar.code) == Art.sprites(char.avatar.code), "posture art is rebuilt per call")
local loX, hiX, loSY, hiSY = math.huge, -math.huge, math.huge, -math.huge
local knight
for _, preset in Kits.presets do if preset.id == "knight" then knight = preset.code end end
assert(knight, "missing knight kit")
for _, avatar in { "Classic", "Noir", knight } do
	for _, wid in { "Sword", "Pike", "Hammer", "Blasters" } do
		local ch = Loadout.build(avatar, wid)
		local f = setup(ch, "idle", 0, true)
		for i = 0, 60 do
			local p, raw = posture(Snapshot.decode(Snapshot.encode(f)), ch, i / 10)
			assert(bend(p.frontX, p.frontY, p.front) < 12, "rest front elbow bends over twelve degrees")
			assert(bend(p.backX, p.backY, p.back) < 14, "rest back elbow bends over fourteen degrees")
			for side, leg in p.legs do
				assert(bend(leg.x, leg.y, leg.pose) < 12, "rest knee bends over twelve degrees")
				local rot, dx = if side == 1 then raw.legL else raw.legR, ch.radius * (if side == 1 then -0.30 else 0.30)
				near(leg.pose.ex, dx - math.sin(rot) * ch.height * 0.34, "planted foot x follows hip sway")
				near(leg.pose.ey + raw.bob, ch.height * 0.34 * (1 - math.cos(rot)), "planted foot y follows breathing")
			end
			assert(p.legs[2].pose.jx - p.legs[1].pose.jx > ch.radius * 0.5, "rest knees collide or cross")
			assert(p.legs[2].pose.ex - p.legs[1].pose.ex > ch.radius, "rest feet collide or cross")
			loX, hiX = math.min(loX, p.hipX), math.max(hiX, p.hipX)
			loSY, hiSY = math.min(loSY, p.chestSY / raw.sy), math.max(hiSY, p.chestSY / raw.sy)
		end
	end
end
assert(hiX - loX > 0.04, "idle hips never shift weight")
assert(hiSY - loSY > 0.025, "chest never breathes")
-- Torso response and genuine phase lag: at the first strike frame the chest has turned through,
-- but the head is still following the wind-up. It follows through a few frames later, regardless
-- of the order in which a renderer happens to request those frames.
do
	local f = setup(char, "attack", 0, true)
	local s = Snapshot.decode(Snapshot.encode(f))
	s.moveFrame, s.startupEff = 11, 10
	local move = { id = "LightSide1", active = 6, recovery = 15 }
	local raw = Channels.For(Snapshot.decode(Snapshot.encode(setup(char, "idle", 0, true))), char, nil, 0)
	raw.lean, raw.head = 0, 0
	local p = Posture.For(raw, s, char, { angle = 0 }, move, 0)
	assert(p.chestRot < 0 and p.hipRot > 0, "strike chest/hips do not counter-rotate")
	assert(p.headRot > 0, "head does not lag the chest into contact")
	s.moveFrame = 15
	local later = Posture.For(raw, s, char, { angle = 0 }, move, 0)
	assert(later.headRot < 0, "head never follows through")
	assert(math.abs(p.chestRot - p.waistRot) > 0.08, "torso is a single rigid plank")
end

-- Bending is still available when the action calls for it; soft rest must not mean rigid
-- limbs everywhere. Runs counter the stride, and the hanging hand still reaches above the head.
do
	local f = setup(char, "idle", 0, true)
	f:startMove("LightSide1"); f.mf = f.startupEff
	local wind = posture(Snapshot.decode(Snapshot.encode(f)), char, 0)
	f.mf = f.startupEff + math.max(1, math.ceil(f.move.active / 2))
	local contact = posture(Snapshot.decode(Snapshot.encode(f)), char, 0)
	assert(bend(wind.frontX, wind.frontY, wind.front) > 25, "wind-up elbow never loads")
	assert(bend(contact.frontX, contact.frontY, contact.front) < 12, "contact arm does not extend")
	local squat = posture(Snapshot.decode(Snapshot.encode(setup(char, "jumpsquat", 3, true))), char, 0)
	assert(bend(squat.legs[1].x, squat.legs[1].y, squat.legs[1].pose) > 18, "crouch knee never bends")
	for _, frame in { 3, 13 } do
		local p, raw = posture(Snapshot.decode(Snapshot.encode(setup(char, "run", frame, true))), char, frame / 60)
		assert((p.chestRot + raw.lean) * p.hipRot < -0.001, "run chest/hips do not counter-rotate")
	end
	local hang = posture(Snapshot.decode(Snapshot.encode(setup(char, "ledge", 6, false))), char, 0)
	assert(hang.back.ey - hang.backY > char.height * 0.2, "ledge support hand stopped reaching overhead")
	local s = Snapshot.decode(Snapshot.encode(setup(char, "idle", 0, true)))
	local raw = Channels.For(s, char, nil, 0)
	local up = Posture.For(raw, s, char, { angle = math.pi / 2 }, nil, 0)
	local down = Posture.For(raw, s, char, { angle = -math.pi / 2 }, nil, 0)
	assert(up.frontY - down.frontY > char.height * 0.02, "shoulder does not rise with overhead reach")
end

-- The actual draw: every body/weapon/effect sprite must be shear-free. Exact joints/grip and
-- joined torso are checked in both facings, all weapons/moves, and both LODs.
local sprites, grip = {}, nil
Canvas.rect, Canvas.ellipse, Canvas.circle, Canvas.tri, Canvas.line = function() end, function() end, function() end, function() end, function() end
Canvas.sprite = function(cv, key, list, x0, y1, pw, ph, cols, rows)
	local m = table.clone(cv.m)
	local skew = math.abs(m.a * m.c + m.b * m.d) / math.sqrt((m.a * m.a + m.b * m.b) * (m.c * m.c + m.d * m.d))
	assert(skew == skew and skew < 1e-9, `{key} is sheared ({skew})`)
	local id = string.match(key, "|(%a+)|")
	if not id or not Art.parts[id] then return end
	local sp = { id = id, list = list, x0 = x0, y1 = y1, pw = pw, ph = ph, m = m, order = #sprites + 1 }
	sp.P = function(x, y) return m.a * x + m.c * y + m.e, m.b * x + m.d * y + m.f end
	table.insert(sprites, sp)
end
local weaponDraw = Weapons.draw
Weapons.draw = function(cv, ...)
	grip = { cv.m.e, cv.m.f }
	return weaponDraw(cv, ...)
end
local function canvas(scale)
	return { m = { a = scale, b = 0, c = 0, d = -scale, e = 300, f = 260 }, stack = {}, alpha = 1, alphaStack = {} }
end
local function pivot(sp, half, tip)
	local P, k = Art.parts[sp.id], if half then 2 else 1
	return sp.P(sp.x0 + P.ox * sp.pw / k, sp.y1 - (P.oy + (if tip then P.span else 0)) * sp.ph / k)
end
local draws = 0
local function check(s, ch, t)
	local p = posture(s, ch, t)
	assert(bend(p.backX, p.backY, p.back) <= 24.01, "back arm folds more than 24 degrees")
	local art = Art.sprites(ch.avatar.code)
	for _, scale in { 8, 26 } do
		local half = scale == 8
		for _, facing in { -1, 1 } do
			s.facing = facing
			table.clear(sprites); grip = nil
			local cv = canvas(scale)
			Draw.draw(cv, s, ch, t)
			assert(#cv.stack == 0, "posture leaves a transform on the canvas")
			if #sprites == 0 then continue end -- intentional blink (invulnerability, KO)
			assert(#sprites == (if half then 8 else 12), "posture added unexpected body sprites")
			local by = {}
			for _, sp in sprites do
				local far = sp.list == art[sp.id].farFull or sp.list == art[sp.id].farHalf
				by[sp.id .. (if far then "F" else "N")] = sp
				if sp.id == "arm" or sp.id == "leg" or sp.id == "upperarm" or sp.id == "forearm" or sp.id == "thigh" or sp.id == "shin" then
					local width = sp.pw / (if half then 2 else 1) * math.sqrt(sp.m.a ^ 2 + sp.m.b ^ 2)
					near(width, ch.radius * 1.15 / 12 * scale, "limb thickness inherits squash/stretch")
				end
			end
			if not half then
				for _, side in { "N", "F" } do
					for _, pair in { { "upperarm", "forearm" }, { "thigh", "shin" } } do
						local up, low = by[pair[1] .. side], by[pair[2] .. side]
						local ex, ey = pivot(up, false, true)
						local jx, jy = pivot(low, false, false)
						near(ex, jx, "joint x"); near(ey, jy, "joint y")
						assert(up.order > low.order, "lower segment top edge is not hidden by the upper")
					end
				end
			end
			if grip then
				local ex, ey = pivot(by[if half then "armN" else "forearmN"], half, true)
				near(ex, grip[1], "hand/grip x"); near(ey, grip[2], "hand/grip y")
				-- Compare against the ORIGINAL authored anchor independently of Posture. Moving both
				-- the hand and weapon together must not make a misplaced grip pass this test.
				local move = Fighter.moveOf(ch, s.moveId)
				local wp = WeaponPose.For(s, ch, move, t)
				local raw = Channels.For(s, ch, move, t)
				local ext = if raw.armR.ext ~= 0 then raw.armR.ext else 1
				local ref = canvas(scale)
				Canvas.translate(ref, s.x + raw.shakeX, s.y + raw.yOff)
				Canvas.scale(ref, facing, 1)
				local pv = ch.height * (raw.rotPivot or 0.5)
				Canvas.translate(ref, 0, pv); Canvas.rotate(ref, raw.rigRotZ * facing); Canvas.translate(ref, 0, -pv)
				Canvas.translate(ref, 0, raw.bob + ch.height * 0.34)
				Canvas.rotate(ref, -raw.lean); Canvas.scale(ref, raw.sx, raw.sy)
				Canvas.translate(ref, ch.radius * 0.55 + math.cos(wp.angle) * ch.height * 0.30 * ext,
					ch.height * 0.36 + math.sin(wp.angle) * ch.height * 0.30 * ext)
				near(grip[1], ref.m.e, "authored grip x moved"); near(grip[2], ref.m.f, "authored grip y moved")
			end
			local chest, abdomen = by.chestN, by.abdomenN
			local wx, wy = abdomen.P(0, abdomen.y1)
			local cx, cy = pivot(chest, half, false)
			near(wx, cx, "waist x"); near(wy, cy, "waist y")
			local nx, ny = chest.P(0, chest.y1 + ch.height * 0.08)
			local hx, hy = pivot(by.headN, half, false)
			near(nx, hx, "head detached from neck x"); near(ny, hy, "head detached from neck y")
			-- Core of the abdomen's top stays underneath the chest, even at the strongest bends.
			local mx, my = chest.P(0, 0)
			local det = chest.m.a * chest.m.d - chest.m.b * chest.m.c
			for _, dx in { -3, -1, 0, 1, 3 } do
				local x, y = abdomen.P(dx * abdomen.pw / (if half then 2 else 1), abdomen.y1 - abdomen.ph * 0.2)
				local lx = ((x - mx) * chest.m.d - (y - my) * chest.m.c) / det
				local ly = ((y - my) * chest.m.a - (x - mx) * chest.m.b) / det
				local row = (chest.y1 - ly) / chest.ph
				local col = (lx - chest.x0) / chest.pw
				local covered = false
				for _, rect in chest.list do
					if col >= rect[1] and col <= rect[1] + rect[3] and row >= rect[2] and row <= rect[2] + rect[4] then covered = true end
				end
				assert(covered, "waist overlap leaves an unpainted gap")
			end
			draws += 1
		end
	end
end
for _, weapon in WeaponData.LIST do
	local ch = Loadout.build("Classic", weapon.id)
	for _, state in { "idle", "run", "dash", "air", "landing", "jumpsquat", "recovery", "hitstun", "shield", "ledge", "tether", "groundpound", "taunt", "victory", "flung" } do
		for _, frame in { 1, 6, 17 } do
			local f = setup(ch, state, frame, state == "idle" or state == "run" or state == "landing" or state == "jumpsquat" or state == "shield")
			check(Snapshot.decode(Snapshot.encode(f)), ch, frame / 60)
		end
	end
	for id, move in ch.moves do
		for _, fraction in { 0, 0.5, 1, 1.05, 1.4, 2 } do
			local f = setup(ch, "idle", 0, move.grounded ~= false)
			f:startMove(id)
			f.mf = if fraction <= 1 then math.floor(f.startupEff * fraction)
				elseif fraction <= 1.4 then f.startupEff + math.max(1, math.ceil(move.active * (fraction - 1) * 2))
				else f.startupEff + move.active + math.floor(move.recovery * 0.4)
			check(Snapshot.decode(Snapshot.encode(f)), ch, 0.3)
		end
	end
end
Weapons.draw = weaponDraw

-- Beveled ends retain the player's colours, stay cached, and add only one sprite. The generated
-- rectangles in the shared composer must not be mutated by the Roblox presentation cuts.
for _, preset in Kits.presets do
	local base, art = Compose.sprites(preset.code), Art.sprites(preset.code)
	assert(Art.sprites(preset.code) == art, "posture art is rebuilt per call")
	for _, id in Compose.SEGMENTS do
		local P = Art.parts[id]
		local edge = if id == "forearm" or id == "shin" then 0 else P.h - 1
		for _, rect in art[id].full do
			if rect[2] <= edge and rect[2] + rect[4] > edge then
				assert(rect[1] >= 1 and rect[1] + rect[3] <= P.w - 1, "joint end has square protruding corners")
			end
		end
		assert(art[id].full ~= base[id].full, "posture edited the shared limb picture")
	end
	assert(Art.parts.chest.h - Art.parts.chest.oy >= 2, "waist art lost its overlap")
end
print(`PASS posture: soft rest elbows/knees, separated planted feet, hip/chest counter-rotation, delayed head, relaxed back arm; {draws} actual draws with joined joints/waist, exact grip, fixed limb width and every sprite shear-free`)

-- Exercise the actual Frame fallback using Lune's Roblox DOM, including child identity across
-- animation. Timing is a local comparison only, never a claim about the lowest Roblox devices.
local Real = luau.load(fs.readFile("src/client/Canvas2D.luau"), { debugName = "Canvas2D", environment = {
	Instance = Rbx.Instance, UDim2 = Rbx.UDim2, UDim = Rbx.UDim, Vector2 = Rbx.Vector2, Color3 = Rbx.Color3,
}, injectGlobals = true })()
for key, value in Real do Canvas[key] = value end
local framePeak, extraPeak = 0, 0
for _, preset in Kits.presets do
	local ch = Loadout.build(preset.code, "Sword")
	local base = Compose.sprites(preset.code)
	local oldFrames = #base.head.full + #base.torso.full + #base.pelvis.full
	for _, id in Compose.SEGMENTS do oldFrames += #base[id].full * 2 end
	local cv = Canvas.inFrame(Rbx.Instance.new("Frame"))
	local states = {}
	for _, state in { "idle", "run", "air", "recovery" } do
		local f = setup(ch, state, 6, state == "idle" or state == "run")
		table.insert(states, Snapshot.decode(Snapshot.encode(f)))
	end
	local function draw(s, t)
		Canvas.setTransform(cv, 26, 0, 0, -26, 300, 260)
		Draw.draw(cv, s, ch, t)
		Canvas.finish(cv)
	end
	draw(states[1], 0)
	local bodyFrames, bodySprites = 0, 0
	for key, sp in cv.sprites do
		if not string.find(key, "^weapon") then bodyFrames += #sp.children; bodySprites += 1 end
	end
	assert(bodySprites == 12, "Frame fallback exceeds one extra torso sprite")
	assert(bodyFrames - oldFrames <= 32, `posture grew the body from {oldFrames} to {bodyFrames} child Frames`)
	framePeak, extraPeak = math.max(framePeak, bodyFrames), math.max(extraPeak, bodyFrames - oldFrames)
	for _, s in states do draw(s, 0.3) end -- warm the existing expression pictures
	local identities = {}
	for key, sp in cv.sprites do identities[key] = table.clone(sp.children) end
	for frame = 1, 24 do
		local s = states[1 + frame % #states]
		s.frameCount = frame
		draw(s, frame / 60)
		for key, sp in cv.sprites do
			if string.find(key, "|head|", 1, true) then continue end -- Expressions has its own held pictures/tests
			local before = identities[key]
			assert(before and #before == #sp.children, `animation rebuilt/added a picture: {key}`)
			for i, child in sp.children do assert(child == before[i], `animation rebuilt sprite children: {key}`) end
		end
	end
end
local cv = Canvas.inFrame(Rbx.Instance.new("Frame"))
local s = Snapshot.decode(Snapshot.encode(setup(char, "run", 6, true)))
local start = os.clock()
for i = 1, 600 do
	s.frameCount = i
	Canvas.setTransform(cv, 26, 0, 0, -26, 300, 260)
	Draw.draw(cv, s, char, i / 60)
	Canvas.finish(cv)
end
print(string.format("PASS posture Frames: all presets, 12 body sprites, peak %d child Frames (+%d); moving limbs/torso reuse their children; local Lune run %.3f ms/draw", framePeak, extraPeak, (os.clock() - start) * 1000 / 600))
