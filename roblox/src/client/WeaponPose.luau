--!strict
-- Where the weapon is this frame: angle, offset, scale, swing trail, muzzle flash.
--
-- A port of the pose half of web/src/render2d/weapons2d.js, held to it by tests/weapon-parity.luau.
-- The drawing half - the twelve weapon shapes - is Weapons2D.luau; this file is only numbers.
--
-- Angles are radians, counter-clockwise, 0 = pointing forward, +PI/2 = straight up. Swings are
-- keyframed as [windup, contact, follow-through] and interpolated across the move's real startup /
-- active / recovery, so a swing always lines up with the frames that actually hit.
--
-- THE PHASE CURVE IS SHARED WITH THE BODY. `Channels.swing` is the same function channels.js
-- exports, not a copy: the JavaScript used to run its own easing here and the torso and the weapon
-- ended up as much as fifteen frames out of phase - on Crescent Rush the body was fully loaded on
-- frame 5 and held for sixteen frames while the sword was six percent of the way back. Two
-- animations playing over each other. Keep them one function.

local Channels = require(script.Parent.Channels)

local WeaponPose = {}

local PI = math.pi
local easeOut, easeIn = Channels.easeOut, Channels.easeIn

local function D(deg: number): number
	return (deg * PI) / 180
end

-- `a or b` is wrong for these: JavaScript's `||` falls through on 0 as well as nil, and a
-- weaponScale of 0 would take the default there and not here.
local function orDefault(v: any, d: number): number
	return if v ~= nil and v ~= 0 then v else d
end

-- How each move swings. `hold` weapons (blasters, grimoire) do not swing at all - they aim.
--   arc:   { windupAngle, contactAngle, endAngle }
--   trail: how much of the arc to smear behind the blade, in radians
local SWINGS: { [string]: any } = {
	jab =     { arc = { D(70), D(5), D(25) }, trail = D(45), thrust = 0.35 },
	side =    { arc = { D(140), D(-25), D(-5) }, trail = D(110) },
	down =    { arc = { D(35), D(-70), D(-50) }, trail = D(80) },
	-- Rising attacks cock BELOW the resting angle before they come up. Starting above rest makes
	-- the wind-up the weapon travelling toward you, and there is nothing to read.
	up =      { arc = { D(-115), D(105), D(80) }, trail = D(100) },
	nair =    { arc = { D(0), D(720), D(720) }, trail = D(150), spin = true },
	fair =    { arc = { D(130), D(-15), D(5) }, trail = D(105) },
	dair =    { arc = { D(-60), D(-95), D(-90) }, trail = D(50) },
	uair =    { arc = { D(-110), D(115), D(95) }, trail = D(110) },
	sigside = { arc = { D(175), D(-40), D(-15) }, trail = D(150), heavy = true },
	sigdown = { arc = { D(150), D(-85), D(-65) }, trail = D(140), heavy = true },
	signeut = { arc = { D(-120), D(130), D(110) }, trail = D(140), heavy = true },
}

