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
local WeaponPose = require(script.Parent.WeaponPose)
-- the generated art plus the Roblox-only weapons' (Shared/Weapons.luau)
local Art = require(game:GetService("ReplicatedStorage").Shared.Weapons).ART
local CosmeticArt = require(game:GetService("ReplicatedStorage").Shared.CosmeticArt)

local Weapons2D = {}

-- Blade length per weapon, used to size the swing trail. The JavaScript's REACH table.
local REACH: { [string]: number } = {
	Sword = 2.6, Scythe = 3.4, Blasters = 1.1, Grimoire = 0.9, Axe = 3.2, Pike = 5.9,
	Gauntlets = 1.0, Hammer = 3.7, Longbow = 1.2, Flail = 4.2, Shield = 1.3, Daggers = 1.7,
	Whip = WeaponPose.WHIP_HANDLE,                 -- the handle: the lash is drawn on beyond it
}
Weapons2D.REACH = REACH

-- The bullwhip's lash, in the weapon's own frame, as segments { x, y, length, thickness, angle,
-- colour } - weapons2d.js lashSegments exactly: eight along it, tapering, bent by `curl`, an
-- outline pass under the leather and a pale cracker on the tip.
local OUTLINE = "#120E16"
Weapons2D.LASH_SEGMENTS = 8
function Weapons2D.lashSegments(lash: any, palette: any): { any }
	local out = {}
	if not lash or not (lash.len > 0) then return out end
	local N, x0 = Weapons2D.LASH_SEGMENTS, WeaponPose.WHIP_HANDLE
	local col, tip = palette.primary or "#8A5A36", palette.accent or "#E8C58A"
	local amp = WeaponPose.LASH.amp
	local function at(t: number): (number, number)
		return x0 + lash.len * t, -lash.curl * amp * math.sin(math.pi * t) * (1 + 0.8 * t)
	end
	for pass = 0, 1 do
		for i = 0, N - 1 do
			local ax, ay = at(i / N)
			local bx, by = at((i + 1) / N)
			local dx, dy = bx - ax, by - ay
			local th = 0.22 - 0.12 * (i + 0.5) / N + (if pass == 0 then 0.125 else 0)
			table.insert(out, { ax, ay, math.sqrt(dx * dx + dy * dy) + (if pass == 0 then 0.0625 else 0.03), th,
				math.atan2(dy, dx), if pass == 0 then OUTLINE else col })
		end
	end
	local ex, ey = at(1)
	table.insert(out, { ex - 0.125, ey, 0.25, 0.16, 0, tip })
	return out
end

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

-- The weapon's drawn extent in its own frame (outline included), in studs. `awake` measures its
-- awakened form (Art.awakened), which is the same weapon with light added round it.
local boundsCache: { [string]: { number } } = {}
-- A drawn weapon's id names its art: `<weapon>`, `<weapon>:one` for one of a pair (Roblox only,
-- DualWield), and either with `@<skin>` for a weapon skin a player wears (Cosmetics; CosmeticArt).
-- A skin is the weapon's own grid in new colours, so where it lacks a form (a pair's single unit
-- for a weapon that is not paired) the unskinned form is used.
local function parse(weaponId: string): (string, boolean, string?)
	local named, skin = string.match(weaponId, "^([^@]+)@(.+)$")
	local name: string = named or weaponId
	local base = string.match(name, "^(.-):one$")
	return base or name, base ~= nil, skin
end
local function artOf(weaponId: string, awake: boolean?): { any }?
	local base, one, skin = parse(weaponId)
	local worn = skin and CosmeticArt[skin]
	if worn and worn.weapon == base then
		local form = if one then (if awake then worn.singleAwakened else worn.single) else nil
		if form then return form end
		if not one or not (Art.single and Art.single[base]) then return if awake then worn.awakened else worn.sprites end
	end
	if one then
		local single = if awake then Art.singleAwakened else Art.single
		if single and single[base] then return single[base] end
	end
	return if awake then Art.awakened[base] else Art.sprites[base]
