--!strict
-- The weapon itself, drawn in its own local frame: grip at (0,0), pointing along +X, one unit =
-- one stud. WeaponPose.luau says where it is; this says what it looks like.
--
-- HYBRID SHAPES, and a deliberate divergence from the web build. web/src/render2d/weapons2d.js
-- builds each weapon from five to nine arbitrary polygons with bevels and fullers. Roblox UI
-- cannot fill a polygon: Canvas2D.tri staircases one into six Frames, so a faithful sword is about
-- ninety-six Frames and four fighters with trails would run into the high hundreds every frame.
--
-- So mass is drawn as rotated rectangles - which a Frame IS, exactly, at no approximation - and a
-- staircased triangle is spent only where the silhouette genuinely needs a point: a blade tip, an
-- axe bit, a spear head. That is twelve to twenty Frames a weapon. At gameplay size what
-- distinguishes a hammer from an axe is the outline, not the bevel, and the outline is intact.
--
-- THE CONTOUR PASS IS NOT OPTIONAL. Every weapon is drawn twice: once flat in a dark value offset
-- back and down, then properly on top. At gameplay zoom a weapon is twenty to thirty pixels of
-- mid-grey against a sky of mid-grey, and without it the sword disappears into the backdrop the
-- moment it leaves the fighter's silhouette.

local Canvas2D = require(script.Parent.Canvas2D)

local Weapons2D = {}

-- Blade length per weapon, used to size the swing trail. The JavaScript's REACH table.
local REACH: { [string]: number } = {
	Sword = 2.6, Scythe = 3.4, Blasters = 1.1, Grimoire = 0.9, Axe = 3.2, Pike = 5.9,
	Gauntlets = 1.0, Hammer = 3.7, Longbow = 1.2, Flail = 4.2, Shield = 1.3, Daggers = 1.7,
}
Weapons2D.REACH = REACH

local CONTOUR = Color3.fromRGB(22, 18, 26)
local WHITE = Color3.new(1, 1, 1)

-- A resolved palette: the shared data layer stores CSS hex strings, as the web build reads them.
type Pal = { primary: Color3, secondary: Color3, tertiary: Color3, accent: Color3, glow: Color3, hilt: Color3 }

local function resolve(p: any): Pal
	local primary = Canvas2D.hex(p.primary, Color3.fromRGB(210, 212, 220))
	local secondary = Canvas2D.hex(p.secondary, Color3.fromRGB(150, 155, 170))
	local tertiary = Canvas2D.hex(p.tertiary, Color3.fromRGB(96, 102, 120))
	local accent = Canvas2D.hex(p.accent, Color3.fromRGB(240, 220, 150))
	return {
		primary = primary, secondary = secondary, tertiary = tertiary, accent = accent,
		glow = Canvas2D.hex(p.glow, accent),
		hilt = Canvas2D.hex(p.hilt, secondary),
	}
end

-- One flat colour for the contour pass, so a shape function can draw its own silhouette.
local function flat(c: Color3): Pal
	return { primary = c, secondary = c, tertiary = c, accent = c, glow = c, hilt = c }
end

-- ---------------------------------------------------------------- the twelve ----
-- Each takes the canvas, a resolved palette, and the weapon's length. Points use `tri`; everything
-- else is a rectangle, which a Frame reproduces exactly under rotation and mirroring.

local function sword(c: any, p: Pal, L: number)
	Canvas2D.rect(c, -0.5, -0.16, 0.5, 0.32, p.tertiary)              -- grip
	Canvas2D.rect(c, -0.68, -0.14, 0.26, 0.28, p.secondary)           -- pommel
	Canvas2D.rect(c, -0.10, -0.60, 0.22, 1.20, p.secondary)           -- crossguard
	Canvas2D.rect(c, 0.14, -0.19, L - 0.59, 0.38, p.primary)          -- blade
	Canvas2D.tri(c, L, 0, L - 0.45, -0.19, L - 0.45, 0.19, p.primary) -- and its point
	Canvas2D.rect(c, 0.14, -0.06, L - 0.64, 0.12, p.accent)           -- fuller
