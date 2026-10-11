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
local UltimateVfx = require(script.Parent.UltimateVfx)
local Avatar2D = require(script.Parent.Avatar2D)
local AvatarCompose = require(script.Parent.AvatarCompose)
local Rig = require(script.Parent.Rig)
local KIT_PARTS = require(game:GetService("ReplicatedStorage").Shared.Data.AvatarKit).parts
local Fighter = require(game:GetService("ReplicatedStorage").Shared.Fighter)

local BLACK = Color3.new(0, 0, 0)

local Effects = require(script.Parent.Effects)
local ShieldArt = require(script.Parent.ShieldArt)
local Fighter2D = {}
-- Screen pixels per kit cell below which a kit character is drawn at half resolution.
Fighter2D.KIT_LOD_PX = 1.3
-- The live effects state (Effects.new()) that a hauled weapon kicks dirt into; set by the client.
Fighter2D.effects = nil :: any
-- Team colour by fighter index in a team match, or nil: each fighter then stands in a disc of it
-- (web/src/data/teams.js TEAM_GLOW). Set by the client when a match starts.
Fighter2D.teamColours = nil :: any
-- A brief flash over a fighter by index - a timed link's gold (FxPlayer.glows) - drawn the way the
-- hit flash is, as the fighter's own silhouette in the colour. Set each frame by FightScene.
Fighter2D.glows = nil :: any
local TEAMS = require(game:GetService("ReplicatedStorage").Shared.Data.Teams)
local TEAM_GLOW, TEAM_MARKER = TEAMS.glow, TEAMS.marker

local function sign(v: number): number
	return if v < 0 then -1 else 1
end

-- `a.ext` extends the limb along its own length. A thrust's reach has to come from somewhere, and
-- sliding the PROP forward off a fixed-length arm is what put the pike's grip further from the hand
-- than the fighter is tall. Extending the arm moves the hand, so the weapon travels with it.
-- `kit`, when the fighter is a kit character, draws the limb's pixel art instead of the block; it
-- is handed the limb's drawn length so a thrust stretches the art with the arm.
local function arm(c: any, colour: Color3, r: number, len: number, a: any, h: number, front: boolean, alpha: number,
	kit: ((number) -> ())?, limb: ((number, number, Rig.Limb, string, string, boolean, boolean?) -> ())?)
	-- A kit body: upper arm and forearm at full detail, the elbow solved so the hand lands exactly on
	-- the weapon's grip (Rig.luau); the one-piece arm to the same hand at half. Either way drawn out of
	-- the torso's squash, which a Frame cannot shear.
	if limb then
		local sx = if front then r * 0.55 else -r * 0.35
		limb(sx, len, Rig.armPose(sx, len, a.z - math.pi / 2 + a.x, if a.ext ~= 0 then a.ext else 1, a.bend or 0, h),
			"upperarm", "forearm", not front, true)
		return
	end
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
	if kit then
		kit(L)
	else
		Canvas2D.rect(c, -w / 2, -L, w, L, colour, alpha)
	end
	Canvas2D.restore(c)
end

