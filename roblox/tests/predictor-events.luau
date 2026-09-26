--!strict
-- The predictor hands each predicted event to the client exactly once - a jump that is replayed
-- by a reconcile is not shown twice - stamped with the fighter and where they were, and the
-- predicted fighter's own event list stays empty. It used to be cloned into every frame's snapshot
-- and never emptied, so the per-frame copy grew for the whole match.
local Loader = require("./loader")
local Stage = Loader.load("Stage")
local Stages = Loader.load("Data/Stages")
local Loadout = Loader.load("Loadout")
local Input = Loader.load("Input")
local Snapshot = Loader.load("Snapshot")
local Fighter = Loader.load("Fighter")
local Predictor = Loader.loadFrom("src/client/", "Predictor")

local data = Stages.LIST[1]
local char = Loadout.build("Classic", "Sword")
local p = Predictor.new(char, 2, Stage.new(data, 999))
-- a server fighter to reconcile against, standing on the floor
local server = Fighter.new({ index = 2, char = char, x = 0, y = data.main.y, stocks = 3 })
server.onGround = true
server.state = "idle"
p:reconcile(Snapshot.decode(Snapshot.encode(server)), 0, nil)

local function frame(jump: boolean): any
	local f = Input.emptyFrame()
	f.jump, f.jumpHeld, f.anyPress = jump, jump, jump
	return f
end
p:push(frame(true))
for _ = 1, 20 do p:push(frame(false)) end
local seen = {}
for _, e in p:drain() do
	seen[e.type] = (seen[e.type] or 0) + 1
	if e.type == "jump" then
		assert(e.fighter == 2, "stamped with the predicted fighter")
		assert(type(e.x) == "number" and type(e.y) == "number", "stamped with where they were")
	end
end
assert(seen.jump == 1, `one jump press, {seen.jump or 0} jump events`)
assert(#p:drain() == 0, "draining empties the queue")
assert(#p.fighter.events == 0, "the predicted fighter's own list is emptied every frame")
-- a reconcile replays all 21 frames; none of their events are shown again
p:reconcile(Snapshot.decode(Snapshot.encode(server)), 0, nil)
assert(#p:drain() == 0, "a replay re-emits nothing the player already saw")
assert(#p.fighter.events == 0, "and leaves nothing behind")
for _ = 1, 600 do p:push(frame(false)) end
local snap = p.snaps[p.sent]
assert(snap and #snap.events == 0, "ten seconds later the per-frame snapshot still carries no events")
print("PASS predictor events: each predicted event shown once, stamped, never replayed; the event list no longer grows")
