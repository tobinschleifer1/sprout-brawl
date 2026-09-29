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
local labels = {}
local function instance(): any
	local obj: any = { attributes = {}, Visible = true }
	table.insert(labels, obj)
	obj.Destroy = function() obj.destroyed = true end
	obj.Activated = { Connect = function(_, fn) obj.activate = fn end }
	obj.SetAttribute = function(_, key, value) obj.attributes[key] = value end
	return obj
end
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
local shapes = {}
local function hex(c: any): string
	return string.format("#%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
Canvas.rect = function(c: any, x: number, y: number, w: number, h: number, colour: any, alpha: number?)
	local m = c.m
	local function P(u: number, v: number) return { m.a * u + m.c * v + m.e, m.b * u + m.d * v + m.f } end
	table.insert(shapes, { "p", P(x, y), P(x + w, y), P(x + w, y + h), P(x, y + h), hex(colour), (alpha or 1) * c.alpha })
end
Canvas.ellipse = function(c: any, x: number, y: number, rx: number, ry: number, colour: any, alpha: number?)
	local m = c.m
	table.insert(shapes, { "e", m.a * x + m.c * y + m.e, m.b * x + m.d * y + m.f, math.abs(rx * m.a), math.abs(ry * m.d), hex(colour), (alpha or 1) * c.alpha })
end
Canvas.circle = function(c: any, x: number, y: number, r: number, colour: any, alpha: number?) Canvas.ellipse(c, x, y, r, r, colour, alpha) end
Canvas.sprite = function(c: any, _key: string, rects: any, x0: number, y1: number, pw: number, ph: number)
	Canvas.eachSpriteRect(rects, x0, y1, pw, ph, function(x, y, w, h, hx, alpha) Canvas.rect(c, x, y, w, h, Rbx.Color3.fromHex(hx), alpha) end)
end
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
local c = setmetatable({ used = 0, stack = {}, alpha = 1, alphaStack = {}, m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 },
	gui = { AbsoluteSize = { X = W, Y = H } }, finish = function() end }, { __index = Canvas })
for _ = 1, 3 do table.clear(shapes); v:draw(c, 1/60) end
local texts = {}
for _, t in labels do
	if t.Text and t.Text ~= "" and t.Visible ~= false and not t.destroyed and t.Position then
		local p, s = t.Position, t.Size
		local x = p.X.Scale * W + p.X.Offset
		local y = p.Y.Scale * H + p.Y.Offset
		local w = (s and (s.X.Scale * W + s.X.Offset)) or 200
		local h = (s and (s.Y.Scale * H + s.Y.Offset)) or 20
		if t.AnchorPoint then x -= t.AnchorPoint.X * w; y -= t.AnchorPoint.Y * h end
		table.insert(texts, { x, y, w, h, t.Text, if t.TextColor3 then hex(t.TextColor3) else "#e7e3d1", t.TextSize or 14, nil })
	end
end
fs.writeFile(process.args[1], require("@lune/serde").encode("json", { w = W, h = H, shapes = shapes, texts = texts }))
print(`climb at checkpoint {from}: {#shapes} shapes`)
