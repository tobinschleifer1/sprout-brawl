--!nocheck
-- cd roblox && lune run tools/perf-raster [out.json] [git-ref]
-- "Drawn unchanged", proved on pixels. perf-match's ordered GUI hash cannot compare two ways of cutting
-- the same picture into rectangles (fewer rectangles ARE a different GUI), so this flattens the real
-- Frames after a draw (tools/perf-output shapes: hierarchy, rotation, anchors, alpha), rasterises them
-- source-over at 960x540 and hashes the pixels. Sample points sit off pixel centres by an irrational
-- amount so two cuts of one edge cannot disagree on a tie. Run it against a ref and the working tree
-- and compare the files: equal means every sampled pixel is equal.
local fs, serde, process = require("@lune/fs"), require("@lune/serde"), require("@lune/process")
local Scene = require("./perf-scene")
local Output = require("./perf-output")
local FRAMES = { 1, 121, 150, 181, 212, 270, 331, 392, 450, 480 }
local W, H = Scene.W, Scene.H
local scene = Scene.new(false, process.args[2])
if not process.args[2] then scene:countdown() end
local function hexRGB(h) return tonumber(string.sub(h, 2, 3), 16), tonumber(string.sub(h, 4, 5), 16), tonumber(string.sub(h, 6, 7), 16) end
local OX, OY = 0.3719, 0.4143
local function raster(shapes)
	local R, G, B = table.create(W * H, 0), table.create(W * H, 0), table.create(W * H, 0)
	for _, s in shapes do
		local r, g, b = hexRGB(s[#s - 1])
		local a = s[#s]
		if s[1] == "p" then
			local p = { s[2], s[3], s[4], s[5] }
			local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
			for _, q in p do x0, y0, x1, y1 = math.min(x0, q[1]), math.min(y0, q[2]), math.max(x1, q[1]), math.max(y1, q[2]) end
			for y = math.max(0, math.floor(y0 - 1)), math.min(H - 1, math.ceil(y1)) do
				for x = math.max(0, math.floor(x0 - 1)), math.min(W - 1, math.ceil(x1)) do
					local px, py = x + OX, y + OY
					local pos, neg = false, false
					for i = 1, 4 do
						local u, v = p[i], p[i % 4 + 1]
						local cross = (v[1] - u[1]) * (py - u[2]) - (v[2] - u[2]) * (px - u[1])
						if cross > 0 then pos = true elseif cross < 0 then neg = true end
					end
					if not (pos and neg) then
						local k = y * W + x + 1
						R[k], G[k], B[k] = R[k] * (1 - a) + r * a, G[k] * (1 - a) + g * a, B[k] * (1 - a) + b * a
					end
				end
			end
		else
			local cx, cy, rx, ry = s[2], s[3], s[4], s[5]
			for y = math.max(0, math.floor(cy - ry)), math.min(H - 1, math.ceil(cy + ry)) do
				for x = math.max(0, math.floor(cx - rx)), math.min(W - 1, math.ceil(cx + rx)) do
					local dx, dy = (x + OX - cx) / rx, (y + OY - cy) / ry
					if dx * dx + dy * dy <= 1 then
						local k = y * W + x + 1
						R[k], G[k], B[k] = R[k] * (1 - a) + r * a, G[k] * (1 - a) + g * a, B[k] * (1 - a) + b * a
					end
				end
			end
		end
	end
	return R, G, B
end
local out, want = {}, {}
for _, f in FRAMES do want[f] = true end
for f = 1, FRAMES[#FRAMES] do
	scene:prepare(f)
	scene.probe:reset()
	scene:draw(f)
	if want[f] then
		local shapes = Output.shapes(scene)
		local R, G, B = raster(shapes)
		local bytes = {}
		for k = 1, W * H do bytes[k] = string.char(math.floor(R[k] + 0.5), math.floor(G[k] + 0.5), math.floor(B[k] + 0.5)) end
		out[tostring(f)] = { hash = serde.hash("sha256", table.concat(bytes)), shapes = #shapes }
		print(f, out[tostring(f)].hash, #shapes .. " shapes")
		if process.args[1] and process.args[1] ~= "-" then
			fs.writeFile(process.args[1] .. "." .. f .. ".ppm", `P6\n{W} {H}\n255\n` .. table.concat(bytes))
		end
	end
end
if process.args[1] and process.args[1] ~= "-" then fs.writeFile(process.args[1], serde.encode("json", out)) end
