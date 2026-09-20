--!strict
-- Client-side prediction, against a simulation that never had to predict anything.
--
--     lune run tests/prediction
--
-- The claim prediction makes is narrow and testable: running the local fighter ahead of the server
-- and correcting it on every snapshot must land in the SAME state as simply stepping it once per
-- frame. If that holds, prediction costs nothing but latency; if it does not, the player is
-- playing a different game from the one the server is running.
--
-- So this runs two fighters from identical starts on identical inputs. `truth` is stepped once per
-- frame and is the server. `pred` is stepped immediately on every input, and every few frames is
-- handed the truth's wire state from LAG frames ago and made to replay everything after it. They
-- are compared on every wire field after every reconcile.
--
-- The lag is deliberately varied, and deliberately includes zero: a reconcile with nothing
-- outstanding is the case where an off-by-one in the replay window is silent.

local Loader = require("./loader")
local Fighter = Loader.load("Fighter")
local Stage = Loader.load("Stage")
local Stages = Loader.load("Data/Stages")
local Loadout = Loader.load("Loadout")
local Input = Loader.load("Input")
local Snapshot = Loader.load("Snapshot")
local Predictor = Loader.loadFrom("src/client/", "Predictor")

local function fail(msg: string): never
	error(msg, 0)
end

local function stubCombat(fighters: any): any
	return {
		fighters = fighters,
		useItem = function() end, dropItem = function() end,
		itemNear = function() return nil end, pickupItem = function() end,
		hasFruit = function() return false end, fruiting = function() end,
		nearestNode = function() return nil end, removeSummon = function() end,
		onMoveActive = function() end, onMoveActiveFrame = function() end,
		spawnBurst = function() end, checkGrab = function() end,
		resolveThrow = function() end,
	}
end

local function stageFor(): any
	for _, data in Stages.LIST do
		if data.id == "FoundryFloor" then
			return Stage.new(data, 999)
		end
	end
	return fail("no FoundryFloor")
end

-- A scripted run: walk, run, jump, attack, fastfall, shield. Enough to cross most of the state
-- machine, because a test that only walks proves only that standing still is predictable.
local function inputAt(n: number): any
	local f = Input.emptyFrame()
	local phase = n % 120
	if phase < 20 then
		f.x = 0.6
	elseif phase < 40 then
		f.x = 1
	elseif phase < 45 then
		f.x = 1; f.jump = true; f.jumpHeld = true
	elseif phase < 60 then
		f.x = 0.8; f.jumpHeld = true
	elseif phase < 66 then
		f.light = true; f.anyPress = true
	elseif phase < 80 then
		f.y = -1; f.downTap = true
	elseif phase < 95 then
		f.guard = true; f.guardHeld = true
	elseif phase < 105 then
		f.x = -1
	else
		f.heavy = true; f.anyPress = true
	end
	-- A press every few frames, so the input buffers are almost never zero. They decay by one per
	-- frame, which makes them the most sensitive thing in the fighter to a rollback that lands on
	-- the wrong frame - but only if they are actually carrying a value.
	if n % 7 == 0 then
		f.light = true; f.anyPress = true
	end
	if n % 11 == 0 then
		f.guard = true
	end
	return f
end

local checked, reconciles, afterMiss = 0, 0, 0
local MISPREDICT_AT = { [182] = true, [225] = true, [245] = true }

