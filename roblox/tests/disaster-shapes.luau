--!strict
-- Does Roblox draw a disaster exactly as the web does?
--
--   lune run tests/disaster-shapes
--
-- Replays tests/trace-disaster-shapes.json (tools/gen-disaster-traces.mjs): a thousand real disaster
-- views, each with the shape list and banner web/src/render2d/disasterShapes.js produced for it.
-- DisasterShapes.luau must produce the same list - same kinds, same order, same numbers, same colours.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Loader = require("./loader")

local Stage = Loader.load("Stage")
local StageData = Loader.load("Data/Stages")
local Shapes = Loader.loadFrom("src/client/", "DisasterShapes")

local T = serde.decode("json", fs.readFile("tests/trace-disaster-shapes.json"))

-- Numbers travel as strings (Lune's JSON keeps ~16 digits); turn them back into numbers.
local function revive(v: any): any
	if type(v) == "string" then
		local n = tonumber(v)
		return if n ~= nil then n else v
	elseif type(v) == "table" then
		local out = {}
		for k, x in v do out[k] = revive(x) end
		return out
	end
	return v
end
local EPS = 1e-12
local function same(a: any, b: any): boolean
	if type(a) == "number" and type(b) == "number" then
		local d = math.abs(a - b)
		return d <= EPS or d <= EPS * math.max(math.abs(a), math.abs(b))
	end
	return a == b
end

local failures, checked = {}, 0
local stages: { [string]: any } = {}
for i, sample in T.samples do
	local key = `{sample.stage}:{sample.seed}`
	stages[key] = stages[key] or Stage.new(StageData.BY_ID[sample.stage], tonumber(sample.seed))
	local view, want = revive(sample.view), revive(sample.shapes)
	local got = Shapes.shapes(view, stages[key])
	if #got ~= #want then
		table.insert(failures, `sample {i} ({view.type} {view.phase} f{view.frame}): {#got} shapes, JS drew {#want}`)
	else
		for j, w in want do
			for f = 1, 7 do
				if not same(w[f], got[j][f]) then
					table.insert(failures, `sample {i} ({view.type}) shape {j} field {f}: JS {tostring(w[f])}, Luau {tostring(got[j][f])}`)
				end
				checked += 1
			end
		end
	end
	local wb, gb = revive(sample.banner), Shapes.banner(view)
	if (wb == nil) ~= (gb == nil) or (wb and (wb.text ~= gb.text or wb.colour ~= gb.colour or wb.seconds ~= gb.seconds)) then
		table.insert(failures, `sample {i} ({view.type}): banner differs`)
	end
	checked += 1
	if #failures >= 10 then break end
end
if #failures > 0 then
	print("FAIL disaster shapes:")
	for _, f in failures do print("  " .. f) end
	process.exit(1)
end
print(`replayed {checked} shape values across {#T.samples} disaster views`)
print("DisasterShapes.luau draws what web/src/render2d/disasterShapes.js draws.")
