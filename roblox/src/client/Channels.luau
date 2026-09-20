--!strict
-- Animation channels: the pose of a fighter for one frame, as plain numbers.
--
-- A port of web/src/render2d/channels.js, held to it by tests/channel-parity.luau. Nothing here
-- touches a canvas: it reads a decoded snapshot and returns a channel bag that Fighter2D paints
-- however it likes.
--
-- The five principles the JavaScript is built on carry over unchanged - anticipation, slow in/slow
-- out, follow through, overlapping action, moving hold - and so does the reason they matter: there
-- are no sprite sheets here, so what makes an attack readable is TIMING, not artwork.
--
-- WHAT THIS READS. Every field comes from Snapshot.decode plus `char` and `move`, both of which the
-- client already has - `move` is looked up from moveId in the generated weapon data rather than
-- sent, because it is static. The JavaScript's `f.sf`/`f.mf` are `stateFrame`/`moveFrame` here:
-- past decode nothing in the client knows the wire's spelling.
--
-- Channels:
--   lean      body tilt, radians, positive = leaning into the attack
--   bob/yOff  vertical offsets in studs
--   sx/sy     squash and stretch
--   armL/armR shoulder rotation, z = swing in the side-on plane, x = swing across it
--   legL/legR hip rotation
--   spinZ     rotation in the screen plane; folded into rigRotZ at the bottom
--   spinY     rotation about the fighter's own vertical axis, rendered as an sx squeeze
--   smear     0-1; how much motion streak the painter should add this frame
--   tint      an emissive flash colour as a hex string, or nil

local Channels = {}

local PI = math.pi
local F = PI / 2                        -- arm straight forward

local function clamp(v: number, lo: number, hi: number): number
	return if v < lo then lo elseif v > hi then hi else v
end

-- ---------------------------------------------------------------- easing ----
-- Fast away from rest, settling in. Wind-ups use this.
local function easeOut(k: number): number
	return 1 - (1 - k) * (1 - k)
end
-- Slow away from rest, fastest at the end. Strikes use this, so the quickest frames of the whole
-- move are the ones where the hitbox is live.
local function easeIn(k: number): number
	return k * k * k
end
local function easeInOut(k: number): number
	return if k < 0.5 then 4 * k * k * k else 1 - ((-2 * k + 2) ^ 3) / 2
end
-- Overshoot past the target and come back. Anticipation uses this: the cock goes a little too far
-- and rebounds, which is what makes a wind-up read as loaded rather than as a position.
local function back(k: number, amt: number?): number
	local a = amt or 1.7
	local c = k - 1
	return 1 + (a + 1) * c * c * c + a * c * c
end
-- A damped spring, for settles. `d` is how fast it dies; higher settles quicker.
local function settle(k: number, freq: number?, d: number?): number
	local fr, dd = freq or 3.2, d or 5
	return if k >= 1 then 1 else 1 - math.cos(k * fr * PI) * math.exp(-dd * k)
end

-- weapons2d.js imports easeOut, easeIn and swing from channels.js, so the weapon and the body are
-- eased by one shared set of curves. Exported here for the same reason: the moment they are two
-- copies, a tweak to one puts the prop and the fighter out of phase.
Channels.easeOut = easeOut
Channels.easeIn = easeIn

-- ---------------------------------------------------------------- phase ----
-- Where a move is, with all the easing already applied. Every attack reads from this rather than
-- working out its own phase, so timing is consistent across the whole moveset.
function Channels.swing(f: any, m: any): any
	local st, act, rec, mf = f.startupEff, m.active, m.recovery, f.moveFrame
	if mf <= st then
		local k = if st ~= 0 then mf / st else 1
		-- The wind-up spends its last third loaded and trembling rather than still arriving.
		return { phase = "wind", k = k, e = back(easeOut(k), 1.1), hold = k > 0.68, smear = 0 }
	end
	if mf <= st + act then
		local k = if act ~= 0 then (mf - st) / act else 1
		-- The strike itself: the first two frames cover most of the distance, then a moving hold.
		local snap = clamp(k * 3.2, 0, 1)
		return { phase = "strike", k = k, e = easeIn(snap), hold = false, smear = 1 - clamp(k, 0, 1) }
	end
	local k = if rec ~= 0 then (mf - st - act) / rec else 1
	local e = 1 - settle(k, if m.heavy then 2.6 else 3.4, if m.heavy then 3.4 else 6)
	return { phase = "settle", k = k, e = e, hold = false, smear = 0 }
end

-- Overlapping action: re-evaluate the swing a few FRAMES earlier and use that value. Subtracting a
-- constant from the eased value instead is an amplitude offset rather than a delay, and because the
-- master curve reaches 1.0 within a frame or two and then holds, the trailing limbs would spend the
-- whole move at a fixed offset and never actually lag.
local function lagged(f: any, m: any, frames: number): number
	if f.moveFrame <= frames then
		return if f.moveFrame <= f.startupEff then 0 else 1
	end
	local shadow = { moveFrame = f.moveFrame - frames, startupEff = f.startupEff, move = m }
	local s2 = Channels.swing(shadow, m)
	return if s2.phase == "wind" then -s2.e else s2.e
end

-- Which ordinary categories a thrusting weapon replaces. Rising attacks stay rotational: you cannot
-- thrust upward off a line that runs forward, and the pike's up-angled moves genuinely are swings
-- of the point.
local THRUSTABLE: { [string]: string } = {
	jab = "thrust", side = "thrust", fair = "thrust", sigside = "thrust",
	down = "thrustlow", sigdown = "thrustlow", dair = "thrustlow",
}

