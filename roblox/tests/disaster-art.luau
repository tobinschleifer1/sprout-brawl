--!strict
-- The natural disasters, the hazards and the weather in the realms' pixel art (DisasterArt,
-- HazardArt, RealmArt.weather), played in real Matches and drawn through FightScene - the
-- client's own draw - with every sprite recorded where it lands in the world.
--
-- What it holds:
--   * every disaster draws in every phase, on its own realm and in Chaos on others, without error
--     and within a Frame budget;
--   * its WARNINGS are where the shared shape list (DisasterShapes, held to the web) puts them:
--     lightning targets on each marked strike, the tornado's marker on the funnel, the lava's line
--     at the line, meteor targets on each shadow;
--   * its DAMAGE is drawn where the damage is: a bolt on each live strike, the funnel at the
--     tornado, the wave at the crest, a crater on each burning crater;
--   * it is in the realm's material: the same disaster on two realms draws different colours;
--   * every hazard draws through a long match, the sea never laps over the island, and the rods
--     an arc runs between are always drawn;
--   * the weather is world-anchored and stays inside the view.
--
--     lune run tests/disaster-art
local Loader = require("./loader")
local serde = require("@lune/serde")
local Match = Loader.load("Match")
local Loadout = Loader.load("Loadout")
local Input = Loader.load("Input")
local Snapshot = Loader.load("Snapshot")
local SceneSnapshot = Loader.load("SceneSnapshot")
local Stage = Loader.load("Stage")
local Stages = Loader.load("Data/Stages")
local Realms = Loader.load("Realms")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local FightScene = Loader.loadFrom("src/client/", "FightScene")
local Effects = Loader.loadFrom("src/client/", "Effects")
local FxPlayer = Loader.loadFrom("src/client/", "FxPlayer")
local DisasterArt = Loader.loadFrom("src/client/", "DisasterArt")
local DisasterShapes = Loader.loadFrom("src/client/", "DisasterShapes")
local RealmArt = Loader.loadFrom("src/client/", "RealmArt")

local function fail(msg: string): never
	error(msg, 0)
end

-- ------------------------------------------------------------------ the recorder ----
-- World coordinates of every sprite's centre and every rect, under a camera at the origin with
-- one pixel a stud, so a screen point maps straight back to the world.
local VW, VH = 1000, 800
local sprites: { any } = {}
local rects: { any } = {}
local frames = 0
local function world(c: any, x: number, y: number): (number, number)
	local m = c.m
	local sx, sy = m.a * x + m.c * y + m.e, m.b * x + m.d * y + m.f
	return sx - VW / 2, VH / 2 - sy
end
Canvas.rect = function(c: any, x: number, y: number, w: number, h: number, colour: any, alpha: number?)
	frames += 1
	local wx, wy = world(c, x + w / 2, y + h / 2)
	table.insert(rects, { x = wx, y = wy, w = w, h = h, colour = colour, alpha = alpha or 1 })
