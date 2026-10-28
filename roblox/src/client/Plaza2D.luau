--!strict
-- The lobby: the Skyhold Bazaar, a market on floating islands walked beat-'em-up style (Plaza.luau
-- is the walking, Data/Plaza the map), and the private lounges fights are prepared in. In Roblox it
-- is drawn as a realm (Realms.LOBBY) to match the arenas; the web's Neon Row data is its map.
--
-- Drawing, back to front: the realm's sky; every plaza (the island it stands on hanging below its
-- front edge, its paving, its low back wall) and the plank bridges between; then every prop
-- and person SORTED BY DEPTH, so a player walking behind a cabinet is hidden by it and one walking
-- in front covers it; then the front railings. A point at depth z is lifted z * DEPTH on screen,
-- which is the whole of the perspective: characters keep their side-on art and are never scaled.
--
-- Props are pixel art built once (PlazaArt) and drawn as sprites; people are drawn by Fighter2D,
-- exactly as they fight. Labels (station names, stall signs, name tags) are TextLabels projected
-- from world points, pooled and hidden when unused.

local Shared = game:GetService("ReplicatedStorage").Shared
local UIS = game:GetService("UserInputService")
local Plaza = require(Shared.Plaza)
local Loadout = require(Shared.Loadout)
local Input = require(Shared.Input)
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Stages = require(Shared.Data.Stages)
local KIT: any = require(Shared.Data.AvatarKit)
local InputClient = require(script.Parent.InputClient)
local Canvas = require(script.Parent.Canvas2D)
local Fighter2D = require(script.Parent.Fighter2D)
local WeaponArt = require(script.Parent.Weapons2D)
local StageThumb = require(script.Parent.StageThumb)
local Realms = require(Shared.Realms)
local PlazaArt = require(script.Parent.PlazaArt)
local RealmArt = require(script.Parent.RealmArt)
local PosedFighter = require(script.Parent.PosedFighter)
local Ui = require(script.Parent.Ui)

local PLAZA: any = Plaza.DATA
local D = PLAZA.depth :: number
local A = PlazaArt.C

local Plaza2D = {}
Plaza2D.__index = Plaza2D

local INK = Color3.fromRGB(15, 18, 24)
local WHITE = Color3.fromRGB(230, 225, 214)
local AMBER = Color3.fromRGB(232, 162, 74)
local CYAN = Color3.fromRGB(127, 168, 184)
local PINK = Color3.fromRGB(200, 100, 60)
local METAL = Color3.fromRGB(38, 43, 53)
local FENCE = Color3.fromHex(A.woodDk)
local FENCE_HI = Color3.fromHex(A.woodHi)
local READY = Color3.fromRGB(127, 190, 110)
local TEAM1 = Color3.fromRGB(62, 138, 46)
local TEAM2 = Color3.fromRGB(222, 98, 28)
local MANNEQUIN_SECONDS = 4

-- Where things stand in the market, beyond the stations themselves. Depths behind the floor's back
-- edge (18) stand on the parapet line, drawn over the roof and under everyone walking on it.
local STALLS = {
	{ x = -62, sign = "RAMEN", goods = "bowls", a = A.lantern, b = A.paper, vendor = "samurai" },
	{ x = -28, sign = "MASKS", goods = "masks", a = A.pink, b = A.white, vendor = "ninja" },
	{ x = 28, sign = "SKEWERS", goods = "skewers", a = A.amber, b = A.woodDk, vendor = "cowboy" },
	{ x = 62, sign = "GADGETS", goods = "gadgets", a = A.cyan, b = A.slate, vendor = "robot" },
}
local STALL_Z = 18.8
Plaza2D.STALLS = STALLS
-- the lettering's room on a stall's sign board: its 54 art pixels (1/8 stud each) less a pixel a side
Plaza2D.SIGN_W = 52 * PlazaArt.CELL
-- a narrow screen's prompt keeps this far left of the screen's middle, where your fighter stands
-- the kit's box in world units (kitBox): its ink outline and its light band and dark lip
Plaza2D.KIT_INK, Plaza2D.KIT_BAND = 0.3, 0.5
-- cabinets deeper than this are the arcade's back row, drawn in their dark shades
Plaza2D.CAB_BACK = 10
Plaza2D.CAB_FAR_SCALE = 0.8
Plaza2D.BANNER_CLEAR = 16
Plaza2D.MIRROR_GLASS = 0.4
-- the arcade canopy's height in PlazaArt cells (its beam's foot is 14 under it)
Plaza2D.CANOPY_H = 52
-- where the arcade's sign stands on its marquee board (cells up from the beam's top)
Plaza2D.MARQUEE_FOOT = 17
Plaza2D.LOUNGE_LIFT = 3
-- (0.7: larger, the lounge's camera fits the wider room and draws everyone smaller - the sky over the
-- stations stays the same, 174-176 px)
Plaza2D.STATION_SCALE = 0.7
-- the lounge's back wall: its depth (behind everything), its height in studs, its windows
Plaza2D.WALL_Z, Plaza2D.WALL_H, Plaza2D.WALL_WINDOWS = 19.5, 15, 6
Plaza2D.SHORT_SCREEN, Plaza2D.SHORT_LIFT, Plaza2D.SHORT_STUDS = 450, 1.5, 46
Plaza2D.FIGHTER_CLEAR = 64
Plaza2D.TIP_SECONDS = 6        -- (the camera leads, and a held weapon reaches back: 40 met the sword)
-- A stall's lettering: its awning colour, lightened until it reads at 4.5:1 on the board's dark face
-- (MASKS' pink measured 2.8:1, GADGETS' blue 3.1:1).
function Plaza2D.signColour(c: Color3): Color3
	local face = Color3.fromHex(PlazaArt.SIGN_FACE)
	local k = 0
	while k < 1 and Ui.contrast(Ui.shade(c, k), face) < 4.5 do k += 0.05 end
	return Ui.shade(c, math.min(k, 1))