-- ------------------------------------------------------- the ultimate bodies -----
-- Each of these is written against the SAME phase boundaries weapons2d.js's ultimatePose uses, so
-- the fighter and the prop are performing one move rather than two.
local function ultChannels(ch: any, f: any, char: any, m: any, t: number)
	local wid = if char.weapon then char.weapon.id else nil
	local st, act, rec, mf = f.startupEff, m.active, m.recovery, f.moveFrame
	local wind = mf <= st
	local live = mf > st and mf <= st + act
	local k = if wind then mf / math.max(1, st) elseif live then (mf - st) / math.max(1, act) else 1
	local ak = mf - st                                        -- frame within the active window
	local out = math.min(1, (mf - st - act) / math.max(1, rec))  -- 0 -> 1 across recovery
	-- mf is never negative, so Lua's floored % and JavaScript's truncated % agree here.
	local function strain(a: number): number
		return if f.moveFrame % 2 ~= 0 then a else -a
	end

	if wid == "Sword" then
		-- COLOSSUS. Hoist a sword twice its own length overhead, hold it, and fall with it.
		local CHOP = 5
		local riseEnd = math.max(1, st - CHOP)
		if wind and mf <= riseEnd then
			local r = easeOut(mf / riseEnd)
			ch.armL.z = 0.6 + 2.4 * r; ch.armR.z = -0.6 - 2.3 * r
			ch.sy = 1 + 0.26 * r; ch.sx = 1 - 0.14 * r
			ch.bob = 0.55 * r; ch.head = -0.35 * r
			ch.legL = -0.35 * r; ch.legR = -0.28 * r
			ch.shakeX = strain(0.10 * r)                       -- the weight is already winning
		elseif wind then
			local c = easeIn((mf - riseEnd) / CHOP)            -- the drop: everything comes down at once
			ch.armL.z = 3.0 - 2.6 * c; ch.armR.z = -2.9 + 2.4 * c
			ch.sy = 1.26 - 0.5 * c; ch.sx = 0.86 + 0.38 * c
			ch.bob = 0.55 - 0.85 * c; ch.lean = 0.34 * c
			ch.legL = -0.35 + 0.9 * c; ch.legR = -0.28 - 0.5 * c
			ch.head = -0.35 + 0.7 * c
			ch.smear = c
		else
			-- planted: buried to the crossguard, braced against a floor that is coming apart
			local q = if live then 1 - math.min(1, ak / 8) else 0
			ch.sy = 0.78 + 0.2 * (1 - q); ch.sx = 1.22 - 0.18 * (1 - q)
			ch.lean = 0.32 - 0.14 * (1 - q); ch.bob = -0.3 + 0.2 * (1 - q)
			ch.armL.z = 0.4; ch.armR.z = -0.5; ch.legL = 0.55; ch.legR = -0.78
			ch.head = 0.35
			if live then ch.shakeX = strain(0.16 * (1 - ak / math.max(1, act))) end
		end
	elseif wid == "Scythe" then
		-- SOUL TETHER. The pull is isometric: nothing moves fast, everything strains.
		local hold = if m.vortex and m.vortex.holdFrames and m.vortex.holdFrames ~= 0
			then m.vortex.holdFrames else 22
		if wind then
			local r = easeOut(k)
			ch.armR.z = -1.5 * r; ch.armL.z = 0.4 + 1.5 * r
			ch.lean = -0.55 * r; ch.sx = 1 - 0.12 * r; ch.sy = 1 + 0.1 * r
			ch.legL = 0.4 * r; ch.legR = -0.35 * r; ch.head = -0.25 * r
		elseif live and ak <= hold then
			local h = ak / hold
			local reach = math.min(1, ak / 5)
			-- reaching hand out, body hauling BACKWARDS against it - the ball is being dragged in
			ch.armR.z = -1.5 + (F + 0.35 + 1.5) * easeOut(reach)
			ch.armL.z = 1.9 - 0.5 * reach
			ch.lean = -0.55 + 0.75 * easeOut(reach) - 0.35 * h
			ch.legR = 0.6 * reach - 0.5 * h; ch.legL = -0.45 * reach + 0.4 * h
			ch.sx = 1 + 0.08 * math.sin(h * PI); ch.sy = 1 - 0.06 * math.sin(h * PI)
			ch.head = -0.2 * h
			ch.shakeX = strain(0.06 + 0.14 * h)                -- grip failing as the ball tightens
			ch.bob = -0.18 * h
		else
			local since = if live then ak - hold else (act - hold) + (mf - st - act)
			local c = easeIn(math.min(1, since / 8))
			ch.armR.z = (F + 0.35) - 2.5 * c; ch.armL.z = 1.4 - 1.0 * c
			ch.lean = 0.16 + 0.26 * c; ch.sy = 1 - 0.3 * c; ch.sx = 1 + 0.24 * c
			ch.legR = 0.9 * c; ch.legL = -0.6 * c; ch.bob = -0.35 * c
			ch.smear = math.max(0, 1 - since / 6)
		end
	elseif wid == "Blasters" then
		-- DEADEYE. A rifle stance: square, still, and every shot is felt through the shoulder.
		local reload = if m.sniper and m.sniper.reload and m.sniper.reload ~= 0 then m.sniper.reload else 16
		if wind then
			local r = easeOut(k)
			ch.armR.z = -0.6 + (F + 0.6) * r; ch.armL.z = -0.3 + 0.9 * r   -- support hand comes up
			ch.lean = 0.18 * r; ch.sx = 1 - 0.08 * r; ch.sy = 1 + 0.04 * r
			ch.legL = -0.3 * r; ch.legR = 0.45 * r; ch.head = -0.15 * r
		elseif live then
			local since = if f.ultCooldown > 0 then reload - f.ultCooldown else 99
			local kick = if since < 7 then (1 - since / 7) * (1 - since / 7) else 0
			ch.armR.z = F; ch.armL.z = 0.6
			ch.lean = 0.18 - 0.42 * kick                        -- driven back into the shoulder
			ch.sx = 1 - 0.08 + 0.1 * kick; ch.sy = 1 + 0.04 - 0.06 * kick
			ch.legL = -0.3 - 0.25 * kick; ch.legR = 0.45 + 0.3 * kick
			ch.head = -0.15 - 0.2 * kick
			ch.shakeX = strain(0.18 * kick)
			ch.smear = kick * 0.6
			ch.bob = math.sin(t * 2.2) * 0.06                   -- breathing on the scope between shots
		else
			ch.armR.z = F * (1 - out); ch.armL.z = 0.6 * (1 - out); ch.legR = 0.45 * (1 - out)
		end
	elseif wid == "Axe" then
		-- REAVE. The fighter stops fighting the weight and goes with it: three revolutions, the body
		-- turning with the head and leaning out against the pull the whole way.
		if wind then
			local r = easeOut(k)
			ch.armR.z = -1.7 * r; ch.armL.z = 0.4 + 1.2 * r
			ch.lean = -0.5 * r                                  -- wound all the way back and low
			ch.sy = 1 - 0.2 * r; ch.sx = 1 + 0.16 * r
			ch.legL = 0.55 * r; ch.legR = -0.5 * r; ch.bob = -0.4 * r; ch.head = -0.3 * r
			ch.shakeX = strain(0.12 * r)
		elseif live then
			local p = ak / math.max(1, act)
			-- spinY, NOT spinZ: spinZ is rotation in the SCREEN plane, which draws the fighter
			-- cartwheeling. A fighter turning with a swing rotates about their own vertical axis.
			ch.spinY = (p ^ 1.15) * PI * 6.0
			ch.lean = 0.20 + 0.12 * p                           -- leaning out against the swing
			ch.armR.z = -0.3; ch.armL.z = -0.25                 -- both arms locked to the haft
			ch.sx = 1 + 0.14 * p; ch.sy = 1 - 0.1 * p
			ch.legL = 0.3; ch.legR = -0.3
			ch.smear = 0.5 + 0.5 * p
			ch.bob = -0.2 - 0.2 * p
		else
			-- the release: dizzy, over-rotated, hauling itself back upright
			ch.lean = 0.34 * (1 - out); ch.sx = 1 + 0.14 * (1 - out)
			ch.armL.z = 1.1 * (1 - out); ch.armR.z = -0.9 * (1 - out)
			ch.head = 0.3 * (1 - out) * math.cos(out * PI * 2)
			ch.bob = -0.4 * (1 - out)
		end
	elseif wid == "Pike" then
		-- LANCE CHARGE. Couched: body low over the front knee, lance along the line, and every
		-- thrust is the whole fighter travelling forward rather than an arm moving.
		local FULLEXT = 1.75
		if wind then
			local r = easeOut(k)
			ch.armR.z = -0.6 + (F + 0.6) * r; ch.armR.ext = 1 - 0.28 * r   -- drawn all the way in
			ch.armL.z = 0.5 + 0.8 * r
			ch.lean = 0.10 + 0.18 * r; ch.sy = 1 - 0.16 * r; ch.sx = 1 + 0.1 * r
			ch.legR = -0.4 * r; ch.legL = 0.5 * r; ch.bob = -0.35 * r; ch.head = -0.1 * r
		elseif live then
			local per = act / 5
			local phase = (ak % per) / per
			local punch = if phase < 0.35 then easeIn(phase / 0.35) else 1 - (phase - 0.35) / 0.65
			local step = math.floor(ak / per) / 5               -- how far into the reach ramp
			ch.armR.z = F; ch.armR.ext = 1 - 0.28 + (FULLEXT - 0.72) * punch * (0.7 + 0.3 * step)
			ch.armL.z = 1.3 - 0.5 * punch
			ch.lean = 0.24 + 0.16 * punch
			ch.legR = 1.0 * punch - 0.4 * (1 - punch); ch.legL = -0.75 * punch + 0.5 * (1 - punch)
			ch.sx = 1 + 0.12 * punch; ch.sy = 1 - 0.16 - 0.05 * punch
			ch.bob = -0.35 - 0.15 * punch
			ch.head = -0.1 - 0.12 * punch
			ch.smear = if punch > 0.6 then punch else 0
		else
			ch.lean = 0.28 * (1 - out); ch.armR.z = F * (1 - out); ch.armR.ext = 1 + 0.5 * (1 - out)
			ch.bob = -0.35 * (1 - out); ch.sy = 1 - 0.16 * (1 - out)
		end
	elseif wid == "Gauntlets" then
		-- HUNDRED HANDS. No weapon, so the body IS the move: wound back, then a torso that never
		-- stops turning, then one straight right that puts everything behind it.
		if wind then
			local r = easeOut(k)
			ch.armR.z = -1.5 * r; ch.armL.z = 0.4 + 1.0 * r
			ch.lean = -0.4 * r; ch.legL = 0.4 * r; ch.legR = -0.35 * r
			ch.sx = 1 - 0.08 * r; ch.bob = -0.2 * r
		elseif live then
			local beat = math.sin(ak * 1.9)
			ch.armR.z = F + beat * 0.5; ch.armR.ext = 1 + 0.28 * math.abs(beat)
			ch.armL.z = -0.4 - beat * 0.5
			ch.lean = 0.2 + beat * 0.12
			ch.spinY = beat * 0.5
			ch.sx = 1 + 0.06 * math.abs(beat)
			ch.smear = 0.7
			ch.bob = -0.14
			if ak > act - 10 then
				local f2 = (ak - (act - 10)) / 10
				ch.armR.z = F; ch.armR.ext = 1 + 0.5 * f2; ch.lean = 0.42; ch.spinY = 0; ch.smear = 1
			end
		else
			ch.lean = 0.42 * (1 - out); ch.armR.z = F * (1 - out); ch.armR.ext = 1 + 0.4 * (1 - out)
		end
	elseif wid == "Hammer" then
		-- UPHEAVAL. The fighter stays down over a planted hammer, shuddering as each column goes up.
		local CHOP = 8
		local riseEnd = math.max(1, st - CHOP)
		if wind and mf <= riseEnd then
			local r = easeOut(mf / riseEnd)
			ch.armL.z = 0.6 + 2.4 * r; ch.armR.z = -0.6 - 2.3 * r
			ch.sy = 1 + 0.3 * r; ch.sx = 1 - 0.16 * r
			ch.bob = 0.7 * r; ch.head = -0.4 * r
			ch.legL = -0.4 * r; ch.legR = -0.32 * r
			ch.shakeX = strain(0.16 * r)
		elseif wind then
			local c = easeIn((mf - riseEnd) / CHOP)
			ch.armL.z = 3.0 - 2.7 * c; ch.armR.z = -2.9 + 2.5 * c
			ch.sy = 1.3 - 0.58 * c; ch.sx = 0.84 + 0.44 * c
			ch.bob = 0.7 - 1.05 * c; ch.lean = 0.34 * c
			ch.legL = -0.4 + 1.0 * c; ch.legR = -0.32 - 0.55 * c
			ch.head = -0.4 + 0.8 * c
			ch.smear = c
		elseif live then
			local U = m.upheaval
			local beat = if U then 1 - (ak % U.every) / U.every else 0
			ch.sy = 0.78 - 0.04 * beat; ch.sx = 1.24 + 0.04 * beat
			ch.lean = 0.3; ch.bob = -0.34
			ch.armL.z = 0.4; ch.armR.z = -0.5; ch.legL = 0.6; ch.legR = -0.8; ch.head = 0.36
			ch.shakeX = strain(0.06 + 0.2 * beat)               -- the floor kicking, once per column
		else
			ch.lean = 0.3 * (1 - out); ch.sy = 1 - 0.22 * (1 - out); ch.sx = 1 + 0.24 * (1 - out)
			ch.bob = -0.34 * (1 - out); ch.legL = 0.6 * (1 - out); ch.legR = -0.8 * (1 - out)
		end
	elseif wid == "Longbow" then
		-- HEARTSEEKER. The draw is the move, and the release is two frames of everything letting go.
		if wind then
			local r = easeOut(k)
			ch.armR.z = -0.5 + (F + 0.5) * r; ch.armR.ext = 1 + 0.18 * r   -- bow arm out and locked
			ch.armL.z = -0.2 - 1.0 * r                                      -- string hand back
			ch.lean = -0.12 * r; ch.head = -0.16 * r
			ch.sx = 1 - 0.06 * r; ch.sy = 1 + 0.04 * r
			ch.legL = -0.3 * r; ch.legR = 0.35 * r
			ch.bob = -0.1 * r
			ch.shakeX = strain(0.04 + 0.12 * r * r)      -- draw weight, rising the longer it is held
		elseif live then
			local kk = math.min(1, ak / 5)
			ch.armR.z = F + 0.5; ch.armR.ext = 1 + 0.18 + 0.12 * (1 - kk)
			ch.armL.z = -1.2 + 1.6 * kk                                     -- the string hand snaps open
			ch.lean = -0.12 + 0.2 * kk
			ch.sx = 0.94 + 0.16 * kk; ch.sy = 1.04 - 0.1 * kk
			ch.legL = -0.3; ch.legR = 0.35
			ch.smear = 1 - kk
			ch.head = -0.16 + 0.1 * kk
		else
			ch.armR.z = (F + 0.5) * (1 - out); ch.armL.z = 0.4 * (1 - out)
			ch.lean = 0.08 * (1 - out); ch.legR = 0.35 * (1 - out)
		end
	elseif wid == "Flail" then
		-- ANCHOR. A wind-up, a throw, and then the fighter is simply WALKING with a rope in their
		-- hands - braced, leaning against the pull, free to move.
		if wind then
			local r = easeOut(k)
			ch.armR.z = -1.8 * r; ch.armL.z = 0.4 + 1.3 * r
			ch.lean = -0.5 * r; ch.sy = 1 - 0.18 * r; ch.sx = 1 + 0.14 * r
			ch.legL = 0.5 * r; ch.legR = -0.45 * r; ch.bob = -0.35 * r; ch.head = -0.28 * r
			ch.shakeX = strain(0.12 * r)
		elseif live then
			local thrown = math.min(1, ak / 6)
			-- the throw
			ch.armR.z = -1.8 + (F + 2.1) * easeIn(thrown)
			ch.armL.z = 1.7 - 1.3 * thrown
			ch.lean = -0.5 + 0.78 * thrown
			ch.smear = 1 - thrown
			-- and then the haul: both hands on the chain, weight back, and it breathes
			if thrown >= 1 then
				ch.armR.z = F - 0.25 + math.sin(t * 2.4) * 0.06
				ch.armL.z = F - 0.75 + math.sin(t * 2.4 + 0.6) * 0.06
				ch.lean = 0.28
				ch.legR = 0.55; ch.legL = -0.4
				ch.sx = 1.06; ch.sy = 0.97
				ch.bob = -0.18 + math.sin(t * 2.2) * 0.05
				ch.head = 0.12
				ch.shakeX = strain(0.05)
			end
		else
			ch.lean = 0.28 * (1 - out); ch.armR.z = (F - 0.25) * (1 - out); ch.armL.z = (F - 0.75) * (1 - out)
			ch.legR = 0.55 * (1 - out); ch.bob = -0.18 * (1 - out)
		end
	elseif wid == "Shield" then
		-- LAST STAND. The only ultimate whose performance is holding still.
		if wind then
			local r = easeOut(k)
			ch.armL.z = 0.4 + 1.1 * r; ch.armR.z = -0.4 - 0.6 * r
			ch.lean = 0.26 * r; ch.sy = 1 - 0.14 * r; ch.sx = 1 + 0.12 * r
			ch.legR = 0.7 * r; ch.legL = -0.5 * r; ch.bob = -0.24 * r; ch.head = 0.2 * r
		elseif live then
			local rel = if ak > act - 12 then (ak - (act - 12)) / 12 else 0
			ch.armL.z = 1.5; ch.armR.z = -1.0
			ch.lean = 0.26 - 0.1 * rel
			ch.sy = 0.86 - 0.06 * (1 - rel) + 0.34 * rel
			ch.sx = 1.12 + 0.06 * (1 - rel) - 0.2 * rel
			ch.legR = 0.7; ch.legL = -0.5; ch.head = 0.2
			ch.bob = -0.24 + 0.3 * rel
			ch.shakeX = strain(0.06 + 0.1 * math.sin(ak * 0.5))
			ch.smear = rel
		else
			ch.lean = 0.2 * (1 - out); ch.armL.z = 1.5 * (1 - out); ch.armR.z = -1.0 * (1 - out)
			ch.sy = 1 + 0.18 * (1 - out); ch.bob = 0.06 * (1 - out)
		end
	elseif wid == "Daggers" then
		-- THOUSAND CUTS. The flicker is deliberate: it alternates between two poses rather than
		-- easing between them, because easing reads as one fighter moving quickly instead of one
		-- who keeps arriving somewhere else.
		if wind then
			local r = easeOut(k)
			ch.armR.z = -1.4 * r; ch.armL.z = 0.4 + 1.2 * r
			ch.lean = -0.36 * r; ch.sx = 1 - 0.1 * r; ch.bob = -0.24 * r
			ch.legL = 0.4 * r; ch.legR = -0.3 * r; ch.head = -0.2 * r
		elseif live then
			local flip = if math.floor(ak / 3) % 2 ~= 0 then 1 else -1
			ch.armR.z = F * flip; ch.armL.z = -F * flip * 0.7
			ch.armR.ext = 1 + 0.35
			ch.lean = 0.3 * flip
			ch.spinY = if flip > 0 then 0 else PI * 0.85        -- facing away on the off beat
			ch.opacity = 0.8
			ch.smear = 1
			ch.bob = -0.16
			if ak > act - 10 then
				local f2 = (ak - (act - 10)) / 10
				ch.spinY = 0; ch.opacity = 1; ch.lean = 0.44; ch.armR.z = F; ch.armR.ext = 1 + 0.5 * f2
			end
		else
			ch.lean = 0.44 * (1 - out); ch.armR.z = F * (1 - out); ch.armR.ext = 1 + 0.4 * (1 - out)
		end
	else
		-- GRIMOIRE - ASTRAL RAIN. The book goes up and the fighter opens out under it, arched back,
		-- pulsing with every wave that leaves the pages.
		if wind then
			local r = easeOut(k)
			ch.armL.z = 0.4 + 2.5 * r; ch.armR.z = -0.4 - 2.4 * r
			ch.lean = -0.45 * r; ch.sy = 1 + 0.2 * r; ch.sx = 1 - 0.12 * r
			ch.bob = 0.45 * r; ch.head = -0.5 * r
			ch.legL = -0.3 * r; ch.legR = -0.25 * r
		elseif live then
			ch.armL.z = 2.9; ch.armR.z = -2.8; ch.lean = -0.45; ch.head = -0.5
			ch.legL = -0.3; ch.legR = -0.25
			local S = m.starfall
			-- one pulse per wave: the fighter is the pump, not a statue
			local pulse = 0
			if S then
				local since = (ak - 1) % S.every
				if since < 10 and ak - 1 < S.perTarget * S.every then
					pulse = 1 - since / 10
				end
			end
			ch.sy = 1.2 + 0.18 * pulse; ch.sx = 0.88 - 0.1 * pulse
			ch.bob = 0.45 + 0.35 * pulse + math.sin(t * 1.8) * 0.08
			ch.opacity = 1
			ch.shakeX = strain(0.1 * pulse)
		else
			ch.armL.z = 2.9 * (1 - out); ch.armR.z = -2.8 * (1 - out)
			ch.lean = -0.45 * (1 - out); ch.sy = 1 + 0.2 * (1 - out); ch.bob = 0.45 * (1 - out)
			ch.head = -0.5 * (1 - out)
		end
	end

	-- Every ultimate settles through the same damped spring the ordinary moves use, so the last
	-- frames read as a fighter recovering their balance rather than as a pose being switched off.
	if not wind and not live then
		local d = 1 - settle(out, 2.4, 3.2)
		for _, key in { "lean", "bob", "head", "legL", "legR", "shakeX", "smear" } do
			ch[key] *= d
		end
		ch.sx = 1 + (ch.sx - 1) * d; ch.sy = 1 + (ch.sy - 1) * d
		ch.armL.z *= d; ch.armR.z *= d
		ch.armR.ext = 1 + (ch.armR.ext - 1) * d
	end
