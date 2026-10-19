--!nocheck
-- Selling clothing (phase 6 of docs/briefs/crates-and-monetisation-plan.md; Roblox only): single
-- pieces at their tier's price, packs that grant only what is missing and are offered only while
-- cheaper than buying those pieces one by one, receipts granted once, credits for a purchase with no
-- remembered piece or a piece bought twice by racing a pack, and nothing random. Real server modules;
-- fake stores.
local Loader = require("./loader")
local Inventory, Products, Cosmetics, Loot = Loader.load("Inventory"), Loader.load("Products"), Loader.load("Cosmetics"), Loader.load("Loot")
local Clothing = Loader.load("RobloxClothing")
local Store = Loader.loadFrom("src/server/", "AvatarStore")
local Mint = Loader.loadFrom("src/server/", "Mint")
local Economy = Loader.loadFrom("src/server/", "Economy")
local Passes = Loader.loadFrom("src/server/", "Passes")
local Shop = Loader.loadFrom("src/server/", "Shop")

local clock = 86400 * 20500 + 3600
local function world()
	local st = Store.new(nil, function() return 1 end, { sessionOnly = true })
	local market = {}
	function market:UserOwnsGamePassAsync() return false end
	local passes = Passes.new({ market = market, studio = false })
	local econ = Economy.new({ store = st, mint = Mint.new(nil, nil, true), rand = function() return 0.3 end,
		time = function() return clock end, paidAllowed = function() return true end, vip = function() return false end })
	local shop = Shop.new({ economy = econ, passes = passes, time = function() return clock end, restricted = function() return false end })
	return { econ = econ, shop = shop }
end
local n = 4000
for _, t in Products.CLOTHING do n += 1; t.id = n end
for _, t in Products.PACKS do n += 1; t.id = n end
local function inv(w) return w.econ:inventory(1) end
local function owns(w, id) return Inventory.owns(inv(w), id) end
local function packOf(view, id) for _, p in view.clothing do if p.id == id then return p end end end
local function pieceOf(id) for _, it in Clothing.items do if it.id == id then return it end end end
local function grant(w, id) assert(w.econ:grant(1, id, true, "shop"), "could not set up " .. id) end

-- 1. The catalogue: every piece sold at its tier, every pack cheaper than its pieces, nothing random.
for _, it in Clothing.items do
	assert(Products.CLOTHING[it.priceTier] and Products.CLOTHING[it.priceTier].price == Clothing.priceTiers[it.priceTier],
		`{it.id}'s price is not its tier's`)
	for crateId in Loot.CRATES do
		for _, o in Loot.odds(crateId, 0) do assert(o.id ~= it.id, `{it.id} can come out of a crate`) end
	end
end
for _, p in Clothing.packs do
	assert(Products.PACKS[p.id] and Products.PACKS[p.id].price == p.suggestedPriceRobux, `{p.id} is not priced as designed`)
end
for d = 20500, 20530 do for _, f in Shop.featured(d) do assert(Cosmetics.get(f.id).type ~= "clothing", "clothing in the featured four") end end
local kind, what = Products.byProductId(Products.CLOTHING.standard.id)
local kind2, what2 = Products.byProductId(Products.PACKS.candy_club.id)
assert(kind == "clothing" and what == "standard" and kind2 == "pack" and what2 == "candy_club", "a clothing product is not recognised")

