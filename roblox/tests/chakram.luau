--!strict
-- The Chakram (Roblox only: src/shared/RobloxWeapons.luau, the rings in Combat.stepRing). Nothing
-- replays it against the web, so its promises are asserted directly, in real matches:
-- 1. Orbit Throw goes out about 22 studs and comes home, and is caught: the ring is back in hand.
-- 2. It hits on the way out AND on the way back - one hit a pass, not one a frame.
-- 3. Rings are spent and refused: two throws empty both hands, a third is refused (dryfire); Halo
--    needs both rings and is refused while either is out.
-- 4. Ground Saw stays on the floor and turns at a ledge instead of falling off it.
-- 5. Halo circles its owner, both rings, then they come home.
-- 6. Eclipse Ring circles, then flies out and back.
-- 7. A ring can never be lost for good: one whose owner is KO'd comes back, one flown off the stage
--    comes back, and a new stock starts with both.
-- 8. The weapon is in the game: in the merged list, built by Loadout, drawn with its own art.
local Loader = require("./loader")
local Match, Loadout = Loader.load("Match"), Loader.load("Loadout")
local Weapons = Loader.load("Weapons")
local Remote = Loader.loadFrom("src/server/", "RemoteInput")

local function fail(msg: string) error(msg, 0) end
local stageData = Loader.load("Data/Stages").LIST[1]

local function setup(): (any, any, any)
	local input = Remote.new(); input:register("p1"); input:register("p2")
	local match = Match.new({ mode = "Training", stage = stageData, seed = 1, items = false, input = input,
		fighters = { { char = Loadout.build("Classic", "Chakram"), source = "p1", team = 0 },
			{ char = Loadout.build("Noir", "Sword"), source = "p2", team = 1 } } })
	match.state = "fight"
	local f, foe = match.fighters[1], match.fighters[2]
	f:reset(0, 0, { state = "idle", invincible = 0 }); f.onGround = true; f.platform = match.stage.main
	f.facing = 1
	foe:reset(60, 0, { state = "idle", invincible = 0 }); foe.onGround = true; foe.platform = match.stage.main
	return match, f, foe
end
local function rings(match: any, f: any): { any }
	local out = {}
	for _, p in match.combat.projectiles do if p.ring and p.owner == f then table.insert(out, p) end end
	return out
end
local function run(match: any, frames: number, each: ((number) -> ())?)
	for i = 1, frames do
		match:step()
		if each then each(i) end
	end
end

-- 8. In the game.
if not Weapons.BY_ID.Chakram or not Weapons.ROBLOX_ONLY.Chakram then fail("the Chakram is not in the merged weapon list") end
local generated = #Loader.load("Data/Weapons").LIST
if Weapons.LIST[generated + 1].id ~= "Chakram" then fail("the Chakram is not right after the generated roster") end
for i = 1, generated do
	if Weapons.LIST[i] ~= Loader.load("Data/Weapons").LIST[i] then fail("merging changed the generated list") end
end
local char = Loadout.build("Classic", "Chakram")
if char.weapon.id ~= "Chakram" or char.mechanic.id ~= "Return" then fail("Loadout did not build the Chakram") end
if not Weapons.ART.sprites.Chakram or #Weapons.ART.sprites.Chakram < 20 then fail("the Chakram has no art") end
if not Weapons.ART.sprites.Sword then fail("merging the art lost the generated weapons") end

-- 1 and 2. Orbit Throw: out, home, caught; a hit each way.
do
	local match, f, foe = setup()
	foe.x = 12                                    -- on the ring's line, inside its range
	f:startMove("SigSide")
	if f.mech.rings ~= 2 then fail("a ring was spent before it left the hand") end
	run(match, 16)
	if f.mech.rings ~= 1 then fail(`Orbit Throw left {f.mech.rings} rings in hand, want 1`) end
	local far, hits, caught, before = 0, 0, false, foe.percent
	local last = foe.percent
	run(match, 240, function()
		for _, p in rings(match, f) do far = math.max(far, math.abs(p.x - f.x)) end
		if foe.percent > last then hits += 1 end
		last = foe.percent
		foe.x, foe.y, foe.vx, foe.vy = 12, 0, 0, 0             -- held on the line both ways
		foe.hitstun = 0; foe.state = "idle"; foe.invincible = 0
		if f.mech.rings == 2 and #rings(match, f) == 0 then caught = true end
	end)
	if far < 20 or far > 25 then fail(`Orbit Throw flew {far} studs out, want about 22`) end
	if not caught then fail("the thrown ring never came home") end
	if hits ~= 2 then fail(`Orbit Throw hit {hits} times on a target in its path, want 2 (out and back)`) end
	if foe.percent <= before then fail("Orbit Throw did no damage") end
