--!strict
-- The launch handshake the lobby waits on (LaunchState): one request at a time, a missing
-- acknowledgement times out so the player can retry, and a match that is playing never does.
--
-- This was the tail of tests/lobby-ui.luau, which otherwise drove Select.luau - the old full-screen
-- fight menu, replaced by the room panel (RoomPanel, tests/room-ui.luau) and removed with it.
local Loader = require("./loader")
local Launch = Loader.loadFrom("src/client/", "LaunchState")
local launch = Launch.new()
assert(launch:begin(1) and not launch:begin(2), "only one pending launch")
assert(not launch:expired(8.9) and launch:expired(9), "missing acknowledgement must time out")
assert(launch:begin(10), "timeout permits retry")
launch:accept(11)
assert(launch.phase == "loading", "Match alone is not playable")
launch:ready()
assert(not launch:expired(100) and launch.phase == "playing", "a live match must not time out")
launch:reset()
assert(launch.phase == "lobby")
print("PASS launch: one pending launch, timeout and retry, loading until a snapshot, a live match never times out")
