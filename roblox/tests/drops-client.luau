--!strict
-- Weapon drops on the client: what crosses the wire, and prediction through arming and throwing.
--
--     lune run tests/drops-client
--
--   * the fighter snapshot carries `armed`, exactly, through the binary codec (keyframe and delta);
--   * the scene carries the drops (where, landed, life, what a thrown one looks like) and a thrown
--     weapon's id and pierce, through the scene codec, with nothing in it a remote cannot carry;
--   * prediction: the local fighter carries its kit. A pickup is the server's to decide (the
--     predictor's combat has no drops) and the weapon leaving on a throw is too, so those frames
--     are genuine mispredictions; once the correction carrying them lands, the predicted fighter
--     holds the server's loadout - the same char, so the same size, weight and moves - and agrees
--     with the server on every wire field, at every lag tested.
local Loader = require("./loader")
local Fighter = Loader.load("Fighter")
local Stage = Loader.load("Stage")
local Stages = Loader.load("Data/Stages")
local Loadout = Loader.load("Loadout")
local Input = Loader.load("Input")
local Snapshot = Loader.load("Snapshot")
local SnapshotCodec = Loader.load("SnapshotCodec")
local SceneSnapshot = Loader.load("SceneSnapshot")
local SceneCodec = Loader.load("SceneCodec")
local Match = Loader.load("Match")
local Combat = Loader.load("Combat")
local Predictor = Loader.loadFrom("src/client/", "Predictor")

local function fail(msg: string): never
	error(msg, 0)
end
local function stageFor(): any
	for _, data in Stages.LIST do
		if data.id == "FoundryFloor" then return Stage.new(data, 999) end
	end
	return fail("no FoundryFloor")
end

-- ---- the fighter snapshot carries `armed` ----
do
	local A = Loadout.buildArmed("Classic", { "Sword", "Hammer" })
	local f = Fighter.new({ index = 0, char = A.char, kit = A.kit, fists = A.fists, x = 0, y = 0, stocks = 3 })
	local function packet(armedTo: number, base: any?): (any, any)
		if armedTo >= 0 then f.armed = -1; f.nextArm = armedTo; f:arm() else f:disarm() end
		local snap = { id = 7, frame = if base then base.frame + 1 else 1, state = "fight", time = 0, countdown = 0, fighters = { Snapshot.encode(f) }, platforms = {}, acks = {} }
		return SnapshotCodec.encode(snap, base), snap
	end
	local k, s1 = packet(1, nil)
	local got = SnapshotCodec.decode(k, nil)
	if not got or Snapshot.decode(got.fighters[1]).armed ~= 1 then fail("a keyframe lost `armed`") end
	local d = packet(-1, s1)
	local got2 = SnapshotCodec.decode(d, got)
	if not got2 or Snapshot.decode(got2.fighters[1]).armed ~= -1 then fail("a delta lost the change of `armed`") end
	print("PASS the fighter snapshot carries which weapon is in hand, through keyframes and deltas")
end

