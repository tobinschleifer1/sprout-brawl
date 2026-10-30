--!strict
-- The near-miss line under a match's results (docs/briefs/retention-plan.md, step 1): the single
-- closest goal, by the share of it still to go, among the next level and (after a ranked match) the
-- next tier. A tie goes to the level. Pure: DropBanner shows it, tests/next-goal checks it.
local Shared = game:GetService("ReplicatedStorage").Shared
local Progression = require(Shared.Progression)
local Weapons = require(Shared.Weapons)
local NextGoal = {}

-- What reaching `level` gives, in words, or "" (a weapon, Ranked opening).
function NextGoal.levelReward(level: number): string
	local parts = {}
	for _, id in Progression.unlocksBetween(level - 1, level) do
		local w = Weapons.BY_ID[id]
		table.insert(parts, if w then w.name else id)
	end
	if level == Progression.RANKED_LEVEL then table.insert(parts, "Ranked") end
	return table.concat(parts, " + ")
end

-- `p` is Economy._progress's answer (out.progress). Returns the line, or "" when there is nothing
-- to show (the match did not count, or the player is at the top of everything).
function NextGoal.text(p: any): string
	if type(p) ~= "table" or type(p.level) ~= "number" then return "" end
	local best, bestShare = "", math.huge
	local need, into = tonumber(p.need) or 0, tonumber(p.into) or 0
	if need > 0 then
		local left = math.max(1, need - into)
		local reward = NextGoal.levelReward(p.level + 1)
		best = `NEXT: {left} XP to level {p.level + 1}` .. (if reward ~= "" then ` - {reward}` else "")
		bestShare = left / need
	end
	local r = p.rank
	if type(r) == "table" and type(r.points) == "number" then
		local t = math.clamp(tonumber(r.tier) or 1, 1, #Progression.TIERS)
		local nextTier = Progression.TIERS[t + 1]
		if nextTier then
			local span = nextTier.at - Progression.TIERS[t].at
			local left = math.max(1, nextTier.at - r.points)
			local wins = math.ceil(left / Progression.RANK_WIN)
			-- (strictly closer: a tie keeps the level)
			if left / span < bestShare then
				best = `NEXT: {left} RP to {nextTier.name} - {wins} {if wins == 1 then "win" else "wins"}`
				bestShare = left / span
			end
		end
	end
	return best
end

return NextGoal
