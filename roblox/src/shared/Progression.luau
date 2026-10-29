--!strict
-- Levels, weapon unlocks and the Ranked ladder (Roblox only; the owner's design, 2026-10-30).
--
-- Everyone starts at level 1 with the first six weapons ever made - Sword, Scythe, Blasters,
-- Grimoire, Axe and Pike - as a foundation, and unlocks the rest between levels 3 and 15. XP comes
-- from matches that count (Economy.qualifies, inside the hourly cap), more for a win, so level 15 is
-- about thirty matches in ("quick", the owner's pick). Ranked - the tournament - opens at level 10.
--
-- Ranked climbs six tiers on rank points: a win adds, a loss takes a few away, but never below the
-- tier you have reached. The first time you reach a tier it pays once (keys, Sparks, a crate), and
-- every ranked match pays a boost on top: the drop meter moves faster, a win pays Sparks, and every
-- few ranked wins pay a Forge Key.
--
-- Pure: the server applies it to the saved record (Economy), the client shows it.
local Progression = {}

-- ---------------------------------------------------------------------- levels ----
Progression.XP_MATCH, Progression.XP_WIN = 100, 60
-- a match with CPU fighters in it counts this much, as it does toward the drop meter
Progression.XP_CPU = 0.75
Progression.MAX_LEVEL = 50
-- XP from level L to L+1: STEP + GROWTH * (L - 1). Level 3 is three matches in, 10 about sixteen,
-- 15 about thirty.
Progression.STEP, Progression.GROWTH = 140, 15

function Progression.need(level: number): number
	return Progression.STEP + Progression.GROWTH * (level - 1)
end

-- The level `xp` reaches, the XP into it, and the XP the next level needs (0 at the top).
function Progression.level(xp: number): (number, number, number)
	local level, left = 1, math.max(0, math.floor(tonumber(xp) or 0))
	while level < Progression.MAX_LEVEL and left >= Progression.need(level) do
		left -= Progression.need(level)
		level += 1
	end
	return level, left, if level < Progression.MAX_LEVEL then Progression.need(level) else 0
end

-- The XP a counted match pays.
function Progression.xpFor(won: boolean, cpu: boolean): number
	local xp = Progression.XP_MATCH + (if won then Progression.XP_WIN else 0)
	return math.floor(xp * (if cpu then Progression.XP_CPU else 1))
end

-- ---------------------------------------------------------------------- weapons ----
-- The first six weapons made: everyone has these.
Progression.STARTERS = { "Sword", "Scythe", "Blasters", "Grimoire", "Axe", "Pike" }
-- The rest, in the order they were made, from level 3 to level 15. A new weapon must be given a
-- level here (tests/progression fails until it is).
Progression.UNLOCKS = {
	{ level = 3, weapon = "Gauntlets" },
	{ level = 5, weapon = "Hammer" },
	{ level = 6, weapon = "Longbow" },
	{ level = 8, weapon = "Flail" },
	{ level = 9, weapon = "Shield" },
	{ level = 11, weapon = "Daggers" },
	{ level = 12, weapon = "Whip" },
	{ level = 14, weapon = "Chakram" },
	{ level = 15, weapon = "RocketBoots" },
}
local UNLOCK_AT: { [string]: number } = {}
for _, id in Progression.STARTERS do UNLOCK_AT[id] = 1 end
for _, u in Progression.UNLOCKS do UNLOCK_AT[u.weapon] = u.level end

-- The level a weapon unlocks at. A weapon nobody gave a level is the last unlock's, never free.
function Progression.unlockLevel(weapon: string): number
	return UNLOCK_AT[weapon] or Progression.UNLOCKS[#Progression.UNLOCKS].level
end
function Progression.unlocked(level: number, weapon: string): boolean
	return level >= Progression.unlockLevel(weapon)
end
-- The weapons unlocked by going from level `from` to level `to`.
function Progression.unlocksBetween(from: number, to: number): { string }
	local out = {}
	for _, u in Progression.UNLOCKS do
		if u.level > from and u.level <= to then table.insert(out, u.weapon) end
	end
	return out
end

-- ---------------------------------------------------------------------- ranked ----
Progression.RANKED_LEVEL = 10
-- rank points: a win, a loss; a match with CPU fighters moves them half as far
Progression.RANK_WIN, Progression.RANK_LOSS, Progression.RANK_CPU = 25, 10, 0.5
-- the boost every ranked match pays: the drop meter steps RANKED_METER further (a match is one
-- step, so half as far again; in quarters, as the meter is saved), a win pays RANKED_SPARKS, and
-- every KEY_EVERY ranked wins pay an earned Forge Key
Progression.RANKED_METER, Progression.RANKED_SPARKS, Progression.KEY_EVERY = 0.5, 15, 3
-- `at` is the points the tier begins at; `reward` is paid once, the first time it is reached
Progression.TIERS = {
	{ id = "bronze", name = "BRONZE", at = 0, colour = "#C98A4B" },
	{ id = "silver", name = "SILVER", at = 100, colour = "#C9D1DC", reward = { keys = 1, sparks = 50 } },
	{ id = "gold", name = "GOLD", at = 250, colour = "#F2C14E", reward = { keys = 2, sparks = 100, crate = "scrap" } },
	{ id = "platinum", name = "PLATINUM", at = 450, colour = "#7FE0D2", reward = { keys = 3, sparks = 200, crate = "forge" } },
	{ id = "diamond", name = "DIAMOND", at = 700, colour = "#8FB8FF", reward = { keys = 4, sparks = 350, crate = "forge" } },
	{ id = "champion", name = "CHAMPION", at = 1000, colour = "#FF6B8A", reward = { keys = 6, sparks = 600, crate = "forge", crates = 2 } },
}

-- The tier (its index) `points` is in.
function Progression.tier(points: number): number
	local t = 1
	for i, tier in Progression.TIERS do
		if points >= tier.at then t = i end
	end
	return t
end

-- Rank points after a ranked match: never below the floor of the best tier reached.
function Progression.rankAfter(points: number, best: number, won: boolean, cpu: boolean): number
	local k = if cpu then Progression.RANK_CPU else 1
	local delta = if won then math.floor(Progression.RANK_WIN * k) else -math.floor(Progression.RANK_LOSS * k)
	local floor = Progression.TIERS[math.clamp(best, 1, #Progression.TIERS)].at
	return math.max(floor, points + delta)
end

return Progression
