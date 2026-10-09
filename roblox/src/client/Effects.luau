--!strict
-- Hit and impact effects, ported from web/src/render2d/effects.js - read that file for the design.
-- Pure: tests/effects-parity.luau feeds both builds the same event and the same random numbers
-- and compares every spark and ring, step by step, and every shape drawn.
local Effects = {}

local PI = math.pi
Effects.PLAYER_TINT = { "#5FBF4B", "#E8862E", "#4A90D9", "#9A6BD6" }
Effects.GRAVITY = 26
Effects.SHAKE_DECAY = 9
Effects.RING_SEGMENTS = 16

function Effects.new(): any
	return { parts = {}, rings = {}, shake = 0, shields = {}, flash = 0 }
end
-- A hit's strength is its launch over HIT_FULL, 0 to 1; a kill hit flashes the screen KILL_FLASH s.
Effects.HIT_FULL = 150
Effects.KILL_FLASH = 0.12
Effects.KILL_FLASH_ALPHA = 0.35    -- at its brightest
-- The heavy-startup glint: its ring's radius (studs) and life (seconds).
Effects.GLINT = { r = 0.9, life = 0.24 }
Effects.SHIELD_FLARE = 0.3

-- The last impact on fighter i's shield, as Shield.shapes takes it (effects.js shieldHit).
function Effects.shieldHit(fx: any, i: number): any
	local s = fx.shields and fx.shields[i]
	return if s then { k = s.life / s.max, x = s.x, y = s.y } else nil
end

local function part(fx: any, x: number, y: number, vx: number, vy: number, life: number, max: number, c: string, s: number)
	table.insert(fx.parts, { x = x, y = y, vx = vx, vy = vy, life = life, max = max, c = c, s = s })
end

