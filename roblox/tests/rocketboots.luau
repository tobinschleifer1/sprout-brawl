--!strict
-- Rocket Boots (Roblox only: src/shared/RobloxWeapons.luau, mechanic ThrustFuel in Fighter.luau and
-- Combat.onMoveActive, Redline Reversal in Combat.stepRedline). Asserted directly, in real matches:
-- 1. In the game: the merged roster, built by Loadout, with art.
-- 2. Fuel is spent at ignition, by exactly the move's cost; a kick interrupted in its wind-up costs
--    nothing.
-- 3. A signature without the fuel for it is refused (dryfire); the kicks need none.
-- 4. The tank refills only after regenDelay frames standing or running on the ground, at regen a
--    frame; never in the air; and any other state starts the wait again.
-- 5. The recovery burns recoveryCost for a full hop; without it, a weaker hop (never none); still
--    once per airtime.
-- 6. Redline Reversal carries the kicker forward, back, then further forward; never off the
--    platform; and kicks a victim once a window at most.
-- 7. A new stock starts with a full tank.
-- 8. A bot never asks for a signature it cannot afford.
local Loader = require("./loader")
local Match, Loadout = Loader.load("Match"), Loader.load("Loadout")
local Weapons = Loader.load("Weapons")
local Remote = Loader.loadFrom("src/server/", "RemoteInput")
local function fail(msg: string) error(msg, 0) end
local stageData = Loader.load("Data/Stages").LIST[1]

local function setup(): (any, any, any)
	local input = Remote.new(); input:register("p1"); input:register("p2")
	local match = Match.new({ mode = "Training", stage = stageData, seed = 1, items = false, input = input,
		fighters = { { char = Loadout.build("Classic", "RocketBoots"), source = "p1", team = 0 },
			{ char = Loadout.build("Noir", "Sword"), source = "p2", team = 1 } } })
	match.state = "fight"
	local f, foe = match.fighters[1], match.fighters[2]
	f:reset(0, 0, { state = "idle", invincible = 0 }); f.onGround = true; f.platform = match.stage.main; f.facing = 1
	foe:reset(60, 0, { state = "idle", invincible = 0 }); foe.onGround = true; foe.platform = match.stage.main
	return match, f, foe
end
local function run(match: any, n: number, each: ((number) -> ())?)
	for i = 1, n do match:step(); if each then each(i) end end
end
local function dried(f: any): boolean
	for _, e in f.events do if e.type == "dryfire" then return true end end
	return false
end

-- 1. In the game.
local B = Weapons.BY_ID.RocketBoots
if not B or not Weapons.ROBLOX_ONLY.RocketBoots then fail("Rocket Boots are not in the merged roster") end
local char = Loadout.build("Classic", "RocketBoots")
if char.weapon.id ~= "RocketBoots" or char.mechanic.id ~= "ThrustFuel" then fail("Loadout did not build the Rocket Boots") end
if not Weapons.ART.sprites.RocketBoots or #Weapons.ART.sprites.RocketBoots < 10 then fail("the Rocket Boots have no art") end
local M = char.mechanic

-- 2. Spent at ignition, by the cost; nothing for an interrupted wind-up.
do
	local match, f = setup()
	f:startMove("SigSide")
	if f.mech.fuel ~= M.max then fail("fuel was spent before the kick ignited") end
	run(match, B.moves.SigSide.startup + 1)
	if f.mech.fuel ~= M.max - B.moves.SigSide.fuelCost then fail(`Jet Kick left {f.mech.fuel} fuel, want {M.max - B.moves.SigSide.fuelCost}`) end
	local match2, g = setup()
	g:startMove("SigNeutral"); run(match2, 5)
	g.move = nil; g:setState("hitstun")             -- hit out of the wind-up
	run(match2, 30)
	if g.mech.fuel ~= M.max then fail(`a kick interrupted in its wind-up cost {M.max - g.mech.fuel} fuel`) end
end

-- 3. Refused without the fuel; the kicks need none.
do
	local match, f = setup()
	f.mech.fuel = B.moves.SigNeutral.fuelCost - 1
	table.clear(f.events)
	f:startMove("SigNeutral")
	if f.moveId == "SigNeutral" or not dried(f) then fail("Ignition Heel started without the fuel for it") end
	f.mech.fuel = 0
	f:startMove("LightNeutral1")
	if f.moveId ~= "LightNeutral1" then fail("a kick was refused on an empty tank") end
	run(match, 1)
end

-- 4. The refill.
do
	local match, f = setup()
	f.mech.fuel, f.mech.grounded = 10, 0
	local function standFor(n: number)
		for _ = 1, n do f:setState("idle"); f.onGround = true; match:step() end
	end
	standFor(M.regenDelay)
	if f.mech.fuel ~= 10 then fail(`the tank refilled before {M.regenDelay} frames on the ground ({f.mech.fuel})`) end
	standFor(10)
	if math.abs(f.mech.fuel - (10 + 10 * M.regen)) > 1e-9 then fail(`ten frames of refill gave {f.mech.fuel - 10}, want {10 * M.regen}`) end
	-- in the air: nothing
	local before = f.mech.fuel
	for _ = 1, 40 do f.onGround = false; f:setState("air"); f.y = 6; match:step() end
	if f.mech.fuel ~= before then fail("the tank refilled in the air") end
	-- and the wait starts again after any other state
	f.y = 0; f.onGround = true
	standFor(M.regenDelay)
	if f.mech.fuel ~= before then fail("leaving the ground did not restart the refill's wait") end
	run(match, 1)
