--!strict
-- The team indicator: in a team match each fighter stands in a disc of their team's colour
-- (web/src/data/teams.js), drawn with the ground shadow; not in a free-for-all, and not while
-- airborne, where there is no ground to stand the disc on.
local Loader = require("./loader")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Fighter2D = Loader.loadFrom("src/client/", "Fighter2D")
local Fighter = Loader.load("Fighter")
local Snapshot = Loader.load("Snapshot")
local Loadout = Loader.load("Loadout")
local Teams = Loader.load("Data/Teams")

local drawn: { any } = {}
Canvas.rect = function() end
Canvas.tri = function() end
Canvas.ellipse = function(c: any, x: number, y: number, rx: number, ry: number, colour: any, alpha: number?)
	table.insert(drawn, { rx = rx, ry = ry, colour = colour, alpha = alpha })
end
local function canvas(): any
	return setmetatable({ m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 }, stack = {}, alpha = 1, alphaStack = {} }, { __index = Canvas })
end
local char = Loadout.build("Classic", "Sword")
local function state(onGround: boolean): any
	local f: any = Fighter.new({ index = 3, char = char, x = 0, y = 0, stocks = 3 })
	f.state, f.onGround = if onGround then "idle" else "air", onGround
	if not onGround then f.y = 4 end
	return Snapshot.decode(Snapshot.encode(f))
end
local orange = Canvas.hex(Teams.colours[2], Canvas.hex("#000000", nil :: any))
local function glows(): number
	local n = 0
	for _, d in drawn do
		if d.colour == orange and math.abs(d.rx - char.radius * Teams.glow.rx) < 1e-9 then n += 1 end
	end
	return n
end

Fighter2D.teamColours = { [3] = orange }
Fighter2D.draw(canvas(), state(true), char, 0, 0)
assert(glows() == 1, `a grounded fighter in a team match stands in their team colour ({glows()} discs)`)
table.clear(drawn)
Fighter2D.draw(canvas(), state(false), char, 0, 0)
assert(glows() == 0, "no disc in the air, with no ground under the fighter")
table.clear(drawn)
Fighter2D.teamColours = nil
Fighter2D.draw(canvas(), state(true), char, 0, 0)
assert(glows() == 0, "no team disc in a free-for-all")
print("PASS team marks: team-coloured disc under grounded fighters in team matches only")