-- Per-weapon overrides. SWINGS is the sword's motion; these weapons do not move like a sword.
-- AXE and HAMMER are hauled overhead and DROPPED, so the cocked angle is high and behind and the
-- contact angle is at or below the floor line. PIKE thrusts: tiny angular travel, and the reach
-- comes from armR.ext in channels.js extending the ARM, so the hand moves and the weapon stays
-- attached. DAGGERS end pointing where the blade is going, because a 1.5-stud blade has no arc
-- long enough to read. FLAIL overshoots every settle, because its head is on four studs of chain.
local SWING_BY_WEAPON: { [string]: { [string]: any } } = {
	Axe = {
		jab =     { arc = { D(60), D(-5), D(15) }, trail = D(60), heavy = true },
		side =    { arc = { D(150), D(-30), D(-10) }, trail = D(130), heavy = true },
		down =    { arc = { D(40), D(-80), D(-62) }, trail = D(100), heavy = true },
		up =      { arc = { D(-120), D(100), D(70) }, trail = D(120), heavy = true },
		fair =    { arc = { D(160), D(-20), D(0) }, trail = D(140), heavy = true },
		dair =    { arc = { D(-40), D(-95), D(-90) }, trail = D(60), heavy = true },
		uair =    { arc = { D(-115), D(110), D(90) }, trail = D(130), heavy = true },
		sigside = { arc = { D(175), D(-38), D(-14) }, trail = D(170), heavy = true },
		sigdown = { arc = { D(168), D(-88), D(-70) }, trail = D(165), heavy = true },
		signeut = { arc = { D(-125), D(120), D(98) }, trail = D(150), heavy = true },
	},
	Pike = {
		jab =     { arc = { D(-26), D(2), D(-8) }, trail = D(26), thrust = 0.2 },
		side =    { arc = { D(-28), D(2), D(-8) }, trail = D(28), thrust = 0.25 },
		down =    { arc = { D(-6), D(-34), D(-26) }, trail = D(28), thrust = 0.2 },
		up =      { arc = { D(6), D(88), D(72) }, trail = D(44), thrust = 0.2 },
		nair =    { arc = { D(0), D(720), D(720) }, trail = D(150), spin = true },
		fair =    { arc = { D(-30), D(0), D(-10) }, trail = D(30), thrust = 0.3 },
		dair =    { arc = { D(-56), D(-92), D(-86) }, trail = D(34), thrust = 0.2 },
		uair =    { arc = { D(16), D(92), D(78) }, trail = D(44), thrust = 0.2 },
		sigside = { arc = { D(-34), D(2), D(-10) }, trail = D(32), thrust = 0.35, heavy = true },
		sigdown = { arc = { D(-4), D(-38), D(-28) }, trail = D(32), thrust = 0.3, heavy = true },
		signeut = { arc = { D(10), D(92), D(76) }, trail = D(48), thrust = 0.3, heavy = true },
	},
	Hammer = {
		jab =     { arc = { D(70), D(-8), D(12) }, trail = D(70), heavy = true },
		side =    { arc = { D(158), D(-32), D(-10) }, trail = D(140), heavy = true },
		down =    { arc = { D(46), D(-84), D(-66) }, trail = D(110), heavy = true },
		up =      { arc = { D(-124), D(104), D(76) }, trail = D(130), heavy = true },
		fair =    { arc = { D(166), D(-22), D(2) }, trail = D(150), heavy = true },
		dair =    { arc = { D(-38), D(-96), D(-92) }, trail = D(64), heavy = true },
		uair =    { arc = { D(-118), D(112), D(92) }, trail = D(140), heavy = true },
		sigside = { arc = { D(178), D(-40), D(-16) }, trail = D(175), heavy = true },
		sigdown = { arc = { D(172), D(-90), D(-72) }, trail = D(170), heavy = true },
		signeut = { arc = { D(-130), D(124), D(100) }, trail = D(158), heavy = true },
	},
	Daggers = {
		jab =     { arc = { D(58), D(14), D(30) }, trail = D(44), thrust = 0.2 },
		side =    { arc = { D(72), D(6), D(24) }, trail = D(66) },
		down =    { arc = { D(26), D(-52), D(-36) }, trail = D(58) },
		up =      { arc = { D(-88), D(88), D(70) }, trail = D(90) },
		nair =    { arc = { D(0), D(720), D(720) }, trail = D(150), spin = true },
		fair =    { arc = { D(76), D(8), D(26) }, trail = D(68) },
		dair =    { arc = { D(-54), D(-92), D(-86) }, trail = D(44) },
		uair =    { arc = { D(-84), D(90), D(74) }, trail = D(92) },
		sigside = { arc = { D(88), D(2), D(22) }, trail = D(80), heavy = true },
		sigdown = { arc = { D(34), D(-60), D(-44) }, trail = D(70), heavy = true },
		signeut = { arc = { D(-92), D(94), D(76) }, trail = D(96), heavy = true },
	},
	Flail = {
		jab =     { arc = { D(96), D(-2), D(34) }, trail = D(96), heavy = true },
		side =    { arc = { D(170), D(-34), D(6) }, trail = D(160), heavy = true },
		down =    { arc = { D(52), D(-78), D(-44) }, trail = D(120), heavy = true },
		up =      { arc = { D(-128), D(112), D(74) }, trail = D(140), heavy = true },
		nair =    { arc = { D(0), D(1080), D(1080) }, trail = D(200), spin = true },
		fair =    { arc = { D(168), D(-18), D(18) }, trail = D(160), heavy = true },
		dair =    { arc = { D(-42), D(-98), D(-88) }, trail = D(72), heavy = true },
		uair =    { arc = { D(-122), D(118), D(88) }, trail = D(150), heavy = true },
		sigside = { arc = { D(186), D(-40), D(24) }, trail = D(190), heavy = true },
		sigdown = { arc = { D(40), D(-86), D(-52) }, trail = D(140), heavy = true },
		signeut = { arc = { D(-134), D(128), D(96) }, trail = D(160), heavy = true },
	},
}

