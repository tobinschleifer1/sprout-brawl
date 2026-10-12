--!strict
-- Roblox-only presentation, downstream of the replay-held Channels and Rig. All points are in
-- the fighter's unsquashed frame (above its bob). In particular the grip and planted feet retain
-- their authored targets; a moving shoulder/hip changes the solve, never those anchors.
local Rig = require(script.Parent.Rig)
local Channels = require(script.Parent.Channels)
local Movement = require(script.Parent.Movement)
local Posture = {}

local function point(x: number, y: number, rot: number, sx: number, sy: number): (number, number)
	local cs, sn = math.cos(rot), math.sin(rot)
	return x * sx * cs - y * sy * sn, x * sx * sn + y * sy * cs
end

function Posture.torsoPoint(ch: any, h: number, x: number, y: number): (number, number)
	local px, py = point(x, y, -ch.lean, ch.sx, ch.sy)
	return px, py + h * 0.34
end

-- Angle is the departure from straight, rather than extra bone length: a small excess length
-- produces a surprisingly large kink. Solve AFTER carrying anchors through squash, so the bend
-- and the width stay consistent even during a spin. Rig itself remains the shared pure solver.
function Posture.limb(x: number, y: number, ex: number, ey: number, bend: number, side: number): Rig.Limb
	local dx, dy = ex - x, ey - y
	local d = math.sqrt(dx * dx + dy * dy)
	return Rig.solveLimb(x, y, if d > 1e-9 then dx / d else 0, if d > 1e-9 then dy / d else -1,
		d, d * 0.5 / math.cos(bend * 0.5), side)
end

local function swing(s: any, move: any, delay: number): number
	local phase = Channels.swing({ moveFrame = math.max(0, s.moveFrame - delay), startupEff = s.startupEff }, move)
	return if phase.phase == "wind" then -phase.e else phase.e
end

