--!nocheck
-- Earning things (phase 3 of docs/briefs/crates-and-monetisation-plan.md; Roblox only): the saved
-- inventory of instances, serials from the Mint, the drop meter, crates and keys, guarantees,
-- crafting, salvaging, and the line under the results. Direct properties, through the real server
-- modules with a fake record store and a fake DataStore.
local Loader = require("./loader")
local Cosmetics, Inventory, Loot = Loader.load("Cosmetics"), Loader.load("Inventory"), Loader.load("Loot")
local Mint = Loader.loadFrom("src/server/", "Mint")
local Economy = Loader.loadFrom("src/server/", "Economy")
local DropBanner = Loader.loadFrom("src/client/", "DropBanner")

local function rng(seed)
	local s = seed
	return function() s = (s * 16807) % 2147483647; return (s - 1) / 2147483646 end
end
local AvatarStore = Loader.loadFrom("src/server/", "AvatarStore")
local function records()
	return AvatarStore.new(nil, function() return 1 end, { sessionOnly = true })
end
-- a DataStore whose UpdateAsync is atomic, and which can be made to fail
local function datastore()
	local data = {}
	local ds = { data = data, fail = false, writes = 0 }
	function ds:UpdateAsync(key, fn)
		if self.fail then error("throttled") end
		self.writes += 1
		data[key] = fn(data[key])
		return data[key]
	end
	function ds:GetAsync(key)
		if self.fail then error("throttled") end
		return data[key]
	end
	return ds
end
local clock = 0
local function now() return clock end

-- 1. The inventory: instances cleaned against the catalogue, balances clamped, a version 1 record
-- migrated, the `owned` index never trusted from storage, the last worn copy coming off.
do
	local inv = Inventory.sanitize({
		items = { u1 = { i = "sword_frostbite", s = 7, p = true, t = 100, src = "crate" }, u2 = { i = "nope", s = 1 },
			[5] = { i = "hit_sakura" }, u9 = { i = "hit_sakura", s = -4, src = "hacked" }, longlonglonglonguid = { i = "ko_firework" } },
		owned = { ko_dragonsbreath = true },
		sparks = -50, crates = { scrap = 3.7, forge = "lots" }, keys = { forge = { earned = 2, paid = 1e12 } },
		pity = { scrap = 4 }, meter = 9, equipped = { skins = { Sword = "sword_frostbite" }, ko = "ko_dragonsbreath" },
	})
	assert(inv.items.u1 and inv.items.u1.p == true and inv.items.u1.s == 7, "a stored instance was lost")
	assert(not inv.items.u2 and not inv.items[5] and not inv.items.longlonglonglonguid, "a bad instance survived")
	assert(inv.items.u9 and inv.items.u9.s == 0 and inv.items.u9.src == "grant", "a bad serial or source survived")
	assert(not inv.owned.ko_dragonsbreath and inv.equipped.ko == nil, "the stored owned index was trusted")
	assert(inv.owned.sword_frostbite and inv.equipped.skins.Sword == "sword_frostbite", "an owned, worn skin came off")
	assert(inv.sparks == 0 and inv.crates.scrap == 3 and inv.crates.forge == 0 and inv.keys.forge.paid == Inventory.MAX_COUNT, "balances not clamped")
	assert(inv.pity.scrap == 4 and inv.pity.forge == 0 and inv.meter == nil, "counters not cleaned")
	assert(inv.seq == 10, `the next uid would collide (seq {inv.seq})`)
	local old = Inventory.sanitize({ owned = { sword_frostbite = true, nope = true }, equipped = { skins = { Sword = "sword_frostbite" } } })
	local n = 0
	for _, inst in old.items do n += 1; assert(inst.i == "sword_frostbite" and inst.s == 0 and inst.p == false and inst.src == "migrated", "a version 1 item migrated wrong") end
	assert(n == 1 and old.equipped.skins.Sword == "sword_frostbite", "a version 1 record did not migrate")
	local a = Inventory.add(inv, "sword_frostbite", 8, false, "drop", 5)
	assert(a and Inventory.copies(inv, "sword_frostbite") == 2, "a second copy was not added")
	Inventory.remove(inv, "u1")
	assert(inv.equipped.skins.Sword == "sword_frostbite", "removing one of two copies took the skin off")
	Inventory.remove(inv, a)
	assert(inv.equipped.skins.Sword == nil and not Inventory.owns(inv, "sword_frostbite"), "removing the last worn copy left it worn")
