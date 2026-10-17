--!nocheck
-- The cosmetics catalogue and the loot tables (src/shared/Cosmetics.luau, Loot.luau; Roblox only).
-- Direct properties, the ones Roblox's paid random items policy and the plan promise: every odds
-- list names every outcome once with percentages summing to exactly 100; the roll does what the list
-- says over 400,000 seeded openings; the guarantee fires on time and its changed odds are what is
-- shown; drops and the drop meter keep their tables; duplicates and crafting pay out as listed, and
-- every crate item can be crafted (nothing is random-only); the catalogue is well formed.
local fs = require("@lune/fs")
local Loader = require("./loader")
local Cosmetics, Loot = Loader.load("Cosmetics"), Loader.load("Loot")
local Weapons = Loader.load("Weapons")

-- a small seeded generator, so a failure reproduces: Park-Miller, whose products stay inside a
-- double's 53 exact bits (a 1103515245 multiplier does not, and skews a million rolls)
local function rng(seed)
	local s = seed
	return function()
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end
local function near(a, b, eps, msg) assert(math.abs(a - b) <= eps, msg) end

-- The catalogue: unique ids, known types and rarities, skins for weapons that exist, and the
-- weapon skins are the ones designed in tools/cosmetic-sheet.mjs.
do
	local sheet = fs.readFile("tools/cosmetic-sheet.mjs")
	local seen = {}
	for _, item in Cosmetics.LIST do
		assert(not seen[item.id], `{item.id} is listed twice`)
		seen[item.id] = true
		assert(table.find(Cosmetics.TYPES, item.type), `{item.id}: unknown type {item.type}`)
		assert(Loot.RARITY[item.rarity], `{item.id}: unknown rarity {item.rarity}`)
		if item.type == "weapon_skin" then
			assert(Weapons.BY_ID[item.weapon], `{item.id}: no weapon {item.weapon}`)
			assert(string.find(sheet, `id: '{item.id}'`, 1, true), `{item.id} has no design in cosmetic-sheet.mjs`)
		end
		if item.source == "crate" then
			assert(item.crates and #item.crates > 0, `{item.id} is a crate item in no crate`)
			for _, c in item.crates do assert(Loot.CRATES[c].odds[item.rarity], `{item.id} is {item.rarity}, which {c} never gives`) end
		end
	end
end

-- Every crate: its rarity odds sum to 100, every rarity it gives has items, and the itemised list
-- names each item once and sums to exactly 100 - before and on the guaranteed opening.
local listed = 0
for id, crate in Loot.CRATES do
	local sum = 0
	for _, pct in crate.odds do sum += pct end
	near(sum, 100, 1e-12, `{id}'s rarity odds sum to {sum}`)
	local pool = Loot.pool(id)
	for rarity in crate.odds do assert(pool[rarity] and #pool[rarity] > 0, `{id} gives {rarity} but holds none`) end
	for _, count in { 0, crate.guarantee.at - 1 } do
		local total, names = 0, {}
		for _, o in Loot.odds(id, count) do
			assert(not names[o.id], `{id}: {o.id} listed twice`)
			names[o.id] = true
			assert(o.percent > 0, `{id}: {o.id} listed at 0%`)
			total += o.percent
			listed += 1
		end
		near(total, 100, 1e-9, `{id} at count {count}: the listed odds sum to {total}`)
		-- and every item in the crate is listed (none hidden), except those the guarantee rules out
		for rarity, ids in pool do
			local ruled = count + 1 >= crate.guarantee.at and Loot.RARITY[rarity].rank < Loot.RARITY[crate.guarantee.min].rank
			for _, item in ids do
				assert(names[item] == (not ruled or nil), `{id} at count {count}: {item} is {ruled and "listed though ruled out" or "missing"}`)
			end
		end
	end
	-- a rarity's items share its odds equally
	local first = Loot.odds(id, 0)
	local byRarity = {}
	for _, o in first do byRarity[o.rarity] = (byRarity[o.rarity] or 0) + o.percent end
	for rarity, pct in crate.odds do near(byRarity[rarity], pct, 1e-9, `{id}: {rarity} items add to {byRarity[rarity]}, not {pct}`) end
end

-- The roll is the list: 400,000 seeded openings land on each rarity at its listed rate (within
-- five standard deviations), and the guaranteed opening is always good enough.
do
	local N = 400000
	for id, crate in Loot.CRATES do
		local r = rng(7 + #id)
		local hits = {}
		for _ = 1, N do
			local _, rarity = Loot.roll(id, 0, r)
			hits[rarity] = (hits[rarity] or 0) + 1
		end
		for rarity, pct in crate.odds do
			local p = pct / 100
			local sd = math.sqrt(N * p * (1 - p))
			assert(math.abs((hits[rarity] or 0) - N * p) < 5 * sd, `{id}: {rarity} came {hits[rarity]} times in {N}, listed {pct}%`)
		end
		local g = crate.guarantee
		for _ = 1, 20000 do
			local _, rarity, after = Loot.roll(id, g.at - 1, r)
			assert(Loot.RARITY[rarity].rank >= Loot.RARITY[g.min].rank, `{id}: the guaranteed opening gave {rarity}`)
			assert(after == 0, `{id}: the guarantee count did not reset after it fired`)
		end
	end
end

-- The guarantee count: up by one for every opening below the guaranteed tier, back to zero on one
-- at or above it, so it fires on exactly the at-th opening since the last.
do
	local r = rng(99)
	for id, crate in Loot.CRATES do
		local g = crate.guarantee
		local count, since, worst = 0, 0, 0
		for _ = 1, 200000 do
			local _, rarity, nextCount = Loot.roll(id, count, r)
			since += 1
			if Loot.RARITY[rarity].rank >= Loot.RARITY[g.min].rank then
				assert(nextCount == 0, `{id}: a {rarity} did not reset the count`)
				worst = math.max(worst, since)
				since = 0
			else
				assert(nextCount == count + 1, `{id}: a {rarity} moved the count from {count} to {nextCount}`)
			end
			count = nextCount
		end
		assert(worst == g.at, `{id}: the longest wait for {g.min}+ was {worst} openings, the guarantee is {g.at}`)
	end
end

-- Drops: the table sums to 100 and the roll follows it; the meter is 2, 3, 4 or 5, each often.
do
	local sum = 0
	for _, d in Loot.DROPS do sum += d.chance end
	near(sum, 100, 1e-12, `the drop table sums to {sum}`)
	local r = rng(5)
	local N = 400000
	local hits = {}
	for _ = 1, N do
		local d = Loot.rollDrop(r)
		hits[d] = (hits[d] or 0) + 1
	end
	for _, d in Loot.DROPS do
		local p = d.chance / 100
		assert(math.abs((hits[d] or 0) - N * p) < 5 * math.sqrt(N * p * (1 - p)), `drop {d.kind} came {hits[d]} times in {N}, listed {d.chance}%`)
	end
	local meters = {}
	for _ = 1, 40000 do
		local m = Loot.nextMeter(r)
		assert(m >= 2 and m <= 5 and m % 1 == 0, `the drop meter chose {m}`)
		meters[m] = (meters[m] or 0) + 1
	end
	for m = 2, 5 do assert(math.abs(meters[m] - 10000) < 600, `the drop meter chose {m} {meters[m]} times in 40000`) end
	assert(Loot.nextMeter(function() return 0.999999 end) == 5 and Loot.nextMeter(function() return 0 end) == 2, "the meter's range is off at its ends")
end

-- Duplicates and crafting: every rarity pays and costs more than the one below; every crate item is
-- craftable (the free route to everything); nothing outside crates is.
do
	local prev
	for _, rarity in Loot.RARITIES do
		local r = Loot.RARITY[rarity]
		if prev then assert(r.dupe > prev.dupe and r.craft > prev.craft, `{rarity} pays or costs no more than the rarity below`) end
		assert(Loot.dupe(rarity) == r.dupe, `{rarity}: a duplicate pays {Loot.dupe(rarity)}`)
		prev = r
	end
	for _, item in Cosmetics.LIST do
		local cost = Loot.craftCost(item.id)
		if item.source == "crate" then
			assert(cost == Loot.RARITY[item.rarity].craft, `{item.id} cannot be crafted for its rarity's price`)
		else
			assert(cost == nil, `{item.id} ({item.source}) can be crafted`)
		end
	end
end

-- The odds screen's numbers: four digits past the first non-zero one, as the policy allows.
do
	assert(Loot.format(60) == "60.000%", Loot.format(60))
	assert(Loot.format(2.5) == "2.5000%", Loot.format(2.5))
	assert(Loot.format(0.0357142857) == "0.035714%", Loot.format(0.0357142857))
	assert(Loot.format(0.5) == "0.50000%", Loot.format(0.5))
end
print(string.format("PASS loot: %d catalogue items; %d listed outcomes across both crates sum to exactly 100%% before and on the guarantee; 400,000 openings each follow the list; guarantees fire on time; drops and the 2-5 meter follow their tables; duplicates and crafting pay out, every crate item craftable", #Cosmetics.LIST, listed))