-- ---- the scene carries drops and thrown weapons ----
local drawn: any = nil
do
	local idle = { kb2Active = false, poll = function() end, get = function() return Input.emptyFrame() end }
	local fighters = {}
	for i, ws in { { "Pike", "Pike" }, { "Sword", "Sword" } } do
		local A = Loadout.buildArmed(if i == 1 then "Classic" else "Noir", ws)
		table.insert(fighters, { char = A.char, kit = A.kit, fists = A.fists, skin = 0, team = i - 1, source = `p{i - 1}`, isBot = false, name = `P{i}` })
	end
	local data
	for _, s in Stages.LIST do if s.id == "FoundryFloor" then data = s end end
	local m = Match.new({ mode = "StockFFA", stage = data, input = idle, seed = 4, stocks = 3, weaponDrops = true, fighters = fighters })
	while m.state == "countdown" do m:step() end
	local a = m.fighters[1]
	Combat.spawnDrop(m.combat, 5, 1, "Hammer")
	a.armed = -1; a.nextArm = 0; a:arm()
	Combat.throwWeapon(m.combat, a)
	m:step()
	local scene = SceneSnapshot.encode(m)
	local thrown, lying = nil, nil
	for _, p in scene.projectiles do if p.weapon then thrown = p end end
	for _, d in scene.drops do if d.look == "Hammer" then lying = d end end
	if not thrown or thrown.weapon ~= "Pike" or thrown.pierce ~= true then fail("the scene does not say a thrown pike is a pike that pierces") end
	if not lying or lying.onGround == nil or type(lying.life) ~= "number" then fail("the scene does not carry the drop lying there") end
	-- nothing a remote cannot carry: no functions, no fighter references
	local function plain(v: any, depth: number)
		if type(v) == "function" then fail("a function in the scene") end
		if type(v) == "table" then
			if v.char or v.kit then fail("a fighter in the scene") end
			if depth < 6 then for _, x in v do plain(x, depth + 1) end end
		end
	end
	plain(scene.drops, 0)
	plain(scene.projectiles, 0)
	local key = SceneCodec.encode(scene, nil)
	local back = SceneCodec.decode(key, nil)
	if not back or not SceneCodec.equal(back.drops, scene.drops) then fail("the scene codec lost the drops") end
	m:step()
	local later = SceneSnapshot.encode(m)
	local delta = SceneCodec.decode(SceneCodec.encode(later, scene), back)
	if not delta or not SceneCodec.equal(delta.drops, later.drops) or not SceneCodec.equal(delta.projectiles, later.projectiles) then
		fail("a scene delta did not carry the drops and thrown weapon on")
	end
	drawn = back
	print("PASS the scene carries drops and thrown weapons (which, and whether they pierce), through keyframes and deltas")
end

-- ---- the renderer draws what the scene carried ----
-- Through a recorder, as tests/scene-view.luau does: every shape DropShapes gives a drop is drawn,
-- a thrown weapon lying there is drawn as its weapon on top, and one in flight is drawn as its
-- weapon - not as the plain box a projectile without art falls back to.
do
	local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
	local World = Loader.loadFrom("src/client/", "World2D")
	local DropShapes = Loader.loadFrom("src/client/", "DropShapes")
	local used = 0
	local function primitive(_c: any, ...: any)
		for i, v in { ... } do
			if i <= 4 and type(v) == "number" then assert(v == v and math.abs(v) < math.huge, "nonfinite drawing geometry") end
		end
		used += 1
	end
	Canvas.rect = primitive; Canvas.circle = primitive; Canvas.ellipse = primitive
	Canvas.sprite = function(c: any, _key: string, rects: any, ...: any) assert(#rects > 0, "a sprite with no rectangles"); primitive(c, ...) end
	local function canvas(): any
		return { used = 0, m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 }, stack = {}, alpha = 1, alphaStack = {}, gui = { AbsoluteSize = { X = 1280, Y = 720 } } }
	end
	local function count(fn: (any) -> ()): number
		used = 0
		local c = canvas()
		fn(c)
		if #c.stack ~= 0 then fail("a drawing left the canvas transform stack unbalanced") end
		return used
	end
	local cache = { x = 0, y = 0, onGround = true, life = 600 }
	local shapes = DropShapes.shapes(cache, 0)
	if count(function(c) World.drop(c, cache, 0) end) ~= #shapes then fail("a fresh drop did not draw every one of its shapes") end
	local lying = { x = 0, y = 0, onGround = true, life = 600, look = "Hammer" }
	local base = #(DropShapes.shapes(lying, 0))
	if count(function(c) World.drop(c, lying, 0) end) <= base then fail("a thrown hammer lying there was not drawn as a hammer") end
	local flying = 0
	for _, p in drawn.projectiles do
		if p.weapon then flying = count(function(c) World.thrownWeapon(c, p, 0.3) end) end
	end
	if flying < 2 then fail("a thrown weapon in flight was not drawn as its weapon") end
	local all = count(function(c) World.entities(c, drawn, {}, {}, 0.3) end)
	if all < flying + #shapes then fail("drawing the scene left out its drops or its thrown weapon") end
	print(`PASS the renderer draws the drops and the thrown weapon the scene carried ({all} shapes)`)
end

