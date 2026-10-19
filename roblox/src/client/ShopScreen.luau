--!strict
-- The Shop (Roblox only; docs/briefs/crates-and-monetisation-plan.md, phase 5; the contract is in
-- docs/briefs/gpt-shop-screen.md): FEATURED items bought outright, FORGE KEYS with their odds shown
-- before purchase, and PASSES.
--
-- It decides nothing: the server's EconomyView `shop` says what is on sale and at what price, and
-- every button is a request (`opts.send`) the server may refuse. A request that the server accepts
-- comes back as a prompt, which `opts.prompt(kind, id)` hands to Roblox's own purchase dialog - that
-- dialog is the confirmation, so a button asks once.
--
-- Rules it keeps: prices are always shown in Robux; no countdown on a purchase, no "was" prices, no
-- premium currency (many players are children); keys have a worded ODDS & DETAILS button with every
-- Forge Crate outcome, from the table the server rolls from (LockerScreen.oddsRows); a player Roblox
-- restricts from paid random items sees no keys at all, and is told why.
local Shared = game:GetService("ReplicatedStorage").Shared
local Cosmetics = require(Shared.Cosmetics)
local Loot = require(Shared.Loot)
local Ui = require(script.Parent.Ui)
local LockerScreen = require(script.Parent.LockerScreen)
local ShopScreen = {}
-- each pass in its own colour; one not built yet goes grey
local PASS_COLOURS = { vip = Ui.SUN, wardrobe = Ui.TEAL, studio = Ui.VIOLET, season = Ui.PINK, emotes = Ui.SKY }
ShopScreen.__index = ShopScreen

-- 26,000 seconds -> "7h 13m"
function ShopScreen.wait(seconds: number): string
	local m = math.max(0, math.floor(seconds / 60))
	if m < 60 then return `{m}m` end
	return `{m // 60}h {m % 60}m`
end

-- A key bundle's per-key price, as its card says it.
function ShopScreen.each(bundle: any): string
	return `{math.floor(bundle.price / bundle.count + 0.5)} R$ each`
end