Effects.DUST = "#D9D2C2"
function Effects.spawn(fx: any, e: any, glow: (number?) -> string?, rand: () -> number, height: ((number?) -> number)?)
	local function feet(): number
		return e.y - (if height then height(e.fighter) else 5) / 2
	end
	local function dust(x: number, y: number, n: number, spread: number, lift: number, life: number, size: number)
		for _ = 1, n do
			local vx = (rand() - 0.5) * 2 * spread
			local vy = lift * (0.4 + rand() * 0.6)
			local px = x + (rand() - 0.5) * 0.8
			part(fx, px, y, vx, vy, life * (0.7 + rand() * 0.5), life, Effects.DUST, size)
		end
	end
	local function push(x: number, y: number, n: number, c: string, sp: number, life: number, size: number)
		for _ = 1, n do
			local a = rand() * PI * 2
			local s = sp * (0.4 + rand() * 0.8)
			part(fx, x, y, math.cos(a) * s, math.sin(a) * s, life * (0.6 + rand() * 0.7), life, c, size)
		end
	end
	local function ring(x: number, y: number, r: number, life: number, c: string, heavy: boolean, rot: number)
		table.insert(fx.rings, { x = x, y = y, r = r, life = life, max = life, c = c, heavy = heavy, rot = rot })
	end
	local function shake(v: number)
		fx.shake = math.max(fx.shake, v)
	end
	local t = e.type
	if t == "hit" then
		-- how hard it sent them, 0..1: sparks, speed, size, life and shake grow with it (effects.js)
		local k = math.max(math.clamp((e.launch or 0) / Effects.HIT_FULL, 0, 1), if e.heavy == true then 0.6 else 0)
		local col = glow(e.attacker) or "#FFFFFF"
		push(e.x, e.y, math.floor(6 + 12 * k + 0.5), col, 12 + 16 * k, 0.26 + 0.3 * k, 0.18 + 0.16 * k)
		push(e.x, e.y, math.floor(3 + 6 * k + 0.5), "#FFFFFF", 9 + 11 * k, 0.24, 0.22)
		if k >= 0.5 then ring(e.x, e.y, 1.8 + 1.4 * k, 0.34, col, true, rand() * PI) end
		shake(0.12 + 0.5 * k)
		-- the kill hit: a white burst, a ring twice any other hit's and a flash of the whole screen
		if e.kill == true then
			push(e.x, e.y, 14, "#FFFFFF", 38, 0.36, 0.3)
			ring(e.x, e.y, 4.2, 0.4, "#FFFFFF", true, rand() * PI)
			shake(1.2)
			fx.flash = Effects.KILL_FLASH
		end
	elseif t == "explosion" then
		push(e.x, e.y, 22, "#FFC44D", 30, 0.5, 0.34); ring(e.x, e.y, e.radius or 3, 0.4, "#FFD37A", true, 0); shake(0.7)
	elseif t == "block" then
		push(e.x, e.y, 6, if e.perfect then "#FFFFFF" else "#9FD1E8", 12, 0.25, 0.2)
		push(e.x, e.y, if e.perfect then 18 else 12, "#7FE8FF", 20, 0.35, 0.18)
		if e.victim ~= nil then
			fx.shields[e.victim] = { life = Effects.SHIELD_FLARE, max = Effects.SHIELD_FLARE, x = e.x, y = e.y }
		end
	elseif t == "ko" then
		local c = Effects.PLAYER_TINT[(e.fighter % 4) + 1]
		push(e.x, e.y, 28, c, 34, 0.7, 0.4); ring(e.x, e.y, 4, 0.5, c, true, 0); shake(1.0)
	elseif t == "projectile" or t == "beam" then
		push(e.x, e.y, 5, "#FFF3D0", 10, 0.2, 0.18)
	elseif t == "land" then
		if e.hard then push(e.x, e.y, 8, "#D9C9A8", 12, 0.3, 0.24); shake(0.35)
		else dust(e.x, feet(), 5, 5, 1.5, 0.26, 0.34) end
	elseif t == "ultimate" then
		push(e.x, e.y, 30, glow(e.fighter) or "#FFFFFF", 30, 0.6, 0.4); shake(1.4)
	elseif t == "ultready" then
		shake(0.2)
	elseif t == "armor" then
		-- a hit shrugged off rings like metal (effects.js)
		push(e.x, e.y, 9, "#D8E2F0", 14, 0.24, 0.2); ring(e.x, e.y, 1.5, 0.22, "#E8EEF6", true, PI / 8); shake(0.2)
	elseif t == "movestart" then
		-- the telegraph: a heavy or signature starting up glints on the upper body (effects.js)
		if e.heavy == true then ring(e.x, e.y + (if height then height(e.fighter) else 5) * 0.2, Effects.GLINT.r, Effects.GLINT.life, "#FFF6C8", true, PI / 4) end
	elseif t == "soulescape" then
		push(e.x, e.y, 12, "#FFFFFF", 24, 0.35, 0.26)
	elseif t == "crater" then
		push(e.x, e.y, if e.first then 26 else 12, "#5A4A3E", if e.first then 26 else 17, 0.55, if e.first then 0.42 else 0.3)
		push(e.x, e.y, if e.first then 18 else 8, "#FFB43C", if e.first then 30 else 20, 0.42, 0.3)
		ring(e.x, e.y, e.radius, 0.32, "#FFD37A", true, 0); shake(if e.first then 1.1 else 0.35)
	elseif t == "rundown" then
		push(e.x, e.y, if e.last then 26 else 12, "#FFE9C4", if e.last then 30 else 18, 0.36, if e.last then 0.4 else 0.26)
		push(e.x, e.y, if e.last then 14 else 6, "#FF9A4A", if e.last then 24 else 14, 0.3, 0.24)
		ring(e.x, e.y, if e.last then 4.6 else 2.8, 0.26, "#FFC98A", e.last == true, rand() * PI); shake(if e.last then 0.9 else 0.28)
	elseif t == "upheaval" then
		for i = 0, 21 do
			local x = e.x + (rand() - 0.5) * 4.6
			local y = e.y + rand() * 2
			local vx = (rand() - 0.5) * 8
			local vy = 22 + rand() * 26
			part(fx, x, y, vx, vy, 0.6, 0.6, if i % 3 ~= 0 then "#8A94A6" else "#4A4038", 0.22 + rand() * 0.3)
		end
		ring(e.x, e.y + 3.5, 3.4, 0.3, "#D8DCE2", true, PI / 2); shake(0.7)
	elseif t == "heartseeker" then
		push(e.x, e.y, 16, "#8EE86A", 34, 0.3, 0.22); shake(0.5)
	elseif t == "anchorset" then
		push(e.x, e.y, 20, "#6E7684", 20, 0.42, 0.3); ring(e.x, e.y, 2.4, 0.3, "#C86AE8", true, 0); shake(0.45)
	elseif t == "anchorsnap" then
		push(e.x, e.y, 26, "#C86AE8", 30, 0.45, 0.32); ring(e.x, e.y, 4.2, 0.34, "#D8B0F0", true, 0); shake(1.0)
	elseif t == "aegis" then
		push(e.x, e.y, 18, "#7FD4FF", 26, 0.38, 0.28); ring(e.x, e.y, 3.0, 0.28, "#FFFFFF", true, 0); shake(0.55)
	elseif t == "aegisbreak" then
		push(e.x, e.y, 30, "#FFFFFF", 34, 0.45, 0.34); ring(e.x, e.y, 5.4, 0.36, "#7FD4FF", true, 0); shake(1.1)
	elseif t == "bleedmark" then
		for _ = 1, 4 do
			local x = e.x + (rand() - 0.5) * 1.6
			local y = e.y + (rand() - 0.5) * 2
			local vx = (rand() - 0.5) * 6
			local vy = 4 + rand() * 8
			part(fx, x, y, vx, vy, 0.4, 0.4, "#FF4A6A", 0.2)
		end
	elseif t == "exsanguinate" then
		local n = math.min(12, e.marks)
		push(e.x, e.y, 10 + n * 3, "#FF4A6A", 22 + n * 2, 0.5, 0.3); ring(e.x, e.y, 1.8 + n * 0.32, 0.34, "#FFFFFF", true, 0)
		shake(0.4 + n * 0.06)
	elseif t == "soulgrab" then
		push(e.x, e.y, 14, "#C79BFF", 20, 0.4, 0.26)
	elseif t == "soulorb" then
		if rand() < 0.7 then
			local a = rand() * PI * 2
			local d = 5 + rand() * 4
			part(fx, e.x + math.cos(a) * d, e.y + math.sin(a) * d, -math.cos(a) * d * 2.4, -math.sin(a) * d * 2.4, 0.4, 0.4, "#B36BFF", 0.2)
		end
	elseif t == "soulburst" then
		push(e.x, e.y, 34, "#C79BFF", 40, 0.6, 0.4); push(e.x, e.y, 14, "#FFFFFF", 26, 0.35, 0.26)
		ring(e.x, e.y, e.radius, 0.45, "#B36BFF", true, 0); ring(e.x, e.y, e.radius * 1.7, 0.3, "#150B22", true, 0); shake(1.2)
	elseif t == "snipe" then
		push(e.x, e.y, 9, "#FFF3D0", 16, 0.24, 0.24); shake(0.4)
	elseif t == "starfall" then
		push(e.x, e.y, 6, "#B36BFF", 8, 0.35, 0.22)
	elseif t == "mark" then
		shake(0.25)
	elseif t == "counter" or t == "freeze" or t == "summonbreak" then
		push(e.x, e.y, 10, "#FFFFFF", 16, 0.3, 0.22)
	elseif t == "jump" then
		dust(e.x, feet(), 8, 7, 3, 0.34, 0.42)
	elseif t == "doublejump" then
		dust(e.x, feet(), 5, 5, -2, 0.28, 0.34); ring(e.x, feet(), 1.3, 0.22, "#FFFFFF", false, 0)
	elseif t == "dash" then
		dust(e.x, feet(), 9, 10, 2, 0.36, 0.44)
	elseif t == "dodge" then
		ring(e.x, e.y, 2.0, 0.2, "#BFE6FF", false, 0)
	elseif t == "ledge" then
		dust(e.x, e.y, 4, 3, 1, 0.28, 0.3)
	elseif t == "tech" then
		push(e.x, e.y, 8, "#FFFFFF", 14, 0.26, 0.22); ring(e.x, e.y, 2.2, 0.26, "#FFFFFF", false, 0)
	elseif t == "catch" then
		-- a teammate caught out of a launch: a ring in the catcher's colour and white (effects.js)
		push(e.x, e.y, 10, "#FFFFFF", 14, 0.3, 0.24); ring(e.x, e.y, 2.4, 0.32, glow(e.fighter) or "#9FE8A8", false, 0)
	elseif t == "rebound" then
		-- a launched fighter rebounding off a wall or ceiling: grit and a jolt by speed (effects.js)
		local k = math.clamp((e.speed or 0) / Effects.HIT_FULL, 0, 1)
		push(e.x, e.y, math.floor(6 + 8 * k + 0.5), Effects.DUST, 10 + 12 * k, 0.32, 0.3)
		ring(e.x, e.y, 1.6 + 1.2 * k, 0.24, "#E6DCC8", true, if e.surface == "ceiling" then 0 else PI / 2)
		shake(0.2 + 0.4 * k)
	elseif t == "shieldbreak" then
		push(e.x, e.y, 24, "#9FD1E8", 28, 0.55, 0.3); ring(e.x, e.y, 4, 0.4, "#FFFFFF", true, 0); shake(0.8)
	elseif t == "grabhit" then
		push(e.x, e.y, 8, "#FFE9C4", 12, 0.25, 0.22); shake(0.2)
	elseif t == "itembreak" or t == "projectilebreak" then
		push(e.x, e.y, 10, "#C9B79C", 14, 0.35, 0.24)
	elseif t == "spring" then
		for _ = 1, 10 do
			local x = e.x + (rand() - 0.5) * 2
			local vx = (rand() - 0.5) * 6
			local vy = 14 + rand() * 12
			part(fx, x, e.y, vx, vy, 0.4, 0.4, "#FFD37A", 0.24)
		end
	elseif t == "teleport" then
		push(e.x, e.y, 12, "#B36BFF", 16, 0.35, 0.24); ring(e.x, e.y, 2.5, 0.3, "#B36BFF", false, 0)
	elseif t == "pickup" then
		push(e.x, e.y, 6, "#FFD58A", 8, 0.3, 0.2)
	end
