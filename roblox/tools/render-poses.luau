--!nocheck
-- Development tool, not a test: one fighter posed at chosen moments of chosen moves, drawn through
-- the SHIPPING fighter renderer (Fighter2D, Weapons2D), as JSON for tools/fight-png.mjs. For looking
-- at animation - a combo string's links side by side - without playing a match to reach them.
--
--   lune run tools/render-poses <out.json> <weapon> <moves,comma,separated> [avatar]
--
-- Each move is drawn three times: cocked (the last startup frame), at contact (mid active) and in
-- the follow-through (40% into recovery). A move name of `breakout` draws the combo break's state
-- at frames 1, 6 and 16 instead. Air moves are drawn off the ground.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Loader = require("../tests/loader")
local Fighter = Loader.load("Fighter")
local Loadout = Loader.load("Loadout")
local Snapshot = Loader.load("Snapshot")
local KIT = Loader.load("Data/AvatarKit")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Fighter2D = Loader.loadFrom("src/client/", "Fighter2D")
local Recorder = require("./recorder")
local Rbx = require("@lune/roblox")
local shapes = Recorder.install(Canvas)

local W, H = 260, 220
local out, weapon = process.args[1], process.args[2]
local moves = {}
for id in string.gmatch(process.args[3] or "LightNeutral1,LightNeutral2,LightNeutral3,Finisher", "[^,]+") do table.insert(moves, id) end
local avatar = process.args[4] or "knight"
for _, p in KIT.presets do if p.id == avatar then avatar = p.code end end
local char = Loadout.build(avatar, weapon)
Fighter2D.effects = nil

local frames = {}
local function draw(f: any, label: string)
	table.clear(shapes)
	local c = Recorder.canvas(Canvas, W, H)
	Canvas.screen(c)
	Canvas.rect(c, 0, 0, W, H, Rbx.Color3.fromHex("#22303f"), 1)
	Canvas.world(c, 1.5, 3.2, 26, 0, 0)
	Canvas.rect(c, -6, -1, 14, 1, Rbx.Color3.fromHex("#4a5a46"), 1)     -- the floor
	local s = Snapshot.decode(Snapshot.encode(f))
	Fighter2D.draw(c, s, char, 0, 0)
	table.insert(frames, { frame = #frames, label = label, shapes = table.clone(shapes) })
end

for _, id in moves do
	local f = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
	f.facing = 1
	if id == "breakout" then
		for _, sf in { 1, 6, 16 } do
			f.onGround = true
			f:setState("breakout"); f.sf = sf
			draw(f, `breakout {sf}`)
		end
		continue
	end
	local m = char.moves[id]
	if not m then error(`{weapon} has no {id}`) end
	local air = m.grounded == false
	for _, at in { "cocked", "contact", "follow" } do
		f.onGround = not air
		f.y = if air then 2.5 else 0
		f:setState(if air then "air" else "idle")
		f:startMove(id)
		local mm = f.move
		f.mf = if at == "cocked" then f.startupEff
			elseif at == "contact" then f.startupEff + math.max(1, math.ceil(mm.active / 2))
			else f.startupEff + mm.active + math.floor(mm.recovery * 0.4)
		draw(f, `{id} {at}`)
	end
end
fs.writeFile(out, serde.encode("json", { w = W, h = H, frames = frames }))
print(`{#frames} poses of {weapon}`)