end

-- 3. Rings spent and refused.
do
	local match, f = setup()
	f:startMove("SigSide"); run(match, 40)
	if f.mech.rings ~= 1 then fail("one ring out should leave one in hand") end
	f.move = nil; f.state = "idle"
	f:startMove("SigNeutral")
	if f.moveId == "SigNeutral" then fail("Halo started with a ring out") end
	f:startMove("SigDown"); run(match, 14)
	if f.mech.rings ~= 0 or f.moveId ~= "SigDown" then fail("a second ring could not be thrown") end
	f.move = nil; f.state = "idle"
	table.clear(f.events)
	f:startMove("SigSide")
	local dry = false
	for _, e in f.events do if e.type == "dryfire" then dry = true end end
	if not dry or f.mech.rings ~= 0 then fail("a third throw with empty hands was not refused") end
end

-- An ultimate refused for empty hands must not spend its meter or freeze either fighter.
-- Exercise the real input path: startMove alone cannot catch effects applied before it runs.
do
	local Input, Snapshot = Loader.load("Input"), Loader.load("Snapshot")
	local Predictor = Loader.loadFrom("src/client/", "Predictor")
	local Stage = Loader.load("Stage")
	for _, held in { 0, 1, 2 } do
		local match, f, foe = setup()
		f.ultCharge, f.mech.rings = 20, held
		local pred = Predictor.new(f.char, 0, Stage.new(stageData, 1))
		pred:reconcile(Snapshot.decode(Snapshot.encode(f)), 0)
		local input = Input.emptyFrame()
		input.ult = true
		f:applyInput(input)
		f:step({ stage = match.stage, fighters = match.fighters, combat = match.combat })
		pred:push(input)
		if held == 0 then
			assert(f.ultCharge == 20 and pred:state().ultCharge == 20, "empty-handed ultimate spent its meter")
			assert(f.state == "idle" and pred:state().state == "idle", "empty-handed ultimate started an action")
			assert(f.ultActive == 0 and f.hitlag == 0 and foe.hitlag == 0 and f.invincible == 0,
				"empty-handed ultimate granted activation effects")
			local denied = 0
			for _, event in f.events do
				assert(event.type ~= "ultimate", "refused ultimate announced a cinematic")
				if event.type == "dryfire" and event.rings == 1 then denied += 1 end
			end
			assert(denied == 1 and f.buffer.ult == 0, "refused ultimate did not consume and explain the press once")
		else
			assert(f.moveId == "Ultimate" and f.ultCharge == 0 and pred:state().moveId == "Ultimate",
				"ultimate with a ring in hand did not activate")
			assert(f.mech.rings == held, "ultimate spent its ring before ignition")
		end
	end
end

-- 4. Ground Saw rolls on the floor and turns at the ledge.
do
	local match, f = setup()
	local main = match.stage.main
	f.x = main.x2 - 6; f.facing = 1                -- six studs from the ledge, throwing toward it
	f:startMove("SigDown")
	local turned, offFloor, sawRolling = false, 0, false
	run(match, 75, function()
		for _, p in rings(match, f) do
			if p.ring.phase == "roll" then
				sawRolling = true
				if p.vx < 0 then turned = true end
				if p.x > main.x2 + 0.01 then fail("Ground Saw rolled off the ledge") end
				if p.x >= main.x1 and p.x <= main.x2 then offFloor = math.max(offFloor, math.abs((p.y - p.h / 2) - main.top)) end
			end
		end
	end)
	if not sawRolling then fail("Ground Saw never rolled") end
	if not turned then fail("Ground Saw did not turn at the ledge") end
	if offFloor > 0.05 then fail(`Ground Saw left the floor by {offFloor} studs while rolling`) end
	run(match, 200)
	if f.mech.rings ~= 2 then fail("Ground Saw's ring never came home") end
