--!nocheck
-- Bug hunt: random bot matches on the real server simulation (shared/Match), with what must always
-- hold checked every frame. A random config each match: mode (stock/timed, free-for-all/teams), 2-6
-- fighters, any weapon and avatar, any bot level, items, weapon drops, disasters, any stage.
--   lune run tools/fuzz-matches [matches] [first seed]
-- Each failure prints its config and seed, so it replays exactly (a match is deterministic in its seed).
local process = require("@lune/process")
local Loader = require("../tests/loader")
local Match, Loadout = Loader.load("Match"), Loader.load("Loadout")
local Weapons = Loader.load("Weapons")
local Stages = Loader.load("Data/Stages").LIST
local Avatars = Loader.load("Data/Avatars")
local N = tonumber(process.args[1] or "40") or 40
local SEED0 = tonumber(process.args[2] or "1") or 1
-- FUZZ_TRACE=seed:fighter:frame prints that fighter's last 40 frames before `frame` in that match
local TS, TF, TA = string.match(process.env.FUZZ_TRACE or "", "^(%d+):(%d+):(%d+)$")
TS, TF, TA = tonumber(TS), tonumber(TF), tonumber(TA)

local avatarIds = {}
for _, a in (Avatars.LIST or Avatars) do if type(a) == "table" and a.id then table.insert(avatarIds, a.id) end end
if #avatarIds == 0 then avatarIds = { "Classic", "Noir" } end
local LEVELS = { "easy", "normal", "hard", "elite", "impossible", "dummy" }
local MODES = { "StockFFA", "StockTeams", "TimedFFA", "TimedTeams" }
local CAP = 8 * 60 * 60          -- eight minutes of game time

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function rng(seed)
	local s = seed
	return function(n) s = (s * 1103515245 + 12345) % 2147483648; return s % n + 1 end
end

local failures, played, frames = {}, 0, 0
local seeds = {}
if process.env.FUZZ_SEEDS then
	for v in string.gmatch(process.env.FUZZ_SEEDS, "%d+") do table.insert(seeds, tonumber(v)) end
else
	for k = 0, N - 1 do table.insert(seeds, SEED0 + k) end
