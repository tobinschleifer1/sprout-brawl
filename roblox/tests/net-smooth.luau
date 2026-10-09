--!strict
-- The connection, made to feel smooth: the scene stream as deltas (SceneCodec), how far back other
-- fighters are drawn (Interp), corrections to our own prediction eased rather than jumped
-- (Predictor.visual), and the performance monitor's arithmetic (PerfMonitor).
--
-- What it holds:
--   * every scene of real matches - hazards, a disaster, items, projectiles - decodes from its delta
--     to exactly the scene sent, and the stream is a good deal smaller than sending scenes whole;
--     a delta without a base decodes to nothing, a keyframe to everything;
--   * the interpolation delay settles near one and a half snapshot gaps on a steady connection,
--     grows on a jittery one, ignores a pause, and never jumps;
--   * a small correction is drawn from where the fighter was and eased out in about 70ms; a large
--     one is drawn at once; with no correction the drawn fighter is the predicted one;
--   * the monitor's averages, percentiles, rates and jitter are the numbers fed to it.
--
--     lune run tests/net-smooth
local Loader = require("./loader")
local Match = Loader.load("Match")
local Loadout = Loader.load("Loadout")
local Input = Loader.load("Input")
local Fighter = Loader.load("Fighter")
local Stage = Loader.load("Stage")
local Stages = Loader.load("Data/Stages")
local Snapshot = Loader.load("Snapshot")
local SceneSnapshot = Loader.load("SceneSnapshot")
local SceneCodec = Loader.load("SceneCodec")
local Predictor = Loader.loadFrom("src/client/", "Predictor")
local Interp = Loader.loadFrom("src/client/", "Interp")
local PerfMonitor = Loader.loadFrom("src/client/", "PerfMonitor")

local function fail(msg: string): never
	error(msg, 0)
