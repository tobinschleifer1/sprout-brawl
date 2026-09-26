--!strict
-- StageThumb.luau draws every map-select thumbnail exactly as web/src/render2d/stageThumb.js does,
-- at four tile sizes, and the Random tile too. Then what parity cannot vouch for: every rectangle
-- inside the tile, the sky covering the whole tile, and the stage framed rather than a sliver - its
-- main floor at least a third of the tile wide.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")
local Thumb = Loader.loadFrom("src/client/", "StageThumb")
local Stages = Loader.load("Data/Stages")
local T = serde.decode("json", fs.readFile("tests/stage-thumb-fixture.json"))

local byId = {}
for _, s in Stages.LIST do byId[s.id] = s end
local checked = 0
local function compare(got: { any }, want: { any }, where: string)
	assert(#got == #want, `{where}: {#got} rectangles, JS drew {#want}`)
	for i, sh in got do
		for j = 1, 7 do
			local g, w = sh[j], want[i][j]
			local ok = if type(g) == "number" then math.abs(g - (tonumber(w) :: number)) < 1e-9 else g == w
			assert(ok, `{where} rect {i} field {j}: JS {w}, Luau {tostring(g)}`)
			checked += 1
		end
	end
end
for _, st in T.stages do
	local stage = assert(byId[st.id], `no stage {st.id}`)
	for k, size in T.sizes do
		local w, h = size[1], size[2]
		local got = Thumb.shapes(stage, w, h)
		compare(got, st.sizes[k], `{st.id} @{w}x{h}`)
		local skyTop, skyBottom = math.huge, -math.huge
		for _, sh in got do
			assert(sh[2] >= 0 and sh[3] >= 0 and sh[2] + sh[4] <= w + 1 and sh[3] + sh[5] <= h + 1, `{st.id} @{w}x{h}: a rectangle leaves the tile`)
		end
		-- the sky bands are drawn first, full width
		local i = 1
		while got[i] and got[i][2] == 0 and got[i][4] == w do
			skyTop, skyBottom = math.min(skyTop, got[i][3]), math.max(skyBottom, got[i][3] + got[i][5])
			i += 1
		end
		assert(skyTop <= 0 and skyBottom >= h - 1, `{st.id} @{w}x{h}: the sky leaves a gap ({skyTop}..{skyBottom})`)
		local x0, x1 = Thumb.extent(stage)
		local floorW = (stage.main.x2 - stage.main.x1) / (x1 - x0) * w
		assert(floorW >= w / 3 or (stage.main.x2 - stage.main.x1) < 25, `{st.id}: the floor is {floorW}px of a {w}px tile`)
	end
end
for k, size in T.sizes do
	compare(Thumb.random(size[1], size[2]), T.random[k], `random @{size[1]}x{size[2]}`)
end
print(`stage thumbnails: {checked} values across {#T.stages} stages x {#T.sizes} sizes, and the Random tile, match the web`)
