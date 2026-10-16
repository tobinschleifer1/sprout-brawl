--!nocheck
-- Direct movement properties; no second implementation to agree with. Mutation evidence is in
-- docs/reviews/roblox-movement.md. Existing posture/weapon replay checks still run independently.
local Loader = require("./loader")
local Posture = Loader.loadFrom("src/client/", "Posture")
local Movement = Loader.loadFrom("src/client/", "Movement")
local Channels = Loader.loadFrom("src/client/", "Channels")
local WeaponPose = Loader.loadFrom("src/client/", "WeaponPose")
local Fighter, Loadout, Snapshot = Loader.load("Fighter"), Loader.load("Loadout"), Loader.load("Snapshot")
local char = Loadout.build("Classic", "Sword")
local h, r = char.height, char.radius
local function near(a, b, msg) assert(math.abs(a - b) < 1e-8, msg) end
local function state(name, frame, overrides)
	local f = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
	f.state, f.sf, f.frameCount, f.invincible, f.facing = name, frame, frame, 0, 1
	f.onGround = name == "run" or name == "idle" or name == "jumpsquat" or name == "landing" or name == "shield" or name == "spotdodge" or name == "knockdown" or name == "tech"
	local s = Snapshot.decode(Snapshot.encode(f))
	for k, v in overrides or {} do s[k] = v end
	return s
end
local function pose(s)
	local move = Fighter.moveOf(char, s.moveId)
	local ch = Channels.For(s, char, move, s.frameCount / 60)
	table.freeze(ch.armL); table.freeze(ch.armR); table.freeze(ch)
	table.freeze(s)
	return Posture.For(ch, s, char, WeaponPose.For(s, char, move, s.frameCount / 60), move, s.frameCount / 60), ch
end
local G = Movement.gait(char)
local function sample(x, ratio, facing)
	local s = state("run", 0, { x = x * facing, facing = facing, vx = char.runSpeed * ratio * facing })
	local p, raw = pose(s)
	return p, raw, s
end
local function len(leg)
	local L = leg.pose
	return math.sqrt((L.jx - leg.x) ^ 2 + (L.jy - leg.y) ^ 2) + math.sqrt((L.ex - L.jx) ^ 2 + (L.ey - L.jy) ^ 2)
end
local function kneeForward(leg)
	-- how far the knee sits forward of the hip-to-foot line (positive: forward, as a knee bends)
	local L = leg.pose
	local dx, dy = L.ex - leg.x, L.ey - leg.y
	return (dx * (L.jy - leg.y) - dy * (L.jx - leg.x)) / math.sqrt(dx * dx + dy * dy)