end
function Weapons2D.baseOf(weaponId: string): string
	return (parse(weaponId))
end
-- The palette a worn skin colours its trail and glow with, or nil.
function Weapons2D.skinPalette(skin: string?): any
	local worn = skin and CosmeticArt[skin]
	return worn and worn.palette
end
function Weapons2D.bounds(weaponId: string, awake: boolean?): { number }?
	local key = if awake then "+" .. weaponId else weaponId
	local cached = boundsCache[key]
	if cached then
		return cached
	end
	local rects = artOf(weaponId, awake)
	if not rects then
		return nil
	end
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, r in rects do
		x0, y0 = math.min(x0, r[1]), math.min(y0, r[2])
		x1, y1 = math.max(x1, r[1] + r[3]), math.max(y1, r[2] + r[4])
	end
	boundsCache[key] = { x0, y0, x1, y1 }
	return boundsCache[key]
end

-- How to frame a weapon, lying flat, in a w x h pixel tile: the camera centre and a scale.
-- The scale is a whole multiple of 8 px per stud - the art's own pixel density - so every art
-- pixel lands on a whole number of screen pixels. Any other scale renders a mix of 1- and 2-pixel
-- cells and the pixel art shimmers. The old fixed window (1.5 +/- 3.5 studs) also cut the pike
-- off at the tile edge; this fits whatever the weapon's real extent is.
function Weapons2D.fit(weaponId: string, w: number, h: number, pad: number?): (number, number, number)
	local b = Weapons2D.bounds(weaponId) or { -1, -1, 1, 1 }
	local p = pad or 4
	local bw, bh = b[3] - b[1], b[4] - b[2]
	local raw = math.min((w - p * 2) / bw, (h - p * 2) / bh)
	local ppu = math.max(8, math.floor(raw / 8) * 8)
	return (b[1] + b[3]) / 2, (b[2] + b[4]) / 2, ppu
end

-- The art as ONE sprite (Canvas2D.sprite): a container Frame holding the rectangles, so a swinging
-- weapon moves one Frame a frame instead of re-placing all forty. Measured in Studio, 24 people with
-- swords in the lobby spent 2.6ms a frame re-placing weapon rectangles. The art is a pixel grid at
-- 8 cells a stud (every rectangle lies on it: tests/weapon-art.luau), so the cells below are exact,
-- and Canvas2D.eachSpriteRect maps them back to the art's own rectangles unchanged.
local CELL = 1 / 8
local spriteCache: { [string]: any } = {}
function Weapons2D.sprite(weaponId: string, awake: boolean?): any
	local key = if awake then "+" .. weaponId else weaponId
	local cached = spriteCache[key]
	if cached then
		return cached
	end
	local rects = artOf(weaponId, awake)
	local b = Weapons2D.bounds(weaponId, awake)
	if not rects or not b then
		return nil
	end
	local function cells(v: number): number
		return math.floor(v / CELL + 0.5)
	end
	local list = {}
	for i, r in rects do
		list[i] = { cells(r[1] - b[1]), cells(b[4] - (r[2] + r[4])), cells(r[3]), cells(r[4]), r[5], r[6] }
	end
	cached = { rects = list, x0 = b[1], y1 = b[4], cols = cells(b[3] - b[1]), rows = cells(b[4] - b[2]) }
	spriteCache[key] = cached
	return cached
end

-- Whether a pose shows the weapon awakened: through the wind-up and the active frames of its
-- ultimate, settling back to the everyday weapon as the recovery starts.
function Weapons2D.awake(pose: any): boolean
	return pose.ult ~= nil and pose.ult.phase ~= "end"
end

