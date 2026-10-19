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
local Cosmetics = require(game:GetService("ReplicatedStorage").Shared.Cosmetics)

local FxPlayer = {}

-- Never more than this many effects alive. A four-player match of overlapping ultimates peaks
-- around twenty; the cap only bites on a pile-up, and drops the oldest, which have mostly played.
FxPlayer.MAX = 40
-- The colour a fighter's shield shatters in, by fighter index; set by FightScene (ShieldArt).
FxPlayer.shieldColour = nil :: ((number?) -> string)?

export type Item = {
	kind: string, x: number, y: number, age: number, dur: number, size: number,
	rot: number, ramp: string?, b: string?, seed: number, sy: number?, delay: number,
	fadeAt: number?,
}

function FxPlayer.new(): any
	return { items = {} :: { Item }, flash = 0, flashColour = "#FFFFFF", seed = 0, glows = {}, emotes = {} }
end

function FxPlayer.clear(P: any)
	table.clear(P.items)
	P.flash = 0
	table.clear(P.glows)
	table.clear(P.emotes)
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
	exsanguinate = "bleed", lash = "stormlash",
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

local glowOf = FxArt.glowOf

local function stateOf(states: { any }, index: number?): any
	if index == nil then return nil end
	for _, s in states do
		if s.index == index then return s end
	end
	return nil
end

-- ------------------------------------------------------------------ hits ----
-- How each weapon's hits look: blades cut, heavy things crunch, points pierce, magic bursts.
FxPlayer.CLASS = {
	Sword = "slash", Axe = "slash", Scythe = "slash", Daggers = "slash", Whip = "slash",
	Hammer = "blunt", Gauntlets = "blunt", Flail = "blunt", Shield = "blunt",
	Pike = "pierce", Longbow = "pierce", Blasters = "pierce",
	Grimoire = "magic",
	RocketBoots = "kick", -- (Roblox only)
}

-- Every landed hit, in the attacker's weapon colour and style, sized by its damage and aimed along
-- the knockback: a crescent cut across the line of the blow, a crunch star, a streak driven
-- through, a burst of starlight. Heavy hits on a grounded victim kick up dust under them. An
-- ultimate's hits are bigger again. Effects still throws the sparks; its rings are dropped.
-- Hits use one variation of each drawing: they already differ by the angle they are aimed along,
-- and every variation is a sprite built the first time it is seen (ult-fx holds the budget).
local ONE = { seed = 0 }
-- A timed link's flash over the fighter (COMBO): gold, for this long.
FxPlayer.PERFECT = "#FFD24A"
FxPlayer.GLOW_TIME = 0.1

-- The hit effects players can wear (Cosmetics, type hit_effect; Roblox only). One with a `ramp`
-- recolours the weapon's own hit drawing (the class below) into that ramp; these draw their own.
FxPlayer.HIT_STYLES = {
	hit_comicpow = function(P: any, x: number, y: number, size: number, dir: number, dur: number, heavy: boolean)
		add(P, "star", x, y, size * 1.6, dur + 0.06, "gold", ONE)
		add(P, "pop", x, y, size * 1.1, dur, "red", { rot = dir, seed = 0 })
		if heavy then add(P, "burst", x, y, size * 1.4, dur + 0.08, "gold", ONE) end
	end,
	hit_supernova = function(P: any, x: number, y: number, size: number, dir: number, dur: number, heavy: boolean)
		add(P, "star", x, y, size * 1.4, dur + 0.04, "gold", ONE)
		add(P, "ring", x, y, size * 1.6, dur, "gold", ONE)
		if heavy then
			for k = 0, 4 do
				local a = k / 5 * math.pi * 2 + dir
				add(P, "star", x + math.cos(a) * size, y + math.sin(a) * size, size * 0.6, dur, "gold", { seed = 0, delay = 0.03 + k * 0.01 })
			end
		end
	end,
	hit_eventhorizon = function(P: any, x: number, y: number, size: number, dir: number, dur: number, heavy: boolean)
		add(P, "cyclone", x, y, size * 1.5, dur + 0.1, "void", ONE)
		add(P, "ring", x, y, size * 2.2, dur + 0.06, "void", { seed = 0, delay = 0.04 })
		add(P, "spark", x, y, size * 0.8, 0.16, "star", ONE)
		if heavy then flash(P, 0.14, "#8A3FE0") end
	end,
} :: { [string]: (any, number, number, number, number, number, boolean) -> () }

