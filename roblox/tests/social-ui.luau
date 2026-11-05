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
	props.IsA = function(_, c)
		if c == "GuiObject" then return props.ClassName ~= "UICorner" and props.ClassName ~= "UIStroke" and props.ClassName ~= "UIPadding"
			and props.ClassName ~= "UIListLayout" and props.ClassName ~= "UIGradient" and props.ClassName ~= "ScreenGui" end
		return props.ClassName == c
	end
	props.GetPropertyChangedSignal = function() return signal() end
	props.AbsoluteSize = Rbx.Vector2.new(1280, 720)
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

local warps, queued, unqueued, filled, invited, tracked, opened = {}, {}, 0, 0, 0, {}, {}
local partySent = {}
local s = Social.new(instance("PlayerGui"), {
	warp = function(id) table.insert(warps, id); return true end,
	queue = function(format) table.insert(queued, format) end,
	unqueue = function() unqueued += 1 end,
	fill = function() filled += 1 end,
	invite = function() invited += 1 end,
	track = function(name) table.insert(tracked, name) end,
	players = function() return { { id = 1, name = "Me" }, { id = 2, name = "Zed" }, { id = 3, name = "Ann" }, { id = 4, name = "Bo" } } end,
	party = function(msg) table.insert(partySent, msg) end,
	opened = function(name) table.insert(opened, name) end,
})
s.localId = 1
s:setEnabled(true)

-- the bar: PLAY and MAP, and nothing of the stamps, quick messages or member list
assert(find(s.gui, "OpenPlay") and find(s.gui, "OpenMap"), "the bar has PLAY and MAP")
for _, gone in { "OpenStamps", "OpenSay", "OpenPeople", "Stamps", "Say", "People", "Log" } do
	assert(not find(s.gui, gone), `the bar still has {gone}`)
end