end

-- 2. The Mint: two servers on one store never hand out the same serial, reserve in blocks that
-- grow when an item goes fast, count copies across servers, and report a failed reservation.
do
	local ds = datastore()
	clock = 0
	local a, b = Mint.new(ds, now), Mint.new(ds, now)
	local seen = {}
	for i = 1, 300 do
		local m = if i % 3 == 0 then b else a
		local s = m:serial("sword_starforged")
		assert(s and not seen[s], `serial {s} handed out twice`)
		seen[s] = true
		clock += 0.5
	end
	assert(ds.writes < 40, `{ds.writes} DataStore writes for 300 serials: not reserving in blocks`)
	assert(a.blocks.sword_starforged.size > Mint.FIRST_BLOCK, "a fast item's block did not grow")
	-- a slow item (one copy every two minutes) never grows its block, and still writes once a block
	local slow = Mint.new(ds, now)
	local w0 = ds.writes
	for _ = 1, 50 do slow:serial("hammer_cobblestone"); clock += 120 end
	assert(ds.writes - w0 <= 50 / Mint.FIRST_BLOCK, `{ds.writes - w0} writes for 50 slow serials: not reserving in blocks`)
	a:destroy("sword_starforged"); a:destroy("sword_starforged")
	a:flush(); b:flush()
	b:refresh({ "sword_starforged" })
	assert(b:copies("sword_starforged") == 298, `copies in existence {b:copies("sword_starforged")}, want 298`)
	ds.fail = true
	local c = Mint.new(ds, now)
	assert(c:serial("hit_sakura") == nil, "a failed reservation handed out a serial")
	local offline = Mint.new(nil, now, true)
	assert(offline:serial("hit_sakura") == 1 and offline:serial("hit_sakura") == 2 and offline:copies("hit_sakura") == 2, "Studio's in-memory serials are off")
end

-- 3. Which matches count.
do
	local ok = { mode = "StockFFA", frames = 60 * 60 }
	assert(Economy.qualifies(ok, { damage = 10, taken = 0, fightFrames = 3600 }) and Economy.qualifies(ok, { damage = 0, taken = 4, fightFrames = 3600 }), "a real match did not count")
	assert(not Economy.qualifies(ok, { damage = 0, taken = 0, fightFrames = 3600 }), "a match without a hit counted")
	assert(not Economy.qualifies({ mode = "StockFFA", frames = 44 * 60 }, { damage = 10, fightFrames = 44 * 60 }), "a 44-second match counted")
	assert(not Economy.qualifies({ mode = "Training", frames = 99999 }, { damage = 10, fightFrames = 99999 }), "Training counted")
end

-- 4. The drop meter: a drop exactly when it runs out, every 2 to 5 counted matches, never from an
-- uncounted one; drops follow their table.
local real = { mode = "StockFFA", frames = 3600 }
local row = { damage = 20, taken = 10, fightFrames = 3600 }
do
	local t = 0
	local econ = Economy.new({ store = records(), mint = Mint.new(nil, now, true), rand = rng(3), time = function() return t end })
	local gap, gaps, kinds, drops = 0, {}, {}, 0
	for _ = 1, 3000 do
		t += 400                                  -- nine counted matches an hour: never capped
		local before = econ:inventory(1).meter
		local out = econ:matchFinished(1, real, row)
		gap += 1
		assert(out.counted, "a real match was not counted")
		if out.drop then
			assert(before == nil or before == 1, `a drop came with {before} matches still to go`)
			assert(gap >= 2 and gap <= 5 or (drops == 0 and gap <= 5), `a drop came after {gap} matches`)
			gaps[gap] = (gaps[gap] or 0) + 1
			kinds[out.drop.kind] = (kinds[out.drop.kind] or 0) + 1
			gap, drops = 0, drops + 1
		else
			assert(out.left >= 1, "the meter ran out without a drop")
		end
		local skip = econ:matchFinished(1, { mode = "Training", frames = 9999 }, row)
		assert(not skip.counted and not skip.drop and econ:inventory(1).meter == out.left, "an uncounted match moved the meter")
	end
	for g = 2, 5 do assert((gaps[g] or 0) > 100, `drops never came after {g} matches`) end
	assert(math.abs(kinds.crate / drops - 0.72) < 0.05 and math.abs((kinds.sparks or 0) / drops - 0.20) < 0.04, "drops do not follow their table")
	local inv = econ:inventory(1)
	assert(inv.crates.scrap > 0 and inv.crates.forge > 0 and inv.keys.forge.earned > 0 and inv.sparks > 0 and next(inv.items), "drops were not paid out")
	for _, inst in inv.items do assert(inst.src == "drop" and inst.p == false and inst.s > 0, "a dropped item is not an earned, serialled copy") end