for _, weapon in { "Sword", "Blasters", "Pike", "Hammer" } do
	for _, LAG in { 0, 1, 2, 4, 7 } do
		local char = Loadout.build("Classic", weapon)
		local stage = stageFor()

		local truth = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
		local truthCtx = { stage = stage, combat = stubCombat({ truth }), fighters = { truth } }

		local pred = Predictor.new(char, 0, stage)
		-- Start both from the same place. The predictor is not "ready" until its first
		-- reconcile, exactly as on the client, so frame 1 anchors it.
		local history: { any } = {}

		for n = 1, 300 do
			local frame = inputAt(n)

			-- The server's frame.
			truth:applyInput(frame)
			truth:step(truthCtx)

			-- A GENUINE MISPREDICT. Without this the truth and the prediction run the same inputs
			-- through the same code and never disagree, so every correction is a no-op and the
			-- test proves only that the replay bookkeeping is arithmetically sound. These are hits
			-- the client could not have known about - combat is stubbed out of prediction on
			-- purpose - and they are placed mid-attack so the correction has to take the fighter
			-- OUT of a move, which is the case where repairing `move` from moveId matters.
			if n == 182 or n == 225 then
				truth.vx, truth.vy = -14.5, 26.5
				truth.hitstun = 22
				truth.percent += 18
				truth.tumbling = true
				truth.effects.chill.stacks = 2      -- a chill the client had no way to see coming
				-- Off the ground, which the client does not know: its own rollback state still has
				-- it standing on a platform, and that reference has to be cleared by the
				-- correction rather than left pointing at a floor the server says it left.
				truth.onGround = false
				truth.platform = nil
				truth:setState("hitstun")
			elseif n == 245 then
				-- A move the client is not in. The correction has to carry the fighter INTO an
				-- attack it never predicted, which is the case where `moveId` arrives without the
				-- `move` table the state machine actually reads.
				truth:setState("attack")
				truth.moveId = "SigSide"
				truth.move = char.moves.SigSide
				truth.mf = 3
				truth.startupEff = char.moves.SigSide.startup
			end

			history[n] = Snapshot.decode(Snapshot.encode(truth))

			-- The client's: simulate immediately.
			pred:push(frame)

			-- A snapshot arrives describing frame n - LAG. The server has therefore consumed
			-- exactly (n - LAG) of our frames.
			local at = n - LAG
			if at >= 1 then
				pred:reconcile(history[at], at)
				reconciles += 1

				-- Whether the replay window (at, n] contains something the client could not have
				-- predicted. If it does, the predictor is RIGHT to disagree: it has not been told
				-- yet. Comparing there would assert that prediction is clairvoyant.
				local blind = false
				for k = at + 1, n do
					if MISPREDICT_AT[k] then
						blind = true
					end
				end

				-- Once the hit is inside the state we anchored to, the predictor must have taken
				-- it on board and replayed from there - which is the whole point of a rollback.
				if not blind then
					for k = at, n do
						if MISPREDICT_AT[k] then
							afterMiss += 1
						end
					end
				end

				-- After reconciling to frame `at` and replaying LAG frames, the predictor must be
				-- exactly where the truth is NOW.
				local got = pred:state()
				local want = history[n]
				for _, pair in Snapshot.FIELDS do
					if blind then
						break
					end
					local key = pair[1]
					local a, b = got[key], want[key]
					if type(a) == "number" and type(b) == "number" then
						if math.abs(a - b) > 1e-9 then
							fail(`{weapon} lag={LAG} frame {n}: {key} predicted {a}, server {b}`)
						end
					elseif a ~= b then
						fail(`{weapon} lag={LAG} frame {n}: {key} predicted {tostring(a)}, `
							.. `server {tostring(b)}`)
					end
					checked += 1
				end

				-- The state the wire does NOT carry. A rollback that restores the wire fields and
				-- leaves these as prediction left them passes every assertion above while quietly
				-- running the fighter on stale input buffers and a spent double jump. Every
				-- mispredict injected here is confined to wire fields, so after the correction is
				-- acknowledged there is nothing that could legitimately hold these apart.
				if not blind then
					-- `platform` is an object reference, which the wire cannot carry at all. Both fighters
					-- here share one stage, so the reference itself is comparable - and a correction
					-- that says "airborne" while leaving a floor reference behind is a fighter
					-- standing on something the server says it left.
					for _, key in { "jumpsLeft", "airDodgeUsed", "recoveryUsed", "ledgeGrabs", "platform" } do
						if (pred.fighter :: any)[key] ~= (truth :: any)[key] then
							fail(`{weapon} lag={LAG} frame {n}: non-wire {key} is `
								.. `{tostring((pred.fighter :: any)[key])} predicted, `
								.. `{tostring((truth :: any)[key])} on the server`)
						end
						checked += 1
					end
					for _, key in { "jump", "light", "heavy", "guard" } do
						if pred.fighter.buffer[key] ~= truth.buffer[key] then
							fail(`{weapon} lag={LAG} frame {n}: input buffer '{key}' is `
								.. `{pred.fighter.buffer[key]} predicted, {truth.buffer[key]} on `
								.. `the server - the replay applied a frame twice`)
						end
						checked += 1
					end
				end
			end
		end
	end
end

-- A run where every comparison was skipped would print a pass having asserted nothing.
if afterMiss == 0 then
	fail("no comparison ever ran with a mispredict already acknowledged - "
		.. "the correction path was never tested")
end

print(`checked {checked} predicted values across {reconciles} reconciles`)
print(`{afterMiss} of them were the frame a correction landed on`)
print("Prediction converges on the server's state at every lag tested, including after a hit "
	.. "it could not have predicted.")
