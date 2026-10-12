--!strict
-- A fighter's presentation. Channels/WeaponPose/Rig remain replay-held; Posture and PostureArt
-- add Roblox-only articulation. Each kit piece is transformed separately: Roblox Frames can
-- rotate and scale but cannot shear. The authored weapon grip and foot targets stay fixed.

local Canvas2D = require(script.Parent.Canvas2D)
local Channels = require(script.Parent.Channels)
local WeaponPose = require(script.Parent.WeaponPose)
local Weapons2D = require(script.Parent.Weapons2D)
local UltimateVfx = require(script.Parent.UltimateVfx)
local Avatar2D = require(script.Parent.Avatar2D)
local Posture = require(script.Parent.Posture)
local PostureArt = require(script.Parent.PostureArt)
local Secondary = require(script.Parent.Secondary)
local Rig = require(script.Parent.Rig)
local Expressions = require(script.Parent.Expressions)
local KIT_PARTS = PostureArt.parts
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
-- The match's stocks at its start, while FightScene draws the fight (nil otherwise): a fighter down to
-- their last of more than one looks determined (Expressions.luau).
Fighter2D.startStocks = nil :: number?
-- A brief flash over a fighter by index - a timed link's gold (FxPlayer.glows) - drawn the way the
-- hit flash is, as the fighter's own silhouette in the colour. Set each frame by FightScene.
Fighter2D.glows = nil :: any
local TEAMS = require(game:GetService("ReplicatedStorage").Shared.Data.Teams)
local TEAM_GLOW, TEAM_MARKER = TEAMS.glow, TEAMS.marker

local function sign(v: number): number
	return if v < 0 then -1 else 1
end

