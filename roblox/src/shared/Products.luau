--!strict
-- Everything Blockfall sells for Robux (Roblox only; docs/briefs/crates-and-monetisation-plan.md,
-- "Prices: volume over margin"): Forge Key bundles, the featured shop's price tiers, single clothing
-- pieces and packs, and the game passes. Prices are always shown in Robux before a purchase.
--
-- ============================== SET THIS UP IN THE CREATOR DASHBOARD ==============================
-- Robux prices are not set here. Each Developer Product and Game Pass is created for this experience
-- (Creator Dashboard -> the experience -> Monetization), priced as below, and its id goes in `id`.
-- An id of 0 means "not created yet": the shop shows the price but says it is not on sale, and
-- nothing is sold. The price a player is charged is Roblox's, so keep the two in step.
-- ================================================================================================
local Products = {}

-- Forge Keys: cheaper per key the more you buy. Not sold to players Roblox restricts from paid
-- random items; the odds of what a key opens are shown before purchase.
Products.KEYS = {
	{ bundle = "keys1", count = 1, price = 25, id = 0 },
	{ bundle = "keys5", count = 5, price = 110, id = 0 },
	{ bundle = "keys12", count = 12, price = 240, id = 0 },
	{ bundle = "keys30", count = 30, price = 540, id = 0 },
}

-- The featured shop: four items a day, bought outright (never random), priced by rarity. One
-- Developer Product per price; the server remembers which item the player chose before prompting.
Products.FEATURED = {
	Uncommon = { price = 29, id = 0 },
	Rare = { price = 49, id = 0 },
	Epic = { price = 99, id = 0 },
	Legendary = { price = 199, id = 0 },
} :: { [string]: { price: number, id: number } }

-- Clothing (GPT's tiers): one piece at a time, or a pack. Sold once clothing can be worn (plan
-- phase 6, the k2 code); listed here so the prices live in one place.
Products.CLOTHING = {
	accent = { price = 3, id = 0 },
	standard = { price = 5, id = 0 },
	statement = { price = 8, id = 0 },
} :: { [string]: { price: number, id: number } }

-- Game passes. `available` is false for a pass whose perks are not built yet: the shop shows it
-- as coming soon and never prompts it.
Products.PASSES = {
	{ id = "vip", name = "VIP", price = 199, pass = 0, available = true, perks = {
		"Gold name and [VIP] chat tag", "+10% Sparks from drops", "A VIP cosmetic every season",
		"A gold sparkle when you respawn", "Double Sparks for your first win each day", "Five saved outfits", "Royal Welcome emote" } },
	{ id = "wardrobe", name = "Wardrobe", price = 79, pass = 0, available = true, perks = {
		"16 saved characters instead of 8" } },
	{ id = "studio", name = "Character Studio+", price = 149, pass = 0, available = false, perks = {
		"The full colour picker", "Saved palettes", "A second accessory layer" } },
	{ id = "season", name = "Season Pass", price = 149, pass = 0, available = false, perks = {
		"The premium season track", "Exclusive skins and a KO effect", "Forge Keys and Sparks" } },
	{ id = "emotes", name = "Emote Pack", price = 99, pass = 0, available = false, perks = { "Six emotes" } },
}

-- What a pass grants into the Locker the moment it is owned (kept forever, never tradeable).
Products.PASS_ITEMS = {
	vip = { "title_vip", "trail_vipgold", "spawn_vipsparkle", "emote_vip" },
} :: { [string]: { string } }

function Products.keyBundle(bundle: any): any
	for _, b in Products.KEYS do if b.bundle == bundle then return b end end
	return nil
end
function Products.pass(id: any): any
	for _, p in Products.PASSES do if p.id == id then return p end end
	return nil
end
-- What a Developer Product id is: ("keys", bundle) or ("featured", rarity), or nil.
function Products.byProductId(productId: number): (string?, any)
	if productId == 0 then return nil, nil end
	for _, b in Products.KEYS do if b.id == productId then return "keys", b end end
	for rarity, t in Products.FEATURED do if t.id == productId then return "featured", rarity end end
	return nil, nil
end

return Products