end

local function scythe(c: any, p: Pal, L: number)
	Canvas2D.rect(c, -0.7, -0.11, L + 0.7, 0.22, p.tertiary)          -- shaft
	Canvas2D.rect(c, L - 0.22, -0.2, 0.32, 0.4, p.secondary)          -- tang
	-- The crescent, as three stepped segments sweeping back from the head. An arc is not a Frame,
	-- and a curve this big reads from its taper rather than its smoothness.
	Canvas2D.rect(c, L - 0.30, -1.30, 0.34, 1.20, p.primary)
	Canvas2D.rect(c, L - 0.95, -1.52, 0.70, 0.34, p.primary)
	Canvas2D.tri(c, L - 1.65, -1.15, L - 0.95, -1.52, L - 0.95, -1.18, p.primary)
	Canvas2D.rect(c, L - 0.26, -1.24, 0.12, 1.06, p.accent)           -- the edge
end

local function blaster(c: any, p: Pal, _L: number)
	Canvas2D.rect(c, -0.34, -0.30, 0.76, 0.36, p.primary)             -- slide
	Canvas2D.rect(c, -0.30, -0.26, 0.66, 0.10, p.accent)              -- top rail
	Canvas2D.rect(c, 0.30, -0.20, 0.62, 0.22, p.secondary)            -- barrel
	Canvas2D.rect(c, 0.10, -0.42, 0.12, 0.14, p.secondary)            -- the sight
	Canvas2D.rect(c, -0.30, 0.02, 0.32, 0.60, p.primary)              -- grip
	Canvas2D.rect(c, 0.06, 0.04, 0.24, 0.08, p.tertiary)              -- trigger guard
end

local function grimoire(c: any, p: Pal, _L: number)
	Canvas2D.rect(c, -0.55, -0.72, 1.17, 1.44, p.primary)             -- cover
	Canvas2D.rect(c, -0.55, -0.72, 1.17, 0.14, p.accent)              -- lit edge
	Canvas2D.rect(c, 0.50, -0.58, 0.28, 1.16, Color3.fromRGB(240, 231, 210))  -- pages
	Canvas2D.rect(c, -0.66, -0.70, 0.16, 1.40, p.tertiary)            -- spine
	Canvas2D.rect(c, 0.44, -0.30, 0.26, 0.16, p.secondary)            -- clasps
	Canvas2D.rect(c, 0.44, 0.14, 0.26, 0.14, p.secondary)
	Canvas2D.circle(c, 0.05, 0, 0.24, p.glow)
	Canvas2D.circle(c, 0.05, 0, 0.12, WHITE, 0.55)
end

local function axe(c: any, p: Pal, L: number)
	Canvas2D.rect(c, -0.85, -0.14, L + 0.65, 0.28, p.hilt)            -- haft
	Canvas2D.rect(c, -0.95, -0.22, 0.25, 0.44, p.secondary)           -- butt cap
	Canvas2D.rect(c, 0.1, -0.2, 0.24, 0.4, p.secondary)               -- grip wrap
	local h = L - 0.5
	-- The head: a broad bearded blade biting forward. The bit is the one shape on this weapon that
	-- has to read, so it gets the triangles.
	Canvas2D.rect(c, h, -0.9, 0.62, 1.8, p.primary)
	Canvas2D.tri(c, L + 0.5, 0.1, h + 0.5, -1.25, L + 0.34, -0.9, p.primary)
	Canvas2D.tri(c, h + 0.62, 1.1, L + 0.5, 0.1, h + 0.62, 0.1, p.primary)
	Canvas2D.rect(c, L + 0.18, -0.9, 0.16, 1.5, p.accent)             -- the bright edge along the bite
	Canvas2D.tri(c, h - 0.28, 0, h + 0.1, -0.3, h + 0.1, 0.3, p.secondary)  -- reverse spike
end

