--!nocheck
-- What a melee move hits is where it is drawn (HitAim, Roblox only; the weapons review, round 1:
-- on 155 of 216 melee moves the drawing and the live hitbox disagreed). Every melee move of every
-- weapon is drawn at contact (mid-active) through the shipping renderer and measured the way the
-- review measured it:
--   * a live box that reaches OVERREACH studs or more past anything drawn, and
--   * a blade that sticks OUTSIDE studs or more out of every live box.
-- The counts are a ratchet: they may only go down. The aim itself is checked directly: at
-- contact the weapon points from the shoulder at its box's centre, the windup before the first
-- active frame is left as authored, and the trail's leading end reaches the box's far edge.
--
--     lune run tests/hit-aim
local Loader = require("./loader")
local Fighter, Loadout, Snapshot, Weapons = Loader.load("Fighter"), Loader.load("Loadout"), Loader.load("Snapshot"), Loader.load("Weapons")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Fighter2D = Loader.loadFrom("src/client/", "Fighter2D")
local Channels = Loader.loadFrom("src/client/", "Channels")
local WeaponPose = Loader.loadFrom("src/client/", "WeaponPose")
local Posture = Loader.loadFrom("src/client/", "Posture")
local HitAim = Loader.loadFrom("src/client/", "HitAim")
local Weapons2D = Loader.loadFrom("src/client/", "Weapons2D")
local OVERREACH, OUTSIDE = 2.0, 1.5
-- Measured with the aim (2026-11-11), of 200 moves. Without it this test counts 134, 122 and 165
-- (the review, on its own sample of 216: 137, 110 and 155). Most of what is left is a weapon drawn
-- longer than its box (the Pike's lights, the Flail): the box, not the drawing, is short.
-- (weapons round 3: the Pike's boxes reach its drawn tip, 44, 65, 96 -> 43, 62, 94)
local MOST_OVERREACH, MOST_OUTSIDE, MOST_EITHER = 43, 62, 94
Fighter2D.effects = nil

local PPU = 40
local art, blade = {}, {}
local drawingWeapon = false
for _, k in { "ellipse", "circle", "tri", "line" } do Canvas[k] = function() end end
local function record(list: any, m: any, x: number, y: number, w: number, h: number)
	for _, p in { { x + w / 2, y + h / 2 }, { x, y }, { x + w, y }, { x, y + h }, { x + w, y + h } } do
		table.insert(list, { (m.a * p[1] + m.c * p[2] + m.e) / PPU, -(m.b * p[1] + m.d * p[2] + m.f) / PPU })
	end
end
Canvas.rect = function(c, x, y, w, h, _colour, alpha)
	if (alpha or 1) * c.alpha < 0.3 then return end
	record(art, c.m, x, y, w, h)
end
Canvas.sprite = function(c, key, rects, x0, y1, pw, ph)
	local weapon = string.sub(key, 1, 7) == "weapon|"
	Canvas.eachSpriteRect(rects, x0, y1, pw, ph, function(x, y, w, h, _, a)
		if a * c.alpha < 0.3 then return end
		record(art, c.m, x, y, w, h)
		if weapon then record(blade, c.m, x, y, w, h) end
	end)
end

local function contact(char: any, id: string): (any, any, number)
	local m = char.moves[id]
	local f = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
	f.facing = 1
	local air = m.grounded == false
	f.onGround = not air
	f.y = if air then 2.5 else 0
	f:setState(if air then "air" else "idle")
	f:startMove(id)
	f.mf = f.startupEff + math.max(1, math.ceil(f.move.active / 2))
	return f, m, f.y
end
local function live(m: any, abs: number): { any }
	local out = {}
	for _, hb in m.hitboxes do
		if abs >= hb.frames[1] and abs <= hb.frames[2] then table.insert(out, hb) end
	end
	return out
end

local moves, overreach, outside, either = 0, 0, 0, 0
local worst = {}
for _, w in Weapons.LIST do
	local char = Loadout.build("Classic", w.id)
	for id, m in char.moves do
		if not HitAim.aims(char, m) then continue end
		local f, _, fy = contact(char, id)
		local s = Snapshot.decode(Snapshot.encode(f))
		table.clear(art); table.clear(blade)
		local c = setmetatable({ used = 0, stack = {}, alpha = 1, alphaStack = {}, m = { a = PPU, b = 0, c = 0, d = -PPU, e = 0, f = 0 },
			gui = { AbsoluteSize = { X = 800, Y = 800 } }, finish = function() end }, { __index = Canvas })
		Fighter2D.draw(c, s, char, 0, 0)
		local boxes = live(m, HitAim.absFrame(s, m))
		if #boxes == 0 then continue end
		moves += 1
		-- how far the box reaches past anything drawn: its furthest point from the nearest drawn one
		local reach = 0
		for _, hb in boxes do
			local cx, cy = hb.offset[1], fy + hb.offset[2]
			for i = 0, 8 do
				for j = 0, 8 do
					local px, py = cx + (i / 8 - 0.5) * hb.size[1], cy + (j / 8 - 0.5) * hb.size[2]
					local near = math.huge
					for _, q in art do near = math.min(near, (q[1] - px) ^ 2 + (q[2] - py) ^ 2) end
					reach = math.max(reach, math.sqrt(near))
				end
			end
		end
		-- how far the blade sticks out of every live box
		local out = 0
		for _, q in blade do
			local best = math.huge
			for _, hb in boxes do
				local dx = math.max(0, math.abs(q[1] - hb.offset[1]) - hb.size[1] / 2)
				local dy = math.max(0, math.abs(q[2] - (fy + hb.offset[2])) - hb.size[2] / 2)
				best = math.min(best, math.sqrt(dx * dx + dy * dy))
			end
			out = math.max(out, best)
		end
		local a, b = reach >= OVERREACH, out >= OUTSIDE
		if a then overreach += 1 end
		if b then outside += 1 end
		if a or b then either += 1; table.insert(worst, { `{w.id} {id}`, reach, out }) end

		-- the aim, directly. On the middle active frame the weapon points from the shoulder at the
		-- box's centre; across the active frames it sweeps as authored (the same turn added to every
		-- live frame: holding it on the box froze the swing, round 2's review)
		local reachOf = Weapons2D.REACH[Weapons2D.baseOf(w.id)] or 2.4
		local ch = Channels.For(s, char, m, 0)
		local authored = WeaponPose.For(s, char, m, 0)
		local aimed = HitAim.apply(s, char, m, ch, authored, reachOf, 0)
		assert(aimed, `{w.id} {id} is not aimed at contact`)
		local lo, hi = math.huge, -math.huge
		for _, box in m.hitboxes do lo = math.min(lo, box.frames[1]); hi = math.max(hi, box.frames[2]) end
		local function at(abs: number): (any, any, any)
			local g = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
			g.facing, g.onGround = 1, m.grounded ~= false
			g.y = if g.onGround then 0 else 2.5
			g:setState(if g.onGround then "idle" else "air")
			g:startMove(id)
			g.mf = abs - (m.startup - g.startupEff)
			local gs = Snapshot.decode(Snapshot.encode(g))
			local gch = Channels.For(gs, char, m, 0)
			local raw = WeaponPose.For(gs, char, m, 0)
			return gs, gch, raw, HitAim.apply(gs, char, m, gch, raw, reachOf, 0)
		end
		local sm, chm, _, aimm = at(lo + math.floor((hi - lo) / 2))
		local _, hb = HitAim.target(sm, m)
		local sx, sy = Posture.torsoPoint(chm, char.height, char.radius * 0.55, char.height * 0.36)
		local want = math.atan2(hb.offset[2] - sy, hb.offset[1] - sx)
		local d = (aimm.angle - chm.lean - want + math.pi) % (2 * math.pi) - math.pi
		assert(math.abs(d) < 1e-6, `{w.id} {id} points {math.deg(d)} degrees off its box on its middle active frame`)
		if hi > lo then
			local _, _, raw1, aim1 = at(lo)
			local _, _, raw2, aim2 = at(hi)
			local function wrap(a: number): number return (a + math.pi) % (2 * math.pi) - math.pi end
			local sweep, drawn = wrap(raw2.angle - raw1.angle), wrap(aim2.angle - aim1.angle)
			assert(math.abs(wrap(drawn - sweep)) < math.rad(10),
				`{w.id} {id} sweeps {math.deg(drawn)} degrees through its active frames, authored {math.deg(sweep)}`)
		end
		if authored.trail then
			assert((aimed.trailFar or 0) >= (Weapons2D.REACH[Weapons2D.baseOf(w.id)] or 2.4) * (authored.scale or 1) - 1e-9,
				`{w.id} {id}'s trail no longer reaches as far as the blade`)
		end
		-- the windup: the last startup frame is drawn as authored
		local g = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
		g.facing, g.onGround = 1, m.grounded ~= false
		g:setState(if g.onGround then "idle" else "air")
		g:startMove(id)
		local lo = math.huge
		for _, box in m.hitboxes do lo = math.min(lo, box.frames[1]) end
		g.mf = lo - 1 - (m.startup - g.startupEff)
		local gs = Snapshot.decode(Snapshot.encode(g))
		if HitAim.absFrame(gs, m) == lo - 1 then
			local wind = HitAim.apply(gs, char, m, Channels.For(gs, char, m, 0), WeaponPose.For(gs, char, m, 0), 2.4)
			assert(wind == nil, `{w.id} {id}'s windup is aimed before its first active frame`)
		end
	end
end
table.sort(worst, function(x, y) return x[2] + x[3] > y[2] + y[3] end)
for k = 1, math.min(8, #worst) do print(string.format("  %-28s box past art %.1f, blade out of box %.1f", worst[k][1], worst[k][2], worst[k][3])) end
assert(overreach <= MOST_OVERREACH, `{overreach} melee moves have a box reaching {OVERREACH}+ studs past the drawing (at most {MOST_OVERREACH})`)
assert(outside <= MOST_OUTSIDE, `{outside} melee moves have a blade {OUTSIDE}+ studs out of its boxes (at most {MOST_OUTSIDE})`)
assert(either <= MOST_EITHER, `{either} melee moves disagree with their hitboxes (at most {MOST_EITHER})`)
print(`PASS hit aim: {moves} melee moves drawn at contact; {overreach} reach {OVERREACH}+ studs past the drawing, {outside} have a blade {OUTSIDE}+ studs out of their boxes, {either} either (the review's baseline: 137, 110, 155); every one points at its box, no windup is aimed`)
