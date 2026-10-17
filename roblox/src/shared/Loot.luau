--!strict
-- Crates, drops and the odds players are shown (Roblox only; docs/briefs/crates-and-monetisation-plan.md).
--
-- ONE SOURCE OF ODDS. `Loot.odds` turns a crate's table into the itemised list the "Odds & Details"
-- screen shows, and `Loot.roll` picks from that same list - so what a player is told is, by
-- construction, what the server does. Roblox's paid random items policy requires every outcome's
-- odds as percentages summing to exactly 100%, shown before a paid key is used, updated while a
-- probability modifier (the guarantee) is in force: tests/loot.luau holds all of it.
--
-- Pure: no services, no saving. The randomness is passed in (a function returning [0, 1)), so the
-- server can use a Random and the tests a seeded one. Not yet used by the game (plan phase 1).
local Cosmetics = require(script.Parent.Cosmetics)
local Loot = {}

-- Rarity order, colour, what a duplicate turns into, and the Sparks price to craft one.
Loot.RARITIES = Cosmetics.RARITIES
Loot.RARITY = {
	Common = { rank = 1, colour = "#B8C0CC", dupe = 5, craft = 30 },
	Uncommon = { rank = 2, colour = "#5FD068", dupe = 15, craft = 90 },
	Rare = { rank = 3, colour = "#4A9BFF", dupe = 40, craft = 250 },
	Epic = { rank = 4, colour = "#B35CFF", dupe = 120, craft = 750 },
	Legendary = { rank = 5, colour = "#FFB730", dupe = 400, craft = 2500 },
	Mythic = { rank = 6, colour = "#FF4A6A", dupe = 1200, craft = 8000 },
} :: { [string]: { rank: number, colour: string, dupe: number, craft: number } }

-- The crates. `odds` are percentages by rarity (each table sums to 100); within a rarity every
-- item is equally likely. `key` names what opens it (nil: free). `guarantee`: the `at`th opening
-- since the last `min`-or-better item is that good or better.
Loot.CRATES = {
	scrap = { name = "Scrap Crate", key = nil,
		odds = { Common = 60, Uncommon = 27, Rare = 10, Epic = 2.5, Legendary = 0.5 },
		guarantee = { at = 25, min = "Epic" } },
	forge = { name = "Forge Crate", key = "forge",
		odds = { Rare = 62, Epic = 28, Legendary = 8.5, Mythic = 1.5 },
		guarantee = { at = 40, min = "Legendary" } },
} :: { [string]: any }

-- What a drop is (every 2-5 qualifying matches), by chance out of 100.
export type Drop = { kind: string, chance: number, crate: string?, key: string?, amount: number? }
Loot.DROPS = {
	{ kind = "crate", crate = "scrap", chance = 60 },
	{ kind = "sparks", amount = 50, chance = 20 },
	{ kind = "crate", crate = "forge", chance = 12 },
	{ kind = "key", key = "forge", chance = 5 },
	{ kind = "item", crate = "scrap", chance = 3 },     -- a cosmetic straight from the Scrap pool
} :: { Drop }
-- the drop meter: matches until the next drop, chosen uniformly from this range
Loot.METER = { 2, 5 }

-- The items a crate holds, by rarity, from a series (default every released one), in a fixed order.
-- The catalogue is fixed for a server's life, so each crate's pool is worked out once.
local pools: { [string]: { [string]: { string } } } = {}
function Loot.pool(crateId: string, series: number?): { [string]: { string } }
	local key = crateId .. "|" .. tostring(series)
	if pools[key] then return pools[key] end
	local out: { [string]: { string } } = {}
	local crate = Loot.CRATES[crateId]
	for _, item in Cosmetics.LIST do
		if item.source == "crate" and item.crates and table.find(item.crates, crateId)
			and crate.odds[item.rarity] and (series == nil or item.series == series) then
			out[item.rarity] = out[item.rarity] or {}
			table.insert(out[item.rarity], item.id)
		end
	end
	for _, ids in out do table.sort(ids) end
	pools[key] = out
	return out
end

export type Outcome = { id: string, rarity: string, percent: number }

-- (worked out once per crate and guarantee state; frozen, as callers share it)
local lists: { [string]: { Outcome } } = {}
-- Every outcome of opening `crateId` with `count` openings already since the last guaranteed-tier
-- item, and its exact chance in percent. On the guaranteed opening the rarities below the
-- guarantee's are 0 and the rest scale up to fill 100. In rarity order, then id.
function Loot.odds(crateId: string, count: number?, series: number?): { Outcome }
	local crate = Loot.CRATES[crateId]
	local pool = Loot.pool(crateId, series)
	local floor = 0
	if crate.guarantee and (count or 0) + 1 >= crate.guarantee.at then
		floor = Loot.RARITY[crate.guarantee.min].rank
	end
	local key = crateId .. "|" .. floor .. "|" .. tostring(series)
	if lists[key] then return lists[key] end
	local total = 0
	for rarity, pct in crate.odds do
		if Loot.RARITY[rarity].rank >= floor and pool[rarity] then total += pct end
	end
	local out: { Outcome } = {}
	for _, rarity in Loot.RARITIES do
		local pct, ids = crate.odds[rarity], pool[rarity]
		if pct and ids and Loot.RARITY[rarity].rank >= floor then
			for _, id in ids do
				table.insert(out, table.freeze({ id = id, rarity = rarity, percent = pct * 100 / total / #ids }))
			end
		end
	end
	lists[key] = table.freeze(out)
	return out
end

-- Open a crate: the item, its rarity, and the guarantee count to save. `rand()` is in [0, 1).
function Loot.roll(crateId: string, count: number, rand: () -> number, series: number?): (string, string, number)
	local outcomes = Loot.odds(crateId, count, series)
	local at = rand() * 100
	local pick = outcomes[#outcomes]
	for _, o in outcomes do
		at -= o.percent
		if at < 0 then pick = o; break end
	end
	local g = Loot.CRATES[crateId].guarantee
	local next = count + 1
	if g and Loot.RARITY[pick.rarity].rank >= Loot.RARITY[g.min].rank then next = 0 end
	return pick.id, pick.rarity, next
end

function Loot.rollDrop(rand: () -> number): any
	local at = rand() * 100
	for _, d in Loot.DROPS do
		at -= d.chance
		if at < 0 then return d end
	end
	return Loot.DROPS[#Loot.DROPS]
end

function Loot.nextMeter(rand: () -> number): number
	local lo, hi = Loot.METER[1], Loot.METER[2]
	return math.min(hi, lo + math.floor(rand() * (hi - lo + 1)))
end

-- Sparks for a duplicate, and the Sparks to craft an item (every crate item is craftable).
function Loot.dupe(rarity: string): number
	return Loot.RARITY[rarity].dupe
end
function Loot.craftCost(id: string): number?
	local item = Cosmetics.get(id)
	if not item or item.source ~= "crate" then return nil end
	return Loot.RARITY[item.rarity].craft
end

-- A percentage as the odds screen writes it: four digits past the first non-zero one, as the policy
-- allows when rounding (the screen adds that shown figures may not sum to exactly 100%).
function Loot.format(percent: number): string
	local decimals
	if percent >= 1 then
		-- the first non-zero digit is the leading integer one: keep four digits after it
		local n = math.floor(math.log10(percent)) + 1
		decimals = math.max(0, 5 - n)
	else
		local k, p = 0, percent
		while p > 0 and p < 1 do p *= 10; k += 1 end
		decimals = k + 4
	end
	return string.format(`%.{decimals}f%%`, percent)
end

return Loot
