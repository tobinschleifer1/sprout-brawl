--!nocheck
-- LobbySocial driven through its real buttons and keys: panels, stamps, quick messages, the log,
-- the member list and warps. Instances and signals are stubs; every behaviour is the module's.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rbx = require("@lune/roblox")
local Loader = require("./loader")

local function signal(): any
	local callbacks = {}
	return { Connect = function(_, fn) table.insert(callbacks, fn) end,
		Fire = function(_, ...) for _, fn in callbacks do fn(...) end end }
end
local function instance(class: string): any
	local props: any = { ClassName = class, Visible = true, Enabled = true, Activated = signal(), Text = "" }
	local children = {}
	local self: any
	props.GetChildren = function() return table.clone(children) end
	props.IsA = function(_, c) return props.ClassName == c end
	props.Destroy = function()
		for _, child in table.clone(children) do child:Destroy() end
		if props.Parent then
			local at = table.find(props.Parent._children, self)
			if at then table.remove(props.Parent._children, at) end
		end
	end
	props._children = children
	self = setmetatable({}, { __index = props, __newindex = function(_, key, value)
		props[key] = value
		if key == "Parent" and value then table.insert(value._children, self) end
	end })
	return self
end
local function find(root: any, name: string): any
	for _, child in root:GetChildren() do
		if child.Name == name then return child end
		local deep = find(child, name)
		if deep then return deep end
	end
	return nil
end
local function click(root: any, name: string)
	assert(find(root, name), "missing control " .. name).Activated:Fire()
end

local codes = setmetatable({}, { __index = function(_, name) return name end })
local shared = setmetatable({ Data = setmetatable({}, { __index = function(_, k) return "Data/" .. k end }) }, { __index = function(_, name) return name end })
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local icons: { any } = {}
Canvas.sprite = function(c: any, key: string, list: any, x0: number, y1: number, pw: number, ph: number, cols: number, rows: number)
	table.insert(icons, { key = key, d = c.m.d, x0 = x0, y1 = y1, w = cols * pw, h = rows * ph })
end
-- the shared UI kit builds with these too (Loader.gui)
Loader.gui = { Instance = { new = instance }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Enum = setmetatable({}, { __index = function() return codes end }) }
local Social = luau.load(fs.readFile("src/client/LobbySocial.luau"), { debugName = "LobbySocial", environment = {
	game = { GetService = function(_, name) if name == "ReplicatedStorage" then return { Shared = shared } end error(name) end },
	script = { Parent = codes },
	require = function(name)
		if type(name) == "string" and fs.isFile("src/client/" .. name .. ".luau") then return Loader.loadFrom("src/client/", name) end
		return Loader.load(name)
	end,
	Instance = { new = instance }, Color3 = Rbx.Color3, Vector2 = Rbx.Vector2, UDim = Rbx.UDim, UDim2 = Rbx.UDim2,
	Enum = setmetatable({}, { __index = function() return codes end }),
	typeof = function(v) return if type(v) == "table" and v.EnumType then "EnumItem" else type(v) end,
}, injectGlobals = true })()
local PLAZA = Loader.load("Data/Plaza")

local now = 100
local sent, requests, warps, warpedTo = {}, 0, {}, {}
local s = Social.new(instance("PlayerGui"), {
	localId = 1, clock = function() return now end,
	send = function(msg) table.insert(sent, msg) end,
	requestMembers = function() requests += 1 end,
	warp = function(id) table.insert(warps, id); return true end,
	warpTo = function(m) table.insert(warpedTo, m.userId); return true end,
})

