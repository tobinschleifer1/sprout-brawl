--!strict
-- The realms: every stage re-themed as a floating island (Realms, RealmArt, Stage2D).
--
-- What it holds:
--   * every stage has a realm with its own name, and a realm is paint - dressing a stage changes
--     its name and colours and nothing a match depends on;
--   * the art sits exactly on the geometry: each island's walking surface on the solid's top,
--     from its x1 to its x2, each platform on its own top, moving platforms followed as they move;
--   * the sky covers the screen at every width, and parallaxes;
--   * what it costs: rectangles per stage and per sky, all built once.
--
--     lune run tests/realms
local Loader = require("./loader")
local Stage = Loader.load("Stage")
local Stages = Loader.load("Data/Stages")
local Realms = Loader.load("Realms")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Stage2D = Loader.loadFrom("src/client/", "Stage2D")
local RealmArt = Loader.loadFrom("src/client/", "RealmArt")

local function fail(msg: string): never
	error(msg, 0)
end

-- ------------------------------------------------------------------ the realms ----
local names: { [string]: boolean } = {}
local function hexOk(v: any): boolean
	return type(v) == "string" and string.match(v, "^#%x%x%x%x%x%x$") ~= nil
end
for _, data in Stages.LIST do
	local r = Realms.of(data.id) or fail(`{data.id} has no realm`)
	if r.name == "" or r.name == data.name then fail(`{data.id}: the realm keeps the web's name`) end
	if names[r.name] then fail(`two realms are called {r.name}`) end
	names[r.name] = true
	if Realms.name(data) ~= r.name then fail(`{data.id}: Realms.name is not the realm's name`) end
	for _, key in { "sky", "cloud", "rock", "top", "shelfRamp", "hangRamp" } do
		for _, hex in (r :: any)[key] do
			if not hexOk(hex) then fail(`{data.id}.{key}: {tostring(hex)} is not a colour`) end
		end
	end
	for _, key in { "far", "near", "accent", "glow" } do
		if not hexOk((r :: any)[key]) then fail(`{data.id}.{key} is not a colour`) end
	end
	-- dressing is paint only: the same geometry, the same id, every other field untouched
	local dressed = Realms.dress(data)
	if dressed.id ~= data.id or dressed.name ~= r.name then fail(`{data.id}: dressed id/name wrong`) end
	for k, v in data do
		if k ~= "palette" and k ~= "name" and dressed[k] ~= v then fail(`{data.id}: dressing changed {k}`) end
	end
	if dressed.palette == data.palette then fail(`{data.id}: dressing kept the web palette`) end
end
if Realms.name({ id = "Nowhere", name = "Plain" }) ~= "Plain" then fail("a stage with no realm keeps its own name") end

-- ------------------------------------------------------------------ the art on the geometry ----
local sprites: { any } = {}
local rects = 0
Canvas.rect = function(_c: any) rects += 1 end
Canvas.ellipse = function(_c: any) rects += 1 end
Canvas.sprite = function(c: any, key: string, list: any, x0: number, y1: number, pw: number, ph: number, cols: number, rows: number)
	if #list == 0 then fail(`{key}: an empty sprite`) end
	local m = c.m
	table.insert(sprites, { key = key, list = list, x0 = x0, y1 = y1, pw = pw, ph = ph, cols = cols, rows = rows,
		a = m.a, d = m.d, e = m.e, f = m.f })
end
local function canvas(w: number?, h: number?): any
	return setmetatable({ m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 }, stack = {}, alpha = 1, alphaStack = {},
		gui = { AbsoluteSize = { X = w or 1280, Y = h or 720 } } }, { __index = Canvas })
