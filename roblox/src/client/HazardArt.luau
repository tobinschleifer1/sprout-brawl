--!strict
-- The stages' hazards, drawn in the realms' pixel art - ROBLOX ONLY. A hazard is a stage's small,
-- permanent feature (Hazards.luau, held to web/src/engine/hazards.js); its view (`stage.visual`)
-- arrives with the scene, and everything here is placed from that view and nothing else.
--
--   vents        Dwarven Forge   grates in the floor that breathe smoke, then erupt as fire
--   slagfall     Dwarven Forge   molten drops from a crucible's lip, spitting where they land
--   sprinkler    Sky Temple      a fountain's spray sweeping the floor, leaving it wet
--   antennaarc   Sky Temple      a crackle of lightning strung between two rods
--   dustdevil    Sunscorch       a small funnel of the realm's sand crossing the floor
--   sandfall     Sunscorch       sand pouring from above in a stream
--   tide         Viking Harbor   the sea either side of the island, rising and falling
--   roguewave    Viking Harbor   a breaker running along the tide
--   crosswind    Bifrost Bridge  streaks of wind and the bridge's light blown across
--   emberdrift   Hall            sparks rising off the island's edges
--
-- Warnings keep the shared rule: cool cyan for "about to", hot for "now".
local Canvas2D = require(script.Parent.Canvas2D)
local FxArt = require(script.Parent.FxArt)
local PixelGrid = require(script.Parent.PixelGrid)
local RealmArt = require(script.Parent.RealmArt)
local DisasterArt = require(script.Parent.DisasterArt)
local DisasterShapes = require(script.Parent.DisasterShapes)

local HazardArt = {}

local COOL, HOT = DisasterShapes.COOL, DisasterShapes.HOT
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(18, 14, 22)
local mix = RealmArt.mix
local hash = PixelGrid.hash
local sized = FxArt.sized
local TILE, P = DisasterArt.TILE, DisasterArt.P

local function hex(h: string): Color3
	return Canvas2D.hex(h, WHITE)
end

local DRAW: { [string]: (any, any, any, any, number) -> () } = {}

