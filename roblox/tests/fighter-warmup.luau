--!nocheck
-- Real Frame output and creation counts: identical skins/weapons must warm distinct slots.
local Probe = require("../tools/perf-probe")
local Output = require("../tools/perf-output")
local serde = require("@lune/serde")
local function scene(scale, warm)
	local P = Probe.new(960, 540)
	local Canvas, Draw = P:load("src/client/Canvas2D"), P:load("src/client/Fighter2D")
	local Warm = P:load("src/client/FighterWarmup")
	local Loadout, Fighter, Snapshot = P:load("src/shared/Loadout"), P:load("src/shared/Fighter"), P:load("src/shared/Snapshot")
	Canvas.IMAGES = false
	local cv = Canvas.new(P.new("Folder"))
	local chars, states = {}, {}
	for i = 1, 6 do
		chars[i] = Loadout.build("Classic", "RocketBoots")
		local f = Fighter.new({ index = i - 1, char = chars[i], x = 0, y = 0, stocks = 1 })
		f.state, f.invincible, f.onGround = "idle", 0, true
		states[i] = Snapshot.decode(Snapshot.encode(f))
	end
	if warm then
		P:reset()
		local queue = Warm.new(cv, chars, scale)
		assert(P.total.creates == 0 and cv.used == 0 and cv.z == 0, "collecting warmup allocated or advanced the canvas")
		local done, ticks = false, 0
		repeat
			P:reset()
			done = Warm.step(cv, queue)
			ticks += 1
			assert(P.total.creates <= Warm.BUDGET, "fighter warmup exceeded batch budget")
			assert(ticks < 100, "fighter warmup stalled")
			for _, sp in cv.sprites do assert(not sp.frame.Visible and not sp.vis, "warm sprites became visible during countdown") end
		until done
		assert(cv.sprites["weapon|RocketBoots#12"], "duplicate boots lost their warm slots")
		assert(cv.used == 0 and cv.z == 0 and next(cv.spriteUse) == nil, "warmup advanced live draw counters")
	end
	P:reset()
	Draw.startStocks = 3 -- a warm neutral face must not delay the first real determined face
	for i, st in states do
		Canvas.setTransform(cv, scale, 0, 0, -scale, i * 140 - 20, 300)
		Draw.draw(cv, st, chars[i], 0)
	end
	Canvas.finish(cv)
	return { output = serde.encode("json", Output.tree(P.raw[cv.layer])), creates = P.total.creates }
end
for _, scale in { 5, 26 } do
	local cold, warm = scene(scale, false), scene(scale, true)
	assert(warm.output == cold.output, "countdown changes the first visible fighter output")
	assert(warm.creates < cold.creates * 0.2, `countdown failed to reuse fighter slots: {warm.creates} vs {cold.creates}`)
end
print("PASS fighter warmup: bounded hidden batches, duplicate bodies/boots, isolated expression holds, identical first visible Frames at both LODs")