end
Canvas.ellipse = function(c: any) frames += 1 end
Canvas.circle = function(c: any) frames += 1 end
Canvas.sprite = function(c: any, key: string, list: any, x0: number, y1: number, pw: number, ph: number, cols: number, rows: number)
	frames += 1
	if #list == 0 then fail(`{key}: an empty sprite`) end
	local wx, wy = world(c, x0 + cols * pw / 2, y1 - rows * ph / 2)
	local colours = {}
	for _, r in list do colours[r[5]] = true end
	table.insert(sprites, { key = key, x = wx, y = wy, w = cols * pw, h = rows * ph, colours = colours, seq = #sprites + 1 })
end
local function canvas(): any
	return setmetatable({ used = 0, stack = {}, alpha = 1, alphaStack = {}, m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 },
		gui = { AbsoluteSize = { X = VW, Y = VH } } }, { __index = Canvas })
end
local function find(pattern: string): { any }
	local out = {}
	for _, s in sprites do
		if string.find(s.key, pattern) then table.insert(out, s) end
	end
	return out
end
-- A drawing is anchored on a pixel's corner, so a centred one lands half an art pixel to the side:
-- this is how close "on it" is.
local ON = 0.3
local function near(list: { any }, x: number, tol: number): boolean
	for _, s in list do
		if math.abs(s.x - x) <= tol then return true end
	end
	return false
end

-- ------------------------------------------------------------------ a match, drawn ----
local function run(stageId: string, disaster: string?, frames_: number, check: (number, any, any, any) -> ())
	local data = assert(Stages.LIST[1])
	for _, s in Stages.LIST do if s.id == stageId then data = s end end
	local input = { poll = function() end, get = function() return Input.emptyFrame() end }
	local m = Match.new({ mode = "Training", stage = data, seed = 3, items = false, input = input,
		fighters = { { char = Loadout.build("Classic", "Sword"), source = "a", team = 0 }, { char = Loadout.build("Noir", "Hammer"), source = "b", team = 1 } },
		disasters = if disaster then "chaos" else nil, forceDisaster = disaster, disasterFirstAt = if disaster then 0.1 else nil })
	m.state = "fight"
	local chars = { m.fighters[1].char, m.fighters[2].char }
	local fx, player = Effects.new(), FxPlayer.new()
	local stage = Stage.new(data, 3)
	DisasterArt.resetMoments()
	local peak = 0
	for frame = 1, frames_ do
		m:step()
		table.clear(m.events)
		local states = {}
		for _, f in m.fighters do table.insert(states, Snapshot.decode(Snapshot.encode(f))) end
		local scene = serde.decode("json", serde.encode("json", SceneSnapshot.encode(m)))
		FxPlayer.step(player, 1 / 60)
		table.clear(sprites); table.clear(rects); frames = 0
		local c = canvas()
		FightScene.draw(c, { view = { x = 0, y = 0, ppu = 1 }, shakeX = 0, shakeY = 0, stage = stage,
			platforms = nil, scene = scene, states = states, chars = chars, t = frame / 60, fx = fx, player = player,
			cine = nil })
		if #c.stack ~= 0 then fail(`{stageId}/{disaster}: frame {frame} left the transform stack at {#c.stack}`) end
		peak = math.max(peak, frames)
		check(frame, scene.hazards, m.stage, scene)
	end
	return peak
end

local report = {}
local peakAll = 0
-- The disasters: home realm first, then a Chaos realm for the ones Chaos can draw.
local CASES = {
	{ "lavasurge", "Smeltworks", 760 }, { "lightning", "Rooftops", 330 }, { "lightning", "FoundryFloor", 330 },
	{ "tornado", "Saltflat", 920 }, { "tornado", "Undertow", 920 }, { "tsunami", "Undertow", 820 },
	{ "earthquake", "Faultline", 450 }, { "earthquake", "FoundryFloor", 450 }, { "meteor", "AshfallSummit", 620 },
	{ "meteor", "Rooftops", 620 },
}
local funnelColours: { [string]: { [string]: boolean } } = {}
local craterKeys: { [string]: boolean } = {}
for _, case in CASES do
	local kind, stageId, len = case[1], case[2], case[3]
	local realm = Realms.of(stageId) :: any
	local phases: { [string]: boolean } = {}
	local checks = 0
	local peak = run(stageId, kind, len, function(frame, visual, stage)
		local v = visual and visual.disaster
		if not v then return end
		phases[v.type .. ":" .. v.phase] = true
		-- the shared shape list's cool shapes are the warnings; the art must mark the same places
		local cool = {}
		for _, sh in DisasterShapes.shapes(v, stage) do
			if (if sh[1] == "r" then sh[6] else sh[6]) == DisasterShapes.COOL then table.insert(cool, sh) end
		end
		if kind == "lightning" then
			local targets, bolts = find("fx|reticle|"), find("fx|bolt|")
			for _, s in v.strikes or {} do
				if s.live then
					if not near(bolts, s.x, 1.5) then fail(`{stageId}: no bolt on the live strike at x {s.x}`) end
				elseif not near(targets, s.x, ON) then
					fail(`{stageId}: the strike marked at x {s.x} has no target drawn`)
				end
				checks += 1
			end
		elseif kind == "tornado" then
			local funnels = find("^disaster|funnel|")
			if v.phase ~= "after" and not near(funnels, v.x, 0.2) then fail(`{stageId}: the funnel is not at the tornado (x {v.x})`) end
			if v.phase == "warn" and not near(find("fx|reticle|"), v.x, ON) then fail(`{stageId}: the tornado's warning is not on it`) end
			for _, f in funnels do
				funnelColours[stageId] = funnelColours[stageId] or {}
				for col in f.colours do funnelColours[stageId][col] = true end
			end
			checks += 1
		elseif kind == "tsunami" then
			if v.phase == "strike" then
				local curls = find("^disaster|curl|")
				if #curls ~= 1 then fail(`{stageId}: {#curls} wave crests drawn`) end
				if math.abs(curls[1].x - v.x) > 14 then fail(`{stageId}: the crest is drawn at {curls[1].x}, the wave is at {v.x}`) end
				checks += 1
			end
		elseif kind == "lavasurge" then
			-- the line: cool dashes at exactly the line's height, as the shared list puts them
			local onLine = 0
			for _, r in rects do
				if math.abs(r.y - v.line) < 1e-6 and r.h == 0.3 then onLine += 1 end
			end
			if onLine < 10 then fail(`{stageId}: {onLine} dashes on the lava line at {v.line}`) end
			if v.level > stage.blast.bottom and #find("^disaster|lava|") == 0 then fail(`{stageId}: lava risen but none drawn`) end
			checks += 1
		elseif kind == "meteor" then
			for _, r in v.rocks or {} do
				if r.shadow > 0 and not near(find("fx|reticle|"), r.x, ON) then fail(`{stageId}: no target under the meteor at {r.x}`) end
				if r.burning then
					local craters = find("^disaster|crater|")
					if not near(craters, r.x, ON) then fail(`{stageId}: no crater where the meteor burns at {r.x}`) end
					for _, cr in craters do craterKeys[cr.key] = true end
				end
				checks += 1
			end
		elseif kind == "earthquake" then
			if #(v.plates or {}) > 0 then
				local cracks = find("fx|bolt|")
				for _, p in v.plates do
					if not near(cracks, p.x1, ON) or not near(cracks, p.x2, ON) then fail(`{stageId}: a plate's seams are not drawn`) end
				end
			end
			checks += 1
		end
		if #cool > 0 and frames == 0 then fail(`{stageId}: a warning with nothing drawn`) end
	end)
	for _, p in { "warn", "strike" } do
		if not phases[kind .. ":" .. p] then fail(`{kind} on {stageId}: never reached {p}`) end
	end
	if checks == 0 then fail(`{kind} on {stageId}: nothing was checked`) end
	if peak > 600 then fail(`{kind} on {stageId}: {peak} Frames in its worst frame, over 600`) end
	peakAll = math.max(peakAll, peak)
	table.insert(report, `{kind}@{realm.name} {peak}`)
end
-- the same disaster in two realms is made of two realms' materials
local a, b = funnelColours.Saltflat, funnelColours.Undertow
local shared = 0
for col in a or {} do if b and b[col] then shared += 1 end end
if not a or not b or shared > 1 then fail(`the tornado looks the same in Sunscorch Ruins and Viking Harbor ({shared} colours shared)`) end
local realmsCratered = 0
for key in craterKeys do
	if string.find(key, "AshfallSummit") or string.find(key, "Rooftops") then realmsCratered += 1 end
end
if realmsCratered < 2 then fail("meteor craters are not in their realm's stone") end

-- ------------------------------------------------------------------ the hazards ----
local hazardsSeen: { [string]: boolean } = {}
for _, data in Stages.LIST do
	if not data.hazards or #data.hazards == 0 then continue end
	run(data.id, nil, 1500, function(_frame, visual, stage)
		for name, v in visual or {} do
			if name ~= "disaster" then hazardsSeen[name] = true end
		end
		local tide = visual and visual.tide
		if tide then
			-- the sea stays outside the island: no water tile reaches over it. One drawn before the
			-- island, behind it, is the sea showing under its belly (without it a grey column of the
			-- sky's far sea showed there, round 5) - and there must be one
			local island = find("|island|")
			local firstIsland = math.huge
			for _, s in island do firstIsland = math.min(firstIsland, s.seq) end
			if firstIsland == math.huge then fail("the tide's stage drew no island") end
			local behind = 0
			for _, s in find("^disaster|water|") do
				local lo, hi = s.x - s.w / 2, s.x + s.w / 2
				if hi > -tide.edge + 1e-6 and lo < tide.edge - 1e-6 then
					if s.seq > firstIsland then
						fail(`the tide lapped over the island: a tile spans {lo}..{hi}, the island {-tide.edge}..{tide.edge}`)
					end
					behind += 1
				end
			end
			if behind == 0 then fail("no sea behind the island: its belly hangs over the sky's far sea") end
		end
		local arc = visual and visual.antennaarc
		if arc then
			-- the rods are there whether or not the arc is
			local rods = 0
			for _, r in rects do
				if math.abs(r.w - 0.3) < 1e-9 and math.abs(r.h - 2.4) < 1e-9 then
					if math.abs(r.x - arc.x1) < 1e-6 or math.abs(r.x - arc.x2) < 1e-6 then rods += 1 end
				end
			end
			if rods ~= 2 then fail(`{rods} lightning rods drawn for the arc`) end
			-- and the arc itself only while it warns or fires: an idle pair of rods is quiet
			if arc.phase == "idle" then
				for _, b in find("fx|bolt|") do
					if math.abs(b.y - arc.y) < 2 and b.x > arc.x1 - 1 and b.x < arc.x2 + 1 then fail("the arc crackles while idle") end
				end
			end
		end
		local vents = visual and visual.vents
		if vents and vents.phase ~= "idle" and vents.phase ~= "warn" then
			for _, x in vents.armed do
				if not near(find("fx|flame|"), x, ON) then fail(`a vent erupting at {x} has no fire drawn`) end
			end
		end
	end)
end
local expect = { "vents", "slagfall", "sprinkler", "antennaarc", "dustdevil", "sandfall", "tide", "roguewave", "crosswind", "emberdrift" }
for _, name in expect do
	if not hazardsSeen[name] then fail(`the hazard {name} never appeared`) end
end

-- ------------------------------------------------------------------ the weather ----
for _, realm in Realms.LIST do
	local function at(cx: number): { any }
		table.clear(rects)
		local c = canvas()
		c:world(0, 0, 1, 0, 0)
		RealmArt.weather(c, realm, cx, 4, 80, 45, 2.5)
		return table.clone(rects)
	end
	local here, panned = at(0), at(3)
	local air = RealmArt.AIR[realm.id] or fail(`{realm.name} has no weather`)
	if #here ~= air.n then fail(`{realm.name}: {#here} weather particles drawn, want {air.n}`) end
	local still = 0
	for i, p in here do
		if math.abs(p.x) > 43 + air.sway + 1 or math.abs(p.y - 4) > 25.5 + 1 then fail(`{realm.name}: a particle outside the view`) end
		if math.abs(panned[i].x - p.x) < 1e-6 then still += 1 end
	end
	-- world-anchored: a small pan leaves most of them where they were in the world
	if still < air.n * 0.8 then fail(`{realm.name}: the weather moved with the camera ({still}/{air.n} stayed)`) end
end

-- the shake an earthquake asks for: a rumble while it warns, a jolt on the drop, nothing after
if not (DisasterArt.shake({ type = "earthquake", phase = "warn", k = 0.5, frame = 10, warn = 120 }) > 0) then fail("no rumble") end
if not (DisasterArt.shake({ type = "earthquake", phase = "strike", k = 0, frame = 121, warn = 120 }) > 0.5) then fail("no jolt") end
if DisasterArt.shake({ type = "earthquake", phase = "after", k = 0.5, frame = 400, warn = 120 }) ~= 0 then fail("shaking after") end

print(`PASS disaster art: six disasters on their own realms and in Chaos, warnings and damage drawn where the simulation puts them, each realm's materials`)
print(`  ten hazards through long matches, the sea kept off the island, the arc's rods always there; nine realms' weather world-anchored`)
print(`  worst frames: {table.concat(report, ", ")}`)
