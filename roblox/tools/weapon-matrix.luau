--!nocheck
-- Development tool, not a test: every weapon against every other, in real bot matches - the
-- roster-wide view tools/weapon-balance.luau gives one weapon at a time.
--   lune run tools/weapon-matrix <out.json> [matches per pair] [botLevel] [shard] [shards]
-- Each unordered pair plays N matches, the sides and the avatars swapping every other one, on the
-- stages in turn (seeded). Two bots, 3 stocks, no items, capped at ten minutes (reported as
-- unfinished). Bot-vs-bot results measure how well the AI plays a weapon as much as the weapon
-- itself, and are noisy: a 14-match duel has returned 3/14 and then 7/14. Use the shards to run it
-- in parallel, then tools/weapon-matrix.mjs to merge them.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Loader = require("../tests/loader")
local Match, Loadout = Loader.load("Match"), Loader.load("Loadout")
local Weapons = Loader.load("Weapons")
local Stages = Loader.load("Data/Stages").LIST
local out = process.args[1] or "weapon-matrix.json"
local N = tonumber(process.args[2] or "10") or 10
local level = process.args[3] or "hard"
local shard, shards = tonumber(process.args[4] or "1") or 1, tonumber(process.args[5] or "1") or 1

local function play(a: string, b: string, seed: number, swap: boolean): (number?, number, any)
	local stage = Stages[(seed % #Stages) + 1]
	local fa = { char = Loadout.build(if swap then "Noir" else "Classic", a), isBot = true, botLevel = level, team = 0 }
	local fb = { char = Loadout.build(if swap then "Classic" else "Noir", b), isBot = true, botLevel = level, team = 1 }
	local m = Match.new({ mode = "StockFFA", stage = stage, seed = seed, items = false, stocks = 3, timeLimit = 180,
		fighters = if swap then { fb, fa } else { fa, fb } })
	m.state = "fight"
	local frames = 0
	while not m.results and frames < 600 * 60 do
		m:step(); frames += 1
	end
	if not m.results then return nil, frames, stage.id end
	local aIndex = if swap then 1 else 0
	return (if m.results.rows[1].index == aIndex then 1 else 0), frames, stage.id
end

local ids = {}
for _, w in Weapons.LIST do table.insert(ids, w.id) end
local results, pair = {}, 0
for i = 1, #ids do
	for j = i + 1, #ids do
		pair += 1
		if (pair - 1) % shards == shard - 1 then
			local r = { a = ids[i], b = ids[j], aWins = 0, games = 0, timeouts = 0, frames = 0 }
			for k = 1, N do
				local won, frames = play(ids[i], ids[j], 1000 + pair * 131 + k * 17, k % 2 == 0)
				if won == nil then r.timeouts += 1 else r.aWins += won; r.games += 1; r.frames += frames end
			end
			table.insert(results, r)
			print(string.format("%-11s vs %-11s %2d/%d  %d timeouts", r.a, r.b, r.aWins, r.games, r.timeouts))
		end
	end
end
fs.writeFile(out, serde.encode("json", { matchesPerPair = N, botLevel = level, results = results }))
