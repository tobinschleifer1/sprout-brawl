--!strict
-- One lobby window at a time (Windows; Roblox only): opening one closes every other open one;
-- toggling an open one closes only it; a window kept (the Character Studio, which asks before
-- losing unsaved work) is never closed by another opening, but opening it closes the rest.
--
--     lune run tests/windows
local Loader = require("./loader")
local Windows = Loader.loadFrom("src/client/", "Windows")

local w = Windows.new()
local state: { [string]: boolean } = {}
local closes: { [string]: number } = {}
local function reg(name: string, keep: boolean?)
	state[name], closes[name] = false, 0
	w:add(name, { keep = keep, isOpen = function() return state[name] end,
		close = function() state[name] = false; closes[name] += 1 end })
end
for _, n in { "shop", "locker", "settings", "social" } do reg(n) end
reg("studio", true)
local function toggle(name: string)
	w:toggle(name, function() return state[name] end, function() state[name] = true end, function() state[name] = false end)
end
local function only(name: string?, what: string)
	for n, open in state do assert(open == (n == name), `{what}: {n} is {if open then "open" else "shut"}`) end
end

toggle("shop"); only("shop", "the Shop opened")
toggle("settings"); only("settings", "Settings opened over the Shop")
toggle("locker"); only("locker", "the Locker opened over Settings")
toggle("locker"); only(nil, "the Locker toggled shut")
-- a panel that opens itself (PLAY) and says so
toggle("shop"); w:opening("social"); state.social = true
only("social", "PLAY opened over the Shop")
-- the studio closes the rest, and nothing closes it
toggle("studio"); only("studio", "the studio opened over PLAY")
toggle("shop")
assert(state.studio and state.shop and closes.studio == 0, "opening the Shop closed the studio, which may hold unsaved work")
-- nothing shut is closed again
local before = closes.locker
toggle("settings")
assert(closes.locker == before, "a shut window was closed again")

print("PASS windows: one lobby window at a time - Shop, Locker, Settings, PLAY; toggling shuts only itself; the studio is never shut by another")