end
local samples, clearance = 0, math.huge
for _, facing in { -1, 1 } do
	for _, ratio in { 0.12, 0.28, 0.55, 1 } do
		local last, lastS, flight = nil, nil, 0
		local low, high = { math.huge }, { -math.huge }
		for j = 0, 240 do
			local x = G.step * 2 * j / 240
			local p, _, s = sample(x, ratio, facing)
			local a, b = p.legs[1].pose, p.legs[2].pose
			local la, lb = p.legs[1], p.legs[2]
			-- Away from the passing point the sockets separate across the pelvis: a single hip
			-- would let both legs hang from one point.
			if math.abs(a.ex - b.ex) > h * 0.10 then
				assert(math.abs(la.x - lb.x) > r * 0.04, "gait hips collapse to one socket")
				assert(la.x * a.ex > 0 and lb.x * b.ex > 0, "gait hip leaves its leg's side of the pelvis")
			end
			local planted = false
			for i, leg in p.legs do
				local L = leg.pose
				-- the gait's ground is its own bounce below the body (Movement.bob), not the authored bob
				assert(L.ey + p.bob >= -1e-8, "gait foot penetrates ground")
				-- one length through the whole stride: the knee folds, the leg's art never stretches
				-- by more than the 3% a walk's trailing toe-off reaches
				assert(len(leg) <= G.leg * 1.03 + 1e-9 and len(leg) >= G.leg - 1e-9, `gait leg is {len(leg)} long, not {G.leg}`)
				assert(kneeForward(leg) > -1e-6, "gait knee bends backwards")
				if math.abs(L.ey + p.bob) < 1e-8 then
					planted = true
					if last and math.abs(last.legs[i].pose.ey + last.bob) < 1e-8 then
						near(s.x + L.ex * facing, lastS.x + last.legs[i].pose.ex * facing, "support foot slides in world space")
					end
				end
			end
			if not planted then flight += 1 end
			if math.abs(a.ex - b.ex) < r * 0.12 then
				clearance = math.min(clearance, math.abs(a.ey - b.ey))
				assert(math.abs(a.ey - b.ey) > h * 0.075, "passing feet collide instead of clearing")
			end
			if p.bob < low[1] then low = { p.bob, x } end
			if p.bob > high[1] then high = { p.bob, x } end
			last, lastS = p, s
			samples += 1
		end
		-- A foot is flat on the ground for the first 60% of its planted step, then its heel peels
		-- up for the push-off; the rest of the step is the flight between steps.
		local flat = 1 - flight / 241
		assert(math.abs(flat - G.support * 0.6) < 0.03, `gait is flat-footed {flat} of the stride, not {G.support * 0.6}`)
		-- The bounce rides the step. A run is lowest while a foot is planted (the down) and highest
		-- with both feet off the ground; a walk rides highest over the planted leg (the passing).
		local q = function(x) return (x / G.step) % 1 end
		if ratio == 1 then
			assert(q(low[2]) < G.support and q(high[2]) > G.support, `a run's lowest point is at {q(low[2])} and highest at {q(high[2])} of the step`)
			-- (the authored run bob it replaces rose 0.14 studs, under a pixel at match scale)
			assert(high[1] - low[1] > h * 0.04, `a run bounces {high[1] - low[1]} studs`)
		elseif ratio <= 0.28 then
			assert(math.abs(q(high[2]) - G.support / 2) < 0.12 or math.abs(q(high[2]) - G.support / 2 - 1) < 0.12, `a walk's highest point is at {q(high[2])} of the step, not the passing`)
		end
	end
end

-- Timing in Channels still owns the weapon. Cosmetic torso counter-motion, however, must
-- follow distance just like the feet, rather than drifting through an unrelated lifetime loop.
do
	local a = state("run", 3, { x = h * 0.05, vx = char.runSpeed })
	local b = state("run", 31, { x = a.x, vx = a.vx })
	local raw = Channels.For(a, char, nil, 0)
	local pa = Posture.For(raw, a, char, { angle = 0 }, nil, 0)
	local pb = Posture.For(raw, b, char, { angle = 0 }, nil, 0)
	near(pa.hipRot, pb.hipRot, "hips use a different stride clock from the feet")
	near(pa.chestRot, pb.chestRot, "chest uses a different stride clock from the feet")
	b.x += G.step -- the next step
	local pc = Posture.For(raw, b, char, { angle = 0 }, nil, 0)
	assert(pa.hipRot * pc.hipRot < -0.001, "hips never exchange weight on the next step")
	assert((pc.chestRot + raw.lean) * pc.hipRot < -0.001, "chest fails to counter next step")
end

