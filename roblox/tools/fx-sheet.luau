--!nocheck
-- Development tool: every FxArt drawing, every frame, in one or more ramps, as JSON for
-- tools/fx-sheet.mjs to paint into a PNG.
--   lune run tools/fx-sheet <out.json> [ramp ...]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Loader = require("../tests/loader")
local FxArt = Loader.loadFrom("src/client/", "FxArt")
local ramps = {}
for i = 2, #process.args do table.insert(ramps, process.args[i]) end
if #ramps == 0 then ramps = { "#9FE8FF" } end
local rows = {}
for _, kind in FxArt.kinds() do
	for _, ramp in ramps do
		local row = { kind = kind, ramp = ramp, frames = {} }
		for f = 0, FxArt.FRAMES[kind] - 1 do
			local art = FxArt.get(kind, f, ramp, nil, 3)
			table.insert(row.frames, { cols = art.cols, rows = art.rows, rects = art.rects, ax = art.ax, ay = art.ay })
		end
		table.insert(rows, row)
	end
end
fs.writeFile(process.args[1], serde.encode("json", rows))
print(`{#rows} rows`)