-- PLAY: three formats; one pressed asks to queue for it and closes the panel
click(s.gui, "OpenPlay")
assert(s:open() == "Play", "PLAY opens its panel")
-- (and says so, so the lobby's other windows close: Windows; closing it says nothing)
assert(#opened == 1 and opened[1] == "Play", "opening PLAY did not tell the lobby")
click(s.gui, "OpenPlay")
assert(s:open() == nil and #opened == 1, "closing PLAY told the lobby it opened")
click(s.gui, "OpenPlay")
assert(s:open() == "Play" and #opened == 2, "reopening PLAY did not tell the lobby")
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
-- a new player (no XP): opening PLAY, 1v1 pulses and the note says where to start, until they choose
do
	local t = 0
	s.now = function() return t end
	s:setProgress({ level = 1, xp = 0, into = 0, need = 140, points = 0, tier = 1 })
	s:tick()
	assert(string.find(find(s.gui, "Note").Text, "Start with a 1v1", 1, true), "a new player is not told where to start")
	assert(tracked[#tracked] == "start_here", "the start-here note was not counted")
	local seen = {}
	for k = 0, 3 do t = k * 0.5; s:tick(); seen[tostring(find(s.gui, "Format_Duel").BackgroundColor3)] = true end
	local n = 0
	for _ in seen do n += 1 end
	assert(n >= 2, "1v1 does not pulse for a new player")
	s.now = os.clock
end
-- your level and rank over the buttons: at level 1, Ranked is greyed, says its level, and does not queue
s:setProgress({ level = 1, into = 40, need = 140, points = 0, tier = 1 })
assert(string.find(find(s.gui, "Level").Text, "LEVEL 1", 1, true) and string.find(find(s.gui, "Level").Text, "40 / 140", 1, true), "PLAY does not show the level")
assert(math.abs(find(find(s.gui, "XpBar"), "Fill").Size.X.Scale - 40 / 140) < 1e-6, "the XP bar is not filled to the XP")
assert(string.find(find(s.gui, "Format_Ranked").Text, "LEVEL 10", 1, true), "a locked Ranked does not say its level")
-- the next level's reward (the Road to 50): level 2's Sparks; at 9, Ranked with its key and crate
assert(find(s.gui, "NextReward").Text == "LEVEL 2:  +24 Sparks", `the next reward reads "{find(s.gui, "NextReward").Text}"`)
s:setProgress({ level = 9, into = 0, need = 260, points = 0, tier = 1 })
assert(find(s.gui, "NextReward").Text == "LEVEL 10:  +40 Sparks  ·  Ranked + Forge Key + Scrap Crate", `level 9's next reward reads "{find(s.gui, "NextReward").Text}"`)
s:setProgress({ level = 50, into = 0, need = 0, points = 0, tier = 1 })
assert(string.find(find(s.gui, "NextReward").Text, "done", 1, true), "level 50 still offers a next reward")
s:setProgress({ level = 1, into = 60, need = 140, points = 0, tier = 1 })
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
-- INVITE FRIENDS asks for Roblox's invite prompt
click(s.gui, "OpenPlay")
assert(find(s.gui, "Invite"), "PLAY has no INVITE FRIENDS")
click(s.gui, "Invite")
assert(invited == 1 and table.find(tracked, "invite"), "INVITE FRIENDS did not ask for the invite prompt, or was not counted")
-- a quiet queue: after QUIET seconds with nobody joining, the card says bots are ready and FILL pulses
do
	local t = 100
	s.now = function() return t end
	s:setQueue({ queued = true, format = "FFA6", name = "6-WAY FFA", waiting = 1, needed = 6, formAt = 5 })
	local fillB = find(find(s.gui, "Queue"), "Fill")
	local before = fillB.BackgroundColor3
	t += Social.QUIET - 1; s:tick()
	assert(not string.find(find(s.gui, "Count").Text, "quiet right now", 1, true), "the queue called itself quiet too soon")
	t += 1; s:tick()
	assert(string.find(find(s.gui, "Count").Text, "quiet right now", 1, true), "a quiet queue did not offer its bots")
	assert(string.find(find(s.gui, "Count").Text, "1 waiting", 1, true), "the quiet nudge hid how many are waiting")
	assert(tracked[#tracked] == "quiet_shown", "the quiet nudge was not counted")
	local colours = {}
	for k = 0, 3 do t += 0.5 * k; s:tick(); colours[tostring(fillB.BackgroundColor3)] = true end
	local n = 0
	for _ in colours do n += 1 end
	assert(n >= 2, "FILL WITH BOTS does not pulse")
	-- (left on the lighter half of the pulse, to see it put back)
	t += 0.5; s:tick()
	assert(fillB.BackgroundColor3 ~= Ui.GREEN, "the test meant to leave FILL on its pulse colour")
	-- someone joining restarts the clock
	s:setQueue({ queued = true, format = "FFA6", name = "6-WAY FFA", waiting = 2, needed = 6, formAt = 5 })
	s:tick()
	assert(not string.find(find(s.gui, "Count").Text, "quiet right now", 1, true), "a queue someone just joined is still called quiet")
	assert(fillB.BackgroundColor3 == Ui.GREEN, "FILL WITH BOTS kept its pulse colour after the quiet ended")
	s:setQueue({ queued = false })
	s.now = os.clock
	local _ = before
end
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
-- PLAY fits a phone on its side: 412 px of window on a 375 px screen ran its level, rank and TEAMS
-- off the top. On a short screen it is as tall as the room above the button row, its contents
-- scrolling under its band; on a tall one, as tall as its contents.
do
	local play, scroll = s.playPanel, s.playScroll
	s:fit(375)
	local shown = play.Size.Y.Offset
	local bottom = 10 + Social.ICON + 8
	if shown > 375 - bottom - 58 or shown < 160 then error(`on a 375 px screen PLAY is {shown} px tall`) end
	if scroll.CanvasSize.Y.Offset ~= s.playH - Social.BAND or scroll.Parent ~= play then error("PLAY's contents do not scroll under its band") end
	for _, name in { "Level", "Rank", "Format_Duel", "Format_Ranked", "Invite" } do
		local c = find(scroll, name)
		if not c then error(`{name} is not in PLAY's scrolling contents`) end
		if c.Position.Y.Offset < 0 then error(`{name} starts above the scrolling contents`) end
	end
	s:fit(1080)
	if play.Size.Y.Offset ~= s.playH then error("on a tall screen PLAY is not as tall as its contents") end
	s:fit(720)
end
-- PARTY (Parties): from PLAY, your party and everyone else here with INVITE; the leader picks.
s:setEnabled(true)
s:closeAll()
click(s.gui, "OpenPlay")
click(s.gui, "OpenParty")
assert(s:open() == "Party", "PARTY did not open its panel from PLAY")
local list = find(s.gui, "Party")
assert(find(list, "Alone") and not find(list, "Leave"), "alone, the panel offers LEAVE PARTY or does not say so")
-- everyone else, by name, each with INVITE; not yourself
assert(not find(list, "Invite_1") and find(list, "Invite_2") and find(list, "Invite_3") and find(list, "Invite_4"), "the players here are not all offered")
assert(find(list, "Invite_3").Position.Y.Offset < find(list, "Invite_4").Position.Y.Offset
	and find(list, "Invite_4").Position.Y.Offset < find(list, "Invite_2").Position.Y.Offset, "the players are not in name order")
click(list, "Invite_3")
assert(#partySent == 1 and partySent[1].action == "invite" and partySent[1].id == 3, "INVITE did not ask the server")
-- the server says it is sent: the button says so and sends nothing more
s:setParty({ members = { { id = 1, name = "Me", leader = false } }, leader = true, invites = {}, sent = { 3 }, max = 3 })
assert(find(list, "Invite_3").Text == "SENT", "a sent invite is offered again")
click(list, "Invite_3")
assert(#partySent == 1, "a sent invite was sent again")
-- in a party of two that you lead: both listed, LEAVE PARTY, and PLAY says how many
s:setParty({ members = { { id = 1, name = "Me", leader = true }, { id = 3, name = "Ann", leader = false } }, leader = true,
	invites = {}, sent = {}, max = 3, event = { to = 1, joined = "Me" } })
assert(find(list, "Member_1") and find(list, "Member_3") and not find(list, "Invite_3") and not find(list, "Alone"), "the party's members are not listed")
assert(string.find(find(list, "Member_1").Text, "LEADER", 1, true) and not string.find(find(list, "Member_3").Text, "LEADER", 1, true), "the leader is not marked")
assert(find(s.gui, "OpenParty").Text == "PARTY  ·  2 / 3", "PLAY does not show the party")
click(list, "Leave")
assert(partySent[#partySent].action == "leave", "LEAVE PARTY did not ask the server")
-- full: nobody else can be invited
s:setParty({ members = { { id = 1, name = "Me", leader = true }, { id = 3, name = "Ann" }, { id = 4, name = "Bo" } }, leader = true,
	invites = {}, sent = {}, max = 3 })
local before = #partySent
click(list, "Invite_2")
assert(#partySent == before and find(list, "Invite_2").Text == "FULL", "a full party invited another")
-- a member, not the leader: no inviting, and PLAY's picks stay with the leader
s:setParty({ members = { { id = 3, name = "Ann", leader = true }, { id = 1, name = "Me" } }, leader = false,
	invites = {}, sent = {}, max = 3, event = { to = 1, error = "Only your party leader can invite." } })
before = #partySent
click(list, "Invite_2")
assert(#partySent == before, "a member who does not lead invited")
assert(find(list, "Note") and string.find(find(list, "Note").Text, "leader", 1, true), "the server's refusal was not shown")
local queuedBefore = #queued
s:choose("Doubles")
assert(#queued == queuedBefore and string.find(find(s.gui, "Note").Text, "leader picks", 1, true), "a member picked the party's fight")
s:setParty({ members = { { id = 1, name = "Me", leader = false } }, leader = true, invites = {}, sent = {}, max = 3 })
s:choose("Doubles")
assert(#queued == queuedBefore + 1, "on your own again, PLAY did not pick")

-- The invite's pop-up (PartyPrompt): JOIN NAME'S PARTY?, its countdown, JOIN and NO, one at a time.
local Prompt = Loader.loadFrom("src/client/", "PartyPrompt")
local now, answers = 100, {}
local pg = instance("PlayerGui")
local prompt = Prompt.new(pg, { now = function() return now end,
	accept = function(id) table.insert(answers, { "join", id }) end, decline = function(id) table.insert(answers, { "no", id }) end })
assert(not prompt.gui.Enabled, "the pop-up shows with no invite")
prompt:set({ invites = { { from = 7, name = "Ann", left = 30 }, { from = 8, name = "Bo", left = 20 } } })
assert(prompt.gui.Enabled and find(pg, "Title").Text == "JOIN ANN'S PARTY?", "the invite does not say whose party")
assert(string.find(find(pg, "Left").Text, "30s", 1, true) and string.find(find(pg, "Left").Text, "1 more", 1, true), "the countdown or the next invite is not shown")
now = 110; prompt:tick()
assert(string.find(find(pg, "Left").Text, "20s", 1, true), "the countdown does not count")
click(pg, "Join")
assert(answers[1][1] == "join" and answers[1][2] == 7, "JOIN did not ask to join that party")
assert(find(pg, "Title").Text == "JOIN BO'S PARTY?", "the next invite was not shown")
now = 121; prompt:tick()
assert(not prompt.gui.Enabled and #answers == 1, "a run-out invite stayed up, or answered itself")
prompt:set({ invites = { { from = 9, name = "Cy", left = 30 } } })
click(pg, "No")
assert(answers[2][1] == "no" and answers[2][2] == 9 and not prompt.gui.Enabled, "NO did not decline")

print("PASS social UI: the bar is PLAY and MAP; PLAY queues for 1v1/2v2/3v3, 3/4/6 free-for-alls and Ranked by button or digit, in three sections; your level, XP and rank; Ranked locked below level 10; INVITE FRIENDS; a quiet queue offers its bots; the queue card counts and offers CANCEL and FILL WITH BOTS; the map lists the lobby's three places, padded and bare; PARTY lists your party and invites the players here, the leader alone inviting and picking; the invite pop-up counts down, JOIN and NO answer it")
