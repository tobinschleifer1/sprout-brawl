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
		featuredCards = {}, keyCards = {}, passCards = {} }, ShopScreen)
	local root = Ui.make("ScreenGui", parent, { Name = "BlockfallShop", ResetOnSpawn = false, Enabled = false, DisplayOrder = 21 })
	self.root = root
	local panel = Ui.panel(root, "Shop", Ui.shade(Ui.GOLD, -0.35), "SHOP", 40)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position, panel.Size = UDim2.fromScale(0.5, 0.52), UDim2.new(1, -24, 1, -90)
	Ui.make("UISizeConstraint", panel, { MaxSize = Vector2.new(940, 620) })
	self.panel = panel
	local close = Ui.button(panel, "X", Ui.RED, function() self:close() end, { size = 18 })
	close.Name, close.ZIndex = "Close", 3
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position, close.Size = UDim2.new(1, -6, 0, 4), UDim2.fromOffset(34, 32)
	local body = Ui.make("ScrollingFrame", panel, { Name = "Body", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 48), Size = UDim2.new(1, -24, 1, -86), CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6 })
	Ui.make("UIListLayout", body, { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder })
	self.body = body
	local function heading(name: string, text: string, order: number): any
		local h = Ui.text(body, text, 18, Ui.WHITE, Ui.DISPLAY)
		h.Name, h.LayoutOrder, h.TextXAlignment = name, order, Enum.TextXAlignment.Left
		h.Size = UDim2.new(1, -8, 0, 26)
		return h
	end
	local function row(name: string, order: number, h: number): any
		local f = Ui.make("Frame", body, { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, h), AutomaticSize = Enum.AutomaticSize.Y })
		Ui.make("UIGridLayout", f, { CellSize = UDim2.fromOffset(200, h), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder })
		return f
	end
	self.featuredHead = heading("FeaturedHead", "FEATURED", 1)
	self.featuredRow = row("Featured", 2, 220)
	-- clothing: a heading and a grid row per pack, made as packs arrive
	heading("ClothingHead", "CLOTHING", 3)
	local clothing = Ui.make("Frame", body, { Name = "Clothing", BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = 4,
		Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	Ui.make("UIListLayout", clothing, { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })
	self.clothing, self.packRows = clothing, {}
	heading("KeysHead", "FORGE KEYS", 6)
	local keyNote = Ui.text(body, "Forge Keys open Forge Crates: Rare or better, Mythic possible.", 13, Ui.DIM)
	keyNote.Name, keyNote.LayoutOrder, keyNote.TextXAlignment, keyNote.TextWrapped = "KeyNote", 7, Enum.TextXAlignment.Left, true
	keyNote.Size = UDim2.new(1, -8, 0, 34)
	self.keyNote = keyNote
	local odds = Ui.button(body, "ODDS & DETAILS", Ui.BLUE, function() self:showOdds(false) end, { size = 15 })
	odds.Name, odds.LayoutOrder = "Odds", 8
	odds.Size = UDim2.fromOffset(200, 36)
	self.oddsButton = odds
	self.keysRow = row("Keys", 9, 150)
	heading("PassesHead", "PASSES", 10)
	self.passesRow = row("Passes", 11, 250)
	local message = Ui.text(panel, "", 15, Ui.WHITE)
	message.Name = "Message"
	message.AnchorPoint = Vector2.new(0.5, 1)
	message.Position, message.Size = UDim2.new(0.5, 0, 1, -8), UDim2.new(1, -24, 0, 26)
	self.message = message
	self:buildOdds()
	return self
end

function ShopScreen.say(self: any, text: string, colour: Color3?)
	self.message.Text, self.message.TextColor3 = text, colour or Ui.WHITE
end

local function card(parent: Instance, pool: { any }, i: number, h: number): any
	local c = pool[i]
	if c then return c end
	local f = Ui.make("Frame", parent, { Name = "Card" .. i, BackgroundColor3 = Ui.INK, BorderSizePixel = 0, LayoutOrder = i })
	Ui.corner(f, 8)
	local edge = Ui.stroke(f, Ui.EDGE, 2)
	local band = Ui.make("Frame", f, { Name = "Band", BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = Ui.EDGE })
	local thumb = Ui.make("Frame", f, { Name = "Thumb", BackgroundColor3 = Ui.PANEL, BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 10), Size = UDim2.new(1, -16, 0, 90) })
	Ui.corner(thumb, 6)
	local name = Ui.text(f, "", 16, Ui.WHITE, Ui.DISPLAY)
	name.Name, name.TextTruncate = "Name", Enum.TextTruncate.AtEnd
	name.Position, name.Size = UDim2.fromOffset(8, 104), UDim2.new(1, -16, 0, 22)
	local meta = Ui.text(f, "", 13, Ui.DIM)
	meta.Name, meta.TextWrapped = "Meta", true
	meta.Position, meta.Size = UDim2.fromOffset(8, 128), UDim2.new(1, -16, 0, h - 176)
	local buy = Ui.button(f, "", Ui.GREEN, nil, { size = 16 })
	buy.Name = "Buy"
	buy.Position, buy.Size = UDim2.new(0, 8, 1, -42), UDim2.new(1, -16, 0, 34)
	c = { frame = f, edge = edge, band = band, thumb = thumb, name = name, meta = meta, buy = buy, onBuy = nil }
	buy.Activated:Connect(function() if c.onBuy then c.onBuy() end end)
	pool[i] = c
	return c
end

function ShopScreen.request(self: any, key: string, msg: any)
	if self.pending then return end
	self.pending = key
	self:say("Asking the shop...", Ui.DIM)
	self.opts.send(msg)
	self:refresh()
end

function ShopScreen.refresh(self: any)
	local shop = self.view and self.view.shop
	if not shop then return end
	-- featured
	self.featuredHead.Text = `FEATURED  ·  new items in {ShopScreen.wait(shop.resetsIn or 0)}`
	for i, f in shop.featured or {} do
		local it = Cosmetics.get(f.id)
		if it then
			local c = card(self.featuredRow, self.featuredCards, i, 220)
			local col = Color3.fromHex((Loot.RARITY[it.rarity] or Loot.RARITY.Common).colour)
			c.band.BackgroundColor3 = col
			c.name.Text = it.name
			c.meta.Text = `{it.rarity} {LockerScreen.TYPE_LABEL[it.type] or ""}{if it.weapon then " · " .. it.weapon else ""}`
			c.meta.TextColor3 = col
			if self.art[c.thumb] ~= f.id then
				self.art[c.thumb] = f.id
				if self.opts.drawArt then self.opts.drawArt(c.thumb, f.id, 184, 90) end
			end
			local key = "item:" .. f.id
			c.buy.Text = if f.owned then "OWNED" elseif f.credit then "CLAIM (PAID)" elseif self.pending == key then "..." else `{f.price} R$`
			Ui.paint(c.buy, if f.owned or self.pending then Ui.PANEL2 else Ui.GREEN)
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
		c.name.Position, c.meta.Position = UDim2.fromOffset(8, 14), UDim2.fromOffset(8, 40)
		c.meta.Size = UDim2.new(1, -16, 0, 22)
		c.name.Text = `{b.count} Forge Key{if b.count == 1 then "" else "s"}`
		c.meta.Text = ShopScreen.each(b)
		local key = "keys:" .. b.bundle
		c.buy.Text = if self.pending == key then "..." else `{b.price} R$`
		Ui.paint(c.buy, if self.pending then Ui.PANEL2 else Ui.GREEN)
		c.onBuy = function() self:request(key, { action = "buy", kind = "keys", bundle = b.bundle }) end
	end
	for i = #keys + 1, #self.keyCards do self.keyCards[i].frame.Visible = false end
	self.keysRow.Visible = #keys > 0
	self:refreshClothing(shop.clothing or {})
	-- passes
	for i, p in shop.passes or {} do
		local c = card(self.passesRow, self.passCards, i, 250)
		c.thumb.Visible = false
		c.name.Position, c.meta.Position = UDim2.fromOffset(8, 14), UDim2.fromOffset(8, 40)
		c.meta.Size = UDim2.new(1, -16, 0, 160)
		c.name.Text = p.name
		local perks = {}
		for _, perk in p.perks or {} do table.insert(perks, "· " .. perk) end
		c.meta.Text = table.concat(perks, "\n")
		local key = "pass:" .. p.id
		c.buy.Text = if p.owned then "OWNED" elseif not p.available then "COMING SOON"
			elseif self.pending == key then "..." else `{p.price} R$`
		Ui.paint(c.buy, if p.owned or not p.available or self.pending then Ui.PANEL2 else Ui.GREEN)
		c.edge.Color = if p.owned then Ui.GOLD else Ui.EDGE
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
			local head = Ui.text(self.clothing, "", 15, Ui.WHITE, Ui.LABEL)
			head.Name, head.LayoutOrder, head.TextXAlignment = "PackHead" .. i, i * 2 - 1, Enum.TextXAlignment.Left
			head.Size = UDim2.new(1, -8, 0, 22)
			local grid = Ui.make("Frame", self.clothing, { Name = "Pack" .. i, BackgroundTransparency = 1, BorderSizePixel = 0,
				LayoutOrder = i * 2, Size = UDim2.new(1, -8, 0, 220), AutomaticSize = Enum.AutomaticSize.Y })
			Ui.make("UIGridLayout", grid, { CellSize = UDim2.fromOffset(150, 220), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder })
			r = { head = head, grid = grid, cards = {} }
			self.packRows[i] = r
		end
		r.head.Text, r.head.Visible, r.grid.Visible = string.upper(pack.name or pack.id), true, true
		-- the pack itself first
		local c = card(r.grid, r.cards, 1, 220)
		c.frame.Visible, c.thumb.Visible = true, false
		c.name.Position, c.meta.Position = UDim2.fromOffset(8, 14), UDim2.fromOffset(8, 44)
		c.meta.Size = UDim2.new(1, -16, 0, 110)
		c.name.Text = "Whole pack"
		c.meta.Text, c.meta.TextColor3 = ShopScreen.packLine(pack), Ui.DIM
		local key = "pack:" .. pack.id
		c.buy.Text = if pack.missing == 0 then "OWNED" elseif not pack.offer then "BUY SINGLY"
			elseif self.pending == key then "..." else `{pack.price} R$`
		Ui.paint(c.buy, if not pack.offer or self.pending then Ui.PANEL2 else Ui.GREEN)
		c.edge.Color = if pack.missing == 0 then Ui.GOLD else Ui.EDGE
		c.onBuy = function()
			if pack.offer then self:request(key, { action = "buy", kind = "pack", id = pack.id }) end
		end
		-- then each piece
		for j, p in pack.pieces or {} do
			local it = Cosmetics.get(p.id)
			local pc = card(r.grid, r.cards, j + 1, 220)
			pc.frame.Visible = true
			local col = Color3.fromHex((Loot.RARITY[it and it.rarity or "Common"] or Loot.RARITY.Common).colour)
			pc.band.BackgroundColor3 = col
			pc.name.Text = if it then it.name else p.id
			pc.meta.Text, pc.meta.TextColor3 = if it then `{it.rarity} {it.category or ""}` else "", col
			if self.art[pc.thumb] ~= p.id then
				self.art[pc.thumb] = p.id
				if self.opts.drawArt then self.opts.drawArt(pc.thumb, p.id, 134, 90) end
			end
			local pkey = "piece:" .. p.id
			pc.buy.Text = if p.owned then "OWNED" elseif p.credit then "CLAIM (PAID)" elseif self.pending == pkey then "..." else `{p.price} R$`
			Ui.paint(pc.buy, if p.owned or self.pending then Ui.PANEL2 else Ui.GREEN)
			pc.edge.Color = if p.owned then Ui.GOLD else Ui.EDGE
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
	local o = Ui.make("Frame", self.panel, { Name = "OddsPanel", BackgroundColor3 = Ui.INK, BackgroundTransparency = 0.04,
		BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 10 })
	Ui.corner(o, 12)
	local t = Ui.text(o, "ODDS & DETAILS  ·  FORGE CRATE", 22, Ui.WHITE, Ui.DISPLAY)
	t.Name, t.ZIndex, t.TextXAlignment = "Title", 11, Enum.TextXAlignment.Left
	t.Position, t.Size = UDim2.fromOffset(16, 10), UDim2.new(1, -32, 0, 30)
	local now = Ui.button(o, "THIS OPENING", Ui.BLUE, function() self:showOdds(false) end, { size = 13, small = true })
	now.Name, now.ZIndex = "Now", 11
	now.Position, now.Size = UDim2.fromOffset(16, 46), UDim2.fromOffset(150, 28)
	local gua = Ui.button(o, "GUARANTEED OPENING", Ui.PANEL2, function() self:showOdds(true) end, { size = 13, small = true })
	gua.Name, gua.ZIndex = "Guaranteed", 11
	gua.Position, gua.Size = UDim2.fromOffset(174, 46), UDim2.fromOffset(190, 28)
	local list = Ui.make("ScrollingFrame", o, { Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 11,
		Position = UDim2.fromOffset(16, 82), Size = UDim2.new(1, -32, 1, -136), CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6 })
	Ui.make("UIListLayout", list, { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
	local foot = Ui.text(o, "Odds are rounded to four digits past the first non-zero one, so shown odds may not add to exactly 100%. Each Forge Key opens one Forge Crate. Paid keys keep their own guarantee count.", 12, Ui.DIM)
	foot.Name, foot.ZIndex, foot.TextWrapped, foot.TextXAlignment = "Footer", 11, true, Enum.TextXAlignment.Left
	foot.AnchorPoint = Vector2.new(0, 1)
	foot.Position, foot.Size = UDim2.new(0, 16, 1, -8), UDim2.new(1, -120, 0, 44)
	local back = Ui.button(o, "BACK", Ui.PANEL2, function() o.Visible = false end, { size = 16 })
	back.Name, back.ZIndex = "Back", 12
	back.AnchorPoint = Vector2.new(1, 1)
	back.Position, back.Size = UDim2.new(1, -16, 1, -10), UDim2.fromOffset(90, 36)
	self.odds = { frame = o, now = now, guaranteed = gua, list = list, rows = {} }
end

function ShopScreen.showOdds(self: any, guaranteed: boolean)
	local o = self.odds
	local rows = LockerScreen.oddsRows("forge", 0, guaranteed)
	Ui.paint(o.now, if guaranteed then Ui.PANEL2 else Ui.BLUE)
	Ui.paint(o.guaranteed, if guaranteed then Ui.BLUE else Ui.PANEL2)
	for i, r in rows do
		local row = o.rows[i]
		if not row then
			local f = Ui.make("Frame", o.list, { Name = "Row" .. i, BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 11, Size = UDim2.new(1, -8, 0, 22) })
			local l = Ui.text(f, "", 14, Ui.WHITE)
			l.Name, l.ZIndex, l.TextXAlignment, l.Size = "Label", 11, Enum.TextXAlignment.Left, UDim2.new(0.62, 0, 1, 0)
			local v = Ui.text(f, "", 14, Ui.WHITE)
			v.Name, v.ZIndex, v.TextXAlignment = "Value", 11, Enum.TextXAlignment.Right
			v.Position, v.Size = UDim2.fromScale(0.62, 0), UDim2.new(0.38, 0, 1, 0)
			row = { frame = f, label = l, value = v }
			o.rows[i] = row
		end
		row.frame.Visible = true
		row.label.Text, row.value.Text = r.text, r.value
		local col = if r.kind == "tier" then Color3.fromHex(Loot.RARITY[r.rarity].colour) else Ui.WHITE
		row.label.TextColor3, row.value.TextColor3 = col, if r.kind == "tier" then col else Ui.DIM
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
			self:say("Confirm in Roblox's purchase window", Ui.DIM)
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