local function pike(c: any, p: Pal, L: number)
	Canvas2D.rect(c, -1.5, -0.09, L + 0.9, 0.18, p.primary)           -- haft
	Canvas2D.rect(c, -1.62, -0.16, 0.26, 0.32, p.secondary)           -- counterweight
	for i = 0, 2 do                                                    -- binding rings
		local x = -0.9 + i * 1.15
		Canvas2D.rect(c, x, -0.13, 0.16, 0.26, p.tertiary)
	end
	Canvas2D.rect(c, 0.55, -0.15, 0.95, 0.30, p.tertiary)             -- the leather grip
	Canvas2D.rect(c, L - 0.75, -0.2, 0.45, 0.4, p.secondary)          -- langets
	Canvas2D.tri(c, L + 0.55, 0, L - 0.35, -0.26, L - 0.35, 0.26, p.accent)  -- the head
end

local function gauntlets(c: any, p: Pal, _L: number)
	Canvas2D.rect(c, -0.5, -0.32, 0.68, 0.64, p.secondary)            -- bracer
	Canvas2D.rect(c, -0.5, -0.30, 0.68, 0.12, p.accent)               -- lit edge
	Canvas2D.rect(c, 0.14, -0.38, 0.72, 0.76, p.primary)              -- fist
	Canvas2D.tri(c, 0.94, 0, 0.86, -0.34, 0.86, 0.34, p.primary)
	for i = 0, 2 do                                                    -- knuckles
		Canvas2D.rect(c, 0.66, -0.26 + i * 0.22, 0.26, 0.10, p.glow)
	end
end

local function hammer(c: any, p: Pal, L: number)
	Canvas2D.rect(c, -1.1, -0.15, L + 0.85, 0.30, p.hilt)             -- haft
	Canvas2D.rect(c, -1.24, -0.24, 0.28, 0.48, p.secondary)           -- butt cap
	local h = L - 0.55
	Canvas2D.rect(c, h, -1.05, L + 0.62 - h, 2.10, p.primary)         -- the head, a slab
	Canvas2D.rect(c, h, -1.05, L + 0.62 - h, 0.50, WHITE, 0.20)       -- lit top
	Canvas2D.rect(c, h, 0.55, L + 0.62 - h, 0.50, CONTOUR, 0.30)      -- shaded bottom
	Canvas2D.rect(c, L + 0.55, -1.05, 0.14, 2.10, p.accent)           -- the face
	Canvas2D.tri(c, h - 0.62, 0, h, -0.42, h, 0.42, p.secondary)      -- reverse spike
end

local function longbow(c: any, p: Pal, L: number)
	-- Two limbs and a string. The string is the read: it is the only straight line on the weapon,
	-- and it is what says the bow is drawn.
	Canvas2D.rect(c, 0.62, -0.42, 0.40, 0.84, p.secondary)            -- the grip
	Canvas2D.rect(c, 0.72, -L, 0.20, L, p.primary)                    -- upper limb
	Canvas2D.rect(c, 0.72, 0, 0.20, L, p.primary)                     -- lower limb
	Canvas2D.rect(c, 0.36, -L - 0.04, 0.40, 0.18, p.primary)          -- and their tips, angled in
	Canvas2D.rect(c, 0.36, L - 0.14, 0.40, 0.18, p.primary)
	Canvas2D.rect(c, 0.08, -L, 0.06, L * 2, p.accent)                 -- the string
end

local function flail(c: any, p: Pal, L: number)
	Canvas2D.rect(c, -0.9, -0.14, 1.25, 0.28, p.hilt)                 -- handle
	Canvas2D.rect(c, -1.02, -0.2, 0.22, 0.4, p.secondary)
	local links, span = 5, L - 1.0
	for i = 0, links - 1 do                                            -- the chain, as links: a
		local x = 0.4 + (i / links) * span                             -- smooth line reads as a
		local w = span / links * 0.7                                   -- stick, and a stick is the pike
		Canvas2D.rect(c, x, -0.11, w, 0.22, if i % 2 == 1 then p.tertiary else p.secondary)
	end
	local bx = L + 0.1
	Canvas2D.circle(c, bx, 0, 0.52, p.primary)                        -- the ball
	Canvas2D.circle(c, bx - 0.14, -0.14, 0.2, WHITE, 0.28)
	for i = 0, 5 do                                                    -- spikes
		local a = (i / 6) * math.pi * 2 + 0.3
		Canvas2D.rect(c, bx + math.cos(a) * 0.45 - 0.07, math.sin(a) * 0.45 - 0.07, 0.14, 0.14, p.accent)
	end
