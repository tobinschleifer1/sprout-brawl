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
-- a run's stride is longer than a walk's (Movement.RUN_STEP): each speed has its own
local function gaitAt(ratio: number): any return Movement.gait(char, Movement.runOf({ vx = char.runSpeed * ratio }, char)) end
local GR = gaitAt(1)
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
		local Gs = gaitAt(ratio)
		for j = 0, 240 do
			local x = Gs.step * 2 * j / 240
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
		local q = function(x) return (x / Gs.step) % 1 end
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
	b.x += GR.step -- the next step
	local pc = Posture.For(raw, b, char, { angle = 0 }, nil, 0)
	assert(pa.hipRot * pc.hipRot < -0.001, "hips never exchange weight on the next step")
	-- (net of the lean: Channels' and the run's own, Posture.RUN_LEAN)
	assert((pc.chestRot + raw.lean + Posture.RUN_LEAN * Movement.runOf(b, char)) * pc.hipRot < -0.001, "chest fails to counter next step")
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
	local pass = sample(gaitAt(ratio).step * G.support / 2, ratio, 1)
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
-- The arms counter-swing their own side's leg, both on the feet's clock (the owner, 2026-11-08: the
-- far arm swung by the frame count, out of step, and was never forward as the near leg reached
-- forward). Empty-handed, through a stride: the far (front) hand leads as the near foot leads, the
-- near (rear) hand as the far foot does. The frame is held still while the distance runs, so an arm
-- on the frame count's clock does not swing here at all.
do
	local bare = table.clone(char)
	bare.weapon = nil
	local function at(x: number, frame: number): any
		local f = Fighter.new({ index = 0, char = bare, x = 0, y = 0, stocks = 3 })
		f.state, f.sf, f.frameCount, f.invincible, f.facing, f.onGround = "run", frame, frame, 0, 1, true
		local st = Snapshot.decode(Snapshot.encode(f))
		st.x, st.vx = x, bare.runSpeed
		local ch = Channels.For(st, bare, nil, frame / 60)
		return Posture.For(ch, st, bare, WeaponPose.For(st, bare, nil, frame / 60), nil, frame / 60)
	end
	local function corr(a: { number }, b: { number }): number
		local ma, mb = 0, 0
		for k = 1, #a do ma += a[k] / #a; mb += b[k] / #b end
		local sab, saa, sbb = 0, 0, 0
		for k = 1, #a do sab += (a[k] - ma) * (b[k] - mb); saa += (a[k] - ma) ^ 2; sbb += (b[k] - mb) ^ 2 end
		return sab / math.sqrt(saa * sbb)
	end
	local lead, far, nearHand = {}, {}, {}
	for k = 0, 31 do
		local p = at(k / 32 * 2 * GR.step, 7)
		table.insert(lead, p.legs[1].pose.ex - p.legs[2].pose.ex)
		table.insert(far, p.front.ex - p.frontX)
		table.insert(nearHand, p.back.ex - p.backX)
	end
	local cf, cb = corr(lead, far), corr(lead, nearHand)
	assert(cf > 0.9, `the far arm does not lead as the near leg leads (correlation {cf})`)
	assert(cb < -0.9, `the near arm does not swing back as the near leg leads (correlation {cb})`)
	local lo, hi = math.huge, -math.huge
	for _, v in far do lo = math.min(lo, v); hi = math.max(hi, v) end
	assert(hi - lo > r * 0.8, `the far arm hardly swings ({hi - lo} studs)`)
	-- At the front of its swing an arm's shoulder comes forward and down (the owner posed it: it read
	-- too high), the whole arm with it, hand and all; swung back, it is where it always was.
	local function shift(k: number): (any, any)
		local x = k / 32 * 2 * GR.step
		local ahead, drop = Posture.SWING_AHEAD, Posture.SWING_DROP
		Posture.SWING_AHEAD, Posture.SWING_DROP = 0, 0
		local still = at(x, 7)
		Posture.SWING_AHEAD, Posture.SWING_DROP = ahead, drop
		return still, at(x, 7)
	end
	local function extreme(list: { number }, sign: number): number
		local best = 1
		for k = 1, #list do if list[k] * sign > list[best] * sign then best = k end end
		return best - 1
	end
	for _, arm in { { "front", far }, { "back", nearHand } } do
		local name, list = arm[1], arm[2]
		local still, moved = shift(extreme(list, 1))
		local dx, dy = moved[name .. "X"] - still[name .. "X"], moved[name .. "Y"] - still[name .. "Y"]
		assert(dx > h * 0.02 and -dy > h * 0.025, `the {name} shoulder swung forward moved only ({dx}, {dy})`)
		local L, S = moved[name], still[name]
		assert(math.abs((L.ex - S.ex) - dx) < 1e-9 and math.abs((L.ey - S.ey) - dy) < 1e-9, `the {name} hand stayed while its shoulder moved`)
		still, moved = shift(extreme(list, -1))
		assert(moved[name .. "X"] == still[name .. "X"] and moved[name .. "Y"] == still[name .. "Y"], `the {name} shoulder moved swung back`)
	end
