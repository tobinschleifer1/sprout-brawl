--!strict
-- The parts of an ultimate that ride on the weapon: the greatsword wreathed in its own fire, the
-- crescent it cuts on the way down, the scythe's vortex, the rifle and its glint, the axe's
-- crescent blur, the pike's lances of light, the flurry's impact stars, the hammer's charged head,
-- the bow's gathering arrow and its sight line, the shield's glare, the daggers' cross-cuts and the
-- grimoire's rune circles - and the muzzle/cast flash every projectile weapon fires through.
--
-- Drawn in the hand's frame, inside Fighter2D, so everything here moves, mirrors and scales with
-- the fighter - whatever avatar they are and whichever way they face. WeaponPose.luau supplies the
-- same U.* values as web/src/render2d/weapons2d.js; this paints them in pixel art (FxArt) in the
-- weapon's own glow colour. The world-space half - fissures, chains, barriers, sights - is
-- UltWorld; the timed explosions are FxPlayer.

local Canvas2D = require(script.Parent.Canvas2D)
local FxArt = require(script.Parent.FxArt)

local UltimateVfx = {}

local WHITE = Color3.new(1, 1, 1)
local GRIT = Color3.fromRGB(107, 90, 68)

local REACH: { [string]: number } = {
	Sword = 2.6, Scythe = 3.4, Blasters = 1.1, Grimoire = 0.9, Axe = 3.2, Pike = 5.9,
	Gauntlets = 1.0, Hammer = 3.7, Longbow = 1.2, Flail = 4.2, Shield = 1.3, Daggers = 1.7,
}
UltimateVfx.REACH = REACH

local function nonzero(v: any): boolean
	-- JavaScript branches on truthiness. Zero is truthy in Luau, so `if v` is not the same test.
	return v ~= nil and v ~= false and v ~= 0
end

local function colour(palette: any, key: string, fallback: Color3): Color3
	return Canvas2D.hex(if palette then palette[key] else nil, fallback)
end

local function glowHex(palette: any): string
	return if palette and palette.glow then palette.glow elseif palette and palette.accent then palette.accent else "#FFFFFF"
end

local function sized(art: any, width: number): number
	return width * art.ppu / art.cols
end

local function line(c: any, x1: number, y1: number, x2: number, y2: number, width: number, value: Color3, alpha: number)
	Canvas2D.line(c, x1, y1, x2, y2, width, value, alpha)
end

-- Re-seat the current transform as an upright one at the same point and scale, mirrored with the
-- fighter. The hand frame carries the torso's squash and stretch; a sprite that ROTATES under a
-- non-uniform scale would need a shear, which a Frame cannot do, so anything here that spins -
-- vortices, rune circles, impact stars - is drawn from an upright frame instead.
local function upright(c: any)
	local m = c.m
	local det = m.a * m.d - m.b * m.c
	local s = math.sqrt(math.abs(det))
	-- The world flips y, so an unmirrored frame has det < 0 on screen.
	Canvas2D.setTransform(c, if det < 0 then s else -s, 0, 0, -s, m.e, m.f)
end

-- A burning edge: two glow bands and a white core along a blade of `length`, and flame licking off
-- its back. The pixel flames are what turns "a bright rectangle" into "a blade on fire".
local function burningEdge(c: any, length: number, sc: number, glow: string, k: number, t: number)
	local g = Canvas2D.hex(glow, WHITE)
	Canvas2D.rect(c, 0.3, -0.26 * sc, length, 0.52 * sc, g, 0.16 + k * 0.26)
	Canvas2D.rect(c, 0.3, -0.07 * sc, length, 0.14 * sc, WHITE, 0.4 * k)
	local n = 4
	for i = 0, n - 1 do
		local u = (i + 0.5) / n
		local f = math.floor(t * 14 + i * 2) % 6
		local fl = FxArt.get("flame", f, glow, nil, i + 1)
		local size = (0.55 + 0.35 * math.sin(u * math.pi)) * sc * (0.5 + 0.5 * k)
		FxArt.draw(c, fl, 0.3 + u * length, 0.12 * sc, sized(fl, size), 0, k)
	end