local function categoryOf(id: string?): string?
	if not id or id == "" then return nil end
	if id == "Ultimate" then return "ult" end
	if string.sub(id, 1, 12) == "LightNeutral" then return "jab" end
	if string.sub(id, 1, 9) == "LightSide" then return "side" end
	if id == "LightDown" then return "down" end
	if id == "LightUp" then return "up" end
	if id == "AirNeutral" then return "nair" end
	if id == "AirForward" then return "fair" end
	if id == "AirDown" then return "dair" end
	if id == "AirUp" then return "uair" end
	if id == "SigSide" then return "sigside" end
	if id == "SigDown" then return "sigdown" end
	if id == "SigNeutral" then return "signeut" end
	return "jab"
end

-- Weapons that are aimed rather than swung: a recoil kick and a muzzle flash on the frame the
-- projectile leaves, instead of an arc.
local AIMED: { [string]: any } = { Blasters = true, Grimoire = "cast", Longbow = true }

-- The axe rests almost straight down and slightly behind: it is not being held, it is being
-- dragged. The gauntlets and shield rest near horizontal because they are worn, not carried.
local REST: { [string]: number } = {
	Sword = D(-78), Scythe = D(-72), Blasters = D(-60), Grimoire = D(-70), Axe = D(-104),
	Pike = D(-58), Gauntlets = D(-28), Hammer = D(-98), Longbow = D(-84), Flail = D(-96),
	Shield = D(-20), Daggers = D(-66),
}
local function restOf(wid: string?): number
	return if wid and REST[wid] then REST[wid] else D(-70)
end
-- `?? 0` in the JavaScript, not `?? D(-70)`: the ultimates fall back to zero rather than carry.
local function restOr0(wid: string?): number
	return if wid and REST[wid] then REST[wid] else 0
end

