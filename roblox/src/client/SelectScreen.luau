--!strict
-- The pre-match select screen: everyone in the room at once, each on their own pedestal, picking
-- a weapon from the roster at the top. Blockfall's own take on the genre's select screen - a grid
-- of round portraits, a pedestal per player with the fighter standing on it and a card of their
-- stats, a ready state, a rules bar - in the game's pixel style. It replaces the room panel.
--
-- Two layers share one layout (SelectScreen.layout, pure): the game's canvas draws the scene - the
-- sky, the portraits (your avatar holding each weapon), the pedestals and the fighters standing on
-- them - and this ScreenGui lays the words, cards and buttons over it. While the screen is open the
-- canvas draws this INSTEAD of the plaza, so it costs nothing on top of what the lobby already did.
--
-- Three pages, one per phase of the room (Rooms.PICK_TIME): PICK, the roster and the pedestals;
-- MAP, a card per arena showing the arena itself, drawn small in its own realm's art, to vote on;
-- RULES, a card per rule set to vote on. The room moves itself on; nobody presses start.
--
-- Empty pedestals offer ADD BOT; a bot's offers REMOVE. Either starts a vote (Rooms.BOT_VOTE_TIME):
-- every player gets YES / NO, and a strict majority of the players in the room decides.
local Shared = game:GetService("ReplicatedStorage").Shared
local Weapons = require(Shared.Weapons)
local Stages = require(Shared.Data.Stages)
local Loadout = require(Shared.Loadout)
local Fighter = require(Shared.Fighter)
local Snapshot = require(Shared.Snapshot)
local Stage = require(Shared.Stage)
local Realms = require(Shared.Realms)
local Rules = require(Shared.Data.Rules)
local Canvas2D = require(script.Parent.Canvas2D)
local Stage2D = require(script.Parent.Stage2D)
local FxArt = require(script.Parent.FxArt)
local Fighter2D = require(script.Parent.Fighter2D)
local HudColors = require(script.Parent.HudColors)
local WeaponStats = require(script.Parent.WeaponStats)
local Ui = require(script.Parent.Ui)

local SelectScreen = {}
SelectScreen.__index = SelectScreen

-- the look is the shared kit's (Ui)
local DISPLAY = Ui.DISPLAY
local INK, PANEL, EDGE, WHITE, DIM = Ui.INK, Ui.PANEL, Ui.EDGE, Ui.WHITE, Ui.DIM
local GOLD, GREEN, RED = Ui.GOLD, Ui.GREEN, Ui.RED
local SLATE = Color3.fromRGB(58, 68, 102)         -- an unchosen chip, an unlit stat block
local STAT_NAMES = { damage = "DMG", defense = "DEF", dexterity = "DEX", speed = "SPD" }
local DIFFICULTIES = { "easy", "normal", "hard" }

