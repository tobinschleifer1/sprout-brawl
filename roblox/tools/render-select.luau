--!nocheck
-- Development tool, not a test: the select screen (SelectScreen) built against stand-in Instances,
-- given a sample room, with its canvas scene recorded - written as JSON for tools/gui-svg.mjs, so
-- the screen can be looked at without Studio. Every Frame, label and button is resolved to its
-- absolute rectangle through its parents, with its corner radius and outline.
--
--   lune run tools/render-select <out.json> [width] [height] [format: 1v1|2v2|3v3] [phase: pick|map|rules]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Rbx = require("@lune/roblox")
local Loader = require("../tests/loader")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local Recorder = require("./recorder")
local KIT = Loader.load("Data/AvatarKit")
local shapes = Recorder.install(Canvas)

local W = tonumber(process.args[2] or "1280") or 1280
local H = tonumber(process.args[3] or "720") or 720
local format = process.args[4] or "2v2"
local phase = process.args[5] or "pick"

-- ------------------------------------------------------------------ stand-in Instances ----
local made = {}
local function signal(): any
	local fns = {}
	return { Connect = function(_, fn) table.insert(fns, fn) end, Fire = function(_, ...) for _, fn in fns do fn(...) end end }
end
local function new(class: string): any
	local props: any = { ClassName = class, Visible = true, Activated = signal(), Name = class, _children = {} }
	local self: any
	props.Destroy = function()
		props.destroyed = true
		for _, ch in table.clone(props._children) do ch:Destroy() end
	end
	props.ClearAllChildren = function() for _, ch in table.clone(props._children) do ch:Destroy() end end
	props.FindFirstChild = function(_, name) for _, ch in props._children do if ch.Name == name then return ch end end return nil end
	props.GetChildren = function() return table.clone(props._children) end
	self = setmetatable({}, { __index = props, __newindex = function(_, k, v)
		props[k] = v
		if k == "Parent" and v then table.insert(v._children, self) end
	end })
	if class == "ScreenGui" then props.AbsoluteSize = Rbx.Vector2.new(W, H); props.Enabled = true end
	table.insert(made, self)
	return self
end
local names = setmetatable({}, { __index = function(_, k) return k end })
local shared = setmetatable({ Data = setmetatable({}, { __index = function(_, k) return "Data/" .. k end }) },
	{ __index = function(_, k) return k end })
local function resolve(name: string): any
	if string.sub(name, 1, 5) == "Data/" then return Loader.load(name) end
	if fs.isFile("src/client/" .. name .. ".luau") then return Loader.loadFrom("src/client/", name) end
	return Loader.load(name)
end
local enumNames = setmetatable({}, { __index = function(_, k) return setmetatable({}, { __index = function(_, v) return k .. "." .. v end }) end })
-- the shared UI kit builds with these too (Loader.gui)
Loader.gui = { Instance = { new = new }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Enum = enumNames }
-- a style theme to draw in (Ui.THEMES), picked before any screen module loads and reads its fonts
Loader.loadFrom("src/client/", "Ui").useTheme(process.env.UI_THEME)
local Screen = luau.load(fs.readFile("src/client/SelectScreen.luau"), { debugName = "SelectScreen", environment = {
	game = { GetService = function() return { Shared = shared } end },
	script = { Parent = names },
	require = resolve,
	Instance = { new = new }, Enum = enumNames,
	Color3 = Rbx.Color3, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Vector2 = Rbx.Vector2,
}, injectGlobals = true })()

