--!strict
-- The lobby's bar: PLAY (pick 1v1, 2v2 or 3v3 and wait in the queue - Rooms.queue - while you walk
-- the roofs) and the roof map's warps. While queued, a card at the top says what you are waiting
-- for, with CANCEL and FILL WITH BOTS.
--
-- (It was also the lobby's stamps, quick messages and member list; the owner had those taken out,
-- 2026-10-29, when PLAY replaced the arcade and the fighters' gates.)
--
-- Keys, while the lobby is up: M the roof map; 1-9 pick from an open list. Every key has a button.

local Shared = game:GetService("ReplicatedStorage").Shared
local Plaza = require(Shared.Plaza)
local Realms = require(Shared.Realms)
local Ui = require(script.Parent.Ui)

local PLAZA: any = Plaza.DATA      -- the Roblox lobby's market (Plaza.luau), not the web's

local LobbySocial = {}
LobbySocial.__index = LobbySocial

-- Room at the right end of the bottom row for the plaza's buttons (Plaza2D.CHARACTER_W): one wide
-- CHARACTER button, or in a light theme the row of three square icon buttons.
LobbySocial.RIGHT_GAP = if Ui.lightPanels() then 3 * 76 + 3 * Ui.GAP else 168 + 8

local LIGHT = Ui.lightPanels()
local PANEL2 = if LIGHT then Ui.PANEL2 else Color3.fromRGB(46, 52, 63)
local ON_PANEL = if LIGHT then Ui.TEXT else Color3.fromRGB(230, 225, 214)

-- The bar: { panel, key, word, colour, icon }.
local SPECS: { { any } } = {
	{ "Play", "", "PLAY", Color3.fromRGB(228, 59, 68), "swords" },
	{ "Map", "M", "MAP", Color3.fromRGB(62, 137, 72), "map" },
}
-- a bar button's side in a light theme (square icon buttons beside the plaza's; Plaza2D.ICON)
LobbySocial.ICON = 76
LobbySocial.BAR_W = if LIGHT then #SPECS * (LobbySocial.ICON + Ui.GAP) - Ui.GAP else #SPECS * 124 - 8
-- the formats PLAY offers, in order, with what each needs
LobbySocial.FORMATS = {
	{ id = "Duel", word = "1v1", note = "One on one", colour = Ui.GOLD },
	{ id = "Doubles", word = "2v2", note = "Two teams of two", colour = Ui.BLUE },
	{ id = "Triples", word = "3v3", note = "Two teams of three", colour = Ui.PINK },
}
-- a list row's words, in from its edge (they sat against the row's left side)
LobbySocial.ROW_PAD = 14

-- A list row inside a panel: the kit's bevelled block, its words dark and bare on the pale face.
local function row(parent: Instance, name: string, text: string, onClick: () -> (), colour: Color3?): TextButton
	local b = Ui.button(parent, text, colour or PANEL2, onClick, { font = Ui.LABEL, size = 13, small = true,
		textColour = if colour == nil or Ui.light(colour) > 0.62 then ON_PANEL else nil })
	b.Name = name
	b.TextXAlignment = Enum.TextXAlignment.Left
	Ui.make("UIPadding", b, { PaddingLeft = UDim.new(0, LobbySocial.ROW_PAD), PaddingRight = UDim.new(0, LobbySocial.ROW_PAD) })
	return b
end

