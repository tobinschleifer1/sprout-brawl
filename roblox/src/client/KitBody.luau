--!strict
-- The jointed kit body shared by fighters and still portraits. The caller owns the art/LOD
-- and optional footwear; geometry and draw order live here so thumbnails cannot drift.
local Canvas2D = require(script.Parent.Canvas2D)
local Rig = require(script.Parent.Rig)
local KIT_PARTS = require(script.Parent.PostureArt).parts
local KitBody = {}
function KitBody.draw(c: any, h: number, PW: number, ch: any, p: any, half: boolean,
	kitPiece: (string, number, boolean?) -> (), foot: ((number, Rig.Limb) -> ())?, backHand: (() -> ())?)
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

	-- The right leg (2) is the far one, drawn first and shaded; the left (1) is nearer the camera,
	-- drawn over it and lit (PostureArt.NEAR_LIGHT).
	for _, i in { 2, 1 } do
		local leg = p.legs[i]
		limb(leg.x, leg.y, leg.pose, "thigh", "shin", i == 2)
		if foot then foot(i, leg.pose) end
	end
	Canvas2D.save(c)
	Canvas2D.translate(c, p.hipX, p.hipY)
	Canvas2D.rotate(c, p.hipRot)
	kitPiece("pelvis", h * 0.10 / KIT_PARTS.pelvis.span)
	Canvas2D.restore(c)
	limb(p.backX, p.backY, p.back, "upperarm", "forearm", true)
	-- what the rear hand holds sits behind the body with it (DualWield's second weapon)
	if backHand then backHand() end

	Canvas2D.save(c)
	Canvas2D.translate(c, p.hipX, p.hipY)
	Canvas2D.rotate(c, p.waistRot)
	Canvas2D.scale(c, ch.sx, ch.sy)
	kitPiece("abdomen", (h * 0.70 - h * 0.34) / 18)
	Canvas2D.restore(c)
	Canvas2D.save(c)
	Canvas2D.translate(c, p.waistX, p.waistY)
	Canvas2D.rotate(c, p.chestRot)
	Canvas2D.scale(c, p.chestSX, p.chestSY)
	kitPiece("chest", (h * 0.70 - h * 0.34) / 18)
	Canvas2D.restore(c)

	Canvas2D.save(c)
	Canvas2D.translate(c, p.headX, p.headY)
	Canvas2D.rotate(c, p.headRot)
	Canvas2D.scale(c, ch.sx, ch.sy)
	kitPiece("head", PW)
	Canvas2D.restore(c)
	limb(p.frontX, p.frontY, p.front, "upperarm", "forearm", false)
end
return KitBody