end

-- 5. The hourly cap: twelve counted matches an hour, the thirteenth not, the next hour again.
do
	local t = 3600 * 100
	local econ = Economy.new({ store = records(), mint = Mint.new(nil, now, true), rand = rng(9), time = function() return t end })
	for i = 1, Economy.HOURLY_CAP do assert(econ:matchFinished(1, real, row).counted, `match {i} of the hour did not count`) end
	local over = econ:matchFinished(1, real, row)
	assert(not over.counted and over.capped, "a thirteenth match in an hour counted")
	t += 3600
	assert(econ:matchFinished(1, real, row).counted, "the next hour did not count")
end

-- 6. Opening crates: a Scrap Crate opens free; a Forge Crate takes a key, an earned one first; an
-- item from a paid key is paid; nothing is spent on a refusal; the guarantee is saved and fires.
do
	local econ = Economy.new({ store = records(), mint = Mint.new(nil, now, true), paidAllowed = function() return true end, rand = rng(21), time = function() return 7 end })
	local inv = econ:inventory(1)
	assert(not econ:open(1, "scrap") and not econ:open(1, "nope"), "a crate opened from nothing")
	inv.crates.scrap = 1
	local ok, res = econ:open(1, "scrap")
	assert(ok and inv.crates.scrap == 0 and inv.items[res.uid] and inv.items[res.uid].src == "crate" and res.serial >= 1, "a Scrap Crate did not open into a serialled copy")
	inv.crates.forge = 3
	assert(not econ:open(1, "forge") and inv.crates.forge == 3, "a Forge Crate opened without a key, or a refusal spent it")
	inv.keys.forge.earned, inv.keys.forge.paid = 1, 1
	local ok1, r1 = econ:open(1, "forge")
	assert(ok1 and not r1.paid and inv.keys.forge.earned == 0 and inv.keys.forge.paid == 1, "the paid key was spent before the earned one")
	local ok2, r2 = econ:open(1, "forge", inv.pity.forge)
	assert(ok2 and r2.paid and inv.items[r2.uid].p == true and inv.keys.forge.paid == 0, "an item from a paid key is not marked paid")
	local g = Loot.CRATES.forge.guarantee
	inv.crates.forge, inv.keys.forge.earned, inv.pity.forge = 1, 1, g.at - 1
	local ok3, r3 = econ:open(1, "forge")
	assert(ok3 and Loot.RARITY[r3.rarity].rank >= Loot.RARITY[g.min].rank and inv.pity.forge == 0, "the saved guarantee did not fire")
	local before = inv.pity.scrap
	inv.crates.scrap = 1
	local _, r4 = econ:open(1, "scrap")
	local min = Loot.RARITY[Loot.CRATES.scrap.guarantee.min].rank
	assert(inv.pity.scrap == (if Loot.RARITY[r4.rarity].rank >= min then 0 else before + 1), "the guarantee count was not saved")
end