end

-- ---------------------------------------------------------------- attacks ----
local function attackChannels(ch: any, f: any, char: any, move: any, t: number)
	local m = move
	if not m then
		return
	end
	local s = Channels.swing(f, m)
	local id = m.id or ""
	-- An ultimate is not a big signature and cannot borrow a signature's timing: `swing` finishes
	-- its strike curve within a handful of frames, which is right for a 4-frame active window and
	-- meaningless across the 54 that Reave is live for.
	if id == "Ultimate" then
		return ultChannels(ch, f, char, m, t)
	end
	local cat
	if string.sub(id, 1, 12) == "LightNeutral" then cat = "jab"
	elseif string.sub(id, 1, 9) == "LightSide" or id == "ItemSwing" then cat = "side"
	elseif id == "LightDown" then cat = "down"
	elseif id == "LightUp" then cat = "up"
	elseif id == "AirNeutral" then cat = "nair"
	elseif id == "AirForward" then cat = "fair"
	elseif id == "AirDown" then cat = "dair"
	elseif id == "AirUp" then cat = "uair"
	elseif id == "SigSide" then cat = "sigside"
	elseif id == "SigDown" then cat = "sigdown"
	elseif id == "SigNeutral" then cat = "signeut"
	elseif id == "CounterBurst" then cat = "burst"
	elseif id == "ItemSpray" then cat = "spray"
	else cat = "jab" end
	ch.smear = s.smear * (if m.heavy then 1 else 0.7)

	-- A weapon can declare that it THRUSTS. A thrust is not a small swing: the reach comes from the
	-- body driving along a line - shoulder, hip, back leg - and from the arm extending, not from the
	-- prop rotating.
	local cat2 = cat
	if char.weapon and char.weapon.thrusts and THRUSTABLE[cat] then
		cat2 = THRUSTABLE[cat]
	end

	if m.kind == "counter" then
		ch.armL.z = 0.9; ch.armR.z = -0.9; ch.sy = 0.92; ch.sx = 1.08; ch.tint = "#3E4F2E"
		ch.bob = math.sin(t * 22) * 0.04    -- a counter is a held stance: keep it breathing
		return
	end

	-- A small tremble through a loaded wind-up, and a hard contact flash on the strike's first
	-- frames. Driven off the move's own frame counter, not wall-clock: at t*90 it aliased against
	-- 60Hz into a shimmer, and 0.05 studs is a quarter of a pixel anyway.
	if s.hold then
		ch.shakeX = (if f.moveFrame % 2 ~= 0 then 1 else -1) * 0.22
	end
	if s.phase == "strike" and s.k < 0.25 and m.heavy then
		ch.tint = "#FFFFFF"
	end

	-- `w` walks from rest (0) through the cocked pose and out to full extension (1), so each move
	-- below only has to name three poses and the easing does the rest. In the settle phase `e`
	-- already runs 1 -> 0, so it IS w; writing `1 - s.e` here runs every recovery backwards.
	local w = if s.phase == "wind" then -s.e else s.e
	-- the same walk, two and three frames behind, for the limbs that trail the torso
	local wLag2, wLag3, wLag4 = lagged(f, m, 2), lagged(f, m, 3), lagged(f, m, 4)
	local function pos(v: number): number return math.max(0, v) end

	if cat2 == "jab" then
		ch.armR.z = if w < 0 then -0.55 * -w else F * w
		ch.armL.z = -0.25 - 0.5 * math.abs(wLag2)
		ch.lean = if w < 0 then -0.12 * -w else 0.2 * w
		ch.legR = 0.18 * w; ch.legL = -0.1 * w
		ch.sx = 1 + 0.06 * pos(w)
	elseif cat2 == "side" then
		ch.armR.z = if w < 0 then -1.1 * -w else (F + 0.25) * w
		ch.armL.z = 0.25 - 0.9 * pos(wLag3)
		ch.lean = if w < 0 then -0.32 * -w else 0.42 * w
		ch.legR = 0.5 * pos(w); ch.legL = -0.35 * pos(w)
		ch.sx = 1 + 0.14 * pos(w); ch.sy = 1 - 0.06 * pos(w)
		ch.head = -0.18 * pos(wLag3)
	elseif cat2 == "down" then
		ch.sy = 1 - 0.28 * math.abs(w); ch.sx = 1 + 0.22 * math.abs(w)
		ch.lean = 0.34 * math.abs(w)
		ch.legR = if w < 0 then -0.3 * -w else 1.4 * w
		ch.legL = -0.25 * math.abs(w)
		ch.armR.z = 0.55 * w; ch.armL.z = 0.6
		ch.head = 0.22 * pos(w)
	elseif cat2 == "up" then
		ch.armR.z = if w < 0 then -0.7 * -w else (F + 0.9) * w
		ch.armL.z = -0.3 - 0.7 * pos(wLag3)
		ch.lean = -0.2 * pos(w)
		ch.sy = 1 + 0.12 * pos(w); ch.sx = 1 - 0.07 * pos(w)
		ch.legL = -0.3 * pos(w); ch.legR = 0.2 * pos(w)
		ch.bob = 0.18 * pos(w)
	elseif cat2 == "nair" then
		-- A spin: spinY squeezes the body horizontally as it turns.
		ch.spinY = easeInOut(clamp(f.moveFrame / math.max(1, f.startupEff + m.active + m.recovery), 0, 1)) * PI * 4
		ch.armL.z = 1.5; ch.armR.z = -1.5; ch.legL = 0.6; ch.legR = -0.6
		ch.sy = 0.96
	elseif cat2 == "fair" then
		ch.armR.z = if w < 0 then -1.15 * -w else (F + 0.15) * w
		ch.armL.z = 0.2 - 0.8 * pos(wLag3)
		ch.lean = 0.45 * w
		ch.legL = -0.55 - 0.2 * pos(w); ch.legR = -0.7 + 0.35 * pos(w)
		ch.head = -0.2 * pos(wLag4)
	elseif cat2 == "dair" then
		if w < 0 then
			ch.armL.z = 2.9 * -w; ch.armR.z = -2.9 * -w; ch.sy = 1 - 0.1 * -w
			ch.legL = -0.4 * -w; ch.legR = -0.4 * -w
		else
			ch.armL.z = 2.9 - 2.6 * w; ch.armR.z = -2.9 + 2.6 * w
			ch.sy = 1 + 0.2 * w; ch.sx = 1 - 0.12 * w; ch.head = 0.45 * w
			ch.legL = 0.5 * w; ch.legR = 0.4 * w
		end
	elseif cat2 == "uair" then
		ch.armR.z = if w < 0 then -0.5 * -w else (F + 1.1) * w
		ch.armL.z = -0.3 - 0.9 * pos(wLag2)
		ch.sy = 1 + 0.16 * pos(w); ch.sx = 1 - 0.09 * pos(w)
		ch.legL = -0.7 * pos(w); ch.legR = -0.5 * pos(w)
		ch.lean = -0.25 * pos(w)
	elseif cat2 == "sigside" then
		ch.lean = if w < 0 then -0.55 * -w else 0.55 * w
		ch.armR.z = if w < 0 then -1.6 * -w else (F + 0.35) * w
		ch.armL.z = 0.3 - 1.1 * pos(wLag3)
		ch.sx = 1 + 0.24 * pos(w) - 0.12 * pos(-w)
		ch.sy = 1 - 0.08 * pos(w) + 0.12 * pos(-w)
		ch.legR = 0.75 * pos(w); ch.legL = -0.5 * pos(w)
		ch.head = -0.25 * pos(wLag4)
		ch.bob = -0.12 * pos(-w)
	elseif cat2 == "sigdown" then
		-- An overhead slam: the arms go UP on the wind-up and come DOWN through the strike.
		ch.armL.z = if w < 0 then 0.6 + 2.4 * -w else 0.6 - 1.4 * w
		ch.armR.z = if w < 0 then -0.6 - 2.4 * -w else -0.6 + 1.4 * w
		ch.sy = if w < 0 then 1 + 0.16 * -w else 1 - 0.26 * w   -- stretch up, then compress in
		ch.sx = if w < 0 then 1 - 0.1 * -w else 1 + 0.22 * w
		ch.legL = 0.3 * pos(-w) - 0.5 * pos(w)
		ch.legR = -0.3 * pos(-w) + 0.5 * pos(w)
		ch.bob = 0.3 * pos(-w) - 0.22 * pos(w)
		ch.head = 0.3 * pos(wLag3) - 0.2 * pos(-w)
	elseif cat2 == "signeut" then
		ch.armR.z = if w < 0 then -1.2 * -w else (F + 0.8) * w
		ch.armL.z = -0.3 - 1.0 * pos(wLag3)
		ch.sy = 1 + 0.2 * pos(w) - 0.14 * pos(-w)
		ch.sx = 1 - 0.1 * pos(w) + 0.16 * pos(-w)
		ch.lean = -0.3 * pos(w)
		ch.bob = 0.24 * pos(w)
		ch.legL = -0.4 * pos(w); ch.legR = 0.3 * pos(w)
	elseif cat2 == "burst" then
		ch.sx = 1 + 0.3 * pos(w); ch.sy = 1 + 0.3 * pos(w)
		ch.armL.z = 1.6 * pos(w); ch.armR.z = -1.6 * pos(w)
	elseif cat2 == "spray" then
		ch.armR.z = F * 0.85; ch.armL.z = -0.4
		ch.lean = 0.2; ch.shakeX = math.sin(t * 40) * 0.06
	elseif cat2 == "thrust" then
		-- Cock: weight back over the rear leg, spear hand drawn in to the ribs. Drive: the whole
		-- body travels, the arm extends along the line, the rear leg straightens behind it.
		ch.armR.z = if w < 0 then -0.5 * -w else F * pos(w)
		ch.armR.ext = 1 + (if w < 0 then -0.22 * -w else 0.62 * w)  -- in on the cock, out on the drive
		ch.armL.z = 0.55 - 1.0 * pos(wLag3)
		ch.lean = if w < 0 then -0.3 * -w else 0.38 * w
		ch.legR = 0.95 * pos(w) - 0.25 * pos(-w)
		ch.legL = -0.7 * pos(w) + 0.3 * pos(-w)
		ch.sx = 1 + 0.1 * pos(w); ch.sy = 1 - 0.06 * pos(w) + 0.05 * pos(-w)
		ch.head = -0.14 * pos(wLag2)
		ch.bob = -0.2 * pos(w) + 0.1 * pos(-w)
	elseif cat2 == "thrustlow" then
		-- The same drive aimed at the ankles: the fighter drops into it rather than leaning into it.
		ch.armR.z = if w < 0 then -0.4 * -w else (F + 0.55) * pos(w)
		ch.armR.ext = 1 + (if w < 0 then -0.18 * -w else 0.52 * w)
		ch.armL.z = 0.5 - 0.8 * pos(wLag3)
		ch.sy = 1 - 0.3 * pos(w) + 0.08 * pos(-w)
		ch.sx = 1 + 0.2 * pos(w)
		ch.lean = 0.4 * pos(w) - 0.2 * pos(-w)
		ch.legR = 1.3 * pos(w); ch.legL = -0.55 * pos(w)
		ch.bob = -0.3 * pos(w)
		ch.head = 0.2 * pos(wLag3)
	end

	-- Charge hold: the whole body compresses and vibrates, and the vibration gets faster the longer
	-- it is held, so a fully charged move is visibly about to go off.
	if m.charge and f.moveFrame == f.startupEff and f.charge > 0 then
		local c = clamp(f.charge / m.charge.maxHold, 0, 1)
		local p = math.sin(f.charge * (0.4 + c * 0.9)) * (0.03 + c * 0.05)
		ch.sx += p; ch.sy -= p
		ch.shakeX = math.sin(f.charge * (1.2 + c * 2)) * (0.04 + c * 0.1)
		ch.tint = if c > 0.85 then "#FFFFFF" else "#FFF6DC"
	end