end

-- The muzzle of an ultimate, ringed by motes being drawn in: a charge gathering at a point.
local function gathering(c: any, x: number, y: number, k: number, glow: string, t: number, radius: number)
	Canvas2D.save(c)
	Canvas2D.translate(c, x, y)
	upright(c)
	x, y = 0, 0
	for i = 0, 3 do
		local cyc = (t * 1.6 + i / 4) % 1
		local a = i * 1.7 + t * 2
		local r = radius * (1 - cyc)
		FxArt.draw(c, FxArt.get("star", if cyc > 0.8 then 1 else 0, glow), x + math.cos(a) * r, y + math.sin(a) * r, 0.5, 0, k)
	end
	local orb = FxArt.get("orb", math.floor(t * 12) % 4, glow)
	FxArt.draw(c, orb, x, y, sized(orb, 0.4 + 1.6 * k), 0, math.min(1, k * 1.5))
	Canvas2D.restore(c)
end

-- The axe's afterimage heads: the silhouette, not the bevels, at this opacity.
local function axeGhost(c: any, palette: any, angle: number, scale: number, alpha: number)
	local primary = colour(palette, "primary", Color3.fromRGB(210, 212, 220))
	local accent = colour(palette, "accent", Color3.fromRGB(240, 220, 150))
	local h, tip = 2.4, 3.7
	Canvas2D.save(c)
	Canvas2D.rotate(c, angle)
	if scale ~= 1 then Canvas2D.scale(c, scale, scale) end
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
	local glow = glowHex(palette)
	local g = Canvas2D.hex(glow, WHITE)
	-- JavaScript's `pose.scale || 1`: zero falls through there, but not through Luau's `or`.
	local sc = if nonzero(pose.scale) then pose.scale else 1

	-- SWORD - COLOSSUS. The blade catches fire as it grows overhead, then cuts a crescent of that
	-- fire on the way down, and cools once it is buried in the floor.
	if weaponId == "Sword" and nonzero(U.glow) then
		local length = REACH.Sword * sc
		Canvas2D.save(c)
		Canvas2D.rotate(c, pose.angle)
		Canvas2D.translate(c, pose.ox, pose.oy)
		burningEdge(c, length, sc, glow, U.glow, now)
		if U.rise ~= nil then
			for i = 0, 3 do
				local u = (now * 1.8 + i / 4) % 1
				FxArt.draw(c, FxArt.get("star", math.floor(u * 4) % 4, glow), 0.4 + u * length, (i % 2 - 0.5) * 1.2 * sc, 0.6, 0, U.rise)
			end
		end
		Canvas2D.restore(c)
		if U.chop ~= nil then
			-- the crescent sits behind the blade, on the side it came from
			local cr = FxArt.get("crescent", math.floor(U.chop * 4.99), glow, nil, 2)
			Canvas2D.save(c)
			Canvas2D.rotate(c, pose.angle + 0.55)
			FxArt.draw(c, cr, 0, 0, sized(cr, (length + 0.6) * 2), 0, 1)
			Canvas2D.restore(c)
		end
	end

	-- SCYTHE - SOUL HARVEST. A vortex with a black eye opens at the end of the blade's reach and
	-- winds tighter as it holds its victims; the crush collapses it into the burst.
	if U.pull ~= nil or U.crush ~= nil then
		local closing = if U.crush == nil then U.pull else 1
		local burst = if U.crush ~= nil then U.crush else 0
		Canvas2D.save(c)
		Canvas2D.rotate(c, pose.angle)
		Canvas2D.translate(c, REACH.Scythe * 0.75, 0)
		upright(c)
		local size = (2.8 + closing * 3.6) * (1 - burst * 0.85)
		if size > 0.3 then
			local ring = FxArt.get("rune", 0, glow, nil, 7)
			FxArt.draw(c, ring, 0, 0, sized(ring, size * 2.2), now * 1.2, 0.45 + 0.35 * closing)
			Canvas2D.circle(c, 0, 0, size * 0.62, Color3.fromRGB(11, 6, 20), 0.75)
			local sw = FxArt.get("swirl", 0, glow, nil, 4)
			FxArt.draw(c, sw, 0, 0, sized(sw, size * 1.55), -now * (5 + closing * 6), 1)
			local sw2 = FxArt.get("swirl", 0, "void", nil, 6)
			FxArt.draw(c, sw2, 0, 0, sized(sw2, size * 1.05), -now * (8 + closing * 8) + 1, 1)
			Canvas2D.circle(c, 0, 0, size * 0.16, Color3.fromRGB(4, 2, 8), 1)
		end
		-- souls spiralling in toward the eye
		for i = 0, 5 do
			local q = (now * 1.3 + i / 6) % 1
			local a = i * 1.05 + q * 4
			local rr = (1 - q) * (5.5 - closing * 2) * (1 - burst)
			if rr > 0.4 then
				FxArt.draw(c, FxArt.get("star", if q > 0.7 then 2 else 1, glow), math.cos(a) * rr, math.sin(a) * rr, 0.6, 0, 1 - burst)
			end
		end
		Canvas2D.restore(c)
	end

	-- BLASTERS - DEADEYE. The pistol extends into a rifle; the scope glints while it aims and the
	-- three rounds hang over the fighter's head as they are spent.
	if nonzero(U.rifle) then
		local rifle = U.rifle
		local primary = colour(palette, "primary", Color3.fromRGB(154, 166, 180))
		local secondary = colour(palette, "secondary", Color3.fromRGB(107, 115, 130))
		local tertiary = colour(palette, "tertiary", Color3.fromRGB(74, 80, 92))
		Canvas2D.save(c)
		Canvas2D.rotate(c, pose.angle)
		Canvas2D.translate(c, pose.ox, pose.oy)
		Canvas2D.rect(c, 0.85, -0.21, 1.9 * rifle + 0.08, 0.27, tertiary)
		Canvas2D.rect(c, 0.85, -0.17, 1.9 * rifle, 0.19, secondary)
		Canvas2D.rect(c, 0.72 + 1.9 * rifle, -0.28, 0.27, 0.38, tertiary)
		Canvas2D.rect(c, 0.74 + 1.9 * rifle, -0.26, 0.23, 0.34, primary)
		Canvas2D.rect(c, 0.05, -0.66, 0.94, 0.36, tertiary)
		Canvas2D.rect(c, 0.07, -0.62, 0.9, 0.28, primary)
		Canvas2D.rect(c, 0.75, -0.6, 0.18, 0.24, g, 0.9)
		line(c, 1.36, 0.02, 1.56, 0.62, 0.12, tertiary, 1)
		line(c, 1.36, 0.02, 1.16, 0.62, 0.12, tertiary, 1)
		if U.aiming then
			local glint = math.floor(now * 3) % 3 == 0
			FxArt.draw(c, FxArt.get("star", if glint then 2 else 0, glow), 0.84, -0.48, 0.9, 0, 1)
			-- the barrel smoulders between shots
			FxArt.draw(c, FxArt.get("spark", math.floor(now * 10) % 3, glow), 0.95 + 1.9 * rifle, -0.1, 0.4, 0, 0.7)
		end
		Canvas2D.restore(c)
		if U.aiming then
			for i = 0, 2 do
				local loaded = i < U.rounds
				local x = -0.9 + i * 0.5
				Canvas2D.rect(c, x - 0.04, -2.65, 0.38, 0.72, Color3.fromRGB(18, 14, 22), if loaded then 0.9 else 0.3)
				Canvas2D.rect(c, x, -2.45, 0.3, 0.48, if loaded then Color3.fromRGB(255, 196, 77) else WHITE, if loaded then 1 else 0.22)
				Canvas2D.rect(c, x + 0.05, -2.62, 0.2, 0.18, if loaded then Color3.fromRGB(255, 107, 74) else WHITE, if loaded then 1 else 0.22)
			end
		end
	end

	-- AXE - REAVE. Strain lines on the haul; in the spin, crescent arcs chasing the head round and
	-- the two afterimage heads, with grit kicked off the rim of the swing.
	if U.haul ~= nil and weaponId == "Axe" then
		Canvas2D.save(c)
		Canvas2D.rotate(c, pose.angle)
		for i = 0, 3 do
			local x = -0.5 - i * 0.42
			local y = -0.5 + i * 0.28
			line(c, x, y, x - 0.7 - U.haul * 1.1, y, 0.12, g, 0.35 + U.haul * 0.45)
		end
		Canvas2D.restore(c)
		gathering(c, 0, 0, U.haul, glow, now, 2.2)
	end
	if U.reave ~= nil and weaponId == "Axe" then
		local radius = REACH.Axe * sc
		local f = math.floor(now * 18) % 3 + 1
		for i = 0, 1 do
			Canvas2D.save(c)
			Canvas2D.rotate(c, pose.angle + 0.5 + i * math.pi)
			local cr = FxArt.get("crescent", f, glow, nil, 3 + i)
			FxArt.draw(c, cr, 0, 0, sized(cr, radius * 2.15), 0, 0.85 - i * 0.3)
			Canvas2D.restore(c)
		end
		for i = 0, 7 do
			local a = (i / 8) * math.pi * 2 + U.reave * 14
			Canvas2D.rect(c, math.cos(a) * radius * 1.08 - 0.16, math.sin(a) * radius * 1.08 - 0.16, 0.32, 0.32, GRIT, 0.55 * U.reave)
		end
	end
	if U.blur and weaponId == "Axe" then
		for i, angle in U.blur do
			axeGhost(c, palette, angle, sc, 0.32 - (i - 1) * 0.12)
		end
	end

	-- PIKE - LANCE CHARGE. The haft telescopes with a seam of light; every thrust fires a lance
	-- of that light down the lane, longer each time, bursting where it ends.
	if (U.extend ~= nil or U.lance) and weaponId == "Pike" then
		local kk = if U.lance then 1 else U.extend
		local reach = REACH.Pike * sc
		local secondary = colour(palette, "secondary", Color3.fromRGB(110, 124, 138))
		Canvas2D.save(c)
		Canvas2D.rotate(c, pose.angle)
		Canvas2D.translate(c, pose.ox, pose.oy)
		Canvas2D.rect(c, 1.2, -0.08, reach * 0.72 * kk, 0.16, secondary, 0.9)
		Canvas2D.rect(c, 1.2, -0.04, reach * 0.72 * kk, 0.08, g, 0.55 + 0.45 * (if U.lance then U.lance.punch else kk))
		if U.extend ~= nil and not U.lance then
			gathering(c, 1.2 + reach * 0.72 * kk, 0, kk, glow, now, 1.8)
		end
		-- the lances themselves fly down the thrust's lane, which is horizontal whatever angle the
		-- haft is held at: UltWorld draws them where the hitboxes are
		Canvas2D.restore(c)
	end

	-- GAUNTLETS - RUNDOWN. Each fist lands with an impact star; the finisher is a big one.
	if weaponId == "Gauntlets" and (U.haul ~= nil or U.flurry ~= nil) then
		if U.haul ~= nil and U.flurry == nil then
			gathering(c, 0.4, 0, U.haul, glow, now, 2)
		end
		if U.flurry ~= nil then
			local beat = math.floor(now * 22)
			local pop = FxArt.get("pop", beat % 3, glow, nil, beat % 4 + 1)
			Canvas2D.save(c)
			Canvas2D.rotate(c, pose.angle)
			Canvas2D.translate(c, REACH.Gauntlets + 0.3, 0)
			upright(c)
			FxArt.draw(c, pop, 0, 0, sized(pop, 1.8), beat * 0.6, 1)
			if U.finish then
				local big = FxArt.get("pop", math.floor(U.finish * 4.99), glow, nil, 6)
				FxArt.draw(c, big, 0.5, 0, sized(big, 3.6), 0, 1)
			end
			Canvas2D.restore(c)
		end
	end

	-- HAMMER - UPHEAVAL. The head charges with fire on the way up and pulses with every column it
	-- calls once it is in the ground.
	if weaponId == "Hammer" and nonzero(U.glow) then
		local head = REACH.Hammer * sc - 0.4
		Canvas2D.save(c)
		Canvas2D.rotate(c, pose.angle)
		Canvas2D.translate(c, pose.ox + head, pose.oy)
		upright(c)
		local orb = FxArt.get("orb", math.floor(now * 12) % 4, glow)
		FxArt.draw(c, orb, 0, 0, sized(orb, 1.6 + U.glow * 1.6), 0, 0.35 + U.glow * 0.5)
		for i = 0, 2 do
			local f = math.floor(now * 14 + i * 2) % 6
			local fl = FxArt.get("flame", f, "fire", nil, i + 3)
			FxArt.draw(c, fl, (i - 1) * 0.6, 0.3, sized(fl, 0.7 * U.glow), 0, U.glow)
		end
		Canvas2D.restore(c)
		if U.chop ~= nil then
			local cr = FxArt.get("crescent", math.floor(U.chop * 4.99), "fire", nil, 5)
			Canvas2D.save(c)
			Canvas2D.rotate(c, pose.angle + 0.6)
			FxArt.draw(c, cr, 0, 0, sized(cr, (REACH.Hammer * sc + 0.4) * 2), 0, 1)
			Canvas2D.restore(c)
		end
	end

	-- LONGBOW - HEARTSEEKER. Light gathers at the arrowhead for the whole draw while a sight line
	-- reaches across the stage; the loose rings the air around the bow.
	if weaponId == "Longbow" and (U.draw ~= nil or U.loose ~= nil) then
		Canvas2D.save(c)
		Canvas2D.rotate(c, pose.angle)
		Canvas2D.translate(c, pose.ox, pose.oy)
		if U.draw ~= nil then
			local k = U.draw
			gathering(c, REACH.Longbow + 0.5, 0, k, glow, now, 2.6)
			-- the sight line flickers in over the draw, dashed, and steadies at full draw
			local on = k > 0.92 or math.floor(now * 18) % 3 ~= 0
			if on then
				for i = 0, 11 do
					local x = REACH.Longbow + 1.6 + i * 2.6
					Canvas2D.rect(c, x, -0.05, 1.5, 0.1, g, (0.15 + k * 0.45) * (1 - i / 13))
				end
			end
		end
		if U.loose ~= nil and U.loose < 1 then
			local ring = FxArt.get("ring", math.floor(U.loose * 5.99), glow)
			FxArt.draw(c, ring, REACH.Longbow + 0.6, 0, sized(ring, 3.6), math.pi / 2, 1, 0.38)
		end
		Canvas2D.restore(c)
	end

	-- FLAIL - ANCHOR. The wind-up gathers at the head; once thrown, the chain is the world's.
	if weaponId == "Flail" and U.haul ~= nil then
		Canvas2D.save(c)
		Canvas2D.rotate(c, pose.angle)
		gathering(c, REACH.Flail, 0, U.haul, glow, now, 2.4)
		Canvas2D.restore(c)
	end

	-- SHIELD - AEGIS. The face of the shield glares; at the release it flares white.
	if weaponId == "Shield" and (U.brace ~= nil or U.wall ~= nil) then
		Canvas2D.save(c)
		Canvas2D.rotate(c, pose.angle)
		Canvas2D.translate(c, pose.ox + 0.5, pose.oy)
		local k = if U.brace ~= nil then U.brace else 1
		Canvas2D.rect(c, -0.2, -1.6 * sc, 0.4, 3.2 * sc, g, 0.25 * k + 0.1 * math.sin(now * 9))
		if U.release then
			local pop = FxArt.get("pop", math.floor(U.release * 2.99), glow, nil, 4)
			FxArt.draw(c, pop, 0.4, 0, sized(pop, 2 + U.release * 4), 0, 1)
		end
		Canvas2D.restore(c)
	end

	-- DAGGERS - EXSANGUINATE. Cross-cuts open in the air where the blades were.
	if weaponId == "Daggers" and (U.haul ~= nil or U.flurry ~= nil) then
		if U.haul ~= nil and U.flurry == nil then
			gathering(c, 0.8, 0, U.haul, glow, now, 2)
		end
		if U.flurry ~= nil then
			local beat = math.floor(now * 16)
			Canvas2D.save(c)
			Canvas2D.rotate(c, pose.angle)
			Canvas2D.translate(c, REACH.Daggers + 0.6, 0)
			upright(c)
			local x = FxArt.get("xslash", beat % 3, glow, nil, beat % 5 + 1)
			FxArt.draw(c, x, 0, 0, sized(x, 2.8), beat * 0.9, 1)
			if U.finish then
				local big = FxArt.get("xslash", math.floor(U.finish * 3.99), glow, nil, 7)
				FxArt.draw(c, big, 0.6, 0, sized(big, 4.6), 0, 1)
			end
			Canvas2D.restore(c)
		end
	end

	-- GRIMOIRE - ASTRAL RAIN. Two rune circles turn against each other over the open book, stars
	-- orbiting the outer one.
	if U.runes ~= nil and weaponId == "Grimoire" then
		Canvas2D.save(c)
		Canvas2D.rotate(c, pose.angle)
		Canvas2D.translate(c, 1.1, 0)
		upright(c)
		local outer = FxArt.get("rune", 0, glow, nil, 3)
		FxArt.draw(c, outer, 0, 0, sized(outer, 5.2), now * 1.1, 0.85)
		local inner = FxArt.get("rune", 0, "star", nil, 8)
		FxArt.draw(c, inner, 0, 0, sized(inner, 3.0), -now * 1.8, 0.9)
		for i = 0, 5 do
			local a = (i / 6) * math.pi * 2 + now * 1.6
			FxArt.draw(c, FxArt.get("star", math.floor(now * 6 + i) % 4, glow), math.cos(a) * 2.9, math.sin(a) * 2.9, 0.55, 0, 1)
		end
		Canvas2D.restore(c)
	end
