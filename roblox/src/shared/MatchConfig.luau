--!strict
-- What a client is allowed to ask for, and what the server will actually run.
--
-- Until now the match was hard-coded on the server: Foundry Floor, Sword, one normal bot. With a
-- select screen the client picks instead, which makes this the first place in the game where a
-- REMOTE DECIDES SOMETHING. So nothing here trusts its argument.
--
-- The rule is sanitise, do not reject. A field that is missing, the wrong type, out of range or
-- simply not a thing gets the default; only a request that could not be turned into a playable
-- match at all is refused. A client that sends rubbish should get an ordinary match, not an error
-- dialogue and not a crashed server thread - and an exploiter who sends `stocks = 1e9` or a weapon
-- id of `"../../etc"` should find it quietly became 3 and Sword.
--
-- The one thing that IS rejected is a roster that cannot make a match: fewer than two fighters, or
-- a request with nobody in it for the player who sent it.

local Stages = require(script.Parent.Data.Stages)
local Weapons = require(script.Parent.Data.Weapons)
local Avatars = require(script.Parent.Data.Avatars)

local MatchConfig = {}

MatchConfig.MODES = { "StockFFA", "TimedFFA", "StockTeams", "TimedTeams" }
MatchConfig.BOT_LEVELS = { "easy", "normal", "hard" }
-- "you" is the player who sent the config. Multiplayer adds more of these; the slice has one.
MatchConfig.SLOT_TYPES = { "you", "bot-easy", "bot-normal", "bot-hard", "off" }

MatchConfig.MIN_FIGHTERS = 2
MatchConfig.MAX_FIGHTERS = 4
MatchConfig.STOCKS = { min = 1, max = 5, default = 3 }
MatchConfig.TIME = { min = 30, max = 600, default = 180 }

local function has(list: { string }, v: any): boolean
	if type(v) ~= "string" then
		return false
	end
	for _, x in list do
		if x == v then
			return true
		end
	end
	return false
end

-- An integer in range, or the default.
--
-- `v % 1 ~= 0` rejects 2.5 AND NaN, which is worth saying because the obvious reading is that NaN
-- needs its own test: NaN fails every comparison, so `v ~= v` looks like the guard that catches it.
-- It is not needed here - `NaN % 1` is NaN, and `NaN ~= 0` is true - and a mutation test proved
-- deleting it changes no output. A guard that cannot fire is not defence, it is something a reader
-- has to work out is pointless.
local function intIn(v: any, lo: number, hi: number, default: number): number
	if type(v) ~= "number" or v % 1 ~= 0 then
		return default
	end
	return math.clamp(v, lo, hi)
end

local function stageIdOr(v: any, default: string): string
	if type(v) == "string" then
		for _, s in Stages.LIST do
			if s.id == v then
				return v
			end
		end
	end
	return default
end

-- The match a player gets before they have chosen anything.
--
-- It lives here rather than in the select screen because the screen and the validator disagreeing
-- about what a default match is would be invisible: the screen would show one thing, the server
-- would run another, and both would look correct on their own. Mirrors _defaultConfig in
-- web/src/ui/menus.js.
function MatchConfig.default(): any
	return {
		mode = "StockFFA", stocks = 3, time = 180, items = true, stageId = "FoundryFloor",
		slots = {
			{ type = "you", weaponId = "Sword", avatarId = "Classic", team = 0 },
			{ type = "bot-normal", weaponId = "Scythe", avatarId = "Noir", team = 1 },
			{ type = "off", weaponId = "Blasters", avatarId = "Ember", team = 0 },
			{ type = "off", weaponId = "Grimoire", avatarId = "Moss", team = 1 },
		},
	}
end

-- Returns (roster, opts) on success, or (nil, nil, reason).
function MatchConfig.sanitise(cfg: any, player: Player): ({ any }?, any?, string?)
	if type(cfg) ~= "table" then
		return nil, nil, "config was not a table"
	end

	local mode = if has(MatchConfig.MODES, cfg.mode) then cfg.mode else "StockFFA"
	local teams = string.find(mode, "Teams") ~= nil

	local slots = cfg.slots
	if type(slots) ~= "table" then
		return nil, nil, "no slots"
	end

	local roster = {}
	local mine = 0
	-- Reading a fixed range rather than walking `slots` is the cap: a client that sends twelve of
	-- them gets the first four looked at and the rest never seen. An explicit break after the
	-- fourth would be unreachable, and a mutation test proved it.
	for i = 1, MatchConfig.MAX_FIGHTERS do
		local sl = slots[i]
		if type(sl) == "table" then
			local kind = if has(MatchConfig.SLOT_TYPES, sl.type) then sl.type else "off"
			if kind ~= "off" then
				local weapon = if type(sl.weaponId) == "string" and Weapons.BY_ID[sl.weaponId]
					then sl.weaponId else Weapons.DEFAULT_ID
				local avatar = if type(sl.avatarId) == "string" and Avatars.BY_ID[sl.avatarId]
					then sl.avatarId else Avatars.DEFAULT_ID
				-- Teams are two-sided; in a free-for-all the team is ignored by Match anyway, and
				-- is set from the slot index so every fighter still has a distinct one.
				local team = if teams then intIn(sl.team, 0, 1, 0) else i - 1

				local entry: any = { avatar = avatar, weapon = weapon, team = team }
				if kind == "you" then
					-- Only ever the player who sent this. A slot claiming to be somebody else is
					-- the obvious thing to try, and there is nothing here to take a name from.
					mine += 1
					if mine == 1 then
						entry.player = player
					else
						entry.botLevel = "normal"   -- a second "you" becomes an ordinary bot
					end
				else
					entry.botLevel = string.sub(kind, 5)
				end
				table.insert(roster, entry)
			end
		end
	end

	if mine == 0 then
		return nil, nil, "the player who asked for this match is not in it"
	end
	if #roster < MatchConfig.MIN_FIGHTERS then
		return nil, nil, `a match needs at least {MatchConfig.MIN_FIGHTERS} fighters`
	end
	-- A team match with everyone on one side has nobody to fight. Rather than refuse, split it:
	-- the request is playable, it was just described badly.
	if teams then
		local a, b = 0, 0
		for _, e in roster do
			if e.team == 0 then a += 1 else b += 1 end
		end
		if a == 0 or b == 0 then
			for i, e in roster do
				e.team = (i - 1) % 2
			end
		end
	end

	local opts = {
		mode = mode,
		stage = stageIdOr(cfg.stageId, "FoundryFloor"),
		stocks = intIn(cfg.stocks, MatchConfig.STOCKS.min, MatchConfig.STOCKS.max, MatchConfig.STOCKS.default),
		timeLimit = intIn(cfg.time, MatchConfig.TIME.min, MatchConfig.TIME.max, MatchConfig.TIME.default),
		items = cfg.items == true,
	}
	return roster, opts, nil
end

return MatchConfig