function Posture.For(ch: any, s: any, char: any, wpose: any, move: any, t: number): any
	local h, r = char.height, char.radius
	local motion = Movement.For(ch, s, char)
	local hip, trunk = h * 0.34 + motion.hipY, h * 0.36
	local idle = s.state == "idle"
	local running = s.state == "run"
	local speed = if running then math.min(1, math.abs(s.vx) / char.runSpeed) else 0
	local phase = motion.phase or s.frameCount * 0.38
	local breath = if idle then math.sin(t * 2.6 + s.index) else 0
	local drive, delayed = 0, 0
	if s.state == "attack" and move and move.id ~= "Ultimate" then
		drive, delayed = swing(s, move, 0), swing(s, move, 3)
	end
	local stride = math.sin(phase) * speed
	local chestSwing = math.sin(phase - 0.6) * speed
	local hipX = r * (0.07 * stride + 0.035 * breath - 0.06 * drive) + motion.hipX
	local hipRot = 0.055 * stride + 0.055 * drive
	local waistRot = -ch.lean * 0.45 + hipRot * 0.4
	local chestRot = -ch.lean - 0.11 * drive - 0.075 * chestSwing + motion.chest
	local chestSX = ch.sx * (1 - 0.055 * math.abs(drive) - 0.035 * math.abs(chestSwing))
	local chestSY = ch.sy * (1 + 0.014 * breath)
	local waistX, waistY = point(0, trunk * 7 / 18, waistRot, ch.sx, ch.sy)
	waistX += hipX; waistY += hip
	local function chestPoint(x: number, y: number): (number, number)
		local px, py = point(x, y, chestRot, chestSX, chestSY)
		return px + waistX, py + waistY
	end
	local chestH = trunk * 11 / 18
	local armed = char.weapon ~= nil
	local armAng = if armed then wpose.angle else ch.armR.z - math.pi / 2 + ch.armR.x
	local ext = if ch.armR.ext ~= 0 then ch.armR.ext else 1
	local gx, gy = Posture.torsoPoint(ch, h, r * 0.55 + math.cos(armAng) * h * 0.30 * ext,
		trunk + math.sin(armAng) * h * 0.30 * ext)
	local frontX, frontY = chestPoint(r * 0.55, chestH)
	local backX, backY = chestPoint(-r * 0.65, chestH - h * 0.009)
	-- A small scapular rise as the hand goes overhead. No scale is inherited by either arm.
	frontY += h * 0.012 * math.sin(armAng)
	backY -= h * 0.006 * math.sin(armAng)
	local frontBend = math.rad(8 + 48 * math.max(0, (ch.armR.bend or 0) - 0.2))
	local backSwing = ch.armL.z + ch.armL.x
	-- Free support arms hang and counter-swing; keep authored reaches in ledge hangs, grabs,
	-- celebrations and airborne reactions, where the hand has an actual job to do.
	if idle or running or s.state == "dash" or (s.state == "attack" and s.onGround and move and move.id ~= "Ultimate") then
		backSwing = math.clamp(backSwing * 0.65 - 0.18, -0.7, 0.65)
	end
	if motion.back then backSwing = motion.back end
	local backAng = -math.pi / 2 + backSwing - ch.lean * 0.35
	local backBend = math.rad(8 + math.min(16, math.abs(backSwing) * 14))
	local bx, by = backX + math.cos(backAng) * h * motion.armLength, backY + math.sin(backAng) * h * motion.armLength
	local neckX, neckY = chestPoint(0, chestH + h * 0.08)
	local p = {
		hipX = hipX, hipY = hip, hipRot = hipRot,
		waistX = waistX, waistY = waistY, waistRot = waistRot,
		chestRot = chestRot, chestSX = chestSX, chestSY = chestSY,
		headX = neckX, headY = neckY,
		headRot = -ch.lean * 0.55 - ch.head * 0.4 - 0.07 * delayed - 0.035 * math.sin(phase - 1.1) * speed + motion.head,
		rigRotZ = motion.rigRotZ, yOff = motion.yOff,
		frontX = frontX, frontY = frontY, backX = backX, backY = backY,
		front = Posture.limb(frontX, frontY, gx, gy, frontBend, 1),
		back = Posture.limb(backX, backY, bx, by, backBend, 1),
		legs = {},
	}
	local planted = s.onGround == true and ch.rigRotZ == 0
	for i, leg in { { ch.legL, -r * 0.30, ch.kneeL }, { ch.legR, r * 0.30, ch.kneeR } } do
		local rot, dx, tuck = leg[1], leg[2], leg[3] or 0
		local target = Rig.legPose(dx, hip, rot, hip, ch.bob, planted, tuck)
		local foot = if motion.feet then motion.feet[i] else nil
		if foot then
			target.ex, target.ey = foot.x, foot.y
			dx = foot.rootX or dx
		end
		local rx, ry = point(dx, 0, hipRot, 1, 1)
		rx += hipX; ry += hip
		if foot and foot.lane then rx = dx end
		local crouch = math.clamp(-ch.bob / (h * 0.09), 0, 1)
		local bend = math.rad(if foot then foot.bend elseif idle then 9 else 10 + 65 * tuck + 32 * crouch)
		local solved = Posture.limb(rx, ry, target.ex, target.ey, bend, -1)
		if foot and foot.lane then
			-- In a side view the passing shin should occlude the support shin, never draw an X
			-- through it. Ease the forward knee projection to zero at the passing point; retain
			-- its lifted height. Both lower segments stay in their foot's projected lane.
			local forward = solved.jx - (rx + target.ex) * 0.5
			solved.jx = (dx + target.ex) * 0.5 + forward * math.abs(foot.lane)
			-- Keep the thigh as well as the shin in that lane. A swaying hip root could still
			-- cross the other thigh, even when the shin-only intersection test passed.
			solved.jx = if foot.lane < 0 then math.min(0, solved.jx) else math.max(0, solved.jx)
		end
		table.insert(p.legs, { x = rx, y = ry, pose = solved })
	end
	return p
end

return Posture
