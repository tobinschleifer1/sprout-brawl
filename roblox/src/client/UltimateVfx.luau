--!strict
-- The parts of an ultimate that are not the weapon itself: the sword's burning edge, the
-- scythe's crushing moon, the blasters' rifle conversion, axe afterimages, the pike's lane, the
-- grimoire's rune stack, and the muzzle/cast burst.
--
-- This is the drawing half of web/src/render2d/weapons2d.js `drawUltimate` and `drawMuzzle`.
-- WeaponPose.luau supplies the same U.* values as the JavaScript; this module only paints them.
--
-- CURVE APPROXIMATION. Canvas2D can fill a circle but cannot stroke one. The web renderer's thin
-- rings are therefore short rotated rectangles tangent to the circle. Unlike a filled translucent
-- disk, the segmented ring leaves the dark centre readable, and twelve Frames is still honest for
-- a one-fighter-at-a-time effect. Straight lines and filled circles remain exact.

local Canvas2D = require(script.Parent.Canvas2D)

local UltimateVfx = {}

local WHITE = Color3.new(1, 1, 1)
local VIOLET = Color3.fromRGB(179, 107, 255)
local VIOLET_DARK = Color3.fromRGB(21, 11, 34)
local VIOLET_EDGE = Color3.fromRGB(199, 155, 255)
local VIOLET_SPARK = Color3.fromRGB(228, 204, 255)
local GRIT = Color3.fromRGB(107, 90, 68)
local RED = Color3.fromRGB(255, 74, 74)
local MUZZLE = Color3.fromRGB(255, 243, 208)

local REACH: { [string]: number } = {
	Sword = 2.6, Scythe = 3.4, Blasters = 1.1, Grimoire = 0.9, Axe = 3.2, Pike = 5.9,
	Gauntlets = 1.0, Hammer = 3.7, Longbow = 1.2, Flail = 4.2, Shield = 1.3, Daggers = 1.7,
}

local function nonzero(v: any): boolean
	-- JavaScript branches on truthiness. Zero is truthy in Luau, so `if v` is not the same test.
	return v ~= nil and v ~= false and v ~= 0
end

local function colour(palette: any, key: string, fallback: Color3): Color3
	return Canvas2D.hex(if palette then palette[key] else nil, fallback)
end

-- A stroked circle has no one-Frame representation in Roblox UI. Short tangent rectangles retain
-- the empty centre and read as a ring without pretending a filled disk is the same shape.
local function ring(c: any, radius: number, width: number, value: Color3, alpha: number, segments: number)
	local chord = 2 * radius * math.sin(math.pi / segments) * 0.88
	for i = 0, segments - 1 do
		local a = (i / segments) * math.pi * 2
		Canvas2D.save(c)
		Canvas2D.rotate(c, a)
		Canvas2D.rect(c, radius - width / 2, -chord / 2, width, chord, value, alpha)
		Canvas2D.restore(c)
	end
end

local function line(c: any, x1: number, y1: number, x2: number, y2: number,
	width: number, value: Color3, alpha: number)
	local dx, dy = x2 - x1, y2 - y1
	local length = math.sqrt(dx * dx + dy * dy)
	Canvas2D.save(c)
	Canvas2D.translate(c, (x1 + x2) / 2, (y1 + y2) / 2)
	Canvas2D.rotate(c, math.atan2(dy, dx))
	Canvas2D.rect(c, -length / 2, -width / 2, length, width, value, alpha)
	Canvas2D.restore(c)
end

