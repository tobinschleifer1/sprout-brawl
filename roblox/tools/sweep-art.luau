--!nocheck
-- Bug hunt: draws every cosmetic and crate the way a tile does (ItemArt.draw) at each tile size the
-- game uses, through a recording canvas, and reports art that errors, draws nothing, draws outside
-- its tile, draws NaN or infinite rects, or falls back to magenta (Canvas2D.hex's "missing colour").
--   lune run tools/sweep-art
local Loader = require("../tests/loader")
local Recorder = require("./recorder")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local shapes = Recorder.install(Canvas)
local ItemArt = Loader.loadFrom("src/client/", "ItemArt")
local Cosmetics = Loader.load("Cosmetics")
local CosmeticArt = Loader.load("CosmeticArt")

-- the tile sizes the game asks for: Locker cards, Shop cells, crate cards, the reel
local SIZES = { { 150, 78 }, { 116, 90 }, { 280, 190 }, { 88, 80 } }
local ids = {}
for _, it in Cosmetics.LIST do table.insert(ids, it.id) end
for id in (CosmeticArt.props or {}) do table.insert(ids, id) end
table.sort(ids)

local function finite(v: number): boolean return v == v and v ~= math.huge and v ~= -math.huge end
local problems, drawn, kinds = {}, 0, {}
for _, id in ids do
	local kind = ItemArt.plan(id)
	kinds[kind] = (kinds[kind] or 0) + 1
	for _, sz in SIZES do
		local w, h = sz[1], sz[2]
		table.clear(shapes)
		local c = Recorder.canvas(Canvas, w, h)
		c.pool, c.poolState = {}, {}          -- (ItemArt calls Canvas2D.finish itself)
		local ok, err = pcall(ItemArt.draw, c, id, w, h)
		local where = `{id} ({kind}) at {w}x{h}`
		if not ok then table.insert(problems, `{where}: ERROR {err}`); continue end
		if #shapes == 0 then table.insert(problems, `{where}: draws nothing`); continue end
		drawn += 1
		local x0, y0, x1, y1, bad, magenta = math.huge, math.huge, -math.huge, -math.huge, 0, 0
		for _, s in shapes do
			local pts = if s[1] == "p" then { s[2], s[3], s[4], s[5] } else { { s[2] - s[4], s[3] - s[5] }, { s[2] + s[4], s[3] + s[5] } }
			local colour = if s[1] == "p" then s[6] else s[6]
			if colour == "#ff00ff" then magenta += 1 end
			for _, p in pts do
				if not finite(p[1]) or not finite(p[2]) then bad += 1 else
					x0, y0, x1, y1 = math.min(x0, p[1]), math.min(y0, p[2]), math.max(x1, p[1]), math.max(y1, p[2])
				end
			end
		end
		if bad > 0 then table.insert(problems, `{where}: {bad} non-finite points`) end
		if magenta > 0 then table.insert(problems, `{where}: {magenta} magenta (missing colour) shapes`) end
		local over = math.max(-x0, -y0, x1 - w, y1 - h)
		if over > 1 then table.insert(problems, string.format("%s: drawn %.0f px outside its tile (%.0f,%.0f to %.0f,%.0f)", where, over, x0, y0, x1, y1)) end
		if #shapes > 4000 then table.insert(problems, `{where}: {#shapes} shapes (a cost bug?)`) end
	end
end
local k = {}
for name, n in kinds do table.insert(k, `{name} {n}`) end
table.sort(k)
print(`{#ids} ids ({table.concat(k, ", ")}), {drawn} drawings checked, {#problems} problems`)
for _, p in problems do print("  " .. p) end
if #problems > 0 then error(`{#problems} item pictures are broken`, 0) end

-- `lune run tools/sweep-art sheet.json`: also every id on one contact sheet (Locker-card size), for
-- tools/gui-svg.mjs, each on its tile's background with its id under it
local out = (require("@lune/process").args)[1]
if out then
	local W, H, COLS = 150, 78, 8
	local sheet, nodes = {}, {}
	for i, id in ids do
		local col, row = (i - 1) % COLS, (i - 1) // COLS
		local ox, oy = col * (W + 10) + 10, row * (H + 26) + 10
		table.insert(nodes, { x = ox, y = oy, w = W, h = H, bg = "#E8E2D4", bgAlpha = 1 })
		table.insert(nodes, { x = ox, y = oy + H + 2, w = W, h = 16, text = id, colour = "#FFFFFF", size = 10, font = "Font.BuilderSansBold", align = "middle" })
		table.clear(shapes)
		local c = Recorder.canvas(Canvas, W, H)
		c.pool, c.poolState = {}, {}
		pcall(ItemArt.draw, c, id, W, H)
		for _, s in shapes do
			local t = table.clone(s)
			if t[1] == "p" then for k = 2, 5 do t[k] = { s[k][1] + ox, s[k][2] + oy } end else t[2], t[3] = s[2] + ox, s[3] + oy end
			table.insert(sheet, t)
		end
	end
	local rows = math.ceil(#ids / COLS)
	-- (gui-svg paints the shapes first, then the nodes: tile backgrounds go in as shapes under the art)
	local bgs = {}
	for _, n in nodes do if n.bg then table.insert(bgs, { "p", { n.x, n.y }, { n.x + n.w, n.y }, { n.x + n.w, n.y + n.h }, { n.x, n.y + n.h }, n.bg, 1 }) end end
	for _, s in sheet do table.insert(bgs, s) end
	local labels = {}
	for _, n in nodes do if n.text then table.insert(labels, n) end end
	require("@lune/fs").writeFile(out, require("@lune/serde").encode("json", { w = COLS * (W + 10) + 10, h = rows * (H + 26) + 10, shapes = bgs, nodes = labels }))
	print(`sheet: {out}`)
end