end

local function shieldWeapon(c: any, p: Pal, L: number)
	-- A kite shield, drawn ACROSS the arm rather than along it, because that is how one is carried.
	Canvas2D.rect(c, -0.36, -L * 0.82, 1.08, L * 1.64, p.primary)
	Canvas2D.tri(c, -0.2, -L, -0.36, -L * 0.82, 0.5, -L * 0.82, p.primary)
	Canvas2D.tri(c, -0.2, L, -0.36, L * 0.82, 0.5, L * 0.82, p.primary)
	Canvas2D.rect(c, -0.36, -L * 0.82, 1.08, 0.16, p.accent)          -- rim, catching the light
	Canvas2D.circle(c, 0.22, 0, 0.3, p.secondary)                     -- the boss
	Canvas2D.circle(c, 0.22, 0, 0.14, p.glow)
end

local function daggers(c: any, p: Pal, L: number)
	-- TWO blades, offset, because one dagger is a short sword. The silhouette has to say "a pair".
	Canvas2D.rect(c, -0.62, -0.10, 0.46, 0.20, p.tertiary)            -- back grip
	Canvas2D.rect(c, -L * 0.62, -0.05, L * 0.62 - 0.05, 0.10, Color3.fromRGB(160, 172, 190))
	Canvas2D.tri(c, -L * 0.78, 0, -L * 0.62, -0.05, -L * 0.62, 0.05, Color3.fromRGB(160, 172, 190))
	Canvas2D.rect(c, -0.5, -0.13, 0.5, 0.26, p.secondary)             -- front grip
	Canvas2D.rect(c, -0.08, -0.26, 0.18, 0.52, p.tertiary)            -- guard
	Canvas2D.rect(c, 0.1, -0.15, L - 0.38, 0.30, p.primary)           -- front blade
	Canvas2D.tri(c, L, 0, L - 0.28, -0.13, L - 0.28, 0.13, p.primary)
	Canvas2D.rect(c, 0.2, -0.025, L - 0.44, 0.05, p.glow)             -- the edge line
end

type Shape = (any, Pal, number) -> ()
local SHAPES: { [string]: { draw: Shape, L: number } } = {
	Sword = { draw = sword, L = 2.35 },
	Scythe = { draw = scythe, L = 2.9 },
	Blasters = { draw = blaster, L = 0 },
	Grimoire = { draw = grimoire, L = 0 },
	Axe = { draw = axe, L = 2.9 },
	Pike = { draw = pike, L = 5.4 },
	Gauntlets = { draw = gauntlets, L = 0 },
	Hammer = { draw = hammer, L = 3.1 },
	Longbow = { draw = longbow, L = 1.5 },
	Flail = { draw = flail, L = 3.6 },
	Shield = { draw = shieldWeapon, L = 1.5 },
	Daggers = { draw = daggers, L = 1.5 },
}

-- ---------------------------------------------------------------- draw ----
function Weapons2D.draw(c: any, weaponId: string?, palette: any, pose: any)
	if not weaponId then
		return
	end
	local shape = SHAPES[weaponId]
	if not shape or pose.hide then
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

	-- The contour pass. See the note at the top: an outline stroke will not do it, because these
	-- shapes are separate pieces with no common path; re-running the shape in one flat colour
	-- gives a true silhouette for free.
	Canvas2D.save(c)
	Canvas2D.translate(c, -0.11, -0.11)
	shape.draw(c, flat(CONTOUR), shape.L)
	Canvas2D.restore(c)

	shape.draw(c, resolve(palette), shape.L)

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
