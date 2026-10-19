--!nocheck
-- The Shop on screen (phase 5 of docs/briefs/crates-and-monetisation-plan.md; the contract in
-- docs/briefs/gpt-shop-screen.md; Roblox only): featured items, Forge Keys with their odds before
-- purchase, passes, restricted players, prompts handed to Roblox, one request at a time. Instances
-- are stubs; every behaviour is the module's.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rbx = require("@lune/roblox")
local Loader = require("./loader")
local Cosmetics = Loader.load("Cosmetics")

local function signal(): any
	local callbacks = {}
	return { Connect = function(_, fn) table.insert(callbacks, fn) end,
		Fire = function(_, ...) for _, fn in callbacks do fn(...) end end }
end
local function instance(class: string): any
	local props: any = { ClassName = class, Visible = true, Enabled = true, Activated = signal(), Text = "", _children = {} }
	local self: any
	props.GetChildren = function() return table.clone(props._children) end
	self = setmetatable({}, { __index = props, __newindex = function(_, key, value)
		props[key] = value
		if key == "Parent" and value then table.insert(value._children, self) end
	end })
	return self
end
local function find(root: any, name: string): any
	for _, child in root:GetChildren() do
		if child.Name == name then return child end
		local deep = find(child, name)
		if deep then return deep end
	end
	return nil
end
local codes = setmetatable({}, { __index = function(_, name) return name end })
local shared = setmetatable({ Data = setmetatable({}, { __index = function(_, k) return "Data/" .. k end }) }, { __index = function(_, name) return name end })
Loader.gui = { Instance = { new = instance }, UDim = Rbx.UDim, UDim2 = Rbx.UDim2, Enum = setmetatable({}, { __index = function() return codes end }) }
local env
env = {
	game = { GetService = function(_, name) if name == "ReplicatedStorage" then return { Shared = shared } end error(name) end },
	script = { Parent = codes },
	require = function(name)
		if type(name) == "string" and fs.isFile("src/client/" .. name .. ".luau") then return Loader.loadFrom("src/client/", name) end
		return Loader.load(name)
	end,
	Instance = { new = instance }, Color3 = Rbx.Color3, Vector2 = Rbx.Vector2, UDim = Rbx.UDim, UDim2 = Rbx.UDim2,
	Enum = setmetatable({}, { __index = function() return codes end }),
}
local Shop = luau.load(fs.readFile("src/client/ShopScreen.luau"), { debugName = "ShopScreen", environment = env, injectGlobals = true })()
local Locker = env.require("LockerScreen")

-- n cells and their 10 px gaps fit a row's width, at every column count used (five used to wrap)
for _, cols in { 3, 4, 5 } do
	local cell = Shop.cell(cols, 100)
	for _, w in { 600, 896, 1200 } do
		assert(cols * (w * cell.X.Scale + cell.X.Offset) + (cols - 1) * 10 <= w, `{cols} cells do not fit a {w} px row`)
	end
end
assert(Shop.wait(26000) == "7h 13m" and Shop.wait(59) == "0m" and Shop.wait(600) == "10m", "the countdown reads wrong")
assert(Shop.each({ price = 110, count = 5 }) == "22 R$ each" and Shop.each({ price = 540, count = 30 }) == "18 R$ each" and Shop.each({ price = 50, count = 3 }) == "17 R$ each", "the per-key price is wrong")