end
-- The run's shape, posed by the owner (2026-11-08): the swinging leg straightens before it lands -
-- over the last fifth of its swing it is never folded below 85% of its length (it was 81%).
do
	local bare = table.clone(char)
	bare.weapon = nil
	local fold = math.huge
	for k = 0, 199 do
		local d = k / 200 * 2 * GR.step
		local f = Fighter.new({ index = 0, char = bare, x = 0, y = 0, stocks = 3 })
		f.state, f.sf, f.frameCount, f.invincible, f.facing, f.onGround = "run", 7, 7, 0, 1, true
		local st = Snapshot.decode(Snapshot.encode(f))
		st.x, st.vx = d, bare.runSpeed
		local ch = Channels.For(st, bare, nil, 7 / 60)
		local u = ((d / GR.step) % 2 - G.support) / (2 - G.support)
		if u >= 0.8 then
			local L = Posture.For(ch, st, bare, WeaponPose.For(st, bare, nil, 7 / 60), nil, 7 / 60).legs[1]
			local P = L.pose
			local reach = math.sqrt((P.ex - L.x) ^ 2 + (P.ey - L.y) ^ 2)
			local full = math.sqrt((P.jx - L.x) ^ 2 + (P.jy - L.y) ^ 2) + math.sqrt((P.ex - P.jx) ^ 2 + (P.ey - P.jy) ^ 2)
			fold = math.min(fold, reach / full)
		end
	end
	assert(fold >= 0.85, `late in its swing the running leg is still folded to {fold} of its length`)
	-- Williams' run (the owner's reference): the pushing leg straightens fully at the up (toe-off),
	-- the landing leg is nearly straight at contact, and the down takes the weight on a bent knee.
	local function knee(d: number, i: number): number
		local f = Fighter.new({ index = 0, char = bare, x = 0, y = 0, stocks = 3 })
		f.state, f.sf, f.frameCount, f.invincible, f.facing, f.onGround = "run", 7, 7, 0, 1, true
		local st = Snapshot.decode(Snapshot.encode(f))
		st.x, st.vx = d, bare.runSpeed
		local ch = Channels.For(st, bare, nil, 7 / 60)
		local L = Posture.For(ch, st, bare, WeaponPose.For(st, bare, nil, 7 / 60), nil, 7 / 60).legs[i]
		local P = L.pose
		local reach = math.sqrt((P.ex - L.x) ^ 2 + (P.ey - L.y) ^ 2)
		local full = math.sqrt((P.jx - L.x) ^ 2 + (P.jy - L.y) ^ 2) + math.sqrt((P.ex - P.jx) ^ 2 + (P.ey - P.jy) ^ 2)
		return math.deg(2 * math.acos(math.min(1, reach / full)))
	end
	for i = 1, 2 do
		local start = (i - 1) * GR.step -- (leg i's contact)
		local up, contact, down = knee(start + G.support * GR.step, i), knee(start, i), knee(start + 0.18 * GR.step, i)
		assert(up < 5, `leg {i} pushes off with its knee bent {up} degrees, not straight`)
		assert(contact < 30, `leg {i} lands with its knee bent {contact} degrees`)
		assert(down > 40 and down < 70, `leg {i} takes the down on a {down}-degree knee`)
	end
	-- Williams' swing (the owner's reference, 2026-11-11): as the other foot lands, the heel is kicked
	-- up high behind - over half a leg off the ground, well behind its hip - and through the down it
	-- is still behind, folded; it comes through after that. (The old swing was under the hip by the
	-- down.) And the whole trunk leans into it, hip to neck.
	local function leaning(q: number): any
		local f = Fighter.new({ index = 0, char = bare, x = 0, y = 0, stocks = 3 })
		f.state, f.sf, f.frameCount, f.invincible, f.facing, f.onGround = "run", 7, 7, 0, 1, true
		local st = Snapshot.decode(Snapshot.encode(f))
		st.x, st.vx, st.stridePhase = 0, bare.runSpeed, q
		return Posture.For(Channels.For(st, bare, nil, 7 / 60), st, bare, WeaponPose.For(st, bare, nil, 7 / 60), nil, 7 / 60)
	end
	for i = 1, 2 do
		local land, down = leaning(i % 2), leaning(i % 2 + 0.18) -- (the other leg's contact, and its down)
		local L, D = land.legs[i], down.legs[i]
		assert(L.pose.ey + land.bob > G.leg * 0.55 and L.pose.ex - L.x < -G.leg * 0.4,
			`as the other foot lands, foot {i} is {(L.pose.ey + land.bob) / G.leg} legs up and {(L.pose.ex - L.x) / G.leg} from its hip`)
		assert(D.pose.ex - D.x < -G.leg * 0.25, `through the down, foot {i} has come through to {(D.pose.ex - D.x) / G.leg} legs from its hip`)
	end
	for _, q in { 0, 0.18, 0.42, 0.62, 0.8 } do
		local p = leaning(q)
		local lean = math.deg(math.atan2(p.headX - p.hipX, p.headY - p.hipY))
		assert(lean > 16, `a run leans only {lean} degrees, hip to neck`)
	end
	-- Williams' arms (the owner's reference, 2026-11-11), measured on the drawn arm, both of them: as
	-- the foot on its own side lands, the upper arm is swung well back, nearly level behind the
	-- shoulder, the forearm hanging; as the other foot lands it is forward, the elbow bent past a
	-- right angle and the fist up in front of it. Bent, an arm keeps its length: its hand comes in.
	local function arms(q: number): any
		local f = Fighter.new({ index = 0, char = bare, x = 0, y = 0, stocks = 3 })
		f.state, f.sf, f.frameCount, f.invincible, f.facing, f.onGround = "run", 7, 7, 0, 1, true
		local st = Snapshot.decode(Snapshot.encode(f))
		st.x, st.vx, st.stridePhase = 0, bare.runSpeed, q
		local p = Posture.For(Channels.For(st, bare, nil, 7 / 60), st, bare, WeaponPose.For(st, bare, nil, 7 / 60), nil, 7 / 60)
		local out = {}
		for _, side in { { "back", 1 }, { "front", 2 } } do
			local sx, sy, L = p[side[1] .. "X"], p[side[1] .. "Y"], p[side[1]]
			local ux, uy, fx, fy = L.jx - sx, L.jy - sy, L.ex - L.jx, L.ey - L.jy
			local upper, fore = math.sqrt(ux * ux + uy * uy), math.sqrt(fx * fx + fy * fy)
			assert(math.abs(upper - h * 0.15) < 1e-6 and math.abs(fore - h * 0.15) < 1e-6,
				`the running {side[1]} arm is {upper} and {fore} long, not {h * 0.15} each`)
			out[side[2]] = {
				upper = math.deg(math.atan2(ux, -uy)), -- from straight down, forward positive
				bend = math.deg(math.acos(math.clamp((ux * fx + uy * fy) / (upper * fore), -1, 1))),
				up = L.ey - L.jy, ahead = L.ex - L.jx,
			}
		end
		return out
	end
	for i = 1, 2 do
		-- (leg i lands at i - 1 steps; the other leg one step later)
		local back, fwd = arms(i - 1)[i], arms(i)[i]
		assert(back.upper < -60 and back.up < 0, `arm {i} is swung back only {back.upper} degrees as its foot lands`)
		assert(fwd.upper > -10 and fwd.bend > 90 and fwd.up > 0 and fwd.ahead > 0,
			`arm {i} is not forward with its fist up as the other foot lands ({fwd.upper} degrees, bent {fwd.bend})`)
	end
