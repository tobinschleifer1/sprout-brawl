--!strict
-- The lobby's bar: PLAY (pick a fight - 1v1, 2v2 or 3v3, a free-for-all of 3, 4 or 6, or Ranked -
-- and wait in the queue - Rooms.queue - while you walk the roofs) and the roof map's warps. While
-- queued, a card at the top says what you are waiting for, with CANCEL and FILL WITH BOTS. PLAY
-- also shows your level and rank (Progression); Ranked stays locked below RANKED_LEVEL.
--
-- (It was also the lobby's stamps, quick messages and member list; the owner had those taken out,
-- 2026-10-29, when PLAY replaced the arcade and the fighters' gates.)
--
-- Keys, while the lobby is up: M the roof map; 1-9 pick from an open list. Every key has a button.

local Shared = game:GetService("ReplicatedStorage").Shared
local Plaza = require(Shared.Plaza)
local Realms = require(Shared.Realms)
local Progression = require(Shared.Progression)
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
local SUB = if LIGHT then Ui.SUB else Color3.fromRGB(170, 176, 190)

-- The bar: { panel, key, word, colour, icon }.
local SPECS: { { any } } = {
	{ "Play", "", "PLAY", Color3.fromRGB(228, 59, 68), "swords" },
	{ "Map", "M", "MAP", Color3.fromRGB(62, 137, 72), "map" },
}
-- a bar button's side in a light theme (square icon buttons beside the plaza's; Plaza2D.ICON)
LobbySocial.ICON = 76
LobbySocial.BAR_W = if LIGHT then #SPECS * (LobbySocial.ICON + Ui.GAP) - Ui.GAP else #SPECS * 124 - 8
-- the fights PLAY offers, in order (and by digit), in three sections
LobbySocial.FORMATS = {
	{ id = "Duel", word = "1v1", section = "TEAMS", colour = Ui.GOLD },
	{ id = "Doubles", word = "2v2", section = "TEAMS", colour = Ui.BLUE },
	{ id = "Triples", word = "3v3", section = "TEAMS", colour = Ui.PINK },
	{ id = "FFA3", word = "3 WAY", section = "FREE FOR ALL", colour = Ui.TEAL },
	{ id = "FFA4", word = "4 WAY", section = "FREE FOR ALL", colour = Ui.SKY },
	{ id = "FFA6", word = "6 WAY", section = "FREE FOR ALL", colour = Ui.VIOLET },
	{ id = "Ranked", word = "RANKED  ·  1v1", section = "RANKED  ·  THE TOURNAMENT", colour = Ui.ORANGE,
		level = Progression.RANKED_LEVEL },
}
LobbySocial.PLAY_W = 340
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
	self.now = os.clock          -- (replaceable, for the tests)
	self.progress = { level = 1, into = 0, need = Progression.need(1), points = 0, tier = 1 }

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

	-- PLAY: your level and rank, then each section's buttons side by side.
	-- (a kit gap between buttons, past their strokes: 8 px apart, their outlines were 2 px apart)
	local gap, inner = Ui.GAP + 6, LobbySocial.PLAY_W - 26
	local y = 38
	local playH = 0
	local play = panel(gui, "Play", "PLAY  ·  FIND A FIGHT", LobbySocial.PLAY_W, 10, SPECS[1][4])
	local level = Ui.text(play, "", 14, ON_PANEL, Ui.LABEL, true)
	level.Name, level.Position, level.Size = "Level", UDim2.fromOffset(13, y), UDim2.new(1, -26, 0, 18)
	level.TextXAlignment = Enum.TextXAlignment.Left
	local rank = Ui.text(play, "", 14, ON_PANEL, Ui.LABEL, true)
	rank.Name, rank.Position, rank.Size = "Rank", UDim2.fromOffset(13, y), UDim2.new(1, -26, 0, 18)
	rank.TextXAlignment = Enum.TextXAlignment.Right
	y += 22
	local track = Ui.make("Frame", play, { Name = "XpBar", BackgroundColor3 = Ui.INK, BorderSizePixel = 0 })
	track.Position, track.Size = UDim2.fromOffset(13, y), UDim2.new(1, -26, 0, 8)
	local fillBar = Ui.make("Frame", track, { Name = "Fill", BackgroundColor3 = Ui.GOLD, BorderSizePixel = 0 })
	fillBar.Position, fillBar.Size = UDim2.fromOffset(1, 1), UDim2.new(0, 0, 1, -2)
	y += 8 + 10
	self.levelText, self.rankText, self.xpFill = level, rank, fillBar
	self.formatButtons = {}
	local i = 1
	while i <= #LobbySocial.FORMATS do
		local section = LobbySocial.FORMATS[i].section
		local group = {}
		while LobbySocial.FORMATS[i] and LobbySocial.FORMATS[i].section == section do
			table.insert(group, LobbySocial.FORMATS[i]); i += 1
		end
		local head = Ui.text(play, section, 12, SUB, Ui.LABEL, true)
		head.Name, head.Position, head.Size = "Section", UDim2.fromOffset(13, y), UDim2.new(1, -26, 0, 16)
		head.TextXAlignment = Enum.TextXAlignment.Left
		y += 20
		local w = math.floor((inner - (#group - 1) * gap) / #group)
		for k, f in group do
			local b = Ui.button(play, f.word, f.colour, function() self:choose(f.id) end, { size = 16 })
			b.Name = "Format_" .. f.id
			b.Position, b.Size = UDim2.fromOffset(13 + (k - 1) * (w + gap), y), UDim2.fromOffset(w, 44)
			self.formatButtons[f.id] = b
		end
		y += 44 + gap
	end
	-- INVITE FRIENDS: Roblox's invite prompt (retention plan, step 1)
	local invite = Ui.button(play, "INVITE FRIENDS", Ui.PURPLE, function() if self.opts.invite then self.opts.invite() end end, { size = 15 })
	invite.Name = "Invite"
	invite.Position, invite.Size = UDim2.fromOffset(13, y), UDim2.new(1, -26, 0, 36)
	y += 36 + gap
	-- why the last choice was refused (Ranked below its level, or the server's reason)
	local note = Ui.text(play, "", 12, SUB, Ui.LABEL, true)
	note.Name, note.Position, note.Size = "Note", UDim2.fromOffset(13, y - gap + 6), UDim2.new(1, -26, 0, 16)
	note.TextXAlignment = Enum.TextXAlignment.Left
	self.note = note
	playH = y - gap + 28
	play.Size = UDim2.fromOffset(LobbySocial.PLAY_W, playH)
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
	self.queueCard, self.queueTitle, self.queueCount, self.fillButton = card, title, count, fill

	self.panels = { Play = play, Map = map }
	self:setProgress(nil)
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
local function formatById(id: string): any
	for _, f in LobbySocial.FORMATS do if f.id == id then return f end end
	return nil
end
function LobbySocial.choose(self: any, format: string)
	local f = formatById(format)
	-- (the server refuses it too: this only says so without the round trip)
	if f and f.level and (self.progress.level or 1) < f.level then
		self.note.Text = `Ranked unlocks at level {f.level}. You are level {self.progress.level or 1}.`
		return
	end
	self.note.Text = ""
	if self.opts.queue then self.opts.queue(format) end
	self:closeAll()
end

-- Your level and rank (Economy.progressView, from EconomyView): the panel's top line and XP bar,
-- and Ranked's button greyed while it is locked.
function LobbySocial.setProgress(self: any, view: any)
	if type(view) == "table" then self.progress = view end
	local p = self.progress
	local level, into, need = p.level or 1, p.into or 0, p.need or 0
	self.levelText.Text = if need > 0 then `LEVEL {level}  ·  {into} / {need} XP` else `LEVEL {level}  ·  MAX`
	self.xpFill.Size = UDim2.new(if need > 0 then math.clamp(into / need, 0, 1) else 1, -2, 1, -2)
	local tier = Progression.TIERS[math.clamp(p.tier or 1, 1, #Progression.TIERS)]
	self.rankText.Text = if level >= Progression.RANKED_LEVEL then `{tier.name}  ·  {p.points or 0} RP` else ""
	for _, f in LobbySocial.FORMATS do
		local b = self.formatButtons[f.id]
		if f.level then
			local open = level >= f.level
			Ui.paint(b, if open then f.colour else PANEL2, if open then Ui.WHITE else ON_PANEL)
			b.Text = if open then f.word else `RANKED  ·  UNLOCKS AT LEVEL {f.level}`
		end
	end
end

-- The server refused a queue (why, as Rooms.queue says it): shown under the buttons.
function LobbySocial.refused(self: any, why: string?)
	if type(why) == "string" and why ~= "" then self.note.Text = why end
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
	-- (the quiet clock restarts when the queue starts, changes format, or someone joins it)
	local was = self.queue
	if view.queued and (not was.queued or was.format ~= view.format or was.waiting ~= view.waiting) then self.queuedAt = self.now() end
	self.quiet = false
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

-- A quiet queue: after QUIET seconds with nobody joining and no room forming, the card says bots are
-- ready and FILL WITH BOTS pulses, so a solo player on a quiet server is never left waiting. Call
-- every frame while the lobby is up.
LobbySocial.QUIET = 20
function LobbySocial.tick(self: any)
	local view = self.queue
	if not view.queued or not self.queuedAt then return end
	local waited = self.now() - self.queuedAt
	if waited < LobbySocial.QUIET or (view.waiting or 1) >= (view.formAt or 2) then return end
	if not self.quiet then
		self.quiet = true
		self.queueCount.Text = "Quiet right now  ·  bots are ready when you are"
	end
	-- (twice a second, between the kit's green and a lighter one)
	Ui.paint(self.fillButton, if math.floor(waited * 2) % 2 == 0 then Ui.GREEN else Ui.shade(Ui.GREEN, 0.3), Ui.WHITE)
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