-- The keys. Contact: the step's first planted frame. The leading leg reaches forward, on the
-- ground and nearly straight, the trailing one already off it.
for _, ratio in { 0.28, 1 } do
	local p = sample(0, ratio, 1)
	local front, back = p.legs[1], p.legs[2]
	assert(front.pose.ex - front.x > h * 0.06 and math.abs(front.pose.ey + p.bob) < 1e-8, "contact: the leading foot does not reach forward onto the ground")
	assert(kneeForward(front) < h * 0.03, `contact: the leading leg is bent {kneeForward(front)}, not nearly straight`)
	assert(back.pose.ex < 0 and back.pose.ey + p.bob > h * 0.05, "contact: the trailing foot is not lifted behind")
	-- Passing: the planted foot under the hip, the swinging one lifted and folded past it.
	local pass = sample(G.step * G.support / 2, ratio, 1)
	local plant, swing = pass.legs[1], pass.legs[2]
	assert(math.abs(plant.pose.ex - plant.x) < h * 0.03 and math.abs(plant.pose.ey + pass.bob) < 1e-8, "passing: the planted foot is not under its hip")
	assert(swing.pose.ey - plant.pose.ey > h * 0.075, "passing: the swinging foot is not lifted")
	assert(kneeForward(swing) > h * 0.06 and swing.pose.jx > plant.pose.jx, "passing: the swinging knee is not folded forward past the planted leg")
	-- (a run's planted knee folds here too; that follows from the fixed leg and the run's bounce,
	-- both asserted above, so no separate check could fail on its own)
	if ratio <= 0.28 then
		assert(kneeForward(plant) < h * 0.025, `passing: a walk's planted leg is bent {kneeForward(plant)}, not carrying the body over it`)
	end
end
local function maxLift(ratio)
	local most = 0
	for j = 0, 60 do
		local p = sample(G.step * 2 * j / 60, ratio, 1)
		for _, leg in p.legs do most = math.max(most, leg.pose.ey + p.bob) end
	end
	return most
end
assert(maxLift(1) - maxLift(0.28) > h * 0.06, `walk and run have the same swing lift: {maxLift(1)} {maxLift(0.28)} h={h}`)
local stride = pose(state("run", 5, { x = h * 0.05, vx = char.runSpeed }))
assert((stride.back.ex - stride.backX) * stride.legs[1].pose.ex < -h * 0.05, "free arm does not oppose its leg")

-- Changing speed within a support step must not slide the foot. Sample in physical frame
-- increments as well as the dense geometric sweep above, through acceleration/deceleration.
for _, facing in { -1, 1 } do
	local x, last, prior = 0, nil, nil
	for frame = 0, 100 do
		local vx = char.runSpeed * (0.15 + 0.85 * math.sin(frame / 100 * math.pi) ^ 2) * facing
		x += vx / 60
		local s = state("run", frame, { x = x, vx = vx, facing = facing })
		local p, raw = pose(s)
		for i, leg in p.legs do
			if prior and math.abs(leg.pose.ey + raw.bob) < 1e-8 and math.abs(last.p.legs[i].pose.ey + last.bob) < 1e-8 then
				near(x + leg.pose.ex * facing, prior.x + last.p.legs[i].pose.ex * facing, "changing speed slides support foot")
			end
		end
		last, prior = { p = p, bob = raw.bob }, s
	end
end

-- These states already carry meaningful authored actions. New movement must not replace
-- their feet, root rotation or arm reach, nor mutate the shared channel bag.
for _, name in { "dash", "attack", "grab", "holding", "grabbed", "flung", "breakout", "stunned", "helpless", "recovery", "respawn" } do
	local s = state(name, 5)
	local raw = Channels.For(s, char, nil, 0)
	table.freeze(raw); table.freeze(s)
	local m = Movement.For(raw, s, char)
	assert(m.feet == nil and m.rigRotZ == nil and m.yOff == nil and m.back == nil, "movement overwrote authored action: " .. name)
end

for _, name in { "jumpsquat", "landing", "shield", "spotdodge" } do
	local initial
	for frame = 0, 10 do
		local p, raw = pose(state(name, frame))
		for i, leg in p.legs do
			near(leg.pose.ey + raw.bob, 0, name .. " planted foot leaves floor")
			if initial then near(leg.pose.ex, initial.legs[i].pose.ex, name .. " planted foot shifts sideways") end
		end
		initial = p
	end