DRAW.vents = function(c, v, stage, realm, t)
	local top = stage.main.top
	local iron, slot = hex(realm.shelfRamp[1]), hex(realm.shelfRamp[2])
	for i, x in v.positions do
		local armed = table.find(v.armed, x) ~= nil
		local live = armed and v.phase ~= "idle"
		local w = v.width
		-- the grate: an iron frame with glowing slots
		Canvas2D.rect(c, x - w / 2 - 0.2, top - 0.2, w + 0.4, 0.9, INK)
		Canvas2D.rect(c, x - w / 2, top, w, 0.6, iron)
		-- (a shine along its top edge, as every walking surface has: the bare iron frame measured
		-- 1.2-2.8:1 against the forge's smoke)
		Canvas2D.rect(c, x - w / 2, top + 0.45, w, 0.15, hex(realm.shelfRamp[3]))
		for k = 0, 4 do
			local sx = x - w / 2 + 0.5 + k * (w - 1) / 4
			Canvas2D.rect(c, sx, top + 0.1, 0.35, 0.4, if live then hex(HOT) else slot, if live then 1 else 0.8)
		end
		if live and v.phase == "warn" then
			-- breathing: smoke from the slots, and the grate glowing hotter
			for k = 0, 3 do
				local cyc = (t * 0.9 + k / 4) % 1
				local b = FxArt.get("burst", 4 + math.floor(cyc * 3), "smoke", nil, k + 1)
				FxArt.draw(c, b, x + (k - 1.5) * 0.9, top + 0.8 + cyc * 4, sized(b, 1.6 + cyc * 2), 0, 0.8 * (1 - cyc))
			end
			Canvas2D.rect(c, x - w / 2, top + 0.55, w, 0.15, hex(COOL), 0.5 + 0.5 * math.sin(t * 12))
		elseif live then
			-- the eruption: a column of fire the height of its reach
			local h = 26 * v.strength
			local n = math.max(1, math.ceil(h / 6))
			for k = 0, n - 1 do
				local fl = FxArt.get("flame", math.floor(t * 14 + k * 2 + i) % 6, "fire", nil, (k % 4) + 1)
				local width = w * (0.9 - k * 0.08)
				FxArt.draw(c, fl, x, top + k * 5.4, sized(fl, math.max(1.5, width)), 0, 1 - k * 0.08)
			end
			for k = 0, 5 do
				local cyc = (t * 1.6 + k / 6) % 1
				FxArt.draw(c, FxArt.get("spark", if cyc > 0.6 then 1 else 0, "fire"), x + math.sin(k * 3 + t * 4) * w * 0.4,
					top + cyc * (h + 4), 0.7, 0, 1 - cyc)
			end
		end
	end
end

DRAW.slagfall = function(c, v, _stage, _realm, t)
	-- the crucible's lip it pours from
	Canvas2D.rect(c, v.x - v.spread / 2 - 0.4, v.from, v.spread + 0.8, 0.8, INK)
	Canvas2D.rect(c, v.x - v.spread / 2, v.from + 0.1, v.spread, 0.5, hex("#3A2E2E"))
	Canvas2D.rect(c, v.x - v.spread / 2, v.from + 0.05, v.spread, 0.15, hex(HOT), 0.7 + 0.3 * math.sin(t * 8))
	for i, d in v.drops do
		Canvas2D.rect(c, d.x - 0.15, d.y + 0.4, 0.3, 1.4, hex("#FFB43C"), 0.45)          -- its trail
		FxArt.draw(c, FxArt.get("orb", (i + math.floor(t * 10)) % 4, "fire"), d.x, d.y + 0.2, 0.9, 0, 1)
		if (d.splash or 0) > 0 then
			FxArt.draw(c, FxArt.get("pop", math.floor(t * 20 + i) % 3, "fire", nil, (i % 4) + 1), d.x, d.y + 0.2, 1.2 + d.splash, 0, 1)
		end
	end
end

local function waterOf(realm: any): { string }
	return DisasterArt.realmWater(realm)
end

DRAW.sprinkler = function(c, v, stage, realm, t)
	local W = waterOf(realm)
	local light, body = hex(W[4]), hex(W[3])
	for _, w in v.wet do
		-- the wet floor: a shallow sheen that glints, drying out
		Canvas2D.rect(c, w.x - 1.6, w.y, 3.2, 0.18, body, w.k * 0.75)
		Canvas2D.rect(c, w.x - 1.0 + math.sin(t * 3 + w.x) * 0.5, w.y + 0.12, 0.6, 0.08, WHITE, w.k * 0.8)
	end
	if v.phase == "active" then
		-- the spray: droplets thrown out and falling across the reach
		for i = 0, 17 do
			local k = (t * 1.5 + i / 18) % 1
			local x = v.x + math.sin(i * 5) * v.radius + v.dir * 0.9 * k * v.height * 0.3
			local y = v.height * (1 - k)
			Canvas2D.rect(c, x - 0.18, y, 0.36, 0.8, if i % 3 == 0 then light else body, 0.9)
			if k > 0.9 then
				FxArt.draw(c, FxArt.get("ring", math.floor((k - 0.9) * 50), W[4]), x, stage.main.top + 0.1, 1.2, 0, 0.8, 0.4)
			end
		end
	elseif v.phase == "warn" then
		Canvas2D.rect(c, v.x - v.radius, stage.main.top + 0.2, v.radius * 2, 0.3, hex(COOL), 0.6 + v.k * 0.4)
		DisasterArt.target(c, v.x, stage.main.top, v.radius * 2, 0.4 + 0.5 * v.k)
	end
end

DRAW.antennaarc = function(c, v, _stage, realm, t)
	local active = v.phase == "active"
	-- the two lightning rods, always there: a floating stone plinth with a copper spike, its tip
	-- charging blue before the arc and white during it
	for _, x in { v.x1, v.x2 } do
		Canvas2D.rect(c, x - 0.9, v.y - 3.4, 1.8, 1.1, INK)
		Canvas2D.rect(c, x - 0.75, v.y - 3.3, 1.5, 0.9, hex(realm.rock[3]))
		Canvas2D.rect(c, x - 0.75, v.y - 2.6, 1.5, 0.2, hex(realm.rock[4]))
		Canvas2D.rect(c, x - 0.15, v.y - 2.4, 0.3, 2.4, hex("#B4703A"))
		local tip = if active then "volt" elseif v.phase ~= "idle" then COOL else nil
		if tip then
			FxArt.draw(c, FxArt.get("orb", math.floor(t * 12) % 4, tip), x, v.y, if active then 1.8 else 1.1, 0, 1)
		else
			Canvas2D.rect(c, x - 0.2, v.y - 0.1, 0.4, 0.4, hex("#E8A866"))
		end
	end
	if v.phase == "idle" then return end
	local len = v.x2 - v.x1
	local n = math.max(1, math.floor(len / 5))
	local seg = len / n
	local flick = math.floor(t * 24)
	for i = 0, n - 1 do
		if active or (flick + i) % 4 == 0 then
			local b = FxArt.get("bolt", (flick + i) % 4, if active then "volt" else COOL, nil, (i % 4) + 1)
			FxArt.draw(c, b, v.x1 + i * seg, v.y + (hash(i, flick, 3) - 0.5) * 0.8, sized(b, seg * 1.05), 0, if active then 1 else 0.5)
		end
	end
end

DRAW.dustdevil = function(c, v, stage, realm, t)
	local top = stage.main.top
	local dust = mix(realm.rock[4], realm.top[2], 0.35)
	if v.active then
		local art = DisasterArt.funnel(math.floor(t * 12) % 4, FxArt.ramp(dust), v.radius * 2, v.height)
		DisasterArt.draw(c, art, v.x, top, 1 / 4, 0.85)
		for i = 0, 3 do
			local cyc = (t * 1.6 + i / 4) % 1
			Canvas2D.rect(c, v.x + math.cos(t * 5 + i * 1.6) * v.radius, top + cyc * v.height * 0.6, 0.3, 0.3,
				hex(realm.rock[2]), 1 - cyc)
		end
	elseif v.warn then
		DisasterArt.target(c, v.from, top, 4, 0.4 + 0.5 * v.warnK)
		local b = FxArt.get("burst", 5, dust, nil, 2)
		FxArt.draw(c, b, v.from, top + 0.4, sized(b, 2 + v.warnK * 2), t * 4, 0.6 * v.warnK)
	end
end

DRAW.sandfall = function(c, v, _stage, realm, t)
	if v.phase == "idle" then return end
	local grains = { hex(realm.top[1]), hex(realm.top[2]), hex(realm.top[3]) }
	local active = v.phase == "active"
	-- the spout it pours from: a crumbling lip of the realm's rock
	Canvas2D.rect(c, v.x - v.width / 2 - 0.6, v.from, v.width + 1.2, 1.2, INK)
	Canvas2D.rect(c, v.x - v.width / 2 - 0.4, v.from + 0.1, v.width + 0.8, 1, hex(realm.rock[3]))
	Canvas2D.rect(c, v.x - v.width / 2 - 0.4, v.from + 0.8, v.width + 0.8, 0.3, hex(realm.top[2]))
	if active then
		-- a curtain of falling sand: columns of grain running down at their own speeds
		for col = 0, 6 do
			local cx = v.x + (col - 3) / 3 * v.width * 0.42
			local speed = 0.8 + (col % 3) * 0.15
			for seg = 0, 3 do
				local k = (t * speed + seg / 4 + col * 0.13) % 1
				local y = v.from + (v.to - v.from) * k
				Canvas2D.rect(c, cx - 0.2, y - 1.2, 0.4, 2.4, grains[(col + seg) % 3 + 1], 0.95)
			end
		end
	else
		for i = 0, 7 do
			local k = (t * 0.9 + i / 8) % 1
			Canvas2D.rect(c, v.x + math.sin(i * 31) * v.width / 2 - 0.15, v.from - k * 2, 0.3, 0.5, grains[(i % 3) + 1], 0.7)
		end
	end
	if active then
		-- the heap it builds where it lands
		local b = FxArt.get("burst", 4 + math.floor(t * 8) % 3, realm.top[2], nil, 3)
		FxArt.draw(c, b, v.x, v.to + 0.3, sized(b, v.width * 1.6), 0, 0.8, 0.45)
	else
		Canvas2D.rect(c, v.x - v.width / 2, v.to + 0.2, v.width, 0.3, hex(COOL), 0.6)
	end
end

DRAW.tide = function(c, v, stage, realm, t)
	local W = waterOf(realm)
	local art = DisasterArt.liquid("water", math.floor(t * 6) % 8, W)
	for _, side in { -1, 1 } do
		-- outward from the island's edge, whole tiles at a time, so no tile reaches over the island
		local inner = side * v.edge
		local outer = if side < 0 then stage.blast.left else stage.blast.right
		local x1, x2 = math.min(inner, outer), math.max(inner, outer)
		Canvas2D.rect(c, x1, stage.blast.bottom, x2 - x1, v.level - 9 - stage.blast.bottom, hex(W[2]), 0.92)
		local x = inner
		while (x - outer) * side < 0 do
			local left = if side > 0 then x else x - TILE
			DisasterArt.draw(c, art, left, v.level + 1, 1 / P, 0.92)
			x += side * TILE
		end
	end
end

-- The same sea behind the island, so what shows under its belly is the water and not the sky's far
-- sea (round 5: a grey column the width of the island, between two saturated seas). Drawn before
-- the stage, whole tiles from the left edge's water onward, so it continues that side's pattern.
local BACK: { [string]: (any, any, any, any, number) -> () } = {}
BACK.tide = function(c, v, stage, realm, t)
	local W = waterOf(realm)
	local art = DisasterArt.liquid("water", math.floor(t * 6) % 8, W)
	Canvas2D.rect(c, -v.edge, stage.blast.bottom, v.edge * 2, v.level - 9 - stage.blast.bottom, hex(W[2]), 0.92)
	local x = -v.edge
	while x < v.edge do
		DisasterArt.draw(c, art, x, v.level + 1, 1 / P, 0.92)
		x += TILE
	end
end

DRAW.roguewave = function(c, v, stage, realm, t)
	local W = waterOf(realm)
	local y = if stage.visual and stage.visual.tide then stage.visual.tide.level else stage.main.top
	if v.active then
		local art = DisasterArt.curl(math.floor(t * 10) % 3, W, v.crest, 0.2)
		Canvas2D.save(c)
		Canvas2D.translate(c, v.x + v.dir * v.width / 2, y)
		Canvas2D.scale(c, v.dir, 1)
		DisasterArt.draw(c, art, 0, 0, 1 / (P * 1.6), 1)
		Canvas2D.restore(c)
	elseif v.warn then
		-- foam gathering along the line it will run
		for x = stage.main.x1, stage.main.x2, 2.5 do
			Canvas2D.rect(c, x, y + 0.4, 1.4, 0.2, WHITE, 0.4 + 0.5 * v.warnK)
		end
		DisasterArt.chevron(c, if v.dir > 0 then stage.main.x1 - 3 else stage.main.x2 + 3, y + 2, 1, hex(COOL), 0.5 + 0.5 * v.warnK, v.dir)
	end
end

DRAW.crosswind = function(c, v, stage, realm, t)
	if v.phase == "calm" then return end
	local gust = v.phase ~= "warn"
	local top = stage.main.top
	local span = stage.main.x2 - stage.main.x1
	for i = 0, 13 do
		local x = stage.main.x1 + ((i * 7.3 + t * 18 * v.dir) % span)
		local y = top + 2.5 + (i * 1.9) % 16
		local len = if gust then 4.5 + (i % 3) * 1.2 else 1.4
		-- a streak, fat in the middle and thin at the ends
		Canvas2D.rect(c, x - len / 2, y, len, 0.16, WHITE, 0.6)
		Canvas2D.rect(c, x - len / 4, y - 0.06, len / 2, 0.28, WHITE, 0.75)
		if gust and i % 3 == 0 then
			-- the bridge's light, torn off and blown along
			local bands = { "#FF5A5A", "#FFB34A", "#FFE45A", "#5AE08A", "#4AB4FF", "#9A6AFF" }
			local col = if realm.material == "light" then bands[(i // 3) % 6 + 1] else realm.top[3]
			Canvas2D.rect(c, x + v.dir * len * 0.6, y + math.sin(t * 6 + i) * 0.4, 0.5, 0.5, hex(col), 0.95)
		end
	end
	if not gust then
		DisasterArt.chevron(c, if v.dir > 0 then stage.main.x1 + 2 else stage.main.x2 - 2, top + 6, 1, hex(COOL), 0.8, v.dir)
	end
end

DRAW.emberdrift = function(c, v, _stage, realm, t)
	for j, x in v.positions do
		for i = 0, 7 do
			local k = (t * 0.3 + i / 8) % 1
			local ex = x + math.sin(i * 13 + t) * v.width / 2
			local ey = v.from + (v.to - v.from) * k
			local spark = FxArt.get("spark", if k > 0.75 then 1 else 0, realm.glow)
			FxArt.draw(c, spark, ex, ey, 1.1, 0, v.pulse * (1 - k * 0.5))
		end
		-- the glow they rise from
		FxArt.draw(c, FxArt.get("orb", math.floor(t * 8 + j) % 4, realm.glow), x, v.from, v.width * 0.5, 0, 0.5 * v.pulse)
	end
end

HazardArt.ORDER = { "tide", "vents", "slagfall", "sprinkler", "antennaarc", "dustdevil", "sandfall", "roguewave", "crosswind", "emberdrift" }

-- Every hazard on the stage, in a fixed order (the tide first: the others stand in it).
function HazardArt.draw(c: any, visual: any, stage: any, realm: any, t: number)
	for _, name in HazardArt.ORDER do
		local v = visual[name]
		if v then DRAW[name](c, v, stage, realm, t) end
	end
end

-- What a hazard draws behind the stage (only the tide, so far).
function HazardArt.back(c: any, visual: any, stage: any, realm: any, t: number)
	for name, fn in BACK do
		local v = visual[name]
		if v then fn(c, v, stage, realm, t) end
	end
end

return HazardArt
