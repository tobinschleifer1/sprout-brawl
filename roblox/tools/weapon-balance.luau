--!nocheck
-- Development tool, not a test: how a weapon fares against the roster, in real bot matches.
--   lune run tools/weapon-balance <weapon> [matches per opponent] [botLevel]
-- Two bots, 3 stocks, up to ten minutes, across stages and seeds. Reports the weapon's win rate per opponent,
-- and overall, with the match lengths and timeouts - the Roblox-only weapons have no web balance
-- harness to lean on, so this is theirs.
local process = require("@lune/process")
local Loader = require("../tests/loader")
local Match, Loadout = Loader.load("Match"), Loader.load("Loadout")
local Weapons = Loader.load("Weapons")
local Stages = Loader.load("Data/Stages").LIST
local weapon = process.args[1] or "Chakram"
local N = tonumber(process.args[2] or "4") or 4
local level = process.args[3] or "hard"

local function play(a: string, b: string, seed: number, swap: boolean): (number?, number)
	local stage = Stages[(seed % #Stages) + 1]
	local fa = { char = Loadout.build("Classic", a), isBot = true, botLevel = level, team = 0 }
	local fb = { char = Loadout.build("Noir", b), isBot = true, botLevel = level, team = 1 }
	local m = Match.new({ mode = "StockFFA", stage = stage, seed = seed, items = false, stocks = 3, timeLimit = 180,
		fighters = if swap then { fb, fa } else { fa, fb } })
	m.state = "fight"
	local frames = 0
	-- stock matches have no clock (Match.timed): cap at ten minutes, reported as unfinished
	while not m.results and frames < 600 * 60 do
		m:step(); frames += 1
	end
	if not m.results then return nil, frames end
	local winnerIndex = m.results.rows[1].index
	local aIndex = if swap then 1 else 0
	return (if winnerIndex == aIndex then 1 else 0), frames
end

local totalW, totalN, timeouts = 0, 0, 0
for _, w in Weapons.LIST do
	if w.id ~= weapon then
		local wins, n, len = 0, 0, 0
		for k = 1, N do
			local r, frames = play(weapon, w.id, 1000 + k * 17, k % 2 == 0)
			if r == nil then timeouts += 1 else wins += r; n += 1; len += frames end
		end
		totalW += wins; totalN += n
		print(string.format("%-10s vs %-10s %d/%d  (avg %.0f s)", weapon, w.id, wins, n, if n > 0 then len / n / 60 else 0))
	end
end
print(string.format("%s overall: %d/%d = %.0f%%, %d timeouts", weapon, totalW, totalN, if totalN > 0 then 100 * totalW / totalN else 0, timeouts))