-- 1. Stamp icons are drawn upright: in a y-up transform, inside their tiles.
assert(#icons == #PLAZA.stamps, `drew {#icons} stamp icons for {#PLAZA.stamps} stamps`)
for _, ic in icons do
	assert(ic.d < 0, `{ic.key} drawn in a y-down transform: it would be upside down`)
	assert(ic.x0 >= 0 and ic.x0 + ic.w <= 68 and ic.y1 <= 68 and ic.y1 - ic.h >= 0, `{ic.key} leaves its tile`)
end

-- 2. Disabled (in a fight), nothing opens.
assert(not s:key("T") and not s.gui.Enabled, "the social layer answers keys while disabled")
s:setEnabled(true)

-- 3. Keys open one panel at a time; numbers pick from the open one and close it.
assert(s:key("T") and s:open() == "Stamps", "T opens the stamps")
assert(s:key("Y") and s:open() == "Say", "Y swaps to quick messages")
assert(s:key("Three") and sent[#sent].kind == "say" and sent[#sent].index == 3 and s:open() == nil, "3 sends the third message and closes")
s:key("T")
s:key("Two")
assert(sent[#sent].kind == "stamp" and sent[#sent].id == PLAZA.stamps[2].id, "2 sends the second stamp")
assert(not s:key("Five") or s:open() ~= nil, "a number with nothing open is not used")
s:key("M")
s:key("Three")
assert(warps[#warps] == PLAZA.market.warps[3].id and s:open() == nil, "3 on the map warps to the third place")
click(s.gui, "OpenSay")
click(s.gui, "Say_10")
assert(sent[#sent].index == 10, "the buttons send too")
click(s.gui, "OpenStamps")
click(s.gui, "Stamp_heart")
assert(sent[#sent].id == "heart", "stamp buttons send their stamp")

-- 4. What arrives goes over the right head, into the log, and away again.
s:onEvent({ userId = 7, name = "Rin", kind = "say", index = 1 })
s:onEvent({ userId = 1, name = "Me", kind = "stamp", id = "gg" })
s:onEvent({ userId = 8, name = "X", kind = "stamp", id = "nope" })
s:onEvent({ userId = 8, name = "X", kind = "say", index = 999 })
assert(s:overhead(7).text == PLAZA.messages[1] and s:overhead(1).id == "gg" and s:overhead(8) == nil, "overheads for what was said and stamped, none for nonsense")
assert(s.logLines[Social.LOG_LINES].Text == "You  [GG]" and s.logLines[Social.LOG_LINES - 1].Text == "Rin: " .. PLAZA.messages[1], "the log names who, and says You for you")
now += Social.STAMP_SECONDS + 0.1
assert(s:overhead(1) == nil and s:overhead(7) ~= nil, "a stamp goes before a message does")
now += Social.SAY_SECONDS
assert(s:overhead(7) == nil, "and the message goes too")
for i = 1, 10 do s:onEvent({ userId = 9, name = "Spam", kind = "say", index = (i % 5) + 1 }) end
assert(#s.log == Social.LOG_LINES, "the log keeps its last lines only")

-- 5. People: opening asks the server; rows for everyone; WARP only to others on the market floor.
click(s.gui, "OpenPeople")
assert(requests == 1 and s:open() == "People", "opening the list asks who is here")
s:setMembers({
	{ userId = 1, name = "Me", avatar = PLAZA.cabinets and "Classic", where = "NEON SQUARE", place = "market", x = 0, z = 6 },
	{ userId = 7, name = "Rin", avatar = Loader.load("Data/AvatarKit").presets[3].code, where = "THE ARCADE", place = "market", x = 138, z = 11 },
	{ userId = 8, name = "Kai", avatar = "Classic", where = "2v2 · CREW LIFT", place = "room" },
	{ userId = 9, name = "Zed", avatar = "Classic", where = "Fighting · Duel", place = "fight" },
})
local rows = find(s.gui, "List"):GetChildren()
local count = 0
for _, r in rows do if r.ClassName == "Frame" then count += 1 end end
assert(count == 4, `four rows, got {count}`)
assert(find(find(s.gui, "Member_1"), "Name").Text == "Me (YOU)", "you are marked")
assert(not find(find(s.gui, "Member_1"), "WarpTo") and not find(find(s.gui, "Member_8"), "WarpTo") and not find(find(s.gui, "Member_9"), "WarpTo"),
	"no WARP to yourself, into a room, or into a fight")
find(find(s.gui, "Member_7"), "WarpTo").Activated:Fire()
assert(warpedTo[1] == 7 and s:open() == nil, "WARP takes you to them and closes the list")
s:setEnabled(false)
assert(s:open() == nil and not s.gui.Enabled, "a fight closes everything")
print("PASS social: upright stamp icons, one panel at a time, keys and buttons send stamps, messages and warps, overheads and log with expiry, member list with warps only where you can go")
