--!nocheck
-- Record the shipping still portraits, for kit-sheet.mjs and fight-png.mjs.
-- lune run tools/render-portraits out.json [presets|category[:head]|random|clothing] [--half|--match]
--   clothing: every clothing piece on the default character, through its k2 code (AvatarKit)
local fs, process, serde = require("@lune/fs"), require("@lune/process"), require("@lune/serde")
local Loader = require("../tests/loader")
local Recorder = require("./recorder")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Portrait = Loader.loadFrom("src/client/", "KitPortrait")
local Kit = Loader.load("AvatarKit")
local words = string.split(process.args[2] or "presets", ":")
local mode, heads = words[1], words[2] == "head"
local half, small = process.args[3] == "--half", process.args[3] == "--match"
local entries = {}
if mode == "presets" then
	for _, p in Kit.KIT.presets do table.insert(entries, { code = p.code, label = p.name }) end
elseif mode == "random" then
	local seed = 7
	local function rnd(n)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return math.floor(seed / 65536) % n + 1
	end
	for i = 1, 24 do
		local spec = { parts = {}, colours = {} }
		for _, c in Kit.KIT.categories do spec.parts[c.id] = c.options[rnd(#c.options)].id end
		for _, c in Kit.KIT.colours do spec.colours[c.id] = rnd(#c.list) - 1 end
		table.insert(entries, { code = Kit.encode(spec), label = `#{i}` })
	end
elseif mode == "clothing" then
	for _, it in Loader.load("RobloxClothing").items do
		local spec = Kit.sanitize(nil)
		spec.parts[it.category] = it.id
		table.insert(entries, { code = Kit.encode(spec), label = it.name })
	end
else
	local category = assert(Kit.category(mode), "unknown category " .. mode)
	for _, o in category.options do
		table.insert(entries, { code = Kit.encode({ parts = { [mode] = o.id } }), label = o.name })
	end
end
local W, H = if small then 48 else 150, if small then 48 else 230
local shapes, frames = Recorder.install(Canvas), {}
for i, e in entries do
	local c = Recorder.canvas(Canvas, W, H)
	table.clear(shapes)
	if small then Canvas.setTransform(c, 5, 0, 0, -5, W / 2, H - 8)
	else Portrait.frame(c, if heads then "head" else "figure", W, H) end
	if heads then Portrait.head(c, e.code, 0, 0, 1, half)
	else Portrait.figure(c, e.code, 0, 0, 1, half) end
	table.insert(frames, { frame = i, label = e.label, shapes = table.clone(shapes) })
end
local json = serde.encode("json", { w = W, h = H, frames = frames })
if process.args[1] == "-" then print(json) else fs.writeFile(process.args[1], json) end
