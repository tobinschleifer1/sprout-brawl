--!strict
-- Does Match.luau run a whole match the way web/src/engine/match.js does?
--
--   lune run tests/match-parity
--
-- Whole matches, not probes: countdown, KOs, credit, respawns, stocks, team pools, the timer,
-- sudden death, and the results table. Scripted rather than fought, because bots are the next phase
-- and a match with no inputs never ends on its own - `set` writes straight onto a fighter, so a KO
-- lands on the frame the scenario chooses.
--
-- Two things this cannot show, both established by mutation:
--   * the rounding on the respawn timer. RESPAWN.delay is 2.0, so 2.0 x 60 is exact and rounding
--     or flooring it is the same number.
--   * the `a.index - b.index` tiebreak in the results sort. It exists because JavaScript's sort is
--     stable and Luau's table.sort is not, so two fighters tied on every other key would otherwise
--     come out in whichever order the sort happened to leave them. Removing it does not reliably
--     fail, because an unstable sort is not obliged to actually reorder a four-element array - the
--     tiebreak is what makes the two languages agree, not something a mutation can demonstrate.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Loader = require("./loader")

local Match = Loader.load("Match")
local Input = Loader.load("Input")
local Loadout = Loader.load("Loadout")
local StageData = Loader.load("Data/Stages")

local T = serde.decode("json", fs.readFile("tests/trace-match.json"))

local failures: { string } = {}
local checked = 0
local function fail(msg: string)
	if #failures < 10 then
		table.insert(failures, msg)
	end
end

local EPS = 1e-12
local function near(a: number, b: number): boolean
	local d = math.abs(a - b)
	return d <= EPS or d <= EPS * math.max(math.abs(a), math.abs(b))
end
local function num(v: any): number
	return tonumber(v) :: number
end

local function frameFrom(input: any): any
	local fr = Input.emptyFrame()
	for k, v in input or {} do
		(fr :: any)[k] = v
	end
	return fr
end

