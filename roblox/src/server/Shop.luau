--!strict
-- Selling things for Robux, on the server (Roblox only; docs/briefs/crates-and-monetisation-plan.md,
-- phase 5). What the Shop screen shows (`view`, the `shop` contract in docs/briefs/gpt-shop-screen.md),
-- what a request may prompt (`request`), and what a receipt grants (`receipt`).
--
-- Rules it keeps:
-- - prices are Products', shown in Robux; an id of 0 is "not on sale yet" and never prompts;
-- - Forge Keys are not offered to, and cannot be prompted by, a player PolicyService restricts from
--   paid random items (`restricted`, which fails closed);
-- - the featured shop sells four items a day outright (one each of Uncommon, Rare, Epic, Legendary,
--   the same on every server); a purchase grants the item the player chose before the prompt, and
--   one that arrives without a remembered choice becomes a credit for an item of that rarity - a
--   purchase is never lost, and never turned into Sparks, which are never sold;
-- - clothing is sold one piece at a time (a product per price tier, the chosen piece remembered like a
--   featured item) or as a pack (a product per pack). A pack grants only the pieces its buyer is
--   missing, is refused when they own them all, and is offered only while it costs less than those
--   pieces bought singly - so it can never charge more than buying one by one. A piece bought singly
--   while a pack's prompt was open comes back as a credit for another piece of its tier;
-- - every grant goes through Economy.purchase: once per purchase id, inside the record's own write.
local Shared = game:GetService("ReplicatedStorage").Shared
local Cosmetics = require(Shared.Cosmetics)
local Inventory = require(Shared.Inventory)
local Products = require(Shared.Products)
local Clothing: any = require(Shared.RobloxClothing)
local Shop = {}
Shop.__index = Shop

Shop.INTENT_SECONDS = 600      -- how long a chosen featured item waits for its receipt
Shop.FEATURED_RARITIES = Inventory.CREDIT_RARITIES

-- opts: { economy = Economy, passes = Passes, restricted = (userId) -> boolean, time = () -> number (os.time) }
function Shop.new(opts: any): any
	return setmetatable({ economy = opts.economy, passes = opts.passes, restrictedFn = opts.restricted,
		time = opts.time or os.time, intents = {}, pieceIntents = {}, packIntents = {} }, Shop)
end

-- Restricted from paid random items? Unknown or failed is restricted.
function Shop.restricted(self: any, userId: number): boolean
	local ok, r = pcall(function() return self.restrictedFn and self.restrictedFn(userId) end)
	return not ok or r ~= false
end