end

function Effects.step(fx: any, dt: number)
	local parts = {}
	for _, p in fx.parts do
		p.life -= dt
		if p.life > 0 then
			p.x += p.vx * dt; p.y += p.vy * dt; p.vy -= Effects.GRAVITY * dt
			table.insert(parts, p)
		end
	end
	fx.parts = parts
	local rings = {}
	for _, r in fx.rings do
		r.life -= dt
		if r.life > 0 then table.insert(rings, r) end
	end
	fx.rings = rings
	fx.shake = math.max(0, fx.shake - dt * Effects.SHAKE_DECAY)
	fx.flash = math.max(0, (fx.flash or 0) - dt)
	for k, s in fx.shields do
		s.life -= dt
		if s.life <= 0 then fx.shields[k] = nil end
	end
end

local function clamp01(v: number): number
	return if v < 0 then 0 elseif v > 1 then 1 else v
end
local function shape(...: any): { any }
	return { ... }
end

function Effects.shapes(fx: any): { any }
	local out = {}
	for _, p in fx.parts do
		table.insert(out, shape("r", p.x - p.s / 2, p.y - p.s / 2, p.s, p.s, p.c, clamp01(p.life / p.max)))
	end
	local N = Effects.RING_SEGMENTS
	for _, s in fx.rings do
		local k = 1 - s.life / s.max
		local a = (1 - k) * 0.9
		local r = s.r * (0.35 + k * 1.5)
		local w = 0.5 * (1 - k) + 0.12
		for i = 0, N - 1 do
			local a0, a1 = (i / N) * PI * 2, ((i + 1) / N) * PI * 2
			table.insert(out, shape("l", s.x + math.cos(a0) * r, s.y + math.sin(a0) * r, s.x + math.cos(a1) * r, s.y + math.sin(a1) * r, w, s.c, a))
		end
		if s.heavy then
			for n = 0, 7 do
				local ang = (n / 8) * PI * 2 + s.rot
				local r0 = s.r * (0.5 + k * 1.2)
				local r1 = r0 + s.r * 0.8 * (1 - k)
				table.insert(out, shape("l", s.x + math.cos(ang) * r0, s.y + math.sin(ang) * r0, s.x + math.cos(ang) * r1, s.y + math.sin(ang) * r1, 0.22 * (1 - k), s.c, a))
			end
		end
	end
	return out
end

function Effects.dragDirt(fx: any, x: number, floor: number, facing: number, vx: number, scrape: number, tertiary: string, rand: () -> number)
	if rand() >= 0.25 + scrape * 0.75 then return end
	local pvx = -facing * (2 + rand() * 7) - vx * 0.12
	local pvy = 1 + rand() * 5
	local life = 0.3 + rand() * 0.3
	local c = if rand() < 0.5 then tertiary else "#6B5A44"
	part(fx, x, floor + 0.1, pvx, pvy, life, 0.6, c, 0.16 + rand() * 0.18)
end

function Effects.orbSparks(fx: any, x: number, y: number, vx: number, glow: string?, rand: () -> number)
	if rand() >= 0.5 then return end
	local pvx = -vx * 0.08 + (rand() - 0.5) * 2
	local pvy = (rand() - 0.5) * 2
	part(fx, x, y, pvx, pvy, 0.28, 0.28, glow or "#7DE8FF", 0.16)
end

return Effects