end

-- 5. The recovery.
do
	local match, f = setup()
	f.onGround = false; f.y = 6; f:setState("air"); f.recoveryUsed = false
	f.input.x = 0
	f:_startRecovery({ stage = match.stage, combat = match.combat })
	local full = f.vy
	if f.mech.fuel ~= M.max - M.recoveryCost then fail(`the recovery cost {M.max - f.mech.fuel}, want {M.recoveryCost}`) end
	local match2, g = setup()
	g.onGround = false; g.y = 6; g:setState("air"); g.recoveryUsed = false; g.mech.fuel = M.recoveryCost - 1
	table.clear(g.events)
	g:_startRecovery({ stage = match2.stage, combat = match2.combat })
	if g.state ~= "recovery" then fail("an empty tank took the recovery away") end
	if math.abs(g.vy - full * M.weakRecovery) > 1e-9 then fail(`a sputtering recovery rose at {g.vy}, want {full * M.weakRecovery}`) end
	if not dried(g) then fail("a sputtering recovery did not say so") end
	local vy = g.vy
	g:_startRecovery({ stage = match2.stage, combat = match2.combat })
	if g.vy ~= vy then fail("the recovery fired twice in one airtime") end
end

-- 6. Redline Reversal.
do
	local match, f, foe = setup()
	foe.x = 3                                       -- in front, inside the first kick
	local x0 = f.x
	f.ultCharge = 100
	f:startMove("Ultimate")
	local xs: { [number]: number } = {}
	local hits, last = 0, foe.percent
	-- by the MOVE's frame: an ultimate opens with a cinematic freeze that holds the move still
	run(match, B.moves.Ultimate.total + 60, function()
		if f.moveId == "Ultimate" then xs[f.mf] = f.x end
		if foe.percent > last then hits += 1 end
		last = foe.percent
		foe.x, foe.y, foe.vx, foe.vy = f.x + 3 * f.facing, 0, 0, 0
		foe.hitstun = 0; foe.state = "idle"; foe.invincible = 0
	end)
	local W = B.moves.Ultimate.redline
	local function at(frame: number): number return xs[frame] or x0 end
	local d1 = at(W[1][2]) - at(W[1][1] - 1)
	local d2 = at(W[2][2]) - at(W[2][1] - 1)
	local d3 = at(W[3][2]) - at(W[3][1] - 1)
	if math.abs(d1 - W[1][3]) > 0.6 or math.abs(d2 - W[2][3]) > 0.6 or math.abs(d3 - W[3][3]) > 0.6 then
		fail(`Redline carried {d1}, {d2}, {d3} studs, want {W[1][3]}, {W[2][3]}, {W[3][3]}`)
	end
	if hits < 2 or hits > 3 then fail(`Redline kicked a victim held in front {hits} times, want 2 or 3 (once a window)`) end
	-- at the ledge, held on the platform
	local match2, g = setup()
	local main = match2.stage.main
	g.x = main.x2 - 2; g.ultCharge = 100
	g:startMove("Ultimate")
	run(match2, B.moves.Ultimate.total + 60, function()
		if g.x > main.x2 then fail("Redline carried the kicker off the platform") end
	end)
end

-- 7. A full tank on a new stock.
do
	local _, f = setup()
	f.mech.fuel = 0
	f:respawn(0)
	if f.mech.fuel ~= M.max then fail("a new stock did not start with a full tank") end
end

-- 8. A bot never asks for a signature it cannot afford.
do
	local m = Match.new({ mode = "StockFFA", stage = stageData, seed = 3, items = false, stocks = 3,
		fighters = { { char = Loadout.build("Classic", "RocketBoots"), isBot = true, botLevel = "hard", team = 0 },
			{ char = Loadout.build("Noir", "Sword"), isBot = true, botLevel = "hard", team = 1 } } })
	m.state = "fight"
	local f = m.fighters[1]
	local sigs, dry, seen = 0, 0, 0
	for i = 1, 90 * 60 do
		if m.results then break end
		if i > 60 * 60 then f.mech.fuel = 10 end        -- the last 30 s on a near-empty tank
		m:step()
		if #m.events < seen then seen = 0 end
		for k = seen + 1, #m.events do
			local e = m.events[k]
			if e.type == "thrust" then sigs += 1 end
			if e.type == "dryfire" and e.fuel and f.state ~= "recovery" then dry += 1 end
		end
		seen = #m.events
	end
	if sigs < 3 then fail(`a hard Rocket Boots bot ignited {sigs} signatures in a minute and a half`) end
	if dry > 0 then fail(`a Rocket Boots bot asked for {dry} signatures it could not afford`) end
end

print("PASS rocket boots: in the roster with art; fuel spent at ignition by the cost, nothing for an interrupted kick; signatures refused without fuel, kicks free; refill only after the wait on the ground, never in the air; recovery burns fuel or sputters, never none, once per airtime; Redline carries forward, back, forward, held on the platform, once a window; full tank each stock; bots never ask for what they cannot afford")