for _, spec in T.scenarios do
	local script: { [string]: any } = {}
	local input = {
		kb2Active = false,
		poll = function(_) end,
		get = function(_, source: string): any
			return script[source] or Input.emptyFrame()
		end,
	}
	local fighters = {}
	for i, who in spec.who do
		table.insert(fighters, { char = Loadout.build(who[1], who[2]), skin = 0,
			team = if spec.teamOf then num(spec.teamOf[i]) else i - 1,
			source = `p{i - 1}`, isBot = false, name = `P{i - 1}` })
	end
	local m = Match.new({
		mode = spec.mode, stage = StageData.BY_ID[spec.stage], input = input,
		seed = if spec.seed ~= nil then num(spec.seed) else 7,
		stocks = if spec.stocks ~= nil then num(spec.stocks) else 3,
		timeLimit = if spec.timeLimit ~= nil then num(spec.timeLimit) else 180,
		items = not not spec.items, fighters = fighters,
	})

	local frame = 0
	local broke = false
	for _, seg in spec.segments do
		if broke then break end
		for _ = 1, seg.frames do
			if seg.set then
				for k, kv in seg.set do
					for field, value in kv do
						if field ~= "selfHit" then
							m.fighters[num(k) + 1][field] = value
						end
					end
					-- see the recorder: `lastHitBy` is a fighter, which JSON cannot carry
					if kv.selfHit then
						m.fighters[num(k) + 1].lastHitBy = m.fighters[num(k) + 1]
					end
				end
			end
			for k = 1, #m.fighters do
				script[`p{k - 1}`] = frameFrom(if seg["in"] then seg["in"][tostring(k - 1)] else nil)
			end
			table.clear(m.events)
			Match.step(m)

			local want = spec.rows[frame + 1]
			if want == nil then
				break
			end
			local at = 0
			local function expect(got: any, label: string, numeric: boolean)
				at += 1
				checked += 1
				local w = want[at]
				local ok
				if w == nil then
					ok = got == nil
				elseif numeric and typeof(got) == "number" then
					ok = near(got, num(w))
				else
					ok = tostring(got) == tostring(w)
				end
				if not ok and not broke then
					fail(string.format("%s frame %d %s: Luau %s, JS %s",
						spec.name, frame, label, tostring(got), tostring(w)))
					broke = true
				end
			end

			expect(m.state, "state", false)
			expect(m.frame, "frame", true)
			expect(m.time, "time", true)
			expect(m.countdown, "countdown", true)
			expect(m.sdTimer, "sdTimer", true)
			expect(m.timed, "timed", false)
			expect(m.training, "training", false)
			for _, f in m.fighters do
				for _, k in T.fields do
					expect(f[k], `P{f.index}.{k}`, true)
				end
				expect(f:stocksLeft(), `P{f.index}.stocksLeft`, true)
				expect(f.eliminatedAt, `P{f.index}.eliminatedAt`, true)
			end
			if broke then break end

			-- the team pool, as sorted key=value pairs
			local keys = {}
			for t in m.teamPool do
				table.insert(keys, tostring(t))
			end
			table.sort(keys)
			local parts = {}
			for _, t in keys do
				table.insert(parts, `{t}={m.teamPool[tonumber(t)]}`)
			end
			expect(table.concat(parts, ","), "teamPool", false)
			if broke then break end

			-- the event stream
			at += 1
			local wantEvents = want[at]
			checked += 1
			if #m.events ~= #wantEvents then
				local got = {}
				for _, e in m.events do
					table.insert(got, e.type)
				end
				fail(string.format("%s frame %d: %d events (%s), JS had %d", spec.name, frame,
					#m.events, table.concat(got, ","), #wantEvents))
				broke = true
			else
				for i, e in m.events do
					local w = wantEvents[i]
					local vals = { e.type, e.n, e.fighter, e.by, e.side, e.last, e.winner, e.x, e.y }
					for j, gv in vals do
						checked += 1
						local wv = w[j]
						local ok
						if wv == nil then
							ok = gv == nil
						elseif typeof(gv) == "number" then
							ok = near(gv, num(wv))
						else
							ok = tostring(gv) == tostring(wv)
						end
						if not ok then
							fail(string.format("%s frame %d event %d field %d: Luau %s, JS %s",
								spec.name, frame, i, j, tostring(gv), tostring(wv)))
							broke = true
							break
						end
					end
					if broke then break end
				end
			end
			if broke then break end

			-- the results table, once the match is over
			at += 1
			local wantResults = want[at]
			checked += 1
			if wantResults == nil then
				if m.results ~= nil then
					fail(`{spec.name} frame {frame}: Luau finished the match, JS had not`)
					broke = true
				end
			elseif m.results == nil then
				fail(`{spec.name} frame {frame}: JS finished the match, Luau had not`)
				broke = true
			else
				for i, wr in wantResults do
					local r = m.results.rows[i]
					local vals = { r.index, r.kos, r.falls, r.sds, r.damage, r.percent, r.stocks,
						r.score, if r.eliminatedAt == math.huge then "inf" else r.eliminatedAt }
					for j, gv in vals do
						checked += 1
						local wv = wr[j]
						local ok
						if typeof(gv) == "number" then
							ok = near(gv, num(wv))
						else
							ok = tostring(gv) == tostring(wv)
						end
						if not ok then
							fail(string.format("%s results row %d field %d: Luau %s, JS %s",
								spec.name, i, j, tostring(gv), tostring(wv)))
							broke = true
							break
						end
					end
					if broke then break end
				end
			end
			if broke then break end
			-- no manual bump here: expect() advances the cursor itself
			expect(if m.results then m.results.winnerTeam else nil, "winnerTeam", false)
			if broke then break end

			frame += 1
			if m.state == "results" then
				break
			end
		end
		if m.state == "results" then
			break
		end
	end
end

print(string.format("replayed %d match values across %d scenarios", checked, #T.scenarios))
if #failures > 0 then
	print(string.format("\n%d MISMATCHES:", #failures))
	for _, f in failures do
		print("  " .. f)
	end
	process.exit(1)
end
print(string.format("Match.luau matches web/src/engine/match.js to within %g relative.", EPS))