-- ---------------------------------------------------------------- draw ----
function Weapons2D.draw(c: any, weaponId: string?, palette: any, pose: any)
	if not weaponId then
		return
	end
	local rects = artOf(weaponId)
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
	-- In its ultimate the weapon is drawn awakened - its outline burning in its own glow - when
	-- that art exists; the everyday weapon otherwise.
	local awake = Weapons2D.awake(pose) and Art.awakened ~= nil and artOf(weaponId, true) ~= nil
	local sp = Weapons2D.sprite(weaponId, awake)
	Canvas2D.sprite(c, (if awake then "weapon+|" else "weapon|") .. weaponId, sp.rects, sp.x0, sp.y1, CELL, CELL, sp.cols, sp.rows)

	if pose.lash then
		for _, sg in Weapons2D.lashSegments(pose.lash, palette or {}) do
			Canvas2D.save(c); Canvas2D.translate(c, sg[1], sg[2]); Canvas2D.rotate(c, sg[5])
			Canvas2D.rect(c, 0, -sg[4] / 2, sg[3], sg[4], Canvas2D.hex(sg[6], WHITE), 1)
			Canvas2D.restore(c)
		end
	end
	if pose.charge > 0 then                          -- charging glows along the weapon
		local glow = Canvas2D.hex(palette.glow, WHITE)
		Canvas2D.rect(c, 0, -0.1, REACH[Weapons2D.baseOf(weaponId)] or 2, 0.2, glow, 0.25 + pose.charge * 0.5)
	end
	Canvas2D.restore(c)
end

-- The swing smear, drawn around the shoulder in the fighter's local frame. Fourteen steps of an
-- arc, widening and brightening toward the blade's current angle, so the streak reads as trailing
-- the weapon rather than leading it.
-- The swing trails players can wear (Cosmetics, type swing_trail; Roblox only): the colours the
-- arc's segments take in turn, from its tail to its tip.
Weapons2D.TRAILS = {
	trail_shadow = { "#2A2438", "#4A3F66" },
	trail_ember = { "#F2621B", "#FFB93F" },
	trail_frost = { "#9FE8FF", "#E6FBFF" },
	trail_glitch = { "#FF3CD8", "#3CFFE8", "#FFFFFF" },
	trail_rainbow = { "#FF3A3A", "#FF9A3C", "#FFE03C", "#5FD068", "#2FA8FF", "#8A3FE0" },
	trail_gold = { "#E8A61C", "#FFE07A" },
	trail_vipgold = { "#FFD24A", "#FFFFFF", "#E8A61C" },
} :: { [string]: { string } }

function Weapons2D.drawTrail(c: any, weaponId: string?, palette: any, trail: any, scale: number?, worn: string?)
	if not trail or not weaponId then
		return
	end
	local colours = worn and Weapons2D.TRAILS[worn]
	local r = (REACH[Weapons2D.baseOf(weaponId)] or 2.4) * (scale or 1)
	local steps = 14
	local a0, a1 = trail.from, trail.to
	local glow = Canvas2D.hex(palette.glow, Canvas2D.hex(palette.accent, WHITE))
	for i = 0, steps - 1 do
		local u = i / (steps - 1)
		local a = a0 + (a1 - a0) * u
		local rad = r * (0.55 + 0.45 * u)
		local thick = (if trail.heavy then 0.9 else 0.55) * (0.4 + 0.6 * u)
		local alpha = trail.alpha * (0.10 + 0.75 * u * u)
		local colour = if u > 0.82 then WHITE elseif colours then Canvas2D.hex(colours[i % #colours + 1], glow) else glow
		-- One segment of the arc, as a rectangle tangent to it. A Frame cannot be an arc, but
		-- fourteen short tangents around a circle is what an arc looks like at this size anyway.
		Canvas2D.save(c)
		Canvas2D.rotate(c, a)
		Canvas2D.rect(c, rad - thick * 0.5, -thick * 0.5, thick, thick, colour, alpha)
		Canvas2D.restore(c)
	end
end

return Weapons2D