end
for _, seed in seeds do
	local r = rng(seed * 7919)
	local mode = MODES[r(#MODES)]
	local n = if string.find(mode, "Teams") then 2 * r(3) else 1 + r(5)
	local cfg = { mode = mode, stage = Stages[r(#Stages)], seed = seed, items = r(2) == 1, weaponDrops = r(3) == 1,
		disasters = ({ "off", "stage", "chaos" })[r(3)], stocks = r(5), timeLimit = 60 * r(3), fighters = {} }
	local desc = {}
	for i = 1, n do
		local w1, w2 = Weapons.LIST[r(#Weapons.LIST)].id, Weapons.LIST[r(#Weapons.LIST)].id
		local av = avatarIds[r(#avatarIds)]
		local armed = if cfg.weaponDrops then Loadout.buildArmed(av, { w1, w2 }) else nil
		local level = LEVELS[r(#LEVELS)]
		table.insert(cfg.fighters, { char = if armed then armed.char else Loadout.build(av, w1), kit = armed and armed.kit,
			fists = armed and armed.fists, team = (i - 1) % 2, isBot = true, botLevel = level, source = `bot{i}`, name = `CPU {i}` })
		table.insert(desc, `{w1}{if cfg.weaponDrops then "+" .. w2 else ""}/{level}`)
	end
	local where = `seed {seed}: {mode} on {cfg.stage.id or cfg.stage.name}, items {cfg.items}, drops {cfg.weaponDrops}, disasters {cfg.disasters}, `
		.. `stocks {cfg.stocks}, time {cfg.timeLimit}s; {table.concat(desc, ", ")}`
	local ok, m = pcall(Match.new, cfg)
	if not ok then table.insert(failures, `{where}\n    Match.new ERROR {m}`); continue end
	m.state = "fight"
	local outside, inside, problem = {}, {}, nil
	local f = 0
	while not m.results and f < CAP and not problem do
		local pre = if TS == seed then m.fighters[TF + 1] else nil
		local px, py, pst = pre and pre.x, pre and pre.y, pre and pre.state
		local stepped, err = pcall(m.step, m)
		if pre and f > TA - 40 and f <= TA then
			local solids = {}
			for i, q in m.stage.solids do table.insert(solids, string.format("#%d %.1f..%.1f y %.2f..%.2f%s", i, q.x1, q.x2, q.bottom, q.top, if q.dy ~= 0 or q.dx ~= 0 then string.format(" moving %.2f,%.2f", q.dx, q.dy) else "")) end
			print(string.format("f%d (%.2f, %.2f %s) -> (%.2f, %.2f) feet..head %.2f..%.2f r %.2f v %.1f,%.1f %s %s | %s", f, px, py, pst, pre.x, pre.y, pre.y, pre.y + pre.h, pre.r, pre.vx, pre.vy, pre.state, tostring(pre.move and pre.move.id), table.concat(solids, "; ")))
		end
		f += 1
		if not stepped then problem = `frame {f}: step ERROR {err}`; break end
		local b = m.stage.blast
		for _, ft in m.fighters do
			local id = `fighter {ft.index}`
			if not (finite(ft.x) and finite(ft.y) and finite(ft.vx) and finite(ft.vy)) then problem = `frame {f}: {id} non-finite position/velocity ({ft.x}, {ft.y}, {ft.vx}, {ft.vy})`; break end
			if not finite(ft.percent) or ft.percent < 0 or ft.percent > 999 then problem = `frame {f}: {id} damage {ft.percent}`; break end
			if (ft.stocks or 0) < 0 then problem = `frame {f}: {id} stocks {ft.stocks}`; break end
			-- alive and well past the blast zone for a second without being knocked out
			local past = ft.alive and ft.state ~= "ko" and ft.state ~= "respawn"
				and (ft.x < b.left - 4 or ft.x > b.right + 4 or ft.y < b.bottom - 4 or ft.y > b.top + 40)
			outside[ft] = if past then (outside[ft] or 0) + 1 else 0
			if outside[ft] > 60 then problem = `frame {f}: {id} alive {outside[ft]} frames past the blast zone at ({ft.x}, {ft.y}), state {ft.state}`; break end
			-- inside a solid platform (between its top and bottom, within its ends) for half a second
			local stuck = false
			if ft.alive and ft.state ~= "respawn" then
				-- (the body's box, a quarter-stud in from its edges, against the solid's: a fighter's centre
				-- point missed one walking along the floor through a block standing on it)
				for _, p in m.stage.solids do
					-- (0.6 of the radius, as the game's own footing test: an edge may be overhung by 40%)
					if ft.x + ft.r * 0.6 > p.x1 + 0.05 and ft.x - ft.r * 0.6 < p.x2 - 0.05 and ft.y < p.top - 0.25 and ft.y + ft.h > p.bottom + 0.25 then stuck = true end
				end
			end
			inside[ft] = if stuck then (inside[ft] or 0) + 1 else 0
			if inside[ft] > 30 then problem = `frame {f}: {id} {inside[ft]} frames inside a solid platform (since frame {f - inside[ft] + 1}) at ({ft.x}, {ft.y}), state {ft.state}`; break end
		end
	end
	played += 1; frames += f
	if not problem and not m.results then
		local st = {}
		for _, ft in m.fighters do table.insert(st, string.format("#%d %s %.0f%% stocks %s at (%.1f, %.1f) KOs %d", ft.index, ft.state, ft.percent, tostring(ft.stocks), ft.x, ft.y, ft.stats and ft.stats.kos or -1)) end
		problem = `no result after {CAP / 3600} minutes [{table.concat(st, "; ")}; team pool {(function() local t = {} for k, v in m.teamPool do table.insert(t, `{k}={v}`) end return table.concat(t, ",") end)()}]` .. (if string.sub(mode, 1, 5) == "Timed" then " (a timed match)" else "")
	end
	if problem then table.insert(failures, `{where}\n    {problem}`) end
end
print(string.format("%d matches, %.1f minutes of fights, %d problems", played, frames / 3600, #failures))
for _, x in failures do print("  " .. x) end
-- FUZZ_SEEDS=a,b,c plays exactly those seeds; FUZZ_STRICT=1 fails on any problem (tests/solid-ground)
if process.env.FUZZ_STRICT == "1" and #failures > 0 then error(`{#failures} fuzzed matches broke an invariant`, 0) end
