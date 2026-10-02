--!strict
-- Timed pixel-art effects: the explosions, shockwaves, pillars and impact stars the ultimates set
-- off. Each is one FxArt flipbook placed in the world and played through once; FxPlayer.spawn turns
-- a match event into the handful of them that event looks like.
--
-- Effects (the parity-held port of effects.js) still throws the sparks and dust for every event,
-- unchanged. This is the layer above it: the drawn moments a fighting game holds a frame on.
--
-- Events say where something happened but rarely who did it, so the caster is found from the
-- states being drawn: the fighter mid-ultimate whose move is the kind that emits that event. That
-- is what colours an explosion in the caster's weapon glow, and it keeps the shared simulation's
-- event shapes - which the JavaScript and its replay tests own - untouched.
local FxArt = require(script.Parent.FxArt)

local FxPlayer = {}

-- Never more than this many effects alive. A four-player match of overlapping ultimates peaks
-- around twenty; the cap only bites on a pile-up, and drops the oldest, which have mostly played.
FxPlayer.MAX = 40

export type Item = {
	kind: string, x: number, y: number, age: number, dur: number, size: number,
	rot: number, ramp: string?, b: string?, seed: number, sy: number?, delay: number,
	fadeAt: number?,
}

function FxPlayer.new(): any
	return { items = {} :: { Item }, flash = 0, flashColour = "#FFFFFF", seed = 0 }
end

function FxPlayer.clear(P: any)
	table.clear(P.items)
	P.flash = 0
end

-- `size` is the drawing's width in studs. `dur` seconds plays the whole flipbook once.
-- Variations of a drawing per kind. Each distinct one is a sprite built the first time it is drawn,
-- so variety is bounded: four strikes of lightning look random; forty cost forty builds.
FxPlayer.VARIANTS = 4
local function variant(n: number): number
	return (n % FxPlayer.VARIANTS) + 1
end

local function add(P: any, kind: string, x: number, y: number, size: number, dur: number, ramp: string?, opts: any?)
	P.seed += 1
	local o = opts or {}
	local item: Item = {
		kind = kind, x = x, y = y, age = 0, dur = dur, size = size, rot = o.rot or 0,
		ramp = ramp, b = o.b, seed = variant(o.seed or P.seed), sy = o.sy, delay = o.delay or 0,
		fadeAt = o.fadeAt,
	}
	table.insert(P.items, item)
	while #P.items > FxPlayer.MAX do table.remove(P.items, 1) end
	return item
end
FxPlayer.add = add

local function flash(P: any, alpha: number, colour: string?)
	if alpha > P.flash then
		P.flash = alpha
		P.flashColour = colour or "#FFFFFF"
	end
end

-- Which move kind emits each ultimate event: how an event finds its caster.
local KIND: { [string]: string } = {
	crater = "slam", soulburst = "vortex", soulgrab = "vortex", snipe = "sniper", starfall = "starfall",
	rundown = "rundown", upheaval = "upheaval", heartseeker = "pierce", anchorset = "anchor",
	anchorsnap = "anchor", aegis = "reflect", aegisbreak = "reflect", bleedmark = "bleed",
	exsanguinate = "bleed",
}
FxPlayer.KIND = KIND

local function inUltimate(s: any, char: any): any
	if s.moveId ~= "Ultimate" or not char or not char.moves then return nil end
	return char.moves.Ultimate
end

-- The fighter mid-ultimate of move kind `kind` nearest (x, y), and their character.
function FxPlayer.casterOf(kind: string, states: { any }, chars: { any }, x: number, y: number): (any, any)
	local best, bestChar, bestD = nil, nil, math.huge
	for _, s in states do
		local char = chars[s.index + 1]
		local m = inUltimate(s, char)
		if m and m.kind == kind then
			local d = (s.x - x) ^ 2 + (s.y - y) ^ 2
			if d < bestD then best, bestChar, bestD = s, char, d end
		end
	end
	return best, bestChar
end

local function glowOf(char: any): string?
	local pal = char and (char.weaponPalette or char.palette)
	return pal and (pal.glow or pal.accent) or nil
end

local function stateOf(states: { any }, index: number?): any
	if index == nil then return nil end
	for _, s in states do
		if s.index == index then return s end
	end
	return nil
end

-- Bolts thrown out radially from (x, y): a discharge.
local function radialBolts(P: any, x: number, y: number, n: number, length: number, ramp: string?)
	for i = 0, n - 1 do
		local a = (i / n) * math.pi * 2 + (P.seed % 5) * 0.4
		add(P, "bolt", x, y, length, 0.28, ramp, { rot = a, seed = P.seed + i, delay = i * 0.02 })
	end