local function view(restricted)
	return { shop = {
		restricted = restricted, resetsIn = 26000,
		featured = { { id = "hammer_cobblestone", price = 29, owned = false }, { id = "sword_frostbite", price = 49, owned = true },
			{ id = "daggers_venomfang", price = 99, owned = false, credit = true }, { id = "sword_starforged", price = 199, owned = false } },
		keys = if restricted == "leaky" then { { bundle = "keys1", count = 1, price = 25 } } elseif restricted then {} else { { bundle = "keys1", count = 1, price = 25 }, { bundle = "keys5", count = 5, price = 110 },
			{ bundle = "keys12", count = 12, price = 240 }, { bundle = "keys30", count = 30, price = 540 } },
		passes = { { id = "vip", name = "VIP", price = 199, owned = false, available = true, perks = { "Gold name", "+10% Sparks" } },
			{ id = "season", name = "Season Pass", price = 149, owned = false, available = false, perks = { "The premium track" } },
			{ id = "wardrobe", name = "Wardrobe", price = 79, owned = true, available = true, perks = { "16 characters" } } },
		clothing = {
			{ id = "candy_club", name = "Candy Club", price = 22, total = 31, missing = 5, missingTotal = 28, offer = true, pieces = {
				{ id = "candy_sugarstripe_tee", price = 8, owned = true }, { id = "candy_bonbon_shorts", price = 5, owned = false },
				{ id = "candy_sundae_beret", price = 5, owned = false, credit = true }, { id = "candy_softserve_swirl", price = 5, owned = false },
				{ id = "candy_sugarstar_specs", price = 3, owned = false }, { id = "candy_taffy_trainers", price = 5, owned = false } } },
			{ id = "neon_night", name = "Neon Night", price = 24, total = 31, missing = 1, missingTotal = 8, offer = false, pieces = {
				{ id = "neon_circuit_bomber", price = 8, owned = false } } },
			{ id = "frostforged", name = "Frostforged", price = 26, total = 34, missing = 0, missingTotal = 0, offer = false, pieces = {
				{ id = "frost_snowline_beanie", price = 5, owned = true } } },
		},
	} }
end

local sent, prompted, drawn = {}, {}, 0
local gui = instance("PlayerGui")
local s = Shop.new(gui, { send = function(m) table.insert(sent, m) end, prompt = function(k, id) table.insert(prompted, { k, id }) end,
	drawArt = function() drawn += 1 end })
local root = find(gui, "BlockfallShop")
assert(root and not s:isOpen(), "the Shop is open before it is asked for")
s:open()
s:setEconomy(view(false))
local featured, keys, passes = find(root, "Featured"), find(root, "Keys"), find(root, "Passes")
local function cardNamed(row, text)
	for _, c in row:GetChildren() do if find(c, "Name") and find(c, "Name").Text == text and c.Visible then return c end end
end
-- 1. Featured: names, plain Robux prices, owned, a paid-for credit to claim, the countdown.
assert(string.find(find(root, "FeaturedHead").Text, "7h 13m", 1, true), "the featured countdown is missing")
assert(find(cardNamed(featured, "Cobblestone"), "Buy").Text == "29 R$" and drawn >= 4, "a featured price is not plain Robux, or nothing was drawn")
assert(find(cardNamed(featured, "Frostbite"), "Buy").Text == "OWNED", "an owned featured item is buyable")
assert(find(cardNamed(featured, "Venomfang"), "Buy").Text == "CLAIM" and find(cardNamed(featured, "Venomfang"), "Meta").Text == "Paid for · tap to claim",
	"a paid-for credit is not offered as a claim, said to be paid for")
