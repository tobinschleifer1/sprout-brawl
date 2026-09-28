--!strict
-- Talking in the lobby: stamps over your head, quick messages in bubbles, a chat log, the member
-- list and the warp menu - after the DBFZ and P4A lobbies, in Neon Row's colours.
--
-- Everything sent is an index into a fixed list (Data/Plaza stamps and messages), so nothing here
-- is free text and nothing needs filtering; the server checks it and passes it to the people in the
-- same place. What arrives is kept in `overheads` (what to draw over whose head, since when) for
-- Plaza2D to draw, and in the log.
--
-- Keys, while the lobby is up: T stamps, Y quick messages, P people, M the roof map; 1-9 and 0 pick
-- from an open list. (Tab and Escape belong to Roblox.) Every key has a button, for touch.

local Shared = game:GetService("ReplicatedStorage").Shared
local PLAZA: any = require(Shared.Data.Plaza)
local Canvas2D = require(script.Parent.Canvas2D)
local KitPortrait = require(script.Parent.KitPortrait)
local PlazaArt = require(script.Parent.PlazaArt)

local LobbySocial = {}
LobbySocial.__index = LobbySocial

LobbySocial.STAMP_SECONDS = 2.6
LobbySocial.SAY_SECONDS = 4.5
LobbySocial.LOG_LINES = 6

local INK = Color3.fromRGB(14, 11, 22)
local PANEL = Color3.fromRGB(28, 24, 44)
local PANEL2 = Color3.fromRGB(44, 38, 66)
local TEXT = Color3.fromRGB(236, 232, 222)
local DIM = Color3.fromRGB(150, 146, 172)
local PINK = Color3.fromRGB(255, 79, 163)
local CYAN = Color3.fromRGB(79, 227, 255)
local AMBER = Color3.fromRGB(255, 181, 71)

