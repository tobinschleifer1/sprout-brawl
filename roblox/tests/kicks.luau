--!nocheck
-- Rocket Boots fight with the legs (src/client/Kicks.luau, KickFx.luau; Roblox only). Direct
-- properties, through every frame of every boots move: the kicking leg chambers, then strikes
-- along the line to its hitbox on exactly the frames Combat counts the box live, then recoils and
-- sets down; the other leg stays planted; legs keep their length and knees bend forward; the hands
-- guard instead of punching; high kicks lean back and sweeps drop; the blast reaches the box's far
-- side and is drawn only while it is live; a landed kick bursts in fire.
local Loader = require("./loader")
local Kicks = Loader.loadFrom("src/client/", "Kicks")
local KickFx = Loader.loadFrom("src/client/", "KickFx")
local Posture = Loader.loadFrom("src/client/", "Posture")
local Movement = Loader.loadFrom("src/client/", "Movement")
local Channels = Loader.loadFrom("src/client/", "Channels")
local WeaponPose = Loader.loadFrom("src/client/", "WeaponPose")
local Fighter2D = Loader.loadFrom("src/client/", "Fighter2D")
local FxPlayer = Loader.loadFrom("src/client/", "FxPlayer")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Recorder = require("../tools/recorder")
Recorder.install(Canvas)
local Fighter, Loadout, Snapshot = Loader.load("Fighter"), Loader.load("Loadout"), Loader.load("Snapshot")
local c = Loadout.build("Classic", "RocketBoots")
local h, r = c.height, c.radius
local L = Movement.gait(c).leg
local function near(a, b, eps, msg) assert(math.abs(a - b) <= (eps or 1e-6), msg) end

local function fighter(id, mf, ground)
	local move = Fighter.moveOf(c, id)
	local f = Fighter.new({ index = 0, char = c, x = 0, y = 0, stocks = 3 })
	f.state, f.onGround, f.facing, f.invincible = "attack", ground, 1, 0
	f.move, f.moveId, f.mf, f.sf, f.frameCount = move, id, mf, mf, 100 + mf
	f.startupEff, f.startupShift = move.startup, 0
	return f, move
end
local function pose(f, move)
	local s = Snapshot.decode(Snapshot.encode(f))
	local ch = Channels.For(s, c, move, s.frameCount / 60)
	return Posture.For(ch, s, c, WeaponPose.For(s, c, move, s.frameCount / 60), move, s.frameCount / 60), ch, s
end
-- which of the move's hitboxes Combat counts live on this frame (its own rule: moveFrameAbs)
local function live(f, move)
	for i, hb in move.hitboxes do
		if f.moveFrameAbs >= hb.frames[1] and f.moveFrameAbs <= hb.frames[2] then return hb, i end
	end
	return nil
end
local function kneeForward(leg)
	local P = leg.pose
	local dx, dy = P.ex - leg.x, P.ey - leg.y
	return (dx * (P.jy - leg.y) - dy * (P.jx - leg.x)) / math.sqrt(dx * dx + dy * dy)
end
local function legLength(leg)
	local P = leg.pose
	return math.sqrt((P.jx - leg.x) ^ 2 + (P.jy - leg.y) ^ 2) + math.sqrt((P.ex - P.jx) ^ 2 + (P.ey - P.jy) ^ 2)
end

