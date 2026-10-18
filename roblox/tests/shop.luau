--!nocheck
-- Selling things (phase 5 of docs/briefs/crates-and-monetisation-plan.md; Roblox only): the Shop's
-- view and rules, receipts granted exactly once (beyond the record's last fifty too), credits for a
-- purchase with no remembered choice, passes and what they grant, the Wardrobe's limit, VIP's
-- outfits, and worn spawn effects. Real server modules; fake stores and marketplace.
local Loader = require("./loader")
local Inventory, Products, Cosmetics = Loader.load("Inventory"), Loader.load("Products"), Loader.load("Cosmetics")
local Store = Loader.loadFrom("src/server/", "AvatarStore")
local Mint = Loader.loadFrom("src/server/", "Mint")
local Economy = Loader.loadFrom("src/server/", "Economy")
local Passes = Loader.loadFrom("src/server/", "Passes")
local Shop = Loader.loadFrom("src/server/", "Shop")
local Locker = Loader.loadFrom("src/server/", "Locker")
local Purchases = Loader.loadFrom("src/server/", "Purchases")
local FxPlayer = Loader.loadFrom("src/client/", "FxPlayer")

local DAY = 86400 * 20500
local clock = DAY + 3600
local function world(opts)
	opts = opts or {}
	local st = Store.new(nil, function() return 1 end, { sessionOnly = true })
	local market = { owns = opts.owns or {} }
	function market:UserOwnsGamePassAsync(_, passId) return self.owns[passId] == true end
	local passes = Passes.new({ market = market, studio = false })
	local econ = Economy.new({ store = st, mint = Mint.new(nil, nil, true), rand = function() return 0.3 end,
		time = function() return clock end, paidAllowed = function() return opts.restricted == false end,
		vip = function(id) return passes:owns(id, "vip") end })
	local shop = Shop.new({ economy = econ, passes = passes, time = function() return clock end,
		restricted = opts.restrictedFn or function() return opts.restricted ~= false end })
	return { store = st, passes = passes, econ = econ, shop = shop, market = market }
end
-- give every product and pass a real id for these tests (0 is "not created yet")
local function createProducts()
	for i, b in Products.KEYS do b.id = 1000 + i end
	local n = 2000
	for _, r in Inventory.CREDIT_RARITIES do n += 1; Products.FEATURED[r].id = n end
	for i, p in Products.PASSES do p.pass = 3000 + i end
end
local function uncreate()
	for _, b in Products.KEYS do b.id = 0 end
	for _, t in Products.FEATURED do t.id = 0 end
	for _, p in Products.PASSES do p.pass = 0 end
end

-- 1. The featured shop: four items a day, one of each rarity, all crate items, the same for a day
-- on every server, changing day to day.
do
	local a, b = Shop.featured(20500), Shop.featured(20500)
	assert(#a == 4, "not four featured items")
	for i, f in a do
		local it = Cosmetics.get(f.id)
		assert(it and it.source == "crate" and it.rarity == Shop.FEATURED_RARITIES[i] and f.price == Products.FEATURED[f.rarity].price,
			`featured {i} is {f.id}, not a {Shop.FEATURED_RARITIES[i]} crate item at its price`)
		assert(b[i].id == f.id, "two servers disagree on the featured shop")
	end
	local changed = false
	for d = 20501, 20510 do
		for i, f in Shop.featured(d) do if f.id ~= a[i].id then changed = true end end
	end
	assert(changed, "the featured shop never changes")
end

-- 2. The view: plain Robux prices, no key bundles for a restricted (or unknown) player, passes with
-- their perks and whether they are on sale.
do
	local w = world({ restricted = true })
	local v = w.shop:view(1)
	assert(v.restricted and #v.keys == 0, "a restricted player was offered Forge Keys")
	assert(#v.featured == 4 and v.resetsIn > 0 and v.resetsIn <= 86400, "the featured shop or its countdown is missing")
	local failing = world({ restrictedFn = function() error("policy service down") end })
	assert(failing.shop:view(1).restricted and #failing.shop:view(1).keys == 0, "a failed policy check offered keys")
	local open = world({ restricted = false })
	local ov = open.shop:view(1)
	assert(not ov.restricted and #ov.keys == #Products.KEYS and ov.keys[2].price == 110, "an unrestricted player sees no keys, or the wrong prices")
	for _, p in ov.passes do
		local src = Products.pass(p.id)
		assert(p.price == src.price and p.available == src.available and #p.perks > 0, `{p.id} is shown wrong`)
	end
end

-- 3. Requests: nothing is prompted that is not on sale, restricted, not today's, or already owned;
-- otherwise the product's own id is prompted.
do
	uncreate()
	local w = world({ restricted = false })
	local feat = Shop.featured(math.floor(clock / 86400))
	assert(not w.shop:request(1, { action = "buy", kind = "keys", bundle = "keys5" }), "a product with id 0 was prompted")
	assert(not w.shop:request(1, { action = "buy", kind = "item", id = feat[1].id }), "a featured item with id 0 was prompted")
	createProducts()
	local ok, ev = w.shop:request(1, { action = "buy", kind = "keys", bundle = "keys5" })
	assert(ok and ev.prompt.kind == "product" and ev.prompt.id == Products.keyBundle("keys5").id, "keys did not prompt their product")
	assert(not w.shop:request(1, { action = "buy", kind = "keys", bundle = "keys999" }), "a made-up bundle was prompted")
	local r = world({ restricted = true })
	assert(not r.shop:request(1, { action = "buy", kind = "keys", bundle = "keys1" }), "a restricted player was prompted for keys")
	assert(not w.shop:request(1, { action = "buy", kind = "item", id = "sword_starforged_nope" }), "an item not in today's shop was prompted")
	local ok2, ev2 = w.shop:request(1, { action = "buy", kind = "item", id = feat[3].id })
	assert(ok2 and ev2.prompt.id == Products.FEATURED[feat[3].rarity].id and w.shop.intents[1].id == feat[3].id, "a featured item did not prompt its tier, or its choice was not remembered")
	local inv = w.econ:inventory(1)
	Inventory.add(inv, feat[2].id, 1, false, "drop", clock)
	assert(not w.shop:request(1, { action = "buy", kind = "item", id = feat[2].id }), "an owned item was prompted")
	assert(not w.shop:request(1, { action = "buy", kind = "pass", id = "season" }), "a coming-soon pass was prompted")
	local ok3, ev3 = w.shop:request(1, { action = "buy", kind = "pass", id = "vip" })
	assert(ok3 and ev3.prompt.kind == "pass" and ev3.prompt.id == Products.pass("vip").pass, "VIP did not prompt its pass")
	for _, junk in { 5, {}, "buy", { action = "buy", kind = "item", id = string.rep("x", 999) }, { action = "buy", kind = {} } } do
		assert(not w.shop:request(1, junk), "a junk request was accepted")
	end
end

-- 4. Receipts: keys arrive once per purchase id; a featured item is the chosen one, paid; one with
-- no remembered choice is a credit, redeemed later without a second charge.
do
	createProducts()
	local w = world({ restricted = false })
	local inv = w.econ:inventory(1)
	local k5 = Products.keyBundle("keys5")
	assert(w.shop:receipt(1, k5.id, "P1") and inv.keys.forge.paid == 5, "five keys did not arrive")
	assert(w.shop:receipt(1, k5.id, "P1") and inv.keys.forge.paid == 5, "a redelivered receipt granted keys twice")
	local feat = Shop.featured(math.floor(clock / 86400))
	w.shop:request(1, { action = "buy", kind = "item", id = feat[4].id })
	local ok, res = w.shop:receipt(1, Products.FEATURED[feat[4].rarity].id, "P2")
	assert(ok and res.kind == "item" and Inventory.owns(inv, feat[4].id), "the chosen featured item did not arrive")
	for _, inst in inv.items do if inst.i == feat[4].id then assert(inst.p == true and inst.src == "shop", "a bought item is not marked paid") end end
	local ok2, res2 = w.shop:receipt(1, Products.FEATURED.Rare.id, "P3")
	assert(ok2 and res2.kind == "credit" and inv.credits.Rare == 1, "a purchase with no choice was not kept as a credit")
	local rare
	for _, f in Shop.featured(math.floor(clock / 86400)) do if f.rarity == "Rare" then rare = f end end
	local ok3, ev3 = w.shop:request(1, { action = "buy", kind = "item", id = rare.id })
	assert(ok3 and ev3.purchased and ev3.purchased.id == rare.id and inv.credits.Rare == 0 and Inventory.owns(inv, rare.id), "a credit was not redeemed for the chosen item")
	assert(not w.shop:receipt(1, 424242, "P4"), "an unknown product was granted")
end

-- 5. Purchases remembers every receipt, not just the record's last fifty: a receipt redelivered
-- after fifty-one newer purchases grants nothing; a receipt store it cannot read waits.
do
	local granted = 0
	local marks = {}
	local receipts = { fail = false }
	function receipts:GetAsync(k) if self.fail then error("down") end return marks[k] end
	function receipts:UpdateAsync(k, fn) marks[k] = fn(marks[k]) end
	local st = Store.new(nil, function() return 1 end, { sessionOnly = true })
	local p = Purchases.new({ store = st, player = function() return { UserId = 7 } end, receipts = receipts })
	p:on(55, function() granted += 1; return true end)
	for i = 1, 52 do assert(p:process({ PurchaseId = "R" .. i, PlayerId = 7, ProductId = 55 }) == "granted", "a purchase was not granted") end
	assert(granted == 52, "purchases were not each granted once")
	assert(p:process({ PurchaseId = "R1", PlayerId = 7, ProductId = 55 }) == "granted" and granted == 52, "an old receipt was granted again")
	receipts.fail = true
	assert(p:process({ PurchaseId = "R99", PlayerId = 7, ProductId = 55 }) == "later" and granted == 52, "a purchase was granted without checking the receipt store")
end

-- 6. Passes: asked once, remembered, recorded when bought; VIP puts its items in the Locker once,
-- paid (so never salvaged into Sparks); in Studio only available passes are owned.
do
	createProducts()
	local w = world({ owns = { [Products.pass("vip").pass] = true } })
	local asked = 0
	local real = w.market.UserOwnsGamePassAsync
	w.market.UserOwnsGamePassAsync = function(m, ...) asked += 1; return real(m, ...) end
	assert(w.passes:owns(1, "vip") and w.passes:owns(1, "vip") and asked == 1, "a pass was not remembered")
	assert(not w.passes:owns(1, "wardrobe"), "an unowned pass is owned")
	assert(w.passes:bought(1, Products.pass("wardrobe").pass) == "wardrobe" and w.passes:owns(1, "wardrobe"), "a bought pass was not recorded")
	local got = w.shop:grantPassItems(1)
	assert(#got == #Products.PASS_ITEMS.vip, "VIP did not grant its items")
	assert(#w.shop:grantPassItems(1) == 0, "VIP granted its items twice")
	local inv = w.econ:inventory(1)
	for uid, inst in inv.items do
		assert(inst.p == true and inst.src == "pass", "a pass item is not marked paid")
		assert(not w.econ:salvage(1, uid), "a pass item was salvaged into Sparks")
	end
	local studio = Passes.new({ studio = true })
	assert(studio:owns(1, "vip") and not studio:owns(1, "season"), "Studio owns passes that are not built, or not VIP")
end

-- 7. VIP's saved outfits: five slots with VIP, one without; saving and wearing; only owned items put on.
do
	local st = Store.new(nil, function() return 1 end, { sessionOnly = true })
	local vip = false
	local l = Locker.new({ store = st, studio = false, vip = function() return vip end })
	local inv = l:inventory(1)
	Inventory.add(inv, "sword_frostbite", 3, false, "drop", 1)
	Inventory.add(inv, "hit_sakura", 4, false, "drop", 1)
	l:apply(1, { action = "equip", id = "sword_frostbite" })
	l:apply(1, { action = "equip", id = "hit_sakura" })
	assert(#l:view(1).presets == 1, "a player without VIP does not have one outfit slot")
	assert(not l:apply(1, { action = "savePreset", slot = 2 }), "a second outfit slot saved without VIP")
	assert(l:apply(1, { action = "savePreset", slot = 1 }) and l:view(1).presets[1], "outfit 1 did not save")
	vip = true
	assert(#l:view(1).presets == Inventory.MAX_PRESETS, "VIP does not have five outfit slots")
	assert(not l:apply(1, { action = "wearPreset", slot = 3 }), "an empty outfit was worn")
	l:apply(1, { action = "remove", weapon = "Sword" })
	l:apply(1, { action = "remove", slot = "hit" })
	for uid, inst in inv.items do if inst.i == "hit_sakura" then Inventory.remove(inv, uid) end end
	assert(l:apply(1, { action = "wearPreset", slot = 1 }), "outfit 1 would not go on")
	assert(inv.equipped.skins.Sword == "sword_frostbite" and inv.equipped.hit == nil, "an outfit put on an item no longer owned, or missed one owned")
	for _, junk in { 0, 6, 1.5, "1", {} } do assert(not l:apply(1, { action = "savePreset", slot = junk }), `outfit slot {tostring(junk)} was accepted`) end
end

-- 8. Worn spawn effects: every one in the catalogue draws where its wearer reappears; a fighter
-- wearing none keeps the plain respawn.
do
	local Loadout = Loader.load("Loadout")
	local states = { { index = 0, x = 12, y = 3, state = "respawn" } }
	local count = 0
	for _, it in Cosmetics.LIST do
		if it.type == "spawn_effect" then
			local c = table.clone(Loadout.build("Classic", "Sword"))
			c.cosmetics = Inventory.cleanLoadout({ spawn = it.id })
			local P = FxPlayer.new()
			assert(FxPlayer.spawn(P, { type = "respawn", fighter = 0 }, states, { c }) and #P.items > 0, `{it.id} draws nothing`)
			for _, x in P.items do assert(math.abs(x.x - 12) < 6, `{it.id} draws away from the fighter`) end
			count += 1
		end
	end
	assert(count >= 5, "spawn effects missing from the catalogue")
	local bare = table.clone(Loadout.build("Classic", "Sword"))
	assert(not FxPlayer.spawn(FxPlayer.new(), { type = "respawn", fighter = 0 }, states, { bare }), "a fighter wearing nothing drew a spawn effect")
end
uncreate()
print("PASS shop: four featured items a day agreed by every server; plain prices, no keys for restricted or unknown players; nothing prompted that is not on sale, restricted, not today's or owned; keys granted once per receipt, featured items as chosen and paid, unchosen ones kept as credits and redeemed without a second charge; every receipt remembered beyond fifty; passes remembered and recorded, VIP's items once and unsalvageable; VIP's five outfits; worn spawn effects")
