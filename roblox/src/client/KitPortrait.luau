--!strict
-- Still pictures of kit characters: the creator's option tiles, its slot chips, anything that
-- shows a character without animating one.
--
-- The same composed pieces (AvatarCompose) the fighter is drawn from, laid on the rig's standing
-- proportions (Fighter2D's HIP, SHO, HEAD and limb lengths at the base stat line) rather than
-- posed by the channels: a thumbnail has no state to pose from, and the stand is what a player
-- recognises. Both functions draw into whatever transform the canvas has, with y up.

local Canvas2D = require(script.Parent.Canvas2D)
local AvatarCompose = require(script.Parent.AvatarCompose)
local KIT: any = require(game:GetService("ReplicatedStorage").Shared.Data.AvatarKit)

local KitPortrait = {}

local H, R = 5.2, 1.1                    -- Data/Avatars BASE: every character is this size
local HIP, SHO, HEADY = H * 0.34, H * 0.70, H * 0.78
local PW = R * 1.15 / 12
KitPortrait.HEIGHT = H

local function piece(c: any, code: string, id: string, list: any, ph: number, tag: string)
	local P = KIT.parts[id]
	Canvas2D.sprite(c, `{code}|{id}|{tag}`, list, -P.ox * PW, P.oy * ph, PW, ph, P.w, P.h)
end

-- The whole character standing, feet at (x, y), `k` canvas units per stud.
function KitPortrait.figure(c: any, code: string, x: number, y: number, k: number)
	local art = AvatarCompose.sprites(code)
	Canvas2D.save(c)
	Canvas2D.translate(c, x, y)
	Canvas2D.scale(c, k, k)
	local function at(dx: number, dy: number, rot: number, fn: () -> ())
		Canvas2D.save(c)
		Canvas2D.translate(c, dx, dy)
		Canvas2D.rotate(c, rot)
		fn()
		Canvas2D.restore(c)
	end
	local L = H * 0.30
	at(-R * 0.30, HIP, -0.12, function() piece(c, code, "leg", art.leg.farFull, HIP / KIT.parts.leg.span, "sf") end)
	at(R * 0.30, HIP, 0.12, function() piece(c, code, "leg", art.leg.full, HIP / KIT.parts.leg.span, "sn") end)
	at(0, HIP, 0, function() piece(c, code, "pelvis", art.pelvis.full, H * 0.10 / KIT.parts.pelvis.span, "s") end)
	at(-R * 0.35, SHO, -0.18, function() piece(c, code, "arm", art.arm.farFull, L / KIT.parts.arm.span, "sf") end)
	at(0, HIP, 0, function() piece(c, code, "torso", art.torso.full, (SHO - HIP) / KIT.parts.torso.span, "s") end)
	at(0, HEADY, 0, function() piece(c, code, "head", art.head.full, PW, "s") end)
	at(R * 0.55, SHO, 0.22, function() piece(c, code, "arm", art.arm.full, L / KIT.parts.arm.span, "sn") end)
	Canvas2D.restore(c)
end

-- The head alone, its neck joint at (x, y).
function KitPortrait.head(c: any, code: string, x: number, y: number, k: number)
	local art = AvatarCompose.sprites(code)
	Canvas2D.save(c)
	Canvas2D.translate(c, x, y)
	Canvas2D.scale(c, k, k)
	piece(c, code, "head", art.head.full, PW, "s")
	Canvas2D.restore(c)
end

-- Where to put a picture so it fills a w x h screen box (y down, like every GUI): the transform to
-- install and the feet or neck point to draw at. A figure is framed on its full height plus
-- headroom for a tall hat; a head on its 18 x 20 canvas.
function KitPortrait.frame(c: any, view: string, w: number, h: number)
	if view == "head" then
		local P = KIT.parts.head
		local k = math.min(w / (P.w * PW), h / (P.h * PW)) * 0.92
		Canvas2D.setTransform(c, k, 0, 0, -k, w / 2, h / 2 + (P.h / 2 - (P.h - P.oy)) * PW * k)
		return
	end
	local k = h / (H + 1.4) * 0.94
	Canvas2D.setTransform(c, k, 0, 0, -k, w / 2, h - 0.35 * k)
end

-- A tile's whole draw: frame, picture, finish (purging what the previous picture left).
function KitPortrait.draw(c: any, code: string, view: string, w: number, h: number)
	KitPortrait.frame(c, view, w, h)
	if view == "head" then
		KitPortrait.head(c, code, 0, 0, 1)
	else
		KitPortrait.figure(c, code, 0, 0, 1)
	end
	Canvas2D.finish(c, true)
end

return KitPortrait
