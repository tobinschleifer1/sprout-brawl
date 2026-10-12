--!nocheck
-- cd roblox && lune run tools/perf-match [report.json] [frames=360] [warmup=120] [picture-prefix|-] [native|-] [git-ref]
-- Counts engine-bound assignments and REAL Instance creation/destruction, not draw calls.
-- Times are Lune wall-clock script times including the instrumented Instance boundary, NOT
-- device FPS/GPU/layout cost. The first render and warmup are reported separately, never hidden.
local fs, serde, process = require("@lune/fs"), require("@lune/serde"), require("@lune/process")
local Scene = require("./perf-scene")
local Output = require("./perf-output")
local frames, warmup = tonumber(process.args[2]) or 360, tonumber(process.args[3]) or 120
local native = process.args[5] == "native"
local capture = process.args[4] and process.args[4] ~= "-"
assert(not (native and capture), "output capture needs the counting probe")
local scene = Scene.new(native, process.args[6])
local P = scene.probe
local function sample(frame)
	scene:prepare(frame)
	P:reset()
	local began = os.clock()
	scene:draw(frame)
	local elapsed = (os.clock() - began) * 1000
	local accounted = 0
	for _, group in P.groups do accounted += group.ms end
	local other = P.groups["Effects/other"] or { writes = 0, creates = 0, destroys = 0, ms = 0, properties = {} }
	P.groups["Effects/other"] = other
	other.ms += elapsed - accounted
	return { frame = frame, writes = P.total.writes, creates = P.total.creates, destroys = P.total.destroys,
		liveFrames = P:frames(), ms = elapsed, properties = P.total.properties, groups = P.groups }
end
local startup = sample(1)
local warming = { writes = 0, creates = 0, destroys = 0, peakWrites = 0, peakCreates = 0 }
for f = 2, warmup do
	local s = sample(f)
	for _, k in { "writes", "creates", "destroys" } do warming[k] += s[k] end
	warming.peakWrites, warming.peakCreates = math.max(warming.peakWrites, s.writes), math.max(warming.peakCreates, s.creates)
end
local pictures, hashes = {}, {}
local samples, groups, totals, peaks = {}, {}, { writes = 0, creates = 0, destroys = 0, ms = 0 }, { writes = 0, creates = 0, destroys = 0, liveFrames = 0, ms = 0 }
for i = 1, frames do
	local s = sample(warmup + i)
	if capture then
		hashes[i] = Output.hash(scene)
		if i == 1 or i == 31 or i == 61 or i == 91 then
			table.insert(pictures, { frame = warmup + i, shapes = Output.shapes(scene) })
		end
	end
	samples[i] = s
	for k in totals do totals[k] += s[k] end
	for k in peaks do peaks[k] = math.max(peaks[k], s[k]) end
	for name, g in s.groups do
		local sum = groups[name] or { writes = 0, creates = 0, destroys = 0, ms = 0, properties = {} }
		groups[name] = sum
		for _, k in { "writes", "creates", "destroys", "ms" } do sum[k] += g[k] end
		for k, value in g.properties do sum.properties[k] = (sum.properties[k] or 0) + value end
	end
end
local owners = P:frameOwners()
-- Include retained setup widgets even though setup contributes no steady-frame assignments.
for name in owners do
	if not groups[name] then groups[name] = { writes = 0, creates = 0, destroys = 0, ms = 0, properties = {} } end
end
local names = {} for name in groups do table.insert(names, name) end table.sort(names)
print(`Frame fallback; {#scene.state.states} fighters; {frames} frames after {warmup} warmup; {Scene.W}x{Scene.H}`)
if native then print("Native Instances: timings only (write/create counters disabled)") end
print("Section             Writes/f Creates/f Destroys/f  Lune ms/f Live Frames")
for _, name in names do local g = groups[name]
	print(string.format("%-19s %8.1f %9.2f %10.2f %10.3f %11d", name, g.writes/frames, g.creates/frames, g.destroys/frames, g.ms/frames, owners[name] or 0))
end
print(string.format("TOTAL               %8.1f %9.2f %10.2f %10.3f", totals.writes/frames, totals.creates/frames, totals.destroys/frames, totals.ms/frames))
print(`Peak: {peaks.writes} writes, {peaks.creates} creates, {peaks.destroys} destroys, {peaks.liveFrames} live Frames`)
print(`First render: {startup.writes} writes, {startup.creates} creates, {startup.destroys} destroys, {startup.liveFrames} live Frames`)
print(`Warmup after first render: {warming.creates} creates, {warming.destroys} destroys ({warming.peakCreates} creates/f peak)`)
if process.args[1] then fs.writeFile(process.args[1], serde.encode("json", { frames = frames, warmup = warmup, startup = startup,
	setup = scene.setup, warming = warming, sourceRef = process.args[6] or "working tree", native = native,
	totals = totals, peaks = peaks, groups = groups, frameOwners = owners, samples = samples })) end
if capture then
	fs.writeFile(process.args[4] .. "-draw.json", serde.encode("json", { w = Scene.W, h = Scene.H, frames = pictures }))
	fs.writeFile(process.args[4] .. "-hashes.json", serde.encode("json", hashes))
end