end
-- Speeding up far from the stage's middle: the run's step grows with speed, so steps counted as
-- distance over the step of the moment would spin the feet through the cycle (40 studs out, a few
-- steps' worth in a frame). Accumulated (Movement.advance) the planted foot holds and no foot jumps.
do
	local bare = table.clone(char)
	bare.weapon = nil
	local key = {}
	local x, worst, lastFeet = 40, 0, nil
	for frame = 0, 90 do
		local vx = bare.runSpeed * math.min(1, 0.3 + frame / 60)
		x += vx / 60
		local f = Fighter.new({ index = 0, char = bare, x = 0, y = 0, stocks = 3 })
		f.state, f.sf, f.frameCount, f.invincible, f.facing, f.onGround = "run", frame, frame, 0, 1, true
		local st = Snapshot.decode(Snapshot.encode(f))
		st.x, st.vx = x, vx
		st.stridePhase = Movement.advance(key, st.x, st.facing, st, bare)
		local p = Posture.For(Channels.For(st, bare, nil, frame / 60), st, bare, WeaponPose.For(st, bare, nil, frame / 60), nil, frame / 60)
		local feet = { x + p.legs[1].pose.ex, x + p.legs[2].pose.ex }
		if lastFeet then
			for k = 1, 2 do worst = math.max(worst, math.abs(feet[k] - lastFeet[k])) end
		end
		lastFeet = feet
	end
	assert(worst < h * 0.2, `speeding up, a foot jumped {worst} studs in a frame`)
end
-- The push-off foot is on the ground (the owner, 2026-11-11: at the up it floated about a third of a
-- stud). Through a run's planted step the foot is drawn where the gait plants it - Posture never has
-- to lift it to meet a leg too short to reach - and as it leaves the ground its shoe is drawn as low
-- as it was when it landed. The shoe is the shin's art, hanging past the leg's end and turning with
-- it, so the sole is measured off the drawn sprite.
do
	local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
	local Fighter2D = Loader.loadFrom("src/client/", "Fighter2D")
	local bare = table.clone(char)
	bare.weapon = nil
	local function posed(q: number, ratio: number): any
		local f = Fighter.new({ index = 0, char = bare, x = 0, y = 0, stocks = 3 })
		f.state, f.sf, f.frameCount, f.invincible, f.facing, f.onGround = "run", 7, 7, 0, 1, true
		local st = Snapshot.decode(Snapshot.encode(f))
		st.x, st.vx, st.stridePhase = 0, bare.runSpeed * ratio, q
		return st
	end
	for _, ratio in { 0.6, 0.8, 1 } do
		local DP = Movement.gait(bare, Movement.runOf({ vx = bare.runSpeed * ratio }, bare)).support
		for k = 0, 199 do
			local q = k / 100
			local st = posed(q, ratio)
			local ch = Channels.For(st, bare, nil, 7 / 60)
			local m = Movement.For(ch, st, bare)
			local p = Posture.For(ch, st, bare, WeaponPose.For(st, bare, nil, 7 / 60), nil, 7 / 60)
			for i = 1, 2 do
				if (q + i - 1) % 2 < DP then
					local lift = p.legs[i].pose.ey - m.feet[i].y
					assert(lift < 1e-9, `running at {ratio} of full speed, planted foot {i} is lifted {lift} studs off the ground to meet its leg`)
				end
			end
		end
	end
	-- the lowest opaque point of each drawn shin, in studs: { near leg (1), far leg (2) }
	local PPU = 40
	local function soles(st: any): { number }
		local found = {}
		local kept = {}
		for _, k in { "sprite", "rect", "ellipse", "circle", "tri", "line" } do kept[k] = Canvas[k]; Canvas[k] = function() end end
		Canvas.sprite = function(c, key, rects, x0, y1, pw, ph)
			if string.match(key, "|(%a+)|") ~= "shin" then return end
			local M, low = c.m, math.huge
			Canvas.eachSpriteRect(rects, x0, y1, pw, ph, function(x, y, w, hh, _, a)
				if a < 0.5 then return end
				for _, pt in { { x, y }, { x + w, y }, { x, y + hh }, { x + w, y + hh } } do
					low = math.min(low, -(M.b * pt[1] + M.d * pt[2] + M.f) / PPU)
				end
			end)
			table.insert(found, 1, low) -- (the far leg is drawn first)
		end
		local c = setmetatable({ used = 0, stack = {}, alpha = 1, alphaStack = {}, m = { a = PPU, b = 0, c = 0, d = -PPU, e = 0, f = 0 },
			gui = { AbsoluteSize = { X = 400, Y = 400 } }, finish = function() end }, { __index = Canvas })
		Fighter2D.draw(c, st, bare, 10, 0)
		for k, v in kept do Canvas[k] = v end
		assert(#found == 2, `{#found} shins drawn`)
		return found
	end
	local DP = GR.support
	for i = 1, 2 do
		local landed = soles(posed(i - 1, 1))[i]
		local leaving = soles(posed(i - 1 + DP - 1e-3, 1))[i]
		-- (0.04 studs: under a pixel and a half even this close)
		assert(leaving <= landed + 0.04, `foot {i} pushes off with its shoe {leaving - landed} studs higher than it landed`)
	end
end
print(string.format("PASS movement: %d gait samples, support world-lock, fixed-length legs with forward knees, contact and passing keys, a bounce on the step, minimum passing clearance %.3f studs; walk/run, load/rise/hang/fall/commit/settle, defence, directed impact, tuck, getup and ledge properties; the stride holds through speeding up; both arms counter-swing their legs on the stride", samples, clearance))