end

-- ---------------------------------------------------------------- the pose ----
-- Chill reads as one of three blues. The JavaScript indexes this by `stacks - 1`; Luau arrays are
-- 1-indexed, so it is indexed by `stacks` directly. Getting this wrong is a silent off-by-one that
-- shows the wrong blue rather than erroring.
local CHILL_TINT = { "#C9E6F5", "#A9D8F0", "#7FC0E6" }

function Channels.For(f: any, char: any, move: any, t: number): any
	local ch = {
		lean = 0, bob = 0, sx = 1, sy = 1, spinY = 0, spinZ = 0,
		armL = { z = 0.25, x = 0, ext = 1 }, armR = { z = -0.25, x = 0, ext = 1 },
		legL = 0, legR = 0, head = 0, opacity = 1, tint = nil :: string?,
		rigRotZ = 0, yOff = 0, bubble = 0, visible = true, shakeX = 0, smear = 0,
	}
	local s, sf = f.state, f.stateFrame
	local runPhase = f.frameCount * 0.38

	if s == "idle" then
		-- Two breathing rates slightly out of step, so an idle fighter never looks like a loop.
		local b1 = math.sin(t * 2.6 + f.index)
		local b2 = math.sin(t * 1.7 + f.index * 2.1)
		-- Anything under about 0.2 studs is a sub-pixel no-op. These are the smallest values that
		-- actually move.
		ch.bob = b1 * 0.26 + b2 * 0.1
		ch.armL.z = 0.3 + b1 * 0.06
		ch.armR.z = -0.3 - math.sin(t * 2.6 + f.index - 0.35) * 0.06
		ch.head = b2 * 0.05
		ch.sy = 1 + b1 * 0.04; ch.sx = 1 - b1 * 0.04
	elseif s == "run" then
		local sp = math.min(1, math.abs(f.vx) / char.runSpeed)
		ch.legL = math.sin(runPhase) * 0.95 * sp; ch.legR = -math.sin(runPhase) * 0.95 * sp
		-- Arms lag the legs by a fifth of a cycle - a run where they are exactly opposed is a march.
		ch.armL.x = -math.sin(runPhase - 0.6) * 0.75 * sp
		ch.armR.x = math.sin(runPhase - 0.6) * 0.75 * sp
		ch.lean = 0.2 * sp
		-- Two bounces per stride, and the body compresses on each footfall.
		local stride = math.abs(math.sin(runPhase))
		ch.bob = stride * 0.14 * sp
		ch.sy = 1 - (1 - stride) * 0.05 * sp; ch.sx = 1 + (1 - stride) * 0.05 * sp
		ch.head = -0.08 * sp + math.sin(runPhase - 1.1) * 0.05 * sp
	elseif s == "dash" then
		-- A dash is mostly its first four frames: hard lean, then it eases toward a run posture.
		local k = clamp(sf / 8, 0, 1)
		ch.lean = 0.5 - 0.12 * easeOut(k)
		ch.legL = 1.0 - 0.3 * k; ch.legR = -0.9 + 0.3 * k
		ch.armL.z = 0.9; ch.armR.z = -0.85
		ch.sx = 1.14 - 0.08 * easeOut(k); ch.sy = 0.9 + 0.06 * easeOut(k)
		ch.smear = 1 - k
	elseif s == "jumpsquat" then
		local k = clamp(sf / 4, 0, 1)
		ch.sy = 0.82 - 0.06 * k; ch.sx = 1.14 + 0.05 * k
		ch.legL = 0.35 * k; ch.legR = -0.35 * k; ch.head = 0.12 * k
	elseif s == "air" or s == "helpless" or s == "recovery" then
		if f.vy > 6 then
			-- rising: stretched, arms trailing below
			local r = clamp(f.vy / 60, 0, 1)
			ch.sy = 1 + 0.12 * r; ch.sx = 1 - 0.08 * r
			ch.armL.z = 2.4; ch.armR.z = -2.5; ch.legL = -0.65; ch.legR = -0.5
			ch.head = -0.1
		elseif f.vy < -6 then
			-- falling: arms come up, legs reach for the ground
			local r = clamp(-f.vy / 45, 0, 1)
			ch.armL.z = 1.2 - 0.3 * r; ch.armR.z = -1.2 + 0.3 * r
			ch.legL = 0.35 * r; ch.legR = -0.25 * r
			ch.sy = if f.fastFalling then 1.12 else 1 + 0.04 * r
			ch.sx = if f.fastFalling then 0.9 else 1
			ch.lean = if f.fastFalling then 0.15 else 0
		else
			-- the apex: the moment worth holding, so it gets its own pose
			local hang = math.sin(t * 4.5 + f.index)
			ch.armL.z = 1.7 + hang * 0.12; ch.armR.z = -1.7 - hang * 0.1
			ch.legL = -0.2 + hang * 0.1; ch.legR = 0.15 - hang * 0.08
			ch.sy = 0.98 + hang * 0.02; ch.sx = 1.02 - hang * 0.02; ch.head = hang * 0.1
		end
		if s == "helpless" then
			ch.spinZ = t * 5; ch.armL.z = 2.2; ch.armR.z = -2.2; ch.opacity = 0.9
		end
		if s == "recovery" then
			ch.spinY = sf * 0.5; ch.armL.z = 3; ch.armR.z = -3; ch.sy = 1.12
			ch.smear = clamp(1 - sf / 12, 0, 1)
		end
	elseif s == "landing" then
		-- Squash on contact, then a damped settle back to standing rather than a flat six frames.
		local k = clamp(sf / 10, 0, 1)
		local q = 1 - settle(k, 3.0, 6)
		ch.sy = 1 - 0.2 * q; ch.sx = 1 + 0.16 * q
		ch.legL = 0.3 * q; ch.legR = -0.3 * q
		ch.bob = -0.14 * q; ch.head = 0.12 * q
	elseif s == "attack" then
		attackChannels(ch, f, char, move, t)
		if not f.onGround then
			ch.legL += 0.3; ch.legR -= 0.3
		end
	elseif s == "hitstun" then
		-- The reaction leans AWAY from where the hit came from, and the first frames are loudest.
		local away = if f.vx >= 0 then 1 else -1
		local fresh = clamp(1 - sf / 10, 0, 1)
		ch.lean = -0.55 * fresh * away * f.facing
		ch.armL.z = 2.2 + math.sin(sf * 0.8) * 0.5 * fresh
		ch.armR.z = -2.0 - math.sin(sf * 0.8 + 1) * 0.5 * fresh
		ch.head = -0.35 * fresh
		ch.legL = 0.5 + math.sin(sf * 0.7) * 0.3 * fresh
		ch.legR = -0.4 - math.sin(sf * 0.7) * 0.3 * fresh
		ch.sx = 1 + 0.1 * fresh; ch.sy = 1 - 0.08 * fresh
		ch.shakeX = if sf < 4 then (if sf % 2 ~= 0 then 0.18 else -0.18) else 0
		ch.smear = fresh * 0.6
	elseif s == "knockdown" then
		-- A downed fighter still breathes, and a stirring body is how a player reads that the
		-- wake-up is coming.
		ch.rigRotZ = -PI / 2 + 0.1; ch.rotPivot = 0; ch.yOff = 0.7
		local br = math.sin(sf * 0.22)
		ch.armL.z = 1.2 + br * 0.18; ch.armR.z = -1.2 - br * 0.14
		ch.sy = 0.95 + br * 0.03; ch.head = br * 0.2; ch.bob = br * 0.1
	elseif s == "tech" then
		ch.opacity = 0.6
		if f.techRoll ~= 0 then
			ch.spinZ = -sf * 0.42; ch.smear = clamp(1 - sf / 10, 0, 1)
		else
			local k = clamp(sf / 8, 0, 1)
			local q = 1 - settle(k, 3, 7)
			ch.sy = 1 - 0.16 * q; ch.sx = 1 + 0.12 * q
		end
	elseif s == "shield" or s == "shielddrop" then
		local k = clamp(sf / 4, 0, 1)
		ch.sy = 1 - 0.12 * easeOut(k); ch.sx = 1 + 0.06 * easeOut(k)
		ch.armL.z = 0.9 * easeOut(k); ch.armR.z = -0.9 * easeOut(k)
		ch.head = 0.1 * easeOut(k)
		if s == "shield" then
			ch.bubble = math.max(0.25, f.shield / 50); ch.bob = math.sin(t * 5) * 0.03
		end
	elseif s == "stunned" then
		ch.lean = math.sin(sf * 0.3) * 0.3; ch.head = math.sin(sf * 0.5) * 0.35
		ch.armL.z = 1.0 + math.sin(sf * 0.4) * 0.3
		ch.armR.z = -1.0 - math.sin(sf * 0.4 + 2) * 0.3
		ch.spinY = math.sin(sf * 0.12) * 0.6
		ch.tint = if sf % 12 < 6 then "#F4C531" else nil
	elseif s == "spotdodge" then
		local k = clamp(sf / 10, 0, 1)
		local q = math.sin(k * PI)
		ch.opacity = 1 - 0.65 * q; ch.sy = 1 - 0.14 * q; ch.sx = 1 + 0.1 * q; ch.lean = -0.35 * q
	elseif s == "airdodge" then
		ch.opacity = 0.35; ch.spinZ = sf * 0.45; ch.smear = clamp(1 - sf / 14, 0, 1)
	elseif s == "ledge" then
		ch.armL.z = 2.9; ch.armR.z = -2.9
		ch.legL = 0.35 + math.sin(t * 3) * 0.06; ch.legR = -0.2; ch.head = -0.3
		ch.bob = math.sin(t * 4) * 0.22; ch.lean = -0.12 + math.sin(t * 2.2) * 0.05
	elseif s == "ledgeaction" then
		local k = f.ledgeAction
		if k == "attack" then
			ch.armR.z = if sf > 8 then PI / 2 else -0.8
			ch.lean = 0.3; ch.smear = if sf > 8 then 0.6 else 0
		elseif k == "roll" then
			ch.spinZ = -sf * 0.34; ch.opacity = 0.7; ch.smear = 0.5
		else
			ch.lean = -0.2; ch.armL.z = 1.4; ch.armR.z = -1.4; ch.sy = 1.06
		end
	elseif s == "grab" then
		local k = clamp(sf / 8, 0, 1)
		ch.armL.z = 1.4 + F * easeIn(k); ch.armR.z = -1.4 + (F + 1.4) * easeIn(k)
		ch.lean = 0.1 + 0.25 * easeIn(k)
		ch.smear = if sf > 6 and sf < 11 then 0.7 else 0
	elseif s == "holding" then
		ch.armL.z = PI / 2; ch.armR.z = PI / 2; ch.lean = 0.15; ch.sx = 1.05
		ch.bob = math.sin(t * 6) * 0.16
	elseif s == "grabbed" then
		ch.armL.z = 1.6; ch.armR.z = -1.6
		ch.legL = math.sin(sf * 0.6) * 0.85; ch.legR = -math.sin(sf * 0.6 + 0.8) * 0.85
		ch.head = -0.2 + math.sin(sf * 0.9) * 0.12
	elseif s == "groundpound" then
		if sf <= 8 then
			local k = clamp(sf / 8, 0, 1)
			ch.sy = 1 - 0.2 * back(k, 1.2); ch.sx = 1 + 0.15 * back(k, 1.2)
			ch.armL.z = 2.9 * k; ch.armR.z = -2.9 * k; ch.bob = 0.2 * k
		else
			ch.sy = 1.28; ch.sx = 0.84; ch.armL.z = 3.1; ch.armR.z = -3.1
			ch.legL = 0; ch.legR = 0; ch.smear = 0.8
		end
	elseif s == "tether" then
		ch.armL.z = 2.9; ch.armR.z = -2.9; ch.sy = 1.15; ch.sx = 0.9
		ch.lean = math.sin(t * 7) * 0.08
	elseif s == "frozen" then
		ch.tint = "#A9D8F0"; ch.armL.z = 1.2; ch.armR.z = -1.2
	elseif s == "taunt" then
		ch.bob = math.abs(math.sin(sf * 0.25)) * 0.5; ch.spinY = sf * 0.14
		ch.armL.z = 2.6 + math.sin(sf * 0.5) * 0.45; ch.armR.z = -0.4
	elseif s == "ko" then
		ch.visible = false
	elseif s == "respawn" then
		ch.yOff = math.sin(t * 4) * 0.3; ch.opacity = 0.85
		ch.armL.z = 1.2; ch.armR.z = -1.2
	end

	if f.tumbling and (s == "air" or s == "hitstun") then
		ch.spinZ = -f.frameCount * 0.3 * f.facing
		ch.smear = math.max(ch.smear, 0.5)
	end
	if f.invincible > 0 and s ~= "ledge" and s ~= "respawn" and f.frameCount % 6 < 3 then
		ch.opacity *= 0.55
	end
	if f.chillStacks > 0 and not ch.tint then
		ch.tint = CHILL_TINT[f.chillStacks]
	end
	if f.hitlag > 0 then
		ch.shakeX = if f.frameCount % 2 ~= 0 then 0.12 else -0.12
	end

	-- spinZ is rotation in the screen plane, which IS rigRotZ - they were separate channels and
	-- spinZ was wired to nothing, so air dodges, tech rolls and helpless falls all set a spin that
	-- rendered as a static pose. Folded here rather than at every call site.
	if ch.spinZ ~= 0 then
		ch.rigRotZ += ch.spinZ
	end
	-- spinY is rotation about the fighter's own vertical axis. In 2D that is a horizontal squeeze:
	-- the body narrows as it turns edge-on and widens again. Same reason - it was dead.
	if ch.spinY ~= 0 then
		ch.sx *= math.max(0.12, math.abs(math.cos(ch.spinY)))
	end
	return ch
end

return Channels