-- The legacy block body (no Roblox kit) still uses the authored one-piece limbs.
local function arm(c: any, colour: Color3, r: number, len: number, a: any, h: number, front: boolean, alpha: number)
	local w = r * 0.34
	local L = h * 0.30 * (if a.ext ~= 0 then a.ext else 1)
	Canvas2D.save(c)
	Canvas2D.translate(c, if front then r * 0.55 else -r * 0.35, len)
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
	-- Every preset and kit code uses the player's composed pixel art. PostureArt caches the
	-- additional waist cut and beveled joints without changing the shared kit/composer.
	local kitCode = if char.avatar and char.avatar.kit then char.avatar.code else nil
	local kitArt = if kitCode then PostureArt.sprites(kitCode) else nil
	local posture = if kitArt then Posture.For(ch, s, char, wpose, move, t) else nil
	local rigRot = if posture and posture.rigRotZ ~= nil then posture.rigRotZ else ch.rigRotZ
	local yOff = if posture and posture.yOff ~= nil then posture.yOff else ch.yOff

	-- Rotate about the body's centre, not its feet. Pivoting at the origin swings the whole drawing
	-- out of its own hurtbox - a tech roll spans a full body height below the floor, and an air
	-- dodge's centre swings several studs across. `rotPivot` is the fraction of height to pivot at,
	-- so knockdown keeps its deliberate feet-pivot.
	local function applyRigRot()
		if rigRot ~= 0 then
			local pv = h * (if ch.rotPivot then ch.rotPivot else 0.5)
			Canvas2D.translate(c, 0, pv)
			Canvas2D.rotate(c, rigRot * s.facing)
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
			Canvas2D.translate(c, s.x - dir * dist * g * 0.55, s.y + yOff)
			Canvas2D.scale(c, s.facing, 1)
			applyRigRot()
			Canvas2D.rect(c, -r * 0.82, h * 0.06, r * 1.64, h * 0.72, primary, a)
			Canvas2D.restore(c)
		end
	end

	Canvas2D.save(c)
	Canvas2D.translate(c, s.x + ch.shakeX, s.y + yOff)
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
	local trailingArt = if kitArt and not half then Secondary.art(kitCode :: string) else nil
	-- The hit flash (and the chill tint and a timed link's gold): a kit character flashes as ITSELF -
	-- each piece drawn again over the top in the colour - where that is cheap, which is where pictures
	-- are images (Canvas2D.imagesOn): one more image per piece. On the Frame fallback a tinted piece is
	-- a second copy of every one of its rectangles, ~185 Frames a fighter (259 at worst), built the
	-- first time it flashes in each colour and held for ten seconds - and held up continuously while
	-- chilled. That fallback is what the lowest devices run, and a hit is the busiest moment of a
	-- fight, so there the flash is one box over the fighter, as the block rig's has always been.
	local silhouette = ch.tint ~= nil and kitArt ~= nil and Canvas2D.imagesOn()
	-- The face (Expressions.luau): this frame's expression, held at least a few frames, and its head
	-- picture - unless at this size it would look exactly like the character's own face.
	local face, faceId = nil, nil
	if kitArt then
		local lastStock = Fighter2D.startStocks ~= nil and (Fighter2D.startStocks :: number) > 1 and s.stocks == 1
		faceId = Expressions.held(char, s, Expressions.of(s, move, half, lastStock))
		if faceId then
			local made = Expressions.head(kitCode :: string, faceId)
			if not (if half then made.sameHalf else made.sameFull) then
				face = made
			end
		end
	end
	local function kitPiece(id: string, ph: number, far: boolean?)
		local P = KIT_PARTS[id]
		local art = (kitArt :: any)[id]
		local list = if far then (if half then art.farHalf else art.farFull) else (if half then art.half else art.full)
		local k = if half then 2 else 1
		local key = `{kitCode}|{id}|{if far then "f" else ""}{if half then "h" else ""}`
		if id == "head" and face then
			list = if half then face.half else face.full
			key = `{kitCode}|head|{faceId}{if half then "h" else ""}`
		end
		if trailingArt and trailingArt.replacements[id] then
			list = if id == "head" and face then Secondary.head(trailingArt, faceId :: string) else trailingArt.replacements[id]
			key ..= "|cut"
		end
		Canvas2D.sprite(c, key, list, -P.ox * PW, P.oy * ph, PW * k, ph * k, math.ceil(P.w / k), math.ceil(P.h / k))
		if silhouette then
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
	local armAng = if wid then wpose.angle else ch.armR.z - math.pi / 2 + ch.armR.x
	local ext = if ch.armR.ext ~= 0 then ch.armR.ext else 1
	local hx = r * 0.55 + math.cos(armAng) * h * 0.30 * ext
	local hy = SHO - HIP + math.sin(armAng) * h * 0.30 * ext
	local gx, gy = Posture.torsoPoint(ch, h, hx, hy)
	local wpal = char.weaponPalette or pal
	local scuff: any = nil

	-- Endpoints are already in the fighter's frame. Width never inherits a torso squash or the
	-- length stretch of a segment: every arm/leg keeps the same number of PW-wide columns.
	local function seg(x0: number, y0: number, x1: number, y1: number, id: string, far: boolean)
		local dx, dy = x1 - x0, y1 - y0
		Canvas2D.save(c)
		Canvas2D.translate(c, x0, y0)
		Canvas2D.rotate(c, math.atan2(dy, dx) + math.pi / 2)
		kitPiece(id, math.sqrt(dx * dx + dy * dy) / KIT_PARTS[id].span, far)
		Canvas2D.restore(c)
	end
	local function limb(x: number, y: number, L: Rig.Limb, upper: string, lower: string, far: boolean)
		if half then
			seg(x, y, L.ex, L.ey, if upper == "thigh" then "leg" else "arm", far)
		else
			-- The lower segment's top edge tucks UNDER the upper's beveled end. Both pivots still
			-- meet exactly; the overlap is in the cached art, not an offset to the solved joints.
			seg(L.jx, L.jy, L.ex, L.ey, lower, far)
			seg(x, y, L.jx, L.jy, upper, far)
		end
	end

	Canvas2D.save(c)
	Canvas2D.translate(c, 0, ch.bob)
	if kitArt then
		local p = posture
		if trailingArt and trailingArt.full then
			local trail = Secondary.pose(trailingArt, p, ch, s, char)
			Canvas2D.save(c)
			Canvas2D.translate(c, trail.x, trail.y)
			Canvas2D.rotate(c, trail.rot)
			Canvas2D.scale(c, trail.sx, trail.sy)
			Canvas2D.sprite(c, `secondary|{kitCode}`, trailingArt.full, -2 * trail.pw, trail.ph,
				trail.pw, trail.ph, trailingArt.w, trailingArt.h)
			Canvas2D.restore(c)
		end
		for i, leg in p.legs do limb(leg.x, leg.y, leg.pose, "thigh", "shin", i == 1) end
		Canvas2D.save(c)
		Canvas2D.translate(c, p.hipX, p.hipY)
		Canvas2D.rotate(c, p.hipRot)
		kitPiece("pelvis", h * 0.10 / KIT_PARTS.pelvis.span)
		Canvas2D.restore(c)
		limb(p.backX, p.backY, p.back, "upperarm", "forearm", true)

		Canvas2D.save(c)
		Canvas2D.translate(c, p.hipX, p.hipY)
		Canvas2D.rotate(c, p.waistRot)
		Canvas2D.scale(c, ch.sx, ch.sy)
		kitPiece("abdomen", (SHO - HIP) / 18)
		Canvas2D.restore(c)
		Canvas2D.save(c)
		Canvas2D.translate(c, p.waistX, p.waistY)
		Canvas2D.rotate(c, p.chestRot)
		Canvas2D.scale(c, p.chestSX, p.chestSY)
		kitPiece("chest", (SHO - HIP) / 18)
		Canvas2D.restore(c)

		Canvas2D.save(c)
		Canvas2D.translate(c, p.headX, p.headY)
		Canvas2D.rotate(c, p.headRot)
		Canvas2D.scale(c, ch.sx, ch.sy)
		kitPiece("head", PW)
		Canvas2D.restore(c)
		limb(p.frontX, p.frontY, p.front, "upperarm", "forearm", false)
	else
		for _, leg in { { ch.legL, -r * 0.30, 0.74 }, { ch.legR, r * 0.30, 1 } } do
			Canvas2D.save(c)
			Canvas2D.translate(c, leg[2], HIP)
			Canvas2D.rotate(c, -leg[1])
			Canvas2D.rect(c, -r * 0.21, -HIP, r * 0.42, HIP, tertiary, leg[3])
			Canvas2D.restore(c)
		end
		Canvas2D.rect(c, -r * 0.56, HIP - h * 0.05, r * 1.12, h * 0.10, secondary)
		Canvas2D.save(c)
		Canvas2D.translate(c, 0, HIP)
		Canvas2D.rotate(c, -ch.lean)
		Canvas2D.scale(c, ch.sx, ch.sy)
		arm(c, secondary, r, SHO - HIP, ch.armL, h, false, 0.74)
		Canvas2D.rect(c, -r * 0.80, 0, r * 1.60, SHO - HIP, primary)
		Avatar2D.drawTorsoMark(c, avPal, r, SHO - HIP, feat)
		Canvas2D.save(c)
		Canvas2D.translate(c, 0, h * 0.78 - HIP)
		Canvas2D.rotate(c, -ch.head * 0.4)
		Avatar2D.drawHead(c, avPal, r * 1.15, feat)
		Canvas2D.restore(c)
		arm(c, primary, r, SHO - HIP, { z = armAng + math.pi / 2, x = 0, ext = ext }, h, true, 1)
		Canvas2D.restore(c)
	end

	if wid and not wpose.hide then
		if wpose.drag and s.onGround and platformTop then
			local rch = Weapons2D.REACH[wid] or 2.4
			local wx = s.x + (gx + math.cos(wpose.angle - ch.lean) * rch) * s.facing
			local wy = s.y + ch.bob + gy + math.sin(wpose.angle - ch.lean) * rch
			if wy < platformTop + 1.2 then
				scuff = { x = wx, y = platformTop }
				if Fighter2D.effects then
					Effects.dragDirt(Fighter2D.effects, wx, platformTop, s.facing, s.vx or 0, wpose.drag.scrape,
						pal.tertiary or "#606678", math.random)
				end
			end
		end
		-- The authored shoulder/grip still carry lean and squash as POINTS. The trail and weapon
		-- rotate outside the squash, just like the limbs: a sprite cannot rotate inside an axis scale.
		if wpose.trail then
			local tx, ty = Posture.torsoPoint(ch, h, r * 0.55, SHO - HIP)
			Canvas2D.save(c)
			Canvas2D.translate(c, tx, ty)
			Canvas2D.rotate(c, -ch.lean)
			Weapons2D.drawTrail(c, wid, wpal, wpose.trail, wpose.scale)
			Canvas2D.restore(c)
		end
		Canvas2D.save(c)
		Canvas2D.translate(c, gx, gy)
		Canvas2D.rotate(c, -ch.lean)
		UltimateVfx.drawUltimate(c, wid, wpal, wpose, t)
		Weapons2D.draw(c, wid, wpal, wpose)
		UltimateVfx.drawMuzzle(c, wid, wpal, wpose, t)
		Canvas2D.restore(c)
	end
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
	-- The hit flash as a box: the block rig always, and a kit character on the Frame fallback (see
	-- `silhouette` above for why).
	if ch.tint and not silhouette then
		Canvas2D.rect(c, s.x - r, s.y, r * 2, h, Canvas2D.hex(ch.tint, BLACK), 0.5)
	end
	c.alpha = 1
end

return Fighter2D