end
-- (white: the pale cyan measured 3.1:1 on the board's own blue-grey, #537289)
Plaza2D.BILLBOARD_LINE = Color3.new(1, 1, 1)

local function text(parent: Instance, name: string, value: string, size: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name, t.Text, t.Font, t.TextSize = name, value, Ui.BODY, Ui.px(size)
	t.TextColor3, t.BackgroundTransparency, t.TextWrapped = WHITE, 1, true
	t.Parent = parent
	return t
end

-- The map this room will fight on as far as anyone can tell yet: the host's pick, the leading
-- ballot when the room votes (ties to the earliest ballot), or nil for Random.
local function shownMap(room: any): any
	if not room then return nil end
	local id = room.stage
	if room.mapChoice == "random" then return nil end
	if room.mapChoice == "vote" then
		local count, best, bestN = {}, nil, 0
		for _, slot in room.slots or {} do
			if slot.vote then
				count[slot.vote] = (count[slot.vote] or 0) + 1
				if count[slot.vote] > bestN then best, bestN = slot.vote, count[slot.vote] end
			end
		end
		id = best or id
	end
	for _, stage in Stages.LIST do
		if stage.id == id then return stage end
	end
	return nil
end
Plaza2D.shownMap = shownMap

-- The top row, below Roblox's top bar (its menu and chat buttons sit at the top left). Placed again
-- whenever that bar's height changes: it is still 0 when the client starts and builds this HUD,
-- which in a playtest left the title under Roblox's buttons.
function Plaza2D.placeTop(self: any, inset: number)
	if self.inset == inset then return end
	self.inset = inset
	self.title.Position = UDim2.fromOffset(18, inset + 12)
	self.directions.Position = UDim2.fromOffset(18, inset + 44)
	self.plate.Position = UDim2.fromOffset(8, inset + 6)
end

-- The bottom row's right end: the CHARACTER button, and LobbySocial's button bar to its left
-- (LobbySocial.RIGHT_GAP leaves the button its room). The controls row stays clear of the lot.
-- the block at the bottom right: three stacked buttons this wide, or (a light theme) a row of three
-- square icon buttons, as the reference simulator's
Plaza2D.ICON = 76
Plaza2D.CHARACTER_W = if Ui.lightPanels() then 3 * Plaza2D.ICON + 2 * Ui.GAP else 168
Plaza2D.SOCIAL_BAR_W = if Ui.lightPanels() then 4 * (Plaza2D.ICON + Ui.GAP) - Ui.GAP + Ui.GAP + Plaza2D.CHARACTER_W
	else 4 * 124 - 8 + 8 + Plaza2D.CHARACTER_W

-- ------------------------------------------------------------------ construction ----
function Plaza2D.new(parent: Instance): any
	local self: any = setmetatable({ active = false, held = false, camX = 0, peers = {}, pool = {}, used = {},
		mannequins = {}, vendors = {}, onInteract = nil, onCharacter = nil, onLocker = nil, onShop = nil, isVip = nil, blocked = false, bannerAt = -10 }, Plaza2D)
	self.input = InputClient.new()
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset = "BlockfallHub", false, true
	gui.DisplayOrder, gui.Enabled, gui.Parent = 12, false, parent
	self.gui = gui
	-- world lettering in its own layer, made first, so it paints under every HUD card: labels are made
	-- as they are first needed, and straight into the ScreenGui the billboard's drew over the prompt
	self.labelLayer = Ui.make("Frame", gui, { Name = "WorldLabels", BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1) })
	-- The HUD is the shared pixel kit (Ui): outlined pixel words, bevelled square buttons, key caps.
	-- the place's name and what is here, in one window (made first, so it sits behind them)
	-- (a light theme makes it a coloured card with outlined white words, like every label over the world)
	local plateColour = if Ui.lightPanels() then Ui.TEAL else Ui.PANEL
	local plate = if Ui.lightPanels() then Ui.card(gui, "TitlePlate", plateColour) else Ui.panel(gui, "TitlePlate")
	if not Ui.lightPanels() then plate.BackgroundTransparency = 0.12 end
	self.plate = plate
	local title = if Ui.lightPanels() then (Ui.faceText(gui, string.upper(Realms.LOBBY.name), 22, plateColour))
		else Ui.text(gui, string.upper(Realms.LOBBY.name), 22, Ui.GOLD, Ui.DISPLAY)
	title.Name = "Title"
	title.Size = UDim2.new(1, -220, 0, 32)
	title.TextXAlignment = Enum.TextXAlignment.Left
	self.title = title
	local directions = Ui.text(gui, "", 12, Ui.WHITE)
	local directionsOutline = Ui.outline(directions, 2, Ui.tone(plateColour))
	-- (the card's secondary line, by the same contrast rule as every card's: ink on the teal)
	if Ui.lightPanels() then Ui.paintSecondary(directions, directionsOutline, plateColour) end
	directions.Name = "Directions"
	directions.Size = UDim2.new(1, -220, 0, 20)
	directions.TextXAlignment = Enum.TextXAlignment.Left
	self.directions = directions
	-- The district you walked into, large, for a moment.
	local banner = Ui.text(gui, "", 40, Ui.GOLD, Ui.DISPLAY, true)
	banner.Name = "District"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position, banner.Size = UDim2.new(0.5, 0, 0, 86), UDim2.fromOffset(700, 52)
	banner.TextTransparency = 1
	self.banner = banner
	self.bannerOutline = Ui.outline(banner, 4)
	self.bannerOutline.Transparency = 1
	-- How to move, as key caps along the bottom.
	-- (centred in the room the social bar leaves at the bottom right; hidden where it does not fit)
	local controls, controlsW = Ui.hintRow(gui, "Movement", { { "A D", "WALK" }, { "W S", "STEP IN / OUT" }, { "SPACE", "HOP" }, { "E", "USE" } }, 24, nil, true)
	controls.Position, controls.Size = UDim2.new(0, 16, 1, -39), UDim2.new(1, -Plaza2D.SOCIAL_BAR_W - 48, 0, 26)
	self.controls, self.controlsW = controls, controlsW
	-- What you can do here: a card with the E key on it beside a station, or a tip when there is
	-- nothing in reach (the cap hides, the words soften).
	local prompt = Ui.make("TextButton", gui, { Name = "Interact", Font = Ui.DISPLAY, TextSize = Ui.px(20), TextColor3 = if Ui.lightPanels() then Ui.TEXT else Ui.GOLD,
		BackgroundColor3 = Ui.PANEL, BackgroundTransparency = 0.04, BorderSizePixel = 0, AutoButtonColor = false, TextWrapped = true })
	prompt.AnchorPoint = Vector2.new(0.5, 1)
	-- (above the row of square buttons in a light theme, which stand taller than the old bar)
	prompt.Position, prompt.Size = UDim2.new(0.5, 0, 1, if Ui.lightPanels() then -(10 + Plaza2D.ICON + 14) else -62), UDim2.new(1, -32, 0, 50)
	Ui.make("UISizeConstraint", prompt, { MaxSize = Vector2.new(720, 66) })
	Ui.corner(prompt, 0)
	self.promptEdge = Ui.stroke(prompt, Ui.INK, 3)
	self.promptRim = select(2, Ui.rim(prompt, Ui.PANEL2, 2, 0))
	self.promptOutline = Ui.outline(prompt, 2)
	self.promptPad = Ui.make("UIPadding", prompt, { PaddingLeft = UDim.new(0, 64), PaddingRight = UDim.new(0, 16) })
	local key = Ui.keycap(prompt, "E", 16)
	key.Position, key.Size = UDim2.new(0, 12, 0.5, -18), UDim2.fromOffset(36, 34)
	self.promptKey = key
	prompt.Activated:Connect(function() self:interact() end)
	self.prompt = prompt
	local LIGHT = Ui.lightPanels()
	local function openCharacter() if self.active and not self.blocked and self.onCharacter then self.onCharacter() end end
	local character = if LIGHT then Ui.iconButton(gui, "shirt", "CHARACTER", Ui.BLUE, openCharacter, Plaza2D.ICON)
		else Ui.button(gui, "CHARACTER", Ui.BLUE, openCharacter)
	character.Name = "CharacterButton"
	-- At the bottom right, in the row with the social buttons. Not the top right: Roblox's player list
	-- hangs there under its top bar, and in a playtest the button could not be clicked through it.
	character.AnchorPoint = Vector2.new(1, 1)
	character.Position = UDim2.new(1, -16, 1, -10)
	if not LIGHT then character.Size = UDim2.fromOffset(Plaza2D.CHARACTER_W, 42) end
	self.characterButton = character
	-- The Locker (also L): cosmetics, crates and the Workshop, stacked over CHARACTER.
	-- (the Locker window's own purple; the old olive read as a disabled button beside SHOP and CHARACTER)
	local function openLocker() if self.active and not self.blocked and self.onLocker then self.onLocker() end end
	local locker = if LIGHT then Ui.iconButton(gui, "chest", "LOCKER", Ui.PURPLE, openLocker, Plaza2D.ICON, "L")
		else Ui.keyButton(gui, "L", "LOCKER", Ui.shade(Ui.GOLD, -0.35), openLocker, 42)
	locker.Name = "LockerButton"
	locker.AnchorPoint = Vector2.new(1, 1)
	if LIGHT then locker.Position = UDim2.new(1, -16 - (Plaza2D.ICON + Ui.GAP), 1, -10)
	else locker.Position, locker.Size = UDim2.new(1, -16, 1, -58), UDim2.fromOffset(Plaza2D.CHARACTER_W, 42) end
	self.lockerButton = locker
	-- The Shop, stacked over the Locker.
	local function openShop() if self.active and not self.blocked and self.onShop then self.onShop() end end
	local shopButton = if LIGHT then Ui.iconButton(gui, "coin", "SHOP", Ui.shade(Ui.GREEN, -0.15), openShop, Plaza2D.ICON)
		else Ui.button(gui, "SHOP", Ui.shade(Ui.GREEN, -0.3), openShop)
	shopButton.Name = "ShopButton"
	shopButton.AnchorPoint = Vector2.new(1, 1)
	if LIGHT then shopButton.Position = UDim2.new(1, -16 - 2 * (Plaza2D.ICON + Ui.GAP), 1, -10)
	else shopButton.Position, shopButton.Size = UDim2.new(1, -16, 1, -106), UDim2.fromOffset(Plaza2D.CHARACTER_W, 42) end
	self.shopButton = shopButton
	-- Alone at a cabinet: take on the CPU (also C).
	local cpu = Ui.keyButton(gui, "C", "VS CPU", Ui.PURPLE, function()
		if self.active and not self.blocked and self.onCabinet then self.onCabinet({ action = "cpu" }) end
	end, 42)
	cpu.Name, cpu.Visible = "CpuButton", false
	cpu.AnchorPoint = Vector2.new(0.5, 1)
	cpu.Position, cpu.Size = UDim2.new(0.5, 0, 1, if Ui.lightPanels() then -(10 + Plaza2D.ICON + 12 + 50 + 10) else -126), UDim2.fromOffset(190, 42)
	self.cpuButton = cpu
	self.cabinets = {}
	self:placeTop(Ui.topInset())
	return self
end

-- ------------------------------------------------------------------ labels ----
-- World labels are pooled by id: `label` claims one for this frame, `endLabels` hides the rest.
function Plaza2D.label(self: any, id: string, value: string, size: number, colour: Color3): TextLabel
	local t = self.pool[id]
	if not t then
		t = text(self.labelLayer, "Label_" .. id, value, size)
		t.TextStrokeTransparency = 0.55
		self.pool[id] = t
	end
	t.Text, t.TextColor3, t.Visible = value, colour, true
	self.used[id] = true
	return t
end

-- `fit`: a width in studs the words must stay inside (a sign's face), measured through the camera, so
-- world lettering shrinks with its sign on a small screen rather than spilling past it.
function Plaza2D.placeLabel(self: any, c: any, id: string, value: string, x: number, y: number, size: number, colour: Color3, width: number?, fit: number?)
	local at = c:project(x, y)
	if fit then
		local span = math.abs(c:project(x + fit / 2, y).X - c:project(x - fit / 2, y).X)
		while size > 6 and Ui.textWidth(value, size) > span do size -= 1 end
	end
	local t = self:label(id, value, size, colour)
	local w = width or 260
	t.TextSize = Ui.px(size)
	t.Position, t.Size = UDim2.fromOffset(at.X - w / 2, at.Y - size * 1.2), UDim2.fromOffset(w, size * 2.4)
	return t
end

-- A world sign: a station's name on a card of the UI's own kit - a coloured face, its own darker
-- border, a light band at the top and a dark lip under - in white words outlined in the face's shade,
-- as the HUD's buttons are lettered. Bare words floating over the roof (round 0) were a third style
-- beside the HUD and the fighters' name tags. Sized to its words; pooled by id like the labels.
Plaza2D.SIGN_PAD = 10
function Plaza2D.placeSign(self: any, c: any, id: string, value: string, x: number, y: number, size: number, face: Color3): any
	self.signs = self.signs or {}
	local key = "sign:" .. id
	local sg = self.signs[id]
	if not sg then
		local card = Ui.card(self.labelLayer, "Sign_" .. id, face)
		local t, o = Ui.faceText(card, value, size, face)
		t.Size, t.BackgroundTransparency = UDim2.fromScale(1, 1), 1
		sg = { card = card, text = t, outline = o, face = face }
		self.signs[id] = sg
		self.pool[key] = card
		Plaza2D.letterSign(sg, face)
	end
	if sg.face ~= face then Ui.paintCard(sg.card, face); sg.face = face; Plaza2D.letterSign(sg, face) end
	sg.text.Text = value
	local w = 0
	local lines = string.split(value, "\n")
	for _, ln in lines do w = math.max(w, Ui.textWidth(ln, size, Ui.DISPLAY)) end
	w = math.ceil(w) + 2 * Plaza2D.SIGN_PAD
	local h = math.ceil(Ui.px(size, Ui.DISPLAY) * (#lines * 1.1) + Plaza2D.SIGN_PAD)
	-- (`y` is the card's foot, so `signAbove` is one gap everywhere: centred on its point, a two-line
	-- card hung lower than a one-line one and the stalls' signs sank into their awnings)
	local at = c:project(x, y)
	sg.card.Position, sg.card.Size = UDim2.fromOffset(math.floor(at.X - w / 2), math.floor(at.Y - h)), UDim2.fromOffset(w, h)
	sg.card.Visible = true
	self.used[key] = true
	return sg.card
end

-- A sign's lettering: white outlined in the face's shade, or ink on a face too pale for white (the
-- UI's own yellows - the shop's FEATURED tab, the CLAIM pill - are lettered in ink; white on the gold
-- lift's face measured 1.17:1 and read only by its outline).
Plaza2D.PALE_FACE = 2
function Plaza2D.letterSign(sg: any, face: Color3)
	local pale = Ui.contrast(Ui.WHITE, face) < Plaza2D.PALE_FACE
	sg.text.TextColor3 = if pale then Ui.INK else Ui.WHITE
	-- (disabled, not only transparent: an ink word wants no halo at all, as the UI's yellows have none)
	sg.outline.Transparency = if pale then 1 else 0
	sg.outline.Enabled = not pale
	sg.pale = pale
end

-- While the district's title is up (three seconds as you walk in), a sign under it steps aside: the
-- climb's sat beside CLIMBERS' YARD as one line with it, the arcade's and the wardrobe's just under it.
-- The title names the place meanwhile; the sign is back when it fades.
function Plaza2D.clearBanner(self: any)
	local banner = self.banner
	if not banner or banner.TextTransparency >= 1 or not self.signs then return end
	local gw = self.gui.AbsoluteSize and self.gui.AbsoluteSize.X or 1280
	local tw = Ui.textWidth(banner.Text, 40, Ui.DISPLAY)
	local x1, x2 = gw / 2 - tw / 2 - 12, gw / 2 + tw / 2 + 12
	-- (16 px under it at least: 9 px under, the wardrobe's card read as the title's second line)
	local bottom = banner.Position.Y.Offset + banner.Size.Y.Offset + Plaza2D.BANNER_CLEAR
	for _, sg in self.signs do
		local c = sg.card
		if c.Visible and c.Position.Y.Offset < bottom and c.Position.X.Offset + c.Size.X.Offset > x1 and c.Position.X.Offset < x2 then
			c.Visible = false
		end
	end
end

-- A name tag over a cabinet's number rises above the number (Corsair's sat on 06's on one baseline;
-- hiding the number left that cabinet with none).
function Plaza2D.clearTags(self: any)
	-- tags against each other first: one whose words meet another's rises 14 px, back to front (nine
	-- names on two baselines read as one line of text in a crowd)
	local tags: { any } = {}
	for id, t in self.pool do
		if string.sub(id, 1, 4) == "name" and t.Visible then table.insert(tags, t) end
	end
	table.sort(tags, function(a, b) return a.Position.Y.Offset > b.Position.Y.Offset end)
	for i, t in tags do
		local w = Ui.textWidth(t.Text, 12) + 8
		local cx = t.Position.X.Offset + t.Size.X.Offset / 2
		for j = 1, i - 1 do
			local o = tags[j]
			local ow = Ui.textWidth(o.Text, 12) + 8
			local ocx = o.Position.X.Offset + o.Size.X.Offset / 2
			if math.abs(cx - ocx) < (w + ow) / 2 and math.abs(t.Position.Y.Offset - o.Position.Y.Offset) < 18 then
				t.Position = UDim2.fromOffset(t.Position.X.Offset, o.Position.Y.Offset - 18)
			end
		end
	end
	if not self.signs then return end
	for id, t in self.pool do
		if string.sub(id, 1, 4) == "name" and t.Visible then
			local w = Ui.textWidth(t.Text, 12) + 8
			local cx = t.Position.X.Offset + t.Size.X.Offset / 2
			local y1, y2 = t.Position.Y.Offset + t.Size.Y.Offset / 2 - 10, t.Position.Y.Offset + t.Size.Y.Offset / 2 + 10
			for sid, sg in self.signs do
				local c = sg.card
				if c.Visible and string.match(sid, "^cab%d+$") then
					local cx1, cy1 = c.Position.X.Offset, c.Position.Y.Offset
					if cx1 < cx + w / 2 and cx1 + c.Size.X.Offset > cx - w / 2 and cy1 < y2 and cy1 + c.Size.Y.Offset > y1 then
						-- the tag's words (about 20 px tall, centred in its box) end 4 px over the card
						t.Position = UDim2.fromOffset(t.Position.X.Offset, cy1 - 14 - t.Size.Y.Offset / 2)
						y1, y2 = cy1 - 24, cy1 - 4
					end
				end
			end
		end
	end
end

-- A sign whose words run off the screen's side is hidden - all of its words or none (NOTICE BOARD read
-- "ARD", and a marquee 62% on screen read "5" for 05). The billboard's lettering likewise ("BLO").
-- `gw`: the canvas's width (the GUI's AbsoluteSize is stale at start and after a resize).
function Plaza2D.clearEdges(self: any, gw: number)
	if gw <= 0 then return end
	for _, sg in self.signs or {} do
		local c = sg.card
		-- (the whole card: its pad allowed off, NOTICE BOARD lost its left frame)
		local x1 = c.Position.X.Offset
		local x2 = c.Position.X.Offset + c.Size.X.Offset
		if c.Visible and (x1 < 0 or x2 > gw) then c.Visible = false end
	end
	for _, id in { "billboard", "billboard2" } do
		local t = self.pool[id]
		if t and t.Visible then
			local w = Ui.textWidth(t.Text, t.TextSize / Ui.SCALE, t.Font)
			local cx = t.Position.X.Offset + t.Size.X.Offset / 2
			if cx - w / 2 < 0 or cx + w / 2 > gw then t.Visible = false end
		end
	end
end

-- A speech bubble: a pooled label styled once, sized to its text.
function Plaza2D.bubble(self: any, c: any, id: string, value: string, x: number, y: number, alpha: number)
	local t = self:label(id, value, 14, INK)
	self.styled = self.styled or {}
	if not self.styled[id] then
		self.styled[id] = true
		t.BackgroundColor3 = Color3.fromRGB(246, 242, 232)
		t.TextStrokeTransparency = 1
		t.TextWrapped = false
		-- a square speech box, ink-framed, as a pixel game draws one
		Ui.corner(t, 0)
		Ui.stroke(t, INK, 2)
	end
	local at = c:project(x, y)
	local w = Ui.textWidth(value, 14) + 20
	t.Position, t.Size = UDim2.fromOffset(at.X - w / 2, at.Y - 30), UDim2.fromOffset(w, 28)
	t.BackgroundTransparency = 1 - 0.95 * alpha
	t.TextTransparency = 1 - alpha
end

-- What someone just stamped or said, over their head (LobbySocial keeps who and since when).
function Plaza2D.drawOverhead(self: any, c: any, userId: number, x: number, headY: number)
	local social = self.social
	if not social then return end
	local o, age, life = social:overhead(userId)
	if not o then return end
	local fade = math.clamp((life - age) / 0.4, 0, 1)
	if o.kind == "stamp" then
		local stamp
		for _, st in PLAZA.stamps do if st.id == o.id then stamp = st end end
		if not stamp then return end
		local prop = PlazaArt.stamp(stamp)
		-- A pop: overshoot, settle, and a slow bob while it is up.
		local pop = if age < 0.18 then 0.5 + age / 0.18 * 0.75 elseif age < 0.32 then 1.25 - (age - 0.18) / 0.14 * 0.25 else 1
		local k = 0.17 * pop
		local y = headY + 0.8 + math.sin(age * 5) * 0.12
		Canvas.sprite(c, "ovh|" .. o.id, prop.rects, x - prop.w * k / 2, y + prop.h * k, k, k, prop.w, prop.h, fade)
	else
		self:bubble(c, "bub" .. userId, o.text, x, headY + 2.6, fade)
	end
end

function Plaza2D.endLabels(self: any)
	for id, t in self.pool do
		if not self.used[id] then t.Visible = false end
	end
	table.clear(self.used)
end

-- ------------------------------------------------------------------ state ----
function Plaza2D.configure(self: any, cfg: any)
	local sl = cfg.slots[1]
	local key = sl.avatarId .. "/" .. sl.weaponId
	if key == self.loadout then return end
	self.char = Loadout.build(sl.avatarId, sl.weaponId)
	self.loadout = key
	if not self.model then self.model = Plaza.new(PLAZA.market) end
end

function Plaza2D.show(self: any, cfg: any)
	self:configure(cfg)
	self.active, self.gui.Enabled, self.blocked = true, true, false
	self.input:reset()
	self:setRoom(nil)
	self.held = true                                  -- a held key must be released first
end

function Plaza2D.hide(self: any)
	self.active, self.gui.Enabled = false, false
end

function Plaza2D.setRoom(self: any, room: any)
	local nextRoom = if room and not room.left then room else nil
	local oldId = if self.room then self.room.id else 0
	local nextId = if nextRoom then nextRoom.id else 0
	self.room = nextRoom
	if oldId ~= nextId then
		if oldId == 0 then self.returnAt = { x = self.model.p.x, z = self.model.p.z } end
		local scene = if nextRoom then PLAZA.rooms[nextRoom.format] else PLAZA.market
		self.model:setScene(scene, if nextId == 0 then self.returnAt else nil)
		self.camX = self.model.p.x
		self:setPeers({}, 0)
		self.input:reset()
		self.held = true
		self.district = nil
	end
	self.characterButton.Visible = nextRoom == nil
	self.lockerButton.Visible = nextRoom == nil
	self.shopButton.Visible = nextRoom == nil
	self.gui:SetAttribute("Scene", self.model.data.id)
	self.gui:SetAttribute("RoomId", nextId)
	if nextRoom then
		local ready, humans, bots = 0, 0, 0
		for _, slot in nextRoom.slots do
			if slot.userId then humans += 1; if slot.ready then ready += 1 end end
			if slot.bot then bots += 1 end
		end
		local shown = shownMap(nextRoom)
		local map = if nextRoom.mapChoice == "random" then "Random map"
			elseif nextRoom.mapChoice == "vote" then (if shown then `Vote: {Realms.name(shown)} leads` else "Vote for a map")
			else (if shown then Realms.name(shown) else "Random map")
		local rules = if nextRoom.mode == "timed" then `Timed {(nextRoom.time or 180) // 60} min` else `{nextRoom.stocks or 3} lives`
		self.title.Text = string.upper(Realms.place("lounge", self.model.data.name))
		self.directions.Text = nextRoom.error or `{ready}/{humans} ready · {bots} {if bots == 1 then "CPU" else "CPUs"} · {map} · {rules}`
	else
		self.title.Text = string.upper(Realms.LOBBY.name)
		-- (short: the long line grew the card to 81% of the screen's width)
		-- (short: the long line took the card to 62% of the screen, 94% of a phone's)
		self.directions.Text = "East: cabinets, gates, climb  ·  West: tailor"
	end
end

function Plaza2D.setPeers(self: any, entries: any, localId: number)
	local present = {}
	local area = if self.room then self.room.id else 0
	for _, entry in entries do
		if entry.userId ~= localId and (entry.area or 0) == area then
			local key = entry.avatar .. "/" .. entry.weapon
			local peer = self.peers[entry.userId]
			if not peer then
				peer = { x = entry.x, z = entry.z or 8, y = entry.y or 0, name = entry.name }
				self.peers[entry.userId] = peer
			end
			if peer.key ~= key then
				peer.char = Loadout.build(entry.avatar, entry.weapon)
				peer.key = key
			end
			peer.target, present[entry.userId] = entry, true
		end
	end
	for id in self.peers do
		if not present[id] then self.peers[id] = nil end
	end
end

-- The arcade as the server last described it (Cabinets.views), and which seat, if any, is yours.
function Plaza2D.setCabinets(self: any, views: any, localId: number)
	if type(views) ~= "table" then return end
	local byNumber = {}
	local mine = nil
	for _, v in views do
		byNumber[v.number] = v
		for side, seat in v.seats or {} do
			if seat.userId == localId then mine = `Cab{v.number}{side}` end
		end
	end
	self.cabinets = byNumber
	self.seatId = mine
end

function Plaza2D.seatStation(self: any): any
	if not self.seatId or self.room then return nil end
	for _, st in PLAZA.market.stations do
		if st.id == self.seatId then return st end
	end
	return nil
end

-- What using a cabinet seat means right now: get up from yours, watch a fight, or sit down.
function Plaza2D.cabinetIntent(self: any, st: any): any
	local view = self.cabinets[st.cabinet]
	if self.seatId then
		return if self.seatId == st.id then { action = "stand" } else nil
	end
	if view and view.state == "playing" then return { action = "watch", cabinet = st.cabinet } end
	local side = if st.side < 0 then "A" else "B"
	if view and view.seats and view.seats[side] then return nil end
	return { action = "sit", cabinet = st.cabinet, side = side }
end

function Plaza2D.interact(self: any)
	if not self.active or self.blocked or UIS:GetFocusedTextBox() then return end
	local seat = self:seatStation()
	local station = seat or self.model:nearest()
	if station and station.kind == "Cabinet" then
		local intent = self:cabinetIntent(station)
		if intent and self.onCabinet then self.onCabinet(intent) end
		return
	end
	if station and self.onInteract then self.onInteract(station) end
end

function Plaza2D.warp(self: any, id: string): boolean
	return self.model:warp(id)
end

function Plaza2D.step(self: any, dt: number, blocked: boolean)
	if not self.active then return end
	self.blocked = blocked
	for _, frame in self.input:sample(dt, Config.FRAME) do
		self.model:step(if blocked then Input.emptyFrame() else frame)
	end
	-- Seated, you stay at the machine, facing it: put back at the seat after every step, which also
	-- undoes any walking or hop the frames just made.
	local seat = self:seatStation()
	if seat then
		local p = self.model.p
		if p.x ~= seat.x or p.z ~= seat.z then self.model:setScene(self.model.data, { x = seat.x, z = seat.z }) end
		p.facing = seat.facing
	end
	local view = seat and self.cabinets[seat.cabinet]
	local alone = view ~= nil and view.state == "open" and not (view.seats.A and view.seats.B)
	self.cpuButton.Visible = alone and not blocked
	local cDown = alone and not UIS:GetFocusedTextBox() and UIS:IsKeyDown(Enum.KeyCode.C)
	if cDown and not self.cHeld and not blocked and self.onCabinet then self.onCabinet({ action = "cpu" }) end
	self.cHeld = cDown
	-- L opens and closes the Locker (the Locker itself is not one of the panels that block the lobby)
	local lDown = not UIS:GetFocusedTextBox() and UIS:IsKeyDown(Enum.KeyCode.L)
	if lDown and not self.lHeld and self.onLocker then self.onLocker() end
	self.lHeld = lDown
	local down = not UIS:GetFocusedTextBox() and (UIS:IsKeyDown(Enum.KeyCode.E)
		or UIS:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonX))
	if down and not self.held then self:interact() end
	self.held = down
end

-- ------------------------------------------------------------------ drawing: the ground ----
-- Under each roof of the bazaar, the floating island it stands on: the same RealmArt body the arenas
-- use, hanging from the roof's front edge. Built once.
local function underside(c: any, r: any, i: number)
	local body = RealmArt.island(Realms.LOBBY, r.x2 - r.x1, 6, 20 + i)
	RealmArt.draw(c, body, r.x1, r.z1 * D, 1 / RealmArt.BODY_PPU)
end

function Plaza2D.drawGround(self: any, c: any, scene: any, left: number, right: number)
	for i, r in scene.floor do
		if r.x2 < left or r.x1 > right then continue end
		local bridge = r.bridge == true
		local y1, y2 = r.z1 * D, r.z2 * D
		if bridge then
			-- Planks across the sky between two islands, with a rope rail either side.
			Canvas.rect(c, r.x1, y1, r.x2 - r.x1, y2 - y1, Canvas.hex(A.woodDk, INK))
			for x = r.x1 + 0.2, r.x2 - 0.6, 1.1 do
				Canvas.rect(c, x, y1 + 0.05, 0.9, y2 - y1 - 0.1, Canvas.hex(A.wood, INK))
			end
			Canvas.rect(c, r.x1, y2 + 1.1, r.x2 - r.x1, 0.12, Canvas.hex(A.paper, WHITE), 0.6)
			Canvas.rect(c, r.x1, y1 - 0.4, r.x2 - r.x1, 0.3, Canvas.hex(A.woodDk, INK))
		else
			underside(c, r, i)
			-- the paving, as one sprite: a plaza of flagstones is hundreds of joints
			local paving = RealmArt.paving(Realms.LOBBY, r.x2 - r.x1, y2 - y1, i)
			RealmArt.draw(c, paving, r.x1, y1, 1 / RealmArt.BODY_PPU)
			Canvas.rect(c, r.x1, y1 - 0.2, r.x2 - r.x1, 0.35, Canvas.hex(Realms.LOBBY.top[2], INK))  -- the grass lip
			-- an ink rim round the roof's ends and along its front, as the arenas' islands have (its ends
			-- were the pale paving straight onto the pale sky, 1.01:1)
			local o = Plaza2D.KIT_INK
			Canvas.rect(c, r.x1 - o, y1 - 0.2, o, y2 - y1 + 1.9, INK)
			Canvas.rect(c, r.x2, y1 - 0.2, o, y2 - y1 + 1.9, INK)
			Canvas.rect(c, r.x1 - o, y2 + 1.7, r.x2 - r.x1 + 2 * o, o, INK)
			Canvas.rect(c, r.x1, y2, r.x2 - r.x1, 1.4, Canvas.hex(A.slate, INK))                     -- the low wall
			Canvas.rect(c, r.x1, y2 + 1.4, r.x2 - r.x1, 0.3, Canvas.hex(A.slateHi, INK))
		end
	end
end

-- The rail along each roof's front edge, drawn over everyone: the nearest thing to the viewer.
function Plaza2D.drawRails(self: any, c: any, scene: any, left: number, right: number)
	for _, r in scene.floor do
		if r.bridge or r.x2 < left or r.x1 > right then continue end
		local y = r.z1 * D - 0.2
		-- a timber fence: a rail on posts
		Canvas.rect(c, r.x1, y + 1.2, r.x2 - r.x1, 0.26, FENCE)
		Canvas.rect(c, r.x1, y + 1.2, r.x2 - r.x1, 0.08, FENCE_HI)
		for x = math.ceil(r.x1 / 4) * 4, r.x2, 4 do
			Canvas.rect(c, x - 0.12, y, 0.24, 1.6, FENCE)
		end
	end
end

-- ------------------------------------------------------------------ drawing: people ----
-- Presentation-only distance on the plaza floor, keyed by actor rather than loadout: two people
-- wearing the same kit must not advance each other's stride. The mirror reads the same actor.
local strides: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
local function stride(actor: any, char: any): number
	local prev = strides[actor]
	if not prev then
		prev = { x = actor.x, z = actor.z, distance = 0 }
		strides[actor] = prev
	end
	local dx, dz = actor.x - prev.x, actor.z - prev.z
	local distance = math.sqrt(dx * dx + dz * dz)
	-- A warp starts afresh, instead of inserting a roof's worth of steps into the next pose.
	prev.distance = if distance > char.height * 2 then 0 else prev.distance + distance
	prev.x, prev.z = actor.x, actor.z
	return prev.distance
end
local function posed(char: any, state: string, sf: number, x: number, z: number, y: number, facing: number, vx: number, actor: any?): any
	local st = PosedFighter.posed(char, 0, state, sf)
	st.x, st.y, st.facing, st.vx = x, y + z * D, facing, vx
	st.onGround = y <= 0.01
	if actor then
		st.strideDistance = stride(actor, char)
		if actor.vx ~= nil and actor.vz ~= nil then
			st.vx = facing * math.sqrt(actor.vx * actor.vx + actor.vz * actor.vz)
		end
	end
	return st
end

function Plaza2D.drawPerson(self: any, c: any, char: any, st: any, z: number, clock: number)
	Fighter2D.draw(c, st, char, clock, z * D)
end

local function vendorChar(self: any, id: string): any
	local v = self.vendors[id]
	if not v then
		for _, p in KIT.presets do
			if p.id == id then
				v = table.clone(Loadout.build(p.code, "Sword"))
				v.weapon = nil                             -- vendors sell; they do not fight
			end
		end
		self.vendors[id] = v
	end
	return v
end

-- ------------------------------------------------------------------ drawing: the market ----
function Plaza2D.marketItems(self: any, c: any, add: (number, () -> ()) -> (), clock: number)
	local model = self.model
	-- The billboard over the square: the game's name, and who is on the rooftop tonight.
	add(24, function()
		local bb = PlazaArt.get("billboard", PlazaArt.billboard)
		-- 0.7 scale: the screen is 23 studs across, 10 tall, standing over the stalls.
		local k, base = 0.7, 24 * D
		PlazaArt.draw(c, "billboard", bb, 0, base, k)
		local sx0, sy0, sw, sh = -16.5 * k, base + 7.5 * k, 33 * k, 10.25 * k
		local pulse = 0.55 + 0.25 * math.sin(clock * 2.2)
		Canvas.rect(c, sx0, sy0, sw, sh, AMBER, 0.03 + pulse * 0.03)
		for i = 0, 7 do
			Canvas.rect(c, sx0, sy0 + ((clock * 2 + i * 1.3) % sh), sw, 0.1, CYAN, 0.05)
		end
		local title = self:placeLabel(c, "billboard", "BLOCKFALL", 0, sy0 + sh * 0.66, 40, AMBER, 520, sw * 0.86)
		local n = 1
		for _ in self.peers do n += 1 end
		-- (Plaza2D.BILLBOARD_LINE, not the scanlines' CYAN: at #7FA8B8 it measured 2.8:1 on the screen; and
		-- the short line where the full one would shrink below 11 px)
		local full = if n == 1 then "THE ARCADE IS OPEN  ·  THE GATES ARE OPEN" else `{n} ON THE ROOF TONIGHT  ·  ARCADE OPEN`
		local span = math.abs(c:project(sw * 0.45, 0).X - c:project(-sw * 0.45, 0).X)
		local line = if Ui.textWidth(full, 11) <= span then full elseif n == 1 then "THE ARCADE IS OPEN" else `{n} ON THE ROOF TONIGHT`
		local sub = self:placeLabel(c, "billboard2", line, 0, sy0 + sh * 0.25, 14, Plaza2D.BILLBOARD_LINE, 520, sw * 0.9)
		-- (a full ink outline on both lines: the board's lighter structure behind them took the white to
		-- 2.9:1 and the gold to 3.0:1)
		sub.TextStrokeTransparency, sub.TextStrokeColor3 = 0, INK
		title.TextStrokeTransparency, title.TextStrokeColor3 = 0, INK
		-- (the game's name in the UI's display face, as its title cards: the body face made it a third
		-- lettering on the roof)
		title.Font, sub.Font = Ui.DISPLAY, Ui.LABEL
	end)
	add(22, function()
		local wt = PlazaArt.get("tower", PlazaArt.waterTower)
		PlazaArt.draw(c, "tower", wt, 76, 22 * D)
		local lights = PlazaArt.get("lights", function() return PlazaArt.stringLights(640) end)
		PlazaArt.draw(c, "lights", lights, -42, 18.6 * D)
		PlazaArt.draw(c, "lights", lights, 42, 18.6 * D)
	end)
	for _, st in STALLS do
		local back = PlazaArt.get("stallB" .. st.sign, function() return PlazaArt.stallBack(st.a, st.b) end)
		local front = PlazaArt.get("stallF" .. st.sign, function() return PlazaArt.stallFront(st.goods) end)
		add(STALL_Z + 0.2, function()
			PlazaArt.draw(c, "stallB" .. st.sign, back, st.x, STALL_Z * D)
			-- (a kit sign in the awning's colour: bare coloured words on a navy board were a second
			-- lettering beside the stations' signs)
			self:placeSign(c, "stall" .. st.sign, st.sign, st.x, STALL_Z * D + Plaza2D.signAbove(78), 14, Plaza2D.awningFace(st.a))
		end)
		add(STALL_Z + 0.1, function()
			local vc = vendorChar(self, st.vendor)
			if vc then
				local s = posed(vc, "idle", math.floor(clock * 60), st.x + 1.5, STALL_Z, 0, -1, 0)
				self:drawPerson(c, vc, s, STALL_Z, clock)
			end
		end)
		add(STALL_Z, function() PlazaArt.draw(c, "stallF" .. st.sign, front, st.x, STALL_Z * D) end)
	end
	add(18.5, function()
		local ac = PlazaArt.get("ac", PlazaArt.acUnit)
		PlazaArt.draw(c, "ac", ac, -80, 18.5 * D)
		PlazaArt.draw(c, "ac", ac, 12, 18.5 * D)
	end)
	add(14, function()
		local k = PlazaArt.get("kiosk", PlazaArt.kiosk)
		PlazaArt.draw(c, "kiosk", k, 0, 12 * D)
		-- The hologram: a turning diamond of light over the projector.
		local turn = math.sin(clock * 1.6)
		-- (low enough to stay under the billboard's screen: higher, it shone between its two lines)
		local cy = 12 * D + 7.6
		for i = 0, 5 do
			local w = (3 - math.abs(i - 2.5) * 1.05) * math.abs(turn) + 0.3
			Canvas.rect(c, -w, cy - 2.8 + i * 1.1, w * 2, 1, CYAN, 0.28)
		end
		-- (stopping under the billboard: up through it, the beam smeared its lettering)
		Canvas.rect(c, -0.12, 12 * D + 6.2, 0.24, 3.4, CYAN, 0.18)
	end)
	-- Tailor's roof: the boutique, its mannequins, and you in its mirror.
	local wardrobe
	for _, s in model.data.stations do if s.kind == "Wardrobe" then wardrobe = s end end
	if wardrobe then
		add(17.4, function()
			local shop = PlazaArt.get("boutique", PlazaArt.boutique)
			PlazaArt.draw(c, "boutique", shop, wardrobe.x, 17.4 * D)
			self:drawWardrobe(c, wardrobe, clock)
		end)
	end
	add(16.6, function()
		local pl = PlazaArt.get("plant", PlazaArt.plant)
		PlazaArt.draw(c, "plant", pl, -144, 16.6 * D)
		PlazaArt.draw(c, "plant", pl, -100, 16.6 * D)
	end)
	add(20.4, function()
		PlazaArt.draw(c, "plant", PlazaArt.get("plant", PlazaArt.plant), 99, 20.4 * D)
		PlazaArt.draw(c, "plant", PlazaArt.get("plant", PlazaArt.plant), 181, 20.4 * D)
	end)
	-- The notice board and the roof map.
	for _, s in model.data.stations do
		if s.kind == "Members" then
			add(s.z + 1, function()
				PlazaArt.draw(c, "board", PlazaArt.get("board", PlazaArt.noticeBoard), s.x, (s.z + 1) * D)
				self:placeSign(c, "st" .. s.id, s.name, s.x, (s.z + 1) * D + Plaza2D.signAbove(60), 13, Plaza2D.STATION_COLOURS.Members)
			end)
		elseif s.kind == "Warp" then
			add(s.z + 1, function()
				PlazaArt.draw(c, "mapsign", PlazaArt.get("mapsign", PlazaArt.mapSign), s.x, (s.z + 1) * D)
				self:placeSign(c, "st" .. s.id, s.name, s.x, (s.z + 1) * D + Plaza2D.signAbove(60), 13, Plaza2D.STATION_COLOURS.Warp)
			end)
		elseif s.kind == "Parkour" then
			add(s.z + 1.6, function()
				PlazaArt.draw(c, "climbgate", PlazaArt.get("climbgate", PlazaArt.climbGate), s.x, (s.z + 1.6) * D)
				-- (on the scaffold's top deck, under the flag: over the flag it met the title card, and beside
				-- the district's title it read as one line with it)
				self:placeSign(c, "climb", s.name, s.x, (s.z + 1.6) * D + Plaza2D.CLIMB_DECK * PlazaArt.CELL, 16, Ui.ORANGE)
			end)
		elseif s.kind == "Records" then
			add(s.z + 1, function()
				PlazaArt.draw(c, "records", PlazaArt.get("records", PlazaArt.recordBoard), s.x, (s.z + 1) * D)
				self:placeSign(c, "records", s.name, s.x, (s.z + 1) * D + Plaza2D.signAbove(76), 13, Ui.INDIGO)
				if self.recordsLine then
					self:placeSign(c, "recordsTop", self.recordsLine, s.x, (s.z + 1) * D + Plaza2D.signAbove(76) + 1.8, 11, Ui.GOLD)
				end
			end)
		elseif s.kind == "Format" then
			add(s.z + 1.8, function()
				local hex = Plaza2D.LIFT_HEX[s.teamSize] or Plaza2D.LIFT_HEX[1]
				local face = Color3.fromHex(hex)
				PlazaArt.draw(c, "lift" .. s.id, PlazaArt.get("lift" .. s.id, function() return PlazaArt.lift(hex, s.teamSize) end), s.x, (s.z + 1.8) * D)
				-- (each lift says what it is: blank, the three read as elevators)
				self:placeSign(c, "st" .. s.id, s.name .. "  " .. s.landmark, s.x, (s.z + 1.8) * D + Plaza2D.signAbove(104), 14, face)
			end)
		end
	end
	-- The arcade: its canopy, and the cabinets, each pair with its stools and number.
	add(20.5, function()
		-- (low, over the cabinets: at 15 studs a band of empty sky and posts lay between beam and machines)
		local canopy = PlazaArt.get("canopy", function() return PlazaArt.canopy(88 * 8, Plaza2D.CANOPY_H) end)
		PlazaArt.draw(c, "canopy", canopy, 140, 20.5 * D)
		-- (on the canopy's beam: over it, the sign sat behind the district's title as you walked in. Its
		-- flicker is in its words: recolouring the card repaints its gradient, border and lip)
		-- (what it is for, not its name again: THE ARCADE sat under THE ARCADE GROVE)
		-- a marquee board standing on the beam, for the arcade's name to hang on (the sky over the canopy
		-- was a quarter of the screen with nothing in it)
		local board = PlazaArt.get("marquee", PlazaArt.arcadeMarquee)
		local beamTop = 20.5 * D + Plaza2D.CANOPY_H * PlazaArt.CELL
		PlazaArt.draw(c, "marquee", board, 140, beamTop)
		-- pennants strung from the board's corners out along the canopy, so the sky either side is not bare
		local half = board.w * PlazaArt.CELL / 2
		local span = math.floor((43 - half) / PlazaArt.CELL)
		local left = PlazaArt.get("buntL", function() return PlazaArt.bunting(span, 34) end)
		local right = PlazaArt.get("buntR", function() return PlazaArt.bunting(span, 34, true) end)
		PlazaArt.draw(c, "buntL", left, 140 - half - span * PlazaArt.CELL / 2, beamTop)
		PlazaArt.draw(c, "buntR", right, 140 + half + span * PlazaArt.CELL / 2, beamTop)
		self:placeSign(c, "arcade", "1v1 CABINETS", 140, beamTop + Plaza2D.MARQUEE_FOOT * PlazaArt.CELL, 22, Ui.TEAL)
	end)
	for _, cab in PLAZA.cabinets do
		add(cab.z, function()
			if cab.z > Plaza2D.CAB_BACK then
				-- (smaller as well as darker: the same size at the same x, the two rows read as one locker)
				PlazaArt.draw(c, "cabFar", PlazaArt.get("cabFar", function() return PlazaArt.cabinetPair(true) end), cab.x, cab.z * D, Plaza2D.CAB_FAR_SCALE)
			else
				PlazaArt.draw(c, "cab", PlazaArt.get("cab", PlazaArt.cabinetPair), cab.x, cab.z * D)
			end
			local flick = 0.7 + 0.3 * math.sin(clock * 9 + cab.number)
			Canvas.rect(c, cab.x - 2.2, cab.z * D + 3.3, 0.3, 2, CYAN, 0.25 * flick)
			Canvas.rect(c, cab.x + 1.9, cab.z * D + 3.3, 0.3, 2, PINK, 0.25 * flick)
			-- (on its own marquee: above it, the front row's numbers sat on the back row's cabinets)
			local far = cab.z > Plaza2D.CAB_BACK
			self:placeSign(c, "cab" .. cab.number, string.format("%02d", cab.number), cab.x,
				cab.z * D + (if far then 44 * PlazaArt.CELL * Plaza2D.CAB_FAR_SCALE else 5.6), if far then 12 else 14, Ui.INDIGO)
			-- What the cabinet is doing: a countdown, a fight (and who is watching), the streak.
			local view = self.cabinets[cab.number]
			if view then
				if view.state == "countdown" and view.startsIn then
					-- (what a cabinet is doing, on tags of the same kit over its marquee: bare coloured words
					-- were the last lettering on the roof outside the kit)
					self:placeSign(c, "cabT" .. cab.number, `READY · {math.ceil(view.startsIn)}`, cab.x, cab.z * D + 8.6, 12, Ui.SKY)
				elseif view.state == "playing" then
					local watchers = if (view.watchers or 0) > 0 then ` · {view.watchers} watching` else ""
					self:placeSign(c, "cabT" .. cab.number, (if view.cpu then "VS CPU" else "IN PLAY") .. watchers, cab.x, cab.z * D + 8.6, 12, Ui.PINK)
					Canvas.rect(c, cab.x - 3.2, cab.z * D + 3.2, 6.4, 2.4, PINK, 0.08 + 0.06 * math.sin(clock * 12))
				end
				if view.streak and view.streak.wins > 0 then
					local s2 = if view.streak.wins == 1 then "1 WIN" else `{view.streak.wins} WINS`
					self:placeSign(c, "cabS" .. cab.number, `{s2}  {view.streak.name}`, cab.x, cab.z * D + 10.2, 12, Ui.GOLD)
				end
			end
		end)
		for _, side in { -1, 1 } do
			add(cab.z - 0.05, function()
				PlazaArt.draw(c, "stool", PlazaArt.get("stool", PlazaArt.stool), cab.x + side * 5, cab.z * D)
			end)
		end
	end
end

-- ------------------------------------------------------------------ drawing: the lounge ----
local function boardThumb(c: any, shapes: { any }, x0: number, y0: number, w: number, h: number, K: number)
	Canvas.save(c)
	Canvas.translate(c, x0, y0 + h)
	Canvas.scale(c, 1 / K, -1 / K)
	for _, sh in shapes do
		Canvas.rect(c, sh[2], sh[3], sh[4], sh[5], Canvas.hex(sh[6], INK), sh[7])
	end
	Canvas.restore(c)
end

-- How many columns the weapon rack needs to hold `n` weapons in three rows (at least four).
function Plaza2D.rackColumns(n: number): number
	return math.max(4, math.ceil(n / 3))
end

-- A preparation station, standing at its depth. The room's own state is drawn on it: the map
-- board the map, the ready rail a lamp per place, the rules board lives or a clock, the rack your
-- weapon.
-- Each lounge station's colour, the HUD's own: the map board blue as the MAP button, the rack the
-- orange of a weapon card, the rules purple, the ready rail green as READY.
Plaza2D.STATION_COLOURS = { Maps = Ui.BLUE, Weapons = Ui.ORANGE, Rules = Ui.VIOLET, Players = Ui.GREEN, Exit = Ui.PINK,
	Members = Ui.TEAL, Warp = Ui.GREEN }
-- the lifts by team size: 1v1 gold, 2v2 blue, 3v3 pink (the HUD's own)
Plaza2D.LIFT_HEX = { [1] = "#FEE761", [2] = "#0099DB", [3] = "#F6757A" }
-- How far above a prop's base its sign sits: the prop's own height (`cells` tall, in PlazaArt cells)
-- and a fixed gap, so every sign hangs the same distance over what it names (at one fixed height, the
-- weapon rack's overlapped its frame and the ready rail's floated 67 px up).
Plaza2D.SIGN_GAP = 0.9
-- the climb's sign stands on its scaffold's top deck (rows of PlazaArt.climbGate), under the flag
Plaza2D.CLIMB_DECK = 124
function Plaza2D.signAbove(cells: number, scale: number?): number
	return cells * PlazaArt.CELL * (scale or 1) + Plaza2D.SIGN_GAP
end
-- A stall's sign face: its awning colour, as a UI card would carry it.
function Plaza2D.awningFace(hex: string): Color3
	return Color3.fromHex(hex)
end

-- A box in the UI's kit, in world units, y up: an ink outline, its face, a light band along the top
-- and a dark lip along the bottom (the HUD's buttons and cards, the fighters' ink). The lounge's
-- stations were flat near-black slabs (#262B35) with no edge on the pale paving.
local function kitBox(c: any, x: number, y: number, w: number, h: number, face: Color3)
	local o, b = Plaza2D.KIT_INK, Plaza2D.KIT_BAND
	Canvas.rect(c, x - o, y - o, w + 2 * o, h + 2 * o, INK)
	Canvas.rect(c, x, y, w, h, face)
	Canvas.rect(c, x, y + h - b, w, b, Ui.shade(face, 0.35))
	Canvas.rect(c, x, y, w, b, Ui.shade(face, -0.35))
end
Plaza2D.kitBox = kitBox

local function stationArt(c: any, s: any, active: boolean, room: any, weaponId: string?)
	local x = s.x
	local colour = AMBER
	local face = Plaza2D.STATION_COLOURS[s.kind] or Ui.INDIGO
	-- the desk a darker shade of the station's colour (in full, four desks were the loudest masses in
	-- the room), and a frame round its screen in the colour itself
	kitBox(c, x - 6, 0, 12, 5, Ui.shade(face, -0.3))
	local top = 5 + Plaza2D.KIT_INK
	local function screen(x0: number, y0: number, w: number, h: number)
		kitBox(c, x0 - 0.5, y0 - 0.5, w + 1, h + 1, face)
		-- (a deep shade of the station's colour, not ink: four ink screens made the room mostly black)
		Canvas.rect(c, x0, y0, w, h, Ui.shade(face, -0.72))
		top = math.max(top, y0 + h + 0.5 + Plaza2D.KIT_INK)
	end
	if s.kind == "Weapons" then
		screen(x - 8, 5.3, 16, 9)
		-- Three rows inside the rack's panel, as many columns as the roster needs, spread across
		-- its width: a fixed four a row put the 13th and 14th weapons below the panel.
		local cols = Plaza2D.rackColumns(#Weapons.LIST)
		local step = 12.8 / math.max(1, cols - 1)
		local art = math.min(0.45, step * 0.13)
		for i, weapon in Weapons.LIST do
			local gx, gy = x - 6.4 + ((i - 1) % cols) * step, 7 + math.floor((i - 1) / cols) * 2.6
			if weapon.id == weaponId then
				Canvas.rect(c, gx - step * 0.45, gy - 1.1, step * 0.9, 2.4, AMBER, 0.9)
				Canvas.rect(c, gx - step * 0.4, gy - 0.9, step * 0.8, 2.0, INK)
			end
			Canvas.save(c)
			Canvas.translate(c, gx, gy)
			Canvas.scale(c, art, art)
			WeaponArt.draw(c, weapon.id, weapon.palette, { angle = 0.2, ox = 0, oy = 0, scale = 1, charge = 0 })
			Canvas.restore(c)
		end
	elseif s.kind == "Maps" then
		screen(x - 5.6, 5.3, 11.2, 7.6)
		local stage = shownMap(room)
		boardThumb(c, if stage then StageThumb.shapes(Realms.dress(stage), 100, 64) else StageThumb.random(100, 64), x - 5, 5.7, 10, 6.4, 10)
	elseif s.kind == "Players" then
		screen(x - 6, 5.3, 12, 4)
		local slots = if room then room.slots else {}
		local n = math.max(1, #slots)
		for i = 1, n do
			local slot = slots[i]
			local lx = x - 5 + (i - 0.5) * (10 / n)
			local lamp = if not slot or (not slot.userId and not slot.bot) then METAL
				elseif slot.ready or slot.bot then READY else AMBER
			Canvas.rect(c, lx - 0.6, 6.4, 1.2, 1.8, lamp)
			Canvas.rect(c, lx - 0.9, 8.4, 1.8, 0.3, if slot and slot.team == 1 then TEAM2 else TEAM1)
		end
	elseif s.kind == "Rules" then
		screen(x - 4, 5.3, 8, 6)
		if room and room.mode == "timed" then
			Canvas.circle(c, x, 8.3, 2.2, colour)
			Canvas.circle(c, x, 8.3, 1.8, INK)
			Canvas.rect(c, x - 0.15, 8.3, 0.3, 1.4, WHITE)
			Canvas.rect(c, x, 8.15, 1.1, 0.3, WHITE)
		else
			local lives = if room then room.stocks or 3 else 3
			for i = 1, lives do
				Canvas.rect(c, x - 3.4 + (i - 1) * 1.5, 7.6, 1.1, 1.1, colour)
			end
		end
	end
	if active then
		Canvas.rect(c, x - 2, 0.6, 4, 0.3, WHITE)
		Canvas.rect(c, x - 1, 1, 2, 0.3, WHITE)
	end
	return top
end
Plaza2D.stationArt = stationArt

function Plaza2D.loungeItems(self: any, c: any, add: (number, () -> ()) -> (), clock: number)
	local near = self.model:nearest()
	-- The room's back wall, behind everything: a kit wall (ink top, light band, a deep indigo face)
	-- with tall windows onto the sky and a pennant in each station's colour, so the lounge reads as a
	-- room and its upper fifth is not empty sky (larger stations could not fill it: the camera fits
	-- the room's width).
	add(Plaza2D.WALL_Z, function()
		local b = self.model.data.bounds
		local cells = math.floor((b.x2 - b.x1) / PlazaArt.CELL + 0.5)
		local wall = PlazaArt.get("wall" .. cells, function()
			return PlazaArt.loungeWall(cells, math.floor(Plaza2D.WALL_H / PlazaArt.CELL), Plaza2D.WALL_WINDOWS, Realms.LOBBY.sky[2])
		end)
		PlazaArt.draw(c, "wall" .. cells, wall, (b.x1 + b.x2) / 2, Plaza2D.WALL_Z * D)
	end)
	add(18.4, function()
		local lights = PlazaArt.get("lights", function() return PlazaArt.stringLights(640) end)
		PlazaArt.draw(c, "lights", lights, 0, 18.4 * D)
		local pl = PlazaArt.get("plant", PlazaArt.plant)
		PlazaArt.draw(c, "plant", pl, -41, 18.4 * D)
		PlazaArt.draw(c, "plant", pl, 41, 18.4 * D)
	end)
	add(17.8, function()
		PlazaArt.draw(c, "couchP", PlazaArt.get("couchP", function() return PlazaArt.couch(A.pinkDk) end), -31, 17.8 * D)
		PlazaArt.draw(c, "couchC", PlazaArt.get("couchC", function() return PlazaArt.couch(A.cyanDk) end), 7, 17.8 * D)
	end)
	for _, s in self.model.data.stations do
		if s.kind == "Exit" then
			add(s.z + 8, function()
				-- The stairwell back down to Neon Row.
				local x, y = s.x, 16 * D
				-- a doorway in the kit (pink frame, ink outline) round a dark stairwell
				kitBox(c, x - 3.6, y + 1, 7.2, 12.8, Ui.shade(Ui.PINK, -0.15))
				Canvas.rect(c, x - 3, y + 1, 6, 12, Ui.shade(Ui.PINK, -0.75))
				for i = 0, 5 do Canvas.rect(c, x - 2.6, y + 1.2 + i * 1.6, 5.2, 0.3, Ui.shade(Ui.PINK, -0.35)) end
				self:placeSign(c, "st" .. s.id, s.name .. "\n" .. s.landmark, x, y + 13.8 + Plaza2D.SIGN_GAP, 14, Ui.PINK)
			end)
		else
			add(s.z + 1, function()
				-- At STATION_SCALE about its base: the stations were drawn for the old hub's wider camera.
				local k = Plaza2D.STATION_SCALE
				Canvas.save(c)
				Canvas.translate(c, s.x, (s.z + 1) * D)
				Canvas.scale(c, k, k)
				Canvas.translate(c, -s.x, 0)
				local top = stationArt(c, s, near == s, self.room, self.char and self.char.weapon and self.char.weapon.id)
				Canvas.restore(c)
				self:placeSign(c, "st" .. s.id, s.name, s.x, (s.z + 1) * D + top * k + Plaza2D.SIGN_GAP, 14, Plaza2D.STATION_COLOURS[s.kind] or Ui.INDIGO)
			end)
		end
	end
end

-- ------------------------------------------------------------------ the wardrobe ----
function Plaza2D.drawWardrobe(self: any, c: any, s: any, clock: number)
	local presets = KIT.presets
	local turn = math.floor(clock / MANNEQUIN_SECONDS)
	local baseY = 17.4 * D
	for k, side in { -1, 1 } do
		local code = presets[(turn * 2 + k) % #presets + 1].code
		local m = self.mannequins[k]
		if not m or m.code ~= code then
			local char = table.clone(Loadout.build(code, "Sword"))
			char.weapon = nil
			m = { code = code, char = char }
			self.mannequins[k] = m
		end
		local st = posed(m.char, "idle", math.floor(clock * 60), s.x + side * 5.6, 17.4, 0.5, -side, 0)
		Fighter2D.draw(c, st, m.char, clock + k * 0.7, baseY + 0.5)
	end
	if self.char then
		local p = self.model.p
		local r = posed(self.char, p.state, p.sf, s.x, 17.4, 0.6 + math.max(0, p.y) * 0.3, -p.facing, p.vx, p)
		r.onGround = p.y <= 0.01
		Fighter2D.draw(c, r, self.char, clock, baseY + 0.6)
	end
	-- (the glass over your reflection, strong enough that it reads as one: at 0.1 the knight in the
	-- mirror read as a second player standing in the doorway)
	Canvas.rect(c, s.x - 2.4, baseY + 0.9, 4.8, 8.7, Canvas.hex(Realms.LOBBY.sky[3], WHITE), Plaza2D.MIRROR_GLASS)
	Canvas.rect(c, s.x - 1.6, baseY + 6.8, 0.25, 2.2, WHITE, 0.25)
	Canvas.rect(c, s.x - 1.1, baseY + 7.6, 0.2, 1.3, WHITE, 0.18)
	-- (just over the awning: higher, it met the district's title as you walked in)
	-- (its foot on the awning, not over it: over it, the card was 9 px under the district title)
	self:placeSign(c, "wardrobe", s.name .. "\n" .. s.landmark, s.x, baseY + 100 * PlazaArt.CELL, 15, Ui.PINK)
end

-- ------------------------------------------------------------------ the frame ----
function Plaza2D.draw(self: any, c: any, dt: number)
	-- Team colours are a match's; the lobby is not one.
	local teams = Fighter2D.teamColours
	Fighter2D.teamColours = nil
	self:drawScene(c, dt)
	Fighter2D.teamColours = teams
end

function Plaza2D.drawScene(self: any, c: any, dt: number)
	local model = self.model
	local p = model.p
	local scene = model.data
	local clock = os.clock()
	local vp = c:viewport()
	local b = scene.bounds
	-- (a short screen sees a little more of the roof - 46 studs tall, not 38 - so its walking band
	-- clears the buttons' row and its billboard the title card: framed lower instead, BLOCKFALL went
	-- under the card)
	local ppu = math.clamp(vp.Y / (if vp.Y < Plaza2D.SHORT_SCREEN then Plaza2D.SHORT_STUDS else 38), 6, 22)
	-- a lounge is one room: all of it in view (at the market's scale its right-hand station and the
	-- stairs out were off the screen's edges)
	-- (fitting the stations, stairs to ready rail, not the island's whole width: fitted to the island
	-- the room's people stood a third smaller than the market's)
	local roomLo, roomHi = b.x1, b.x2
	if scene.kind ~= "plaza" then
		roomLo, roomHi = math.huge, -math.huge
		for _, st in scene.stations do
			local reach = if st.kind == "Exit" then 4.5 else 8 * Plaza2D.STATION_SCALE + 0.6
			roomLo, roomHi = math.min(roomLo, st.x - reach), math.max(roomHi, st.x + reach)
		end
		roomLo, roomHi = math.max(roomLo, b.x1), math.min(roomHi, b.x2)
		ppu = math.min(ppu, vp.X / (roomHi - roomLo))
	end
	local half = vp.X / ppu / 2
	local target = p.x + p.facing * 4
	if b.x2 - b.x1 > half * 2 then
		target = math.clamp(target, b.x1 + half, b.x2 - half)
	else
		target = (b.x1 + b.x2) / 2
	end
	if scene.kind ~= "plaza" then target = (roomLo + roomHi) / 2 end
	self.camX += (target - self.camX) * math.min(1, dt * 6)
	RealmArt.sky(c, Realms.LOBBY, self.camX, clock)
	-- Framed on the plaza, not the island under it: the underside is a strip at the bottom.
	-- (a lounge framed higher on its stations: framed as the market, a quarter of the screen under its
	-- rail was empty floor and island)
	-- (and a short screen's world framed lower, so the walking band clears the buttons' row: on a
	-- phone the buttons sat on its front 32 px)
	c:world(self.camX, 12.5 + p.z * D * 0.3 + (if scene.kind ~= "plaza" then Plaza2D.LOUNGE_LIFT else 0)
		- (if vp.Y < Plaza2D.SHORT_SCREEN then Plaza2D.SHORT_LIFT else 0), ppu, 0, 0)
	local left, right = self.camX - half - 12, self.camX + half + 12
	self:drawGround(c, scene, left, right)

	-- Everything that stands on the roof, sorted back to front by depth.
	local items: { any } = {}
	local seq = 0
	local function add(z: number, fn: () -> ())
		seq += 1
		table.insert(items, { z = z, seq = seq, fn = fn })
	end
	if scene.kind == "plaza" then self:marketItems(c, add, clock) else self:loungeItems(c, add, clock) end
	for id, peer in self.peers do
		local goal = peer.target
		local blend = math.min(1, dt * 14)
		peer.x += (goal.x - peer.x) * blend
		peer.z += ((goal.z or 8) - peer.z) * blend
		peer.y += ((goal.y or 0) - peer.y) * blend
		if peer.x > left and peer.x < right then
			add(peer.z, function()
				local state = if peer.y > 0.1 then "air" elseif goal.moving then "run" else "idle"
				local st = posed(peer.char, state, math.floor(clock * 60), peer.x, peer.z, peer.y, goal.facing or 1, if goal.moving then (goal.facing or 1) * 15 else 0, peer)
				self:drawPerson(c, peer.char, st, peer.z, clock)
				local head = peer.y + peer.z * D + peer.char.height
				-- VIP names in gold (the server's VIP attribute on that player, read through `isVip`)
				local gold = self.isVip and self.isVip(id)
				local tag = self:placeLabel(c, "name" .. id, (if gold then "VIP  " else "") .. (peer.name or ""), peer.x, head + 1.6, 12, if gold then Ui.GOLD else Ui.WHITE, 180)
				-- (outlined whole in ink, as the HUD's words: at a 0.55 stroke a name over the pale sky
				-- or paving was grey on grey)
				tag.Font = Ui.LABEL
				-- (a 2 px ink outline, as the signs' words: TextStroke is 1 px, and white on the paving is
				-- 1.7-2.9:1 without it)
				self.tagStrokes = self.tagStrokes or {}
				if not self.tagStrokes[id] then
					self.tagStrokes[id] = Ui.outline(tag, 2, INK)
					tag.TextStrokeTransparency = 1
				end
				self:drawOverhead(c, id, peer.x, head + 1.4)
			end)
		end
	end
	if self.char then
		add(p.z, function()
			local st = posed(self.char, p.state, p.sf, p.x, p.z, p.y, p.facing, p.vx, p)
			self:drawPerson(c, self.char, st, p.z, clock)
			if self.localId then self:drawOverhead(c, self.localId, p.x, p.y + p.z * D + self.char.height + 0.2) end
		end)
	end
	table.sort(items, function(a, b2)
		if a.z ~= b2.z then return a.z > b2.z end
		return a.seq < b2.seq
	end)
	for _, it in items do it.fn() end
	self:drawRails(c, scene, left, right)

	-- The district you are in, announced as you enter it.
	local d = model:district()
	-- (not in a lounge: its name is the title card's already, and the two read THE WAR ROOM twice)
	if d and d.id ~= self.district and scene.kind == "plaza" then
		self.district = d.id
		self.banner.Text = string.upper(Realms.place(d.id, d.name))
		self.bannerAt = clock
	end
	local age = clock - self.bannerAt
	-- (not on a narrow screen: there the billboard fills the only space for it, and the title card
	-- already says where you are)
	self.banner.TextTransparency = if self.bannerNarrow then 1 elseif age < 2 then 0 elseif age < 3 then age - 2 else 1
	self.bannerOutline.Transparency = self.banner.TextTransparency

	local near = self:seatStation() or model:nearest()
	local cabinetWord = nil
	if near and near.kind == "Cabinet" then
		local intent = self:cabinetIntent(near)
		cabinetWord = if not intent then "TAKEN:" elseif intent.action == "stand" then "STAND UP FROM"
			elseif intent.action == "watch" then "WATCH" else "SIT AT"
		if intent and intent.action == "sit" then
			self:placeSign(c, "seat", "SIT HERE", near.x, near.z * D + 7.2, 13, Ui.GOLD)
		end
	end
	self:endLabels()
	self:clearBanner()
	self:clearTags()
	self:clearEdges(vp.X)
	c:finish()
	self:placeTop(Ui.topInset())
	local gw = self.gui.AbsoluteSize and self.gui.AbsoluteSize.X or 0
	self.plate.Size = UDim2.fromOffset(math.min(math.max(gw - 16, 200),
		math.max(Ui.textWidth(self.title.Text, 22), Ui.textWidth(self.directions.Text, 12)) + 24), 62)
	self.controls.Visible = gw - Plaza2D.SOCIAL_BAR_W - 64 >= self.controlsW
	-- the district's name is not drawn on a narrow screen (it landed on the billboard's lettering)
	self.bannerNarrow = gw > 0 and gw < 1000
	local action = not self.blocked and near ~= nil
	self.prompt.Text = if self.blocked then "Finish at the panel, then carry on."
		elseif near then `{if near.kind == "Format" or near.kind == "Exit" then "ENTER" elseif cabinetWord then cabinetWord else "USE"} {near.name}`
		else if self.room then "Walk to a station to set up the fight." else "Walk the roofs: the arcade and the climb are east, the tailor is west."
	self.prompt.Active = action
	-- (a tip - not an action - goes after a few seconds: it sat over your own fighter on a phone)
	if self.promptLast ~= self.prompt.Text then self.promptLast, self.promptAt = self.prompt.Text, clock end
	-- (on every screen now: on a wide one the tip never went and cut the legs off people at the front.
	-- On a wide screen there is no tip at all - the title card's directions say the same - so the card
	-- at the bottom is only ever an action; a narrow one keeps it, for a few seconds)
	-- (and now on a phone too: its tip covered a stall and the back of the walking band. The title
	-- card's directions say which way things are; the card below is an action, or the blocked note)
	local tipDone = not action and not self.blocked
	self.prompt.Visible = not (self.social and self.social.anyOpen and self.social:anyOpen()) and not tipDone
	-- the card fits its words, so a short line is not a long bar and a long one does not leave a
	-- word alone on a second line
	-- (centred, it stays clear of the button column at the right on both sides: on a phone a long
	-- tip wraps onto its second line rather than running under SHOP and LOCKER)
	-- (a narrow screen in a light theme: under the title card, the full width - centred over the
	-- button row it sat on your own fighter, who stands mid-screen on a phone)
	local high = self.bannerNarrow and Ui.lightPanels()
	if high then
		-- (bottom left, above the dock and clear of the screen's middle: centred it sat on your fighter,
		-- under the title card on the billboard's BLOCKFALL)
		self.prompt.AnchorPoint = Vector2.new(0, 1)
		self.prompt.Position = UDim2.new(0, 16, 1, -(10 + Plaza2D.ICON + 14))
	elseif Ui.lightPanels() then
		-- (in the key hints' row at the bottom left, which it stands in for while it shows: above the
		-- buttons' row it covered the front of the walking band, where a crowd's front row stands)
		self.prompt.AnchorPoint = Vector2.new(0, 1)
		self.prompt.Position = UDim2.new(0, 16, 1, -10)
	else
		self.prompt.AnchorPoint = Vector2.new(0.5, 1)
		self.prompt.Position = UDim2.new(0.5, 0, 1, -62)
	end
	if not high and Ui.lightPanels() and self.prompt.Visible then self.controls.Visible = false end
	local promptMax = if high then math.max(gw / 2 - 16 - Plaza2D.FIGHTER_CLEAR, 160)
		elseif Ui.lightPanels() then math.max(gw - Plaza2D.SOCIAL_BAR_W - 48, 200)
		else math.max(gw - 2 * (Plaza2D.CHARACTER_W + 28), 200)
	local promptWant = Ui.textWidth(self.prompt.Text, if action then 20 else 13) + (if action then 64 else 16) + 24
	-- (taller when the words must wrap, so two lines keep their padding)
	self.prompt.Size = UDim2.new(0, math.min(promptMax, promptWant), 0, if promptWant > promptMax then 66 else 50)
	-- an action (the E key, gold words, a gold rim) or a tip (soft words, no key)
	if self.promptAction ~= action then
		self.promptAction = action
		self.promptKey.Visible = action
		self.prompt.Font = if action then Ui.DISPLAY else Ui.LABEL
		self.prompt.TextSize = Ui.px(if action then 20 else 13)
		-- (on a pale card: dark words, a gold edge for an action; on a dark one gold words)
		self.prompt.TextColor3 = if Ui.lightPanels() then Ui.TEXT elseif action then Ui.GOLD else Ui.WHITE
		self.promptOutline.Enabled = action and not Ui.lightPanels()
		self.promptEdge.Color = if Ui.lightPanels() and action then Ui.shade(Ui.SUN, -0.2) else Ui.INK
		self.promptRim.Color = if action then Ui.GOLD else Ui.PANEL2
		self.promptPad.PaddingLeft = UDim.new(0, if action then 64 else 16)
	end
	self.gui:SetAttribute("NearbyStation", if near then near.id else "")
	self.gui:SetAttribute("FighterX", p.x)
	self.gui:SetAttribute("FighterZ", p.z)
	self.gui:SetAttribute("District", if d then d.id else "")
end

return Plaza2D