function FxPlayer.hit(P: any, e: any, states: { any }, chars: { any }): boolean
	local s = stateOf(states, e.attacker)
	local char = if s then chars[s.index + 1] else nil
	if not s or not char then return false end
	local glow = glowOf(char)
	local class = FxPlayer.CLASS[char.weapon and char.weapon.id or ""] or "blunt"
	local ult = inUltimate(s, char) ~= nil
	local size = math.clamp(1.6 + (e.damage or 4) * 0.12, 1.8, 4) * (if e.heavy then 1.25 else 1) * (if ult then 1.25 else 1)
	-- the direction the victim is sent
	local a = math.rad(e.angle or 45)
	local dir = math.atan2(math.sin(a), math.cos(a) * (e.facing or 1))
	local dur = if e.heavy then 0.24 else 0.18
	-- a worn hit effect: its own drawing, or the weapon's drawing in its ramp
	local worn = char.cosmetics and char.cosmetics.hit
	local style = worn and FxPlayer.HIT_STYLES[worn]
	if style then
		style(P, e.x, e.y, size, dir, dur, e.heavy == true)
		class = "worn"
	elseif worn then
		local it = Cosmetics.get(worn)
		if it and it.ramp then glow = it.ramp end
	end
	if class == "worn" then
		-- (drawn above)
	elseif class == "slash" then
		add(P, "crescent", e.x, e.y, size * 1.5, dur, glow, { rot = dir + math.pi / 2, seed = 0 })
		add(P, "spark", e.x, e.y, size * 0.6, 0.16, glow, ONE)
		if e.heavy then add(P, "xslash", e.x, e.y, size * 1.2, dur, glow, ONE) end
	elseif class == "pierce" then
		add(P, "lance", e.x - math.cos(dir) * size, e.y - math.sin(dir) * size, size * 2.2, 0.14, glow, { rot = dir, sy = 0.5, seed = 0 })
		add(P, "pop", e.x, e.y, size * 0.9, dur, glow, { rot = dir, seed = 0 })
	elseif class == "magic" then
		add(P, "star", e.x, e.y, size * 1.3, dur, glow, ONE)
		add(P, "pop", e.x, e.y, size, dur, "star", ONE)
	elseif class == "kick" then
		-- a boot landing: a pop of exhaust fire, a shock ring in the boots' glow, and the jet's
		-- streak driven through along the blow; a heavy kick adds a second, wider ring of fire.
		-- (A "burst" explosion read better but built 440 Frames the first time: tests/perf-budget.)
		add(P, "pop", e.x, e.y, size * 1.2, dur + 0.06, "fire", { rot = dir, seed = 0 })
		add(P, "ring", e.x, e.y, size * 1.5, dur, glow, ONE)
		add(P, "lance", e.x - math.cos(dir) * size, e.y - math.sin(dir) * size, size * 2.0, 0.14, "fire", { rot = dir, sy = 0.5, seed = 0 })
		if e.heavy then add(P, "ring", e.x, e.y, size * 2.4, dur + 0.04, "fire", { seed = 0, delay = 0.04 }) end
	else
		add(P, "pop", e.x, e.y, size * 1.15, dur, glow, { rot = (P.seed % 8) * 0.39, seed = 0 })
		if e.heavy then add(P, "ring", e.x, e.y, size * 1.8, dur, glow, ONE) end
	end
	-- A finisher (COMBO, config.js): the end of a string linked perfectly all the way. Its impact
	-- goes off two sizes up, in a gold burst under the weapon's own, with a flash of the screen and
	-- the hardest shake a hit gives (FightScene.spawn).
	if e.finisher then
		add(P, "burst", e.x, e.y, size * 2.4, 0.36, "gold", ONE)
		add(P, "ring", e.x, e.y, size * 3.6, 0.34, glow, ONE)
		add(P, "ring", e.x, e.y, size * 2.2, 0.26, "gold", { seed = 0, delay = 0.05 })
		flash(P, 0.26, glow or "#FFE07A")
	end
	if e.heavy then
		local v = stateOf(states, e.victim)
		if v and v.onGround then
			local vc = chars[v.index + 1]
			add(P, "burst", v.x, v.y + 0.4, 3.2, 0.5, "smoke", { delay = 0.03, fadeAt = 0.5, seed = 0 })
			if vc then add(P, "ring", v.x, v.y + 0.1, vc.radius * 5, 0.3, "#D9D2C2", { sy = 0.28, seed = 0 }) end
		end
	end
	return true