-- ------------------------------------------------------------------ a sample room ----
local code
for _, p in KIT.presets do if p.id == "knight" then code = p.code end end
local looks = {}
for _, p in KIT.presets do table.insert(looks, p.code) end
local size = if format == "1v1" then 2 elseif format == "3v3" then 6 else 4
local slots = {}
local weapons = { "Sword", "Hammer", "Scythe", "Daggers", "Pike", "Grimoire" }
for i = 1, size do
	slots[i] = { team = (i - 1) % 2, weapon = weapons[i], avatar = looks[(i * 3) % #looks + 1], ready = false, name = "Open" }
end
slots[1].userId, slots[1].name, slots[1].avatar, slots[1].ready = 1, "You", code, true
slots[2].userId, slots[2].name = 2, "Rival"
if size >= 4 then
	slots[4].bot, slots[4].name, slots[4].ready = "normal", "CPU", true
	slots[3].weapon = nil        -- open, with a vote running on it
end
if size >= 6 then slots[5].userId, slots[5].name = 5, "Ally" end
local room = { id = 12, host = 1, format = format, name = format .. " Match", state = "setup", revision = 3, stage = "FoundryFloor",
	stocks = 3, items = true, disasters = "off", slots = slots, canStart = false, mapChoice = "vote", mapSet = "all",
	mode = "stock", time = 180,
	botVote = if size >= 4 then { slot = 3, value = "normal", by = 2, yes = 1, no = 0, voters = if size >= 6 then 3 else 2,
		ballots = { ["2"] = true }, left = 7 } else nil }

room.phase, room.phaseLeft = phase, if phase == "pick" then nil else 11
if phase ~= "pick" then
	room.botVote = nil
	for _, slot in slots do if not slot.userId and not slot.bot then slot.bot, slot.weapon, slot.ready = "easy", "Axe", true end end
end
if phase == "map" then slots[1].vote, slots[2].vote = "Undertow", "Random"; if slots[5] then slots[5].vote = "Undertow" end end
if phase == "rules" then
	room.mapResult, room.stage = "Undertow", "Undertow"
	slots[1].ruleVote = "casual"
	if slots[5] then slots[5].ruleVote = "chaos" end
end
local screen = Screen.new(new("Folder"))
screen:update(room, 1)
local c = Recorder.canvas(Canvas, W, H)
for _ = 1, 3 do table.clear(shapes); screen:draw(c, 1 / 60, code) end

-- ------------------------------------------------------------------ resolve the GUI ----
local function hex(c3: any): string
	return string.format("#%02x%02x%02x", math.floor(c3.R * 255 + 0.5), math.floor(c3.G * 255 + 0.5), math.floor(c3.B * 255 + 0.5))
end
local function rect(o: any): (number, number, number, number)
	local p = o.Parent
	local px, py, pw, ph = 0, 0, W, H
	if p and p.ClassName ~= "ScreenGui" and p.ClassName ~= "Folder" then px, py, pw, ph = rect(p) end
	local pos, sz = o.Position or Rbx.UDim2.new(), o.Size or Rbx.UDim2.new(1, 0, 1, 0)
	local w, h = pw * sz.X.Scale + sz.X.Offset, ph * sz.Y.Scale + sz.Y.Offset
	local x, y = px + pw * pos.X.Scale + pos.X.Offset, py + ph * pos.Y.Scale + pos.Y.Offset
	if o.AnchorPoint then x -= o.AnchorPoint.X * w; y -= o.AnchorPoint.Y * h end
	return x, y, w, h
end
local function shown(o: any): boolean
	local cur = o
	while cur do
		if cur.destroyed or cur.Visible == false or (cur.ClassName == "ScreenGui" and cur.Enabled == false) then return false end
		cur = cur.Parent
	end
	return true
end
local nodes = {}
for _, o in made do
	local cls = o.ClassName
	if (cls == "Frame" or cls == "TextLabel" or cls == "TextButton") and shown(o) then
		local x, y, w, h = rect(o)
		local node = { x = x, y = y, w = w, h = h }
		if o.BackgroundTransparency == nil or o.BackgroundTransparency < 1 then
			node.bg, node.bgAlpha = hex(o.BackgroundColor3 or Rbx.Color3.new(0.6, 0.6, 0.6)), 1 - (o.BackgroundTransparency or 0)
		end
		for _, ch in o._children do
			if ch.ClassName == "UICorner" and not ch.destroyed then node.radius = ch.CornerRadius.Offset + (ch.CornerRadius.Scale or 0) * math.min(w, h) end
			-- (a 0 px stroke draws nothing in Roblox; recorded, the SVG drew a default one)
			if ch.ClassName == "UIStroke" and not ch.destroyed and ch.Enabled ~= false and (ch.Thickness or 1) > 0 then
				if ch.ApplyStrokeMode == "ApplyStrokeMode.Border" then node.stroke, node.strokeW = hex(ch.Color), ch.Thickness
				elseif cls ~= "Frame" then node.textStroke, node.textStrokeW = hex(ch.Color), ch.Thickness end
			end
		end
		if (cls == "TextLabel" or cls == "TextButton") and o.Text and o.Text ~= "" then
			node.text, node.colour, node.size = o.Text, hex(o.TextColor3 or Rbx.Color3.new(1, 1, 1)), o.TextSize or 14
			node.font = tostring(o.Font or "")
			node.wrap = o.TextWrapped == true
			node.align = if o.TextXAlignment == "TextXAlignment.Left" then "start" elseif o.TextXAlignment == "TextXAlignment.Right" then "end" else "middle"
		end
		table.insert(nodes, node)
	end
end
fs.writeFile(process.args[1], serde.encode("json", { w = W, h = H, shapes = shapes, nodes = nodes }))
print(`select screen {format} at {W}x{H}: {#shapes} canvas shapes, {#nodes} GUI nodes`)
