--!nocheck
-- The Locker on screen (phase 4 of docs/briefs/crates-and-monetisation-plan.md; Roblox only): its
-- cards, crates, Workshop, crate opening and Odds & Details, from what the server sends, and every
-- button's request. Instances are stubs; every behaviour is the module's.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rbx = require("@lune/roblox")
local Loader = require("./loader")
local Loot, Cosmetics = Loader.load("Loot"), Loader.load("Cosmetics")

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
local Locker = luau.load(fs.readFile("src/client/LockerScreen.luau"), { debugName = "LockerScreen", environment = {
	game = { GetService = function(_, name) if name == "ReplicatedStorage" then return { Shared = shared } end error(name) end },
	script = { Parent = codes },
	require = function(name)
		if type(name) == "string" and fs.isFile("src/client/" .. name .. ".luau") then return Loader.loadFrom("src/client/", name) end
		return Loader.load(name)
	end,
	Instance = { new = instance }, Color3 = Rbx.Color3, Vector2 = Rbx.Vector2, UDim = Rbx.UDim, UDim2 = Rbx.UDim2,
	Enum = setmetatable({}, { __index = function() return codes end }),
}, injectGlobals = true })()

-- 1. The words.
assert(Locker.number(1240) == "1,240" and Locker.number(7) == "7" and Locker.number(1234567) == "1,234,567", "numbers are not grouped")
assert(Locker.existence(1) == "the only one" and Locker.existence(1240) == "1,240 exist" and Locker.existence(0) == "", "copies in existence read wrong")
assert(Locker.serialText({ serial = 57, copies = 1 }) == "#57" and Locker.serialText({ serial = 57, copies = 3 }) == "#57  x3"
	and Locker.serialText({ serial = nil, copies = 1 }) == "", "serials read wrong")

-- 2. Cards: what the server says you own, rarest first, your lowest serial shown, the highest
-- salvaged first, worn marked, Studio's loans told apart, filters.
local lockerView = { owned = { "sword_frostbite", "hit_sakura", "ko_dragonsbreath", "trail_ember" },
	wearing = { skins = { Sword = "sword_frostbite" }, hit = "hit_sakura" } }
local economyView = { sparks = 300, crates = { scrap = 2, forge = 1 }, keys = { forge = 0 }, meter = 3,
	guarantees = { scrap = 25, forge = 1 },
	items = { { uid = "u1", id = "sword_frostbite", serial = 91, copies = 40 }, { uid = "u2", id = "sword_frostbite", serial = 12, copies = 40 },
		{ uid = "u3", id = "hit_sakura", serial = 5, copies = 9 }, { uid = "u4", id = "trail_ember", serial = 1, copies = 1 } } }