end

-- 5. Halo: both rings circle the owner, then come home.
do
	local match, f = setup()
	f:startMove("SigNeutral"); run(match, 10)
	if f.mech.rings ~= 0 then fail("Halo should take both rings") end
	local worst, circling = 0, 0
	run(match, 50, function()
		local rs = rings(match, f)
		for _, p in rs do
			if p.ring.phase == "orbit" and p.ring.t > 1 then
				worst = math.max(worst, math.abs(math.sqrt((p.x - f.x) ^ 2 + (p.y - f.cy) ^ 2) - p.ring.radius))
				circling = math.max(circling, #rs)
			end
		end
	end)
	if circling ~= 2 then fail(`Halo circled {circling} rings, want 2`) end
	if worst > 0.6 then fail(`a Halo ring strayed {worst} studs off its circle`) end
	run(match, 120)
	if f.mech.rings ~= 2 or #rings(match, f) > 0 then fail("Halo's rings never came home") end
end

-- 6. Eclipse Ring: circles, then out and back.
do
	local match, f = setup()
	f.ultCharge = 100
	f:startMove("Ultimate")
	local phases: { [string]: boolean } = {}
	run(match, 300, function()
		for _, p in rings(match, f) do phases[p.ring.phase] = true end
	end)
	if not (phases.orbit and phases.out and phases.back) then fail("Eclipse Ring did not circle, fly out and come back") end
	if f.mech.rings ~= 2 then fail("Eclipse Ring's ring never came home") end
end

-- 7. A ring is never lost for good.
do
	local match, f = setup()
	-- KO'd in the wind-up, before the ring leaves the hand: nothing was thrown, nothing is lost
	f:startMove("SigSide"); run(match, 5)
	f.alive = false
	run(match, 3)
	if f.mech.rings ~= 2 then fail("a throw interrupted in its wind-up lost a ring") end
	f.alive = true; f.move = nil; f.state = "idle"
	f:startMove("SigSide"); run(match, 20)
	if #rings(match, f) ~= 1 then fail("the second throw never left the hand") end
	f.alive = false                                -- KO'd with the ring in flight
	run(match, 3)
	if #rings(match, f) ~= 0 or f.mech.rings ~= 2 then fail("a KO'd owner's ring was lost") end
	f.alive = true
	f:startMove("SigSide"); run(match, 2)
	for _, p in rings(match, f) do p.y = -500 end   -- knocked off the bottom of the stage
	run(match, 2)
	if f.mech.rings ~= 2 then fail("a ring lost off the stage never came back") end
	f.mech.rings = 0
	f:respawn(0)
	if f.mech.rings ~= 2 then fail("a new stock did not start with both rings") end
end

-- 9. A bot throws its rings - and never with empty hands (Ai.luau, "Returning zoner").
do
	local m = Match.new({ mode = "StockFFA", stage = stageData, seed = 2, items = false, stocks = 3,
		fighters = { { char = Loadout.build("Classic", "Chakram"), isBot = true, botLevel = "hard", team = 0 },
			{ char = Loadout.build("Noir", "Sword"), isBot = true, botLevel = "hard", team = 1 } } })
	m.state = "fight"
	local throws, dry, seen = 0, 0, 0
	for _ = 1, 60 * 60 do
		if m.results then break end
		m:step()
		if #m.events < seen then seen = 0 end
		for i = seen + 1, #m.events do
			local e = m.events[i]
			if e.type == "projectile" and (e.shape == "ring" or e.shape == "eclipse") then throws += 1 end
			if e.type == "dryfire" then dry += 1 end
		end
		seen = #m.events
	end
	if throws < 5 then fail(`a hard Chakram bot threw {throws} rings in a minute`) end
	if dry > 0 then fail(`a Chakram bot tried {dry} throws with empty hands`) end
	-- and with its hands held empty (both rings out, for 20 s), it does not try
	local f = m.fighters[1]
	for _ = 1, 20 * 60 do
		if m.results then break end
		f.mech.rings = 0
		m:step()
		if #m.events < seen then seen = 0 end
		for i = seen + 1, #m.events do if m.events[i].type == "dryfire" then dry += 1 end end
		seen = #m.events
	end
	if dry > 0 then fail(`a Chakram bot with no rings in hand tried {dry} throws`) end
	-- and with one ring in hand, never the Halo, which needs both
	for _ = 1, 20 * 60 do
		if m.results then break end
		f.mech.rings = 1
		m:step()
		if #m.events < seen then seen = 0 end
		for i = seen + 1, #m.events do if m.events[i].type == "dryfire" then dry += 1 end end
		seen = #m.events
	end
	if dry > 0 then fail(`a Chakram bot with one ring in hand tried {dry} Halos`) end
end

-- Empty hands only prevent throws. An airborne up-heavy is the free recovery hop; replacing it
-- with light makes a bot swing an aerial while falling past the ledge, even with recovery unused.
do
	local Ai = Loader.load("Ai")
	local recovered, cases, hops = 0, 0, 0
	for _, side in { -1, 1 } do
		for seed = 1, 8 do
			local match = Match.new({ mode = "Training", stage = stageData, seed = seed, items = false,
				fighters = { { char = Loadout.build("Classic", "Chakram"), isBot = true, botLevel = "hard", team = 0 },
					{ char = Loadout.build("Noir", "Sword"), isBot = true, botLevel = "dummy", team = 1 } } })
			match.state = "fight"
			local f, foe = match.fighters[1], match.fighters[2]
			local main = match.stage.main
			local edge = if side < 0 then main.x1 else main.x2
			f:reset(edge + side * (9 + seed * 0.4), main.top - 8 - seed * 0.8, { state = "air", invincible = 0 })
			f.jumpsLeft, f.vx, f.vy, f.mech.rings = 0, side * 12, -12, 0
			foe:reset(0, main.top, { state = "idle", invincible = 0 })
			foe.onGround, foe.platform = true, main
			local input = Ai.computeBotInput(f, match)
			if input.heavy and input.y > 0 and not input.light then hops += 1 end
			for _ = 1, 240 do
				match:step()
				if f.state == "ledge" or (f.onGround and f.alive) then recovered += 1; break end
				if not f.alive then break end
			end
			cases += 1
		end
	end
	print(`Chakram empty-handed recovery: {hops}/{cases} hops requested, {recovered}/{cases} returned`)
	assert(hops == cases, "empty-handed bot replaced its recovery hop with an aerial")
	assert(recovered >= 12, "empty-handed Chakram bots failed to return to the ledge")
end

-- 9. Its own poses: the Chakram is neither the defaults nor a borrowed Grimoire. Every move below
-- is posed through the same WeaponPose and Channels the renderer uses.
do
	local WeaponPose = Loader.loadFrom("src/client/", "WeaponPose")
	local Channels = Loader.loadFrom("src/client/", "Channels")
	local Fighter, Snapshot = Loader.load("Fighter"), Loader.load("Snapshot")
	local function posed(weapon: string, id: string, mfAt: (any) -> number): (any, any)
		local ch = Loadout.build("Classic", weapon)
		local f = Fighter.new({ index = 0, char = ch, x = 0, y = 0, stocks = 3 })
		f.facing = 1; f.onGround = true
		f:setState("idle"); f:startMove(id)
		f.mf = mfAt(f)
		local snap = Snapshot.decode(Snapshot.encode(f))
		return WeaponPose.For(snap, ch, ch.moves[id], 0), Channels.For(snap, ch, ch.moves[id], 0)
	end
	local REST = WeaponPose.REST
	if REST.Chakram == nil then fail("the Chakram has no REST angle of its own") end
	if REST.Chakram == -70 * math.pi / 180 then fail("the Chakram rests where an unknown weapon would") end

	-- the ultimate is not the Grimoire's, at several frames of the move
	for _, at in { 8, 24, 26, 40, 50, 55 } do
		local wp, body = posed("Chakram", "Ultimate", function() return at end)
		local gp, gbody = posed("Grimoire", "Ultimate", function() return at end)
		local same = wp.angle == gp.angle and wp.oy == gp.oy and wp.hide == gp.hide
			and body.armR.z == gbody.armR.z and body.armL.z == gbody.armL.z
		if same then fail(`the Chakram's ultimate at frame {at} is the Grimoire's pose`) end
	end
	-- wound up, the ring is raised overhead; while it circles the hand is empty, and it is back by the end
	local wind = posed("Chakram", "Ultimate", function(f) return f.startupEff end)
	if wind.angle < 1.5 or wind.hide then fail("Eclipse Ring's wind-up does not raise the ring overhead in hand") end
	local orbit = posed("Chakram", "Ultimate", function(f) return f.startupEff + 4 end)
	if not orbit.hide then fail("the hand still holds a ring while the giant one circles") end
	local done = posed("Chakram", "Ultimate", function(f) return f.startupEff + 2 + f.move.recovery end)
	if done.hide then fail("the ring never comes back to hand after Eclipse Ring") end
	-- the throw: the arm winds up high behind the head, then reaches forward
	local _, cocked = posed("Chakram", "Ultimate", function(f) return f.startupEff + 2 + math.floor(f.move.recovery * 0.62) end)
	local _, thrown = posed("Chakram", "Ultimate", function(f) return f.startupEff + 2 + math.floor(f.move.recovery * 0.82) end)
	if cocked.armR.z < 2.9 then fail(`Eclipse Ring's arm is not cocked back ({cocked.armR.z})`) end
	if thrown.armR.z > 2.0 then fail(`Eclipse Ring's arm never throws forward ({thrown.armR.z})`) end

	-- the signatures: a ring thrown leaves an empty hand, and it is back when the throw ends
	for _, id in { "SigSide", "SigDown", "SigNeutral" } do
		local held = posed("Chakram", id, function(f) return f.startupEff end)
		if held.hide then fail(`{id}: the ring is not in hand while winding up`) end
		local gone = posed("Chakram", id, function(f) return f.startupEff + 2 end)
		if not gone.hide then fail(`{id}: the ring is still in the hand after it was thrown`) end
		local back = posed("Chakram", id, function(f) return f.startupEff + 2 + f.move.recovery end)
		if back.hide then fail(`{id}: the hand stays empty after the throw ends`) end
	end
	-- Orbit Throw winds far behind and finishes forward; Ground Saw winds low and finishes low and forward
	local _, sideCock = posed("Chakram", "SigSide", function(f) return f.startupEff end)
	local _, sideThrow = posed("Chakram", "SigSide", function(f) return f.startupEff + 2 end)
	if sideCock.armR.z > -1.5 or sideThrow.armR.z < 0.9 then fail("Orbit Throw is not a back-to-front throwing arm") end
	local sawWp = posed("Chakram", "SigDown", function(f) return f.startupEff end)
	local _, sawThrow = posed("Chakram", "SigDown", function(f) return f.startupEff + 2 end)
	if sawWp.angle > 0 then fail("Ground Saw does not wind up low") end
	if sawThrow.armR.z > 1.2 or sawThrow.armR.z < 0.2 then fail("Ground Saw is not an underhand arm (low and forward)") end
	-- Halo: both arms raised and spread (right behind, left ahead, both above the shoulders)
	local _, halo = posed("Chakram", "SigNeutral", function(f) return f.startupEff + 2 end)
	if halo.armR.z > -1.5 or halo.armL.z < 1.5 then fail("Halo's arms are not raised and spread") end
end

print("PASS chakram: its own rest, throwing arms and ultimate (not the defaults, not the Grimoire's), an empty hand once a ring is thrown; Orbit Throw out ~22 studs, home and caught, a hit each way; rings spent and refused (dryfire, Halo needs both); Ground Saw on the floor and turning at the ledge; Halo circles both rings; Eclipse circles, out and back; no ring lost to a KO, the blast zone or a new stock; in the roster with its art; a bot throws its rings, never empty-handed")
