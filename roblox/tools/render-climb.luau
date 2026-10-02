--!nocheck
-- Development tool: draw the Skyline Climb at a checkpoint to JSON, for tools/hub-svg.mjs.
--   lune run tools/render-climb <out.json> [checkpoint index] [dx]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local Rbx = require("@lune/roblox")
local Loader = require("../tests/loader")
local Input = Loader.load("Input")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local codes = setmetatable({}, { __index = function(_, key) return key end })
local shared = setmetatable({ Data = setmetatable({}, { __index = function(_, k) return "Data/" .. k end }) }, { __index = function(_, key) return key end })
local Recorder = require("./recorder")
local instance, labels = Recorder.instances()
local View = luau.load(fs.readFile("src/client/ParkourView.luau"), { environment = {
	game = { GetService = function(_, name) return { Shared = shared } end },
	script = { Parent = codes },
	require = function(name)
		if name == "InputClient" then return { new = function() return { sample = function() return {} end, reset = function() end } end } end
		if type(name) == "string" and fs.isFile("src/client/" .. name .. ".luau") then return Loader.loadFrom("src/client/", name) end
		return Loader.load(name)
	end,
	Color3 = Rbx.Color3, Vector2 = Rbx.Vector2, UDim2 = Rbx.UDim2, UDim = Rbx.UDim,
	Enum = setmetatable({}, { __index = function() return codes end }), Instance = { new = instance },
}, injectGlobals = true })()
local shapes = Recorder.install(Canvas)
local W, H = 1280, 720
local KIT = Loader.load("Data/AvatarKit")
local v = View.new({}, { send = function() end })
local from = tonumber(process.args[2] or "0") or 0
-- 4th arg: the furthest checkpoint climbed to (default: where you start), for the rewards.
v:setProgress({ best = from, climbed = tonumber(process.args[4] or "") or from, summits = 0 })
v:start(KIT.presets[5].code, from)
local dx = tonumber(process.args[3] or "0") or 0
v.pk.fighter.x += dx
v.camX, v.camY = v.pk.fighter.x + 5, v.pk.fighter.y + 6
local c = Recorder.canvas(Canvas, W, H)
for _ = 1, 3 do table.clear(shapes); v:draw(c, 1/60) end
local texts = Recorder.texts(labels, W, H)
fs.writeFile(process.args[1], require("@lune/serde").encode("json", { w = W, h = H, shapes = shapes, texts = texts }))
print(`climb at checkpoint {from}: {#shapes} shapes`)
