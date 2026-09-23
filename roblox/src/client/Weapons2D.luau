--!strict
-- The weapon itself, drawn in its own local frame: grip at (0,0), pointing along +X, one unit =
-- one stud. WeaponPose.luau says where it is; this says what it looks like.
--
-- PIXEL ART, SHARED WITH THE WEB BUILD. Every weapon is a pixel grid in web/src/data/weaponArt.js,
-- compiled to merged rectangles [x, y, w, h, hex, alpha] and generated into Data/Art.luau as
-- `Art.sprites`. The web draws that list with fillRect and this draws it with Canvas2D.rect, so the
-- two builds now draw the same weapon. That ends a deliberate divergence: this file used to
-- approximate the web's polygons with rectangles and staircased triangles, because a Frame cannot
-- be a polygon - but every cell of a pixel grid is a rectangle, and a rectangle is exactly a Frame.
--
-- The outline is part of the art (a one-pixel ring baked into the grid), which replaces the old
-- contour pass that redrew the whole weapon dark and offset. Rectangle counts are held down by
-- merging; see weaponArt.js `merge` and the Frame budget checked in tests/weapon-art.luau.

local Canvas2D = require(script.Parent.Canvas2D)
local Art = require(game:GetService("ReplicatedStorage").Shared.Data.Art)

local Weapons2D = {}

-- Blade length per weapon, used to size the swing trail. The JavaScript's REACH table.
local REACH: { [string]: number } = {
	Sword = 2.6, Scythe = 3.4, Blasters = 1.1, Grimoire = 0.9, Axe = 3.2, Pike = 5.9,
	Gauntlets = 1.0, Hammer = 3.7, Longbow = 1.2, Flail = 4.2, Shield = 1.3, Daggers = 1.7,
}
Weapons2D.REACH = REACH

local WHITE = Color3.new(1, 1, 1)

-- Hex strings are resolved once per colour and cached by Canvas2D.hex, so drawing a sprite costs
-- one lookup per rectangle, not a parse.
local function drawSprite(c: any, rects: { any }, alpha: number)
	for _, r in rects do
		Canvas2D.rect(c, r[1], r[2], r[3], r[4], Canvas2D.hex(r[5], WHITE), r[6] * alpha)
	end
end
Weapons2D.drawSprite = function(c: any, weaponId: string, alpha: number?): boolean
	local rects = Art.sprites[weaponId]
	if not rects then
		return false
	end
	drawSprite(c, rects, alpha or 1)
	return true
end

-- ---------------------------------------------------------------- draw ----
function Weapons2D.draw(c: any, weaponId: string?, palette: any, pose: any)
	if not weaponId then
		return
	end
	local rects = Art.sprites[weaponId]
	if not rects or pose.hide then
		return
	end
	Canvas2D.save(c)
	-- The world transform already flips Y, so negating the angle here would flip it a second time
	-- and draw every weapon vertically mirrored - the spike (AirDown, hitbox below the feet) would
	-- point overhead.
	Canvas2D.rotate(c, pose.angle)
	Canvas2D.translate(c, pose.ox, pose.oy)
	if pose.scale ~= 1 then
		Canvas2D.scale(c, pose.scale, pose.scale)   -- Colossus doubles the blade
	end
	drawSprite(c, rects, 1)

	if pose.charge > 0 then                          -- charging glows along the weapon
		local glow = Canvas2D.hex(palette.glow, WHITE)
		Canvas2D.rect(c, 0, -0.1, REACH[weaponId] or 2, 0.2, glow, 0.25 + pose.charge * 0.5)
	end
	Canvas2D.restore(c)
end

-- The swing smear, drawn around the shoulder in the fighter's local frame. Fourteen steps of an
-- arc, widening and brightening toward the blade's current angle, so the streak reads as trailing
-- the weapon rather than leading it.
function Weapons2D.drawTrail(c: any, weaponId: string?, palette: any, trail: any, scale: number?)
	if not trail or not weaponId then
		return
	end
	local r = (REACH[weaponId] or 2.4) * (scale or 1)
	local steps = 14
	local a0, a1 = trail.from, trail.to
	local glow = Canvas2D.hex(palette.glow, Canvas2D.hex(palette.accent, WHITE))
	for i = 0, steps - 1 do
		local u = i / (steps - 1)
		local a = a0 + (a1 - a0) * u
		local rad = r * (0.55 + 0.45 * u)
		local thick = (if trail.heavy then 0.9 else 0.55) * (0.4 + 0.6 * u)
		local alpha = trail.alpha * (0.10 + 0.75 * u * u)
		local colour = if u > 0.82 then WHITE else glow
		-- One segment of the arc, as a rectangle tangent to it. A Frame cannot be an arc, but
		-- fourteen short tangents around a circle is what an arc looks like at this size anyway.
		Canvas2D.save(c)
		Canvas2D.rotate(c, a)
		Canvas2D.rect(c, rad - thick * 0.5, -thick * 0.5, thick, thick, colour, alpha)
		Canvas2D.restore(c)
	end
end

return Weapons2D