-- The day's four featured items: deterministic from the UTC day, so every server agrees.
function Shop.featured(day: number): { any }
	local s = (day * 7919 + 104729) % 2147483647
	if s == 0 then s = 1 end
	local function rand(): number s = (s * 16807) % 2147483647; return (s - 1) / 2147483646 end
	local out = {}
	for _, rarity in Shop.FEATURED_RARITIES do
		local pool = {}
		for _, it in Cosmetics.LIST do
			if it.source == "crate" and it.rarity == rarity then table.insert(pool, it.id) end
		end
		table.sort(pool)
		local t = Products.FEATURED[rarity]
		table.insert(out, { id = pool[math.floor(rand() * #pool) + 1], rarity = rarity, price = t.price, product = t.id })
	end
	return out
end

local function today(self: any): number
	return math.floor(self.time() / 86400)
end

-- The `shop` table the screen draws (the contract in docs/briefs/gpt-shop-screen.md).
function Shop.view(self: any, userId: number): any
	local inv = self.economy:inventory(userId)
	local restricted = self:restricted(userId)
	local featured = {}
	for _, f in Shop.featured(today(self)) do
		table.insert(featured, { id = f.id, price = f.price, owned = Inventory.owns(inv, f.id), credit = inv.credits[f.rarity] > 0 })
	end
	local keys = {}
	if not restricted then
		for _, b in Products.KEYS do table.insert(keys, { bundle = b.bundle, count = b.count, price = b.price }) end
	end
	local passes = {}
	for _, p in Products.PASSES do
		table.insert(passes, { id = p.id, name = p.name, price = p.price, owned = self.passes:owns(userId, p.id),
			available = p.available, perks = table.clone(p.perks) })
	end
	return { restricted = restricted, resetsIn = 86400 - self.time() % 86400, featured = featured, keys = keys, passes = passes,
		clothing = Shop.clothing(inv) }
end

local function piecePrice(it: any): number
	return Products.CLOTHING[it.priceTier].price
end
local function packPieces(packId: string): { any }
	local out = {}
	for _, it in Clothing.items do if it.pack == packId then table.insert(out, it) end end
	return out
end

-- The clothing packs as the screen shows them: each pack with its pieces, what owning some of them
-- leaves to pay one by one, and whether the pack is still the cheaper way (`offer`).
function Shop.clothing(inv: any): { any }
	local out = {}
	for _, p in Clothing.packs do
		local pieces, missing, missingTotal, total = {}, 0, 0, 0
		for _, it in packPieces(p.id) do
			local owned = Inventory.owns(inv, it.id)
			total += piecePrice(it)
			if not owned then missing += 1; missingTotal += piecePrice(it) end
			table.insert(pieces, { id = it.id, price = piecePrice(it), owned = owned, credit = inv.credits[it.priceTier] > 0 })
		end
		local price = Products.PACKS[p.id].price
		table.insert(out, { id = p.id, name = p.name, price = price, total = total, missing = missing, missingTotal = missingTotal,
			offer = missing > 0 and price < missingTotal, pieces = pieces })
	end
	return out
end

-- A request from the screen. Returns ok and the event to send: { prompt = { kind, id } }, or for a
-- credit redeemed, { purchased = ... }; or false and why not.
function Shop.request(self: any, userId: number, msg: any): (boolean, any)
	if type(msg) ~= "table" or msg.action ~= "buy" then return false, "bad request" end
	if msg.kind == "keys" then
		if self:restricted(userId) then return false, "Forge Keys are not available for your account" end
		local b = Products.keyBundle(msg.bundle)
		if not b then return false, "no such bundle" end
		if b.id == 0 then return false, "Forge Keys are not on sale yet" end
		return true, { prompt = { kind = "product", id = b.id } }
	elseif msg.kind == "item" then
		if type(msg.id) ~= "string" or #msg.id > 64 then return false, "no such item" end
		local pick
		for _, f in Shop.featured(today(self)) do if f.id == msg.id then pick = f end end
		if not pick then return false, "that is not in today's shop" end
		local inv = self.economy:inventory(userId)
		if Inventory.owns(inv, pick.id) then return false, "you already own it" end
		if inv.credits[pick.rarity] > 0 then
			-- a purchase already made, waiting for its choice: redeem it, no new prompt
			local ok, res = self.economy:purchase(userId, `credit:{pick.rarity}:{inv.credits[pick.rarity]}:{self.time()}`, function(i: any): (boolean, any)
				if i.credits[pick.rarity] < 1 then return false, "no credit" end
				local uid, why = self.economy:_grant(i, pick.id, true, "shop")
				if not uid then return false, why end
				i.credits[pick.rarity] -= 1
				return true, { kind = "item", id = pick.id, serial = i.items[uid].s }
			end)
			if not ok then return false, res end
			return true, { purchased = res }
		end
		if pick.product == 0 then return false, "the featured shop is not on sale yet" end
		self.intents[userId] = { id = pick.id, rarity = pick.rarity, at = self.time() }
		return true, { prompt = { kind = "product", id = pick.product } }
	elseif msg.kind == "piece" then
		local it
		for _, c in Clothing.items do if c.id == msg.id then it = c end end
		if not it then return false, "no such piece" end
		local inv = self.economy:inventory(userId)
		if Inventory.owns(inv, it.id) then return false, "you already own it" end
		if inv.credits[it.priceTier] > 0 then
			-- a clothing purchase already made, waiting for its piece: redeem it, no new prompt
			local ok, res = self.economy:purchase(userId, `credit:{it.priceTier}:{inv.credits[it.priceTier]}:{self.time()}`, function(i: any): (boolean, any)
				if i.credits[it.priceTier] < 1 then return false, "no credit" end
				local uid, why = self.economy:_grant(i, it.id, true, "shop")
				if not uid then return false, why end
				i.credits[it.priceTier] -= 1
				return true, { kind = "item", id = it.id, serial = i.items[uid].s }
			end)
			if not ok then return false, res end
			return true, { purchased = res }
		end
		local product = Products.CLOTHING[it.priceTier]
		if product.id == 0 then return false, "clothing is not on sale yet" end
		self.pieceIntents[userId] = { id = it.id, tier = it.priceTier, at = self.time() }
		return true, { prompt = { kind = "product", id = product.id } }
	elseif msg.kind == "pack" then
		local product = if type(msg.id) == "string" then Products.PACKS[msg.id] else nil
		if not product then return false, "no such pack" end
		local inv = self.economy:inventory(userId)
		local missing, missingTotal = {}, 0
		for _, it in packPieces(msg.id) do
			if not Inventory.owns(inv, it.id) then table.insert(missing, it.id); missingTotal += piecePrice(it) end
		end
		if #missing == 0 then return false, "you already own every piece in it" end
		if product.price >= missingTotal then return false, `the pieces you are missing cost {missingTotal} R$ one by one, less than the pack` end
		if product.id == 0 then return false, "clothing is not on sale yet" end
		self.packIntents[userId] = { id = msg.id, missing = missing, at = self.time() }
		return true, { prompt = { kind = "product", id = product.id } }
	elseif msg.kind == "pass" then
		local p = Products.pass(msg.id)
		if not p then return false, "no such pass" end
		if not p.available then return false, `{p.name} is coming soon` end
		if self.passes:owns(userId, p.id) then return false, `you already have {p.name}` end
		if p.pass == 0 then return false, `{p.name} is not on sale yet` end
		return true, { prompt = { kind = "pass", id = p.pass } }
	end
	return false, "bad request"
end

-- A Developer Product receipt (through Purchases): grant it once. Returns true when granted (or
-- already granted), and what was bought.
function Shop.receipt(self: any, userId: number, productId: number, purchaseId: string): (boolean, any)
	local kind, what = Products.byProductId(productId)
	if kind == "keys" then
		return self.economy:purchase(userId, purchaseId, function(inv: any): (boolean, any)
			inv.keys.forge.paid = math.min(Inventory.MAX_COUNT, inv.keys.forge.paid + what.count)
			return true, { kind = "keys", count = what.count }
		end)
	elseif kind == "featured" then
		local intent = self.intents[userId]
		local fresh = intent and intent.rarity == what and self.time() - intent.at <= Shop.INTENT_SECONDS
		local ok, res = self.economy:purchase(userId, purchaseId, function(inv: any): (boolean, any)
			if fresh and not Inventory.owns(inv, intent.id) then
				local uid, why = self.economy:_grant(inv, intent.id, true, "shop")
				if not uid then return false, why end
				return true, { kind = "item", id = intent.id, serial = inv.items[uid].s }
			end
			inv.credits[what] = math.min(Inventory.MAX_COUNT, inv.credits[what] + 1)
			return true, { kind = "credit", rarity = what }
		end)
		if ok and fresh then self.intents[userId] = nil end
		return ok, res
	elseif kind == "clothing" then
		-- each kind of purchase remembers its own choice, so opening one prompt never forgets another's
		local intent = self.pieceIntents[userId]
		local fresh = intent and intent.tier == what and self.time() - intent.at <= Shop.INTENT_SECONDS
		local ok, res = self.economy:purchase(userId, purchaseId, function(inv: any): (boolean, any)
			if fresh and not Inventory.owns(inv, intent.id) then
				local uid, why = self.economy:_grant(inv, intent.id, true, "shop")
				if not uid then return false, why end
				return true, { kind = "item", id = intent.id, serial = inv.items[uid].s }
			end
			inv.credits[what] = math.min(Inventory.MAX_COUNT, inv.credits[what] + 1)
			return true, { kind = "credit", tier = what }
		end)
		if ok and fresh then self.pieceIntents[userId] = nil end
		return ok, res
	elseif kind == "pack" then
		local intent = self.packIntents[userId]
		local fresh = intent and intent.id == what and self.time() - intent.at <= Shop.INTENT_SECONDS
		local ok, res = self.economy:purchase(userId, purchaseId, function(inv: any): (boolean, any)
			local granted, credited = {}, {}
			for _, it in packPieces(what) do
				if not Inventory.owns(inv, it.id) then
					local uid, why = self.economy:_grant(inv, it.id, true, "shop")
					if not uid then return false, why end
					table.insert(granted, it.id)
				elseif fresh and table.find(intent.missing, it.id) then
					-- bought singly while this pack's prompt was open: not paid for twice
					inv.credits[it.priceTier] = math.min(Inventory.MAX_COUNT, inv.credits[it.priceTier] + 1)
					table.insert(credited, it.id)
				end
			end
			return true, { kind = "pack", id = what, granted = granted, credited = credited }
		end)
		if ok and fresh then self.packIntents[userId] = nil end
		return ok, res
	end
	return false, "unknown product"
end

-- A player left: what they chose before a prompt is dropped (a receipt that still arrives becomes a
-- credit, never lost).
function Shop.forget(self: any, userId: number)
	self.intents[userId], self.pieceIntents[userId], self.packIntents[userId] = nil, nil, nil
end

-- Grant what owned passes put in the Locker, once each (on join, and when a pass is bought).
function Shop.grantPassItems(self: any, userId: number): { string }
	local granted = {}
	for passId, ids in Products.PASS_ITEMS do
		if self.passes:owns(userId, passId) then
			for _, id in ids do
				if not Inventory.owns(self.economy:inventory(userId), id) then
					local uid = self.economy:grant(userId, id, true, "pass")
					if uid then table.insert(granted, id) end
				end
			end
		end
	end
	return granted
end

return Shop