do
	local cards = Locker.cards(lockerView, economyView, "all")
	assert(#cards == 4, `{#cards} cards for four owned items`)
	assert(cards[1].id == "ko_dragonsbreath", "the rarest is not first")
	local sword
	for _, c in cards do if c.id == "sword_frostbite" then sword = c end end
	assert(sword.copies == 2 and sword.serial == 12 and sword.uids[1] == "u1" and sword.worn and sword.exist == 40, "a card's copies, serial, salvage order or worn mark is wrong")
	assert(cards[1].copies == 0, "an item owned only on loan (Studio) shows copies")
	assert(#Locker.cards(lockerView, economyView, "weapon_skin") == 1 and #Locker.cards(lockerView, economyView, "other") == 0, "filters do not filter")
	local crates = Locker.crates(economyView)
	assert(crates[1].id == "scrap" and crates[1].canOpen and crates[2].id == "forge" and not crates[2].canOpen, "a crate's OPEN is wrong (Forge needs a key)")
	assert(string.find(crates[2].guarantee, "Next opening", 1, true) and crates[2].pity == Loot.CRATES.forge.guarantee.at - 1, "the guarantee countdown is wrong")
	local craft = Locker.craftable(economyView, "all")
	local affordable, pricey = 0, 0
	for _, m in craft do
		assert(m.cost == Loot.craftCost(m.id), `{m.id} is priced wrong`)
		if m.affordable then affordable += 1; assert(m.cost <= 300, "an unaffordable item is offered") else pricey += 1 end
	end
	assert(affordable > 0 and pricey > 0, "the Workshop does not tell affordable from not")
end

-- 3. Odds & Details: every item once with Loot's own odds, headed by rarity shares summing to 100;
-- the guaranteed opening leaves out what it rules out.
do
	for _, id in { "scrap", "forge" } do
		for _, g in { false, true } do
			local rows = Locker.oddsRows(id, 0, g)
			local list = Loot.odds(id, if g then Loot.CRATES[id].guarantee.at - 1 else 0)
			local items, tiers = 0, 0
			for _, r in rows do
				if r.kind == "item" then items += 1 else tiers += 1 end
			end
			assert(items == #list, `{id}: {items} odds lines for {#list} outcomes`)
			for i, o in list do
				local found = false
				for _, r in rows do if r.id == o.id then found = r.value == Loot.format(o.percent) end end
				assert(found, `{id}: {o.id} is not listed at its odds`)
			end
			if g then
				for _, r in rows do
					assert(Loot.RARITY[r.rarity].rank >= Loot.RARITY[Loot.CRATES[id].guarantee.min].rank, `{id}: the guaranteed opening lists a {r.rarity}`)
				end
			end
		end
	end
	local reel = Locker.reel("scrap", "sword_starforged", math.random)
	assert(reel[Locker.REEL.win] == "sword_starforged" and #reel == Locker.REEL.tiles, "the reel does not stop on the result")
	local pool = {}
	for _, o in Loot.odds("scrap", 0) do pool[o.id] = true end
	for i, id in reel do if i ~= Locker.REEL.win then assert(pool[id], `the reel shows {id}, which this crate never gives`) end end
end

-- 4. The screen.
local t = 100
local sentLocker, sentEconomy, drawn = {}, {}, 0
local gui = instance("PlayerGui")
local s = Locker.new(gui, {
	sendLocker = function(m) table.insert(sentLocker, m) end,
	sendEconomy = function(m) table.insert(sentEconomy, m) end,
	drawArt = function() drawn += 1 end,
	tween = function(obj, _seconds, props, done) for k, v in props do obj[k] = v end; done() end,
	now = function() return t end, rand = function() return 0.5 end,
})
local root = find(gui, "BlockfallLocker")
assert(root and not s:isOpen(), "the Locker is open before it is asked for")
s:open()
assert(s:isOpen(), "the Locker did not open")
s:setLocker(lockerView)
s:setEconomy(economyView)
local grid = find(find(root, "LockerTab"), "Grid")
local first = find(grid, "Card1")
assert(first and find(first, "Name").Text == "Dragon's Breath" and drawn > 0, "the first card is not the rarest, or nothing was drawn")
assert(string.find(find(root, "Balance").Text, "300 Sparks", 1, true), "the balance is not shown")
-- (the arcade theme shows it as currency pills, the gem and the key)
assert(find(find(root, "Currency_gem"), "Value").Text == "300" and find(find(root, "Currency_key"), "Value").Text == tostring(economyView.keys.forge),
	"the currency pills do not show the balance")
-- wear / take off
local function cardFor(name)
	for _, c in grid:GetChildren() do if find(c, "Name") and find(c, "Name").Text == name and c.Visible then return c end end
end
find(cardFor("Dragon's Breath"), "Primary").Activated:Fire()
assert(sentLocker[1].action == "equip" and sentLocker[1].id == "ko_dragonsbreath", "WEAR did not ask to wear it")
local sword = cardFor("Frostbite")
assert(find(sword, "Primary").Text == "TAKE OFF", "a worn item does not offer TAKE OFF")
find(sword, "Primary").Activated:Fire()
assert(sentLocker[2].action == "remove" and sentLocker[2].weapon == "Sword", "TAKE OFF did not ask to take the skin off its weapon")
find(cardFor("Sakura"), "Primary").Activated:Fire()
assert(sentLocker[3].action == "remove" and sentLocker[3].slot == "hit", "TAKE OFF did not name the hit slot")
-- salvage: twice, within the window
find(sword, "Secondary").Activated:Fire()
assert(#sentEconomy == 0 and string.find(find(root, "Message").Text, "again", 1, true), "one press salvaged")
t += 1
find(sword, "Secondary").Activated:Fire()
assert(#sentEconomy == 1 and sentEconomy[1].action == "salvage" and sentEconomy[1].uid == "u1", "the second press did not salvage the highest serial")
find(sword, "Secondary").Activated:Fire()
t += 5
find(sword, "Secondary").Activated:Fire()
assert(#sentEconomy == 1, "a press long after the first salvaged")
-- crates
find(root, "Tab_crates").Activated:Fire()
assert(find(root, "CratesTab").Visible and not find(root, "LockerTab").Visible, "the CRATES tab did not show")
assert(string.find(find(root, "Meter").Text, "3 games", 1, true), "the drop meter is not shown")
-- (a light theme: each crate card the tab's height, its buttons at its foot, its art on a mount)
for _, id in { "scrap", "forge" } do
	local card = find(root, "Crate_" .. id)
	assert(card.Size.Y.Scale == 1 and find(card, "Open").Position.Y.Scale == 1, `the {id} crate card does not fill the tab`)
	assert(find(find(card, "Thumb"), "Mount"), `the {id} crate's art has no mount`)
end
local forgeCard = find(root, "Crate_forge")
find(forgeCard, "Open").Activated:Fire()
assert(#sentEconomy == 1 and string.find(find(root, "Message").Text, "Forge Key", 1, true), "a keyless Forge Crate was opened")
find(find(root, "Crate_scrap"), "Open").Activated:Fire()
assert(sentEconomy[2].pity == Loot.CRATES.scrap.guarantee.at - economyView.guarantees.scrap, "open request must bind the disclosed guarantee counter")
assert(sentEconomy[2].action == "open" and sentEconomy[2].crate == "scrap" and find(root, "Opening").Visible, "OPEN did not ask, or the opening did not show")
find(find(root, "Crate_scrap"), "Open").Activated:Fire()
assert(#sentEconomy == 2, "a second OPEN went out while one was pending")
local view = table.clone(economyView)
view.event = { done = "open", result = { id = "sword_starforged", rarity = "Legendary", uid = "u9", serial = 57, copies = 1240 } }
s:setEconomy(view)
local opening = find(root, "Opening")
assert(find(opening, "Result").Text == "Legendary: Starforged" and find(opening, "Collect").Visible, "the opening did not land on the result")
assert(find(opening, "Title").Text == "Scrap Crate opened", "the opening still says it is opening")
assert(string.find(find(opening, "Detail").Text, "#57", 1, true) and string.find(find(opening, "Detail").Text, "1,240 exist", 1, true), "the result lacks its serial or copies")
local winner = find(find(opening, "Strip"), "Tile" .. Locker.REEL.win)
assert(winner, "the winning tile was not built")
find(opening, "Collect").Activated:Fire()
assert(not opening.Visible, "COLLECT did not close the opening")
-- a refused opening closes and says why
find(find(root, "Crate_scrap"), "Open").Activated:Fire()
local refused = table.clone(economyView)
refused.event = { error = "the vault is busy: try again in a moment" }
s:setEconomy(refused)
assert(not opening.Visible and string.find(find(root, "Message").Text, "vault is busy", 1, true), "a refused opening stayed open or said nothing")
-- odds
find(forgeCard, "Odds").Activated:Fire()
local odds = find(root, "OddsPanel")
local rows = Locker.oddsRows("forge", Loot.CRATES.forge.guarantee.at - 1, false)
assert(odds.Visible and find(find(odds, "List"), "Row1").Visible and find(find(odds, "List"), "Row1"):GetChildren()[1].Text == rows[1].text, "Odds & Details did not show the crate's odds")
find(odds, "Guaranteed").Activated:Fire()
local g = Locker.oddsRows("forge", 0, true)
assert(find(find(odds, "List"), "Row1"):GetChildren()[1].Text == g[1].text, "the guaranteed opening's odds did not show")
find(odds, "Back").Activated:Fire()
assert(not odds.Visible, "BACK did not close the odds")
-- the Workshop
find(root, "Tab_workshop").Activated:Fire()
local wgrid = find(find(root, "WorkshopTab"), "Grid")
local dear, cheap
for _, c in wgrid:GetChildren() do
	local n = find(c, "Name")
	if n and c.Visible then
		local it
		for _, x in Cosmetics.LIST do if x.name == n.Text then it = x end end
		if it and Loot.craftCost(it.id) > 300 then dear = dear or c elseif it then cheap = cheap or c end
	end
end
find(dear, "Primary").Activated:Fire()
assert(#sentEconomy == 3 and string.find(find(root, "Message").Text, "costs", 1, true), "an unaffordable craft went out")
find(cheap, "Primary").Activated:Fire()
assert(#sentEconomy == 3, "one CRAFT press crafted")
t += 1
find(cheap, "Primary").Activated:Fire()
assert(#sentEconomy == 4 and sentEconomy[4].action == "craft", "two CRAFT presses did not craft")
s:close()
assert(not s:isOpen(), "the Locker did not close")
-- no card's words lie under its buttons, in the Locker or the Workshop (CRAFT once covered the price)
for _, tab in { "LockerTab", "WorkshopTab" } do
	local g = find(find(root, tab), "Grid")
	local layout
	for _, ch in g:GetChildren() do if ch.ClassName == "UIGridLayout" then layout = ch end end
	local H = layout.CellSize.Y.Offset
	local function span(o) local y = o.Position.Y.Scale * H + o.Position.Y.Offset return y, y + o.Size.Y.Offset end
	local checked = 0
	for _, cardFrame in g:GetChildren() do
		if cardFrame.Visible and string.sub(cardFrame.Name or "", 1, 4) == "Card" then
			for _, word in { "Name", "Meta", "Extra" } do
				local w = find(cardFrame, word)
				if w and w.Visible ~= false and w.Text ~= "" then
					for _, btn in { "Primary", "Secondary" } do
						local b = find(cardFrame, btn)
						if b and b.Visible ~= false then
							local a1, a2 = span(w)
							local b1, b2 = span(b)
							assert(a2 <= b1 or b2 <= a1, `{tab}: a card's {word} ("{w.Text}") lies under its {btn}`)
							checked += 1
						end
					end
				end
			end
		end
	end
	assert(checked > 0, `{tab}: no cards were checked for overlap`)
end
-- buttons side by side keep 8 px between their outer strokes (3 px each, drawn outside the box): WEAR
-- and the salvage button, SAVE and the outfit slots, the filter chips. Measured at two widths, so a
-- gap that only holds at one card width fails too.
local function gapOK(a: any, b: any, W: number): number
	local function x(o) return o.Position.X.Scale * W + o.Position.X.Offset end
	local function w(o) return o.Size.X.Scale * W + o.Size.X.Offset end
	local l, r = a, b
	if x(a) > x(b) then l, r = b, a end
	return x(r) - (x(l) + w(l)) - 2 * 3
end
local pairsChecked = 0
local function row(parent: any, names: { string }, label: string)
	local shown = {}
	for _, n in names do local b = find(parent, n); if b and b.Visible ~= false then table.insert(shown, b) end end
	table.sort(shown, function(a, b) return a.Position.X.Offset < b.Position.X.Offset end)
	for k = 2, #shown do
		for _, W in { 260, 400 } do
			local g = gapOK(shown[k - 1], shown[k], W)
			assert(g >= 8, `{label}: {shown[k - 1].Name} and {shown[k].Name} are {g} px apart between strokes, under 8`)
		end
		pairsChecked += 1
	end
end
for _, cardFrame in find(find(root, "LockerTab"), "Grid"):GetChildren() do
	if cardFrame.Visible and string.sub(cardFrame.Name or "", 1, 4) == "Card" then row(cardFrame, { "Primary", "Secondary" }, "a card") end
end
row(find(root, "Outfits"), { "SaveOutfit", "Outfit1", "Outfit2", "Outfit3", "Outfit4", "Outfit5" }, "the outfit row")
local chips = {}
for _, f in Locker.FILTERS do table.insert(chips, "Filter_" .. f[1]) end
row(find(root, "LockerTab"), chips, "the filter row")
assert(pairsChecked >= 8, `only {pairsChecked} button pairs were checked for their gap`)
print("PASS locker ui: cards rarest first with your lowest serial, copies and copies in existence; WEAR, TAKE OFF (skin by weapon, effects by slot), SALVAGE twice; crates with their keys and guarantee countdown, OPEN once, the reel landing on the server's roll with its serial, refusals explained; Odds & Details from Loot, guaranteed opening too; the Workshop prices and crafts on a second press")