-- A panel over the bar: the kit's card, with a band in its button's colour and its title.
local function panel(parent: Instance, name: string, title: string, w: number, h: number, colour: Color3): Frame
	local f = Ui.panel(parent, name, colour, title, 30)
	f.AnchorPoint = Vector2.new(1, 1)
	-- (above the bar's real height: the square buttons stand 76 px)
	f.Position, f.Size = UDim2.new(1, -16, 1, if LIGHT then -(10 + LobbySocial.ICON + 8) else -62), UDim2.fromOffset(w, h)
	f.Visible = false
	return f
end

-- `opts.warp(id)` moves you to a warp point; `opts.queue(format)`, `opts.unqueue()` and
-- `opts.fill()` go to the room remote.
function LobbySocial.new(parent: Instance, opts: any): any
	local self: any = setmetatable({}, LobbySocial)
	self.opts = opts
	self.enabled = false
	self.queue = { queued = false }

	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "BlockfallSocial", false, true, 13
	gui.Enabled = false
	gui.Parent = parent
	self.gui = gui

	-- The bar, bottom right.
	local bar = Instance.new("Frame")
	bar.Name, bar.BackgroundTransparency, bar.AnchorPoint = "Bar", 1, Vector2.new(1, 1)
	bar.Position, bar.Size = UDim2.new(1, -16 - LobbySocial.RIGHT_GAP, 1, -10),
		UDim2.fromOffset(LobbySocial.BAR_W, if LIGHT then LobbySocial.ICON else 42)
	bar.Parent = gui
	for i, sp in SPECS do
		local open = function() self:toggle(sp[1]) end
		local key = if sp[2] ~= "" then sp[2] else nil
		local b = if LIGHT then Ui.iconButton(bar, sp[5], sp[3], sp[4], open, LobbySocial.ICON, key)
			else Ui.keyButton(bar, sp[2], sp[3], sp[4], open, 42, { size = 12 })
		b.Name = "Open" .. sp[1]
		if LIGHT then b.Position = UDim2.fromOffset((i - 1) * (LobbySocial.ICON + Ui.GAP), 0)
		else b.Position, b.Size = UDim2.fromOffset((i - 1) * 124, 0), UDim2.fromOffset(116, 42) end
	end
	self.bar = bar

	-- PLAY: the three formats, a big button each.
	-- (a kit gap between buttons, past their strokes: 8 px apart, their outlines were 2 px apart)
	local step = 48 + Ui.GAP + 6
	local play = panel(gui, "Play", "PLAY  ·  FIND A FIGHT", 300, 38 + #LobbySocial.FORMATS * step - Ui.GAP, SPECS[1][4])
	for i, f in LobbySocial.FORMATS do
		local b = Ui.button(play, `{f.word}   {f.note}`, f.colour, function() self:choose(f.id) end, { size = 16 })
		b.Name = "Format_" .. f.id
		b.Position, b.Size = UDim2.fromOffset(13, 38 + (i - 1) * step), UDim2.new(1, -26, 0, 48)
	end
	self.playPanel = play

	-- The roof map.
	local map = panel(gui, "Map", "BAZAAR MAP  ·  WARP", 300, 38 + #PLAZA.market.warps * 44 + 8, SPECS[2][4])
	for i, w in PLAZA.market.warps do
		local b = row(map, "Warp_" .. w.id, `{i}   {Realms.place(w.id, w.name)}`, function() self:warp(w.id) end)
		b.Position, b.Size = UDim2.fromOffset(10, 36 + (i - 1) * 44), UDim2.new(1, -20, 0, 38)
	end
	self.mapPanel = map

	-- The queue's card, top centre: what you are waiting for, CANCEL and FILL WITH BOTS.
	local card = Ui.card(gui, "Queue", Ui.INDIGO)
	card.AnchorPoint, card.Position, card.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 12), UDim2.fromOffset(440, 96)
	card.Visible = false
	local title = Ui.faceText(card, "", 20, Ui.INDIGO)
	title.Name, title.Position, title.Size = "Title", UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 26)
	local count = Ui.faceText(card, "", 13, Ui.INDIGO, Ui.LABEL)
	count.Name, count.Position, count.Size = "Count", UDim2.fromOffset(12, 32), UDim2.new(1, -24, 0, 18)
	local cancel = Ui.button(card, "CANCEL", Ui.PANEL2, function() self:cancel() end, { size = 14 })
	cancel.Name, cancel.Position, cancel.Size = "Cancel", UDim2.fromOffset(14, 56), UDim2.fromOffset(150, 30)
	local fillX = 14 + 150 + Ui.GAP + 6
	local fill = Ui.button(card, "FILL WITH BOTS", Ui.GREEN, function() self:fill() end, { size = 14 })
	fill.Name, fill.Position, fill.Size = "Fill", UDim2.fromOffset(fillX, 56), UDim2.new(1, -fillX - 14, 0, 30)
	self.queueCard, self.queueTitle, self.queueCount = card, title, count

	self.panels = { Play = play, Map = map }
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

-- Is a panel up? (The plaza's prompt steps aside under one: they share the bottom right.)
function LobbySocial.anyOpen(self: any): boolean
	for _, p in self.panels do if p.Visible then return true end end
	return false
end

function LobbySocial.toggle(self: any, name: string)
	if not self.enabled then return end
	local was = self.panels[name].Visible
	self:closeAll()
	self.panels[name].Visible = not was
end

-- ------------------------------------------------------------------ PLAY ----
function LobbySocial.choose(self: any, format: string)
	if self.opts.queue then self.opts.queue(format) end
	self:closeAll()
end

function LobbySocial.cancel(self: any)
	if self.opts.unqueue then self.opts.unqueue() end
end

function LobbySocial.fill(self: any)
	if self.opts.fill then self.opts.fill() end
end

-- What the server says about your place in the queue (Rooms.queueView).
function LobbySocial.setQueue(self: any, view: any)
	if type(view) ~= "table" then return end
	self.queue = view
	local on = view.queued == true
	self.queueCard.Visible = on
	if on then
		self.queueTitle.Text = `FINDING A {view.name or "FIGHT"}`
		local waiting, formAt = view.waiting or 1, view.formAt or 2
		-- (how many wait, and when a room opens: at all but one, and the last place is the bot vote's)
		self.queueCount.Text = if waiting >= formAt then "A room is opening..."
			else `{waiting} waiting  ·  a room opens at {formAt}  ·  or fill it with bots`
	end
end

function LobbySocial.warp(self: any, id: string)
	if self.opts.warp and self.opts.warp(id) then self:closeAll() end
end

-- Keys. Returns true when it used the key.
function LobbySocial.key(self: any, code: any): boolean
	if not self.enabled then return false end
	local open = self:open()
	local digits = { One = 1, Two = 2, Three = 3, Four = 4, Five = 5, Six = 6, Seven = 7, Eight = 8, Nine = 9 }
	local name = if typeof(code) == "EnumItem" then code.Name else tostring(code)
	local n = digits[name]
	if n and open then
		if open == "Map" and PLAZA.market.warps[n] then self:warp(PLAZA.market.warps[n].id); return true end
		if open == "Play" and LobbySocial.FORMATS[n] then self:choose(LobbySocial.FORMATS[n].id); return true end
		return false
	end
	if name == "M" then self:toggle("Map")
	else return false end
	return true
end

return LobbySocial