-- `s` is a decoded snapshot; `t` is wall clock, for the poses that breathe.
function Fighter2D.draw(c: any, s: any, char: any, t: number, platformTop: number?)
	if not s.alive or s.state == "ko" then
		return
	end
	-- `move` is not on the wire: everything the poses read off it is static weapon data the
	-- client already has, so it is looked up from moveId here.
	local move = Fighter.moveOf(char, s.moveId)        -- (the throw is no weapon's move)
	local ch = Channels.For(s, char, move, t)
	local glow = if Fighter2D.glows then Fighter2D.glows[s.index] else nil
	if glow and not ch.tint then ch.tint = glow.colour end     -- the pose's own flash wins
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
	local accent = Canvas2D.hex(pal.accent, Color3.fromRGB(240, 220, 150))
	-- The avatar shapes index a palette rather than take four arguments, because a head, a face, a
	-- hat and a chest mark each reach for a different subset of it.
	local avPal = {
		primary = primary, secondary = secondary, tertiary = tertiary, accent = accent,
		glow = Canvas2D.hex(pal.glow, accent),
	}
	local feat = Avatar2D.features(char.avatar)
	-- A kit character (AvatarKit) draws each puppet piece as its composed pixel art, one sprite per
	-- piece, in exactly the transforms the block rig uses.
	-- a kit body (every preset and every kit code) draws from its code (renderer2d.js)
	local kitCode = if char.avatar and char.avatar.kit then char.avatar.code else nil
	local kitArt = if kitCode then AvatarCompose.sprites(kitCode) else nil

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
	-- One kit cell is a twelfth of the head. Below about a screen pixel and a third it shimmers, so
	-- the half-resolution cut takes over (AvatarCompose.halve).
	local PW = r * 1.15 / 12
	local m = c.m
	local half = kitArt ~= nil and PW * math.sqrt(math.abs(m.a * m.d - m.b * m.c)) < Fighter2D.KIT_LOD_PX
	local function kitPiece(id: string, ph: number, far: boolean?)
		local P = KIT_PARTS[id]
		local art = (kitArt :: any)[id]
		local list = if far then (if half then art.farHalf else art.farFull) else (if half then art.half else art.full)
		local k = if half then 2 else 1
		local key = `{kitCode}|{id}|{if far then "f" else ""}{if half then "h" else ""}`
		Canvas2D.sprite(c, key, list, -P.ox * PW, P.oy * ph, PW * k, ph * k, math.ceil(P.w / k), math.ceil(P.h / k))
		if ch.tint then
			-- the hit flash: the same piece, in the flash colour, over itself
			Canvas2D.sprite(c, key .. "|" .. ch.tint, Canvas2D.tinted(list, ch.tint), -P.ox * PW, P.oy * ph, PW * k, ph * k,
				math.ceil(P.w / k), math.ceil(P.h / k), 0.6)
		end
	end
	-- Every alpha passed to a primitive below is RELATIVE - Canvas2D multiplies it by c.alpha
	-- itself. Passing c.alpha through as well squares the opacity, which is invisible at full
	-- opacity and wrong everywhere it matters: an air dodge draws at 0.12 instead of 0.35.

	-- Ground shadow, tied to how far above the platform the fighter is, so height off the stage is
	-- readable without looking away from the fighter.
	--
	-- Not while ragdolling through the air. A shadow says "there is ground under me and this is how
	-- far above it I am", which is useful information while you are jumping and is a lie while you
	-- are being launched off the stage - the thing the shadow is cast on is about to not be under
	-- you. It also rotates with the rig, because it is drawn inside the body's transform, so a
	-- tumbling fighter drags a spinning ellipse around with it.
	local ragdolling = s.tumbling and not s.onGround
	local team = if Fighter2D.teamColours then Fighter2D.teamColours[s.index] else nil
	if team and platformTop and s.onGround then
		local d = math.clamp(1 - (s.y - platformTop) / 14, 0.25, 1)
		Canvas2D.ellipse(c, 0, platformTop - s.y + 0.1, r * TEAM_GLOW.rx * d, TEAM_GLOW.ry * d, team, TEAM_GLOW.alpha)
	end
	if platformTop and not ragdolling then
		local d = math.clamp(1 - (s.y - platformTop) / 14, 0.25, 1)
		Canvas2D.ellipse(c, 0, platformTop - s.y + 0.1, r * 1.25 * d, 0.45 * d, BLACK, 0.22)
	end

	local HIP, SHO = h * 0.34, h * 0.70
	local lw, ll = r * 0.42, HIP

	-- Full detail: elbows and knees (Rig.luau). Each limb is two segments cut from the kit's limb
	-- art, the upper drawn first and the lower over the joint. Half detail - a fighter too small on
	-- screen for an elbow to read - keeps the one-piece limbs and their cheaper art.
	local jointed = kitArt ~= nil and not half
	-- one segment from (x0, y0) to (x1, y1), along its own line at exactly that length
	local function seg(x0: number, y0: number, x1: number, y1: number, id: string, far: boolean)
		local dx, dy = x1 - x0, y1 - y0
		Canvas2D.save(c)
		Canvas2D.translate(c, x0, y0)
		Canvas2D.rotate(c, math.atan2(dy, dx) + math.pi / 2)
		kitPiece(id, math.sqrt(dx * dx + dy * dy) / KIT_PARTS[id].span, far)
		Canvas2D.restore(c)
	end
	-- An ARM is solved in the torso's frame but drawn out of it: a segment rotated inside the torso's
	-- non-uniform squash is sheared, which a Frame cannot draw - the elbow came apart by a stud when
	-- a recovery's spin squeezed the body. The joints are carried through the lean and squash and the
	-- segments drawn between the carried points (renderer2d.js).
	local function torsoPoint(x: number, y: number): (number, number)
		local X, Y = x * ch.sx, y * ch.sy
		local cs, sn = math.cos(-ch.lean), math.sin(-ch.lean)
		return X * cs - Y * sn, X * sn + Y * cs + HIP
	end
	-- A direction at angle `a` in the torso's frame, carried through the same lean and squash: (cos a,
	-- sin a) mapped by R(-lean)·diag(sx, sy), as an angle - `a` plus the turn the squash gives it, so
	-- a trail's sweep keeps its winding where a bare atan2 would wrap (renderer2d.js).
	local function torsoAngle(a: number): number
		local cs, sn = math.cos(a), math.sin(a)
		return a - ch.lean + math.atan2((ch.sy - ch.sx) * sn * cs, ch.sx * cs * cs + ch.sy * sn * sn)
	end
	local function limb(rx: number, ry: number, L: Rig.Limb, upper: string, lower: string, far: boolean, inTorso: boolean?)
		local ax, ay, jx, jy, ex, ey = rx, ry, L.jx, L.jy, L.ex, L.ey
		if inTorso then
			ax, ay = torsoPoint(rx, ry)
			jx, jy = torsoPoint(L.jx, L.jy)
			ex, ey = torsoPoint(L.ex, L.ey)
			Canvas2D.save(c)
			Canvas2D.scale(c, 1 / ch.sx, 1 / ch.sy)
			Canvas2D.rotate(c, ch.lean)
			Canvas2D.translate(c, 0, -HIP)
		end
		if jointed then
			seg(ax, ay, jx, jy, upper, far)
			seg(jx, jy, ex, ey, lower, far)
		else
			-- half detail: the one-piece limb between the same carried points
			seg(ax, ay, ex, ey, if upper == "thigh" then "leg" else "arm", far)
		end
		if inTorso then
			Canvas2D.restore(c)
		end
	end
	-- A foot on the ground stays on it through the body's bob - unless the whole rig is rotated (a
	-- knockdown), when "down" is no longer the floor.
	local planted = s.onGround == true and ch.rigRotZ == 0

	Canvas2D.save(c)
	Canvas2D.translate(c, 0, ch.bob)

	-- Legs, far one first and in the darker palette entry, which is where the depth in this art
	-- style comes from - there is no lighting to do it. The channels rotate them about the hip.
	local legs = { { ch.legL, -r * 0.30, 0.74, ch.kneeL }, { ch.legR, r * 0.30, 1, ch.kneeR } }
	for _, leg in legs do
		local rot, dx, shade = leg[1], leg[2], leg[3]
		-- a kit leg at either detail: at half detail the one-piece leg aimed at the same planted foot,
		-- so the feet do not start riding the breathing as a fighter shrinks past the threshold
		if kitArt then
			limb(dx, HIP, Rig.legPose(dx, HIP, rot, ll, ch.bob, planted, leg[4] or 0), "thigh", "shin", shade < 1)
			continue
		end
		Canvas2D.save(c)
		Canvas2D.translate(c, dx, HIP)
		Canvas2D.rotate(c, -rot)
		if kitArt then
			kitPiece("leg", ll / KIT_PARTS.leg.span, shade < 1)
		else
			Canvas2D.rect(c, -lw / 2, -ll, lw, ll, tertiary, shade)
		end
		Canvas2D.restore(c)
	end

	-- The pelvis: a short block spanning both hip joints, drawn after the legs and before the
	-- torso so it covers where they attach. Without it the torso starts AT the hip and goes up,
	-- the legs hang from the hip and go down, and the joint is simply open - which is invisible
	-- standing still and reads as two detached limbs the moment the body rotates away from them.
	if kitArt then
		Canvas2D.save(c)
		Canvas2D.translate(c, 0, HIP)
		kitPiece("pelvis", h * 0.10 / KIT_PARTS.pelvis.span)
		Canvas2D.restore(c)
	else
		Canvas2D.rect(c, -r * 0.56, HIP - h * 0.05, r * 1.12, h * 0.10, secondary)
	end

	-- The torso carries the lean and the squash, so everything welded to it inherits both.
	Canvas2D.save(c)
	Canvas2D.translate(c, 0, HIP)
	Canvas2D.rotate(c, -ch.lean)
	Canvas2D.scale(c, ch.sx, ch.sy)

	-- Back arm, then torso, then head, then front arm and the weapon it is holding. The torso has
	-- to hide the far shoulder, and the front arm has to sit over the head.
	local kitArm = if kitArt then function(far: boolean): (number) -> ()
		return function(L: number) kitPiece("arm", L / KIT_PARTS.arm.span, far) end
	end else nil
	arm(c, secondary, r, SHO - HIP, ch.armL, h, false, 0.74, if kitArm then kitArm(true) else nil, if kitArt then limb else nil)
	if kitArt then
		kitPiece("torso", (SHO - HIP) / KIT_PARTS.torso.span)
	else
		Canvas2D.rect(c, -r * 0.80, 0, r * 1.60, SHO - HIP, primary)
		Avatar2D.drawTorsoMark(c, avPal, r, SHO - HIP, feat)
	end

	-- The head: shape, face and headgear, all from the avatar, so a preset and a player-made
	-- character are drawn by the same code at the same moment. It takes the head channel at 0.4 as
	-- a nod rather than a full turn, as the JavaScript does.
	local HEAD = h * 0.78
	local hs = r * 1.15
	Canvas2D.save(c)
	Canvas2D.translate(c, 0, HEAD - HIP)
	Canvas2D.rotate(c, -ch.head * 0.4)
	if kitArt then
		kitPiece("head", PW)
	else
		Avatar2D.drawHead(c, avPal, hs, feat)
	end
	Canvas2D.restore(c)

	-- THE FRONT ARM IS DRIVEN BY THE WEAPON, not by armR.z, so the swing and the limb always
	-- agree. Posing the arm from the channels and then hanging the weapon off it is the same
	-- motion computed twice from two sources, and they disagree the moment a swing arc and a
	-- body pose are not the same curve - which is most of the moveset.
	local wpal = char.weaponPalette or pal
	local armAng = if wid then wpose.angle else ch.armR.z - math.pi / 2
	local ext = if ch.armR.ext ~= 0 then ch.armR.ext else 1
	-- An armed arm takes no `x` (the run's arm swing): the hand is where the weapon is, and the weapon
	-- never had it - the arm used to swing while the sword hung still, a hand-width off its grip.
	arm(c, primary, r, SHO - HIP, { z = armAng + math.pi / 2, x = if wid then 0 else ch.armR.x, ext = ext, bend = ch.armR.bend }, h, true, 1,
		if kitArm then kitArm(false) else nil, if kitArt then limb else nil)

	local scuff: any = nil
	if wid and not wpose.hide then
		-- The hand is the far end of the arm, at the length the arm was actually drawn at, so a
		-- thrust's armR.ext carries the weapon with it instead of leaving the grip behind.
		local AL = h * 0.30 * ext
		local hx = r * 0.55 + math.cos(armAng) * AL
		local hy = (SHO - HIP) + math.sin(armAng) * AL
		-- A hauled weapon scrapes: the head's world position is the hand plus the weapon's reach
		-- along its angle, so the dirt comes off where the axe meets the floor (see renderer2d.js).
		if wpose.drag and s.onGround and platformTop then
			local rch = Weapons2D.REACH[wid] or 2.4
			local wx = s.x + (hx + math.cos(wpose.angle) * rch) * s.facing
			local wy = s.y + HIP + hy + math.sin(wpose.angle) * rch
			if wy < platformTop + 1.2 then
				scuff = { x = wx, y = platformTop }
				if Fighter2D.effects then
					Effects.dragDirt(Fighter2D.effects, wx, platformTop, s.facing, s.vx or 0, wpose.drag.scrape,
						pal.tertiary or "#606678", math.random)
				end
			end
		end
		-- Drawn out of the torso's squash, like the arm holding it: rotated inside the non-uniform
		-- squash the weapon is sheared, which a Frame cannot draw - Canvas2D.sprite dropped the shear and
		-- a Shield air neutral put the sword 1.7 studs from the web's. The grip and every angle the
		-- drawing turns by (its own, the afterimages', the trail's ends) are carried through the lean
		-- and squash, and the weapon is drawn from there unsquashed: a rigid prop, which only its own
		-- uniform scale (Colossus) changes (renderer2d.js).
		local cw = table.clone(wpose)
		cw.angle = torsoAngle(wpose.angle)
		if wpose.ult and wpose.ult.blur then
			cw.ult = table.clone(wpose.ult)
			local blur = {}
			for i, a in wpose.ult.blur do blur[i] = torsoAngle(a) end
			cw.ult.blur = blur
		end
		local gx, gy = torsoPoint(hx, hy)
		Canvas2D.save(c)
		Canvas2D.scale(c, 1 / ch.sx, 1 / ch.sy)
		Canvas2D.rotate(c, ch.lean)
		Canvas2D.translate(c, 0, -HIP)
		-- The trail sweeps around the SHOULDER, not the hand: it is where the blade has been.
		if wpose.trail then
			local trail = table.clone(wpose.trail)
			trail.from, trail.to = torsoAngle(wpose.trail.from), torsoAngle(wpose.trail.to)
			local sx0, sy0 = torsoPoint(r * 0.55, SHO - HIP)
			Canvas2D.save(c)
			Canvas2D.translate(c, sx0, sy0)
			Weapons2D.drawTrail(c, wid, wpal, trail, wpose.scale)
			Canvas2D.restore(c)
		end
		-- No rotation here. Weapons2D.draw applies pose.angle itself, and turning the frame by the
		-- arm angle first would apply it twice.
		Canvas2D.save(c)
		Canvas2D.translate(c, gx, gy)
		UltimateVfx.drawUltimate(c, wid, wpal, cw, t)
		Weapons2D.draw(c, wid, wpal, cw)
		UltimateVfx.drawMuzzle(c, wid, wpal, cw, t)
		Canvas2D.restore(c)
		Canvas2D.restore(c)   -- out of the squash
	end

	Canvas2D.restore(c)   -- torso
	Canvas2D.restore(c)   -- bob
	Canvas2D.restore(c)   -- fighter
	if scuff then
		Canvas2D.rect(c, scuff.x - 0.5, scuff.y, 1.0, 0.22, tertiary, 0.5)
	end

	-- The shield bubble and the hit flash are drawn in world space around the fighter rather than
	-- welded to the rig: both are about the fighter rather than part of them, and neither should
	-- squash when the body does.
	-- The team chevron over the head, on the ground and in the air (renderer2d.js).
	local markerTeam = if Fighter2D.teamColours then Fighter2D.teamColours[s.index] else nil
	if markerTeam then
		local M = TEAM_MARKER
		local top = s.y + h + M.above
		Canvas2D.tri(c, s.x, top, s.x - M.w / 2, top + M.h, s.x + M.w / 2, top + M.h, markerTeam, M.alpha)
	end
	-- The shield: a pixel-art shell in the fighter's colour (ShieldArt), sized, flickering and
	-- flaring by the rule Shield.luau holds to the web.
	if ch.bubble > 0 then
		local hit = if Fighter2D.effects then Effects.shieldHit(Fighter2D.effects, s.index) else nil
		ShieldArt.draw(c, s.x, s.y + h * 0.5, h, ch.bubble, math.floor(t * 60), hit, ShieldArt.colourOf(s.index, Fighter2D.teamColours))
	end
	-- The hit flash. A kit character flashes as itself - each piece is drawn again in the flash
	-- colour over the top (see kitPiece) - so only the block rig still gets the box.
	if ch.tint and not kitArt then
		Canvas2D.rect(c, s.x - r, s.y, r * 2, h, Canvas2D.hex(ch.tint, BLACK), 0.5)
	end
	c.alpha = 1
end

return Fighter2D
