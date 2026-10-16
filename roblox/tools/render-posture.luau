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
if process.args[5] == "cycle" then W, H = 300, 420 end
local avatar = process.args[2] or "Classic"
for _, preset in Loader.load("Data/AvatarKit").presets do
	if preset.id == avatar then avatar = preset.code; break end
end
local char = Loadout.build(avatar, "Sword")
local chars = {}
local frames = {}
local poses = { { "idle", 0 }, { "idle", 0.7 }, { "idle", 1.4 }, { "run", 3 }, { "run", 8 }, { "run", 14 },
	{ "jumpsquat", 3 }, { "landing", 1 }, { "landing", 7 } }
-- Optional fifth argument: phase-four contact sheets, identical inputs before/after a change.
local sheet = process.args[5]
if sheet == "gait" then
	poses = {}
	for _, speed in { 0.28, 1 } do
		for _, frame in { 0, 2, 4, 6, 8, 10, 12, 14 } do table.insert(poses, { "run", frame, vx = char.runSpeed * speed }) end
	end
elseif sheet == "cycle" then
	-- one full stride (two steps) in eight even slices of distance, at a run and at a walk
	poses = {}
	local S = char.height * 0.58 -- Movement.gait(char).step
	for _, speed in { 1, 0.28 } do
		for j = 0, 7 do
			local vx = char.runSpeed * speed
			table.insert(poses, { "run", 2 * S * j / 8 * 60 / vx, vx = vx })
		end
	end
elseif sheet == "jump" then
	poses = { { "jumpsquat", 0 }, { "jumpsquat", 3 }, { "air", 3, vy = 32 }, { "air", 9, vy = 14 },
		{ "air", 14, vy = 0 }, { "air", 19, vy = -18 }, { "air", 22, vy = -55, fastFalling = true },
		{ "landing", 0 }, { "landing", 2 }, { "landing", 4 }, { "landing", 7 }, { "idle", 0 } }
elseif sheet == "reaction" then
	poses = { { "shield", 4 }, { "spotdodge", 5 }, { "airdodge", 4 }, { "hitstun", 2, vx = 25 },
		{ "hitstun", 2, vx = -25 }, { "hitstun", 5, tumbling = true }, { "hitstun", 9, tumbling = true },
		{ "knockdown", 3 }, { "knockdown", 16 }, { "knockdown", 23 }, { "tech", 4 }, { "tech", 4, techRoll = 1 } }
elseif sheet == "ledge" then
	poses = { { "ledge", 2 }, { "ledge", 12 }, { "ledgeaction", 3, ledgeAction = "getup" },
		{ "ledgeaction", 15, ledgeAction = "getup" }, { "ledgeaction", 3, ledgeAction = "attack" },
		{ "ledgeaction", 10, ledgeAction = "attack" }, { "ledgeaction", 4, ledgeAction = "roll" },
		{ "air", 5, vy = 32 } } -- a ledge jump enters air directly; there is no ledgeaction/jump
elseif sheet == "secondary" then
	poses = {}
	local Kit = Loader.load("AvatarKit")
	for _, parts in { { hair = "ponytail" }, { hair = "dreads" }, { neck = "scarf" },
		{ neck = "summitMantle" }, { top = "trench" } } do
		local code = Kit.encode(Kit.sanitize({ parts = parts }))
		for _, v in { { "idle", 0 }, { "run", 4 }, { "run", 12 }, { "idle", 23, sf = 1 } } do
			v.avatar = code
			table.insert(poses, v)
		end
	end
end
local airborne = { air = true, airdodge = true, hitstun = true, ledge = true, ledgeaction = true }
for _, pose in poses do
	if pose.avatar then
		chars[pose.avatar] = chars[pose.avatar] or Loadout.build(pose.avatar, "Sword")
		char = chars[pose.avatar]
	end
	local f = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
	f.state, f.sf, f.onGround, f.facing = pose[1], pose[2], not airborne[pose[1]], tonumber(process.args[4]) or 1
	f.invincible = 0
	f.frameCount = if pose[1] == "idle" and not pose.avatar then 0 else pose[2]
	f.vx = if pose[1] == "run" then char.runSpeed else 0
	for key, value in pose do if type(key) == "string" and key ~= "ledgeAction" and key ~= "avatar" then f[key] = value end end
	if pose.ledgeAction then f.la = { kind = pose.ledgeAction } end
	if pose[1] == "run" then f.vx *= f.facing; f.x = pose[2] * f.vx / 60 end
	local c = Recorder.canvas(Canvas, W, H)
	table.clear(shapes)
	Canvas.screen(c)
	Canvas.rect(c, 0, 0, W, H, Rbx.Color3.fromHex("#22303f"), 1)
	Canvas.world(c, f.x + (if sheet == "cycle" then 0.3 else 1) * f.facing, if sheet == "cycle" then 3.0 else 3.2, scale, 0, 0)
	Canvas.rect(c, -20, -1, 40, 1, Rbx.Color3.fromHex("#4a5a46"), 1)
	Fighter2D.draw(c, Snapshot.decode(Snapshot.encode(f)), char, if pose[1] == "idle" then pose[2] else pose[2] / 60, 0)
	table.insert(frames, { frame = #frames, label = `{pose[1]} {pose[2]}`, shapes = table.clone(shapes) })
end
fs.writeFile(process.args[1], serde.encode("json", { w = W, h = H, frames = frames }))
print(`{#frames} posture samples of {char.avatar.id}`)
