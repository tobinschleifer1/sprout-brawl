--!nocheck
-- Development tool, not a test: every expression (Expressions.luau) on a set of characters, each
-- head drawn from its composed rectangles, as JSON for tools/fight-png.mjs - one frame per character,
-- the neutral face then the ten expressions left to right, full resolution above half.
--
--   lune run tools/render-faces <out.json> [avatar,avatar,...]
--
-- An avatar is a preset id (Classic...), a kit preset id (knight...) or a kit code.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Rbx = require("@lune/roblox")
local Loader = require("../tests/loader")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Compose = Loader.loadFrom("src/client/", "AvatarCompose")
local Expressions = Loader.loadFrom("src/client/", "Expressions")
local Loadout = Loader.load("Loadout")
local KIT = Loader.load("Data/AvatarKit")
local Recorder = require("./recorder")
local shapes = Recorder.install(Canvas)

local out = process.args[1]
local who = {}
for id in string.gmatch(process.args[2] or "Classic,Noir,Ember,Moss,Vapor,Steel", "[^,]+") do table.insert(who, id) end
local CELL, PAD = 9, 6
local W = 11 * (18 * CELL + PAD) + PAD
local H = 20 * CELL + 20 * CELL + 3 * PAD
local frames = {}
for _, id in who do
	local code = id
	for _, p in KIT.presets do if p.id == id then code = p.code end end
	local a = Loadout.avatarById(code)
	code = a.code or code
	table.clear(shapes)
	local c = Recorder.canvas(Canvas, W, H)
	Canvas.screen(c)
	Canvas.rect(c, 0, 0, W, H, Rbx.Color3.fromHex("#22303f"), 1)
	local neutral = Compose.sprites(code).head
	local list = { { full = neutral.full, half = neutral.half } }
	for _, e in Expressions.LIST do table.insert(list, Expressions.head(code, e)) end
	for i, h in list do
		local x0 = PAD + (i - 1) * (18 * CELL + PAD)
		local dim = h.sameFull and 0.35 or 1         -- an expression this face cannot show: faded
		-- sprites lay their rows downward in the world's y-up frame; this canvas is y-down
		local function at(y: number, fn: () -> ())
			Canvas.save(c); Canvas.translate(c, x0, y); Canvas.scale(c, 1, -1); fn(); Canvas.restore(c)
		end
		at(PAD, function() Canvas.sprite(c, "f" .. i, h.full, 0, 0, CELL, CELL, 18, 20, dim) end)
		-- half resolution: half the cells at twice the size, so the same head size
		at(2 * PAD + 20 * CELL, function() Canvas.sprite(c, "h" .. i, h.half, 0, 0, CELL * 2, CELL * 2, 9, 10, h.sameHalf and 0.35 or 1) end)
	end
	table.insert(frames, { frame = #frames, label = id, shapes = table.clone(shapes) })
end
fs.writeFile(out, serde.encode("json", { w = W, h = H, frames = frames }))
print(`{#frames} characters x 11 faces`)