-- ---- prediction through arming and throwing ----
-- The server's combat for one fighter: a drop lies where it is put, taking it arms the fighter, and a
-- throw lets the weapon go on its first active frame - the parts of Combat that change the fighter.
local function serverCombat(fighters: any, drop: any): any
	return {
		fighters = fighters,
		useItem = function() end, dropItem = function() end,
		itemNear = function() return nil end, allyToCatch = function() return nil end, pickupItem = function() end,
		hasFruit = function() return false end, fruiting = function() end,
		nearestNode = function() return nil end, removeSummon = function() end,
		onMoveActiveFrame = function() end, spawnBurst = function() end,
		checkGrab = function() end, resolveThrow = function() end,
		dropNear = function(_, f: any): any
			if drop.here and math.abs(drop.x - f.x) < 3 and math.abs(f.y) < 3.5 then return drop end
			return nil
		end,
		takeDrop = function(_, f: any) drop.here = false; f:arm() end,
		onMoveActive = function(_, f: any, m: any) if m.kind == "weaponthrow" then f:disarm() end end,
	}
end
-- walk right, and every 60 frames press pickup (the server arms or throws); jumps and lights between
local function inputAt(n: number): any
	local f = Input.emptyFrame()
	local phase = n % 60
	if phase < 25 then f.x = if (n // 120) % 2 == 0 then 0.8 else -0.8
	elseif phase == 30 then f.pickup = true; f.anyPress = true
	elseif phase == 45 then f.jump = true; f.jumpHeld = true
	elseif phase == 52 then f.light = true; f.anyPress = true end
	return f
end
local checked, corrections = 0, 0
for _, LAG in { 0, 2, 5 } do
	local A = Loadout.buildArmed("Classic", { "Hammer", "Daggers" })
	local stage = stageFor()
	local truth = Fighter.new({ index = 0, char = A.char, kit = A.kit, fists = A.fists, x = 0, y = 0, stocks = 3 })
	local drop = { x = 0, y = 0, here = true }
	local tctx = { stage = stage, combat = serverCombat({ truth }, drop), fighters = { truth } }
	local pred = Predictor.new(A.char, 0, stage, A)
	local history, changed = {}, {}
	for n = 1, 600 do
		-- a fresh drop under the fighter whenever they are back on fists, so it keeps arming
		if truth.armed < 0 and not drop.here and n % 60 == 20 then drop.here = true; drop.x = truth.x end
		local before = truth.armed
		local frame = inputAt(n)
		truth:applyInput(frame)
		truth:step(tctx)
		table.clear(truth.events)
		changed[n] = truth.armed ~= before
		history[n] = Snapshot.decode(Snapshot.encode(truth))
		pred:push(frame)
		local at = n - LAG
		if at >= 1 then
			pred:reconcile(history[at], at)
			-- the window (at, n] holds a pickup or a weapon leaving the client could not foresee
			local blind = false
			for k = at + 1, n do if changed[k] then blind = true end end
			if not blind then
				local got, want = pred:state(), history[n]
				for _, pair in Snapshot.FIELDS do
					local key = pair[1]
					local a, b = got[key], want[key]
					local ok = if type(a) == "number" and type(b) == "number" then math.abs(a - b) < 1e-9 else a == b
					if not ok then fail(`lag {LAG} frame {n}: {key} predicted {tostring(a)}, server {tostring(b)}`) end
					checked += 1
				end
				if pred.fighter.char ~= truth.char then fail(`lag {LAG} frame {n}: predicting with {pred.fighter.char.weapon.id} in hand, the server's has {truth.char.weapon.id}`) end
				if pred.fighter.weight ~= truth.weight or pred.fighter.h ~= truth.h then fail(`lag {LAG} frame {n}: the predicted fighter is not the weapon's size and weight`) end
				for k = at, n do if changed[k] then corrections += 1 end end
			end
		end
	end
end
if corrections < 6 then fail(`only {corrections} corrections carried an arm or a throw - the test is not exercising them`) end
print(`PASS prediction through arming and throwing: {checked} wire values agree with the server outside the frames it could not foresee; {corrections} corrections carried a pickup or a throw and left the right loadout in hand`)
