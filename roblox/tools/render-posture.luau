--!nocheck
-- Idle/stride/landing contact sheet through the shipping renderer. Optional LOD and facing:
-- lune run tools/render-posture /tmp/charplan/rest.json Classic 26 1
-- node tools/fight-png.mjs /tmp/charplan/rest.json /tmp/charplan/rest.png 3 2
local fs, process, serde = require("@lune/fs"), require("@lune/process"), require("@lune/serde")
local Loader = require("../tests/loader")
local Fighter, Loadout, Snapshot = Loader.load("Fighter"), Loader.load("Loadout"), Loader.load("Snapshot")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Fighter2D = Loader.loadFrom("src/client/", "Fighter2D")
local Recorder = require("./recorder")
local Rbx = require("@lune/roblox")
local shapes = Recorder.install(Canvas)
local W, H, scale = 260, 220, tonumber(process.args[3]) or 26
local avatar = process.args[2] or "Classic"
for _, preset in Loader.load("Data/AvatarKit").presets do
	if preset.id == avatar then avatar = preset.code; break end
end
local char = Loadout.build(avatar, "Sword")
local frames = {}
for _, pose in { { "idle", 0 }, { "idle", 0.7 }, { "idle", 1.4 }, { "run", 3 }, { "run", 8 }, { "run", 14 },
	{ "jumpsquat", 3 }, { "landing", 1 }, { "landing", 7 } } do
	local f = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
	f.state, f.sf, f.onGround, f.facing = pose[1], pose[2], true, tonumber(process.args[4]) or 1
	f.invul = 0
	f.frameCount = if pose[1] == "run" then pose[2] else 0
	f.vx = if pose[1] == "run" then char.runSpeed else 0
	local c = Recorder.canvas(Canvas, W, H)
	table.clear(shapes)
	Canvas.screen(c)
	Canvas.rect(c, 0, 0, W, H, Rbx.Color3.fromHex("#22303f"), 1)
	Canvas.world(c, 1 * f.facing, 3.2, scale, 0, 0)
	Canvas.rect(c, -20, -1, 40, 1, Rbx.Color3.fromHex("#4a5a46"), 1)
	Fighter2D.draw(c, Snapshot.decode(Snapshot.encode(f)), char, if pose[1] == "idle" then pose[2] else pose[2] / 60, 0)
	table.insert(frames, { frame = #frames, label = `{pose[1]} {pose[2]}`, shapes = table.clone(shapes) })
end
fs.writeFile(process.args[1], serde.encode("json", { w = W, h = H, frames = frames }))
print(`{#frames} posture samples of {char.avatar.id}`)