-- 7. When the vault (the Mint's store) cannot be reached nothing is spent, and a dropped item
-- becomes a crate instead of vanishing.
do
	local ds = datastore()
	ds.fail = true
	local econ = Economy.new({ store = records(), mint = Mint.new(ds, now), rand = rng(5), time = function() return 7 end })
	local inv = econ:inventory(1)
	inv.crates.forge, inv.keys.forge.earned, inv.sparks = 1, 1, 99999
	local ok = econ:open(1, "forge")
	assert(not ok and inv.crates.forge == 1 and inv.keys.forge.earned == 1 and next(inv.items) == nil, "a failed opening spent the crate or key")
	assert(not econ:craft(1, "sword_rustwood") and inv.sparks == 99999, "a failed craft spent Sparks")
	local d = econ:_drop(1, { kind = "item", crate = "scrap" })
	assert(d.kind == "crate" and inv.crates.scrap == 1, "a dropped item was lost when the vault failed")
end

-- 8. Crafting and salvaging.
do
	local mint = Mint.new(nil, now, true)
	local econ = Economy.new({ store = records(), mint = mint, rand = rng(8), time = function() return 7 end })
	local inv = econ:inventory(1)
	local cost = Loot.craftCost("sword_starforged")
	inv.sparks = cost - 1
	assert(not econ:craft(1, "sword_starforged") and inv.sparks == cost - 1, "crafted without the Sparks")
	inv.sparks = cost + 5
	local ok, res = econ:craft(1, "sword_starforged")
	assert(ok and inv.sparks == 5 and inv.items[res.uid].src == "craft" and not inv.items[res.uid].p, "crafting did not cost its price or make an earned copy")
	assert(not econ:craft(1, "title_untouchable"), "a mastery title was crafted")
	inv.equipped.skins.Sword = "sword_starforged"
	local before = mint:copies("sword_starforged")
	local sok, sres = econ:salvage(1, res.uid)
	assert(sok and inv.sparks == 5 + Loot.dupe("Legendary") and sres.sparks == Loot.dupe("Legendary"), "salvaging did not pay its rarity's Sparks")
	assert(not inv.items[res.uid] and inv.equipped.skins.Sword == nil, "a salvaged last copy is still owned or worn")
	assert(mint:copies("sword_starforged") == before - 1, "a salvaged copy still exists")
	assert(not econ:salvage(1, res.uid), "a copy was salvaged twice")
end

-- 9. Serials stay unique per item when several players open crates on two servers at once, and
-- the view tells a player what they have.
do
	local ds = datastore()
	clock = 0
	local servers = {}
	for k = 1, 2 do
		servers[k] = Economy.new({ store = records(), mint = Mint.new(ds, now), rand = rng(30 + k), time = function() return 7 end })
	end
	local serials = {}
	for i = 1, 400 do
		local econ = servers[i % 2 + 1]
		local user = i % 7
		local inv = econ:inventory(user)
		inv.crates.scrap += 1
		local ok, res = econ:open(user, "scrap")
		assert(ok, "an opening failed")
		local k = res.id .. "#" .. res.serial
		assert(not serials[k], `{k} was minted twice`)
		serials[k] = true
		clock += 1
	end
	local view = servers[1]:view(1)
	assert(#view.items > 0 and view.items[1].serial and view.items[1].copies >= 1, "the view lacks serials or copies")
	assert(view.guarantees.forge == Loot.CRATES.forge.guarantee.at - servers[1]:inventory(1).pity.forge, "the view's guarantee countdown is wrong")
end

-- 10. The line under the results.
do
	local t, c = DropBanner.text({ counted = true, left = 3 })
	assert(t == "Next drop in 3 games", t)
	t = DropBanner.text({ counted = true, left = 1 })
	assert(t == "Next drop in 1 game", t)
	t, c = DropBanner.text({ counted = true, left = 4, drop = { kind = "item", id = "sword_starforged", rarity = "Legendary", serial = 57 } })
	assert(t == "DROP!  Legendary Starforged  #57  ·  next drop in 4 games" and c == Loot.RARITY.Legendary.colour, t)
	t = DropBanner.text({ counted = true, left = 2, drop = { kind = "crate", crate = "forge" } })
	assert(string.find(t, "Forge Crate", 1, true), t)
	assert(DropBanner.text({ counted = false, capped = true }) == "Drops are resting: back next hour", "the cap is not explained")
	assert(DropBanner.text({ counted = false }) == "This match did not count toward a drop", "an uncounted match is not explained")
end
print("PASS economy: instances cleaned and migrated, the owned index rebuilt; serials unique across servers in growing blocks, copies counted, failures reported; Training, short and hitless matches do not count; a drop every 2-5 counted matches following its table, twelve an hour; crates open with keys (earned first, paid marked), guarantees saved and firing; a failed vault spends nothing and never loses a drop; crafting and salvaging pay as listed; the results line says it")