end
-- Deep equality of its own, not the codec's: a test that judges the codec by the codec's own
-- comparison passes whatever that comparison gets wrong.
local function same(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in a do if not same(v, b[k]) then return false end end
	for k in b do if a[k] == nil then return false end end
	return true
end

-- ------------------------------------------------------------------ the scene stream ----
local whole, delta = 0, 0
for _, id in { "Smeltworks", "Rooftops", "Undertow", "AshfallSummit" } do
	local data = Stages.LIST[1]
	for _, s in Stages.LIST do if s.id == id then data = s end end
	local fighters = {}
	for i = 1, 4 do
		table.insert(fighters, { char = Loadout.build("Classic", ({ "Sword", "Hammer", "Blasters", "Grimoire" })[i]), source = "b" .. i, team = i })
	end
	local m = Match.new({ mode = "Training", stage = data, seed = 5, items = true, disasters = "chaos", disasterFirstAt = 1,
		input = { poll = function() end, get = function() return Input.emptyFrame() end }, fighters = fighters })
	for _, f in m.fighters do f.isBot = true; f.botLevel = "hard" end
	m.state = "fight"
	local base, client, sent = nil, nil, 0
	for frame = 1, 1400 do
		m:step()
		table.clear(m.events)
		if frame % 2 == 0 then
			local scene = SceneSnapshot.encode(m)
			scene.id = 7
			local key = base == nil or sent % SceneCodec.KEYFRAME_EVERY == 0
			local packet = SceneCodec.encode(scene, if key then nil else base)
			whole += SceneCodec.estimate(scene)
			delta += SceneCodec.estimate(packet)
			client = SceneCodec.decode(packet, client)
			if not client or not same(client, scene) then fail(`{id}: scene at frame {frame} decoded wrongly`) end
			base, sent = scene, sent + 1
		end
	end
end
if delta > whole * 0.8 then fail(`the scene stream is {math.floor(delta / whole * 100)}% of sending scenes whole`) end
if SceneCodec.decode({ f = 1, id = 1, s = { items = {} } }, nil) ~= nil then fail("a delta decoded without a base") end
local key = SceneCodec.decode({ k = true, s = { frame = 3, id = 1, hazards = {} } }, nil)
if not key or key.frame ~= 3 then fail("a keyframe did not decode on its own") end
-- a hazard that goes away, and a field that goes away, go away
local a = { frame = 1, id = 1, hazards = { vents = { k = 1, w = 2 }, tide = { level = 0 } }, items = {} }
local b = { frame = 2, id = 1, hazards = { vents = { k = 1 } }, items = {} }
local back = SceneCodec.decode(SceneCodec.encode(b, a), a)
if back.hazards.tide ~= nil or back.hazards.vents.w ~= nil or back.hazards.vents.k ~= 1 then fail("removals did not travel") end
if a.hazards.tide == nil or a.hazards.vents.w ~= 2 then fail("decoding changed the base") end

-- ------------------------------------------------------------------ interpolation ----
do
	local I = Interp.new(1 / 60)
	local now = 0
	for _ = 1, 600 do now += 1 / 60; I:arrive(now) end
	local steady = I.delay
	if math.abs(steady - math.max(Interp.MIN, 1.5 / 60)) > 0.004 then fail(`steady 60Hz settled at {steady * 1000}ms`) end
	-- ragged: gaps between 0 and 3 frames
	local J = Interp.new(1 / 60)
	now = 0
	local biggest = 0
	for i = 1, 600 do
		now += (i % 4) / 60
		local before = J.delay
		J:arrive(now)
		biggest = math.max(biggest, math.abs(J.delay - before))
	end
	if J.delay <= steady + 0.008 then fail(`a jittery connection got {J.delay * 1000}ms, no more than a steady one`) end
	if J.delay > Interp.MAX + 1e-9 then fail("the delay passed its ceiling") end
	if biggest > 0.01 then fail(`the delay jumped {biggest * 1000}ms in one snapshot`) end
	-- a pause (the window lost focus) does not read as jitter
	local K = Interp.new(1 / 60)
	now = 0
	for _ = 1, 300 do now += 1 / 60; K:arrive(now) end
	local was = K.delay
	now += 4
	K:arrive(now)
	for _ = 1, 20 do now += 1 / 60; K:arrive(now) end
	if math.abs(K.delay - was) > 0.002 then fail(`a four-second pause moved the delay {(K.delay - was) * 1000}ms`) end
end

-- ------------------------------------------------------------------ eased corrections ----
do
	local data = Stages.LIST[1]
	local stage = Stage.new(data, 1)
	local char = Loadout.build("Classic", "Sword")
	local truth = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
	local ctx = { stage = stage, combat = { fighters = { truth }, useItem = function() end, dropItem = function() end,
		itemNear = function() return nil end, allyToCatch = function() return nil end, pickupItem = function() end, hasFruit = function() return false end,
		fruiting = function() end, nearestNode = function() return nil end, removeSummon = function() end,
		onMoveActive = function() end, onMoveActiveFrame = function() end, spawnBurst = function() end,
		checkGrab = function() end, resolveThrow = function() end }, fighters = { truth } }
	local pred = Predictor.new(char, 0, Stage.new(data, 1))
	local walk = Input.emptyFrame()
	walk.x = 0.6
	for n = 1, 30 do
		truth:applyInput(walk); truth:step(ctx); pred:push(walk)
		if n == 10 then pred:reconcile(Snapshot.decode(Snapshot.encode(truth)), n) end
	end
	-- no correction: drawn where predicted
	local v = pred:visual(1 / 60)
	if math.abs(v.x - pred.fighter.x) > 1e-9 then fail("with nothing corrected, the fighter is not drawn where predicted") end
	-- the server says we are a stud further on than we predicted
	local wire = Snapshot.decode(Snapshot.encode(truth))
	wire.x += 1
	local drawnBefore = pred.fighter.x
	pred:reconcile(wire, 30)
	local now = pred:visual(0)
	if math.abs(now.x - drawnBefore) > 1e-6 then fail(`a correction jumped the drawing to {now.x} from {drawnBefore}`) end
	for _ = 1, 4 do pred:visual(1 / 60) end
	local left = pred:visual(1 / 60).x - pred.fighter.x
	if math.abs(left) > 0.2 then fail(`70ms after a 1-stud correction, {left} studs of it are still showing`) end
	for _ = 1, 30 do pred:visual(1 / 60) end
	if pred:visual(1 / 60).x ~= pred.fighter.x then fail("a correction never finished easing") end
	-- a big one (a respawn, a warp) is drawn at once
	wire = Snapshot.decode(Snapshot.encode(truth))
	wire.x += Predictor.SNAP_STUDS + 4
	pred:reconcile(wire, 30)
	if math.abs(pred:visual(0).x - pred.fighter.x) > 1e-9 then fail("a large correction was eased instead of drawn at once") end
	if pred.lastCorrection < Predictor.SNAP_STUDS then fail(`a {Predictor.SNAP_STUDS + 4}-stud correction measured {pred.lastCorrection}`) end
end

-- ------------------------------------------------------------------ the monitor ----
do
	local M = PerfMonitor.new()
	for i = 1, 100 do M:frame(1 / 60, if i == 100 then 0.009 else 0.001, 300, 20) end
	for i = 1, 31 do M:arrival(i / 30, 140) end
	M:correction(1.0, 0.5)
	M:correction(1.1, 1.5)
	local s = M:stats(1.05)
	if math.abs(s.fps - 60) > 0.5 then fail(`fps {s.fps}`) end
	if math.abs(s.drawMs - 1.08) > 0.01 then fail(`draw mean {s.drawMs}`) end
	if math.abs(s.drawP95 - 1) > 1e-6 then fail(`draw p95 {s.drawP95}`) end
	if math.abs(s.snapHz - 30) > 0.5 or s.jitterMs > 0.5 then fail(`snapshots {s.snapHz}Hz jitter {s.jitterMs}`) end
	if math.abs(s.correctionStuds - 1) > 1e-9 then fail(`correction size {s.correctionStuds}`) end
	if s.frames ~= 300 or s.sprites ~= 20 then fail("counts not carried") end
	local attrs = {}
	local target = { SetAttribute = function(_, k: string, v: number) attrs[k] = v end }
	M:publish(target, 2)
	if attrs.PerfFps == nil or attrs.PerfDrawP95 == nil or attrs.PerfCorrections == nil then fail("attributes not published") end
	attrs = {}
	M:publish(target, 2.1)
	if next(attrs) then fail("published again within half a second") end
end

print(`PASS net smooth: scene deltas exact across four realms' matches at {math.floor(delta / whole * 100)}% of whole scenes; interpolation steady, wider when ragged, ignores pauses, never jumps`)
print("  small corrections eased out in ~70ms, large ones drawn at once; the monitor's numbers are the ones fed to it")