end
local function find(prefix: string): { any }
	local out = {}
	for _, s in sprites do
		if string.sub(s.key, 1, #prefix) == prefix then table.insert(out, s) end
	end
	return out
end

local worstStage, worstStageWhere = 0, ""
local worstSky, worstSkyWhere = 0, ""
local placed = 0
for _, data in Stages.LIST do
	local realm = Realms.of(data.id) :: any
	local stage = Stage.new(data, 1)
	-- step a while, so moving platforms are somewhere other than where they start
	for _ = 1, 97 do Stage.step(stage, { fighters = {} }) end
	table.clear(sprites)
	Stage2D.draw(canvas(), stage)
	local surfaces = find(`realm|{realm.id}|surface|`)
	local bodies = find(`realm|{realm.id}|island|`)
	local shelves = find(`realm|{realm.id}|shelf|`)
	if #surfaces ~= #stage.solids or #bodies ~= #stage.solids then
		fail(`{data.id}: {#bodies} island bodies and {#surfaces} surfaces for {#stage.solids} solids`)
	end
	local soft = 0
	for _, pl in stage.platforms do if not pl.solid then soft += 1 end end
	if #shelves ~= soft then fail(`{data.id}: {#shelves} platforms drawn for {soft}`) end
	-- the walking surface of each island lies exactly on its solid: top edge on `top`, x1 to x2
	for i, sp in stage.solids do
		local s = surfaces[i]
		local art = RealmArt.surface(realm, sp.x2 - sp.x1, i)
		local topY = s.y1 - art.ay * s.ph
		local left = s.x0 + art.ax * s.pw
		local right = left + math.floor((sp.x2 - sp.x1) * RealmArt.PPU + 0.5) * s.pw
		if math.abs(topY - sp.top) > 1e-9 then fail(`{data.id} solid {i}: surface at y {topY}, the solid's top is {sp.top}`) end
		if math.abs(left - sp.x1) > 1e-9 or math.abs(right - sp.x2) > 0.13 then
			fail(`{data.id} solid {i}: surface spans {left}..{right}, the solid spans {sp.x1}..{sp.x2}`)
		end
		-- and its body hangs from the same top
		local b = bodies[i]
		if math.abs(b.y1 - sp.top) > 1e-9 then fail(`{data.id} solid {i}: the body starts at {b.y1}, not {sp.top}`) end
		placed += 1
	end
	-- each platform on its own top, where the platform is NOW (moving ones included)
	local k = 0
	for _, pl in stage.platforms do
		if not pl.solid then
			k += 1
			local s = shelves[k]
			local art = RealmArt.shelf(realm, pl.x2 - pl.x1, pl.thickness or 1,
				if pl.moving and pl.moving.x and realm.shelf == "minecart" then "minecart" elseif realm.shelf == "minecart" then "wood" else nil)
			local topY = s.y1 - art.ay * s.ph
			local left = s.x0 + art.ax * s.pw
			if math.abs(topY - pl.top) > 1e-9 or math.abs(left - pl.x1) > 1e-9 then
				fail(`{data.id}: a platform drawn at ({left}, {topY}), it is at ({pl.x1}, {pl.top})`)
			end
			placed += 1
		end
	end
	local cost = 0
	for _, s in sprites do cost += #s.list end
	if cost > worstStage then worstStage, worstStageWhere = cost, data.id end
	if cost > 1700 then fail(`{data.id}: the stage art is {cost} rectangles, over 1700`) end

	-- the sky: tiles cover every width, and move with the camera at less than full speed
	for _, size in { { 1280, 720 }, { 2560, 1080 }, { 812, 375 } } do
		table.clear(sprites)
		RealmArt.sky(canvas(size[1], size[2]), realm, 37, 4)
		local s = size[2] / 270
		local layers: { [string]: { any } } = {}
		for _, sp in sprites do
			layers[sp.key] = layers[sp.key] or {}
			table.insert(layers[sp.key], sp)
		end
		local n = 0
		for key, tiles in layers do
			n += 1
			table.sort(tiles, function(a, b) return a.x0 < b.x0 end)
			if tiles[1].x0 > 1e-9 then fail(`{data.id} {key}: the first tile starts at {tiles[1].x0}, leaving a gap`) end
			local reach = tiles[1].x0
			for _, t in tiles do
				if t.x0 > reach + 1e-6 then fail(`{data.id} {key}: a gap between sky tiles`) end
				reach = t.x0 + t.cols * t.pw
			end
			if reach < size[1] / s - 1e-6 then fail(`{data.id} {key}: tiles stop at {reach}, the screen is {size[1] / s} wide`) end
		end
		if n ~= 4 then fail(`{data.id}: {n} sky layers drawn, not 4`) end
	end
	local skyCost = 0
	for _, which in { "far", "landmark", "near", "clouds" } do skyCost += #RealmArt.layer(realm, which).rects end
	if skyCost > worstSky then worstSky, worstSkyWhere = skyCost, data.id end
	if skyCost > 1300 then fail(`{data.id}: the sky is {skyCost} rectangles, over 1300`) end
end

-- Parallax: the far layer moves less than the clouds when the camera pans.
do
	local realm = Realms.LIST[1]
	local function xOf(camX: number, prefix: string): number
		table.clear(sprites)
		RealmArt.sky(canvas(), realm, camX, 0)
		for _, s in sprites do
			if string.find(s.key, prefix, 1, true) then return s.x0 end
		end
		return fail("layer missing")
	end
	local far = math.abs(xOf(10, "|sky|far") - xOf(0, "|sky|far"))
	local near = math.abs(xOf(10, "|sky|clouds") - xOf(0, "|sky|clouds"))
	if not (far > 0 and near > far) then fail(`parallax: far moved {far}, clouds {near}`) end
end

-- The lobby is a realm too: its sky draws (no landmark: three layers), and its paving lies on the
-- plaza it is given - front edge on the front, back edge `depth` behind.
do
	local lobby = Realms.LOBBY
	table.clear(sprites)
	RealmArt.sky(canvas(), lobby, 0, 0)
	local layers: { [string]: boolean } = {}
	for _, sp in sprites do layers[sp.key] = true end
	local n = 0
	for _ in layers do n += 1 end
	if n ~= 3 then fail(`the lobby sky drew {n} layers, want 3`) end
	table.clear(sprites)
	local art = RealmArt.paving(lobby, 40, 10, 1)
	RealmArt.draw(canvas(), art, -20, 2, 1 / RealmArt.BODY_PPU)
	local s = sprites[1]
	local front = s.y1 - s.rows * s.ph
	if math.abs(front - 2) > 1e-9 or math.abs(s.y1 - 12) > 1e-9 or math.abs(s.x0 + 20) > 1e-9 then
		fail(`the paving spans y {front}..{s.y1} from x {s.x0}; the plaza is 2..12 from -20`)
	end
	for _, place in { "tailor", "square", "arcade", "gates", "climb", "lounge" } do
		if Realms.place(place, "?") == "?" then fail(`no bazaar name for {place}`) end
	end
end

print(`PASS realms: nine stages each in a realm of its own name, paint only; {placed} islands and platforms drawn exactly on their geometry`)
print(`  skies cover every width in four parallax layers; most expensive stage {worstStage} rectangles ({worstStageWhere}), sky {worstSky} ({worstSkyWhere})`)
