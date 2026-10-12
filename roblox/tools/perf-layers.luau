--!nocheck
-- cd roblox && lune run tools/perf-layers : rectangles per effect kind, plain partition vs layered
local Probe = require("./perf-probe")
local P = Probe.new(960, 540)
local FxArt, PG = P:load("src/client/FxArt"), P:load("src/client/PixelGrid")
local all = { 0, 0 }
for _, kind in FxArt.kinds() do
	local a, b = 0, 0
	for f = 0, (FxArt.FRAMES[kind] or 1) - 1 do
		local g = FxArt.paint(kind, f, 1)
		a += #PG.merge(g); b += #PG.layers(g, function(v) return v <= 10 end)
	end
	all[1] += a; all[2] += b
	print(string.format("%-9s %5d -> %5d  (%3d%%)", kind, a, b, b * 100 / a))
end
print(string.format("%-9s %5d -> %5d  (%3d%%)", "all", all[1], all[2], all[2] * 100 / all[1]))