-- ------------------------------------------------------------------ layout ----
-- Where everything goes on a W x H screen with `slots` (the room's slot views, in room order).
-- Pure: the canvas and the GUI both read it, so they cannot drift apart. Pedestals are in screen
-- order - team 0 on the left, team 1 on the right, with a gap for the VS between them.
function SelectScreen.layout(W: number, H: number, slots: { any }): any
	local s = math.clamp(math.min(W / 1280, H / 720), 0.55, 1.4)
	-- a wide, short screen (a phone on its side) takes the roster in one row, leaving the height for
	-- the fighters; anything squarer takes two rows. By the weapon count, not a fixed six: the
	-- thirteenth weapon spilled onto a third row and the fighters shrank under it.
	local count = #Weapons.LIST
	local perRow = if W / H > 1.9 or H < 520 then count else math.ceil(count / 2)
	local cell = math.floor(math.clamp(math.min(W * (0.064 - 0.001 * perRow), H * 0.1), 34, 84))
	local gap = math.floor(cell * 0.22)
	local rosterW = perRow * cell + (perRow - 1) * gap
	local rosterTop = math.floor(84 * s)
	local roster = {}
	for i = 1, #Weapons.LIST do
		local row, col = (i - 1) // perRow, (i - 1) % perRow
		-- (each row centred, the short last one too)
		local inRow = math.min(perRow, #Weapons.LIST - row * perRow)
		local rowW = inRow * cell + (inRow - 1) * gap
		roster[i] = { id = Weapons.LIST[i].id, x = W / 2 - rowW / 2 + col * (cell + gap) + cell / 2,
			y = rosterTop + row * (cell + gap + math.floor(14 * s)) + cell / 2 }
	end
	local rows = math.ceil(#Weapons.LIST / perRow)
	local rosterBottom = rosterTop + rows * cell + (rows - 1) * gap + math.floor(14 * s) * rows
	-- pedestals: team 0 then team 1
	local order = {}
	for i, slot in slots do if (slot.team or 0) == 0 then table.insert(order, i) end end
	for i, slot in slots do if (slot.team or 0) ~= 0 then table.insert(order, i) end end
	local n = math.max(1, #order)
	local buttonsY = H - math.floor(62 * s)
	local cardH = math.floor(math.clamp(H * 0.24, 96, 190))
	local cardY = buttonsY - math.floor(18 * s) - cardH
	local vsGap = math.floor(56 * s)
	local cardW = math.floor(math.min(250 * s, (W - 40 - vsGap) / n - 14))
	local total = n * cardW + (n - 1) * 14 + vsGap
	local x = W / 2 - total / 2
	local fighterH = math.max(40, cardY - math.floor(26 * s) - (rosterBottom + math.floor(18 * s)))
	local pedestals = {}
	for k, i in order do
		if k > 1 and (slots[order[k - 1]].team or 0) ~= (slots[i].team or 0) then x += vsGap end
		table.insert(pedestals, { slot = i, team = slots[i].team or 0, x = x, cardY = cardY, cardW = cardW, cardH = cardH,
			cx = x + cardW / 2, plinthY = cardY - math.floor(2 * s), plinthW = cardW * 0.8, plinthH = math.floor(30 * s),
			fighterH = math.min(fighterH, cardW * 1.15) })
		x += cardW + 14
	end
	local vsX = nil
	for k = 2, #pedestals do
		if pedestals[k].team ~= pedestals[k - 1].team then vsX = (pedestals[k - 1].x + pedestals[k - 1].cardW + pedestals[k].x) / 2 end
	end
	-- the vote pages: a band for the cards between the title and the strip of who has voted
	local voteTop = math.floor(126 * s)
	local stripY = buttonsY - math.floor(46 * s)
	local area = stripY - math.floor(12 * s) - voteTop
	-- the map cards: every arena and Random, five to a row, each a 16:9 picture with its name under it
	local ids = {}
	for _, st in Stages.LIST do table.insert(ids, st.id) end
	table.insert(ids, "Random")
	local cols = 5
	local rowsN = math.ceil(#ids / cols)
	local nameH = math.floor(18 * s)
	local mapW = math.floor(math.min((W - 60) / cols - 14, ((area - (rowsN - 1) * 10) / rowsN - nameH) * 16 / 9))
	local mapH = math.floor(mapW * 9 / 16)
	local gridW = cols * mapW + (cols - 1) * 14
	local gridH = rowsN * (mapH + nameH) + (rowsN - 1) * 10
	local gridTop = voteTop + math.max(0, (area - gridH) / 2)
	local maps = {}
	for i, id in ids do
		local row, col = (i - 1) // cols, (i - 1) % cols
		maps[i] = { id = id, x = W / 2 - gridW / 2 + col * (mapW + 14), y = gridTop + row * (mapH + nameH + 10), w = mapW, h = mapH }
	end
	-- the rule cards: every preset and "keep current", in a row
	local rules = {}
	local rids = {}
	for _, preset in Rules.presets do table.insert(rids, preset.id) end
	table.insert(rids, "current")
	local ruleW = math.floor(math.min(260 * s, (W - 60) / #rids - 16))
	local ruleH = math.floor(math.min(area, 360 * s))
	local rowW = #rids * ruleW + (#rids - 1) * 16
	for i, id in rids do
		rules[i] = { id = id, x = W / 2 - rowW / 2 + (i - 1) * (ruleW + 16), y = voteTop, w = ruleW, h = ruleH,
			panelH = math.min(ruleH * 0.75, math.floor(196 * s)) }
	end
	return { s = s, cell = cell, roster = roster, rosterBottom = rosterBottom, pedestals = pedestals, vsX = vsX,
		buttonsY = buttonsY, W = W, H = H, maps = maps, nameH = nameH, rules = rules, voteTop = voteTop, stripY = stripY }
end

-- ------------------------------------------------------------------ gui helpers ----
local make, corner, stroke, text = Ui.make, Ui.corner, Ui.stroke, Ui.text
-- `small` buttons (the difficulty chips) skip the text outline, which fills small letters in
local function button(parent: Instance, value: string, colour: Color3, onClick: () -> (), small: boolean?): any
	return Ui.button(parent, value, colour, onClick, { small = small })
end
-- A stat block: a square of colour with a lit top row and a shadowed bottom row, like a pixel
-- tile. `lit` is gold, otherwise slate.
local function paintBlock(block: any, lit: boolean)
	local c = if lit then GOLD else SLATE
	block.frame.BackgroundColor3 = c
	block.hi.BackgroundColor3 = Ui.shade(c, if lit then 0.5 else 0.12)
	block.lo.BackgroundColor3 = Ui.shade(c, -0.32)
end
local function hexOf(c: Color3): string
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

-- ------------------------------------------------------------------ construction ----
function SelectScreen.new(parent: Instance): any
	local self: any = setmetatable({ open = false, minimised = false, room = nil, userId = 0, cards = {}, cells = {},
		tags = {}, difficulty = "normal", hand = 1, fighters = {}, chars = {}, voteEndsAt = 0, built = nil,
		now = os.clock }, SelectScreen)        -- (`now` is replaceable, for the tests)
	local gui = make("ScreenGui", parent, { Name = "BlockfallSelect", ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = 15, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	self.gui = gui
	local root = make("Frame", gui, { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	self.root = root
	-- a page per phase; the top bar, the status line and LEAVE / HIDE are shared
	self.pages = {}
	for _, name in { "pick", "map", "rules" } do
		self.pages[name] = make("Frame", root, { Name = "Page" .. name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
	end
	self.pickPage = self.pages.pick

	-- the top bar: the room, and its rules as a pill, with the map and rules boards behind buttons
	self.title = text(root, "MATCH ROOM", 26, WHITE, DISPLAY)
	self.title.Name = "Title"
	self.title.TextXAlignment = Enum.TextXAlignment.Left
	local bar = make("Frame", root, { Name = "RulesBar", BackgroundColor3 = PANEL, BackgroundTransparency = 0.12, BorderSizePixel = 0 })
	corner(bar, 18)
	stroke(bar, EDGE, 2)
	self.bar = bar
	self.rules = text(bar, "", 15, WHITE)
	self.rules.Name = "Rules"

	-- the VS between the teams
	self.vs = text(self.pickPage, "VS", 40, GOLD, DISPLAY)
	self.vs.Name = "VS"

	-- the bottom row
	self.leave = button(root, "LEAVE", Ui.RED, function() self:send("leave") end)
	self.leave.Name = "Leave"
	self.hideButton = button(root, "HIDE", Ui.PANEL2, function() self:minimise() end)
	self.hideButton.Name = "Hide"
	self.ready = button(self.pickPage, "READY", GREEN, function() self:send("ready") end)
	self.ready.Name = "Ready"
	self.status = text(root, "", 14, WHITE)
	-- the vote pages' title and countdown
	self.voteTitle = text(root, "", 30, WHITE, DISPLAY)
	self.voteTitle.Name = "VoteTitle"
	self.clock = text(root, "", 30, GOLD, DISPLAY)
	self.clock.Name = "Clock"
	self.clock.BackgroundTransparency, self.clock.BackgroundColor3 = 0, PANEL
	corner(self.clock, 30)
	stroke(self.clock, GOLD, 3)
	self.mapCards, self.ruleCards, self.chips = {}, {}, {}
	self.status.Name = "Status"

	-- minimised: one button back in, over the plaza
	self.reopen = button(gui, "ROOM ▲", Ui.BLUE, function() self:show() end)
	self.reopen.Name = "Reopen"
	self.reopen.Visible = false
	self.reopen.Size = UDim2.fromOffset(150, 40)
	self.reopen.Position = UDim2.new(0.5, -75, 1, -56)
	return self
end

-- ------------------------------------------------------------------ actions ----
-- A vote page ignores clicks for its first moments: the rules page replaces the map page under the
-- pointer, and in a playtest a click meant for an arena landed on the rule card that took its
-- place, voting for rules nobody had read.
SelectScreen.SETTLE = 0.6
function SelectScreen.settled(self: any): boolean
	return self.now() - (self.phaseShownAt or -math.huge) >= SelectScreen.SETTLE
end

function SelectScreen.send(self: any, action: string, value: any?, slot: number?)
	if self.onAction then
		self.onAction({ action = action, value = value, slot = slot, id = self.room and self.room.id,
			revision = self.room and self.room.revision })
	end
end
function SelectScreen.show(self: any)
	if not self.room or self.room.left then return end
	self.open, self.minimised = true, false
	self.gui.Enabled = true
	self.root.Visible, self.reopen.Visible = true, false
	self.layoutKey = nil       -- relayout against the current screen
	self:render()
end
function SelectScreen.minimise(self: any)
	self.open, self.minimised = false, true
	self.root.Visible, self.reopen.Visible = false, true
	if self.onHide then self.onHide() end
end
function SelectScreen.hide(self: any)
	self.open, self.minimised = false, false
	self.gui.Enabled = false
end
function SelectScreen.waiting(self: any, message: string)
	self.status.Text = message
end

-- A room view from the server. Opening a room (a new id) brings the screen up.
function SelectScreen.update(self: any, room: any, userId: number)
	local entering = not self.room or self.room.left or self.room.id ~= room.id
	local back = not entering and self.room.state == "playing" and room.state == "setup"
	self.room, self.userId = room, userId
	if room.left then self:hide(); self.room = nil; return end
	if room.botVote then self.voteEndsAt = os.clock() + (room.botVote.left or 0) end
	-- a new room, or this one back from a fight (a rematch), brings the screen up
	if (entering or back) and room.state == "setup" then self.hand = 1; self:show() else self:render() end
end

-- Weapon drops: you bring two weapons. A click fills the hand being chosen and moves on to the
-- other, so two clicks pick a pair; clicking one you already hold keeps it and chooses its
-- partner next. (The server keeps the pair two different weapons: see Rooms, "weapon2".)
function SelectScreen.pickWeapon(self: any, id: string)
	local mine = nil
	for _, slot in (self.room and self.room.slots) or {} do if slot.userId == self.userId then mine = slot end end
	if mine and mine.weapon == id then self.hand = 2
	elseif mine and mine.weapon2 == id then self.hand = 1
	else
		self:send(if self.hand == 1 then "weapon" else "weapon2", id)
		self.hand = 3 - self.hand
	end
	self:render()
end

-- ------------------------------------------------------------------ building the layout ----
local function place(o: any, x: number, y: number, w: number, h: number)
	o.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	o.Size = UDim2.fromOffset(math.floor(w + 0.5), math.floor(h + 0.5))
end

-- The roster's portraits and each pedestal's card, rebuilt when the screen or the slot count
-- changes. Everything else in a room update only changes text and colours.
function SelectScreen.build(self: any, L: any)
	for _, c in self.cells do c.button:Destroy() end
	for _, c in self.cards do c.root:Destroy() end
	for _, t in self.tags do t:Destroy() end
	for _, c in self.mapCards do c.button:Destroy(); c.name:Destroy() end
	for _, c in self.ruleCards do c.root:Destroy() end
	for _, c in self.chips do c:Destroy() end
	self.cells, self.cards, self.tags, self.mapCards, self.ruleCards, self.chips = {}, {}, {}, {}, {}, {}
	local s = L.s
	-- below Roblox's top bar where it has one: its menu and chat buttons sit at the top left
	place(self.title, 24 * s, math.max(12 * s, Ui.topInset() + 4), L.W / 2 - 300 * s - 36 * s, 36 * s)
	self.title.TextSize = Ui.px(20 * s)
	self.title.TextScaled = false
	self.title.TextTruncate = Enum.TextTruncate.AtEnd
	place(self.bar, L.W / 2 - 300 * s, 14 * s, 600 * s, 38 * s)
	place(self.rules, 14 * s, 0, 572 * s, 38 * s)
	self.rules.TextSize = Ui.px(15 * s)
	for _, b in { self.leave, self.hideButton, self.ready } do b.TextSize = Ui.px(18 * s) end
	place(self.leave, 24 * s, L.buttonsY, 110 * s, 44 * s)
	place(self.hideButton, 144 * s, L.buttonsY, 96 * s, 44 * s)
	place(self.ready, L.W / 2 - 110 * s, L.buttonsY, 220 * s, 48 * s)
	self.ready.TextSize = Ui.px(26 * s)
	place(self.voteTitle, L.W / 2 - 360 * s, 80 * s, 720 * s, 36 * s)
	self.voteTitle.TextSize = Ui.px(30 * s)
	place(self.clock, L.W - 92 * s, 66 * s, 60 * s, 60 * s)
	self.clock.TextSize = Ui.px(30 * s)
	place(self.status, L.W / 2 - 400 * s, 56 * s, 800 * s, 18 * s)
	self.status.TextSize = Ui.px(14 * s)
	if L.vsX then place(self.vs, L.vsX - 40 * s, L.pedestals[1].cardY + 20 * s, 80 * s, 50 * s); self.vs.TextSize = Ui.px(36 * s) end
	self.vs.Visible = L.vsX ~= nil

	-- the roster: a ring per weapon over the canvas's portrait, the weapon's name under it
	for i, r in L.roster do
		local b = make("TextButton", self.pickPage, { Name = "Pick" .. r.id, Text = "", BackgroundTransparency = 1, AutoButtonColor = false })
		place(b, r.x - L.cell / 2, r.y - L.cell / 2, L.cell, L.cell)
		corner(b, math.floor(L.cell / 2))
		local ring = stroke(b, Color3.fromRGB(214, 228, 250), 3)
		local name = text(self.pickPage, string.upper(Weapons.LIST[i].name), 11 * s, WHITE)
		Ui.outline(name, 1)
		name.Name = "Name" .. r.id
		place(name, r.x - L.cell, r.y + L.cell / 2 + 5, L.cell * 2, 14 * s)
		b.Activated:Connect(function() self:pickWeapon(r.id) end)
		self.cells[i] = { button = b, ring = ring, name = name, id = r.id }
		table.insert(self.tags, name)
	end

	-- a card per pedestal
	for _, p in L.pedestals do
		local team = HudColors.TEAM[(p.team % 2) + 1]
		-- the card: an ink border with the team's colour as a ring inside it (green once ready), and
		-- a header band in the team's colour with the player's name outlined in it
		local card = make("Frame", self.pickPage, { Name = "Card" .. p.slot, BackgroundColor3 = PANEL, BackgroundTransparency = 0, BorderSizePixel = 0 })
		place(card, p.x, p.cardY, p.cardW, p.cardH)
		corner(card, 0)
		stroke(card, INK, 3)
		local ring = make("Frame", card, { Name = "Ring", BackgroundTransparency = 1, BorderSizePixel = 0 })
		place(ring, 2, 2, p.cardW - 4, p.cardH - 4)
		corner(ring, 10)
		local edge = stroke(ring, team, 2)
		local band = Ui.band(card, team, 24 * s)
		local who = text(band, "", math.floor(14 * s), WHITE, Ui.LABEL)           -- (small Fredoka capitals run together)
		who.Name = "Who"
		place(who, 10 * s, 0, p.cardW - 20 * s, 24 * s)
		who.TextXAlignment = Enum.TextXAlignment.Left
		local status = text(band, "", math.floor(13 * s), WHITE, Ui.LABEL)
		status.Name = "State"
		place(status, 10 * s, 0, p.cardW - 20 * s, 24 * s)
		status.TextXAlignment = Enum.TextXAlignment.Right
		local weapon = text(card, "", math.floor(22 * s), WHITE, DISPLAY)
		weapon.Name = "Weapon"
		place(weapon, 8 * s, 27 * s, p.cardW - 16 * s, 24 * s)
		local kind = text(card, "", math.floor(11 * s), DIM)
		kind.Name = "Kind"
		place(kind, 8 * s, 48 * s, p.cardW - 16 * s, 14 * s)
		-- the four stat bars, ten segments each
		local bars = {}
		local rowH = math.floor((p.cardH - 72 * s) / 4)
		for k, key in WeaponStats.KEYS do
			local y = 66 * s + (k - 1) * rowH
			local tag = text(card, STAT_NAMES[key], math.floor(11 * s), DIM)
			place(tag, 10 * s, y, 34 * s, rowH)
			tag.TextXAlignment = Enum.TextXAlignment.Left
			tag.Name = "Stat" .. key
			local segs: any = { blocks = {} }
			local segW = (p.cardW - 62 * s) / 10
			local segH = math.max(6, math.floor(rowH * 0.56))
			local px = math.max(1, math.floor(segH / 5))       -- one "pixel" of the block's shading
			for n = 1, 10 do
				local seg = make("Frame", card, { BorderSizePixel = 0, BackgroundColor3 = SLATE })
				place(seg, 48 * s + (n - 1) * segW, y + (rowH - segH) / 2, segW - 3, segH)
				local hi = make("Frame", seg, { Name = "Hi", BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, px) })
				local lo = make("Frame", seg, { Name = "Lo", BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -px), Size = UDim2.new(1, 0, 0, px) })
				-- (flat themes: a plain rounded block, no pixel shading)
				if Ui.flat() then hi.BackgroundTransparency, lo.BackgroundTransparency = 1, 1 end
				Ui.pip(seg)
				segs[n] = seg
				segs.blocks[n] = { frame = seg, hi = hi, lo = lo }
				paintBlock(segs.blocks[n], false)
			end
			bars[key] = segs
			segs.tag = tag
		end
		-- the open slot: ADD BOT and the difficulty to propose it at
		local open = make("Frame", card, { Name = "Open", BackgroundTransparency = 1 })
		place(open, 0, 26 * s, p.cardW, p.cardH - 26 * s)
		local openText = text(open, "OPEN SLOT", math.floor(18 * s), DIM, DISPLAY)
		place(openText, 0, 4 * s, p.cardW, 24 * s)
		local addBot = button(open, "+ ADD BOT", Ui.BLUE, function()
			self:send("bot", self.difficulty, p.slot)
		end)
		addBot.Name = "AddBot"
		addBot.TextSize = Ui.px(18 * s)
		place(addBot, p.cardW * 0.12, 36 * s, p.cardW * 0.76, 38 * s)
		local chips = {}
		for k, d in DIFFICULTIES do
			local chip = button(open, string.upper(d), SLATE, function()
				self.difficulty = d
				self:render()
			end, true)
			chip.Name = "Difficulty" .. d
			chip.TextSize = Ui.px(12 * s)
			local cw = (p.cardW * 0.76 - 8 * s) / 3
			place(chip, p.cardW * 0.12 + (k - 1) * (cw + 4 * s), 82 * s, cw, 26 * s)
			chips[d] = chip
		end
		-- a running vote on this slot: the question, the time left, the tally and your ballot
		local vote = make("Frame", card, { Name = "Vote", BackgroundTransparency = 1, Visible = false })
		place(vote, 0, 26 * s, p.cardW, p.cardH - 26 * s)
		local question = text(vote, "", math.floor(16 * s), GOLD, DISPLAY)
		question.Name = "Question"
		place(question, 6 * s, 2 * s, p.cardW - 12 * s, 22 * s)
		local tally = text(vote, "", math.floor(12 * s), WHITE)
		tally.Name = "Tally"
		place(tally, 6 * s, 26 * s, p.cardW - 12 * s, 16 * s)
		local yes = button(vote, "YES", GREEN, function() self:send("ballot", true) end)
		yes.Name = "Yes"
		place(yes, p.cardW * 0.1, 50 * s, p.cardW * 0.38, 34 * s)
		local no = button(vote, "NO", RED, function() self:send("ballot", false) end)
		no.Name = "No"
		place(no, p.cardW * 0.52, 50 * s, p.cardW * 0.38, 34 * s)
		-- a bot's own card: who it is, and the vote to take it out
		local remove = button(card, "REMOVE BOT", Ui.RED, function() self:send("bot", false, p.slot) end)
		remove.Name = "RemoveBot"
		remove.TextSize = Ui.px(12 * s)
		place(remove, p.cardW - 98 * s, 26 * s, 90 * s, 22 * s)
		-- an empty pedestal's "?" where a fighter would stand
		local unknown = text(self.pickPage, "?", math.floor(p.fighterH * 0.5), Color3.fromRGB(190, 210, 240), DISPLAY)
		unknown.Name = "Unknown" .. p.slot
		unknown.TextTransparency = 0.35
		place(unknown, p.cx - p.fighterH * 0.4, p.plinthY - p.plinthH - p.fighterH * 0.8, p.fighterH * 0.8, p.fighterH * 0.7)
		table.insert(self.tags, unknown)
		self.cards[p.slot] = { unknown = unknown, root = card, edge = edge, band = band, who = who, status = status, weapon = weapon, kind = kind,
			bars = bars, open = open, addBot = addBot, chips = chips, vote = vote, question = question, tally = tally,
			yes = yes, no = no, remove = remove, team = team, p = p }
	end
end

-- ------------------------------------------------------------------ rendering a room view ----
-- The vote pages' cards: a picture per arena (the canvas draws it under the ring), a card per rule
-- set, and a chip per slot for who has voted.
function SelectScreen.buildVotes(self: any, L: any)
	local s = L.s
	for _, m in L.maps do
		local b = make("TextButton", self.pages.map, { Name = "Map" .. m.id, Text = "", BackgroundTransparency = 1, AutoButtonColor = false })
		place(b, m.x, m.y, m.w, m.h)
		corner(b, 8)
		local ring = stroke(b, Color3.fromRGB(214, 228, 250), 3)
		local stage = Stages.BY_ID[m.id]
		local name = text(self.pages.map, if stage then string.upper(Realms.name(stage)) else "RANDOM", 11 * s, WHITE)
		name.Name = "MapName" .. m.id
		-- on an ink plate, so the name reads over any sky
		name.BackgroundTransparency, name.BackgroundColor3 = 0.1, INK
		place(name, m.x, m.y + m.h + 2, m.w, L.nameH)
		local count = text(b, "", math.floor(14 * s), INK, DISPLAY)
		count.Name = "Count"
		count.BackgroundTransparency, count.BackgroundColor3 = 0, GOLD
		corner(count, 0)
		stroke(count, INK, 2)
		place(count, m.w - 30 * s, 4 * s, 26 * s, 20 * s)
		if m.id == "Random" then
			local q = text(b, "?", math.floor(m.h * 0.6), WHITE, DISPLAY)
			q.Name = "RandomMark"
			place(q, 0, 0, m.w, m.h)
		end
		b.Activated:Connect(function() if self:settled() then self:send("vote", m.id) end end)
		table.insert(self.mapCards, { id = m.id, button = b, ring = ring, name = name, count = count, m = m })
	end
	for _, r in L.rules do
		local preset = nil
		for _, p in Rules.presets do if p.id == r.id then preset = p end end
		-- the card: a solid panel for the words on top, glass below it where the canvas draws the
		-- rule set's emblem (RULE_EMBLEMS)
		local card = make("TextButton", self.pages.rules, { Name = "Rule" .. r.id, Text = "", BackgroundTransparency = 1,
			AutoButtonColor = false, BorderSizePixel = 0 })
		place(card, r.x, r.y, r.w, r.h)
		corner(card, 12)
		local ring = stroke(card, EDGE, 3)
		local panel = make("Frame", card, { Name = "Panel", BackgroundColor3 = PANEL, BorderSizePixel = 0 })
		place(panel, 0, 0, r.w, r.panelH)
		corner(panel, 12)
		local bandColour = if preset then Ui.BLUE else Ui.PANEL2
		local band = Ui.band(card, bandColour, 44 * s)
		local title = text(band, if preset then string.upper(preset.name) else "KEEP CURRENT", math.floor(20 * s), WHITE, DISPLAY)
		title.Name = "Title"
		place(title, 6 * s, 0, r.w - 12 * s, 44 * s)
		title.TextWrapped = true
		local hint = text(card, if preset then preset.hint else "The room's rules as they are now.", 13 * s, Ui.KEY, Ui.BODY)
		hint.Name = "Hint"
		hint.TextWrapped = true
		place(hint, 12 * s, 50 * s, r.w - 24 * s, 52 * s)
		local facts = {}
		for k = 1, 3 do
			local f = text(card, "", math.floor(15 * s), WHITE)
			f.Name = "Fact" .. k
			place(f, 12 * s, 108 * s + (k - 1) * 26 * s, r.w - 24 * s, 24 * s)
			facts[k] = f
		end
		local count = text(card, "", math.floor(18 * s), GOLD, DISPLAY)
		count.Name = "Count"
		place(count, 0, r.h - 36 * s, r.w, 30 * s)
		card.Activated:Connect(function() if self:settled() then self:send("rule", r.id) end end)
		table.insert(self.ruleCards, { id = r.id, root = card, ring = ring, facts = facts, count = count, preset = preset, r = r })
	end
end

-- The rules a card stands for, in three lines: how a fight is won, items, disasters.
local function ruleFacts(rules: any): { string }
	local how = if rules.mode == "timed" then `TIMED · {math.floor((rules.time or 180) / 60)}:{string.format("%02d", (rules.time or 180) % 60)}`
		else `STOCK · {rules.stocks or 3} LIVES`
	return { how, `ITEMS {if rules.items then "ON" else "OFF"}`, `DISASTERS {string.upper(rules.disasters or "off")}` }
end

-- The screen's size: the canvas's, once draw has seen it (it fills the same screen), else this
-- gui's. Not this gui's alone: a ScreenGui's AbsoluteSize is a deferred layout result, and read in
-- the frame it is enabled it was stale - in a playtest the screen laid itself out for 890x500 on a
-- 1514x806 window and stayed that way.
function SelectScreen.viewport(self: any): (number, number)
	local size = self.seen or self.gui.AbsoluteSize
	return math.max(320, size.X), math.max(240, size.Y)
end

function SelectScreen.render(self: any)
	local room = self.room
	if not room or room.left then return end
	local W, H = self:viewport()
	local layoutKey = `{W}x{H}x{#room.slots}`
	if self.layoutKey ~= layoutKey then
		self.L = SelectScreen.layout(W, H, room.slots)
		self:build(self.L)
		self:buildVotes(self.L)
		self.layoutKey = layoutKey
	end
	local mine = nil
	for _, slot in room.slots do if slot.userId == self.userId then mine = slot end end

	self.title.Text = `{string.upper(room.name or "MATCH")}  ·  ROOM {room.id}`
	local mode = if room.mode == "timed" then `TIMED {math.floor((room.time or 180) / 60)}:{string.format("%02d", (room.time or 180) % 60)}` else `STOCK · {room.stocks}`
	-- which page: the room's phase
	local phase = room.phase or "pick"
	-- the arena is voted on after the picks, so until that vote is done it is not known
	local map = if phase == "pick" or phase == "map" then "MAP: VOTE"
		else "MAP: " .. string.upper(Realms.name(Stages.BY_ID[room.stage] or { name = room.stage }))
	self.rules.Text = `{mode} · ITEMS {if room.items then "ON" else "OFF"} · DISASTERS {string.upper(room.disasters or "off")} · {map}`
	-- the pixel face is monospaced, so the line can be sized to fit its bar exactly
	if self.L then
		local s = self.L.s
		self.rules.TextSize = math.min(Ui.px(15 * s), math.floor((572 * s - 8) / (math.max(1, utf8.len(self.rules.Text) or 1) * Ui.ADVANCE)))
	end

	if phase ~= self.shownPhase then self.shownPhase, self.phaseShownAt = phase, self.now() end
	for name, page in self.pages do page.Visible = name == phase end
	self.voteTitle.Visible = phase ~= "pick"
	self.clock.Visible = phase ~= "pick"
	self:renderVotes(phase, room, mine)

	-- the roster: your pick in gold, everyone's tag over what they picked
	local picked: { [string]: { any } } = {}
	for i, slot in room.slots do
		for _, id in { slot.weapon, slot.weapon2 } do
			if (slot.userId or slot.bot) and id then
				picked[id] = picked[id] or {}
				table.insert(picked[id], { i = i, slot = slot })
			end
		end
	end
	for k = #self.tags, 1, -1 do
		local t = self.tags[k]
		if t.Name == "Tag" then t:Destroy(); table.remove(self.tags, k) end
	end
	local L = self.L
	for idx, c in self.cells do
		-- your two in gold, each named with its hand
		local hand = if mine and mine.weapon == c.id then 1 elseif mine and mine.weapon2 == c.id then 2 else nil
		c.ring.Color = if hand then GOLD else Color3.fromRGB(214, 228, 250)
		c.ring.Thickness = if hand then 5 else 3
		c.name.TextColor3 = if hand then GOLD else DIM
		c.name.Text = (if hand then `{hand} · ` else "") .. string.upper(Weapons.BY_ID[c.id].name)
		local list: { any } = picked[c.id] or {}
		for n, entry in list do
			local slot = entry.slot
			local you = slot.userId == self.userId
			local colour = HudColors.TEAM[((slot.team or 0) % 2) + 1]
			local tag = text(self.pickPage, if you then "YOU" elseif slot.bot then "CPU" else `P{entry.i}`, math.floor(11 * L.s), INK)
			tag.Name = "Tag"
			tag.BackgroundTransparency = 0
			tag.BackgroundColor3 = colour
			corner(tag, 6)
			local r = L.roster[idx]
			place(tag, r.x - L.cell / 2 + (n - 1) * 30 * L.s + 4, r.y - L.cell / 2 + 4, 30 * L.s, 15 * L.s)
			table.insert(self.tags, tag)
		end
	end

	-- the cards
	local vote = room.botVote
	for i, slot in room.slots do
		local card = self.cards[i]
		if not card then continue end
		local human, bot = slot.userId ~= nil, slot.bot ~= nil
		local filled = human or bot
		card.who.Text = if human then `{if slot.userId == room.host then "★ " else ""}{string.upper(slot.name or "PLAYER")}`
			elseif bot then `CPU · {string.upper(slot.bot)}` else `PLAYER {i}`
		card.status.Text = if human then (if slot.ready then "READY" else "SELECTING") elseif bot then "READY" else ""
		card.status.TextColor3 = WHITE
		card.edge.Color = if human and slot.ready then GREEN else card.team
		card.edge.Thickness = if human and slot.ready then 3 else 2
		card.weapon.Visible, card.kind.Visible = filled, filled
		local w = filled and Weapons.BY_ID[slot.weapon]
		if w then
			-- both weapons named (a fit, so the longest pair stays on the card); the kind line and
			-- the bars are the first's, the one shown on the pedestal
			local w2 = slot.weapon2 and Weapons.BY_ID[slot.weapon2]
			local name = string.upper(w.name) .. (if w2 then " + " .. string.upper(w2.name) else "")
			card.weapon.Text = name
			card.weapon.TextSize = math.floor(math.min(Ui.px(22 * self.L.s), (card.p.cardW - 16 * self.L.s) / (#name * Ui.ADVANCE)))
			card.kind.Text = `{string.upper(w.archetype or "")}  {string.rep("★", w.difficulty or 1)}{string.rep("☆", 3 - (w.difficulty or 1))}`
			local stats = WeaponStats.of(w.id)
			for key, segs in card.bars do
				segs.tag.Visible = true
				for n = 1, 10 do
					segs[n].Visible = true
					paintBlock(segs.blocks[n], n <= stats[key])
				end
			end
		else
			for _, segs in card.bars do
				segs.tag.Visible = false
				for n = 1, 10 do segs[n].Visible = false end
			end
		end
		card.unknown.Visible = not filled
		local voting = vote ~= nil and vote.slot == i
		card.vote.Visible = voting
		card.open.Visible = not filled and not voting
		card.remove.Visible = bot and not voting and vote == nil
		card.addBot.Active = vote == nil
		card.addBot.Text = if vote then "VOTE RUNNING" else "+ ADD BOT"
		for d, chip in card.chips do
			Ui.paint(chip, if d == self.difficulty then GOLD else SLATE, if d == self.difficulty then INK else WHITE)
		end
		if voting then
			local mineBallot = vote.ballots and vote.ballots[tostring(self.userId)]
			card.question.Text = if vote.value == false then "REMOVE THE BOT?" else `ADD {string.upper(vote.value)} BOT?`
			card.tally.Text = `{vote.yes} YES · {vote.no} NO  ·  {vote.voters} VOTING`
			Ui.paint(card.yes, if mineBallot == true then GREEN else Color3.fromRGB(46, 88, 60))
			Ui.paint(card.no, if mineBallot == false then RED else Color3.fromRGB(88, 46, 46))
		end
	end

	-- the bottom row
	self.ready.Text = if mine and mine.ready then "READY ✓" else "READY"
	Ui.paint(self.ready, if mine and mine.ready then GREEN else Color3.fromRGB(46, 120, 76))
	self.phaseEndsAt = if room.phaseLeft then os.clock() + room.phaseLeft else nil
	local last = room.lastVote
	local arena = room.mapResult and Stages.BY_ID[room.mapResult]
	self.status.Text = room.error
		or (if room.state == "playing" then `Loading {if arena then Realms.name(arena) else "the arena"}…` else nil)
		or (if phase == "rules" and arena then `The arena: {string.upper(Realms.name(arena))}. Now the rules.` else nil)
		or (if phase == "pick" and last then (if last.passed then (if last.value == false then "The bot was voted out." else "Vote passed: bot added.")
			else "Bot vote failed.") else nil)
		or (if phase == "map" then "Pick the arena. Most votes wins; a tie is drawn at random." else nil)
		or (if phase == "rules" then "Pick the rules. Most votes wins." else nil)
		or `Pick two weapons - choosing weapon {self.hand} - and ready up. When every pedestal is ready, the map vote begins.`
	self:tickPhase(os.clock())
end

-- The vote pages: counts, rings on your vote, tags on everyone's, the who-has-voted strip.
function SelectScreen.renderVotes(self: any, phase: string, room: any, mine: any)
	local L = self.L
	local s = L.s
	local field = if phase == "map" then "vote" else "ruleVote"
	self.voteTitle.Text = if phase == "map" then "VOTE FOR THE ARENA" elseif phase == "rules" then "VOTE THE RULES" else ""
	local counts: { [string]: number } = {}
	for _, slot in room.slots do
		local b = slot.userId and slot[field]
		if b then counts[b] = (counts[b] or 0) + 1 end
	end
	local myVote = mine and mine[field]
	for _, c in self.mapCards do
		local n = counts[c.id] or 0
		c.count.Text = tostring(n)
		c.count.Visible = n > 0 and phase == "map"
		local chosen = phase == "map" and myVote == c.id
		c.ring.Color = if chosen then GOLD else Color3.fromRGB(214, 228, 250)
		c.ring.Thickness = if chosen then 5 else 3
		c.name.TextColor3 = if chosen then GOLD else WHITE
	end
	for _, c in self.ruleCards do
		local rules = if c.preset then c.preset.rules else room
		for k, line in ruleFacts(rules) do c.facts[k].Text = line end
		local n = counts[c.id] or 0
		c.count.Text = if n == 1 then "1 VOTE" elseif n > 1 then `{n} VOTES` else ""
		local chosen = phase == "rules" and myVote == c.id
		c.ring.Color = if chosen then GOLD else EDGE
		c.ring.Thickness = if chosen then 5 else 3
	end
	-- who has voted: a chip per slot (bots do not vote)
	for _, chip in self.chips do chip:Destroy() end
	self.chips = {}
	if phase ~= "pick" then
		local n = #room.slots
		local w = math.min(150 * s, (L.W - 60) / n - 8)
		for i, slot in room.slots do
			local voted = slot.userId ~= nil and slot[field] ~= nil
			local label = if slot.userId then `{if voted then "✓" else "…"} {string.upper(slot.name or "PLAYER")}` elseif slot.bot then "CPU" else "OPEN"
			local chip = text(self.pages[phase], label, 12 * s, if voted then INK else WHITE)
			chip.Name = "Chip" .. i
			chip.BackgroundTransparency = 0
			chip.BackgroundColor3 = if voted then GREEN else (if slot.bot then Color3.fromRGB(52, 64, 88) else PANEL)
			corner(chip, 8)
			stroke(chip, Ui.INK, 2)               -- (the fill says voted; the team shows on the pick page)
			place(chip, L.W / 2 - (n * (w + 8)) / 2 + (i - 1) * (w + 8), L.stripY - 4 * s, w, 34 * s)
			table.insert(self.chips, chip)
		end
	end
end

-- The countdown: the vote's seconds left, or (in the pick phase, once the room is full) the
-- seconds until the map vote begins anyway. Written once a second.
function SelectScreen.tickPhase(self: any, t: number)
	local room = self.room
	if not room or not self.phaseEndsAt then
		if self.clock then self.clock.Text = "" end
		return
	end
	local left = math.max(0, math.ceil(self.phaseEndsAt - t))
	if self.clockShown == left then return end
	self.clockShown = left
	self.clock.Text = tostring(left)
	if (room.phase or "pick") == "pick" and not room.error then
		self.status.Text = `Map vote in {left}s - or as soon as everyone is ready.`
	end
end

-- ------------------------------------------------------------------ the canvas scene ----
-- A fighter standing on a pedestal (or in a portrait), cached by look: a Fighter posed and turned
-- into the snapshot shape Fighter2D draws.
-- `still` is for the roster: its portraits never move, so the snapshot is made once per look.
local function standIn(self: any, key: string, avatar: string, weapon: string, facing: number, state: string, still: boolean?): (any, any)
	local char = self.chars[avatar .. "|" .. weapon]
	if not char then
		char = Loadout.build(avatar, weapon)
		self.chars[avatar .. "|" .. weapon] = char
	end
	local f = self.fighters[key]
	if not f or f.char ~= char then
		f = Fighter.new({ index = 0, char = char, x = 0, y = 0, stocks = 3 })
		f.onGround, f.invincible = true, 0
		self.fighters[key] = f
		f.snap = nil
	end
	if still and f.snap then return f.snap, char end
	if f.state ~= state then f:setState(state) end
	f.facing = facing
	f.sf += 1
	f.frameCount += 1
	local snap = Snapshot.decode(Snapshot.encode(f))
	if still then f.snap = snap end
	return snap, char
end

-- Draw `s` with its feet at screen (x, y), `h` pixels tall.
local function drawStanding(c: any, s: any, char: any, x: number, y: number, h: number, t: number)
	local vp = c:viewport()
	local ppu = h / (char.height + 0.6)
	c:world((vp.X / 2 - x) / ppu, (y - vp.Y / 2) / ppu, ppu, 0, 0)
	Fighter2D.draw(c, s, char, t, 0)
end

local SKY = { Color3.fromRGB(10, 18, 48), Color3.fromRGB(24, 58, 112), Color3.fromRGB(56, 128, 196), Color3.fromRGB(150, 206, 240) }
local function skyAt(k: number): Color3
	local n = #SKY - 1
	local i = math.clamp(math.floor(k * n), 0, n - 1)
	return SKY[i + 1]:Lerp(SKY[i + 2], k * n - i)
end

-- The whole scene, into the game's canvas (in place of the plaza). `myAvatar` dresses the roster.
-- Redrawn at REDRAW_HZ, not every frame: a menu's idle breathing reads the same at 30 frames a
-- second, and the canvas keeps the last frame's picture through a frame that draws nothing - so
-- this halves the screen's cost for free.
SelectScreen.REDRAW_HZ = 30

function SelectScreen.draw(self: any, c: any, dt: number, myAvatar: string?)
	local room, L = self.room, self.L
	if not room or not L then return end
	-- the canvas knows the real screen size; lay out again if it is not what this was built for
	self.seen = c:viewport()
	local W, H = self:viewport()
	if W ~= L.W or H ~= L.H then
		self:render()
		L = self.L
		self.sinceDraw = nil
	end
	local t = os.clock()
	self.sinceDraw = (self.sinceDraw or math.huge) + dt
	if self.sinceDraw < 1 / SelectScreen.REDRAW_HZ - 1e-3 then
		self:tickVote(t)
		self:tickPhase(t)
		return
	end
	self.sinceDraw = 0
	local vp = c:viewport()
	local W, H = vp.X, vp.Y
	c:screen()
	-- the sky, in pixel bands, with a few stars twinkling at the top
	local bands = 28
	for b = 0, bands - 1 do
		Canvas2D.rect(c, 0, b * H / bands, W, H / bands + 1, skyAt(b / (bands - 1)), 1)
	end
	for k = 1, 22 do
		local sx, sy = (k * 197) % W, (k * 61) % (H * 0.35)
		local tw = 0.35 + 0.35 * math.sin(t * 2 + k)
		Canvas2D.rect(c, sx, sy, 2, 2, WHITE, tw)
	end
	-- a bank of pixel clouds along the bottom, drifting
	local cloud = Color3.fromRGB(226, 240, 252)
	for k = 0, 9 do
		local cx = ((k * 173 + t * 6) % (W + 260)) - 130
		local cy = H * 0.86 + (k % 3) * 14
		for j = 0, 4 do
			local r = 26 + ((k + j) % 3) * 10
			Canvas2D.rect(c, cx + j * 26 - r, cy - r * 0.6, r * 2, r * 1.2, cloud, 0.85)
		end
	end
	local phase = room.phase or "pick"
	if phase == "map" then
		self:drawMaps(c, t)
		c:finish()
		self:tickPhase(t)
		return
	elseif phase == "rules" then
		self:drawRuleEmblems(c, t)
		c:finish()
		self:tickPhase(t)
		return
	end
	-- the roster: a disc per weapon, your avatar holding it standing in the disc
	local avatar: string = myAvatar or "Classic"
	if not myAvatar then
		for _, slot in room.slots do if slot.userId == self.userId and slot.avatar then avatar = slot.avatar end end
	end
	for i, r in L.roster do
		-- a square pixel tile behind each portrait: a dark well, lighter toward the top, with a
		-- floor stripe the fighter stands on
		local h = L.cell / 2
		Canvas2D.rect(c, r.x - h, r.y - h, L.cell, L.cell, Color3.fromRGB(38, 43, 68), 1)
		Canvas2D.rect(c, r.x - h, r.y - h, L.cell, L.cell * 0.55, Color3.fromRGB(58, 68, 102), 1)
		Canvas2D.rect(c, r.x - h, r.y + h * 0.66, L.cell, L.cell * 0.17, Color3.fromRGB(24, 20, 37), 1)
		local s, char = standIn(self, "roster" .. i, avatar, r.id, 1, "idle", true)
		drawStanding(c, s, char, r.x, r.y + L.cell * 0.36, L.cell * 0.64, 0)
		c:screen()
	end
	-- the pedestals and who stands on them
	for _, p in L.pedestals do
		local slot = room.slots[p.slot]
		local team = HudColors.TEAM[(p.team % 2) + 1]
		local left = p.cx - p.plinthW / 2
		-- a beam of the team's light behind the fighter, in three soft steps
		local top = p.plinthY - p.plinthH - p.fighterH * 1.05
		for k = 0, 2 do
			local bw = p.cardW * (0.62 - k * 0.17)
			Canvas2D.rect(c, p.cx - bw / 2, top, bw, p.plinthY - top, team, 0.07)
		end
		-- the pedestal: its body down behind the card, a stone top slab with a lit bevel and a dark
		-- lip, a band of the team's colour, and a few chips of stone for texture
		local bodyW = p.cardW * 0.86
		Canvas2D.rect(c, p.cx - bodyW / 2, p.plinthY - 2, bodyW, p.cardH * 0.4, Color3.fromRGB(58, 66, 86), 1)
		Canvas2D.rect(c, left - 6, p.plinthY - p.plinthH, p.plinthW + 12, p.plinthH, Color3.fromRGB(104, 116, 142), 1)
		Canvas2D.rect(c, left - 6, p.plinthY - p.plinthH, p.plinthW + 12, 5, Color3.fromRGB(190, 204, 226), 1)
		Canvas2D.rect(c, left - 6, p.plinthY - 4, p.plinthW + 12, 4, Color3.fromRGB(44, 50, 66), 1)
		Canvas2D.rect(c, left - 6, p.plinthY - p.plinthH + 8, p.plinthW + 12, 4, team, 1)
		for k = 1, 5 do
			Canvas2D.rect(c, left + (k * 37) % p.plinthW, p.plinthY - p.plinthH + 14 + (k % 2) * 3, 6, 2, Color3.fromRGB(78, 88, 110), 1)
		end
		if slot and (slot.userId or slot.bot) and slot.weapon then
			local facing = if p.team == 0 then 1 else -1
			local s, char = standIn(self, "slot" .. p.slot, slot.avatar or "Classic", slot.weapon, facing,
				if slot.ready or slot.bot then "victory" else "idle")
			drawStanding(c, s, char, p.cx, p.plinthY - p.plinthH, p.fighterH, t)
			c:screen()
		end
	end
	c:finish()
	self:tickVote(t)
	self:tickPhase(t)
end

-- The map vote's pictures: each arena as it is, drawn small in its own realm - the realm's sky in
-- bands, then the stage itself through the same renderer the fight uses, fitted to the card.
-- Random is a dark card (its "?" is the GUI's).
function SelectScreen.drawMaps(self: any, c: any, t: number)
	self.stages = self.stages or {}
	for _, card in self.mapCards do
		local m = card.m
		local data = Stages.BY_ID[m.id]
		if not data then
			Canvas2D.rect(c, m.x, m.y, m.w, m.h, Color3.fromRGB(26, 34, 56), 1)
			for k = 0, 3 do
				Canvas2D.rect(c, m.x + k * m.w / 4, m.y, 2, m.h, Color3.fromRGB(40, 54, 84), 1)
			end
			continue
		end
		local realm = Realms.of(m.id) or Realms.LIST[1]
		local stops = realm.sky
		local bands = 10
		for b = 0, bands - 1 do
			local at = (b + 0.5) / bands * (#stops - 1)
			local k = math.min(#stops - 1, math.floor(at) + 1)
			local a, z = Canvas2D.hex(stops[k], WHITE), Canvas2D.hex(stops[k + 1], WHITE)
			local f = at - (k - 1)
			Canvas2D.rect(c, m.x, m.y + b * m.h / bands, m.w, m.h / bands + 1,
				Color3.new(a.R + (z.R - a.R) * f, a.G + (z.G - a.G) * f, a.B + (z.B - a.B) * f), 1)
		end
		local stage = self.stages[m.id]
		if not stage then
			stage = Stage.new(data, 1)
			self.stages[m.id] = stage
		end
		-- the stage's extent: every surface, and the depth of the main island under it
		local x1, x2, top, bottom = math.huge, -math.huge, -math.huge, math.huge
		for _, pl in stage.platforms do
			x1, x2 = math.min(x1, pl.x1), math.max(x2, pl.x2)
			top = math.max(top, pl.top)
			bottom = math.min(bottom, pl.top - (pl.thickness or 1) - (if pl.solid then 12 else 1))
		end
		local ppu = math.min(m.w * 0.9 / math.max(1, x2 - x1), m.h * 0.78 / math.max(1, top - bottom + 4))
		local cx, cy = (x1 + x2) / 2, (top + bottom) / 2 + 1
		local vp = c:viewport()
		c:world(cx + (vp.X / 2 - (m.x + m.w / 2)) / ppu, cy + ((m.y + m.h / 2) - vp.Y / 2) / ppu, ppu, 0, 0)
		Stage2D.draw(c, stage)
		c:screen()
	end
	-- anything an island hangs below its card is cut off by repainting the sky beneath the card
	local vp = c:viewport()
	for _, card in self.mapCards do
		local m = card.m
		local y0 = m.y + m.h
		local y1 = y0 + self.L.nameH + 10
		for y = y0, y1, 6 do Canvas2D.rect(c, m.x - 4, y, m.w + 8, 7, skyAt(y / vp.Y), 1) end
	end
end

-- Each rule set's emblem, in the glass under its card's words: a trophy-gold star for the
-- tournament, a ring for casual, a fire burst for chaos, a rune for keeping the room's own.
-- { drawing, colour ramp, frame }: each held on one full-size frame of its FxArt animation
local RULE_EMBLEMS: { [string]: { any } } = { tournament = { "star", "gold", 1 }, casual = { "ring", "#7DE8B0", 2 }, chaos = { "burst", "fire", 2 },
	current = { "rune", "star", 0 } }
function SelectScreen.drawRuleEmblems(self: any, c: any, t: number)
	for i, card in self.ruleCards do
		local r = card.r
		local top = r.y + r.panelH
		local glass = r.h - r.panelH - 36 * self.L.s
		Canvas2D.rect(c, r.x + 3, top, r.w - 6, r.h - r.panelH - 3, PANEL, 0.62)
		local e = RULE_EMBLEMS[card.id] or RULE_EMBLEMS.current
		local art = FxArt.get(e[1], e[3], e[2], nil, 1)
		local size = math.min(r.w * 0.4, glass * 0.95)
		FxArt.draw(c, art, r.x + r.w / 2, top + glass / 2 + 2, FxArt.sized(art, size), 0, 1)
		c:screen()
	end
end

-- The vote's countdown, written once a second.
function SelectScreen.tickVote(self: any, t: number)
	local vote = self.room and self.room.botVote
	if not vote then return end
	local card = self.cards[vote.slot]
	local left = math.max(0, math.ceil(self.voteEndsAt - t))
	if card and card.leftShown ~= left then
		card.leftShown = left
		card.tally.Text = `{vote.yes} YES · {vote.no} NO  ·  {vote.voters} VOTING  ·  {left}s`
	end
end

SelectScreen.hexOf = hexOf
return SelectScreen