end

-- Bolts thrown out radially from (x, y): a discharge.
local function radialBolts(P: any, x: number, y: number, n: number, length: number, ramp: string?)
	for i = 0, n - 1 do
		local a = (i / n) * math.pi * 2 + (P.seed % 5) * 0.4
		add(P, "bolt", x, y, length, 0.28, ramp, { rot = a, seed = P.seed + i, delay = i * 0.02 })
	end
end

-- The KO effects players can wear (Cosmetics, type ko_effect; Roblox only): drawn at the blast line
-- for the stock the wearer takes, in place of the plain KO burst.
local function scatter(P: any, x: number, y: number, n: number, r: number, size: number, ramp: string?, kind: string?)
	for k = 0, n - 1 do
		local a = k / n * math.pi * 2 + 0.4
		add(P, kind or "spark", x + math.cos(a) * r, y + math.sin(a) * r, size, 0.3, ramp, { rot = a, seed = 0, delay = 0.02 + k * 0.012 })
	end
end
FxPlayer.KO_STYLES = {
	ko_balloonpop = function(P: any, x: number, y: number)
		add(P, "pop", x, y, 5, 0.3, "#FF6A8A", ONE)
		scatter(P, x, y, 8, 2.6, 1.2, "#FFE07A")
	end,
	ko_ghostrise = function(P: any, x: number, y: number)
		add(P, "pillar", x, y, 4, 0.6, "#DDE6FF", ONE)
		add(P, "ring", x, y, 6, 0.4, "#DDE6FF", { seed = 0, sy = 0.4 })
	end,
	ko_firework = function(P: any, x: number, y: number)
		-- (two shells, not three: a third colour built 1,276 rectangles the first time it played)
		add(P, "burst", x, y, 6, 0.45, "red", ONE)
		add(P, "burst", x + 2.5, y + 1.5, 4.5, 0.45, "gold", { seed = 0, delay = 0.12 })
		add(P, "star", x - 1.5, y + 2, 3, 0.3, "gold", { seed = 0, delay = 0.24 })
	end,
	ko_pixelshatter = function(P: any, x: number, y: number)
		add(P, "xslash", x, y, 6, 0.32, "#E8ECF2", ONE)
		scatter(P, x, y, 12, 3.2, 1.0, "#E8ECF2", "spark")
		flash(P, 0.18, "#FFFFFF")
	end,
	ko_meteor = function(P: any, x: number, y: number)
		add(P, "comet", x, y + 3, 7, 0.32, "fire", { rot = -math.pi / 2.6, seed = 0 })
		add(P, "burst", x, y, 7, 0.5, "fire", { seed = 0, delay = 0.12 })
		add(P, "ring", x, y, 10, 0.42, "smoke", { seed = 0, delay = 0.16, sy = 0.35 })
	end,
	ko_blackhole = function(P: any, x: number, y: number)
		add(P, "cyclone", x, y, 7, 0.7, "void", ONE)
		add(P, "ring", x, y, 11, 0.5, "void", { seed = 0, delay = 0.1 })
		add(P, "star", x, y, 2.4, 0.3, "star", { seed = 0, delay = 0.45 })
		flash(P, 0.22, "#33135C")
	end,
	ko_dragonsbreath = function(P: any, x: number, y: number)
		add(P, "comet", x - 6, y + 4, 12, 0.4, "fire", { rot = -0.5, seed = 0 })
		add(P, "pillar", x, y, 8, 0.6, "fire", { seed = 0, delay = 0.1 })
		add(P, "burst", x, y, 10, 0.6, "fire", { seed = 0, delay = 0.18 })
		add(P, "ring", x, y, 14, 0.5, "gold", { seed = 0, delay = 0.22 })
		flash(P, 0.3, "#F2621B")
	end,
} :: { [string]: (any, number, number) -> () }

