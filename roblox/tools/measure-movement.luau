--!nocheck
-- Six fighters on the real Canvas2D Frame fallback. Run unchanged against before/after sources:
-- lune run tools/measure-movement /tmp/charplan/movement-perf-after.json
-- Local Lune timings are comparative evidence, not a low-end Roblox device benchmark.
local fs, luau, Rbx, serde, process = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox"), require("@lune/serde"), require("@lune/process")
local Loader = require("../tests/loader")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Draw = Loader.loadFrom("src/client/", "Fighter2D")
local Kit, Loadout, Fighter, Snapshot = Loader.load("AvatarKit"), Loader.load("Loadout"), Loader.load("Fighter"), Loader.load("Snapshot")
local Real = luau.load(fs.readFile("src/client/Canvas2D.luau"), { debugName = "Canvas2D", environment = {
	Instance = Rbx.Instance, UDim2 = Rbx.UDim2, UDim = Rbx.UDim, Vector2 = Rbx.Vector2, Color3 = Rbx.Color3,
}, injectGlobals = true })()
for key, value in Real do Canvas[key] = value end
Canvas.IMAGES = false
local chars, snapshots = {}, {}
for _, parts in { { hair = "ponytail" }, { hair = "dreads" }, { neck = "scarf", hair = "ponytail", top = "trench" },
	{ neck = "summitMantle", hair = "ponytail", top = "trench" }, { top = "trench", hair = "ponytail" }, { top = "robe", hair = "ponytail" } } do
	local char = Loadout.build(Kit.encode(Kit.sanitize({ parts = parts })), "Sword")
	table.insert(chars, char)
end
-- Prebuild snapshots so the timing covers drawing and Canvas.finish, not test setup/encoding.
for frame = 1, 360 do
	snapshots[frame] = {}
	for i, char in chars do
		local f = Fighter.new({ index = i - 1, char = char, x = frame * char.runSpeed / 60, y = 0, stocks = 3 })
		f.state, f.sf, f.frameCount, f.invincible, f.onGround, f.vx = "run", frame, frame, 0, true, char.runSpeed
		snapshots[frame][i] = Snapshot.decode(Snapshot.encode(f))
	end
end
local result = {}
for _, scale in { 5, 26 } do
	local root = Rbx.Instance.new("Frame")
	local cv = Canvas.inFrame(root)
	local durations, rebuilt, children, slots, tails = {}, 0, 0, 0, 0
	-- First pass also warms the pre-existing blink/head pictures for each fighter index.
	for tick = 1, #snapshots * 2 do
		local frame = (tick - 1) % #snapshots + 1
		local states = snapshots[frame]
		local begin = os.clock()
		for i, s in states do
			Canvas.setTransform(cv, scale, 0, 0, -scale, i * 180 - s.x * scale, 200)
			Draw.draw(cv, s, chars[i], frame / 60)
		end
		if tick > #snapshots then rebuilt += cv.built end
		Canvas.finish(cv)
		if tick > #snapshots then table.insert(durations, (os.clock() - begin) * 1000) end
	end
	for key, sp in cv.sprites do
		children += #sp.children; slots += 1
		if string.find(key, "^secondary|") then tails += 1 end
	end
	table.sort(durations)
	table.insert(result, { scale = scale, fighters = #chars, measuredFrames = #durations,
		childFrames = children, instances = #root:GetDescendants(), spriteSlots = slots, tailSlots = tails,
		warmRebuiltRects = rebuilt, medianMs = durations[math.ceil(#durations * 0.5)], p95Ms = durations[math.ceil(#durations * 0.95)] })
	root:Destroy()
end
fs.writeFile(process.args[1], serde.encode("json", result))
print(serde.encode("json", result))
