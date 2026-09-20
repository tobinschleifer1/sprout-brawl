--!strict
-- A fighter's body: the rig half of `_fighter` in web/src/render2d/renderer2d.js.
--
-- The pose comes from Channels.luau, which is a parity-tested port of render2d/channels.js, so
-- every limb angle, lean, squash, smear and flash here is the same number the web build computes.
-- What is left in this file is only the painting: where the joints are and what order they are
-- drawn in.
--
-- STILL TO COME: the avatar's head shape, face and headgear (avatar2d.js), the weapon and its
-- swing (weapons2d.js), and hand-drawn character parts. The head is a plain box until then. None
-- of those change the skeleton - they hang off HIP, SHO and HEAD, which is why those three are
-- load-bearing and why they are the JavaScript's proportions rather than convenient ones.

local Canvas2D = require(script.Parent.Canvas2D)
local Channels = require(script.Parent.Channels)
local WeaponPose = require(script.Parent.WeaponPose)
local Weapons2D = require(script.Parent.Weapons2D)

local BLACK = Color3.new(0, 0, 0)
local SHIELD = Color3.fromRGB(159, 209, 232)

local Fighter2D = {}

local function sign(v: number): number
	return if v < 0 then -1 else 1
end

-- `a.ext` extends the limb along its own length. A thrust's reach has to come from somewhere, and
-- sliding the PROP forward off a fixed-length arm is what put the pike's grip further from the hand
-- than the fighter is tall. Extending the arm moves the hand, so the weapon travels with it.
local function arm(c: any, colour: Color3, r: number, len: number, a: any, h: number, front: boolean, alpha: number)
	local w = r * 0.34
	local L = h * 0.30 * (if a.ext ~= 0 then a.ext else 1)
	Canvas2D.save(c)
	Canvas2D.translate(c, if front then r * 0.55 else -r * 0.35, len)
	-- Arm channels are "direction the limb points, +X forward, +Y up", the same convention the
	-- weapon uses. The limb is drawn along local -Y, so pointing it at angle A needs rotate(A) -
	-- `a.z` already holds it. Negating it mirrors every channel-driven arm: a ledge hang (armL.z
	-- 2.9, meant to be overhead) draws pointing backwards and down.
	-- `a.x` is the across-the-body component; the run writes its whole arm swing into it.
	Canvas2D.rotate(c, a.z + a.x)
	Canvas2D.rect(c, -w / 2, -L, w, L, colour, alpha)
	Canvas2D.restore(c)
end