-- The JavaScript redraws the complete axe twice for its active-frame afterimages. Repeating the
-- port's contour pass would spend dozens of Frames per ghost on bevels that disappear at this
-- opacity, so this keeps the load-bearing silhouette: haft, head, bright bit and pointed beard.
local function axeGhost(c: any, palette: any, angle: number, scale: number, alpha: number)
	local primary = colour(palette, "primary", Color3.fromRGB(210, 212, 220))
	local accent = colour(palette, "accent", Color3.fromRGB(240, 220, 150))
	local h, tip = 2.4, 3.7
	Canvas2D.save(c)
	Canvas2D.rotate(c, angle)
	if scale ~= 1 then
		Canvas2D.scale(c, scale, scale)
	end
	Canvas2D.rect(c, -0.85, -0.12, 3.55, 0.24, primary, alpha)
	Canvas2D.rect(c, h, -0.9, 0.62, 1.8, primary, alpha)
	Canvas2D.tri(c, tip, 0.1, h + 0.5, -1.25, h + 0.5, 0.9, primary, alpha)
	Canvas2D.rect(c, tip - 0.16, -0.82, 0.14, 1.42, accent, alpha)
	Canvas2D.restore(c)
end

function UltimateVfx.drawUltimate(c: any, weaponId: string?, palette: any, pose: any, t: number?)
	local U = pose.ult
	if not U or not weaponId then
		return
	end
	local now = t or 0
	local glow = colour(palette, "glow", colour(palette, "accent", WHITE))
	-- JavaScript's `pose.scale || 1`: zero falls through there, but not through Luau's `or`.
	local sc = if nonzero(pose.scale) then pose.scale else 1

	-- Sword: energy running the length of an oversized blade.
	if weaponId == "Sword" and nonzero(U.glow) then
		Canvas2D.save(c)
		Canvas2D.rotate(c, pose.angle)
		Canvas2D.translate(c, pose.ox, pose.oy)
		local length = REACH.Sword * sc
		Canvas2D.rect(c, 0.2, -0.24 * sc, length, 0.14 * sc, glow, 0.22 + U.glow * 0.38)
		Canvas2D.rect(c, 0.2, 0.10 * sc, length, 0.14 * sc, glow, 0.22 + U.glow * 0.38)
		Canvas2D.rect(c, 0.2, -0.05 * sc, length, 0.10 * sc, WHITE, 0.55 * U.glow)
		if U.rise ~= nil then
			for i = 0, 4 do
				local u = (now * 1.6 + i / 5) % 1
				Canvas2D.rect(c, 0.3 + u * length, -0.5 * sc + (i % 2) * sc,
					0.22, 0.22, WHITE, (1 - u) * U.rise)
			end
		end
		if U.chop ~= nil then
			-- This wedge genuinely needs a point, so it earns the six-Frame stepped triangle.
			Canvas2D.tri(c, 0.2, 0, length, -1.5 * sc, length, 1.5 * sc, glow, 0.55)
		end
		Canvas2D.restore(c)
	end

	-- Scythe: the purple-black ball the victims are being crushed into.
	if U.pull ~= nil or U.crush ~= nil then
		local closing = if U.crush == nil then U.pull else 1
		local burst = if U.crush ~= nil then U.crush else 0
		Canvas2D.save(c)
		Canvas2D.rotate(c, pose.angle)
		Canvas2D.translate(c, REACH.Scythe * 0.75, 0)
		local radius = (1 + closing * 1.9) * (1 - burst * 0.55) + burst * 5.5
		Canvas2D.circle(c, 0, 0, radius * 1.45, VIOLET, 0.30 + closing * 0.25)
		Canvas2D.circle(c, 0, 0, radius, VIOLET_DARK, 0.95 - burst * 0.8)
		ring(c, radius * 1.12, 0.14 + burst * 0.3, VIOLET_EDGE, 0.9, 12)
		for i = 0, 7 do
			local a = (i / 8) * math.pi * 2 - now * 4.5
			local rr = radius * (2.6 - closing * 1.4) * (1 - burst)
			Canvas2D.rect(c, math.cos(a) * rr - 0.13, math.sin(a) * rr - 0.13,
				0.26, 0.26, VIOLET_SPARK, (0.8 - burst) * (0.35 + 0.65 * closing))
		end
		Canvas2D.restore(c)
	end

	-- Blasters: the pistol extends into a rifle.
	if nonzero(U.rifle) then
		local rifle = U.rifle
		local primary = colour(palette, "primary", Color3.fromRGB(154, 166, 180))
		local secondary = colour(palette, "secondary", Color3.fromRGB(107, 115, 130))
		local tertiary = colour(palette, "tertiary", Color3.fromRGB(74, 80, 92))
		Canvas2D.save(c)
		Canvas2D.rotate(c, pose.angle)
		Canvas2D.translate(c, pose.ox, pose.oy)
		Canvas2D.rect(c, 0.85, -0.17, 1.9 * rifle, 0.19, secondary)
		Canvas2D.rect(c, 0.72 + 1.9 * rifle, -0.26, 0.23, 0.34, primary)
		Canvas2D.rect(c, 0.05, -0.62, 0.9, 0.28, primary)
		Canvas2D.circle(c, 0.88, -0.48, 0.13, RED, 0.55 + 0.45 * math.sin(now * 9))
		line(c, 1.36, 0.02, 1.56, 0.62, 0.12, tertiary, 1)
		line(c, 1.36, 0.02, 1.16, 0.62, 0.12, tertiary, 1)
		Canvas2D.restore(c)
		if U.aiming then
			for i = 0, 2 do
				local loaded = i < U.rounds
				Canvas2D.rect(c, -0.9 + i * 0.42, -2.6, 0.3, 0.55,
					if loaded then Color3.fromRGB(255, 107, 74) else WHITE,
					if loaded then 0.95 else 0.22)
			end
		end
	end

	-- Axe: strain on the haul, then accelerating rings, grit and two afterimage heads.
	if U.haul ~= nil and weaponId == "Axe" then
		Canvas2D.save(c)
		Canvas2D.rotate(c, pose.angle)
		for i = 0, 3 do
			local x = -0.5 - i * 0.42
			local y = -0.5 + i * 0.28
			line(c, x, y, x - 0.7 - U.haul * 1.1, y, 0.1, glow, 0.35 + U.haul * 0.45)
		end
		Canvas2D.restore(c)
	end
	if U.reave ~= nil and weaponId == "Axe" then
		local radius = REACH.Axe * sc
		for i = 0, 2 do
			ring(c, radius * (0.72 + i * 0.16), 0.5 - i * 0.12,
				if i == 0 then WHITE else glow,
				(0.10 + U.reave * 0.22) * (1 - i * 0.26), 12)
		end
		for i = 0, 9 do
			local a = (i / 10) * math.pi * 2 + U.reave * 14
			Canvas2D.rect(c, math.cos(a) * radius * 1.05 - 0.16,
				math.sin(a) * radius * 1.05 - 0.16, 0.32, 0.32, GRIT, 0.5 * U.reave)
		end
	end
	if U.blur and weaponId == "Axe" then
		for i, angle in U.blur do
			axeGhost(c, palette, angle, sc, 0.30 - (i - 1) * 0.10)
		end
	end

	-- Pike: the telescoping segment and the line the lance owns.
	if (U.extend ~= nil or U.lance) and weaponId == "Pike" then
		local k = if U.lance then 1 else U.extend
		local reach = REACH.Pike * sc
		local secondary = colour(palette, "secondary", Color3.fromRGB(110, 124, 138))
		Canvas2D.save(c)
		Canvas2D.rotate(c, pose.angle)
		Canvas2D.translate(c, pose.ox, pose.oy)
		Canvas2D.rect(c, 1.2, -0.07, reach * 0.72 * k, 0.14, secondary, 0.9)
		Canvas2D.rect(c, 1.2, -0.03, reach * 0.72 * k, 0.06, glow,
			0.55 + 0.45 * (if U.lance then U.lance.punch else k))
		if U.lance then
			local lane = 1.2 + reach * 0.72 + U.lance.reach * 14
			Canvas2D.rect(c, 1.2, -0.5, lane, 1, glow, 0.16 + U.lance.punch * 0.34)
			Canvas2D.rect(c, lane - 1.6, -0.16, 1.6, 0.32, WHITE, 0.7 * U.lance.punch)
			for i = 0, 4 do
				Canvas2D.rect(c, lane - 3 - i * 2.1, -0.1, 1.1, 0.2,
					WHITE, (0.5 - i * 0.09) * U.lance.punch)
			end
		end
		Canvas2D.restore(c)
	end

	-- Grimoire: three rune rings, three speeds. Each circular stroke is a tangent-segment ring;
	-- the orbiting rune squares are otherwise the same as the JavaScript.
	if U.runes ~= nil and weaponId == "Grimoire" then
		Canvas2D.save(c)
		Canvas2D.rotate(c, pose.angle)
		Canvas2D.translate(c, 1.1, 0)
		for i = 0, 2 do
			local radius = 1.5 + i * 1.25
			local spin = now * (1.4 - i * 0.45) * (if i % 2 == 1 then -1 else 1)
			local alpha = 0.75 - i * 0.16
			ring(c, radius, 0.14, glow, alpha, 10 + i * 2)
			local count = 4 + i * 2
			for rune = 0, count - 1 do
				local a = (rune / count) * math.pi * 2 + spin
				Canvas2D.rect(c, math.cos(a) * radius - 0.11, math.sin(a) * radius - 0.11,
					0.22, 0.22, if i == 0 then WHITE else glow, alpha)
			end
		end
		Canvas2D.restore(c)
	end
