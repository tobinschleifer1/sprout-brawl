--!strict
-- The HUD's damage ramp, against the JavaScript's.
--
--     lune run tests/hud-parity
--
-- Only the arithmetic. web/src/ui/hud.js is a DOM tree and the Roblox HUD is a ScreenGui; there is
-- nothing to compare between them but this, and this is exactly the part nobody would notice was
-- wrong - a ramp off by one stop still produces a plausible colour for every percent.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")
local HudColors = Loader.loadFrom("src/client/", "HudColors")

local function fail(msg: string): never
	error(msg, 0)
end

local fixture = serde.decode("json", fs.readFile("tests/hud-fixture.json"))
local checked = 0

-- The JavaScript returns "rgb(r,g,b)"; Color3.fromRGB stores 0-1 floats. Compare as integers.
local function parse(css: string): (number, number, number)
	local r, g, b = string.match(css, "rgb%((%d+),(%d+),(%d+)%)")
	if not r then
		fail(`could not parse "{css}"`)
	end
	return tonumber(r) :: number, tonumber(g) :: number, tonumber(b) :: number
end

local function channels(c: Color3): (number, number, number)
	return math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)
end

for _, row in fixture.rows do
	local p = tonumber(row.p) :: number
	local wr, wg, wb = parse(row.c)
	local gr, gg, gb = channels(HudColors.percent(p))
	if gr ~= wr or gg ~= wg or gb ~= wb then
		fail(`percent {p}: Luau says ({gr},{gg},{gb}), JavaScript says ({wr},{wg},{wb})`)
	end
	checked += 3
end

-- The palettes are data and must not drift either: a player whose tile is a different colour from
-- their marker is worse than one with no colour at all.
if #HudColors.PLAYER ~= #fixture.playerColors then
	fail(`{#HudColors.PLAYER} player colours here, {#fixture.playerColors} in the JavaScript`)
end
for i, css in fixture.playerColors do
	local want = string.upper(string.sub(css, 2))
	local r, g, b = channels(HudColors.PLAYER[i])
	local got = string.format("%02X%02X%02X", r, g, b)
	if got ~= want then
		fail(`player colour {i}: {got} here, {want} in the JavaScript`)
	end
	checked += 1
end
for i, mark in fixture.playerMarks do
	if HudColors.MARKS[i] ~= mark then
		fail(`player mark {i}: "{HudColors.MARKS[i]}" here, "{mark}" in the JavaScript`)
	end
	checked += 1
end

print(`checked {checked} HUD colour values`)
print("HudColors matches web/src/ui/hud.js exactly.")
