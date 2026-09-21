--!strict
-- What a client is allowed to ask the server for.
--
--     lune run tests/match-config
--
-- MatchConfig is the first place in this game where a remote decides something, so it is the first
-- place an exploiter has anything to aim at. The happy path is the least interesting thing here;
-- what this checks is that hostile and malformed input produces an ORDINARY MATCH rather than an
-- error, a crash, or the thing that was asked for.

local Loader = require("./loader")
local MatchConfig = Loader.load("MatchConfig")

local function fail(msg: string): never
	error(msg, 0)
end

local checked = 0
local PLAYER = { UserId = 7, DisplayName = "tester" } :: any

local function ok(cfg: any): (any, any)
	local roster, opts, why = MatchConfig.sanitise(cfg, PLAYER)
	if not roster then
		fail(`expected a playable match, got refused: {tostring(why)}`)
	end
	checked += 1
	return roster :: any, opts
end

local function refused(cfg: any, what: string)
	local roster, _, why = MatchConfig.sanitise(cfg, PLAYER)
	if roster then
		fail(`{what}: expected a refusal, got a roster of {#roster}`)
	end
	if not why or why == "" then
		fail(`{what}: refused without saying why`)
	end
	checked += 1
end

local function slot(kind: string, weapon: string?, avatar: string?, team: number?): any
	return { type = kind, weaponId = weapon, avatarId = avatar, team = team }
end

local BASE = {
	mode = "StockFFA", stocks = 3, time = 180, items = true, stageId = "TheSpan",
	slots = { slot("you", "Pike", "Vapor"), slot("bot-hard", "Hammer", "Steel") },
}

-- 1. The ordinary case survives intact. If this drifts, everything below is measuring nothing.
do
	local roster, opts = ok(BASE)
	if #roster ~= 2 then fail(`a two-slot config made {#roster} fighters`) end
	if roster[1].player ~= PLAYER then fail("the sender is not in their own match") end
	if roster[1].weapon ~= "Pike" or roster[1].avatar ~= "Vapor" then fail("the sender's kit was not kept") end
	if roster[2].botLevel ~= "hard" then fail(`bot level came out as {tostring(roster[2].botLevel)}`) end
	if roster[2].player ~= nil then fail("a bot slot was given a player") end
	if opts.stage ~= "TheSpan" or opts.stocks ~= 3 or opts.items ~= true then
		fail("the options were not carried through")
	end
	checked += 6
end

-- 2. Rubbish becomes an ordinary match rather than an error. Each of these is a thing a hand-
-- written exploit would actually send.
do
	local roster, opts = ok({
		mode = "SuddenDeathAllItemsOn",               -- not a mode
		stocks = 1e9,                                 -- absurd
		time = -5,
		items = "yes",                                -- not a boolean
		stageId = "../../etc/passwd",                 -- not a stage
		-- A real second fighter, so the match is playable and the assertions below are about
		-- sanitising rather than about refusal. The third slot names a bot level that does not
		-- exist and must be dropped, not invented.
		slots = {
			slot("you", "Excalibur", "Hacker"),
			slot("bot-normal", "Sword", "Noir"),
			slot("bot-impossible", "Sword", "Noir"),
		},
	})
	if opts.mode ~= "StockFFA" then fail(`an invented mode became {opts.mode}`) end
	if opts.stocks ~= 5 then fail(`stocks of 1e9 became {opts.stocks}, expected a clamp to 5`) end
	if opts.timeLimit ~= 30 then fail(`a negative time became {opts.timeLimit}`) end
	if opts.items ~= false then fail("a non-boolean items field was treated as true") end
	if opts.stage ~= "FoundryFloor" then fail(`an invented stage became {opts.stage}`) end
	if roster[1].weapon ~= "Sword" then fail(`an invented weapon became {roster[1].weapon}`) end
	if roster[1].avatar ~= "Classic" then fail(`an invented avatar became {roster[1].avatar}`) end
	if #roster ~= 2 then
		fail(`an unknown bot level was honoured rather than dropped: {#roster} fighters`)
	end
	checked += 8
end

