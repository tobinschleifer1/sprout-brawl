--!nocheck
-- The same six-fighter Frame-fallback scene as tools/perf-match, with a small deterministic
-- regression margin. No wall-clock assertions: host load is not a rendering regression.
local Scene = require("../tools/perf-scene")
local Probe = require("../tools/perf-probe")
-- Calibrate the measuring boundary itself: equal assignments must count, and destroying a
-- container must include its children. These are real @lune/roblox Instances behind the proxies.
do
	local probe = Probe.new(10, 10)
	local parent, child = probe.new("Frame"), probe.new("Frame")
	child.Parent = parent
	parent.Visible = false
	parent.Visible = false
	assert(probe.total.creates == 2 and probe.total.writes == 3 and probe.total.properties.Visible == 2,
		"probe stopped counting equal assignments/real creations")
	assert(#probe.raw[parent]:GetChildren() == 1 and probe.raw[parent].Visible == false, "probe stopped forwarding to real Instances")
	parent:Destroy()
	assert(probe.total.destroys == 2 and probe:frames() == 0, "probe missed recursive destruction")
end
local scene = Scene.new()
local P = scene.probe
assert(scene.Canvas.IMAGES == false and #scene.state.states == 6, "budget must exercise six fighters on Frames")
local totals = { writes = 0, creates = 0, destroys = 0 }
local peaks = { writes = 0, creates = 0, destroys = 0, liveFrames = 0 }
local warmCreates, warmPeak = 0, 0
for frame = 1, 480 do
	scene:prepare(frame)
	P:reset()
	scene:draw(frame)
	if frame == 1 then
		assert(P.total.writes <= 22200 and P.total.creates <= 3070, "cold draw exceeded its build budget")
	end
	if frame <= 120 then
		if frame > 1 then
			warmCreates += P.total.creates
			warmPeak = math.max(warmPeak, P.total.creates)
		end
		continue
	end
	for key in totals do
		totals[key] += P.total[key]
		peaks[key] = math.max(peaks[key], P.total[key])
	end
	peaks.liveFrames = math.max(peaks.liveFrames, P:frames())
end
-- Measured on tools/perf-scene (6 shipping weapons incl. Chakram and Rocket Boots): feature/character-rig
-- before the perf pass 956.9 writes/f (4682 peak); after 592.7 (2926 peak), 4 created across 360
-- frames, 0 destroyed, 11870 live Frames. ~4% headroom; no timing assertion on a shared host.
assert(warmCreates <= 9360 and warmPeak <= 612, `warmup built {warmCreates} Instances ({warmPeak} peak)`)
assert(totals.writes / 360 <= 620, `mean writes {totals.writes / 360} > 620`)
assert(peaks.writes <= 3050, `peak writes {peaks.writes} > 3050`)
assert(totals.creates <= 6 and peaks.creates <= 4, `steady creates {totals.creates} ({peaks.creates} peak)`)
assert(totals.destroys == 0, `steady draw destroyed {totals.destroys} Instances`)
assert(peaks.liveFrames <= 12410, `live Frames {peaks.liveFrames} > 12410`)
print(string.format("PASS match budget: %.1f writes/f (%d peak), %d creates, %d destroys, %d live Frames",
	totals.writes / 360, peaks.writes, totals.creates, totals.destroys, peaks.liveFrames))
