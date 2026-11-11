--!nocheck
-- Development tool, not a test: how the bots actually fight, measured in real matches.
--   lune run tools/bot-stats <out.json> ladder [matches per pair] [weapon]
--   lune run tools/bot-stats <out.json> weapons [matches per weapon] [level]
-- `ladder`: every difficulty against every other, mirror weapon (default Sword), so the levels are
-- all that differs. `weapons`: each weapon against itself at one level, so the weapon is all that
-- differs. Both record, per fighter: KOs and self-destructs (a KO with no hit taken in the 4 s
-- before it), ledge grabs, every move started (by id), and frames spent shielding, dodging and
-- grabbing. 3 stocks, no items, every stage in turn, capped at ten minutes. Merge and print with
-- tools/bot-stats.mjs.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Loader = require("../tests/loader")
local Match, Loadout = Loader.load("Match"), Loader.load("Loadout")
local Weapons = Loader.load("Weapons")
local Stages = Loader.load("Data/Stages").LIST
local out, mode = process.args[1], process.args[2] or "ladder"
local N = tonumber(process.args[3] or "10") or 10
local SD_FRAMES = 240

local function blank(): any
	return { matches = 0, wins = 0, kos = 0, sds = 0, ledges = 0, frames = 0, shield = 0, dodge = 0, grab = 0, moves = {}, damage = 0, timeouts = 0 }
end

local function play(a: any, b: any, seed: number, swap: boolean, sa: any, sb: any)
	local stage = Stages[(seed % #Stages) + 1]
	local fa = { char = Loadout.build(if swap then "Noir" else "Classic", a.weapon), isBot = true, botLevel = a.level, team = 0 }
	local fb = { char = Loadout.build(if swap then "Classic" else "Noir", b.weapon), isBot = true, botLevel = b.level, team = 1 }
	local m = Match.new({ mode = "StockFFA", stage = stage, seed = seed, items = false, stocks = 3, timeLimit = 180,
		fighters = if swap then { fb, fa } else { fa, fb } })
	m.state = "fight"
	local stats = if swap then { sb, sa } else { sa, sb }
	local was, lastMove, lastPct = {}, {}, {}
	local frames = 0
	while not m.results and frames < 600 * 60 do
		m:step(); frames += 1
		for i, f in m.fighters do
			local st = stats[i]
			local s = f.state
			if s ~= was[i] then
				if s == "ko" then
					local fresh = f.lastHitBy ~= nil and (f.frameCount - f.lastHitFrame) <= SD_FRAMES
					if fresh then st.kos += 1 else st.sds += 1 end
				elseif s == "ledge" then st.ledges += 1
				end
				was[i] = s
			end
			if f.state == "attack" and f.move and f.move ~= lastMove[i] then
				st.moves[f.move.id] = (st.moves[f.move.id] or 0) + 1
			end
			lastMove[i] = if f.state == "attack" then f.move else nil
			if s == "shield" or s == "shielddrop" then st.shield += 1
			elseif s == "spotdodge" or s == "airdodge" or s == "tech" then st.dodge += 1
			elseif s == "grab" or s == "holding" then st.grab += 1 end
			local pct = f.percent or 0
			if lastPct[i] and pct > lastPct[i] then stats[3 - i].damage += pct - lastPct[i] end
			lastPct[i] = pct
		end
	end
	for i = 1, 2 do stats[i].matches += 1; stats[i].frames += frames end
	if not m.results then
		for i = 1, 2 do stats[i].timeouts += 1 end
		return
	end
	stats[m.results.rows[1].index + 1].wins += 1
end

local result = { mode = mode, matchesPerPair = N, rows = {} }
if mode == "ladder" then
	local weapon = process.args[4] or "Sword"
	local levels = { "easy", "normal", "hard", "elite", "impossible" }
	local per = {}
	for _, l in levels do per[l] = blank() end
	local pairs = {}
	for i = 1, #levels do
		for j = i + 1, #levels do
			local pa, pb = blank(), blank()
			for k = 1, N do
				play({ weapon = weapon, level = levels[i] }, { weapon = weapon, level = levels[j] }, 500 + i * 97 + j * 31 + k * 17, k % 2 == 0, pa, pb)
			end
			table.insert(pairs, { a = levels[i], b = levels[j], aWins = pa.wins, bWins = pb.wins, games = pa.matches, timeouts = pa.timeouts })
			for key, v in pa do if type(v) == "number" then per[levels[i]][key] += v end end
			for key, v in pb do if type(v) == "number" then per[levels[j]][key] += v end end
			for id, c in pa.moves do per[levels[i]].moves[id] = (per[levels[i]].moves[id] or 0) + c end
			for id, c in pb.moves do per[levels[j]].moves[id] = (per[levels[j]].moves[id] or 0) + c end
			print(string.format("%-10s vs %-10s %d-%d (%d timeouts)", levels[i], levels[j], pa.wins, pb.wins, pa.timeouts))
		end
	end
	result.weapon, result.pairs, result.levels = weapon, pairs, per
else
	local level = process.args[4] or "hard"
	result.level = level
	for _, w in Weapons.LIST do
		local sa, sb = blank(), blank()
		for k = 1, N do play({ weapon = w.id, level = level }, { weapon = w.id, level = level }, 700 + k * 23, k % 2 == 0, sa, sb) end
		local st = blank()
		for key, v in sa do if type(v) == "number" then st[key] = v + sb[key] end end
		for _, src in { sa.moves, sb.moves } do for id, c in src do st.moves[id] = (st.moves[id] or 0) + c end end
		local all, never = 0, {}
		for id in w.moves do all += 1; if not st.moves[id] then table.insert(never, id) end end
		table.sort(never)
		st.never = never
		st.weapon, st.moveCount, st.timeouts = w.id, all, sa.timeouts -- (a timeout is one match, not two)
		table.insert(result.rows, st)
		print(string.format("%-11s KOs %d  SDs %d  timeouts %d", w.id, st.kos, st.sds, st.timeouts))
	end
end
fs.writeFile(out, serde.encode("json", result))
