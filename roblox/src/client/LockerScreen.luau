--!strict
-- The Locker (Roblox only; docs/briefs/crates-and-monetisation-plan.md, phase 4): what you own and
-- wear, your crates and keys, the Workshop, the crate opening and its Odds & Details.
--
--   LOCKER     a card per item you own: its picture, rarity, your lowest serial (#57), how many you
--              have and how many exist; WEAR / TAKE OFF; SALVAGE for Sparks (press twice)
--   CRATES     each crate with how many you have, the key it needs, its guarantee countdown, OPEN and
--              a labelled ODDS & DETAILS button (Roblox requires the odds before a paid key is used,
--              behind a worded button, not a bare icon)
--   WORKSHOP   every craftable item and its Sparks price; CRAFT (press twice)
--
-- It decides nothing: the server's LockerView and EconomyView say what you own, and every action
-- is a request (`sendLocker`, `sendEconomy`) the server may refuse. The odds come from Loot, the
-- table the server rolls from, so what is shown is what happens. The reel always stops on what the
-- server rolled; the items around it are only scenery.
--
-- The pure pieces (cards, crates, craftable, oddsRows, reel, and the words) are tested directly in
-- tests/locker-ui.luau, with the screen driven through stub Instances.
local Shared = game:GetService("ReplicatedStorage").Shared
local Cosmetics = require(Shared.Cosmetics)
local Loot = require(Shared.Loot)
local Inventory = require(Shared.Inventory)
local Ui = require(script.Parent.Ui)
local LockerScreen = {}
LockerScreen.__index = LockerScreen

LockerScreen.TYPE_LABEL = {
	weapon_skin = "Weapon skin", hit_effect = "Hit effect", ko_effect = "KO effect", swing_trail = "Swing trail",
	step_trail = "Step trail", spawn_effect = "Spawn effect", shield_skin = "Shield skin", title = "Title",
} :: { [string]: string }
LockerScreen.FILTERS = { { "all", "ALL" }, { "weapon_skin", "SKINS" }, { "hit_effect", "HITS" }, { "ko_effect", "KOS" },
	{ "swing_trail", "TRAILS" }, { "other", "MORE" } }
LockerScreen.CONFIRM_SECONDS = 3
local EMPTY = "Nothing here yet: play matches for drops, open crates, or craft in the Workshop"
LockerScreen.REEL = { tiles = 44, win = 38, width = 104, pad = 8 }

local function colourOf(rarity: string): Color3
	return Color3.fromHex((Loot.RARITY[rarity] or Loot.RARITY.Common).colour)
end
local function matches(it: any, filter: string?): boolean
	if not filter or filter == "all" then return true end
	if filter == "other" then
		return it.type ~= "weapon_skin" and it.type ~= "hit_effect" and it.type ~= "ko_effect" and it.type ~= "swing_trail"
	end
	return it.type == filter
end
local function byRarityThenName(a: any, b: any): boolean
	local ra, rb = Loot.RARITY[a.rarity].rank, Loot.RARITY[b.rarity].rank
	if ra ~= rb then return ra > rb end
	return a.name < b.name
end

-- 1,240 -> "1,240"
function LockerScreen.number(n: number): string
	local s = tostring(math.floor(n))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	return (string.gsub(out, "^,", ""))
end

-- How many exist, as a card says it.
function LockerScreen.existence(n: number?): string
	if not n or n <= 0 then return "" end
	if n == 1 then return "the only one" end
	return `{LockerScreen.number(n)} exist`
end

-- The serial a card shows (your lowest, the one a collector cares about) and how many you have.
function LockerScreen.serialText(card: any): string
	local s = if card.serial and card.serial > 0 then `#{card.serial}` else ""
	if card.copies > 1 then s = (if s ~= "" then s .. "  " else "") .. `x{card.copies}` end
	return s
end

-- Is `id` worn, in this loadout?
local function worn(wearing: any, it: any): boolean
	if not wearing then return false end
	if it.type == "weapon_skin" then return wearing.skins and wearing.skins[it.weapon] == it.id end
	local slot = Inventory.SLOTS[it.type]
	return slot ~= nil and wearing[slot] == it.id
end

-- The Locker's cards: every item the server says you own, rarest first.
function LockerScreen.cards(locker: any, economy: any, filter: string?): { any }
	local copies: { [string]: { any } } = {}
	for _, inst in (economy and economy.items) or {} do
		copies[inst.id] = copies[inst.id] or {}
		table.insert(copies[inst.id], inst)
	end
	local ids: { [string]: boolean } = {}
	for _, id in (locker and locker.owned) or {} do ids[id] = true end
	for id in copies do ids[id] = true end
	local out = {}
	for id in ids do
		local it = Cosmetics.get(id)
		if it and matches(it, filter) then
			local list: { any } = copies[id] or {}
			-- salvage the highest serial first: the low ones are the collectable ones
			table.sort(list, function(a, b) return (a.serial or 0) < (b.serial or 0) end)
			local lowest = nil
			for _, inst in list do if (inst.serial or 0) > 0 then lowest = inst.serial; break end end
			table.insert(out, {
				id = id, name = it.name, rarity = it.rarity, type = it.type, weapon = it.weapon,
				copies = #list, serial = lowest, exist = if list[1] then list[1].copies else nil,
				uids = (function() local u = {}; for i = #list, 1, -1 do table.insert(u, list[i].uid) end; return u end)(),
				worn = worn(locker and locker.wearing, it),
			})
		end
	end
	table.sort(out, byRarityThenName)
	return out
end

-- The crate cards.
function LockerScreen.crates(economy: any): { any }
	local out = {}
	for _, id in Inventory.CRATES do
		local c = Loot.CRATES[id]
		local left = economy and economy.guarantees and economy.guarantees[id] or c.guarantee.at
		local keys = economy and economy.keys and economy.keys[c.key or ""] or 0
		local have = economy and economy.crates and economy.crates[id] or 0
		table.insert(out, {
			id = id, name = c.name, count = have, key = c.key, keys = keys,
			canOpen = have > 0 and (c.key == nil or keys > 0),
			guarantee = if left <= 1 then `Next opening: {c.guarantee.min} or better, guaranteed`
				else `{c.guarantee.min} or better guaranteed within {left} openings`,
			pity = c.guarantee.at - left,
		})
	end
	return out
end

-- The Workshop: every craftable item, its price, and whether you can pay it.
function LockerScreen.craftable(economy: any, filter: string?): { any }
	local sparks = economy and economy.sparks or 0
	local out = {}
	for _, it in Cosmetics.LIST do
		local cost = Loot.craftCost(it.id)
		if cost and matches(it, filter) then
			table.insert(out, { id = it.id, name = it.name, rarity = it.rarity, type = it.type, weapon = it.weapon,
				cost = cost, affordable = sparks >= cost })
		end
	end
	table.sort(out, byRarityThenName)
	return out
end

-- The Odds & Details rows: a heading per rarity with its share, then every item and its odds.
-- `pity` is openings since the last guaranteed-tier item; `guaranteed` shows the guaranteed opening.
function LockerScreen.oddsRows(crateId: string, pity: number, guaranteed: boolean?): { any }
	local c = Loot.CRATES[crateId]
	local list = Loot.odds(crateId, if guaranteed then c.guarantee.at - 1 else pity)
	local rows = {}
	for _, rarity in Loot.RARITIES do
		local share, items = 0, {}
		for _, o in list do
			if o.rarity == rarity then share += o.percent; table.insert(items, o) end
		end
		if #items > 0 then
			table.insert(rows, { kind = "tier", text = rarity, value = `{Loot.format(share)}  ·  each {Loot.format(items[1].percent)}`, rarity = rarity })
			for _, o in items do
				local it = Cosmetics.get(o.id) :: any
				table.insert(rows, { kind = "item", text = `{it.name}  ·  {LockerScreen.TYPE_LABEL[it.type]}`, value = Loot.format(o.percent), rarity = rarity, id = o.id })
			end
		end
	end
	return rows
end

-- The reel's tiles: scenery from the crate's own pool, the result on the winning tile.
function LockerScreen.reel(crateId: string, resultId: string, rand: () -> number): { string }
	local list = Loot.odds(crateId, 0)
	local out = {}
	for i = 1, LockerScreen.REEL.tiles do
		out[i] = if i == LockerScreen.REEL.win then resultId else list[math.floor(rand() * #list) + 1].id
	end
	return out
end

-- ------------------------------------------------------------------------------------ screen ----
-- opts: { sendLocker, sendEconomy, drawArt = (frame, id, w, h) -> (), tween = (obj, seconds,
--   props, done) -> (), now = () -> number, rand = () -> number }
function LockerScreen.new(parent: Instance, opts: any): any
	local self = setmetatable({
		opts = opts, locker = nil, economy = nil, tab = "locker", filter = "all", workshopFilter = "all",
		confirm = nil, pending = nil, now = opts.now or os.clock, rand = opts.rand or math.random,
		cardPool = {}, craftPool = {}, art = {},
	}, LockerScreen)
	local root = Ui.make("ScreenGui", parent, { Name = "BlockfallLocker", ResetOnSpawn = false, Enabled = false, DisplayOrder = 20 })
	self.root = root
	local panel = Ui.panel(root, "Locker", Ui.PURPLE, "LOCKER", 40)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position, panel.Size = UDim2.fromScale(0.5, 0.52), UDim2.new(1, -24, 1, -90)
	Ui.make("UISizeConstraint", panel, { MaxSize = Vector2.new(940, 620) })
	self.panel = panel
	local close = Ui.button(panel, "X", Ui.RED, function() self:close() end, { size = 18 })
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position, close.Size, close.ZIndex = UDim2.new(1, -6, 0, 4), UDim2.fromOffset(34, 32), 3
	local balance = Ui.text(panel, "", 14, Ui.GOLD)
	balance.Name = "Balance"
	balance.AnchorPoint = Vector2.new(1, 0)
	balance.Position, balance.Size, balance.ZIndex = UDim2.new(1, -48, 0, 8), UDim2.new(0.6, 0, 0, 24), 3
	balance.TextXAlignment = Enum.TextXAlignment.Right
	self.balance = balance
	-- the tabs
	self.tabs = {}
	for i, t in { { "locker", "LOCKER" }, { "crates", "CRATES" }, { "workshop", "WORKSHOP" } } do
		local b = Ui.button(panel, t[2], Ui.PANEL2, function() self:show(t[1]) end, { size = 16 })
		b.Name = "Tab_" .. t[1]
		b.Position, b.Size = UDim2.fromOffset(12 + (i - 1) * 132, 48), UDim2.fromOffset(124, 34)
		self.tabs[t[1]] = b
	end
	local function body(name: string): any
		local f = Ui.make("Frame", panel, { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0,
			Position = UDim2.fromOffset(12, 90), Size = UDim2.new(1, -24, 1, -128), Visible = false })
		return f
	end
	local function grid(parent: Instance, cell: Vector2): any
		local list = Ui.make("ScrollingFrame", parent, { Name = "Grid", BackgroundTransparency = 1, BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6 })
		Ui.make("UIGridLayout", list, { CellSize = UDim2.fromOffset(cell.X, cell.Y), CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder })
		return list
	end
	local function filters(parent: Instance, onPick: (string) -> ()): { [string]: any }
		local chips = {}
		for i, f in LockerScreen.FILTERS do
			local b = Ui.button(parent, f[2], Ui.PANEL2, function() onPick(f[1]) end, { size = 13, small = true })
			b.Name = "Filter_" .. f[1]
			b.Position, b.Size = UDim2.fromOffset((i - 1) * 86, 2), UDim2.fromOffset(80, 30)
			chips[f[1]] = b
		end
		return chips
	end
	self.lockerBody = body("LockerTab")
	self.lockerChips = filters(self.lockerBody, function(f) self.filter = f; self:refresh() end)
	self.lockerGrid = grid(self.lockerBody, Vector2.new(168, 206))
	-- saved outfits, at the end of the filter row: a number puts that outfit on; SAVE, then a number,
	-- saves what you wear into it
	self.saveMode = false
	self.outfitButtons = {}
	local outfits = Ui.make("Frame", self.lockerBody, { Name = "Outfits", BackgroundTransparency = 1, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.fromOffset(300, 30) })
	local save = Ui.button(outfits, "SAVE", Ui.PANEL2, function()
		self.saveMode = not self.saveMode
		self:say(if self.saveMode then "Pick an outfit slot to save what you are wearing" else "", Ui.GOLD)
		self:refresh()
	end, { size = 13, small = true })
	save.Name = "SaveOutfit"
	save.Position, save.Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(64, 30)
	self.saveOutfit = save
	for i = 1, Inventory.MAX_PRESETS do
		local b = Ui.button(outfits, tostring(i), Ui.PANEL2, function() self:outfit(i) end, { size = 14, small = true })
		b.Name = "Outfit" .. i
		b.Position, b.Size = UDim2.fromOffset(70 + (i - 1) * 46, 0), UDim2.fromOffset(40, 30)
		self.outfitButtons[i] = b
	end
	self.cratesBody = body("CratesTab")
	self.workshopBody = body("WorkshopTab")
	self.workshopChips = filters(self.workshopBody, function(f) self.workshopFilter = f; self:refresh() end)
	self.workshopGrid = grid(self.workshopBody, Vector2.new(168, 176))
	self.crateCards = {}
	for i, id in Inventory.CRATES do
		local card = Ui.panel(self.cratesBody, "Crate_" .. id, nil)
		card.BackgroundColor3 = Ui.INK
		card.Position, card.Size = UDim2.new((i - 1) * 0.5, if i == 1 then 0 else 6, 0, 4), UDim2.new(0.5, -6, 0, 300)
		local thumb = Ui.make("Frame", card, { Name = "Thumb", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(120, 100) })
		self:drawArt(thumb, "crate_" .. id, 120, 100)
		local name = Ui.text(card, Loot.CRATES[id].name, 22, Ui.WHITE, Ui.DISPLAY)
		name.Name, name.TextXAlignment = "Name", Enum.TextXAlignment.Left
		name.Position, name.Size = UDim2.fromOffset(144, 14), UDim2.new(1, -156, 0, 30)
		local count = Ui.text(card, "", 15, Ui.DIM)
		count.Name, count.TextXAlignment = "Count", Enum.TextXAlignment.Left
		count.Position, count.Size = UDim2.fromOffset(144, 48), UDim2.new(1, -156, 0, 22)
		local need = Ui.text(card, "", 14, Ui.DIM)
		need.Name, need.TextXAlignment = "Needs", Enum.TextXAlignment.Left
		need.Position, need.Size = UDim2.fromOffset(144, 72), UDim2.new(1, -156, 0, 22)
		local g = Ui.text(card, "", 14, Ui.GOLD)
		g.Name, g.TextXAlignment, g.TextWrapped = "Guarantee", Enum.TextXAlignment.Left, true
		g.Position, g.Size = UDim2.fromOffset(12, 124), UDim2.new(1, -24, 0, 40)
		local open = Ui.button(card, "OPEN", Ui.GREEN, function() self:openCrate(id) end, { size = 20 })
		open.Name = "Open"
		open.Position, open.Size = UDim2.fromOffset(12, 176), UDim2.new(0.5, -18, 0, 44)
		local odds = Ui.button(card, "ODDS & DETAILS", Ui.BLUE, function() self:showOdds(id, false) end, { size = 15 })
		odds.Name = "Odds"
		odds.Position, odds.Size = UDim2.new(0.5, 6, 0, 176), UDim2.new(0.5, -18, 0, 44)
		self.crateCards[id] = { card = card, count = count, need = need, guarantee = g, open = open }
	end
	local meter = Ui.text(self.cratesBody, "", 15, Ui.DIM)
	meter.Name = "Meter"
	meter.Position, meter.Size = UDim2.fromOffset(0, 316), UDim2.new(1, 0, 0, 24)
	self.meter = meter
	-- the message line
	local message = Ui.text(panel, "", 15, Ui.WHITE)
	message.Name = "Message"
	message.AnchorPoint = Vector2.new(0.5, 1)
	message.Position, message.Size = UDim2.new(0.5, 0, 1, -8), UDim2.new(1, -24, 0, 26)
	self.message = message
	self:buildOverlays()
	self:show("locker")
	return self
end

function LockerScreen.drawArt(self: any, frame: Instance, id: string, w: number, h: number)
	if self.art[frame] == id then return end
	self.art[frame] = id
	local draw = self.opts.drawArt
	if draw then draw(frame, id, w, h) end
end

function LockerScreen.say(self: any, text: string, colour: Color3?)
	self.message.Text, self.message.TextColor3 = text, colour or Ui.WHITE
end

-- Ask twice for anything that spends: the first press arms it, a second within CONFIRM_SECONDS acts.
function LockerScreen.armed(self: any, key: string, prompt: string): boolean
	local t = self.now()
	if self.confirm and self.confirm.key == key and t - self.confirm.at <= LockerScreen.CONFIRM_SECONDS then
		self.confirm = nil
		return true
	end
	self.confirm = { key = key, at = t }
	self:say(prompt, Ui.GOLD)
	return false
end

-- ------------------------------------------------------------------------------------- cards ----
local function card(self: any, pool: { any }, grid: Instance, i: number): any
	local c = pool[i]
	if c then return c end
	local f = Ui.make("Frame", grid, { Name = "Card" .. i, BackgroundColor3 = Ui.INK, BorderSizePixel = 0, LayoutOrder = i })
	Ui.corner(f, 8)
	local edge = Ui.stroke(f, Ui.EDGE, 2)
	local band = Ui.make("Frame", f, { Name = "Band", BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 4) })
	local thumb = Ui.make("Frame", f, { Name = "Thumb", BackgroundColor3 = Ui.PANEL, BorderSizePixel = 0,
		Position = UDim2.fromOffset(6, 10), Size = UDim2.new(1, -12, 0, 78) })
	Ui.corner(thumb, 6)
	local name = Ui.text(f, "", 15, Ui.WHITE)
	name.Name, name.TextTruncate = "Name", Enum.TextTruncate.AtEnd
	name.Position, name.Size = UDim2.fromOffset(6, 92), UDim2.new(1, -12, 0, 20)
	local meta = Ui.text(f, "", 12, Ui.DIM)
	meta.Name, meta.Position, meta.Size = "Meta", UDim2.fromOffset(6, 112), UDim2.new(1, -12, 0, 16)
	local extra = Ui.text(f, "", 12, Ui.DIM)
	extra.Name, extra.Position, extra.Size = "Extra", UDim2.fromOffset(6, 128), UDim2.new(1, -12, 0, 16)
	local primary = Ui.button(f, "", Ui.BLUE, nil, { size = 14, small = true })
	primary.Name = "Primary"
	primary.Position, primary.Size = UDim2.new(0, 6, 1, -64), UDim2.new(1, -12, 0, 28)
	local secondary = Ui.button(f, "", Ui.PANEL2, nil, { size = 12, small = true })
	secondary.Name = "Secondary"
	secondary.Position, secondary.Size = UDim2.new(0, 6, 1, -32), UDim2.new(1, -12, 0, 26)
	c = { frame = f, edge = edge, band = band, thumb = thumb, name = name, meta = meta, extra = extra,
		primary = primary, secondary = secondary, onPrimary = nil, onSecondary = nil }
	primary.Activated:Connect(function() if c.onPrimary then c.onPrimary() end end)
	secondary.Activated:Connect(function() if c.onSecondary then c.onSecondary() end end)
	pool[i] = c
	return c
end

function LockerScreen.refreshLocker(self: any)
	local cards = LockerScreen.cards(self.locker, self.economy, self.filter)
	for i, m in cards do
		local c = card(self, self.cardPool, self.lockerGrid, i)
		local col = colourOf(m.rarity)
		c.frame.Visible = true
		c.band.BackgroundColor3, c.edge.Color = col, if m.worn then Ui.GOLD else Ui.EDGE
		c.name.Text = m.name
		local serial = LockerScreen.serialText(m)
		c.meta.Text = `{m.rarity}{if serial ~= "" then "  ·  " .. serial else ""}`
		c.meta.TextColor3 = col
		c.extra.Text = if m.copies == 0 then "Studio: on loan" else LockerScreen.existence(m.exist)
		self:drawArt(c.thumb, m.id, 150, 78)
		c.primary.Text = if m.worn then "TAKE OFF" else "WEAR"
		Ui.paint(c.primary, if m.worn then Ui.PANEL2 else Ui.BLUE)
		c.onPrimary = function()
			if m.worn then
				local msg: any = { action = "remove" }
				if m.type == "weapon_skin" then msg.weapon = m.weapon else msg.slot = Inventory.SLOTS[m.type] end
				self.opts.sendLocker(msg)
			else
				self.opts.sendLocker({ action = "equip", id = m.id })
			end
		end
		local uid = m.uids[1]
		c.secondary.Visible = uid ~= nil
		c.secondary.Text = `SALVAGE  +{Loot.dupe(m.rarity)}`
		c.onSecondary = function()
			if uid and self:armed("salvage:" .. uid, `Press SALVAGE again to turn {m.name}{if m.serial then "" else ""} into {Loot.dupe(m.rarity)} Sparks`) then
				self.opts.sendEconomy({ action = "salvage", uid = uid })
			end
		end
	end
	for i = #cards + 1, #self.cardPool do self.cardPool[i].frame.Visible = false end
	if #cards == 0 then self:say(EMPTY, Ui.DIM)
	elseif self.message.Text == EMPTY then self:say("") end
end

-- An outfit slot pressed: save into it (after SAVE) or put it on.
function LockerScreen.outfit(self: any, i: number)
	local slots = self.locker and self.locker.presets or {}
	if i > #slots then
		self:say(if #slots <= 1 then "VIP has five outfit slots" else "That slot is not yours", Ui.DIM)
		return
	end
	if self.saveMode then
		self.saveMode = false
		self.opts.sendLocker({ action = "savePreset", slot = i })
		self:say(`Saved to outfit {i}`, Ui.GREEN)
	elseif slots[i] then
		self.opts.sendLocker({ action = "wearPreset", slot = i })
	else
		self:say(`Outfit {i} is empty: press SAVE, then {i}`, Ui.DIM)
	end
	self:refresh()
end

function LockerScreen.refreshOutfits(self: any)
	local slots = self.locker and self.locker.presets or {}
	Ui.paint(self.saveOutfit, if self.saveMode then Ui.GOLD else Ui.PANEL2)
	for i, b in self.outfitButtons do
		local mine = i <= #slots
		b.Visible = mine or i == #slots + 1      -- one locked slot shows, so VIP's extra slots are discoverable
		b.Text = if mine then tostring(i) else "VIP"
		Ui.paint(b, if not mine then Ui.PANEL else if slots[i] then Ui.BLUE else Ui.PANEL2)
	end
end

function LockerScreen.refreshCrates(self: any)
	for _, m in LockerScreen.crates(self.economy) do
		local c = self.crateCards[m.id]
		c.count.Text = `You have {m.count}`
		c.need.Text = if m.key then `Needs a Forge Key  ·  you have {m.keys}` else "Free to open"
		c.guarantee.Text = m.guarantee
		Ui.paint(c.open, if m.canOpen then Ui.GREEN else Ui.PANEL2)
	end
	local left = self.economy and self.economy.meter and math.ceil(self.economy.meter)
	self.meter.Text = if left then `Next drop in {left} {if left == 1 then "game" else "games"}` else "Play a match to start your drop meter"
end

function LockerScreen.refreshWorkshop(self: any)
	local list = LockerScreen.craftable(self.economy, self.workshopFilter)
	for i, m in list do
		local c = card(self, self.craftPool, self.workshopGrid, i)
		local col = colourOf(m.rarity)
		c.frame.Visible = true
		c.band.BackgroundColor3, c.edge.Color = col, Ui.EDGE
		c.name.Text = m.name
		c.meta.Text, c.meta.TextColor3 = m.rarity, col
		c.extra.Text = `{LockerScreen.number(m.cost)} Sparks`
		self:drawArt(c.thumb, m.id, 150, 78)
		c.primary.Text = "CRAFT"
		Ui.paint(c.primary, if m.affordable then Ui.GREEN else Ui.PANEL2)
		c.onPrimary = function()
			if not m.affordable then self:say(`{m.name} costs {LockerScreen.number(m.cost)} Sparks`, Ui.RED); return end
			if self:armed("craft:" .. m.id, `Press CRAFT again to spend {LockerScreen.number(m.cost)} Sparks on {m.name}`) then
				self.opts.sendEconomy({ action = "craft", id = m.id })
			end
		end
		c.secondary.Visible = false
		c.onSecondary = nil
	end
	for i = #list + 1, #self.craftPool do self.craftPool[i].frame.Visible = false end
end

function LockerScreen.refresh(self: any)
	local e = self.economy
	self.balance.Text = if e then `{LockerScreen.number(e.sparks or 0)} Sparks   ·   {e.keys and e.keys.forge or 0} Forge Keys` else ""
	for id, b in self.tabs do Ui.paint(b, if id == self.tab then Ui.PURPLE else Ui.PANEL2) end
	for id, b in self.lockerChips do Ui.paint(b, if id == self.filter then Ui.BLUE else Ui.PANEL2) end
	for id, b in self.workshopChips do Ui.paint(b, if id == self.workshopFilter then Ui.BLUE else Ui.PANEL2) end
	if self.tab == "locker" then self:refreshLocker(); self:refreshOutfits()
	elseif self.tab == "crates" then self:refreshCrates()
	else self:refreshWorkshop() end
end

function LockerScreen.show(self: any, tab: string)
	self.tab = tab
	self.lockerBody.Visible, self.cratesBody.Visible, self.workshopBody.Visible = tab == "locker", tab == "crates", tab == "workshop"
	self:say("")
	self:refresh()
end

-- -------------------------------------------------------------------------------- overlays ----
function LockerScreen.buildOverlays(self: any)
	local function cover(name: string): any
		local f = Ui.make("Frame", self.panel, { Name = name, BackgroundColor3 = Ui.INK, BackgroundTransparency = 0.04,
			BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 10 })
		Ui.corner(f, 12)
		return f
	end
	-- the crate opening: a reel that slows onto what the server rolled
	local opening = cover("Opening")
	local title = Ui.text(opening, "", 24, Ui.WHITE, Ui.DISPLAY)
	title.Name, title.Position, title.Size, title.ZIndex = "Title", UDim2.fromOffset(0, 24), UDim2.new(1, 0, 0, 34), 11
	local clip = Ui.make("Frame", opening, { Name = "Reel", BackgroundColor3 = Ui.PANEL, BorderSizePixel = 0, ClipsDescendants = true,
		Position = UDim2.new(0, 16, 0.5, -70), Size = UDim2.new(1, -32, 0, 128), ZIndex = 11 })
	Ui.corner(clip, 8)
	local strip = Ui.make("Frame", clip, { Name = "Strip", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 11,
		Size = UDim2.fromOffset(LockerScreen.REEL.tiles * LockerScreen.REEL.width, 112) })
	local needle = Ui.make("Frame", clip, { Name = "Needle", BackgroundColor3 = Ui.GOLD, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 3, 1, 0), ZIndex = 13 })
	local _ = needle
	local result = Ui.text(opening, "", 22, Ui.WHITE, Ui.DISPLAY)
	result.Name, result.Position, result.Size, result.ZIndex = "Result", UDim2.new(0, 0, 0.5, 72), UDim2.new(1, 0, 0, 30), 11
	local detail = Ui.text(opening, "", 15, Ui.DIM)
	detail.Name, detail.Position, detail.Size, detail.ZIndex = "Detail", UDim2.new(0, 0, 0.5, 104), UDim2.new(1, 0, 0, 22), 11
	local collect = Ui.button(opening, "COLLECT", Ui.GREEN, function() self:closeOpening() end, { size = 20 })
	collect.Name, collect.ZIndex, collect.Visible = "Collect", 12, false
	collect.AnchorPoint = Vector2.new(0.5, 1)
	collect.Position, collect.Size = UDim2.new(0.5, 0, 1, -18), UDim2.fromOffset(200, 46)
	self.opening = { frame = opening, title = title, strip = strip, result = result, detail = detail, collect = collect, tiles = {} }
	-- Odds & Details
	local odds = cover("OddsPanel")
	local oTitle = Ui.text(odds, "ODDS & DETAILS", 22, Ui.WHITE, Ui.DISPLAY)
	oTitle.Name, oTitle.Position, oTitle.Size, oTitle.ZIndex = "Title", UDim2.fromOffset(16, 10), UDim2.new(1, -80, 0, 30), 11
	oTitle.TextXAlignment = Enum.TextXAlignment.Left
	local sub = Ui.text(odds, "", 13, Ui.DIM)
	sub.Name, sub.Position, sub.Size, sub.ZIndex = "Sub", UDim2.fromOffset(16, 40), UDim2.new(1, -32, 0, 18), 11
	sub.TextXAlignment = Enum.TextXAlignment.Left
	local now = Ui.button(odds, "THIS OPENING", Ui.BLUE, function() self:showOdds(self.oddsCrate, false) end, { size = 13, small = true })
	now.Name, now.ZIndex = "Now", 11
	now.Position, now.Size = UDim2.fromOffset(16, 64), UDim2.fromOffset(150, 28)
	local gua = Ui.button(odds, "GUARANTEED OPENING", Ui.PANEL2, function() self:showOdds(self.oddsCrate, true) end, { size = 13, small = true })
	gua.Name, gua.ZIndex = "Guaranteed", 11
	gua.Position, gua.Size = UDim2.fromOffset(174, 64), UDim2.fromOffset(190, 28)
	local list = Ui.make("ScrollingFrame", odds, { Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 11,
		Position = UDim2.fromOffset(16, 100), Size = UDim2.new(1, -32, 1, -150), CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6 })
	Ui.make("UIListLayout", list, { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
	local foot = Ui.text(odds, "Odds are rounded to four digits past the first non-zero one, so shown odds may not add to exactly 100%. Every item in a rarity is equally likely. Duplicates are kept: salvage them for Sparks.", 12, Ui.DIM)
	foot.Name, foot.ZIndex, foot.TextWrapped = "Footer", 11, true
	foot.AnchorPoint = Vector2.new(0, 1)
	foot.Position, foot.Size = UDim2.new(0, 16, 1, -8), UDim2.new(1, -120, 0, 40)
	local back = Ui.button(odds, "BACK", Ui.PANEL2, function() odds.Visible = false end, { size = 16 })
	back.Name, back.ZIndex = "Back", 12
	back.AnchorPoint = Vector2.new(1, 1)
	back.Position, back.Size = UDim2.new(1, -16, 1, -10), UDim2.fromOffset(90, 36)
	self.odds = { frame = odds, sub = sub, now = now, guaranteed = gua, list = list, rows = {} }
end

function LockerScreen.showOdds(self: any, crateId: string, guaranteed: boolean)
	self.oddsCrate = crateId
	local o = self.odds
	local cards = LockerScreen.crates(self.economy)
	local pity = 0
	for _, m in cards do if m.id == crateId then pity = m.pity end end
	local rows = LockerScreen.oddsRows(crateId, pity, guaranteed)
	local c = Loot.CRATES[crateId]
	o.sub.Text = `{c.name}  ·  {#rows} lines  ·  ` .. (if guaranteed then `the {c.guarantee.at}th opening without {c.guarantee.min} or better`
		else `{c.guarantee.min} or better guaranteed by the {c.guarantee.at}th opening`)
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
		local col = if r.kind == "tier" then colourOf(r.rarity) else Ui.WHITE
		row.label.TextColor3, row.value.TextColor3 = col, if r.kind == "tier" then col else Ui.DIM
		row.label.Font = if r.kind == "tier" then Ui.DISPLAY else Ui.LABEL
	end
	for i = #rows + 1, #o.rows do o.rows[i].frame.Visible = false end
	o.frame.Visible = true
end

function LockerScreen.openCrate(self: any, crateId: string)
	if self.pending then return end
	local m
	for _, c in LockerScreen.crates(self.economy) do if c.id == crateId then m = c end end
	if not m or m.count < 1 then self:say(`You have no {Loot.CRATES[crateId].name}: they drop from matches`, Ui.RED); return end
	if m.key and m.keys < 1 then self:say("You need a Forge Key: they drop from matches and weekly challenges", Ui.RED); return end
	self.pending = crateId
	local o = self.opening
	o.title.Text = `Opening a {Loot.CRATES[crateId].name}...`
	o.result.Text, o.detail.Text, o.collect.Visible = "", "", false
	o.frame.Visible = true
	self.opts.sendEconomy({ action = "open", crate = crateId, pity = m.pity })
end

-- The server's answer to an opening: the reel spins onto it.
function LockerScreen.reveal(self: any, res: any)
	local crateId = self.pending
	if not crateId then return end
	local o = self.opening
	local ids = LockerScreen.reel(crateId, res.id, self.rand)
	local R = LockerScreen.REEL
	for i, id in ids do
		local t = o.tiles[i]
		if not t then
			t = Ui.make("Frame", o.strip, { Name = "Tile" .. i, BackgroundColor3 = Ui.PANEL2, BorderSizePixel = 0, ZIndex = 11,
				Position = UDim2.fromOffset(R.pad + (i - 1) * R.width, 8), Size = UDim2.fromOffset(R.width - 8, 96) })
			Ui.corner(t, 6)
			local band = Ui.make("Frame", t, { Name = "Band", BorderSizePixel = 0, ZIndex = 12, Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(1, 0, 0, 4) })
			local thumb = Ui.make("Frame", t, { Name = "Thumb", BackgroundTransparency = 1, ZIndex = 12, Position = UDim2.fromOffset(4, 6), Size = UDim2.new(1, -8, 1, -16) })
			t = { frame = t, band = band, thumb = thumb }
			o.tiles[i] = t
		end
		local it = Cosmetics.get(id) :: any
		t.band.BackgroundColor3 = colourOf(it.rarity)
		t.id = id
		self:drawArt(t.thumb, id, R.width - 16, 80)
	end
	-- from the first tile under the needle to the winning one, landing a little off its centre
	local centre = R.pad + (R.width - 8) / 2
	local start = UDim2.new(0.5, -centre, 0, 8)
	local finish = UDim2.new(0.5, -(centre + (R.win - 1) * R.width) + math.floor((self.rand() - 0.5) * (R.width - 24)), 0, 8)
	o.strip.Position = start
	local it = Cosmetics.get(res.id) :: any
	local done = function()
		o.title.Text = `{Loot.CRATES[crateId].name} opened`
		o.result.Text = `{it.rarity}: {it.name}`
		o.result.TextColor3 = colourOf(it.rarity)
		local serial = if res.serial and res.serial > 0 then `#{res.serial}` else ""
		local exist = LockerScreen.existence(res.copies)
		o.detail.Text = table.concat({ LockerScreen.TYPE_LABEL[it.type] .. (if it.weapon then ` for {it.weapon}` else ""), serial, exist }, "   ·   ")
		o.collect.Visible = true
		self.pending = nil
	end
	local tween = self.opts.tween
	if tween then tween(o.strip, 4.2, { Position = finish }, done)
	else o.strip.Position = finish; done() end
end

function LockerScreen.closeOpening(self: any)
	self.opening.frame.Visible = false
	self.pending = nil
end

-- -------------------------------------------------------------------------------- the server ----
function LockerScreen.setLocker(self: any, view: any)
	self.locker = view
	if type(view) == "table" and view.error then self:say(`Could not do that: {view.error}`, Ui.RED) end
	self:refresh()
end

function LockerScreen.setEconomy(self: any, view: any)
	self.economy = view
	local e = type(view) == "table" and view.event
	if e then
		if e.error then
			if self.pending then self:closeOpening() end
			self:say(`Could not do that: {e.error}`, Ui.RED)
		elseif e.done == "open" and e.result then
			self:reveal(e.result)
		elseif e.done == "craft" and e.result then
			local it = Cosmetics.get(e.result.id) :: any
			self:say(`Crafted {it.name}{if e.result.serial then "  #" .. e.result.serial else ""}`, Ui.GREEN)
		elseif e.done == "salvage" and e.result then
			self:say(`Salvaged for {e.result.sparks} Sparks`, Ui.GREEN)
		end
	end
	self:refresh()
end

function LockerScreen.open(self: any) self.root.Enabled = true; self:refresh() end
function LockerScreen.close(self: any) self.root.Enabled = false; self.odds.frame.Visible = false end
function LockerScreen.toggle(self: any) if self.root.Enabled then self:close() else self:open() end end
function LockerScreen.isOpen(self: any): boolean return self.root.Enabled == true end

return LockerScreen