-- 3. Non-integer and NaN stocks. NaN fails every comparison, including the ones that look like
-- they would catch it, so it needs its own check rather than a clamp.
do
	local _, opts = ok({ mode = "StockFFA", stocks = 2.5, slots = BASE.slots })
	if opts.stocks ~= 3 then fail(`fractional stocks became {opts.stocks}`) end
	local _, o2 = ok({ mode = "StockFFA", stocks = 0 / 0, slots = BASE.slots })
	if o2.stocks ~= 3 then fail(`NaN stocks became {tostring(o2.stocks)}`) end
	if o2.stocks ~= o2.stocks then fail("NaN stocks stayed NaN") end
	checked += 3
end

-- 4. The sender is always the sender. A slot cannot claim to be somebody else, and a config that
-- puts the sender in twice gets one player and one bot rather than two players.
do
	local roster = ok({
		mode = "StockFFA",
		slots = { slot("you", "Sword", "Classic"), slot("you", "Scythe", "Noir") },
	})
	local players = 0
	for _, e in roster do
		if e.player ~= nil then
			players += 1
			if e.player ~= PLAYER then fail("a fighter belongs to someone other than the sender") end
		end
	end
	if players ~= 1 then fail(`{players} slots came back owned by a player`) end
	if roster[2].botLevel == nil then fail("the duplicate slot did not become a bot") end
	checked += 3
end

-- 5. Refusals: only what genuinely cannot be played.
refused(nil, "nil config")
refused("StockFFA", "a string instead of a table")
refused({ mode = "StockFFA" }, "no slots at all")
refused({ mode = "StockFFA", slots = { slot("you", "Sword", "Classic") } }, "one fighter")
refused({ mode = "StockFFA", slots = { slot("bot-easy"), slot("bot-hard") } }, "a match the sender is not in")

-- 6. More slots than the game supports are dropped, not honoured.
do
	local many = {}
	for _ = 1, 12 do
		table.insert(many, slot("bot-easy", "Sword", "Classic"))
	end
	many[1] = slot("you", "Sword", "Classic")
	local roster = ok({ mode = "StockFFA", slots = many })
	if #roster > MatchConfig.MAX_FIGHTERS then
		fail(`twelve slots produced {#roster} fighters, over the cap of {MatchConfig.MAX_FIGHTERS}`)
	end
	checked += 1
end

-- 7. A team match always has two sides. Asking for four fighters all on green is describable and
-- unplayable, so it is split rather than refused.
do
	local roster = ok({
		mode = "StockTeams",
		slots = {
			slot("you", "Sword", "Classic", 0), slot("bot-easy", "Scythe", "Noir", 0),
			slot("bot-easy", "Pike", "Ember", 0), slot("bot-easy", "Axe", "Moss", 0),
		},
	})
	local a, b = 0, 0
	for _, e in roster do
		if e.team == 0 then a += 1 else b += 1 end
	end
	if a == 0 or b == 0 then fail(`a team match came out {a} against {b}`) end
	-- And a team index outside {0,1} does not leak through.
	local r2 = ok({
		mode = "StockTeams",
		slots = { slot("you", "Sword", "Classic", 99), slot("bot-easy", "Scythe", "Noir", 1) },
	})
	for _, e in r2 do
		if e.team ~= 0 and e.team ~= 1 then fail(`team came out as {tostring(e.team)}`) end
	end
	checked += 2
end

-- 8. The default the select screen starts from must itself be a match the server will run. The
-- screen and the validator live on opposite sides of a remote, and a default that fails validation
-- would mean a player who touched nothing and pressed FIGHT got an error.
do
	local roster, opts = ok(MatchConfig.default())
	if #roster ~= 2 then
		fail(`the default config makes {#roster} fighters, expected 2`)
	end
	if roster[1].player ~= PLAYER then fail("the default does not put the sender in the match") end
	if roster[2].botLevel ~= "normal" then fail("the default opponent is not a normal bot") end
	if opts.mode ~= "StockFFA" or opts.stocks ~= 3 then
		fail(`the default survived validation as {opts.mode}/{opts.stocks}`)
	end
	-- And it must come back fresh each time: a shared table would let one player's picks leak
	-- into the next player's screen.
	local a, b = MatchConfig.default(), MatchConfig.default()
	a.slots[1].weaponId = "Hammer"
	if b.slots[1].weaponId ~= "Sword" then
		fail("MatchConfig.default() hands out the same table twice")
	end
	checked += 5
end

print(`checked {checked} config outcomes`)
print("MatchConfig turns anything a client can send into a match the server is willing to run.")