local frames, strikes = 0, 0
for id, style in Kicks.MOVES do
	local move = Fighter.moveOf(c, id)
	local ground = move.grounded ~= false and string.sub(id, 1, 3) ~= "Air"
	local single = type(style.leg) == "number"
	local plant
	for mf = 0, move.total do
		local f = fighter(id, mf, ground)
		local p, ch = pose(f, move)
		assert(p.kick, `{id} {mf}: the boots are not kicking`)
		for i, leg in p.legs do
			near(legLength(leg), L, 1e-6, `{id} {mf}: leg {i} is {legLength(leg)} long, not {L}`)
			assert(kneeForward(leg) > -1e-6, `{id} {mf}: leg {i}'s knee bends backwards`)
		end
		local hb = live(f, move)
		local anyActive = p.kick.active[1] or p.kick.active[2]
		assert((hb ~= nil) == anyActive, `{id} {mf}: the leg strikes {anyActive and "with no live box" or "late: its box is live"}`)
		if hb then
			for i, leg in p.legs do
				if p.kick.active[i] then
					-- along the line from its hip, toward the box, a leg's length out (or onto it)
					local d = p.kick.dirs[i]
					local fx, fy = leg.pose.ex - leg.x, leg.pose.ey - leg.y
					near(fx * d[2] - fy * d[1], 0, 1e-6, `{id} {mf}: leg {i} does not strike along its kick`)
					local tx, ty = hb.offset[1] - leg.x, hb.offset[2] - ch.bob - leg.y
					assert(fx * d[1] + fy * d[2] > 0 and (tx * d[1] + ty * d[2]) > 0, `{id} {mf}: leg {i} kicks away from its box`)
					-- the blast's far end is at the box's far side: inside the box, or on its edge
					local bx, by = leg.pose.ex + d[1] * p.kick.reach[i], leg.pose.ey + d[2] * p.kick.reach[i]
					local cx, cy = hb.offset[1], hb.offset[2] - ch.bob
					assert(math.abs(bx - cx) <= hb.size[1] / 2 + 0.6 and math.abs(by - cy) <= hb.size[2] / 2 + 0.6,
						`{id} {mf}: the blast ends at ({bx}, {by}), off its box at ({cx}, {cy})`)
					-- and that end is the box's far side along the kick, not short of it
					local along = (bx - cx) * d[1] + (by - cy) * d[2]
					local far = math.abs(d[1]) * hb.size[1] / 2 + math.abs(d[2]) * hb.size[2] / 2
					assert(along >= far - 0.25, `{id} {mf}: the blast stops {far - along} short of its box's far side`)
					strikes += 1
				end
			end
		end
		if ground and single then
			-- the leg that is not kicking stays planted: on the ground, where it started
			local k = if style.leg == 1 then 2 else 1
			local foot = p.legs[k].pose
			near(foot.ey + ch.bob, 0, 1e-6, `{id} {mf}: the standing foot left the ground`)
			plant = plant or foot.ex
			near(foot.ex, plant, 1e-6, `{id} {mf}: the standing foot slid`)
		end
		frames += 1
	end
	if single and move.hitboxes[1] then
		local a = move.hitboxes[1].frames[1]
		local leg = style.leg
		-- the last wind-up frame is chambered: the knee folded, the foot off the floor and drawn in
		local p, ch = pose(fighter(id, a - 1, ground), move)
		local P = p.legs[leg]
		local reach = math.sqrt((P.pose.ex - P.x) ^ 2 + (P.pose.ey - P.y) ^ 2)
		if style.axe then
			-- an axe kick's wind-up lifts the foot overhead, to bring it down
			assert(P.pose.ey > P.y + L * 0.5, `{id}: the axe kick's foot is not raised overhead before it falls`)
		else
			assert(reach < L * 0.75, `{id}: the kicking leg is not chambered before it strikes ({reach})`)
		end
		-- off the floor: well up for a kick, just clear of it for a sweep, which skims along it
		if ground then
			local lift = if style.drop then L * 0.08 else L * 0.3
			assert(P.pose.ey + ch.bob > lift, `{id}: a chambered foot stays on the floor ({P.pose.ey + ch.bob})`)
		end
		if ground then
			-- and the move ends set down again
			local e, ech = pose(fighter(id, move.total, ground), move)
			near(e.legs[leg].pose.ey + ech.bob, 0, 1e-6, `{id}: the kicking foot never sets down`)
		end
	end
end
assert(frames > 400 and strikes > 50, `only {frames} frames and {strikes} strikes checked`)

