--!strict
-- Roblox-only presentation, downstream of the replay-held Channels and Rig. All points are in
-- the fighter's unsquashed frame (above its bob). In particular the grip and planted feet retain
-- their authored targets; a moving shoulder/hip changes the solve, never those anchors.
local Rig = require(script.Parent.Rig)
local Channels = require(script.Parent.Channels)
local Movement = require(script.Parent.Movement)
local DualWield = require(script.Parent.DualWield)
local Kicks = require(script.Parent.Kicks)
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

-- How far (of the height) a running arm's shoulder comes forward and drops at the front of its
-- swing, which is SWING_PEAK (Movement's largest swing at a full run: the hand's direction, the
-- upper arm's plus half the elbow's bend).
Posture.SWING_AHEAD, Posture.SWING_DROP = 0.045, 0.035
Posture.SWING_PEAK = Movement.ARM_PEAK
-- How much further a full run leans the trunk forward than Channels' run does (radians; the head
-- takes half). Williams' run leans about 20 degrees, hip to neck; Channels' lean alone, bent mostly
-- at the chest, read as running upright.
Posture.RUN_LEAN = 0.18

function Posture.For(ch: any, s: any, char: any, wpose: any, move: any, t: number): any
	local h, r = char.height, char.radius
	local motion = Movement.For(ch, s, char)
	-- Rocket Boots kick (Kicks): the legs strike, the hips drop for a sweep
	local kick = Kicks.For(s, char, move, ch.bob)
	if kick then motion.feet, motion.hipY = kick.feet, -kick.drop end
	if ch.emote then
		motion.feet = {}
		for i, leg in { { ch.legL, ch.kneeL, -r * 0.30 }, { ch.legR, ch.kneeR, r * 0.30 } } do
			motion.feet[i] = { x = leg[3] - math.sin(leg[1]) * h * 0.34 * (1 - leg[2] * 0.5),
				y = -ch.bob + h * 0.26 * leg[2], len = h * 0.34 }
		end
	end
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
	local runLean = Posture.RUN_LEAN * (motion.run or 0)
	local waistRot = -ch.lean * 0.45 + hipRot * 0.4 + (if kick then kick.lean * 0.5 else 0) - runLean
	local lean = if kick then kick.lean else 0 -- a high kick tilts the torso back, away from it
	local chestRot = -ch.lean - 0.11 * drive - 0.075 * chestSwing + motion.chest + lean - runLean
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
	-- A pair carried in a run (DualWield: Gauntlets, Daggers, Blasters, Chakram) pumps both arms with
	-- the stride, as an empty pair of hands does, a weapon in each fist along its forearm. Held in its
	-- guard and its weapon pose instead, the rear fist sat over the face and the front arm stuck
	-- straight out for the whole run (the owner, 2026-11-11). An attack takes the poses back.
	local pumping = armed and running and s.onGround == true and motion.frontBend ~= nil and not ch.emote
		and DualWield.paired(char)
	local armAng = if armed and not pumping then wpose.angle else ch.armR.z - math.pi / 2 + ch.armR.x
	-- an empty front hand in a run swings with the feet (Movement), hanging as the rear arm does: the
	-- torso's lean is undone here, as the rear arm's angle carries only a third of it
	if (not armed or pumping) and motion.front and not ch.emote then armAng = -math.pi / 2 + motion.front + ch.lean * 0.65 end
	local ext = if ch.armR.ext ~= 0 then ch.armR.ext else 1
	local hx, hy = r * 0.55 + math.cos(armAng) * h * 0.30 * ext, trunk + math.sin(armAng) * h * 0.30 * ext
	local gx, gy = Posture.torsoPoint(ch, h, hx, hy)
	-- A weapon that comes in pairs is held one in each hand (DualWield): a back-hand strike twists
	-- the rear shoulder forward, and the hand that is not striking holds the other one.
	local dual = if armed then DualWield.For(s, char, move, wpose, hx, hy) else nil
	local twist = if dual then dual.twist else 0
	local frontX, frontY = chestPoint(r * 0.55 + DualWield.TWIST.front * r * twist, chestH)
	local backX, backY = chestPoint(-r * 0.65 + DualWield.TWIST.back * r * twist, chestH - h * 0.009)
	-- In a run, an arm swinging forward brings its shoulder forward and down with it: hung from the
	-- top corner of the chest, the upper arm's top otherwise rose above the shoulder line as it
	-- turned. The owner set the amount by posing the near arm at the front of its swing (2026-11-08).
	-- (the whole arm moves: a swinging hand is placed from its shoulder, below)
	if motion.front and not ch.emote then
		local function reach(swing: number): number return math.clamp(swing / Posture.SWING_PEAK, 0, 1) end
		if not armed or pumping then
			local k = reach(motion.front)
			frontX += h * Posture.SWING_AHEAD * k
			frontY -= h * Posture.SWING_DROP * k
		end
		if motion.back then
			local k = reach(motion.back)
			backX += h * Posture.SWING_AHEAD * k
			backY -= h * Posture.SWING_DROP * k
		end
	end
	-- A small scapular rise as the hand goes overhead. No scale is inherited by either arm.
	frontY += h * 0.012 * math.sin(armAng)
	backY -= h * 0.006 * math.sin(armAng)
	local frontBend = math.rad(if ch.emote then ch.emote.frontBend else 8 + 48 * math.max(0, (ch.armR.bend or 0) - 0.2))
	-- Bent at the elbow (Movement), a gait's arm keeps its length: the hand comes in towards the
	-- shoulder by what the bend takes up, rather than the arm stretching to reach it.
	local swingsFront = (not armed or pumping) and motion.frontBend ~= nil and not ch.emote
	if swingsFront then frontBend = motion.frontBend end
	local backSwing = ch.armL.z + ch.armL.x
	-- Free support arms hang and counter-swing; keep authored reaches in ledge hangs, grabs,
	-- celebrations and airborne reactions, where the hand has an actual job to do.
	if idle or running or s.state == "dash" or (s.state == "attack" and s.onGround and move and move.id ~= "Ultimate") then
		backSwing = math.clamp(backSwing * 0.65 - 0.18, -0.7, 0.65)
	end
	if motion.back then backSwing = motion.back end
	local backAng = -math.pi / 2 + backSwing - ch.lean * 0.35
	local backBend = math.rad(if ch.emote then ch.emote.backBend else 8 + math.min(16, math.abs(backSwing) * 14))
	local backReach = 1
	if motion.backBend and not ch.emote then backBend, backReach = motion.backBend, math.cos(motion.backBend / 2) end
	if ch.emote then motion.armLength *= ch.emote.backExt end
	local bx = backX + math.cos(backAng) * h * motion.armLength * backReach
	local by = backY + math.sin(backAng) * h * motion.armLength * backReach
	local fx, fy = gx, gy
	if swingsFront then
		-- (from the shoulder itself, so it takes the run's lean and its swing's shift with it; the
		-- same angle as the hand placed in the torso's frame above)
		local a = armAng - ch.lean
		fx = frontX + math.cos(a) * h * 0.30 * math.cos(frontBend / 2)
		fy = frontY + math.sin(a) * h * 0.30 * math.cos(frontBend / 2)
	end
	local offX, offY
	if dual and dual.off and ch.emote then
		-- The second weapon follows the authored rear hand, rather than replacing it with a guard.
		offX, offY = bx, by
		dual.off.angle = backAng + ch.lean
	elseif dual and dual.off and pumping then
		-- the second weapon rides in the swinging rear hand (its angle, along the forearm, below)
		offX, offY = bx, by
	elseif dual and dual.off then
		offX, offY = Posture.torsoPoint(ch, h, dual.off.x, dual.off.y)
		if dual.off.hand == "back" then
			bx, by, backBend = offX, offY, math.rad(dual.off.bend)
		else
			-- the rear hand strikes: it takes the move's grip, the front hand guards with the other
			bx, by, backBend = gx, gy, frontBend
			fx, fy, frontBend = offX, offY, math.rad(dual.off.bend)
		end
	end
	local neckX, neckY = chestPoint(0, chestH + h * 0.08)
	if Kicks.guards(char, s) then
		-- the boots leave the hands empty: the front fist stays up by the chin, and through a kick
		-- the rear arm swings back against it
		fx, fy, frontBend = frontX + math.cos(1.15) * h * 0.15, frontY + math.sin(1.15) * h * 0.15, math.rad(75)
		if kick then
			local a = math.atan2(-kick.aim[2] * 0.5 - 0.5, -kick.aim[1])
			bx = bx + (backX + math.cos(a) * h * 0.27 - bx) * kick.commit
			by = by + (backY + math.sin(a) * h * 0.27 - by) * kick.commit
		end
	end
	local p = {
		hipX = hipX, hipY = hip, hipRot = hipRot,
		kick = kick,
		waistX = waistX, waistY = waistY, waistRot = waistRot,
		chestRot = chestRot, chestSX = chestSX, chestSY = chestSY,
		headX = neckX, headY = neckY,
		headRot = -ch.lean * 0.55 - ch.head * 0.4 + lean * 0.6 - 0.07 * delayed - 0.035 * math.sin(phase - 1.1) * speed + motion.head - runLean * 0.5,
		rigRotZ = motion.rigRotZ, yOff = motion.yOff, bob = motion.bob,
		frontX = frontX, frontY = frontY, backX = backX, backY = backY,
		front = Posture.limb(frontX, frontY, fx, fy, frontBend, 1),
		dual = dual, offX = offX, offY = offY,
		back = Posture.limb(backX, backY, bx, by, backBend, 1),
		legs = {},
	}
	if pumping then
		-- each weapon along its forearm, from elbow to hand (in WeaponPose's frame, which the lean turns)
		local function along(L: any): number return math.atan2(L.ey - L.jy, L.ex - L.jx) + ch.lean end
		p.pump, p.mainAngle = true, along(p.front)
		if dual and dual.off then dual.off.angle = along(p.back) end
	end
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
		if foot and foot.rootY then rx, ry = foot.rootX, foot.rootY end -- a kick aims from this hip
		local crouch = math.clamp(-ch.bob / (h * 0.09), 0, 1)
		local bend = math.rad(if foot then (foot.bend or 0) elseif idle then 9 else 10 + 65 * tuck + 32 * crouch)
		if foot and foot.len then
			-- A gait leg is one fixed length: the knee folds by exactly what the hip-to-foot
			-- distance leaves over, so a lowered body bends the planted knee and a lifted foot
			-- folds the swinging one. Nothing stretches the leg's art.
			local dx, dy = target.ex - rx, target.ey - ry
			-- Out of reach (the body risen off a pushing leg): the leg is straight and the foot
			-- comes up to meet it - straight up, on the toe, so a planted foot never slides.
			-- (a run only: a walk's trailing toe keeps its old few percent of reach)
			if (foot.run or 0) > 0 and dx * dx + dy * dy > foot.len * foot.len then
				local up = ry - math.sqrt(math.max(0, foot.len * foot.len - dx * dx))
				target.ey += (up - target.ey) * foot.run
				dy = target.ey - ry
			end
			bend = 2 * math.acos(math.min(1, math.sqrt(dx * dx + dy * dy) / foot.len))
		end
		local solved = Posture.limb(rx, ry, target.ex, target.ey, bend, -1)
		table.insert(p.legs, { x = rx, y = ry, pose = solved })
	end
	return p
end

return Posture