end
local load = pose(state("jumpsquat", 3))
local land = pose(state("landing", 0))
local settled = pose(state("landing", 10))
assert(load.headY < settled.headY - h * 0.05, "jump never loads")
assert(land.headY < settled.headY - h * 0.05, "landing never compresses and settles")
local rise = pose(state("air", 3, { vy = 32 }))
local apex = pose(state("air", 12, { vy = 0 }))
local fall = pose(state("air", 20, { vy = -24 }))
local fast = pose(state("air", 20, { vy = -55, fastFalling = true }))
assert(rise.legs[2].pose.ey - rise.legs[1].pose.ey > h * 0.15 and rise.legs[1].pose.ex < -h * 0.15, "rise has no trailing leg")
assert(math.min(apex.legs[1].pose.ey, apex.legs[2].pose.ey) > h * 0.10, "apex never gathers the feet")
assert(fall.legs[1].pose.ey < apex.legs[1].pose.ey - h * 0.09, "fall does not reach for ground")
assert(fast.legs[2].pose.ex - fast.legs[1].pose.ex < (fall.legs[2].pose.ex - fall.legs[1].pose.ex) * 0.8 and fast.chestRot < fall.chestRot - 0.1, "fast fall does not commit")
local guard = pose(state("shield", 4))
assert(guard.back.ex - guard.backX > h * 0.22 and guard.chestRot < -0.1, "shield has no brace")
local dodge = pose(state("spotdodge", 5))
assert(dodge.hipY < h * 0.31, "spot dodge does not duck")
for _, facing in { -1, 1 } do
	local left = pose(state("hitstun", 1, { vx = -25, facing = facing }))
	local right = pose(state("hitstun", 1, { vx = 25, facing = facing }))
	assert(left.hipX * facing < -h * 0.05 and right.hipX * facing > h * 0.05, "impact ignores launch direction or facing")
end
for _, s in { state("hitstun", 6, { tumbling = true, lastHitFrame = 0 }), state("airdodge", 6),
	state("tech", 6, { techRoll = 1 }), state("ledgeaction", 6, { ledgeAction = "roll" }) } do
	local p = pose(s)
	assert(p.legs[1].pose.ey >= h * 0.19 and p.legs[2].pose.ey >= h * 0.23, "rolling body fails to tuck")
	assert(p.backY - p.back.ey < h * 0.2, "rolling support arm stays splayed")
end
local down = pose(state("knockdown", 5))
local up = pose(state("knockdown", 26))
assert(math.abs(down.rigRotZ) > 1.3 and math.abs(up.rigRotZ) < 0.001 and up.yOff < 0.001, "knockdown never gets up within its existing duration")
for _, facing in { -1, 1 } do
	for frame = 0, 26 do
		local p, raw = pose(state("knockdown", frame, { facing = facing }))
		local cs, sn = math.cos(p.rigRotZ * facing), math.sin(p.rigRotZ * facing)
		for i, leg in p.legs do
			local x, y = leg.pose.ex, leg.pose.ey + raw.bob
			near(x * sn + y * cs + p.yOff, 0, "getup foot goes through floor")
			near(x * cs - y * sn, r * (if i == 1 then -0.65 else 0.65), "getup foot slides")
		end
	end
end
local ledge = pose(state("ledge", 8))
assert(ledge.back.ey - ledge.backY > h * 0.2 and ledge.legs[2].pose.ey > h * 0.15, "ledge loses overhead reach or climbing knee")
local climb = pose(state("ledgeaction", 3, { ledgeAction = "getup" }))
local atop = pose(state("ledgeaction", 24, { ledgeAction = "getup" }))
assert(climb.legs[2].pose.ey > h * 0.20 and atop.legs[2].pose.ey < 1e-8, "ledge getup never plants its climbing foot")
for _, action in { { "getup", 10 }, { "attack", 8 } } do
	local p, raw = pose(state("ledgeaction", action[2], { ledgeAction = action[1] }))
	for _, leg in p.legs do near(leg.pose.ey + raw.bob, 0, "ledge action feet miss platform arrival") end
end
print(string.format("PASS movement: %d gait samples, support world-lock, fixed-length legs with forward knees, contact and passing keys, a bounce on the step, minimum passing clearance %.3f studs; walk/run, load/rise/hang/fall/commit/settle, defence, directed impact, tuck, getup and ledge properties", samples, clearance))
