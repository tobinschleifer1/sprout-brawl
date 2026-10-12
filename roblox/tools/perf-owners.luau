--!nocheck
-- cd roblox && lune run tools/perf-owners [frames=240]
-- Where the live Frames are, by sprite-key family: slots (container Frames), their child Frames,
-- and the plain pool. Run after the same scene tools/perf-match draws.
local process = require("@lune/process")
local Scene = require("./perf-scene")
local frames = tonumber(process.args[1]) or 240
local scene = Scene.new()
local P = scene.probe
for f = 1, frames do scene:prepare(f); P:reset(); scene:draw(f) end
local fam = {}
local function add(name, slots, kids)
	local e = fam[name] or { slots = 0, kids = 0 }
	e.slots += slots; e.kids += kids; fam[name] = e
end
for slot, sp in scene.canvas.sprites do
	local key = string.match(slot, "^(.-)#%d+$") or slot
	local name = string.match(key, "^(%a+)") or key
	if name == "fx" then name = "fx|" .. (string.match(key, "^fx|([^|]+)") or "?") end
	add(name, 1, #sp.children)
end
if process.args[2] then
	for slot, sp in scene.canvas.sprites do
		if string.find(slot, process.args[2], 1, true) then print(slot, #sp.children, sp.vis, sp.rows, sp.cols) end
	end
end
add("pool(rect/ellipse)", #scene.canvas.pool, 0)
local rows = {}
for name, e in fam do table.insert(rows, { name, e }) end
table.sort(rows, function(a, b) return a[2].slots + a[2].kids > b[2].slots + b[2].kids end)
local total = 0
print(string.format("%-24s %7s %7s %7s", "family", "slots", "kids", "frames"))
for _, r in rows do
	local n = r[2].slots + r[2].kids; total += n
	print(string.format("%-24s %7d %7d %7d", r[1], r[2].slots, r[2].kids, n))
end
print("total", total, "probe live", P:frames())