end

-- Returns true when this event was drawn here, so the caller can leave out the plain impact rings
-- Effects would draw over it (see FightScene.spawn).
function FxPlayer.spawn(P: any, e: any, states: { any }, chars: { any }): boolean
	local t = e.type
	if t == "ultimate" then
		local s = stateOf(states, e.fighter)
		local char = if e.fighter ~= nil then chars[e.fighter + 1] else nil
		if not s or not char then return false end
		local glow = glowOf(char)
		local cy = s.y + char.height * 0.5
		add(P, "burst", s.x, cy, char.height * 1.6, 0.42, glow)
		add(P, "ring", s.x, cy, char.height * 2.6, 0.36, glow)
		add(P, "ring", s.x, s.y + 0.2, char.height * 3.4, 0.4, glow, { sy = 0.28, delay = 0.05 })
		flash(P, 0.32, glow)
		return true
	end
	if t == "hit" then
		-- Every hit an ultimate lands gets an impact star in the caster's colour, over the sparks.
		local s = stateOf(states, e.attacker)
		local char = if s then chars[s.index + 1] else nil
		if not s or not inUltimate(s, char) then return false end
		local size = if e.heavy then 3.6 else 2.4
		add(P, "pop", e.x, e.y, size, 0.2, glowOf(char), { rot = (P.seed % 8) * 0.39 })
		return true
	end
	if t == "explosion" then
		-- An exploding projectile or keg. Astral Rain's orbs burst in starlight; anything else in
		-- plain fire.
		local s = FxPlayer.casterOf("starfall", states, chars, e.x or 0, e.y or 0)
		local ramp = if s then "star" else "fire"
		local r = e.radius or 3
		add(P, "burst", e.x, e.y, r * 2.4, 0.42, ramp)
		add(P, "ring", e.x, e.y, r * 3.2, 0.32, ramp)
		return true
	end
	local kind = KIND[t]
	if not kind then return false end
	local s, char = FxPlayer.casterOf(kind, states, chars, e.x or 0, e.y or 0)
	local glow = glowOf(char)
	local x, y = e.x or 0, e.y or 0
	if t == "crater" then
		-- The greatsword's crater, or the hammer's Earthshatter (not an ultimate: no caster, so it
		-- burns in plain fire).
		local ramp = glow or "fire"
		if e.first then
			add(P, "burst", x, y + 1.2, 7.5, 0.45, ramp)
			add(P, "ring", x, y + 0.2, 13, 0.38, ramp, { sy = 0.26 })
			add(P, "pop", x, y + 0.6, 5, 0.18, ramp)
			if s then flash(P, 0.28, glow) end
		end
		-- the greatsword's flames are drawn from its state, burning down as the crater spreads
		-- (UltWorld); Earthshatter has no state to draw from, so its bursts flare here
		if not s then add(P, "flame", x, y, 1.6 + (e.radius or 3) * 0.2, 0.5, ramp, { seed = P.seed }) end
		add(P, "ring", x, y + 0.15, (e.radius or 3) * 2.2, 0.3, ramp, { sy = 0.3 })
	elseif t == "soulgrab" then
		add(P, "star", x, y, 2.2, 0.3, glow or "void")
	elseif t == "soulburst" then
		local r = e.radius or 4
		add(P, "burst", x, y, r * 2.6, 0.5, "void")
		add(P, "ring", x, y, r * 4, 0.42, glow or "void")
		add(P, "crescent", x, y, r * 2.4, 0.26, glow or "void", { rot = 0.6 })
		add(P, "crescent", x, y, r * 2.4, 0.26, glow or "void", { rot = 0.6 + math.pi, delay = 0.05 })
		flash(P, 0.26, glow)
	elseif t == "snipe" then
		local dir = e.facing or 1
		add(P, "pop", x, y, 2.6, 0.16, glow or "gold", { rot = if dir < 0 then math.pi else 0 })
		add(P, "ring", x, y, 2.4, 0.2, glow or "gold", { rot = math.pi / 2, sy = 0.4 })
	elseif t == "starfall" then
		add(P, "star", x, y, 2.6, 0.32, glow or "star")
	elseif t == "rundown" then
		local ramp = glow or "fire"
		if e.last then
			add(P, "burst", x, y, 7, 0.45, ramp)
			add(P, "ring", x, y, 10, 0.34, ramp)
			add(P, "pop", x, y, 6, 0.22, ramp)
			flash(P, 0.24, glow)
		else
			add(P, "pop", x, y, 3.6, 0.2, ramp, { rot = (e.step or 0) * 0.7 })
			add(P, "ring", x, y, 4, 0.2, ramp)
		end
	elseif t == "upheaval" then
		local ramp = glow or "fire"
		local big = e.last == true
		add(P, "pillar", x, y, if big then 4.4 else 3.2, if big then 0.9 else 0.7, ramp, { b = "earth", seed = P.seed, fadeAt = 0.7 })
		add(P, "ring", x, y + 0.15, if big then 12 else 7, 0.3, ramp, { sy = 0.28 })
		if big then
			add(P, "flame", x, y, 3.4, 0.6, "fire", { seed = P.seed })
			add(P, "burst", x, y + 6, 6, 0.42, ramp, { delay = 0.06 })
			flash(P, 0.22, glow)
		end
	elseif t == "heartseeker" then
		local dir = e.facing or 1
		add(P, "ring", x, y, 4.2, 0.26, glow, { rot = math.pi / 2, sy = 0.35 })
		add(P, "ring", x - dir * 1.4, y, 3.0, 0.22, glow, { rot = math.pi / 2, sy = 0.35, delay = 0.04 })
		add(P, "pop", x, y, 3.4, 0.18, glow, { rot = if dir < 0 then math.pi else 0 })
		flash(P, 0.16, glow)
	elseif t == "anchorset" then
		add(P, "burst", x, y + 0.6, 4.2, 0.36, "earth")
		add(P, "ring", x, y + 0.1, 6, 0.3, glow, { sy = 0.3 })
		add(P, "pop", x, y + 0.4, 3.2, 0.2, glow)
	elseif t == "anchorsnap" then
		add(P, "burst", x, y + 0.6, 7, 0.45, glow)
		add(P, "ring", x, y + 0.4, 9, 0.34, glow)
		radialBolts(P, x, y + 0.6, 5, 5.5, glow)
		flash(P, 0.22, glow)
	elseif t == "aegis" then
		add(P, "ring", x, y, 3.6, 0.24, glow or "volt")
		add(P, "pop", x, y, 3.0, 0.2, glow or "volt")
	elseif t == "aegisbreak" then
		local k = math.clamp((e.stored or 0) / 40, 0, 1)
		add(P, "burst", x, y, 8 + k * 4, 0.5, glow or "volt")
		add(P, "ring", x, y, 12 + k * 4, 0.38, glow or "volt")
		radialBolts(P, x, y, 6, 6 + k * 3, glow or "volt")
		flash(P, 0.3, glow)
	elseif t == "bleedmark" then
		add(P, "xslash", x, y, 2.4, 0.2, "blood", { seed = P.seed })
	elseif t == "exsanguinate" then
		local n = math.min(12, e.marks or 1)
		add(P, "burst", x, y, 3 + n * 0.45, 0.42, "blood")
		add(P, "xslash", x, y, 3.6 + n * 0.25, 0.28, glow or "blood", { seed = P.seed })
		add(P, "ring", x, y, 4 + n * 0.5, 0.3, "blood")
		if n >= 6 then flash(P, 0.14 + n * 0.01, "#FF4A6A") end
	end
	-- Earthshatter's crater is not an ultimate's: its own rings stay
	return s ~= nil or t ~= "crater"
end

function FxPlayer.step(P: any, dt: number)
	local keep = {}
	for _, it in P.items do
		if it.delay > 0 then
			it.delay -= dt
		else
			it.age += dt
		end
		if it.age < it.dur then table.insert(keep, it) end
	end
	P.items = keep
	P.flash = math.max(0, P.flash - dt * 5)
end

function FxPlayer.draw(P: any, c: any)
	for _, it in P.items do
		if it.delay > 0 then continue end
		local u = it.age / it.dur
		local n = FxArt.FRAMES[it.kind] or 1
		local art = FxArt.get(it.kind, math.floor(u * n), it.ramp, it.b, it.seed)
		local scale = it.size * art.ppu / art.cols
		local alpha = 1
		if it.fadeAt and u > it.fadeAt then alpha = 1 - (u - it.fadeAt) / (1 - it.fadeAt) end
		FxArt.draw(c, art, it.x, it.y, scale, it.rot, alpha, it.sy)
	end
end

return FxPlayer