end

-- The muzzle flash (blasters and other projectile weapons) and the grimoire's cast burst, drawn at
-- the business end of the weapon. This is deliberately separate so Fighter2D can keep the web
-- renderer's layer order: ultimate VFX, weapon, then flash.
function UltimateVfx.drawMuzzle(c: any, weaponId: string?, palette: any, pose: any, t: number?)
	if not nonzero(pose.flash) then
		return
	end
	local now = t or 0
	local k = pose.flash
	local reach = if weaponId then (REACH[weaponId] or 1) else 1
	local glow = colour(palette, "glow", Color3.fromRGB(255, 196, 77))
	Canvas2D.save(c)
	Canvas2D.rotate(c, pose.angle)
	Canvas2D.translate(c, reach + pose.ox, pose.oy)
	if weaponId == "Grimoire" then
		local radius = 1.5 * k
		-- Canvas2D cannot stroke these two circles; segmented outlines preserve their open centres.
		ring(c, radius * 1.25, 0.13, glow, k, 12)
		ring(c, radius * 0.68, 0.13, glow, k, 8)
		for i = 0, 5 do
			local a = (i / 6) * math.pi * 2 + now * 3
			Canvas2D.rect(c, math.cos(a) * radius * 1.25 - 0.09,
				math.sin(a) * radius * 1.25 - 0.09, 0.18, 0.18, glow, k)
		end
		Canvas2D.circle(c, 0, 0, radius * 0.3, WHITE, k)
	else
		local radius = k
		for i = 0, 4 do
			local a = (i / 5) * math.pi * 2 + 0.35
			local length = radius * (if i % 2 == 1 then 0.7 else 1.5)
			-- The burst's five pointed rays are silhouette, so they use the stepped triangle.
			Canvas2D.tri(c, 0, 0,
				math.cos(a) * length, math.sin(a) * length,
				math.cos(a + 0.5) * length * 0.35, math.sin(a + 0.5) * length * 0.35,
				MUZZLE, k)
		end
		Canvas2D.circle(c, 0, 0, radius * 0.5, glow, k)
		Canvas2D.circle(c, 0, 0, radius * 0.24, WHITE, k)
	end
	Canvas2D.restore(c)
end

return UltimateVfx