-- 2. The view: four packs of six, prices and totals, offered while nothing is owned.
do
	local w = world()
	local view = w.shop:view(1)
	assert(#view.clothing == #Clothing.packs, "the shop does not show every pack")
	for _, pack in view.clothing do
		local total = 0
		for _, p in pack.pieces do
			total += p.price
			assert(p.price == Products.CLOTHING[pieceOf(p.id).priceTier].price and not p.owned, `{p.id} is shown wrong`)
		end
		assert(#pack.pieces == 6 and pack.total == total and pack.missing == 6 and pack.missingTotal == total, `{pack.id}'s totals are wrong`)
		assert(pack.offer and pack.price < total, `{pack.id} is not offered below its pieces`)
	end
end

-- 3. A single piece: prompted at its tier, the remembered piece granted once, paid and owned.
do
	local w = world()
	local ok, ev = w.shop:request(1, { action = "buy", kind = "piece", id = "frost_snowline_beanie" })
	assert(ok and ev.prompt.kind == "product" and ev.prompt.id == Products.CLOTHING.standard.id, "a piece was not prompted at its tier")
	local ok2, res = w.shop:receipt(1, Products.CLOTHING.standard.id, "p1")
	assert(ok2 and res.kind == "item" and res.id == "frost_snowline_beanie" and owns(w, "frost_snowline_beanie"), "the chosen piece was not granted")
	local uid = next(inv(w).items)
	assert(inv(w).items[uid].p == true and inv(w).items[uid].src == "shop", "a bought piece is not marked paid")
	local count = 0
	for _ in inv(w).items do count += 1 end
	w.shop:receipt(1, Products.CLOTHING.standard.id, "p1")
	local again = 0
	for _ in inv(w).items do again += 1 end
	assert(again == count, "one purchase granted twice")
	local refused, why = w.shop:request(1, { action = "buy", kind = "piece", id = "frost_snowline_beanie" })
	assert(not refused and string.find(why, "already own", 1, true), "an owned piece could be bought again")
	assert(not w.shop:request(1, { action = "buy", kind = "piece", id = "not_a_piece" }), "a made-up piece was prompted")
end

-- 4. No remembered piece: a credit of that tier, claimed later without paying again.
do
	local w = world()
	local ok, res = w.shop:receipt(1, Products.CLOTHING.statement.id, "p2")
	assert(ok and res.kind == "credit" and res.tier == "statement" and inv(w).credits.statement == 1, "a purchase with no piece was lost")
	assert(w.shop:view(1).clothing[1].pieces[1].credit, "the credit is not shown on a statement piece")
	local ok2, ev = w.shop:request(1, { action = "buy", kind = "piece", id = "neon_circuit_bomber" })
	assert(ok2 and ev.purchased and ev.purchased.id == "neon_circuit_bomber" and owns(w, "neon_circuit_bomber") and inv(w).credits.statement == 0,
		"the credit was not claimed")
	local ok3, ev3 = w.shop:request(1, { action = "buy", kind = "piece", id = "frost_rimeguard_coat" })
	assert(ok3 and ev3.prompt, "a spent credit was claimed again")
	-- a credit of one tier does not pay for another
	w.shop:receipt(1, Products.CLOTHING.accent.id, "p3")
	local ok4, ev4 = w.shop:request(1, { action = "buy", kind = "piece", id = "frost_whiteout_halfcape" })
	assert(ok4 and ev4.prompt and inv(w).credits.accent == 1, "an accent credit paid for a statement piece")
	local credits = Inventory.sanitize(inv(w)).credits
	assert(credits.accent == 1, "clothing credits are lost on load")
end

-- 5. Packs: only what is missing, refused when owned, and only while cheaper than singles.
do
	local w = world()
	grant(w, "neon_pulse_gloves")                                      -- 3 R$ owned: 28 R$ left singly, pack 24
	local pack = packOf(w.shop:view(1), "neon_night")
	assert(pack.missing == 5 and pack.missingTotal == pack.total - 3 and pack.offer, "owning a piece did not lower what is left")
	local ok, ev = w.shop:request(1, { action = "buy", kind = "pack", id = "neon_night" })
	assert(ok and ev.prompt.id == Products.PACKS.neon_night.id, "the pack was not prompted")
	local ok2, res = w.shop:receipt(1, Products.PACKS.neon_night.id, "k1")
	assert(ok2 and res.kind == "pack" and #res.granted == 5 and #res.credited == 0, "the pack did not grant exactly what was missing")
	local copies = 0
	for _, item in inv(w).items do if item.i == "neon_pulse_gloves" then copies += 1 end end
	assert(copies == 1, "the pack granted a piece already owned")
	for _, it in Clothing.items do if it.pack == "neon_night" then assert(owns(w, it.id), `{it.id} missing after the pack`) end end
	local owned = packOf(w.shop:view(1), "neon_night")
	assert(owned.missing == 0 and not owned.offer, "a fully owned pack is offered")
	local refused, why = w.shop:request(1, { action = "buy", kind = "pack", id = "neon_night" })
	assert(not refused and string.find(why, "every piece", 1, true), "a fully owned pack could be bought")

	-- the 8 R$ piece owned: 23 R$ left singly, less than the 24 R$ pack, so the pack is not offered
	local w2 = world()
	grant(w2, "neon_circuit_bomber")
	local p2 = packOf(w2.shop:view(1), "neon_night")
	assert(p2.missingTotal < p2.price and not p2.offer, "a pack dearer than its missing pieces is offered")
	local r2, why2 = w2.shop:request(1, { action = "buy", kind = "pack", id = "neon_night" })
	assert(not r2 and string.find(why2, `{p2.missingTotal} R$`, 1, true), "a pack dearer than its missing pieces could be bought")
	assert(not w2.shop:request(1, { action = "buy", kind = "pack", id = "no_pack" }), "a made-up pack was prompted")
end

-- 6. A piece bought singly while the pack's prompt was open is not paid for twice.
do
	local w = world()
	assert(w.shop:request(1, { action = "buy", kind = "pack", id = "candy_club" }))
	assert(w.shop:request(1, { action = "buy", kind = "piece", id = "candy_sundae_beret" }))
	assert(w.shop:receipt(1, Products.CLOTHING.standard.id, "s1"))
	assert(owns(w, "candy_sundae_beret"), "the single was not granted")
	local ok, res = w.shop:receipt(1, Products.PACKS.candy_club.id, "k2")
	assert(ok and #res.granted == 5 and #res.credited == 1 and res.credited[1] == "candy_sundae_beret" and inv(w).credits.standard == 1,
		"a piece bought singly during the pack's prompt was paid for twice")
	-- with no remembered pack (a new server), the pack still grants what is missing, crediting nothing
	local w2 = world()
	grant(w2, "candy_taffy_trainers")
	local ok2, res2 = w2.shop:receipt(1, Products.PACKS.candy_club.id, "k3")
	assert(ok2 and #res2.granted == 5 and #res2.credited == 0, "a pack with no remembered prompt did not grant what was missing")
	assert(w2.shop:request(1, { action = "buy", kind = "piece", id = "void_null_visor" }))
	assert(w2.shop:request(1, { action = "buy", kind = "pack", id = "void_court" }))
	assert(w2.shop.packIntents[1] and w2.shop.pieceIntents[1], "a prompt's choice was not remembered")
	w2.shop:forget(1)
	assert(w2.shop.packIntents[1] == nil and w2.shop.pieceIntents[1] == nil, "a player's choices were kept after they left")
end

-- 7. Not created in the Creator Dashboard: shown, never prompted.
do
	for _, t in Products.CLOTHING do t.id = 0 end
	for _, t in Products.PACKS do t.id = 0 end
	local w = world()
	local a, why = w.shop:request(1, { action = "buy", kind = "piece", id = "void_null_visor" })
	local b, why2 = w.shop:request(1, { action = "buy", kind = "pack", id = "void_court" })
	assert(not a and not b and string.find(why, "not on sale", 1, true) and string.find(why2, "not on sale", 1, true), "clothing with no product was prompted")
	assert(#w.shop:view(1).clothing == #Clothing.packs, "clothing not yet on sale is hidden")
end

print("PASS clothing shop: every piece at its tier and never random; packs priced as designed, granting only what is missing, refused when owned and when singles are cheaper; receipts once; credits for no remembered piece and for a piece bought during a pack's prompt, kept on load and only for their tier; nothing prompted before its product exists")