find(cardNamed(featured, "Frostbite"), "Buy").Activated:Fire()
assert(#sent == 0, "an owned item was requested")
find(cardNamed(featured, "Cobblestone"), "Buy").Activated:Fire()
assert(sent[1].action == "buy" and sent[1].kind == "item" and sent[1].id == "hammer_cobblestone", "BUY did not request the item")
-- the day's priciest leads, wide, on the hero card; its pill buys like the rest
local hero = find(root, "Hero")
assert(hero and find(hero, "Name").Text == "Starforged" and find(hero, "Buy").Text == "199 R$" and not cardNamed(featured, "Starforged"),
	"the priciest featured item does not lead on the hero card")
find(hero, "Buy").Activated:Fire()
assert(#sent == 1, "a second request went out while one was pending")
-- the whole card buys, as the reference shop's cards do (not only its pill)
s:cancelled()
find(cardNamed(featured, "Cobblestone"), "Hit").Activated:Fire()
assert(#sent == 2 and sent[2].id == "hammer_cobblestone", "tapping a card did not buy it")
s:cancelled()
find(hero, "Hit").Activated:Fire()
assert(#sent == 3 and sent[3].id == "sword_starforged", "tapping the hero card did not buy it")
local v = view(false); v.event = { prompt = { kind = "product", id = 2001 } }
s:setEconomy(v)
assert(prompted[1] and prompted[1][1] == "product" and prompted[1][2] == 2001, "the server's prompt was not handed to Roblox")
-- 2. Keys: four bundles with their per-key price; odds before purchase, from Loot's table.
assert(find(cardNamed(keys, "5 Forge Keys"), "Buy").Text == "110 R$" and find(cardNamed(keys, "5 Forge Keys"), "Meta").Text == "22 R$ each", "a key bundle's price is wrong")
assert(find(root, "Odds").Visible and find(root, "Odds").Text == "ODDS & DETAILS", "keys have no worded odds button")
find(cardNamed(keys, "12 Forge Keys"), "Buy").Activated:Fire()
assert(sent[#sent].kind == "keys" and sent[#sent].bundle == "keys12", "a key bundle was not requested")
find(root, "Odds").Activated:Fire()
local odds = find(root, "OddsPanel")
local rows = Locker.oddsRows("forge", 0, false)
local items = 0
for i, r in rows do
	local row = find(find(odds, "List"), "Row" .. i)
	assert(row and row.Visible and find(row, "Label").Text == r.text and find(row, "Value").Text == r.value, `odds row {i} is not Loot's`)
	if r.kind == "item" then items += 1 end
end
assert(items > 20 and odds.Visible, "the odds do not list every outcome")
find(odds, "Guaranteed").Activated:Fire()
assert(find(find(find(odds, "List"), "Row1"), "Label").Text == Locker.oddsRows("forge", 0, true)[1].text, "the guaranteed opening's odds are missing")
find(odds, "Back").Activated:Fire()
assert(not odds.Visible, "BACK did not close the odds")
-- 3. Passes: perks, price, owned, coming soon.
local err = view(false); err.event = { error = "VIP is not on sale yet" }
s:setEconomy(err)
assert(string.find(find(root, "Message").Text, "not on sale", 1, true), "a refusal was not shown")
assert(find(cardNamed(passes, "VIP"), "Buy").Text == "199 R$" and string.find(find(cardNamed(passes, "VIP"), "Meta").Text, "Gold name", 1, true), "VIP's price or perks are missing")
assert(find(cardNamed(passes, "Season Pass"), "Buy").Text == "COMING SOON", "a pass not built is offered")
assert(find(cardNamed(passes, "Wardrobe"), "Buy").Text == "OWNED", "an owned pass is offered")
local before = #sent
find(cardNamed(passes, "Season Pass"), "Buy").Activated:Fire()
find(cardNamed(passes, "Wardrobe"), "Buy").Activated:Fire()
assert(#sent == before, "a pass not on sale, or owned, was requested")
find(cardNamed(passes, "VIP"), "Buy").Activated:Fire()
assert(sent[#sent].kind == "pass" and sent[#sent].id == "vip", "VIP was not requested")
s:cancelled()
local done = view(false); done.event = { purchased = { kind = "keys", count = 5 } }
s:setEconomy(done)
assert(string.find(find(root, "Message").Text, "5 Forge Keys added", 1, true), "a purchase was not acknowledged")
-- 3b. Clothing: a pack and its pieces; the pack offered only while cheaper than what is missing.
assert(Shop.packLine({ pieces = { 1, 2, 3, 4, 5, 6 }, missing = 6, total = 31, missingTotal = 31 }) == "6 pieces · 31 R$ one by one"
	and Shop.packLine({ pieces = { 1, 2, 3, 4, 5, 6 }, missing = 5, total = 31, missingTotal = 28 }) == "you own 1 · the other 5: 28 R$ one by one"
	and Shop.packLine({ pieces = { 1, 2 }, missing = 0, total = 8, missingTotal = 0 }) == "2 pieces · you own them all", "a pack's line reads wrong")
s:cancelled()
local candy, neon, frost = find(root, "Pack1"), find(root, "Pack2"), find(root, "Pack3")
assert(find(root, "PackHead1").Text == "CANDY CLUB" and find(root, "PackHead2").Text == "NEON NIGHT", "the packs are not headed by name")
assert(find(cardNamed(candy, "Whole pack"), "Buy").Text == "22 R$" and find(cardNamed(candy, "Whole pack"), "Meta").Text == "you own 1 · the other 5: 28 R$ one by one",
	"the pack's price or line is wrong")
assert(find(cardNamed(candy, "Sugarstripe Tee"), "Buy").Text == "OWNED" and find(cardNamed(candy, "Sundae Beret"), "Buy").Text == "CLAIM"
	and find(cardNamed(candy, "Bonbon Shorts"), "Buy").Text == "5 R$" and find(cardNamed(candy, "Sugarstar Specs"), "Buy").Text == "3 R$",
	"a piece's button is wrong")
assert(find(cardNamed(neon, "Whole pack"), "Buy").Text == "BUY SINGLY" and find(cardNamed(frost, "Whole pack"), "Buy").Text == "OWNED",
	"a pack dearer than its missing pieces, or fully owned, is offered")
local was = #sent
find(cardNamed(neon, "Whole pack"), "Buy").Activated:Fire()
find(cardNamed(frost, "Whole pack"), "Buy").Activated:Fire()
find(cardNamed(candy, "Sugarstripe Tee"), "Buy").Activated:Fire()
assert(#sent == was, "a pack not offered, or an owned piece, was requested")
find(cardNamed(candy, "Bonbon Shorts"), "Buy").Activated:Fire()
assert(sent[#sent].kind == "piece" and sent[#sent].id == "candy_bonbon_shorts", "a piece was not requested")
s:cancelled()
find(cardNamed(candy, "Whole pack"), "Buy").Activated:Fire()
assert(sent[#sent].kind == "pack" and sent[#sent].id == "candy_club", "the pack was not requested")
s:cancelled()
local packDone = view(false); packDone.event = { purchased = { kind = "pack", id = "candy_club", granted = { "a", "b", "c", "d", "e" }, credited = {} } }
s:setEconomy(packDone)
assert(string.find(find(root, "Message").Text, "5 pieces are in your Locker", 1, true), "a pack purchase was not acknowledged")
local credit = view(false); credit.event = { purchased = { kind = "credit", tier = "standard" } }
s:setEconomy(credit)
assert(string.find(find(root, "Message").Text, "standard clothing piece", 1, true), "a clothing credit was not explained")

-- 4. A restricted player: no keys, no odds button, told why.
s:setEconomy(view(true))
local any = false
for _, c in keys:GetChildren() do if c.Visible and find(c, "Name") then any = true end end
assert(not any and not keys.Visible and not find(root, "Odds").Visible, "a restricted player sees Forge Keys")
assert(string.find(find(root, "KeyNote").Text, "not available for your account", 1, true), "a restricted player is not told why")
s:setEconomy(view(false))
s:setEconomy(view("leaky"))
any = false
for _, c in keys:GetChildren() do if c.Visible and find(c, "Name") then any = true end end
assert(not any and not keys.Visible, "a restricted player sees Forge Keys the server should not have sent")
s:close()
assert(not s:isOpen(), "the Shop did not close")
print("PASS shop ui: featured items in plain Robux with their countdown, owned and paid-for credits shown; Forge Keys with per-key prices and a worded ODDS & DETAILS from Loot's own table, guaranteed opening too; passes with perks, coming soon and owned; clothing packs with their pieces, offered only while cheaper than what is missing; one request at a time, prompts handed to Roblox, refusals and purchases shown; restricted players see no keys and are told why")