-- opts: { send = (msg) -> (), prompt = (kind, id) -> (), drawArt = (frame, id, w, h) -> () }
function ShopScreen.new(parent: Instance, opts: any): any
	local self = setmetatable({ opts = opts, view = nil, pending = nil, art = {}, oddsGuaranteed = false,
		featuredCards = {}, keyCards = {}, passCards = {}, grids = {} }, ShopScreen)
	local root = Ui.make("ScreenGui", parent, { Name = "BlockfallShop", ResetOnSpawn = false, Enabled = false, DisplayOrder = 21 })
	self.root = root
	local HEAD = 60                                           -- a heavy header, as the reference shop's
	local panel = Ui.panel(root, "Shop", Ui.RED, "SHOP", HEAD)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position, panel.Size = UDim2.fromScale(0.5, 0.52), UDim2.new(1, -24, 1, -90)
	Ui.make("UISizeConstraint", panel, { MaxSize = Vector2.new(940, 620) })
	self.panel = panel
	-- (every window's close is the same red X: Ui.closeButton)
	Ui.closeButton(panel, function() self:close() end, HEAD)
	-- your balance in the header, the pixel kit's gem and key, as in the Locker
	if Ui.lightPanels() then
		local sp, sv = Ui.currency(panel, "gem", "0")
		local kp, kv = Ui.currency(panel, "key", "0")
		sp.AnchorPoint, kp.AnchorPoint = Vector2.new(1, 0.5), Vector2.new(1, 0.5)
		kp.Position, kp.Size, kp.ZIndex = UDim2.new(1, -60, 0, HEAD / 2), UDim2.fromOffset(84, 32), 3
		-- (100 wide: at 120 a phone's SHOP title ran into it)
		sp.Position, sp.Size, sp.ZIndex = UDim2.new(1, -152, 0, HEAD / 2), UDim2.fromOffset(100, 32), 3
		self.sparksPill, self.keysPill = sv, kv
	end
	local body = Ui.make("ScrollingFrame", panel, { Name = "Body", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.fromOffset(14, HEAD + 52), Size = UDim2.new(1, -28, 1, -(HEAD + (if Ui.lightPanels() then 64 else 90))), CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6 })
	-- (Ui.GAP between the sections: at 10 the hero card's outline came within 4 px of the row under it)
	Ui.make("UIListLayout", body, { Padding = UDim.new(0, if Ui.lightPanels() then Ui.GAP else 10), SortOrder = Enum.SortOrder.LayoutOrder })
	-- (room for the cards' borders, drawn outside them, so the scroll area does not clip the first column)
	Ui.make("UIPadding", body, { PaddingLeft = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) })
	self.body = body
	local function heading(name: string, text: string, order: number): any
		local h = Ui.text(body, text, 20, Ui.TEXT, Ui.DISPLAY, true)
		h.Name, h.LayoutOrder, h.TextXAlignment = name, order, Enum.TextXAlignment.Left
		h.Size = UDim2.new(1, -8, 0, 26)
		return h
	end
	-- a row of `cols` cards that fill its width (no dead space at the right, whatever the window)
	local function row(name: string, order: number, h: number, cols: number): any
		local f = Ui.make("Frame", body, { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, h), AutomaticSize = Enum.AutomaticSize.Y })
		local g = Ui.make("UIGridLayout", f, { CellSize = ShopScreen.cell(cols, h), CellPadding = UDim2.fromOffset(Ui.GAP, Ui.GAP), SortOrder = Enum.SortOrder.LayoutOrder })
		self.grids[name] = { layout = g, cols = cols, h = h }
		return f
	end
	self.featuredHead = heading("FeaturedHead", "FEATURED", 1)
	self.heads = { featured = self.featuredHead }
	-- a section's tab, under the header: the passes sat ten screens down on a phone
	for i, t in { { "featured", "FEATURED" }, { "clothing", "CLOTHING" }, { "keys", "KEYS" }, { "passes", "PASSES" } } do
		local b = Ui.button(panel, t[2], if i == 1 then Ui.SELECTED else Ui.PANEL2, function() self:jump(t[1]) end, { size = 13, small = true })
		b.Name = "Jump_" .. t[1]
		-- (the word fits inside the tab, 6 px in from its edges: on a phone FEATURED touched its stroke)
		Ui.make("UIPadding", b, { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) })
		Ui.fit(b, 10)
		self.jumps = self.jumps or {}
		self.jumps[t[1]] = b
		-- (Ui.GAP between tabs, 14 px in from the window's edges)
		b.Position, b.Size = UDim2.new((i - 1) / 4, if i == 1 then 14 else Ui.GAP / 2, 0, HEAD + 10),
			UDim2.new(0.25, if i == 1 or i == 4 then -(14 + Ui.GAP / 2) else -Ui.GAP, 0, 32)
	end
	-- the day's priciest item leads, wide, as the reference shop's starter pack; the rest beside
	self.hero = ShopScreen.heroCard(body, 2)
	self.featuredRow = row("Featured", 3, 220, 3)
	-- clothing: a heading and a grid row per pack, made as packs arrive
	self.heads.clothing = heading("ClothingHead", "CLOTHING", 4)
	local clothing = Ui.make("Frame", body, { Name = "Clothing", BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = 5,
		Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	Ui.make("UIListLayout", clothing, { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })
	self.clothing, self.packRows = clothing, {}
	self.heads.keys = heading("KeysHead", "FORGE KEYS", 7)
	local keyNote = Ui.text(body, "Forge Keys open Forge Crates: Rare or better, Mythic possible.", 14, Ui.SUB)
	keyNote.Name, keyNote.LayoutOrder, keyNote.TextXAlignment, keyNote.TextWrapped = "KeyNote", 8, Enum.TextXAlignment.Left, true
	keyNote.Size = UDim2.new(1, -8, 0, 34)
	self.keyNote = keyNote
	local odds = Ui.button(body, "ODDS & DETAILS", Ui.BLUE, function() self:showOdds(false) end, { size = 15 })
	odds.Name, odds.LayoutOrder = "Odds", 9
	odds.Size = UDim2.fromOffset(200, 36)
	self.oddsButton = odds
	self.keysRow = row("Keys", 10, 150, 4)
	self.heads.passes = heading("PassesHead", "PASSES", 11)
	-- (three to a row: VIP's six perks wrapped to fourteen lines in a fifth and ran over its price)
	self.passesRow = row("Passes", 12, 270, 3)
	local message = Ui.text(panel, "", 15, Ui.TEXT, nil, true)
	message.Name = "Message"
	message.AnchorPoint = Vector2.new(0.5, 1)
	message.Position, message.Size = UDim2.new(0.5, 0, 1, -8), UDim2.new(1, -24, 0, 26)
	-- (a light theme: a pill over the list's foot, shown while it has something to say, so the list
	-- runs to the window's edge; a line kept for it left a dead 38 px strip under the cards)
	if Ui.lightPanels() then
		message.BackgroundColor3, message.BackgroundTransparency, message.ZIndex, message.Visible = Ui.PANEL, 0, 9, false
		message.TextWrapped = false
		Ui.make("UICorner", message, { CornerRadius = UDim.new(1, 0) })
		Ui.stroke(message, Ui.INK, 2)
	end
	self.message = message
	self:buildOdds()
	return self
end

-- Scroll the body so a section's heading is at its top (read after layout, at a tap: not stale).
function ShopScreen.jump(self: any, section: string)
	local h = self.heads[section]
	if not h or not h.AbsolutePosition or not self.body.AbsolutePosition then return end
	local y = h.AbsolutePosition.Y - self.body.AbsolutePosition.Y + self.body.CanvasPosition.Y - 4
	self.body.CanvasPosition = Vector2.new(0, math.max(0, y))
	-- the section you jumped to is the selected tab
	for id, b in self.jumps do Ui.paint(b, if id == section then Ui.SELECTED else Ui.PANEL2) end
end

function ShopScreen.say(self: any, text: string, colour: Color3?)
	self.message.Text, self.message.TextColor3 = text, colour or Ui.TEXT
	if Ui.lightPanels() then
		self.message.Visible = text ~= ""
		self.message.Size = UDim2.fromOffset(math.min(Ui.textWidth(text, 15) + 36, 900), 30)
	end
end

-- A grid cell `cols` to a row: a fraction of the row, less its share of the gaps and a pixel of slack
-- (with none, five 1/5 cells and their gaps came to the row's exact width and the last one wrapped).
function ShopScreen.cell(cols: number, h: number): UDim2
	-- (Ui.GAP apart: at 10 the cards' 3 px borders left 4 px between them)
	return UDim2.new(1 / cols, -math.ceil(Ui.GAP * (cols - 1) / cols) - 1, 0, h)
end

-- A price (or OWNED, CLAIM...) on a pill, coloured by what it says: a price dark, as the reference
-- shop's price pills; owned green; a paid-for claim gold; waiting or not for sale grey.
local PILL = Color3.fromRGB(35, 27, 51)
local pillOutline: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
local function pill(parent: Instance): any
	local b = Ui.make("TextButton", parent, { Name = "Buy", Text = "", Font = Ui.DISPLAY, TextSize = Ui.px(16, Ui.DISPLAY),
		TextColor3 = Ui.WHITE, BackgroundColor3 = PILL, BorderSizePixel = 0, AutoButtonColor = true, ZIndex = 3 })
	Ui.make("UICorner", b, { CornerRadius = UDim.new(1, 0) })
	-- white words on a green or grey pill are outlined in its shade (bare, OWNED read at 2.1:1)
	pillOutline[b] = Ui.outline(b, 2, Ui.tone(PILL))
	return b
end
function ShopScreen.pillColour(text: string): (Color3, Color3)
	if text == "OWNED" then return Ui.GREEN, Ui.INK end      -- (ink: white on the green was 2.1:1)
	if string.find(text, "CLAIM", 1, true) then return Ui.SUN, Ui.tone(Ui.SUN) end
	if text == "..." or text == "COMING SOON" or text == "BUY SINGLY" then return Color3.fromRGB(150, 140, 160), Ui.WHITE end
	return PILL, Ui.WHITE
end
local function paintPill(b: any)
	b.BackgroundColor3, b.TextColor3 = ShopScreen.pillColour(b.Text)
	local o = pillOutline[b]
	if o then
		local light = Ui.light(b.TextColor3) > 0.5
		o.Thickness, o.Color = if light then 2 else 0, Ui.tone(b.BackgroundColor3)
	end
end

local function card(parent: Instance, pool: { any }, i: number, h: number): any
	local c = pool[i]
	if c then return c end
	-- a saturated card in the item's colour (paintCard), its art on a soft window, white words
	local f = Ui.card(parent, "Card" .. i, Ui.SKY)
	f.LayoutOrder = i
	local thumb = Ui.make("Frame", f, { Name = "Thumb", BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.72, BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 90) })
	Ui.corner(thumb, 6)
	if Ui.lightPanels() then Ui.mount(thumb, Ui.SKY) end
	local name, nameStroke = Ui.faceText(f, "", 17, Ui.SKY)
	name.Name = "Name"
	Ui.fit(name, 11)
	name.Position, name.Size = UDim2.fromOffset(8, 102), UDim2.new(1, -16, 0, 24)
	local meta, metaStroke = Ui.faceText(f, "", 13, Ui.SKY, Ui.LABEL)
	meta.Name, meta.TextWrapped = "Meta", true
	meta.Position, meta.Size = UDim2.fromOffset(8, 128), UDim2.new(1, -16, 0, math.max(18, h - 178))
	-- the whole card buys, as the reference's do; its price on a pill along the foot
	local hit = Ui.make("TextButton", f, { Name = "Hit", Text = "", BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	local buy = pill(f)
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position, buy.Size = UDim2.new(0.5, 0, 1, -12), UDim2.new(1, -28, 0, 32)
	c = { frame = f, thumb = thumb, name = name, meta = meta, buy = buy, onBuy = nil,
		paint = function(colour: Color3)
			Ui.paintCard(f, colour)
			Ui.paintTitle(name, nameStroke, colour)
			Ui.paintSecondary(meta, metaStroke, colour)
		end }
	buy.Activated:Connect(function() if c.onBuy then c.onBuy() end end)
	hit.Activated:Connect(function() if c.onBuy then c.onBuy() end end)
	pool[i] = c
	return c
end

-- The wide card that leads the featured shop: its art at the left, the name large, the price pill.
function ShopScreen.heroCard(parent: Instance, order: number): any
	local f = Ui.card(parent, "Hero", Ui.SUN)
	f.LayoutOrder, f.Size = order, UDim2.new(1, -8, 0, 150)
	local thumb = Ui.make("Frame", f, { Name = "Thumb", BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.72, BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 12), Size = UDim2.new(0.42, -12, 1, -29) })
	Ui.corner(thumb, 6)
	if Ui.lightPanels() then Ui.mount(thumb, Ui.SUN) end
	local tag, tagStroke = Ui.faceText(f, "TODAY'S BEST", 14, Ui.SUN, Ui.LABEL)
	tag.Name, tag.TextXAlignment = "Tag", Enum.TextXAlignment.Left
	tag.Position, tag.Size = UDim2.new(0.42, 12, 0, 14), UDim2.new(0.58, -24, 0, 18)
	local name, nameStroke = Ui.faceText(f, "", 30, Ui.SUN)
	name.Name, name.TextXAlignment, name.TextTruncate = "Name", Enum.TextXAlignment.Left, Enum.TextTruncate.AtEnd
	name.Position, name.Size = UDim2.new(0.42, 12, 0, 34), UDim2.new(0.58, -24, 0, 38)
	local meta, metaStroke = Ui.faceText(f, "", 15, Ui.SUN, Ui.LABEL)
	meta.Name, meta.TextXAlignment = "Meta", Enum.TextXAlignment.Left
	meta.Position, meta.Size = UDim2.new(0.42, 12, 0, 74), UDim2.new(0.58, -24, 0, 20)
	local hit = Ui.make("TextButton", f, { Name = "Hit", Text = "", BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	local buy = pill(f)
	buy.AnchorPoint = Vector2.new(1, 1)
	buy.Position, buy.Size = UDim2.new(1, -16, 1, -18), UDim2.fromOffset(160, 38)
	local c: any = { frame = f, thumb = thumb, name = name, meta = meta, buy = buy, onBuy = nil,
		paint = function(colour: Color3)
			Ui.paintCard(f, colour)
			Ui.paintTitle(name, nameStroke, colour)
			Ui.paintSecondary(tag, tagStroke, colour)
			Ui.paintSecondary(meta, metaStroke, colour)
		end }
	buy.Activated:Connect(function() if c.onBuy then c.onBuy() end end)
	hit.Activated:Connect(function() if c.onBuy then c.onBuy() end end)
	return c
end

function ShopScreen.request(self: any, key: string, msg: any)
	if self.pending then return end
	self.pending = key
	self:say("Asking the shop...", Ui.SUB)
	self.opts.send(msg)
	self:refresh()
end

-- How many cards a row holds at a screen `width` px wide (the window is the screen less 24, at most
-- 940, less its 36 px of margins): a phone gets two to a row, and passes one, each its perks' height.
function ShopScreen.columns(width: number): { [string]: number }
	local row = math.min(width - 24, 940) - 36
	local narrow = row < 560
	return { Featured = if narrow then 2 else 3, Keys = if narrow then 2 else 4, Passes = if narrow then 1 else 3,
		Clothing = if narrow then 2 else 4 }
end

function ShopScreen.refresh(self: any)
	local shop = self.view and self.view.shop
	if not shop then return end
	local size = self.root.AbsoluteSize
	local cols = ShopScreen.columns(if size and size.X > 0 then size.X else 1280)
	self.cols = cols
	for name, g in self.grids do
		-- one pass to a row: as tall as its perks need, so a long list never runs over its price
		local h = g.h
		if name == "Passes" and cols.Passes == 1 then
			local most = 0
			for _, p in shop.passes or {} do most = math.max(most, #(p.perks or {})) end
			h = 96 + 20 * most
		end
		g.layout.CellSize = ShopScreen.cell(cols[name] or g.cols, h)
	end
	if self.sparksPill then
		self.sparksPill.Text = LockerScreen.number(self.view.sparks or 0)
		self.keysPill.Text = tostring(self.view.keys and self.view.keys.forge or 0)
	end
	-- featured
	self.featuredHead.Text = `FEATURED  ·  new items in {ShopScreen.wait(shop.resetsIn or 0)}`
	for i, f in shop.featured or {} do
		local it = Cosmetics.get(f.id)
		if it then
			local hero = i == #shop.featured
			local c = if hero then self.hero else card(self.featuredRow, self.featuredCards, i, 220)
			local col = Color3.fromHex((Loot.RARITY[it.rarity] or Loot.RARITY.Common).colour)
			c.paint(col)
			c.name.Text = it.name
			-- (the card's colour says the rarity too: kept short so it never runs edge to edge)
			-- (a claim says on the card that it is already paid for: the pill has room for one word)
			c.meta.Text = if f.credit and not f.owned then "Paid for · tap to claim" else `{it.rarity} · {it.weapon or LockerScreen.TYPE_LABEL[it.type] or ""}`
			if self.art[c.thumb] ~= f.id then
				self.art[c.thumb] = f.id
				if self.opts.drawArt then self.opts.drawArt(c.thumb, f.id, if hero then 320 else 184, if hero then 120 else 90) end
			end
			local key = "item:" .. f.id
			c.buy.Text = if f.owned then "OWNED" elseif f.credit then "CLAIM" elseif self.pending == key then "..." else `{f.price} R$`
			paintPill(c.buy)
			c.onBuy = function()
				if not f.owned then self:request(key, { action = "buy", kind = "item", id = f.id }) end
			end
		end
	end
	-- keys: none at all for a restricted player, whatever else arrives
	local keys = if shop.restricted then {} else shop.keys or {}
	self.oddsButton.Visible = not shop.restricted
	self.keyNote.Text = if shop.restricted
		then "Forge Keys are not available for your account. Crates still drop from matches, and keys from play."
		else "Forge Keys open Forge Crates: Rare or better, Mythic possible. See the odds before you buy."
	for i, b in keys do
		local c = card(self.keysRow, self.keyCards, i, 150)
		c.frame.Visible = true
		c.thumb.Visible = false
		c.paint(Ui.ORANGE)
		c.name.Position, c.meta.Position = UDim2.fromOffset(8, 14), UDim2.fromOffset(8, 40)
		c.meta.Size = UDim2.new(1, -16, 0, 22)
		c.name.Text = `{b.count} Forge Key{if b.count == 1 then "" else "s"}`
		c.meta.Text = ShopScreen.each(b)
		local key = "keys:" .. b.bundle
		c.buy.Text = if self.pending == key then "..." else `{b.price} R$`
		paintPill(c.buy)
		c.onBuy = function() self:request(key, { action = "buy", kind = "keys", bundle = b.bundle }) end
	end
	for i = #keys + 1, #self.keyCards do self.keyCards[i].frame.Visible = false end
	self.keysRow.Visible = #keys > 0
	self:refreshClothing(shop.clothing or {})
	-- passes
	for i, p in shop.passes or {} do
		local c = card(self.passesRow, self.passCards, i, 270)
		c.thumb.Visible = false
		c.name.Position, c.meta.Position = UDim2.fromOffset(8, 14), UDim2.fromOffset(8, 40)
		c.meta.Size = UDim2.new(1, -16, 0, if self.cols and self.cols.Passes == 1 then 20 * #(p.perks or {}) + 8 else 160)
		c.name.Text = p.name
		local perks = {}
		for _, perk in p.perks or {} do table.insert(perks, "· " .. perk) end
		c.meta.Text = table.concat(perks, "\n")
		local key = "pass:" .. p.id
		c.buy.Text = if p.owned then "OWNED" elseif not p.available then "COMING SOON"
			elseif self.pending == key then "..." else `{p.price} R$`
		paintPill(c.buy)
		c.paint(if not p.available then Color3.fromRGB(150, 140, 160) else PASS_COLOURS[p.id] or Ui.VIOLET)
		c.onBuy = function()
			if not p.owned and p.available then self:request(key, { action = "buy", kind = "pass", id = p.id }) end
		end
	end
end

-- A pack's line under its card: what it holds, and what owning some of it leaves to pay.
function ShopScreen.packLine(pack: any): string
	local n = #(pack.pieces or {})
	if pack.missing == 0 then return `{n} pieces · you own them all` end
	if pack.missing == n then return `{n} pieces · {pack.total} R$ one by one` end
	return `you own {n - pack.missing} · the other {pack.missing}: {pack.missingTotal} R$ one by one`
end

function ShopScreen.refreshClothing(self: any, packs: { any })
	for i, pack in packs do
		local r = self.packRows[i]
		if not r then
			local head = Ui.text(self.clothing, "", 16, Ui.TEXT, Ui.DISPLAY, true)
			head.Name, head.LayoutOrder, head.TextXAlignment = "PackHead" .. i, i * 2 - 1, Enum.TextXAlignment.Left
			head.Size = UDim2.new(1, -8, 0, 22)
			local grid = Ui.make("Frame", self.clothing, { Name = "Pack" .. i, BackgroundTransparency = 1, BorderSizePixel = 0,
				LayoutOrder = i * 2, Size = UDim2.new(1, -8, 0, 220), AutomaticSize = Enum.AutomaticSize.Y })
			local layout = Ui.make("UIGridLayout", grid, { CellSize = ShopScreen.cell(self.cols and self.cols.Clothing or 4, 220), CellPadding = UDim2.fromOffset(Ui.GAP, Ui.GAP), SortOrder = Enum.SortOrder.LayoutOrder })
			r = { head = head, grid = grid, cards = {}, layout = layout }
			self.packRows[i] = r
		end
		r.head.Text, r.head.Visible, r.grid.Visible = string.upper(pack.name or pack.id), true, true
		r.layout.CellSize = ShopScreen.cell(self.cols and self.cols.Clothing or 4, 220)
		-- the pack itself first
		local c = card(r.grid, r.cards, 1, 220)
		c.frame.Visible, c.thumb.Visible = true, false
		c.name.Position, c.meta.Position = UDim2.fromOffset(8, 14), UDim2.fromOffset(8, 44)
		c.meta.Size = UDim2.new(1, -16, 0, 110)
		c.name.Text = "Whole pack"
		c.meta.Text = ShopScreen.packLine(pack)
		c.paint(Ui.SUN)
		local key = "pack:" .. pack.id
		c.buy.Text = if pack.missing == 0 then "OWNED" elseif not pack.offer then "BUY SINGLY"
			elseif self.pending == key then "..." else `{pack.price} R$`
		paintPill(c.buy)
		c.onBuy = function()
			if pack.offer then self:request(key, { action = "buy", kind = "pack", id = pack.id }) end
		end
		-- then each piece
		for j, p in pack.pieces or {} do
			local it = Cosmetics.get(p.id)
			local pc = card(r.grid, r.cards, j + 1, 220)
			pc.frame.Visible = true
			local col = Color3.fromHex((Loot.RARITY[it and it.rarity or "Common"] or Loot.RARITY.Common).colour)
			pc.paint(col)
			pc.name.Text = if it then it.name else p.id
			pc.meta.Text = if p.credit and not p.owned then "Paid for · tap to claim" elseif it then `{it.rarity} {it.category or ""}` else ""
			if self.art[pc.thumb] ~= p.id then
				self.art[pc.thumb] = p.id
				if self.opts.drawArt then self.opts.drawArt(pc.thumb, p.id, 134, 90) end
			end
			local pkey = "piece:" .. p.id
			pc.buy.Text = if p.owned then "OWNED" elseif p.credit then "CLAIM" elseif self.pending == pkey then "..." else `{p.price} R$`
			paintPill(pc.buy)
			pc.onBuy = function()
				if not p.owned then self:request(pkey, { action = "buy", kind = "piece", id = p.id }) end
			end
		end
		for j = #(pack.pieces or {}) + 2, #r.cards do r.cards[j].frame.Visible = false end
	end
	for i = #packs + 1, #self.packRows do self.packRows[i].head.Visible, self.packRows[i].grid.Visible = false, false end
end

-- -------------------------------------------------------------------------- odds & details ----
function ShopScreen.buildOdds(self: any)
	local o = Ui.make("Frame", self.panel, { Name = "OddsPanel", BackgroundColor3 = Ui.PANEL, BackgroundTransparency = 0,
		BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 10 })
	Ui.corner(o, 12)
	-- a window like every other: the title on a band across its top
	local band = Ui.band(o, Ui.BLUE, 44, "OddsBand")
	band.ZIndex = 11
	local t = Ui.faceText(band, "ODDS & DETAILS  ·  FORGE CRATE", Ui.WINDOW_TITLE, Ui.BLUE, Ui.TITLE)
	t.Name, t.ZIndex, t.TextXAlignment = "Title", 12, Enum.TextXAlignment.Left
	t.Position, t.Size = UDim2.fromOffset(16, 0), UDim2.new(1, -32, 1, 0)
	local now = Ui.button(o, "THIS OPENING", Ui.BLUE, function() self:showOdds(false) end, { size = 13, small = true })
	now.Name, now.ZIndex = "Now", 11
	now.Position, now.Size = UDim2.fromOffset(16, 56), UDim2.fromOffset(150, 30)
	local gua = Ui.button(o, "GUARANTEED OPENING", Ui.PANEL2, function() self:showOdds(true) end, { size = 13, small = true })
	gua.Name, gua.ZIndex = "Guaranteed", 11
	gua.Position, gua.Size = UDim2.fromOffset(16 + 150 + Ui.GAP, 56), UDim2.fromOffset(190, 30)
	local list = Ui.make("ScrollingFrame", o, { Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 11,
		Position = UDim2.fromOffset(16, 96), Size = UDim2.new(1, -32, 1, -162), CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6 })
	Ui.make("UIListLayout", list, { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
	local foot = Ui.text(o, "Shown odds are rounded, so they may not add to exactly 100%. Each Forge Key opens one Forge Crate. Paid keys keep their own guarantee count.", 12, Ui.SUB, nil, true)
	foot.Name, foot.ZIndex, foot.TextWrapped, foot.TextXAlignment = "Footer", 11, true, Enum.TextXAlignment.Left
	foot.AnchorPoint = Vector2.new(0, 1)
	foot.Position, foot.Size = UDim2.new(0, 16, 1, -10), UDim2.new(1, -136, 0, 44)
	local back = Ui.button(o, "BACK", Ui.PANEL2, function() o.Visible = false end, { size = 16 })
	back.Name, back.ZIndex = "Back", 12
	back.AnchorPoint = Vector2.new(1, 1)
	back.Position, back.Size = UDim2.new(1, -16, 1, -10), UDim2.fromOffset(90, 36)
	self.odds = { frame = o, now = now, guaranteed = gua, list = list, rows = {} }
end

function ShopScreen.showOdds(self: any, guaranteed: boolean)
	local o = self.odds
	local rows = LockerScreen.oddsRows("forge", 0, guaranteed)
	Ui.paint(o.now, if guaranteed then Ui.PANEL2 else Ui.SELECTED)
	Ui.paint(o.guaranteed, if guaranteed then Ui.SELECTED else Ui.PANEL2)
	for i, r in rows do
		local row = o.rows[i]
		if not row then
			local f = Ui.make("Frame", o.list, { Name = "Row" .. i, BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 11, Size = UDim2.new(1, -8, 0, 22) })
			local l = Ui.text(f, "", 14, Ui.TEXT, nil, true)
			l.Name, l.ZIndex, l.TextXAlignment, l.Size = "Label", 11, Enum.TextXAlignment.Left, UDim2.new(0.62, 0, 1, 0)
			local v = Ui.text(f, "", 14, Ui.TEXT, nil, true)
			v.Name, v.ZIndex, v.TextXAlignment = "Value", 11, Enum.TextXAlignment.Right
			v.Position, v.Size = UDim2.fromScale(0.62, 0), UDim2.new(0.38, 0, 1, 0)
			row = { frame = f, label = l, value = v }
			o.rows[i] = row
		end
		row.frame.Visible = true
		row.label.Text, row.value.Text = r.text, r.value
		-- tiers in their colour, deepened to read on a pale window
		local tier: Color3? = if r.kind == "tier" then Color3.fromHex(Loot.RARITY[r.rarity].colour) else nil
		local col = if tier then (if Ui.lightPanels() then Ui.shade(tier, -0.35) else tier) else Ui.TEXT
		row.label.TextColor3, row.value.TextColor3 = col, if tier then col else Ui.SUB
	end
	for i = #rows + 1, #o.rows do o.rows[i].frame.Visible = false end
	o.frame.Visible = true
end

-- ------------------------------------------------------------------------------- the server ----
function ShopScreen.setEconomy(self: any, view: any)
	self.view = view
	local e = type(view) == "table" and view.event
	if e then
		if e.prompt then
			self.pending = nil
			self:say("Confirm in Roblox's purchase window", Ui.SUB)
			self.opts.prompt(e.prompt.kind, e.prompt.id)
		elseif e.error then
			self.pending = nil
			self:say(`Could not do that: {e.error}`, Ui.RED)
		elseif e.purchased then
			self.pending = nil
			local p = e.purchased
			local it = p.id and Cosmetics.get(p.id)
			self:say(if p.kind == "keys" then `Thank you: {p.count} Forge Key{if p.count == 1 then "" else "s"} added`
				elseif p.kind == "pass" then "Thank you: your pass is active"
				elseif p.kind == "pack" then `Thank you: {#(p.granted or {})} piece{if #(p.granted or {}) == 1 then " is" else "s are"} in your Locker - wear them in the Character Studio`
				elseif p.kind == "credit" and p.tier then `Thank you: pick a {p.tier} clothing piece to claim it`
				elseif p.kind == "credit" then `Thank you: pick a {p.rarity} item to claim it`
				elseif it then `Thank you: {it.name} is in your Locker` else "Thank you", Ui.GREEN)
		end
	end
	self:refresh()
end

-- Roblox's purchase window closed without a purchase.
function ShopScreen.cancelled(self: any)
	self.pending = nil
	self:say("")
	self:refresh()
end

function ShopScreen.open(self: any) self.root.Enabled = true; self:refresh() end
function ShopScreen.close(self: any) self.root.Enabled = false; self.odds.frame.Visible = false end
function ShopScreen.toggle(self: any) if self.root.Enabled then self:close() else self:open() end end
function ShopScreen.isOpen(self: any): boolean return self.root.Enabled == true end

return ShopScreen
