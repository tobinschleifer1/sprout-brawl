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
local KitBody = require(script.Parent.KitBody)
local Expressions = require(script.Parent.Expressions)
local Movement = require(script.Parent.Movement)
local DualWield = require(script.Parent.DualWield)
local KickFx = require(script.Parent.KickFx)
local KIT_PARTS = PostureArt.parts
local Fighter = require(game:GetService("ReplicatedStorage").Shared.Fighter)

local BLACK = Color3.new(0, 0, 0)

local Effects = require(script.Parent.Effects)
local ShieldArt = require(script.Parent.ShieldArt)
local Fighter2D = {}
-- Screen pixels per kit cell below which a kit character is drawn at half resolution.
Fighter2D.KIT_LOD_PX = 1.3
-- Rocket Boots' art against a foot: the boot is drawn at this fraction of its art's size.
Fighter2D.BOOT_SCALE = 0.55
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
-- Overlapping action on a held blade (Roblox only): the blade trails the hand by this fraction of
-- where the hand was LAG frames ago, so it drags into a swing and settles after the hand stops,
-- and dips as the body rises in a run. It turns about the grip: the hand never leaves it, and the
-- hitboxes are untouched. By weapon id; a weapon not listed is drawn exactly as posed.
-- Heavier and longer heads trail further; the daggers' short blades barely.
Fighter2D.OVERLAP = { Sword = 0.4, Scythe = 0.5, Axe = 0.45, Pike = 0.35, Daggers = 0.25 } :: { [string]: number }
local LAG, MAX_LAG, SNAP = 3, 0.3, 1.2
local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end
local function past(s: any): any
	local was = table.clone(s)
	was.moveFrame = math.max(0, (s.moveFrame or 0) - LAG)
	was.stateFrame = math.max(0, (s.stateFrame or 0) - LAG)
	was.frameCount = (s.frameCount or 0) - LAG
	was.x = s.x - (s.vx or 0) * LAG / 60
	return was
end
local function lagOf(k: number, s: any, char: any, was: any, turn: number): number
	-- More than SNAP in LAG frames is a cut between poses, not a swing; which way round the blade
	-- went is unknowable, so nothing trails it.
	local lag = if math.abs(turn) > SNAP then 0 else k * turn
	if s.state == "run" and s.onGround and char.avatar and char.avatar.kit then
		-- the body's own bounce: rising, the blade's weight holds its tip back down
		lag -= k * 0.9 * (Movement.bob(s, char) - Movement.bob(was, char))
	end
	return math.clamp(lag, -MAX_LAG, MAX_LAG)
end
function Fighter2D.bladeLag(s: any, char: any, move: any, t: number, wpose: any): number
	local k = Fighter2D.OVERLAP[if char.weapon then char.weapon.id else ""]
	-- an ultimate's cinematic holds its move frame while time runs on: nothing is moving to lag
	if not k or wpose.hide or (move and move.id == "Ultimate") then return 0 end
	local was = past(s)
	return lagOf(k, s, char, was, wrap(WeaponPose.For(was, char, move, t - LAG / 60).angle - wpose.angle))
end
-- The same for the second of a pair (DualWield): it trails where ITS hand was LAG frames ago.
function Fighter2D.offLag(s: any, char: any, move: any, t: number, wpose: any, off: any): number
	local k = Fighter2D.OVERLAP[if char.weapon then char.weapon.id else ""]
	if not k or not off or off.empty or wpose.hide or (move and move.id == "Ultimate") then return 0 end
	local was = past(s)
	local before = DualWield.For(was, char, move, WeaponPose.For(was, char, move, t - LAG / 60), 0, 0)
	-- (the past is rebuilt from the same move, so the same hand holds it then as now)
	if not before or not before.off then return 0 end
	return lagOf(k, s, char, was, wrap(before.off.angle - off.angle))
