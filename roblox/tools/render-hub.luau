--!nocheck
-- Development tool, not a test: runs the real Hub2D draw path with a recording canvas and writes
-- what it drew - every rectangle as its four screen corners, plus the text labels - as JSON, for
-- tools/hub-svg.mjs to turn into a picture. The game renders into a ScreenGui, so Studio's
-- screenshot is empty; this is how to look at the lobby without it.
--   lune run tools/render-hub <out.json> [market|Duel|Doubles|Triples] [x] [mapChoice] [mode] [character] [z] [peers]
-- `peers` scatters that many ready-made characters around you, to see a busy roof.
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
local Hub = luau.load(fs.readFile("src/client/Plaza2D.luau"), { environment = {
	game = { GetService = function(_, name)
		if name == "ReplicatedStorage" then return { Shared = shared } end
		return { GetFocusedTextBox = function() return false end, IsKeyDown = function() return false end,
			IsGamepadButtonDown = function() return false end }
	end },
	script = { Parent = codes },
	require = function(name)
		if name == "InputClient" then return { new = function() return {
			frame = Input.emptyFrame(), sample = function(self) return { self.frame } end, reset = function() end,
		} end } end
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
	local cx, cy = m.a * x + m.c * y + m.e, m.b * x + m.d * y + m.f
	table.insert(shapes, { "e", cx, cy, math.abs(rx * m.a), math.abs(ry * m.d), hex(colour), (alpha or 1) * c.alpha })
end
Canvas.circle = function(c: any, x: number, y: number, r: number, colour: any, alpha: number?)
	Canvas.ellipse(c, x, y, r, r, colour, alpha)
end
-- A sprite is its rectangles, recorded one by one in the sprite's transform.
Canvas.sprite = function(c: any, _key: string, rects: any, x0: number, y1: number, pw: number, ph: number)
	Canvas.eachSpriteRect(rects, x0, y1, pw, ph, function(x, y, w, h, hex, alpha)
		Canvas.rect(c, x, y, w, h, Rbx.Color3.fromHex(hex), alpha)
	end)
end

local W, H = 1280, 720
local scene = process.args[2] or "market"
local at = tonumber(process.args[3] or "0") or 0
local cfg = Loader.load("MatchConfig").default()
-- Optional 4th/5th arguments: wear this kit code (or preset id) in the render.
if process.args[6] then
	local KIT = Loader.load("Data/AvatarKit")
	for _, p in KIT.presets do if p.id == process.args[6] then cfg.slots[1].avatarId = p.code end end
	if string.sub(process.args[6], 1, 2) == "k1" then cfg.slots[1].avatarId = process.args[6] end
end
local hub = Hub.new({})
hub:show(cfg)
if scene ~= "market" then
	-- a room mid-setup: you not ready, a ready teammate, an open place and a bot, voting on maps
	hub:setRoom({ id = 1, format = scene, stage = "FoundryFloor", mapChoice = process.args[4] or "host", mode = process.args[5] or "stock", stocks = 3, time = 180,
		slots = { { userId = 1, team = 0, ready = false, vote = "Undertow" }, { userId = 2, team = 1, ready = true, vote = "Undertow" },
			{ team = 0 }, { team = 1, bot = "easy" } } })
end
local z = tonumber(process.args[7] or "8") or 8
hub.model:setScene(hub.model.data, { x = at, z = z })
hub.camX = at
local crowd = tonumber(process.args[8] or "0") or 0
if crowd > 0 then
	local KIT = Loader.load("Data/AvatarKit")
	local list = {}
	for i = 1, crowd do
		local p = KIT.presets[(i * 3) % #KIT.presets + 1]
		table.insert(list, { userId = 100 + i, name = p.name, avatar = p.code, weapon = "Sword",
			x = at - 20 + (i * 37 % 41), z = 2 + (i * 5 % 15), y = 0, facing = if i % 2 == 0 then 1 else -1, moving = i % 3 == 0 })
	end
	hub:setPeers(list, 1)
	for id, peer in hub.peers do peer.x, peer.z = peer.target.x, peer.target.z end
end
local c = setmetatable({ used = 0, stack = {}, alpha = 1, alphaStack = {}, m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 },
	gui = { AbsoluteSize = { X = W, Y = H } }, finish = function() end }, { __index = Canvas })
for _ = 1, 30 do table.clear(shapes); hub:step(1/60, false); hub:draw(c, 1/60) end
local texts = {}
for _, t in labels do
	if t.Text and t.Text ~= "" and t.Visible ~= false and not t.destroyed and t.Position then
		local p, s = t.Position, t.Size
		local x = p.X.Scale * W + p.X.Offset
		local y = p.Y.Scale * H + p.Y.Offset
		local w = (s and (s.X.Scale * W + s.X.Offset)) or 200
		local h = (s and (s.Y.Scale * H + s.Y.Offset)) or 20
		if t.AnchorPoint then x -= t.AnchorPoint.X * w; y -= t.AnchorPoint.Y * h end
		table.insert(texts, { x, y, w, h, t.Text, if t.TextColor3 then hex(t.TextColor3) else "#e7e3d1", t.TextSize or 14,
			t.BackgroundTransparency ~= nil and t.BackgroundTransparency < 1 and hex(t.BackgroundColor3) or nil })
	end
end
fs.writeFile(process.args[1], require("@lune/serde").encode("json", { w = W, h = H, shapes = shapes, texts = texts }))
print(`{scene} at x={at}: {#shapes} shapes, {#texts} labels`)