-- ------------------------------------------------------------- the ultimates -----
-- One per weapon, each the shape of its own move rather than a louder signature. These share the
-- phase boundaries ultChannels uses, so the fighter and the prop perform one move rather than two.
local function ultimatePose(f: any, m: any, wid: string?, out: any, t: number): any
	local st, act, rec, mf = f.startupEff, m.active, m.recovery, f.moveFrame
	local k = if mf <= st then mf / math.max(1, st)
		elseif mf <= st + act then (mf - st) / math.max(1, act)
		else 1 + (mf - st - act) / math.max(1, rec)
	local inWindup = mf <= st
	local inActive = mf > st and mf <= st + act
	local ak = mf - st                                    -- frame within the active window
	local recK = math.min(1, (mf - st - act) / math.max(1, rec))
	out.ult = { phase = if inWindup then "windup" elseif inActive then "active" else "end", k = k, wid = wid }

	if wid == "Sword" then
		-- The blade grows and stays grown, so the silhouette alone says what is about to happen.
		-- CHOP lands on the LAST startup frame: the hitbox and the crater both fire on active
		-- frame 1, and a chop played across the active frames has the floor erupting four frames
		-- before the sword reaches it.
		local FULL = orDefault(m.weaponScale, 2)
		local CHOP = 5
		local riseEnd = math.max(1, st - CHOP)
		if inWindup then
			if mf <= riseEnd then                         -- hoisted overhead, growing as it goes
				local r = mf / riseEnd
				out.scale = 1 + (FULL - 1) * r
				out.angle = restOr0(wid) + (D(104) - restOr0(wid)) * (r * r)
				out.oy = -r * 0.4
				out.charge = r
				out.ult.glow = r; out.ult.rise = r
				return out
			end
			local c = (mf - riseEnd) / CHOP               -- and down, arriving as the active frames open
			out.scale = FULL
			out.angle = D(104) + (D(-84) - D(104)) * (c * c * (3 - 2 * c))
			out.trail = { from = D(104), to = out.angle, alpha = 1, heavy = true }
			out.ult.glow = 1; out.ult.chop = c
			return out
		end
		-- Planted while the crater runs outward. The blade SINKS: at full scale a 2x sword held at
		-- -84 degrees is a 5-stud bar reaching well below the fighter's feet, and with the edge
		-- glow on top it draws as a solid white rectangle through the character.
		local since = if inActive then ak else act + (mf - st - act)
		local sink = math.min(1, since / 6)
		out.scale = FULL - (FULL - 1.05) * sink
		out.ult.glow = 1 - sink * 0.75                    -- the edge cools once it is in the ground
		out.angle = D(-84) + math.sin(since * 0.55) * 0.035
		out.ult.planted = sink
		out.ult.shock = if inActive then ak / math.max(1, act) else 1
		if not inActive then                              -- recovery: shoulder it, back to normal
			out.angle = D(-84) + (restOr0(wid) - D(-84)) * recK
			out.scale = 1.05 + (1 - 1.05) * recK
			out.ult.glow = (1 - sink * 0.75) * (1 - recK)
		end
		return out
	elseif wid == "Scythe" then
		local hold = orDefault(if m.vortex then m.vortex.holdFrames else nil, 22)
		if inWindup then                                  -- cocked back, blade high behind the head
			out.angle = restOr0(wid) + (D(158) - restOr0(wid)) * (k * k)
			out.charge = k
			return out
		end
		if inActive and ak <= hold then
			local h = ak / hold
			-- the arm reaches out and STAYS out: the hold is the move, so the pose holds too
			local reach = math.min(1, ak / 5)
			out.angle = D(158) + (D(14) - D(158)) * (reach * reach * (3 - 2 * reach))
			out.ox = reach * 0.5
			out.angle += math.sin(ak * 1.7) * 0.05 * h    -- strain, rising as the ball tightens
			if ak <= 6 then
				out.trail = { from = D(158), to = out.angle, alpha = 1 - ak / 8, heavy = true }
			end
			out.ult.pull = h
			return out
		end
		-- the crush: whip the blade down through the ball
		local since = if inActive then ak - hold else (act - hold) + (mf - st - act)
		local w = math.min(1, since / 8)
		out.angle = D(14) + (D(-92) - D(14)) * w
		if w < 1 then
			out.trail = { from = D(14), to = out.angle, alpha = 1, heavy = true }
		end
		out.ult.crush = w
		if not inActive then
			out.angle = D(-92) + (restOr0(wid) - D(-92)) * recK
		end
		return out
	elseif wid == "Blasters" then
		-- The two pistols fold into one long-barrelled rifle.
		local reload = orDefault(if m.sniper then m.sniper.reload else nil, 16)
		out.ult.rifle = if inWindup then k else 1
		out.ult.rounds = f.ultShots or 0
		if inWindup then
			out.angle = D(-30) * (1 - k); out.charge = k; out.ox = -0.4 * (1 - k)
			return out
		end
		out.angle = D(0)
		if inActive then
			-- frames since the last trigger pull, off the reload counter the engine already keeps
			local since = if f.ultCooldown > 0 then reload - f.ultCooldown else 99
			if since < 7 then
				local kk = since / 7
				out.angle = D(26) * (1 - kk) * (1 - kk)   -- hard recoil, this is a rifle now
				out.ox = -0.7 * (1 - kk)
				out.flash = math.max(0, 1 - since / 2.5)
			else
				out.angle = math.sin(t * 2.2) * D(1.2)    -- holding the aim, breathing
			end
			out.ult.aiming = true
		else
			out.angle = D(0) + (restOr0(wid) - D(0)) * recK
			out.ult.rifle = 1 - recK
		end
		return out
	elseif wid == "Axe" then
		-- REAVE. The wind-up is the only moment of effort. After that they are not swinging it,
		-- they are being swung BY it: the angle just accelerates, three revolutions getting faster.
		if inWindup then
			out.angle = restOr0(wid) + (D(-150) - restOr0(wid)) * (k * k)
			out.charge = k; out.oy = -0.1
			out.ult.haul = k                              -- renderer: strain lines and a dust scuff
			return out
		end
		if inActive then
			-- PI*6 is three revolutions. The exponent is 1.15, not 1.45: at 1.45 the finisher box
			-- spins at 5.7 rev/s, making the one pass that actually sends the least legible frame.
			local spin = ((ak / math.max(1, act)) ^ 1.15) * PI * 6.0
			out.angle = D(-150) - spin
			out.scale = orDefault(m.weaponScale, 1.35)
			out.trail = { from = out.angle + D(300), to = out.angle, alpha = 1, heavy = true }
			out.ult.reave = ak / math.max(1, act)
			out.ult.blur = { out.angle + D(115), out.angle + D(232) }
			return out
		end
		out.angle = D(-84) + (restOr0(wid) - D(-84)) * recK
		local ws = orDefault(m.weaponScale, 1.35)
		out.scale = ws - (ws - 1) * recK
		return out
	elseif wid == "Pike" then
		-- LANCE CHARGE. The haft telescopes and stays out, then delivers a run of thrusts. The
		-- angle barely moves; everything is along the line, which is the identity of the weapon.
		local FULL = orDefault(m.weaponScale, 1.9)
		if inWindup then
			out.angle = D(-58) + (D(-6) - D(-58)) * easeOut(k)
			out.scale = 1 + (FULL - 1) * k
			out.charge = k
			out.ult.extend = k
			return out
		end
		if inActive then
			out.scale = FULL
			-- FIVE thrusts, one per hitbox step, so a damage tick always lands on a visible punch
			local per = act / 5
			local phase = (ak % per) / per
			local punch = if phase < 0.35 then easeIn(phase / 0.35) else 1 - (phase - 0.35) / 0.65
			out.angle = D(-6) + math.sin(ak * 0.4) * D(3)
			-- Small, now that the ARM extends on the punch: the hand carries most of the travel
			-- and this is just the haft sliding through the grip.
			out.ox = punch * 0.25
			out.flash = if punch > 0.8 then (punch - 0.8) * 5 else 0
			out.ult.lance = { punch = punch, reach = ak / math.max(1, act) }
			if punch > 0.5 then
				out.trail = { from = out.angle - D(8), to = out.angle, alpha = punch, heavy = true }
			end
			return out
		end
		out.angle = D(-6) + (restOr0(wid) - D(-6)) * recK
		out.scale = FULL - (FULL - 1) * recK
		return out
	elseif wid == "Gauntlets" then
		-- HUNDRED HANDS. Nothing to swing, so the pose is the arms.
		if inWindup then
			out.angle = D(-40) + (D(-110) - D(-40)) * (k * k)
			out.charge = k; out.ult.haul = k
			return out
		end
		if inActive then
			local p2 = ak / math.max(1, act)
			out.angle = D(-6) + math.sin(ak * 1.9) * D(26)
			out.ox = 0.12 + math.abs(math.sin(ak * 1.9)) * 0.2
			out.ult.flurry = p2
			out.ult.blur = { out.angle + D(26), out.angle - D(26) }
			if ak > act - 10 then
				out.angle = D(2); out.ox = 0.32; out.ult.finish = (ak - (act - 10)) / 10
			end
			return out
		end
		out.angle = D(-6) + (restOr0(wid) - D(-6)) * recK
		return out
	elseif wid == "Hammer" then
		-- UPHEAVAL. One strike into the floor, and then the hammer STAYS there: the fighter is
		-- holding the ground open while the columns come up. A prop that falls and then does
		-- nothing for sixty frames reads as the move having ended.
		local FULL = orDefault(m.weaponScale, 1.4)
		local CHOP = 8
		local riseEnd = math.max(1, st - CHOP)
		if inWindup then
			if mf <= riseEnd then
				local r = mf / riseEnd
				out.scale = 1 + (FULL - 1) * r
				out.angle = restOr0(wid) + (D(120) - restOr0(wid)) * (r * r)
				out.oy = -r * 0.4; out.charge = r
				out.ult.haul = r; out.ult.glow = r
				return out
			end
			local c = (mf - riseEnd) / CHOP
			out.scale = FULL
			out.angle = D(120) + (D(-92) - D(120)) * (c * c * (3 - 2 * c))
			out.trail = { from = D(120), to = out.angle, alpha = 1, heavy = true }
			out.ult.glow = 1; out.ult.chop = c
			return out
		end
		if inActive then
			-- planted, and shuddering every time another column goes up
			local U = m.upheaval
			local beat = if U then (ak % U.every) / U.every else 0
			out.scale = FULL * 0.96
			out.angle = D(-92) + math.sin(ak * 0.7) * 0.03
			out.ult.planted = 1
			out.ult.shock = 1 - beat
			out.ult.glow = 0.4 + (1 - beat) * 0.6
			return out
		end
		out.angle = D(-92) + (restOr0(wid) - D(-92)) * recK
		out.scale = FULL * 0.96 - (FULL * 0.96 - 1) * recK
		return out
	elseif wid == "Longbow" then
		-- HEARTSEEKER. Forty-four frames of drawing, one release. The only fast thing is the loose.
		if inWindup then
			local r = easeOut(k)
			out.angle = restOr0(wid) + (D(-2) - restOr0(wid)) * r
			out.charge = k
			out.ult.draw = k                              -- renderer: the string and the aiming line
			out.ox = -0.22 * k                            -- the bow drifts back as it is drawn
			return out
		end
		if inActive then
			local kk = math.min(1, ak / 5)
			out.angle = D(-2) + D(9) * (1 - kk) * (1 - kk)  -- the snap forward on release
			out.ox = 0.26 * (1 - kk)
			out.flash = math.max(0, 1 - ak / 3)
			out.ult.loose = kk
			return out
		end
		out.angle = D(-2) + (restOr0(wid) - D(-2)) * recK
		return out
	elseif wid == "Flail" then
		-- ANCHOR. The head is thrown, and after that the fighter is walking around holding the
		-- other end of a chain.
		if inWindup then
			out.angle = restOr0(wid) + (D(-150) - restOr0(wid)) * (k * k)
			out.charge = k; out.ult.haul = k
			return out
		end
		if inActive then
			local thrown = math.min(1, ak / 6)
			out.angle = D(-150) + (D(-14) - D(-150)) * (thrown * thrown * (3 - 2 * thrown))
			if thrown < 1 then
				out.trail = { from = D(-150), to = out.angle, alpha = 1, heavy = true }
			end
			-- the head is gone: hide the prop and let the world-space chain BE the weapon
			out.hide = thrown >= 1
			out.ult.anchored = if thrown >= 1 then 1 else 0
			out.ox = 0.2 * thrown
			return out
		end
		out.hide = false
		out.angle = D(-14) + (restOr0(wid) - D(-14)) * recK
		return out
	elseif wid == "Shield" then
		-- LAST STAND. The prop's job is to sit absolutely still and grow.
		if inWindup then
			out.angle = restOr0(wid) + (D(-4) - restOr0(wid)) * easeOut(k)
			out.ox = 0.2 * k; out.charge = k; out.ult.brace = k
			return out
		end
		if inActive then
			out.angle = D(-4)
			out.ox = 0.2 + math.sin(ak * 0.9) * 0.04
			out.scale = 1.12
			out.ult.wall = ak / math.max(1, act)
			if ak > act - 12 then
				out.ult.release = (ak - (act - 12)) / 12
				out.ox = 0.2 + out.ult.release * 0.14
				out.scale = 1.12 + out.ult.release * 0.45
			end
			return out
		end
		out.angle = D(-4) + (restOr0(wid) - D(-4)) * recK
		out.ox = 0.2 * (1 - recK)
		return out
	elseif wid == "Daggers" then
		-- THOUSAND CUTS. The blades are where the fighter is not: the pose flickers between two
		-- extremes rather than travelling between them, which is the only way a teleport reads.
		if inWindup then
			out.angle = restOr0(wid) + (D(-150) - restOr0(wid)) * (k * k)
			out.charge = k; out.ult.haul = k
			return out
		end
		if inActive then
			local flip = if math.floor(ak / 3) % 2 ~= 0 then 1 else -1
			out.angle = D(20) * flip + math.sin(ak * 2.6) * D(14)
			out.ox = 0.16 + (if flip > 0 then 0.16 else 0)
			out.ult.flurry = ak / math.max(1, act)
			out.ult.blur = { out.angle + D(150), out.angle - D(150) }
			if ak > act - 10 then
				out.angle = D(6); out.ox = 0.3; out.ult.finish = (ak - (act - 10)) / 10
			end
			return out
		end
		out.angle = D(6) + (restOr0(wid) - D(6)) * recK
		return out
	end

	-- Grimoire: the book goes overhead and stays there while the sky falls.
	if inWindup then
		out.angle = D(-70) + k * D(160); out.charge = k; out.oy = k * 0.3
		return out
	end
	out.angle = D(92) + math.sin(mf * 0.5) * 0.05
	out.oy = 0.3
	if inActive then
		out.ult.runes = ak / math.max(1, act)
		out.flash = 0.35
		-- a pulse of light each time a wave of orbs leaves the book
		local S = m.starfall
		if S then
			local since = (ak - 1) % S.every
			if since < 6 and ak - 1 < S.perTarget * S.every then
				out.flash = 1 - since / 6
			end
		end
	else
		out.angle = D(92) + (restOr0(wid) - D(92)) * recK
	end
	return out
