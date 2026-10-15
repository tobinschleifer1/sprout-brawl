--!nocheck
-- Compare local prediction to the REAL activation hooks, before any correcting packet arrives.
-- The old prediction suite stubs combat on both sides and cannot detect a missing self impulse
-- or resource spend in a new weapon's Combat hook.
local Loader = require("./loader")
local Fighter, Combat, Stage = Loader.load("Fighter"), Loader.load("Combat"), Loader.load("Stage")
local Loadout, Snapshot, Input = Loader.load("Loadout"), Loader.load("Snapshot"), Loader.load("Input")
local Predictor = Loader.loadFrom("src/client/", "Predictor")
local data = Loader.load("Data/Stages").BY_ID.FoundryFloor
local checked = 0
for _, weapon in { "RocketBoots", "Chakram" } do
	for _, move in { "SigSide", "SigDown", "SigNeutral", "Ultimate" } do
		for _, facing in { -1, 1 } do
			local char = Loadout.build("Classic", weapon)
			local stage = Stage.new(data, 999)
			local truth = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
			local x = if move == "Ultimate" then (if facing == 1 then stage.main.x2 - 2 else stage.main.x1 + 2) else 0
			truth:reset(x, stage.main.top, { state = "idle", invincible = 0 })
			truth.onGround, truth.platform, truth.facing, truth.ultCharge = true, stage.main, facing, 100
			local combat = Combat.new({ stage = stage, fighters = { truth } })
			local ctx = { stage = stage, fighters = { truth }, combat = combat }
			truth:startMove(move)
			local pred = Predictor.new(char, 0, Stage.new(data, 999))
			pred:reconcile(Snapshot.decode(Snapshot.encode(truth)), 0)
			local history = {}
			for frame = 1, char.moves[move].total + 60 do
				local input = Input.emptyFrame()
				truth:applyInput(input); truth:step(ctx)
				history[frame] = Snapshot.decode(Snapshot.encode(truth))
				pred:push(input)
				local function compare()
					local got, want = pred:state(), history[frame]
					for _, key in { "x", "y", "vx", "vy", "fuel", "rings", "state", "moveFrame" } do
						local equal = if type(want[key]) == "number" then math.abs(got[key] - want[key]) < 1e-8 else got[key] == want[key]
						assert(equal, `{weapon}/{move} frame {frame}: predicted {key} {got[key]}, server {want[key]}`)
						checked += 1
					end
				end
				compare()
				if frame > 3 and frame % 4 == 0 then
					pred:reconcile(history[frame - 3], frame - 3)
					compare()
				end
			end
		end
	end
end

-- Joining or correcting while the tank is part-full must preserve the refill delay too. The
-- resource amount alone cannot distinguish just-landed boots from boots already regenerating.
for _, grounded in { 0, 29, 30, 60 } do
	local char = Loadout.build("Classic", "RocketBoots")
	local stage = Stage.new(data, 999)
	local truth = Fighter.new({ index = 0, char = char, x = 0, y = stage.main.top, stocks = 3 })
	truth:reset(0, stage.main.top, { state = "idle", invincible = 0 })
	truth.onGround, truth.platform = true, stage.main
	truth.mech.fuel, truth.mech.grounded = 55, grounded
	local pred = Predictor.new(char, 0, Stage.new(data, 999))
	pred:reconcile(Snapshot.decode(Snapshot.encode(truth)), 0)
	local ctx = { stage = stage, fighters = { truth }, combat = Combat.new({ stage = stage, fighters = { truth } }) }
	for frame = 1, 45 do
		local input = Input.emptyFrame()
		truth:applyInput(input); truth:step(ctx)
		pred:push(input)
		assert(pred:state().fuel == truth.mech.fuel, `refill delay lost after join at {grounded}: frame {frame}`)
		assert(pred.fighter.mech.grounded == truth.mech.grounded, "refill clock not reconciled")
		checked += 2
	end
end
print(`PASS new-weapon prediction: {checked} live/replayed self-motion and resource values against real Combat hooks`)
