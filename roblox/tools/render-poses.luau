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

-- RENDER_SCALE=<px per stud> draws larger, for looking closely (the frame grows to match)
-- RENDER_HITBOXES=1 outlines, at contact, every hitbox live on that frame (red), so the art can be
-- judged against what the move actually hits
local SCALE = tonumber(process.env.RENDER_SCALE) or 26
local W, H = math.floor(260 * SCALE / 26), math.floor(220 * SCALE / 26)
local out, weapon = process.args[1], process.args[2]
local moves = {}
for id in string.gmatch(process.args[3] or "LightNeutral1,LightNeutral2,LightNeutral3,Finisher", "[^,]+") do table.insert(moves, id) end
local avatar = process.args[4] or "knight"
for _, p in KIT.presets do if p.id == avatar then avatar = p.code end end
local char = Loadout.build(avatar, weapon)
-- RENDER_WEAR=<skin id>[,<trail id>] dresses the fighter in a weapon skin (and a swing trail)
if process.env.RENDER_WEAR then
	local skin, trail = string.match(process.env.RENDER_WEAR, "^([^,]+),?(.*)$")
	char = table.clone(char)
	char.cosmetics = Loader.load("Inventory").cleanLoadout({ skins = { [weapon] = skin }, trail = if trail ~= "" then trail else nil })
end
Fighter2D.effects = nil

local frames = {}
local HITBOXES = process.env.RENDER_HITBOXES == "1"
local RED = Rbx.Color3.fromHex("#ff3b3b")
local function outline(c: any, f: any, m: any, abs: number)
	for _, hb in m.hitboxes or {} do
		if abs >= hb.frames[1] and abs <= hb.frames[2] then
			local w, h = hb.size[1], hb.size[2]
			local x1, y1, t = f.x + hb.offset[1] * f.facing - w / 2, f.y + hb.offset[2] - h / 2, 0.07
			Canvas.rect(c, x1, y1, w, t, RED, 0.95); Canvas.rect(c, x1, y1 + h - t, w, t, RED, 0.95)
			Canvas.rect(c, x1, y1, t, h, RED, 0.95); Canvas.rect(c, x1 + w - t, y1, t, h, RED, 0.95)
		end
	end
end
local function draw(f: any, label: string, m: any?, abs: number?)
	table.clear(shapes)
	local c = Recorder.canvas(Canvas, W, H)
	Canvas.screen(c)
	Canvas.rect(c, 0, 0, W, H, Rbx.Color3.fromHex("#22303f"), 1)
	Canvas.world(c, 1.5, 3.2, SCALE, 0, 0)
	Canvas.rect(c, -6, -1, 14, 1, Rbx.Color3.fromHex("#4a5a46"), 1)     -- the floor
	local s = Snapshot.decode(Snapshot.encode(f))
	Fighter2D.draw(c, s, char, 0, 0)
	if HITBOXES and m and abs then outline(c, f, m, abs) end
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
		draw(f, `{id} {at}`, m, if at == "contact" then m.startup + math.max(1, math.ceil(m.active / 2)) else nil)
	end
end
fs.writeFile(out, serde.encode("json", { w = W, h = H, frames = frames }))
print(`{#frames} poses of {weapon}`)