end

-- Where a projectile-spawning move actually fires, in absolute move frames.
local function fireFrame(f: any): number
	return f.startupEff + 1
end

-- `f` is a decoded snapshot; `char` and `move` are looked up by the caller, as in Channels.
function WeaponPose.For(f: any, char: any, move: any, t: number): any
	local wid = if char.weapon then char.weapon.id else nil
	local out: any = {
		angle = restOf(wid), ox = 0, oy = 0, scale = 1,
		trail = nil, flash = 0, charge = 0, hide = false, ult = nil,
	}
	if not wid then
		return out
	end

	local s = f.state
	local aimed = AIMED[wid]

	-- idle / movement poses
	if s == "idle" or s == "run" or s == "dash" then
		out.angle = restOf(wid) + math.sin(t * 3 + f.index) * 0.06
		if s == "run" or s == "dash" then
			out.angle += 0.25
		end
		-- A weapon with `drag` is not carried, it is hauled: the head stays on the floor and the
		-- haft trails BEHIND the direction of travel, so the fighter is visibly pulling it.
		if char.weapon and char.weapon.drag and f.onGround then
			local moving = math.abs(f.vx) > 1.5
			out.angle = D(-104) - (if moving then 0.30 else 0.10)
				- math.sin(t * 6 + f.index) * (if moving then 0.05 else 0.015)
			out.oy = -0.12
			out.drag = { scrape = if moving then math.min(1, math.abs(f.vx) / char.runSpeed) else 0 }
		end
		return out
	end
	if s == "shield" or s == "shielddrop" then out.angle = D(-100); return out end
	if s == "ledge" or s == "tether" then out.angle = D(-110); return out end
	if s == "knockdown" or s == "ko" then out.hide = true; return out end
	if s == "hitstun" or s == "tumble" then
		out.angle = D(-120) + math.sin(f.stateFrame * 0.7) * 0.5
		return out
	end
	if s == "air" or s == "helpless" or s == "recovery" then out.angle = D(-95); return out end
	if s == "groundpound" then out.angle = D(-90); return out end

	if s ~= "attack" or not move then
		return out
	end

	local m = move
	local st, act, rec, mf = f.startupEff, m.active, m.recovery, f.moveFrame
	local cat = categoryOf(m.id)
	if cat == "ult" then
		return ultimatePose(f, m, wid, out, t)
	end
	local byWeapon = SWING_BY_WEAPON[wid]
	local swing = (if byWeapon and cat then byWeapon[cat] else nil)
		or (if cat then SWINGS[cat] else nil)
		or SWINGS.jab

	-- charge hold: the weapon sits at the top of the windup and vibrates
	if m.charge and mf == st and f.charge > 0 then
		out.charge = math.min(1, f.charge / m.charge.maxHold)
		out.angle = if aimed then D(0) else swing.arc[1]
		out.angle += math.sin(f.charge * 0.6) * 0.05
		return out
	end

	if aimed then
		-- Aim forward, kick back on the shot, settle. The flash peaks exactly when the projectile
		-- leaves, which is the frame the engine spawns it.
		local fire = fireFrame(f)
		local since = mf - fire
		out.angle = D(0)
		if mf < fire then
			out.angle = D(-18) * (1 - mf / math.max(1, fire))       -- bringing it up
		elseif since >= 0 and since < 8 then
			local k = since / 8
			out.angle = D(22) * (1 - k) * (1 - k)                   -- recoil kick
			out.ox = -0.35 * (1 - k)
			out.flash = math.max(0, 1 - since / 3)
		end
		if aimed == "cast" and since >= -3 and since < 10 then
			out.flash = math.max(out.flash, 1 - math.abs(since) / 10)
		end
		return out
	end

	-- A swing: windup across startup, contact across the active frames, settle across recovery,
	-- timed by the SAME curve the body uses. Luau arrays are 1-indexed, so arc[0..2] is arc[1..3].
	local ph = Channels.swing(f, m)
	local from, to, k
	if ph.phase == "wind" then
		from = restOr0(wid); to = swing.arc[1]; k = ph.e
	elseif ph.phase == "strike" then
		from = swing.arc[1]; to = swing.arc[2]; k = ph.e
	else
		-- during the settle `e` already runs 1 -> 0 with an overshoot, so the weapon springs past
		-- its end pose and comes back exactly as the body does
		from = swing.arc[2]; to = swing.arc[3]; k = 1 - ph.e
	end
	out.angle = from + (to - from) * k

	if swing.thrust then
		out.ox = swing.thrust * (if mf > st and mf <= st + act then 1 else 0)
	end

	-- The trail smears behind the blade while it is actually live, and fades through recovery.
	if mf > st and mf <= st + act + math.min(rec, 8) then
		local past = if mf <= st + act then 1 else 1 - (mf - st - act) / math.min(rec, 8)
		out.trail = {
			from = out.angle - swing.trail * (if out.angle > from then -1 else 1),
			to = out.angle, alpha = past, heavy = swing.heavy == true,
		}
	end
	return out
end

WeaponPose.REST = REST
WeaponPose.categoryOf = categoryOf

return WeaponPose