-- The spawn effects players can wear (Cosmetics, type spawn_effect; Roblox only): drawn where the
-- wearer reappears after losing a stock. `x, y` are their feet, `h` their height.
FxPlayer.SPAWN_STYLES = {
	spawn_confetti = function(P: any, x: number, y: number, h: number)
		add(P, "burst", x, y + h * 0.5, h * 1.1, 0.4, "gold", ONE)
		scatter(P, x, y + h * 0.6, 8, h * 0.5, 1.0, "#FF8AC8")
	end,
	spawn_portal = function(P: any, x: number, y: number, h: number)
		add(P, "ring", x, y + h * 0.5, h * 1.6, 0.5, "void", { seed = 0, sy = 1.4 })
		add(P, "swirl", x, y + h * 0.5, h * 1.1, 0.5, "void", ONE)
	end,
	spawn_droppod = function(P: any, x: number, y: number, h: number)
		add(P, "comet", x, y + h * 1.4, h * 1.4, 0.3, "wind", { rot = -math.pi / 2, seed = 0 })
		add(P, "ring", x, y + 0.1, h * 2.2, 0.36, "smoke", { seed = 0, sy = 0.3, delay = 0.12 })
	end,
	spawn_lightning = function(P: any, x: number, y: number, h: number)
		add(P, "bolt", x, y + h * 1.2, h * 2.4, 0.3, "volt", { rot = -math.pi / 2, seed = 0 })
		add(P, "pop", x, y + 0.2, h * 0.9, 0.24, "volt", { seed = 0, delay = 0.06 })
		flash(P, 0.12, "#9BE8FF")
	end,
	spawn_vipsparkle = function(P: any, x: number, y: number, h: number)
		add(P, "star", x, y + h * 0.55, h * 0.9, 0.36, "gold", ONE)
		scatter(P, x, y + h * 0.55, 6, h * 0.55, 0.9, "gold", "star")
	end,
} :: { [string]: (any, number, number, number) -> () }

