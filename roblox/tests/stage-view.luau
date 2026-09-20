--!strict
-- The client's view-only Stage, moved by the server.
--
--     lune run tests/stage-view
--
-- The client never steps its Stage: a stepped copy would advance platforms off its own clock and
-- draw hazard RNG from the shared seed, and both would drift from the server within seconds. So
-- the server sends the platform state instead, and this checks that what it sends is enough to put
-- an unstepped stage exactly where the stepped one is.
--
-- There is no JavaScript counterpart to compare against - the web build has one Stage and no
-- network - so this is a round trip against a stage that WAS stepped, which is the only thing that
-- makes the claim meaningful.

local Loader = require("./loader")
local Stage = Loader.load("Stage")
local Stages = Loader.load("Data/Stages")

local function fail(msg: string): never
	error(msg, 0)
end

local function stageFor(id: string): any
	for _, data in Stages.LIST do
		if data.id == id then
			return Stage.new(data, 12345)
		end
	end
	return fail(`no such stage: {id}`)
end

local checked = 0

-- Undertow has a moving raft and two moving buoys; Smeltworks has a sinking gantry. The other four
-- have nothing dynamic and must send nil rather than an empty table.
for _, id in { "FoundryFloor", "TheSpan", "Rooftops", "Saltflat" } do
	local st = stageFor(id)
	if Stage.dynamicState(st) ~= nil then
		fail(`{id} has nothing that moves but still sent a platform payload`)
	end
	checked += 1
end

for _, id in { "Undertow", "Smeltworks" } do
	local live = stageFor(id)
	local view = stageFor(id)
	local payload = Stage.dynamicState(live)
	if payload == nil then
		fail(`{id} has a moving or sinking platform but sent nothing`)
	end

	-- A fighter parked on every platform, so the sinking branch actually runs rather than being
	-- skipped for want of anybody standing on it.
	local stub = { fighters = {} }
	for _, p in live.platforms do
		-- Enough of a fighter for Stage.step: it stands on the platform, carries the env bag the
		-- hazards write into, and can be told to drop through when the gantry gives way.
		table.insert(stub.fighters, {
			alive = true, onGround = true, platform = p, x = p.cx, y = p.top,
			vx = 0, vy = 0, r = 0.5, h = 5.2, percent = 0, state = "idle",
			env = { updraft = 0, windX = 0, traction = 1, grip = 1, damp = 1 },
			dropThrough = function() end,
		})
	end

	local moved = false
	for frame = 1, 240 do
		Stage.step(live, stub)
		local state = Stage.dynamicState(live)
		Stage.applyDynamicState(view, state)
		for _, e in state :: { any } do
			local a, b = live.platforms[e.i], view.platforms[e.i]
			for _, key in { "cx", "top", "x1", "x2", "cy", "bottom" } do
				if (a :: any)[key] ~= (b :: any)[key] then
					fail(`{id} frame {frame}: platform {e.i} {key} is {(b :: any)[key]} on the view `
						.. `and {(a :: any)[key]} on the server`)
				end
				checked += 1
			end
			if frame > 1 and (a.dx ~= 0 or a.dy ~= 0) then
				moved = true
				-- The deltas have to survive too. A view whose platforms teleport with dx/dy of
				-- zero tells the ledge logic and the renderer that nothing moved.
				if b.dx ~= a.dx or b.dy ~= a.dy then
					fail(`{id} frame {frame}: platform {e.i} delta is ({b.dx}, {b.dy}) on the view `
						.. `and ({a.dx}, {a.dy}) on the server`)
				end
				checked += 2
			end
		end
	end
	if not moved then
		fail(`{id} was stepped 240 frames and nothing ever moved - this test proved nothing`)
	end
end

print(`checked {checked} view-stage values`)
print("Stage.dynamicState carries a moving platform exactly onto an unstepped copy.")