end
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
	-- What the fighter wears (Inventory loadout, set on the char by the client; Roblox only): a weapon
	-- skin draws the weapon's own grid in its colours, and colours the trail and glow too.
	local worn = char.cosmetics
	local skin = if worn and wid then worn.skins[wid] else nil
	local wpal = Weapons2D.skinPalette(skin) or char.weaponPalette or pal
	local scuff: any = nil

	-- A pair held one in each hand (DualWield): each hand draws one unit, and the second weapon
	-- goes where Posture put the hand that holds it - behind the body in the rear hand.
	local dual = if posture then posture.dual else nil
	local unitId = if dual and wid then wid .. ":one" else wid
	if unitId and skin then unitId ..= "@" .. skin end
	local function drawOff()
		local off = dual and dual.off
		if not off or off.empty or not wid then return end
		local pose = table.clone(wpose)
		pose.angle, pose.ox, pose.oy, pose.charge, pose.trail, pose.lash = off.angle, 0, 0, 0, nil, nil
		pose.angle += Fighter2D.offLag(s, char, move, t, wpose, off)
		pose.offhand = true -- (the second of the pair: the move's hitboxes are on the other one)
		Canvas2D.save(c)
		Canvas2D.translate(c, posture.offX, posture.offY)
		Canvas2D.rotate(c, -ch.lean)
		Weapons2D.draw(c, unitId :: string, wpal, pose)
		Canvas2D.restore(c)
	end
	-- a gait carries its own bounce, in step with the feet (Movement.bob)
	local bob = if posture and posture.bob ~= nil then posture.bob else ch.bob
	Canvas2D.save(c)
	Canvas2D.translate(c, 0, bob)
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
		KitBody.draw(c, h, PW, ch, p, half, kitPiece, function(i, L)
			-- Rocket Boots are worn (Roblox only): one boot on each foot, turned with its shin,
			-- instead of a weapon in the hand. The boot's art is anchored at the ankle.
			-- a striking kick throws its blast ahead and its exhaust behind (KickFx), under the boot
			local kick = posture and posture.kick
			if kick and kick.active[i] then
				local d = kick.dirs[i]
				KickFx.draw(c, L.ex, L.ey, d[1], d[2], kick.reach[i], kick.ignite)
			end
			if wid == "RocketBoots" and not wpose.hide then
				Canvas2D.save(c)
				Canvas2D.translate(c, L.ex, L.ey)
				Canvas2D.rotate(c, math.atan2(L.ey - L.jy, L.ex - L.jx) + math.pi / 2)
				-- the art's rows run down from the shaft to the sole: flipped so the shaft climbs the shin
				Canvas2D.scale(c, Fighter2D.BOOT_SCALE, -Fighter2D.BOOT_SCALE)
				-- one sprite a boot (the weapon-in-hand path), not a Frame per rectangle: ~95 each
				local sp = Weapons2D.sprite(unitId :: string)
				Canvas2D.sprite(c, "weapon|" .. (unitId :: string), sp.rects, sp.x0, sp.y1, 1 / 8, 1 / 8, sp.cols, sp.rows, if i == 2 then 0.85 else 1)
				Canvas2D.restore(c)
			end
		end, if dual and dual.off and dual.off.hand == "back" then drawOff else nil)
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

	-- a Chakram with both rings thrown has nothing in its hands (Roblox only: Snapshot `rings`)
	-- (and Rocket Boots are on the feet, drawn with the legs above, not in the hand)
	if wid and not wpose.hide and not (wid == "Chakram" and s.rings == 0) and wid ~= "RocketBoots" then
		if wpose.drag and s.onGround and platformTop then
			local rch = Weapons2D.REACH[wid] or 2.4
			local wx = s.x + (gx + math.cos(wpose.angle - ch.lean) * rch) * s.facing
			local wy = s.y + bob + gy + math.sin(wpose.angle - ch.lean) * rch
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
			Weapons2D.drawTrail(c, wid, wpal, wpose.trail, wpose.scale, worn and worn.trail)
			Canvas2D.restore(c)
		end
		Canvas2D.save(c)
		Canvas2D.translate(c, gx, gy)
		Canvas2D.rotate(c, -ch.lean)
		UltimateVfx.drawUltimate(c, wid, wpal, wpose, t)
		local lag = Fighter2D.bladeLag(s, char, move, t, wpose)
		if lag ~= 0 then
			local drawn: any = table.clone(wpose)
			drawn.angle += lag
			Weapons2D.draw(c, unitId, wpal, drawn)
		else
			Weapons2D.draw(c, unitId, wpal, wpose)
		end
		UltimateVfx.drawMuzzle(c, wid, wpal, wpose, t)
		Canvas2D.restore(c)
	end
	-- the front hand's second weapon, while the rear hand strikes, is the nearest thing drawn
	if dual and dual.off and dual.off.hand == "front" then drawOff() end
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