-- Returns true when this event was drawn here, so the caller can leave out the plain impact rings
-- Effects would draw over it (see FightScene.spawn).
function FxPlayer.spawn(P: any, e: any, states: { any }, chars: { any }): boolean
	local t = e.type
	if t == "emote" then
		local old = P.emotes[e.fighter]
		if not old or e.start >= old.start then P.emotes[e.fighter] = e end
		return true
	elseif t == "respawn" then
		-- the reappearing fighter's spawn effect, if they wear one
		local s = stateOf(states, e.fighter)
		local char = if e.fighter ~= nil then chars[e.fighter + 1] else nil
		local style = char and char.cosmetics and char.cosmetics.spawn and FxPlayer.SPAWN_STYLES[char.cosmetics.spawn]
		if not style or not s then return false end
		style(P, s.x, s.y, char.height)
		return true
	end
	if t == "ko" then
		-- the stock's taker's KO effect, if they wear one; otherwise the plain burst (Effects)
		local by = if type(e.by) == "number" and e.by >= 0 then chars[e.by + 1] else nil
		local style = by and by.cosmetics and by.cosmetics.ko and FxPlayer.KO_STYLES[by.cosmetics.ko]
		if not style then return false end
		style(P, e.x or 0, e.y or 0)
		return true
	end
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
		return FxPlayer.hit(P, e, states, chars)
	end
	-- ---- combos (COMBO in config.js) ----
	if t == "perfectlink" then
		-- A timed link: a gold star where the fighter is, bigger the longer the streak, and a brief
		-- gold flash over the fighter's own silhouette (P.glows, read by Fighter2D via FightScene).
		local s = stateOf(states, e.fighter)
		local char = if s then chars[s.index + 1] else nil
		local streak = math.min(e.streak or 1, 4)
		local x, y = e.x or (s and s.x) or 0, e.y or (if s and char then s.y + char.height * 0.5 else 0)
		local size = 1.6 + streak * 0.5 + (if e.finisher then 1 else 0)
		add(P, "star", x, y, size, 0.22, "gold", ONE)
		add(P, "ring", x, y, size * 1.6, 0.24, "gold", ONE)
		if e.fighter ~= nil then P.glows[e.fighter] = { colour = FxPlayer.PERFECT, left = FxPlayer.GLOW_TIME } end
		return true
	end
	if t == "combobreak" then
		-- The break: a shockwave in the breaker's shield colour, and shards of the combo flung out.
		local col = FxPlayer.shieldColour and FxPlayer.shieldColour(e.fighter) or "#4FC8FF"
		local x, y = e.x or 0, e.y or 0
		add(P, "burst", x, y, 6, 0.34, col, ONE)
		add(P, "ring", x, y, 10, 0.36, col, ONE)
		add(P, "ring", x, y, 6, 0.3, "#FFFFFF", { seed = 0, delay = 0.04, sy = 0.5 })
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			add(P, "spark", x + math.cos(a) * 2.2, y + math.sin(a) * 2.2, 1.2, 0.26, col, { rot = a, seed = 0, delay = k * 0.012 })
		end
		flash(P, 0.16, col)
		return true
	end
	if t == "chase" then
		-- The chase: a streak in the attacker's weapon colour, aimed at the fighter they are after.
		local s, v = stateOf(states, e.fighter), stateOf(states, e.victim)
		local char = if s then chars[s.index + 1] else nil
		if not s or not v or not char then return false end
		local cy = s.y + char.height * 0.5
		local vc = chars[v.index + 1]
		local a = math.atan2(v.y + (if vc then vc.height * 0.5 else 2.5) - cy, v.x - s.x)
		add(P, "lance", s.x - math.cos(a) * 1.5, cy - math.sin(a) * 1.5, 4.5, 0.18, glowOf(char), { rot = a, sy = 0.6, seed = 0 })
		return true
	end
	if t == "cancel" then
		-- A cancel: a small puff where the fighter cut the move short.
		local s = stateOf(states, e.fighter)
		add(P, "pop", e.x or (s and s.x) or 0, (s and s.y or e.y or 0) + 0.4, 1.8, 0.18, "wind", ONE)
		return true
	end
	if t == "shieldbreak" then
		-- the shell shatters: a burst in its colour and shards flung out of it
		local s = stateOf(states, e.fighter)
		local char = if s then chars[s.index + 1] else nil
		local x, y = e.x or (s and s.x) or 0, e.y or (if s and char then s.y + char.height * 0.5 else 0)
		local col = FxPlayer.shieldColour and FxPlayer.shieldColour(e.fighter) or "#4FC8FF"
		add(P, "burst", x, y, 7, 0.4, col)
		add(P, "ring", x, y, 9, 0.32, col)
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2 + 0.3
			add(P, "spark", x + math.cos(a) * 2.6, y + math.sin(a) * 2.6, 1.4, 0.3, col, { delay = k * 0.015 })
		end
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
	elseif t == "lash" then
		-- STORM LASH: every crack on the dome snaps - a bolt where the tip breaks the air - and the
		-- last, out in front, bursts like a thunderclap.
		local ramp = glow or "gold"
		if e.last then
			add(P, "burst", x, y, 6.5, 0.42, ramp)
			add(P, "ring", x, y, 9, 0.34, ramp)
			add(P, "bolt", x, y, 4.6, 0.26, ramp, { seed = P.seed })
			flash(P, 0.22, glow)
		else
			add(P, "bolt", x, y, 2.4, 0.16, ramp, { seed = P.seed + (e.step or 0) })
			add(P, "pop", x, y, 2.2, 0.14, ramp, { rot = (e.step or 0) * 0.5 })
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
	-- Compact in draw order without allocating a replacement array every render frame. Effects
	-- overlap translucently, so swapping the last survivor into an expired slot would change art.
	local items, kept = P.items, 0
	for _, it in items do
		if it.delay > 0 then
			it.delay -= dt
		else
			it.age += dt
		end
		if it.age < it.dur then kept += 1; items[kept] = it end
	end
	for i = #items, kept + 1, -1 do items[i] = nil end
	P.flash = math.max(0, P.flash - dt * 5)
	for i, g in P.glows do
		g.left -= dt
		if g.left <= 0 then P.glows[i] = nil end
	end
end

function FxPlayer.draw(P: any, c: any)
	for _, it in P.items do
		if it.delay > 0 then continue end
		local u = it.age / it.dur
		local n = FxArt.FRAMES[it.kind] or 1
		local art = FxArt.get(it.kind, math.floor(u * n), it.ramp, it.b, it.seed)
		local scale = FxArt.sized(art, it.size)
		local alpha = 1
		if it.fadeAt and u > it.fadeAt then alpha = 1 - (u - it.fadeAt) / (1 - it.fadeAt) end
		-- an effect that never fades draws as the cheaper stack of layers (FxArt.draw)
		FxArt.draw(c, art, it.x, it.y, scale, it.rot, if it.fadeAt then alpha else nil, it.sy)
	end
end

return FxPlayer