end

-- The muzzle flash (blasters and other projectile weapons) and the grimoire's cast burst, drawn at
-- the business end of the weapon, after the weapon - the web renderer's layer order.
function UltimateVfx.drawMuzzle(c: any, weaponId: string?, palette: any, pose: any, t: number?)
	if not nonzero(pose.flash) then
		return
	end
	local now = t or 0
	local k = pose.flash
	local reach = if weaponId then (REACH[weaponId] or 1) else 1
	local glow = if palette and palette.glow then palette.glow else "#FFC44D"
	Canvas2D.save(c)
	Canvas2D.rotate(c, pose.angle)
	Canvas2D.translate(c, reach + pose.ox, pose.oy)
	if weaponId == "Grimoire" then
		upright(c)
		local ring = FxArt.get("rune", 0, glow, nil, 9)
		FxArt.draw(c, ring, 0, 0, sized(ring, 3.4 * k), now * 3, k)
		FxArt.draw(c, FxArt.get("star", 1, glow), 0, 0, 0.9 * k, 0, k)
	else
		-- a bright flash that pops then shrinks: frame by how spent it is
		upright(c)
		local pop = FxArt.get("pop", math.floor((1 - k) * 4.99), glow, nil, 1)
		FxArt.draw(c, pop, 0.3, 0, sized(pop, 2.4 * math.max(0.4, k)), 0, 1)
	end
	Canvas2D.restore(c)
end

return UltimateVfx
