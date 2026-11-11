--!nocheck
-- Development tool, not a test: how each stage plays, in real bot matches.
--   lune run tools/stage-stats <out.json> [matches per stage] [level] [disasters: off|stage|chaos]
-- Every stage plays N matches of two bots (weapons drawn from the roster by seed, 3 stocks, no
-- items), the match ending or capped at ten minutes. Per stage: the average length, timeouts, KOs
-- credited to a fighter and KOs nobody is credited with (a self-destruct, or a hazard or disaster
-- that launched them with no fighter's hit in the 8 s before), and where fighters died (the side
-- of the blast box). Hazards are part of a stage and always on; disasters are the switch.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Loader = require("../tests/loader")
local Match, Loadout, Weapons = Loader.load("Match"), Loader.load("Loadout"), Loader.load("Weapons")
local Stages = Loader.load("Data/Stages").LIST
local out = process.args[1]
local N = tonumber(process.args[2] or "8") or 8
local level = process.args[3] or "hard"
local disasters = process.args[4] or "off"

local rows = {}
for si, stage in Stages do
	local row = { stage = stage.id, matches = 0, frames = 0, timeouts = 0, credited = 0, uncredited = 0, sides = {} }
	for k = 1, N do
		local seed = 900 + si * 101 + k * 13
		local a = Weapons.LIST[(seed % #Weapons.LIST) + 1].id
		local b = Weapons.LIST[((seed * 7) % #Weapons.LIST) + 1].id
		local m = Match.new({ mode = "StockFFA", stage = stage, seed = seed, items = false, stocks = 3, timeLimit = 180, disasters = disasters,
			fighters = { { char = Loadout.build("Classic", a), isBot = true, botLevel = level, team = 0 },
				{ char = Loadout.build("Noir", b), isBot = true, botLevel = level, team = 1 } } })
		m.state = "fight"
		local frames, seen = 0, 0
		while not m.results and frames < 600 * 60 do
			m:step(); frames += 1
			if #m.events < seen then seen = 0 end
			for e = seen + 1, #m.events do
				local ev = m.events[e]
				if ev.type == "ko" then
					if ev.by == -1 or ev.by == ev.fighter then row.uncredited += 1 else row.credited += 1 end
					row.sides[ev.side] = (row.sides[ev.side] or 0) + 1
				end
			end
			seen = #m.events
		end
		row.matches += 1; row.frames += frames
		if not m.results then row.timeouts += 1 end
	end
	table.insert(rows, row)
	print(string.format("%-14s %3.0f s  KOs %d credited, %d not  timeouts %d", stage.id, row.frames / row.matches / 60, row.credited, row.uncredited, row.timeouts))
end
fs.writeFile(out, serde.encode("json", { matchesPerStage = N, level = level, disasters = disasters, rows = rows }))
