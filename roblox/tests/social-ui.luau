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
local PLAZA = Loader.load("Plaza").DATA      -- (the Roblox lobby's market)
local Ui = Loader.loadFrom("src/client/", "Ui")

local warps, queued, unqueued, filled = {}, {}, 0, 0
local s = Social.new(instance("PlayerGui"), {
	warp = function(id) table.insert(warps, id); return true end,
	queue = function(format) table.insert(queued, format) end,
	unqueue = function() unqueued += 1 end,
	fill = function() filled += 1 end,
})
s:setEnabled(true)

-- the bar: PLAY and MAP, and nothing of the stamps, quick messages or member list
assert(find(s.gui, "OpenPlay") and find(s.gui, "OpenMap"), "the bar has PLAY and MAP")
for _, gone in { "OpenStamps", "OpenSay", "OpenPeople", "Stamps", "Say", "People", "Log" } do
	assert(not find(s.gui, gone), `the bar still has {gone}`)
end

-- PLAY: three formats; one pressed asks to queue for it and closes the panel
click(s.gui, "OpenPlay")
assert(s:open() == "Play", "PLAY opens its panel")
-- (above the bar's real height: the square buttons stand ICON px, and a panel at the old 42 px bar's
-- height covered their tops)
if Ui.lightPanels() then
	assert(find(s.gui, "Play").Position.Y.Offset <= -(10 + Social.ICON), "the PLAY panel covers the button bar")
end
for _, f in { "Duel", "Doubles", "Triples", "FFA3", "FFA4", "FFA6", "Ranked" } do assert(find(s.gui, "Format_" .. f), "PLAY offers " .. f) end
-- its sections: the team fights, the free-for-alls and Ranked, each a row of buttons side by side
local heads = {}
for _, ch in find(s.gui, "Play"):GetChildren() do if ch.Name == "Section" then table.insert(heads, ch.Text) end end
assert(#heads == 3 and heads[1] == "TEAMS" and heads[2] == "FREE FOR ALL" and string.find(heads[3], "RANKED", 1, true), "PLAY's sections are " .. table.concat(heads, ", "))
local d, t = find(s.gui, "Format_Duel"), find(s.gui, "Format_Triples")
assert(d.Position.Y.Offset == t.Position.Y.Offset and t.Position.X.Offset > d.Position.X.Offset, "1v1, 2v2 and 3v3 are not side by side")
assert(find(s.gui, "Format_FFA3").Position.Y.Offset > d.Position.Y.Offset, "the free-for-alls are not under the team fights")
-- no two buttons overlap, and every one is inside the panel
local panelH = find(s.gui, "Play").Size.Y.Offset
local boxes = {}
for _, ch in find(s.gui, "Play"):GetChildren() do
	if string.sub(ch.Name or "", 1, 7) == "Format_" then
		local x, y, w, h = ch.Position.X.Offset, ch.Position.Y.Offset, ch.Size.X.Offset, ch.Size.Y.Offset
		assert(x >= 0 and y + h <= panelH and x + w <= Social.PLAY_W, ch.Name .. " spills out of the panel")
		for _, b in boxes do
			assert(x + w + 8 <= b[1] or b[1] + b[3] + 8 <= x or y + h + 8 <= b[2] or b[2] + b[4] + 8 <= y, ch.Name .. " is within 8 px of another button")
		end
		table.insert(boxes, { x, y, w, h })
	end
end
-- your level and rank over the buttons: at level 1, Ranked is greyed, says its level, and does not queue
s:setProgress({ level = 1, into = 40, need = 140, points = 0, tier = 1 })
assert(string.find(find(s.gui, "Level").Text, "LEVEL 1", 1, true) and string.find(find(s.gui, "Level").Text, "40 / 140", 1, true), "PLAY does not show the level")
assert(math.abs(find(find(s.gui, "XpBar"), "Fill").Size.X.Scale - 40 / 140) < 1e-6, "the XP bar is not filled to the XP")
assert(string.find(find(s.gui, "Format_Ranked").Text, "LEVEL 10", 1, true), "a locked Ranked does not say its level")
assert(find(s.gui, "Format_Ranked").BackgroundColor3 ~= Ui.ORANGE, "a locked Ranked is in its open colour")
click(s.gui, "Format_Ranked")
assert(#queued == 0 and s:open() == "Play" and string.find(find(s.gui, "Note").Text, "level 10", 1, true), "a level 1 player queued for Ranked")
click(s.gui, "Format_Doubles")
assert(queued[1] == "Doubles" and s:open() == nil, "choosing 2v2 queues for it and closes the panel")
-- a digit picks from the open PLAY panel
click(s.gui, "OpenPlay")
assert(s:key("Three") and queued[2] == "Triples", "3 on the PLAY panel queues for 3v3")
click(s.gui, "OpenPlay")
assert(s:key("Five") and queued[3] == "FFA4", "5 on the PLAY panel queues for a 4-way free-for-all")
-- at level 10 Ranked opens, in its own colour, and the rank shows
s:setProgress({ level = 10, into = 0, need = 275, points = 140, tier = 2 })
assert(not string.find(find(s.gui, "Format_Ranked").Text, "LEVEL", 1, true), "Ranked still says it is locked at level 10")
assert(find(s.gui, "Format_Ranked").BackgroundColor3 == Ui.ORANGE, "an open Ranked is still grey")
assert(string.find(find(s.gui, "Rank").Text, "SILVER", 1, true) and string.find(find(s.gui, "Rank").Text, "140", 1, true), "the rank is not shown")
click(s.gui, "OpenPlay")
click(s.gui, "Format_Ranked")
assert(queued[4] == "Ranked", "a level 10 player could not queue for Ranked")
-- the server's refusal is shown
s:refused("Ranked unlocks at level 10.")
assert(find(s.gui, "Note").Text == "Ranked unlocks at level 10.", "the server's refusal was not shown")

-- the queue's card: shown while queued, with what it waits for; CANCEL and FILL WITH BOTS
local card = find(s.gui, "Queue")
assert(card and not card.Visible, "no queue card before queueing")
s:setQueue({ queued = true, format = "Doubles", name = "2v2", waiting = 1, needed = 4, formAt = 3 })
assert(card.Visible and string.find(find(card, "Title").Text, "2v2", 1, true), "the queue card says what it is finding")
assert(string.find(find(card, "Count").Text, "1 waiting", 1, true) and string.find(find(card, "Count").Text, "at 3", 1, true),
	"and how many wait, and when a room opens")
click(card, "Cancel")
assert(unqueued == 1, "CANCEL leaves the queue")
click(card, "Fill")
assert(filled == 1, "FILL WITH BOTS asks for bots")
s:setQueue({ queued = false })
assert(not card.Visible, "out of the queue, the card goes")

-- the roof map: the Roblox lobby's warps (the arcade and the gates are gone), its rows' words padded
-- in from their edge and bare (dark words wore a grey smudge of an outline on the pale rows)
click(s.gui, "OpenMap")
assert(s:open() == "Map", "MAP opens the roof map")
local rows = 0
for _, w in PLAZA.market.warps do
	local b = find(s.gui, "Warp_" .. w.id)
	assert(b, "no row for " .. w.id)
	rows += 1
	local pad = nil
	for _, ch in b:GetChildren() do if ch.ClassName == "UIPadding" then pad = ch end end
	assert(pad and pad.PaddingLeft.Offset >= 10, `the {w.id} row's words sit against its edge`)
	for _, ch in b:GetChildren() do
		if ch.ClassName == "UIStroke" and tostring(ch.ApplyStrokeMode) ~= "Border" and ch.ApplyStrokeMode ~= "Border" then
			assert((ch.Thickness or 0) == 0, `the {w.id} row's dark words are outlined`)
		end
	end
end
assert(rows == 3 and not find(s.gui, "Warp_arcade") and not find(s.gui, "Warp_gates"), "the map lists the arcade or the gates")
assert(s:key("Three") and warps[#warps] == PLAZA.market.warps[3].id and s:open() == nil, "3 on the map warps to the third place")
assert(s:key("M") and s:open() == "Map", "M opens the map")
s:setEnabled(false)
assert(not s:key("M"), "a hidden bar takes no keys")
print("PASS social UI: the bar is PLAY and MAP; PLAY queues for 1v1/2v2/3v3, 3/4/6 free-for-alls and Ranked by button or digit, in three sections; your level, XP and rank; Ranked locked below level 10; the queue card counts and offers CANCEL and FILL WITH BOTS; the map lists the lobby's three places, padded and bare")
