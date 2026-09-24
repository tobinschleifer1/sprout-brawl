--!strict
-- Stage2D draws a grabbable-ledge marker exactly where the stage has a ledge, and nowhere else.
--
-- A ledge marker is a promise to the player. It used to be drawn at both ends of any solid whose
-- `ledges` was not false - and "outer" is not false - so every split floor (Smeltworks' islands,
-- Faultline's plates, Ashfall Summit's isles) showed markers at inner seams with nothing to grab.
local Loader = require("./loader")
local Stage = Loader.load("Stage")
local Stages = Loader.load("Data/Stages")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Stage2D = Loader.loadFrom("src/client/", "Stage2D")

local drawn: { any } = {}
Canvas.rect = function(_c: any, x: number, y: number, w: number, h: number, colour: any, alpha: number?)
	table.insert(drawn, { x = x, y = y, w = w, h = h, colour = colour })
end
local function canvas(): any
	return { m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 }, stack = {}, alpha = 1, alphaStack = {} }
end

local checked = 0
for _, data in Stages.LIST do
	local stage = Stage.new(data, 1)
	local accent = Canvas.hex(data.palette.accent, {} :: any)   -- every stage declares an accent
	table.clear(drawn)
	Stage2D.draw(canvas(), stage)
	local markers = {}
	for _, r in drawn do
		if r.colour == accent and math.abs(r.w - 0.7) < 1e-9 and math.abs(r.h - 2.0) < 1e-9 then
			table.insert(markers, r)
		end
	end
	assert(#markers == #stage.ledges, `{data.id}: {#markers} ledge markers for {#stage.ledges} real ledges`)
	for _, L in stage.ledges do
		local found = false
		for _, r in markers do
			local edge = if L.side < 0 then r.x else r.x + r.w
			if math.abs(edge - L.x) < 1e-9 and math.abs(r.y + r.h - L.platform.top) < 1e-9 then found = true end
		end
		assert(found, `{data.id}: no marker at the ledge at x={L.x}`)
	end
	checked += #markers
end
print(`PASS stage art: {checked} ledge markers across {#Stages.LIST} stages, one per real ledge and none elsewhere`)