-- `s` is a decoded snapshot; `t` is wall clock, for the poses that breathe.
function Fighter2D.draw(c: any, s: any, char: any, t: number, platformTop: number?)
	if not s.alive or s.state == "ko" then
		return
	end
	-- `move` is not on the wire: everything the poses read off it is static weapon data the
	-- client already has, so it is looked up from moveId here.
	local move = if s.moveId then char.moves[s.moveId] else nil
	local ch = Channels.For(s, char, move, t)
	local wpose = WeaponPose.For(s, char, move, t)
	local wid = if char.weapon then char.weapon.id else nil
	if not ch.visible then
		return
	end

	local h, r = char.height, char.radius
	local pal = char.palette or {}
	local primary = Canvas2D.hex(pal.primary, Color3.fromRGB(210, 212, 220))
	local secondary = Canvas2D.hex(pal.secondary, Color3.fromRGB(150, 155, 170))
	local tertiary = Canvas2D.hex(pal.tertiary, Color3.fromRGB(96, 102, 120))

	-- Rotate about the body's centre, not its feet. Pivoting at the origin swings the whole drawing
	-- out of its own hurtbox - a tech roll spans a full body height below the floor, and an air
	-- dodge's centre swings several studs across. `rotPivot` is the fraction of height to pivot at,
	-- so knockdown keeps its deliberate feet-pivot.
	local function applyRigRot()
		if ch.rigRotZ ~= 0 then
			local pv = h * (if ch.rotPivot then ch.rotPivot else 0.5)
			Canvas2D.translate(c, 0, pv)
			Canvas2D.rotate(c, ch.rigRotZ * s.facing)
			Canvas2D.translate(c, 0, -pv)
		end
	end

	-- Smear: two ghosts of the body trailing the direction of travel, drawn before the fighter.
	-- Hand-drawn fighting games solve fast motion with smear frames, because at 60Hz a genuinely
	-- fast move is between frames more than it is on them.
	if ch.smear > 0.02 then
		-- Ghosts TRAIL. Using -facing puts both of them in front, so the streak leads the swing.
		local dir = if math.abs(s.vx) > 1 then sign(s.vx) else s.facing
		local dist = math.min(2.6, 0.7 + math.abs(s.vx) * 0.035) * ch.smear
		for g = 1, 2 do
			Canvas2D.save(c)
			local a = ch.opacity * ch.smear * (0.45 / g)
			Canvas2D.translate(c, s.x - dir * dist * g * 0.55, s.y + ch.yOff)
			Canvas2D.scale(c, s.facing, 1)
			applyRigRot()
			Canvas2D.rect(c, -r * 0.82, h * 0.06, r * 1.64, h * 0.72, primary, a)
			Canvas2D.restore(c)
		end
	end

	Canvas2D.save(c)
	Canvas2D.translate(c, s.x + ch.shakeX, s.y + ch.yOff)
	-- One drawing, both facings. Everything below is drawn facing +X and mirrored here, which is
	-- why a weapon that looked right for months can turn out to have been mirrored the whole time.
	Canvas2D.scale(c, s.facing, 1)
	applyRigRot()
	c.alpha = ch.opacity
	-- Every alpha passed to a primitive below is RELATIVE - Canvas2D multiplies it by c.alpha
	-- itself. Passing c.alpha through as well squares the opacity, which is invisible at full
	-- opacity and wrong everywhere it matters: an air dodge draws at 0.12 instead of 0.35.

	-- Ground shadow, tied to how far above the platform the fighter is, so height off the stage is
	-- readable without looking away from the fighter.
	if platformTop then
		local d = math.clamp(1 - (s.y - platformTop) / 14, 0.25, 1)
		Canvas2D.ellipse(c, 0, platformTop - s.y + 0.1, r * 1.25 * d, 0.45 * d, BLACK, 0.22)
	end

	local HIP, SHO = h * 0.34, h * 0.70
	local lw, ll = r * 0.42, HIP

	Canvas2D.save(c)
	Canvas2D.translate(c, 0, ch.bob)

	-- Legs, far one first and in the darker palette entry, which is where the depth in this art
	-- style comes from - there is no lighting to do it. The channels rotate them about the hip.
	local legs = { { ch.legL, -r * 0.30, 0.74 }, { ch.legR, r * 0.30, 1 } }
	for _, leg in legs do
		local rot, dx, shade = leg[1], leg[2], leg[3]
		Canvas2D.save(c)
		Canvas2D.translate(c, dx, HIP)
		Canvas2D.rotate(c, -rot)
		Canvas2D.rect(c, -lw / 2, -ll, lw, ll, tertiary, shade)
		Canvas2D.restore(c)
	end

	-- The torso carries the lean and the squash, so everything welded to it inherits both.
	Canvas2D.save(c)
	Canvas2D.translate(c, 0, HIP)
	Canvas2D.rotate(c, -ch.lean)
	Canvas2D.scale(c, ch.sx, ch.sy)

	-- Back arm, then torso, then head, then front arm and the weapon it is holding. The torso has
	-- to hide the far shoulder, and the front arm has to sit over the head.
	arm(c, secondary, r, SHO - HIP, ch.armL, h, false, 0.74)
	Canvas2D.rect(c, -r * 0.80, 0, r * 1.60, SHO - HIP, primary)

	-- The head is a plain box here; avatar2d.js owns its real shape, face and headgear. It takes
	-- the head channel at 0.4 as a nod rather than a full turn, as the JavaScript does.
	local HEAD = h * 0.78
	local hs = r * 1.15
	Canvas2D.save(c)
	Canvas2D.translate(c, 0, HEAD - HIP)
	Canvas2D.rotate(c, -ch.head * 0.4)
	Canvas2D.rect(c, -hs / 2, -hs * 0.15, hs, hs, primary)
	Canvas2D.restore(c)

	-- THE FRONT ARM IS DRIVEN BY THE WEAPON, not by armR.z, so the swing and the limb always
	-- agree. Posing the arm from the channels and then hanging the weapon off it is the same
	-- motion computed twice from two sources, and they disagree the moment a swing arc and a
	-- body pose are not the same curve - which is most of the moveset.
	local wpal = char.weaponPalette or pal
	local armAng = if wid then wpose.angle else ch.armR.z - math.pi / 2
	local ext = if ch.armR.ext ~= 0 then ch.armR.ext else 1
	arm(c, primary, r, SHO - HIP, { z = armAng + math.pi / 2, x = ch.armR.x, ext = ext }, h, true, 1)

	if wid and not wpose.hide then
		-- The hand is the far end of the arm, at the length the arm was actually drawn at, so a
		-- thrust's armR.ext carries the weapon with it instead of leaving the grip behind.
		local AL = h * 0.30 * ext
		local hx = r * 0.55 + math.cos(armAng) * AL
		local hy = (SHO - HIP) + math.sin(armAng) * AL
		-- The trail sweeps around the SHOULDER, not the hand: it is where the blade has been.
		if wpose.trail then
			Canvas2D.save(c)
			Canvas2D.translate(c, r * 0.55, SHO - HIP)
			Weapons2D.drawTrail(c, wid, wpal, wpose.trail, wpose.scale)
			Canvas2D.restore(c)
		end
		-- No rotation here. Weapons2D.draw applies pose.angle itself, and turning the frame by the
		-- arm angle first would apply it twice.
		Canvas2D.save(c)
		Canvas2D.translate(c, hx, hy)
		Weapons2D.draw(c, wid, wpal, wpose)
		Canvas2D.restore(c)
	end

	Canvas2D.restore(c)   -- torso
	Canvas2D.restore(c)   -- bob
	Canvas2D.restore(c)   -- fighter

	-- The shield bubble and the hit flash are drawn in world space around the fighter rather than
	-- welded to the rig: both are about the fighter rather than part of them, and neither should
	-- squash when the body does.
	if ch.bubble > 0 then
		Canvas2D.ellipse(c, s.x, s.y + h * 0.5,
			h * 0.62 * (0.55 + ch.bubble * 0.45), h * 0.62 * (0.55 + ch.bubble * 0.45),
			SHIELD, 0.30 + ch.bubble * 0.25)
	end
	if ch.tint then
		Canvas2D.rect(c, s.x - r, s.y, r * 2, h, Canvas2D.hex(ch.tint, BLACK), 0.5)
	end
	c.alpha = 1
end

return Fighter2D