local function corner(parent: Instance, px: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = parent
end

local function button(parent: Instance, name: string, text: string, onClick: () -> (), colour: Color3?): TextButton
	local b = Instance.new("TextButton")
	b.Name, b.Text, b.Font, b.TextSize = name, text, Enum.Font.GothamBold, 14
	b.BackgroundColor3, b.TextColor3, b.BorderSizePixel, b.AutoButtonColor = colour or PANEL2, TEXT, 0, true
	b.Parent = parent
	corner(b, 6)
	b.Activated:Connect(onClick)
	return b
end

local function label(parent: Instance, name: string, text: string, size: number, colour: Color3?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name, t.Text, t.Font, t.TextSize = name, text, Enum.Font.GothamBold, size
	t.BackgroundTransparency, t.TextColor3, t.TextXAlignment, t.TextWrapped = 1, colour or TEXT, Enum.TextXAlignment.Left, true
	t.Parent = parent
	return t
end

local function panel(parent: Instance, name: string, title: string, w: number, h: number): Frame
	local f = Instance.new("Frame")
	f.Name, f.BackgroundColor3, f.BackgroundTransparency, f.BorderSizePixel = name, PANEL, 0.05, 0
	f.AnchorPoint = Vector2.new(1, 1)
	f.Position, f.Size = UDim2.new(1, -16, 1, -96), UDim2.fromOffset(w, h)
	f.Visible = false
	f.Parent = parent
	corner(f, 10)
	local s = Instance.new("UIStroke")
	s.Color, s.Thickness, s.Parent = PINK, 2, f
	local t = label(f, "Title", title, 16, PINK)
	t.Position, t.Size = UDim2.fromOffset(14, 8), UDim2.new(1, -28, 0, 22)
	return f
end

-- `opts.send(msg)` goes to the Social remote, `opts.requestMembers()` asks who is here,
-- `opts.warp(id)` moves you to a warp point, `opts.warpTo(member)` next to someone,
-- `opts.clock()` is the time.
function LobbySocial.new(parent: Instance, opts: any): any
	local self: any = setmetatable({}, LobbySocial)
	self.opts = opts
	self.clock = opts.clock or os.clock
	self.overheads = {}                 -- userId -> { kind, id?, index?, at }
	self.log = {}                       -- { text, colour, at }
	self.members = {}
	self.localId = opts.localId or 0
	self.enabled = false

	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "BlockfallSocial", false, true, 13
	gui.Enabled = false
	gui.Parent = parent
	self.gui = gui

	-- The button bar, bottom right.
	local bar = Instance.new("Frame")
	bar.Name, bar.BackgroundTransparency, bar.AnchorPoint = "Bar", 1, Vector2.new(1, 1)
	bar.Position, bar.Size = UDim2.new(1, -16, 1, -44), UDim2.fromOffset(4 * 96 - 6, 40)
	bar.Parent = gui
	local specs: { { any } } = { { "Stamps", "STAMP  T", PINK }, { "Say", "SAY  Y", CYAN }, { "People", "PEOPLE  P", AMBER }, { "Map", "MAP  M", Color3.fromRGB(98, 224, 138) } }
	for i, sp in specs do
		local b = button(bar, "Open" .. sp[1], sp[2], function() self:toggle(sp[1]) end, PANEL)
		b.Position, b.Size, b.TextColor3 = UDim2.fromOffset((i - 1) * 96, 0), UDim2.fromOffset(90, 40), sp[3]
	end
	self.bar = bar

	-- Stamps: eight tiles with the icon drawn in each.
	local stamps = panel(gui, "Stamps", "STAMPS", 4 * 74 + 20, 2 * 74 + 44)
	for i, st in PLAZA.stamps do
		local b = button(stamps, "Stamp_" .. st.id, "", function() self:stamp(st.id) end, PANEL2)
		b.Position, b.Size = UDim2.fromOffset(10 + ((i - 1) % 4) * 74, 36 + math.floor((i - 1) / 4) * 74), UDim2.fromOffset(68, 68)
		local holder = Instance.new("Frame")
		holder.Name, holder.BackgroundTransparency, holder.Size, holder.Parent = "Icon", 1, UDim2.fromScale(1, 1), b
		local c = Canvas2D.inFrame(holder)
		local prop = PlazaArt.stamp(st)
		local k = math.floor(44 / math.max(prop.w, prop.h))
		-- y up, origin at the tile's bottom-left, as the world is: sprites assume it.
		Canvas2D.setTransform(c, 1, 0, 0, -1, 0, 68)
		Canvas2D.sprite(c, "stamp|" .. st.id, prop.rects, 34 - prop.w * k / 2, 34 + prop.h * k / 2, k, k, prop.w, prop.h)
		local n = label(b, "Key", tostring(i), 11, DIM)
		n.Position, n.Size = UDim2.fromOffset(4, 2), UDim2.fromOffset(14, 14)
	end
	self.stampsPanel = stamps

	-- Quick messages.
	local say = panel(gui, "Say", "SAY", 300, 38 + math.ceil(#PLAZA.messages / 2) * 34 + 8)
	for i, m in PLAZA.messages do
		local key = if i <= 9 then tostring(i) elseif i == 10 then "0" else ""
		local b = button(say, "Say_" .. i, (if key ~= "" then key .. "  " else "") .. m, function() self:say(i) end, PANEL2)
		b.TextSize, b.TextXAlignment = 13, Enum.TextXAlignment.Left
		b.Position, b.Size = UDim2.fromOffset(10 + ((i - 1) % 2) * 142, 36 + math.floor((i - 1) / 2) * 34), UDim2.fromOffset(136, 30)
	end
	self.sayPanel = say

	-- People.
	local people = panel(gui, "People", "WHO IS HERE", 340, 380)
	local list = Instance.new("ScrollingFrame")
	list.Name, list.BackgroundTransparency, list.BorderSizePixel = "List", 1, 0
	list.Position, list.Size = UDim2.fromOffset(8, 36), UDim2.new(1, -16, 1, -44)
	list.AutomaticCanvasSize, list.CanvasSize, list.ScrollBarThickness = Enum.AutomaticSize.Y, UDim2.new(), 5
	list.Parent = people
	local layout = Instance.new("UIListLayout")
	layout.Padding, layout.SortOrder, layout.Parent = UDim.new(0, 6), Enum.SortOrder.LayoutOrder, list
	self.peoplePanel, self.peopleList = people, list

	-- The roof map.
	local map = panel(gui, "Map", "ROOF MAP  ·  WARP", 300, 38 + #PLAZA.market.warps * 44 + 8)
	for i, w in PLAZA.market.warps do
		local b = button(map, "Warp_" .. w.id, `{i}  {w.name}`, function() self:warp(w.id) end, PANEL2)
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.Position, b.Size = UDim2.fromOffset(10, 36 + (i - 1) * 44), UDim2.new(1, -20, 0, 38)
	end
	self.mapPanel = map

	-- The log, bottom left.
	local log = Instance.new("Frame")
	log.Name, log.BackgroundColor3, log.BackgroundTransparency, log.BorderSizePixel = "Log", INK, 0.35, 0
	log.AnchorPoint, log.Position, log.Size = Vector2.new(0, 1), UDim2.new(0, 16, 1, -96), UDim2.fromOffset(330, LobbySocial.LOG_LINES * 20 + 12)
	log.Parent = gui
	corner(log, 8)
	self.logFrame = log
	self.logLines = {}
	for i = 1, LobbySocial.LOG_LINES do
		local l = label(log, "Line" .. i, "", 13)
		l.Position, l.Size = UDim2.fromOffset(10, 6 + (i - 1) * 20), UDim2.new(1, -20, 0, 20)
		l.TextTruncate = Enum.TextTruncate.AtEnd
		self.logLines[i] = l
	end
	self.panels = { Stamps = stamps, Say = say, People = people, Map = map }
	self:renderLog()
	return self
end

-- ------------------------------------------------------------------ panels ----
function LobbySocial.setEnabled(self: any, on: boolean)
	self.enabled = on
	self.gui.Enabled = on
	if not on then self:closeAll() end
end

function LobbySocial.open(self: any): string?
	for name, p in self.panels do
		if p.Visible then return name end
	end
	return nil
end

function LobbySocial.closeAll(self: any)
	for _, p in self.panels do p.Visible = false end
end

function LobbySocial.toggle(self: any, name: string)
	if not self.enabled then return end
	local was = self.panels[name].Visible
	self:closeAll()
	self.panels[name].Visible = not was
	if name == "People" and not was and self.opts.requestMembers then self.opts.requestMembers() end
end

-- ------------------------------------------------------------------ sending ----
function LobbySocial.stamp(self: any, id: string)
	self.opts.send({ kind = "stamp", id = id })
	self:closeAll()
end

function LobbySocial.say(self: any, index: number)
	self.opts.send({ kind = "say", index = index })
	self:closeAll()
end

function LobbySocial.warp(self: any, id: string)
	if self.opts.warp and self.opts.warp(id) then self:closeAll() end
end

-- Keys. Returns true when it used the key.
function LobbySocial.key(self: any, code: any): boolean
	if not self.enabled then return false end
	local open = self:open()
	local digits = { One = 1, Two = 2, Three = 3, Four = 4, Five = 5, Six = 6, Seven = 7, Eight = 8, Nine = 9, Zero = 10 }
	local name = if typeof(code) == "EnumItem" then code.Name else tostring(code)
	local n = digits[name]
	if n and open then
		if open == "Stamps" and PLAZA.stamps[n] then self:stamp(PLAZA.stamps[n].id); return true end
		if open == "Say" and PLAZA.messages[n] then self:say(n); return true end
		if open == "Map" and PLAZA.market.warps[n] then self:warp(PLAZA.market.warps[n].id); return true end
		return false
	end
	if name == "T" then self:toggle("Stamps")
	elseif name == "Y" then self:toggle("Say")
	elseif name == "P" then self:toggle("People")
	elseif name == "M" then self:toggle("Map")
	else return false end
	return true
end

-- ------------------------------------------------------------------ receiving ----
function LobbySocial.onEvent(self: any, ev: any)
	if type(ev) ~= "table" or type(ev.userId) ~= "number" then return end
	local now = self.clock()
	local who = if ev.userId == self.localId then "You" else tostring(ev.name or "?")
	if ev.kind == "stamp" then
		local stamp
		for _, st in PLAZA.stamps do if st.id == ev.id then stamp = st end end
		if not stamp then return end
		self.overheads[ev.userId] = { kind = "stamp", id = ev.id, at = now }
		self:addLog(`{who}  [{stamp.name}]`, PINK)
	elseif ev.kind == "say" then
		local text = PLAZA.messages[ev.index]
		if not text then return end
		self.overheads[ev.userId] = { kind = "say", index = ev.index, text = text, at = now }
		self:addLog(`{who}: {text}`, if ev.userId == self.localId then CYAN else TEXT)
	end
end

function LobbySocial.addLog(self: any, text: string, colour: Color3)
	table.insert(self.log, { text = text, colour = colour, at = self.clock() })
	while #self.log > LobbySocial.LOG_LINES do table.remove(self.log, 1) end
	self:renderLog()
end

function LobbySocial.renderLog(self: any)
	local n = #self.log
	for i, l in self.logLines do
		local entry = self.log[n - LobbySocial.LOG_LINES + i]
		l.Text = if entry then entry.text else ""
		l.TextColor3 = if entry then entry.colour else TEXT
	end
	self.logFrame.Visible = n > 0
end

-- What is over someone's head right now, or nil once it has had its time.
function LobbySocial.overhead(self: any, userId: number): any
	local o = self.overheads[userId]
	if not o then return nil end
	local age = self.clock() - o.at
	local life = if o.kind == "stamp" then LobbySocial.STAMP_SECONDS else LobbySocial.SAY_SECONDS
	if age > life then
		self.overheads[userId] = nil
		return nil
	end
	return o, age, life
end

function LobbySocial.setMembers(self: any, list: any)
	if type(list) ~= "table" then return end
	self.members = list
	for _, child in self.peopleList:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end
	for i, m in list do
		local row = Instance.new("Frame")
		row.Name, row.BackgroundColor3, row.BorderSizePixel, row.LayoutOrder = "Member_" .. tostring(m.userId), PANEL2, 0, i
		row.Size, row.Parent = UDim2.new(1, -8, 0, 48), self.peopleList
		corner(row, 6)
		local face = Instance.new("Frame")
		face.Name, face.BackgroundTransparency, face.Position, face.Size, face.Parent = "Face", 1, UDim2.fromOffset(4, 2), UDim2.fromOffset(44, 44), row
		if type(m.avatar) == "string" and string.sub(m.avatar, 1, 2) == "k1" then
			KitPortrait.draw(Canvas2D.inFrame(face), m.avatar, "head", 44, 44)
		end
		local name = label(row, "Name", (if m.userId == self.localId then m.name .. "  (you)" else tostring(m.name)), 14)
		name.Position, name.Size = UDim2.fromOffset(54, 4), UDim2.new(1, -140, 0, 20)
		local where = label(row, "Where", tostring(m.where or ""), 12, if m.place == "fight" then PINK elseif m.place == "room" then AMBER else DIM)
		where.Position, where.Size = UDim2.fromOffset(54, 24), UDim2.new(1, -140, 0, 18)
		if m.place == "market" and m.userId ~= self.localId and m.x then
			local go = button(row, "WarpTo", "WARP", function()
				if self.opts.warpTo and self.opts.warpTo(m) then self:closeAll() end
			end, Color3.fromRGB(40, 90, 110))
			go.Position, go.Size = UDim2.new(1, -78, 0, 8), UDim2.fromOffset(70, 32)
		end
	end
end

return LobbySocial