-- A linked kick starts sooner (startupEff < startup, Fighter's startupShift): the leg still
-- strikes on exactly the frames Combat counts its box live.
do
	local move = Fighter.moveOf(c, "LightNeutral2")
	for mf = 0, move.total do
		local f = fighter("LightNeutral2", mf, true)
		f.startupEff, f.startupShift = move.startup - 2, 2
		local p = pose(f, move)
		local on = p.kick.active[1] or p.kick.active[2]
		assert((live(f, move) ~= nil) == on, `a linked LightNeutral2 at {mf}: the leg and its box disagree`)
	end
end

-- The ultimate's three windows: forward with the near leg, back with the far one, then both.
do
	local move = Fighter.moveOf(c, "Ultimate")
	local function at(w)
		local hb = move.hitboxes[w]
		return pose(fighter("Ultimate", hb.frames[1], true), move).kick
	end
	local a, b, d = at(1), at(2), at(3)
	assert(a.active[1] and not a.active[2] and a.dirs[1][1] > 0, "Redline's first kick is not the near leg, forward")
	assert(b.active[2] and not b.active[1] and b.dirs[2][1] < 0, "Redline's reverse kick is not the far leg, backward")
	assert(d.active[1] and d.active[2], "Redline's thrust is not both heels")
end

-- Hands: a guard, not a punch at a weapon that is not there; the rear arm swings against a kick.
do
	local move = Fighter.moveOf(c, "LightSide1")
	local mid = move.hitboxes[1].frames[1]
	local p, ch, s = pose(fighter("LightSide1", mid, true), move)
	local wp = WeaponPose.For(s, c, move, s.frameCount / 60)
	-- where the hand would be holding a weapon: the authored grip, as Posture places it
	local ext = if ch.armR.ext ~= 0 then ch.armR.ext else 1
	local gx, gy = Posture.torsoPoint(ch, h, r * 0.55 + math.cos(wp.angle) * h * 0.30 * ext, h * 0.36 + math.sin(wp.angle) * h * 0.30 * ext)
	assert(math.sqrt((p.front.ex - gx) ^ 2 + (p.front.ey - gy) ^ 2) > r * 0.3, "the front hand still punches the boots' empty grip")
	assert(p.front.ey > p.frontY, "the front fist is not up in a guard")
	assert((p.back.ex - p.backX) * p.kick.aim[1] < 0, "the rear arm does not swing against the kick")
end

-- High kicks lean back, sweeps drop the hips: measured against the same frame without them.
local function without(field, id)
	local style = Kicks.MOVES[id]
	local move = Fighter.moveOf(c, id)
	local mf = move.hitboxes[1].frames[1]
	local with = pose(fighter(id, mf, true), move)
	local saved = style[field]
	style[field] = nil
	local flat = pose(fighter(id, mf, true), move)
	style[field] = saved
	return with, flat
end
do
	local with, flat = without("lean", "LightUp")
	assert(with.chestRot > flat.chestRot + 0.3, "the rising heel does not lean the torso back")
	with, flat = without("drop", "LightDown")
	assert(with.hipY < flat.hipY - L * 0.2, "the sweep does not drop the hips")
end

-- The effects: the blast and the exhaust only while a leg strikes, the exhaust doubled on the
-- frames a fuel-burning move ignites, and one of each per striking leg.
local function fx(id, mf, air)
	local f = fighter(id, mf, not air)
	local seen = {}
	local real = Canvas.sprite
	Canvas.sprite = function(cv, key, list, x0, y1, pw, ph, cols, rows, ...)
		if string.sub(key, 1, 7) == "kickfx|" then table.insert(seen, { key = key, pw = pw, ph = ph, cols = cols }) end
		return real(cv, key, list, x0, y1, pw, ph, cols, rows, ...)
	end
	local cv = Recorder.canvas(Canvas, 300, 260)
	Canvas.world(cv, 0, 3, 26, 0, 0)
	Fighter2D.draw(cv, Snapshot.decode(Snapshot.encode(f)), c, f.frameCount / 60)
	Canvas.sprite = real
	return seen
end
do
	local move = Fighter.moveOf(c, "SigSide")
	local a = move.hitboxes[1].frames[1]
	assert(#fx("SigSide", a - 1) == 0, "the blast is drawn before the kick strikes")
	local on = fx("SigSide", a)
	assert(#on == 2 and on[1].key == "kickfx|plume" and on[2].key == "kickfx|blast", "a striking kick does not draw one exhaust and one blast")
	local later = fx("SigSide", a + 3)
	assert(#later == 2, "the blast stops while the box is still live")
	near(on[1].pw * on[1].cols, KickFx.PLUME_LENGTH * 2, 1e-9, "the ignition frame's exhaust is not doubled")
	near(later[1].pw * later[1].cols, KickFx.PLUME_LENGTH, 1e-9, "the exhaust stays doubled after ignition")
	assert(#fx("SigSide", move.hitboxes[1].frames[2] + 1) == 0, "the blast outlasts the box")
	local split = Fighter.moveOf(c, "AirNeutral")
	assert(#fx("AirNeutral", split.hitboxes[1].frames[1], true) == 4, "a split kick does not blast from both feet")
end

-- A landed kick bursts in fire with a ring in the boots' glow; a sword still cuts.
do
	local sword = Loadout.build("Classic", "Sword")
	local states = { { index = 0, x = 0, y = 0, state = "attack", moveId = "LightNeutral1", moveFrame = 6 } }
	local function kinds(char)
		local P = FxPlayer.new()
		FxPlayer.hit(P, { attacker = 0, x = 1, y = 2, damage = 6, angle = 45, facing = 1 }, states, { char })
		local out = {}
		for _, it in P.items do out[it.kind .. "|" .. tostring(it.ramp)] = true end
		return out
	end
	local k = kinds(c)
	assert(k["pop|fire"] and k["lance|fire"], "a landed kick does not burst in fire")
	assert(not kinds(sword)["pop|fire"], "a sword's hit bursts in fire")
end

-- Nothing else kicks.
for _, wid in { "Sword", "Gauntlets", "Daggers" } do
	local w = Loadout.build("Classic", wid)
	local f = Fighter.new({ index = 0, char = w, x = 0, y = 0, stocks = 3 })
	f.state, f.onGround, f.move, f.moveId, f.mf = "attack", true, Fighter.moveOf(w, "LightNeutral1"), "LightNeutral1", 6
	assert(Kicks.For(Snapshot.decode(Snapshot.encode(f)), w, f.move, 0) == nil, `{wid} kicks`)
end
print(string.format("PASS kicks: %d frames of every Rocket Boots move - legs whole, knees forward, chamber then strike on exactly the live frames along the line to the box, recoil and set down, the other foot planted; %d strikes; Redline's three kicks; guard and counter-swing; lean and drop; blast and exhaust only while live, ignition doubled; landed kicks burst in fire", frames, strikes))
