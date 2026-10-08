--!strict
-- Server-owned membership and setup, independent of transport and simulation.
local Shared = game:GetService("ReplicatedStorage").Shared
local Plaza = require(Shared.Plaza)
local Weapons = require(Shared.Data.Weapons)
local Loadout = require(Shared.Loadout)
local AvatarKit = require(Shared.AvatarKit)
local Stages = require(Shared.Data.Stages)
local Rules = require(Shared.Data.Rules)
local Rooms = {}
Rooms.__index = Rooms
-- The room settings a preset sets (see Rooms.presetOf).
local PRESET_KEYS = { "mode", "stocks", "time", "items", "disasters", "mapChoice", "mapSet" }

local BOT_LOOKS = {}
for _, p in (AvatarKit.KIT :: any).presets do
	if p.id ~= "rookie" then table.insert(BOT_LOOKS, p.code) end
end
-- Weapon drops: every fighter brings two weapons, and two different ones. A bot's second is by
-- slot, from everything but its sword, so a room of bots shows the spread of the roster.
local BOT_SECONDS = {}
for _, w in Weapons.LIST do
	if w.id ~= "Sword" then table.insert(BOT_SECONDS, w.id) end
end

-- The player's character changed (the creator saved or they switched): it is cosmetic, so unlike
-- a rules change it un-readies nobody and does not bump the revision - a teammate's ready press
-- in flight must not fail because someone changed their hat.
function Rooms.setAvatar(self: any, player: any, code: string): any
	self:profile(player.UserId).avatar = code
	local room = self:get(player.UserId)
	if room and room.state == "setup" then
		for _, slot in room.slots do
			if slot.player == player then slot.avatar = code end
		end
		return room
	end
	return nil
end

local function invalidate(room: any)
	room.revision += 1
	for _, slot in room.slots do slot.ready = false end
end

-- The bot vote. An empty pedestal's ADD BOT (or a bot's REMOVE) is a proposal anyone in the room
-- can make; every player gets a ballot, the proposer's counted as yes, and a strict majority of the
-- players in the room decides - three players, two yes, the bot is added; two players, both must
-- agree; alone, your own yes is a majority. It closes the moment the result is certain, and fails
-- if it is still open after BOT_VOTE_TIME seconds. One vote at a time per room.
Rooms.BOT_VOTE_TIME = 10

-- The room's way to the fight, in three phases (all inside state "setup"):
--   pick   everyone picks a weapon; it moves on the moment every pedestal is filled and every
--          player is ready, or PICK_TIME seconds after the room fills, with whatever is picked;
--   map    everyone votes for an arena (or Random) for MAP_TIME seconds, or until all have voted;
--          most votes wins, a tie is drawn at random between the tied, no votes is Random;
--   rules  the same, between the rule presets and "keep current", for RULES_TIME seconds.
-- Then the fight starts itself: nobody, the host included, presses start. A player leaving during
-- a vote sends the room back to pick, because it has a pedestal to fill again.
Rooms.PICK_TIME, Rooms.MAP_TIME, Rooms.RULES_TIME = 30, 15, 15
-- What a winning rule set changes (the map is already chosen by then, so not mapChoice/mapSet).
local RULE_KEYS = { "mode", "stocks", "time", "items", "disasters" }

function Rooms.new(): any
	-- `clock` and `rand` are replaceable so the timers and the tie-breaks can be tested
	return setmetatable({ rooms = {}, membership = {}, nextId = 0, profiles = {}, clock = os.clock,
		rand = function(n: number): number return math.random(1, n) end }, Rooms)
end

local function humans(room: any): number
	local n = 0
	for _, slot in room.slots do if slot.player then n += 1 end end
	return n
end

-- Puts a bot in (or takes one out of) slot `i`: the old host-only action, now what a passed vote does.
local function applyBot(room: any, i: number, value: any)
	local slot = room.slots[i]
	slot.bot = value or nil
	-- A bot wears a ready-made character (by slot, so it is stable), which also shows every
	-- player what the kit can do before they open the creator.
	slot.weapon, slot.avatar = "Sword", if value then BOT_LOOKS[(i * 5) % #BOT_LOOKS + 1] else "Classic"
	slot.weapon2 = if value then BOT_SECONDS[(i * 3) % #BOT_SECONDS + 1] else "Hammer"
	invalidate(room)
end

-- Settle the room's vote if its result is certain, or its time is up. Returns true if it closed.
function Rooms.settleVote(self: any, room: any): boolean
	local v = room.botVote
	if not v then return false end
	local slot = room.slots[v.slot]
	-- the slot it was about is no longer what the vote was about: someone took it, or it changed
	if not slot or slot.player or (v.value ~= false) == (slot.bot ~= nil) then
		room.botVote = nil
		return true
	end
	local total, yes, no = humans(room), 0, 0
	for _, slot2 in room.slots do
		if slot2.player then
			local b = v.ballots[slot2.player.UserId]
			if b == true then yes += 1 elseif b == false then no += 1 end
		end
	end
	if yes * 2 > total then
		room.botVote = nil
		room.lastVote = { slot = v.slot, value = v.value, passed = true }
		applyBot(room, v.slot, v.value)
		return true
	end
	if no * 2 >= total or self.clock() >= v.deadline then
		room.botVote = nil
		room.lastVote = { slot = v.slot, value = v.value, passed = false }
		return true
	end
	return false
end

local function full(room: any): boolean
	for _, slot in room.slots do if not slot.player and not slot.bot then return false end end
	return true
end
-- Back to weapon select: votes cleared (the bot vote's too, and its result - after a fight it read
-- "Vote passed: bot added" over a pedestal the fight had emptied), everyone un-readied.
function Rooms.toPick(room: any)
	room.phase, room.phaseEnds = "pick", nil
	room.botVote, room.lastVote = nil, nil
	for _, slot in room.slots do slot.vote, slot.ruleVote = nil, nil end
	invalidate(room)
end
local function enter(self: any, room: any, phase: string, seconds: number)
	room.phase, room.phaseEnds = phase, self.clock() + seconds
	for _, slot in room.slots do
		if phase == "map" then slot.vote = nil else slot.ruleVote = nil end
	end
	room.revision += 1
end
-- The most-voted of the players' ballots in `field`; a tie is drawn by `rand` between the tied
-- (in a fixed order, so the draw is reproducible); nil when nobody voted.
local function winner(self: any, room: any, field: string): string?
	local count: { [string]: number } = {}
	for _, slot in room.slots do
		local b = slot.player and slot[field]
		if b then count[b] = (count[b] or 0) + 1 end
	end
	local best, tied = 0, {}
	for id, n in count do
		if n > best then best, tied = n, { id } elseif n == best then table.insert(tied, id) end
	end
	if #tied == 0 then return nil end
	table.sort(tied)
	return tied[if #tied == 1 then 1 else self.rand(#tied)]
end
-- (A room always has a player in it: the last one leaving deletes it.)
local function allVoted(room: any, field: string): boolean
	for _, slot in room.slots do
		if slot.player and not slot[field] then return false end
	end
	return true
end

-- Move the room on if its phase is over (see PICK_TIME). Returns true if anything changed; the
-- caller resends the room, and starts the fight once `state` is "playing".
function Rooms.advance(self: any, room: any): boolean
	if room.state ~= "setup" then return false end
	local now = self.clock()
	local phase = room.phase or "pick"
	if phase ~= "pick" and not full(room) then
		Rooms.toPick(room)
		return true
	end
	if phase == "pick" then
		if self:canStart(room) or (room.phaseEnds and now >= room.phaseEnds and full(room)) then
			enter(self, room, "map", Rooms.MAP_TIME)
			return true
		end
		if full(room) and not room.phaseEnds then room.phaseEnds = now + Rooms.PICK_TIME; return true end
		if not full(room) and room.phaseEnds then room.phaseEnds = nil; return true end
		return false
	elseif phase == "map" then
		if not (allVoted(room, "vote") or now >= room.phaseEnds) then return false end
		local pick = winner(self, room, "vote") or "Random"
		if pick == "Random" then
			local pool = Rooms.mapPool("all")
			pick = pool[self.rand(#pool)]
		end
		room.stage, room.mapChoice, room.mapResult = pick, "host", pick
		enter(self, room, "rules", Rooms.RULES_TIME)
		return true
	elseif phase == "rules" then
		if not (allVoted(room, "ruleVote") or now >= room.phaseEnds) then return false end
		local pick = winner(self, room, "ruleVote") or "current"
		for _, preset in Rules.presets do
			if preset.id == pick then
				for _, key in RULE_KEYS do room[key] = preset.rules[key] end
			end
		end
		room.ruleResult = pick
		room.phase, room.phaseEnds = "pick", nil
		room.state = "playing"
		room.revision += 1
		return true
	end
	return false
end

-- Close every vote and phase whose time is up. Returns the rooms that changed, for the caller to
-- resend (and to start the fight in, if one now is "playing").
function Rooms.tick(self: any): { any }
	local changed = {}
	for _, room in self.rooms do
		local moved = false
		if room.botVote and self.clock() >= room.botVote.deadline and self:settleVote(room) then moved = true end
		if self:advance(room) then moved = true end
		if moved then table.insert(changed, room) end
	end
	return changed
end
function Rooms.profile(self: any, id: number): any
	if not self.profiles[id] then self.profiles[id] = { weapon = "Sword", weapon2 = "Hammer", avatar = "Classic" } end
	return self.profiles[id]
end
function Rooms.get(self: any, id: number): any
	return self.rooms[self.membership[id]]
end
function Rooms.leave(self: any, player: any): any
	local room = self:get(player.UserId)
	if not room then return nil end
	self.membership[player.UserId] = nil
	for i, slot in room.slots do
		if slot.player == player then room.slots[i] = { team = slot.team } end
	end
	local first = nil
	for _, slot in room.slots do if slot.player then first = first or slot.player.UserId end end
	if not first then self.rooms[room.id] = nil
	elseif room.host == player.UserId then room.host = first end
	invalidate(room)
	if room.botVote then
		room.botVote.ballots[player.UserId] = nil
		self:settleVote(room)
	end
	return room
end
function Rooms.join(self: any, player: any, format: any): (any, string?)
	if self:get(player.UserId) then return self:get(player.UserId), nil end
	local spec = nil
	-- Only a fight format opens a room: the concourse also has the wardrobe, and a client naming
	-- it as a format must not create a room nobody can fight in.
	for _, entry in Plaza.DATA.market.stations do if entry.id == format and entry.kind == "Format" then spec = entry end end
	if not spec then return nil, "Choose 1v1, 2v2 or 3v3." end
	-- Fill the fullest waiting room first, lowest id on a tie. Taking the first open slot in
	-- `pairs` order - which Luau leaves unspecified - could strand people: after a few leaves
	-- there can be two 1v1 rooms each holding one waiting player, and newcomers landed in either
	-- at random, so those two never met. Fullest-first always completes a room before feeding
	-- another, and the choice no longer depends on hash order.
	local room: any, place: number?, bestOpen = nil, nil, math.huge
	for _, candidate in self.rooms do
		if candidate.format == format and candidate.state == "setup" then
			local open, first = 0, nil
			for i, slot in candidate.slots do
				if not slot.player and not slot.bot then
					open += 1
					first = first or i
				end
			end
			if first and (open < bestOpen or (open == bestOpen and candidate.id < room.id)) then
				room, place, bestOpen = candidate, first, open
			end
		end
	end
	if not room then
		self.nextId += 1
		room = { id = self.nextId, host = player.UserId, format = format, name = spec.name,
			state = "setup", revision = 0, stage = "FoundryFloor", stocks = 3, items = true,
			disasters = "off", slots = {},    -- natural disasters: OFF unless the host turns them on
			mapChoice = "host", mapSet = "all", mode = "stock", time = 180, phase = "pick" }
		for i = 1, spec.teamSize * 2 do room.slots[i] = { team = (i - 1) % 2 } end
		self.rooms[room.id], place = room, 1
	end
	local profile = self:profile(player.UserId)
	local slot = room.slots[place]
	slot.player, slot.weapon, slot.weapon2, slot.avatar = player, profile.weapon, profile.weapon2, profile.avatar
	self.membership[player.UserId] = room.id
	invalidate(room)
	-- a newcomer takes a vote's slot (cancelling it) or joins the electorate
	if room.botVote then self:settleVote(room) end
	return room, nil
end
function Rooms.canStart(_self: any, room: any): boolean
	if room.state ~= "setup" then return false end
	for _, slot in room.slots do
		if not slot.player and not slot.bot then return false end
		if slot.player and not slot.ready then return false end
	end
	return true
end
function Rooms.view(self: any, room: any): any
	local slots = {}
	for _, slot in room.slots do
		table.insert(slots, { userId = if slot.player then slot.player.UserId else nil,
			name = if slot.player then slot.player.DisplayName else if slot.bot then "CPU" else "Open · bots off",
			team = slot.team, bot = slot.bot, ready = slot.ready == true, weapon = slot.weapon, weapon2 = slot.weapon2, avatar = slot.avatar,
			vote = slot.vote, ruleVote = slot.ruleVote })
	end
	local vote = nil
	if room.botVote then
		local v = room.botVote
		local ballots, yes, no = {}, 0, 0
		for id, b in v.ballots do
			ballots[tostring(id)] = b
			if b then yes += 1 else no += 1 end
		end
		vote = { slot = v.slot, value = v.value, by = v.by, yes = yes, no = no, voters = humans(room),
			ballots = ballots, left = math.max(0, v.deadline - self.clock()) }
	end
	return { id = room.id, host = room.host, format = room.format, name = room.name,
		state = room.state, revision = room.revision, stage = room.stage, stocks = room.stocks,
		items = room.items, disasters = room.disasters, slots = slots, canStart = self:canStart(room),
		mapChoice = room.mapChoice, mapSet = room.mapSet, mode = room.mode, time = room.time,
		preset = Rooms.presetOf(room), botVote = vote, lastVote = room.lastVote,
		phase = room.phase or "pick", phaseLeft = if room.phaseEnds then math.max(0, room.phaseEnds - self.clock()) else nil,
		mapResult = room.mapResult, ruleResult = room.ruleResult }
end
function Rooms.edit(self: any, player: any, msg: any): (boolean, string?)
	local room = self:get(player.UserId)
	if not room or type(msg) ~= "table" or msg.id ~= room.id then
		return false, "Room changed. Please use the refreshed choices."
	end
	-- The revision guards CONSENT and shared settings: a ready press or a host change made while
	-- looking at an out-of-date room is refused, and a duplicated ready cannot flip twice. Your own
	-- weapon or avatar is an absolute choice about your own slot, so it is exempt - otherwise every
	-- teammate's ready toggle made your loadout change fail with "Room changed".
	local own_loadout = msg.action == "weapon" or msg.action == "weapon2" or msg.action == "avatar" or msg.action == "vote"
		or msg.action == "ballot" or msg.action == "rule"
	if msg.revision ~= room.revision and not own_loadout then
		return false, "Room changed. Please use the refreshed choices."
	end
	if room.state ~= "setup" then return false, "This fight has already started." end
	local own = nil
	for _, slot in room.slots do if slot.player == player then own = slot end end
	if not own then return false, "You are not in this room." end
	local action, value = msg.action, msg.value
	local phase = room.phase or "pick"
	-- Weapons, readiness and bots are the pick phase's; once the votes begin they are locked in.
	if phase ~= "pick" and (action == "ready" or action == "weapon" or action == "weapon2" or action == "bot" or action == "ballot") then
		return false, "Weapons are locked in - the vote is on."
	end
	if action == "ready" then
		own.ready = not own.ready; room.revision += 1; return true, nil
	elseif action == "start" then
		-- Gone: the fight starts itself after the rules vote (see PICK_TIME). Nobody presses start.
		return false, "The fight starts itself after the map and rules votes."
	elseif action == "rule" then
		-- Your ballot in the rules phase: a preset's id, or "current" to keep the room's rules.
		if phase ~= "rules" then return false, "The rules vote has not started." end
		local ok = value == "current"
		for _, preset in Rules.presets do if preset.id == value then ok = true end end
		if not ok then return false, "Unknown rule set." end
		own.ruleVote = value
		room.revision += 1
		return true, nil
	elseif action == "vote" then
		-- Your own ballot: like your loadout it is exempt from the revision check, and unlike the
		-- shared rules it un-readies nobody - a vote changes no-one's consent to the fight. The map
		-- phase is the vote; a room set to "vote" outside it keeps the old standing ballot.
		if phase ~= "map" and room.mapChoice ~= "vote" then return false, "The host picks the map in this room." end
		local set = if phase == "map" then "all" else room.mapSet
		if value ~= "Random" and not (type(value) == "string" and Stages.BY_ID[value] and Rooms.inSet(Stages.BY_ID[value], set)) then
			return false, "Unknown map."
		end
		own.vote = value
		room.revision += 1
		return true, nil
	elseif action == "bot" then
		-- A proposal, not an edit: see BOT_VOTE_TIME. Anyone in the room may make one.
		local i = msg.slot
		if type(i) ~= "number" or i % 1 ~= 0 or i < 1 or i > #room.slots then return false, "Invalid slot." end
		local slot = room.slots[i]
		if slot.player then return false, "Cannot replace a player with a bot." end
		if value ~= false and value ~= "easy" and value ~= "normal" and value ~= "hard" then return false, "Unknown difficulty." end
		if room.botVote then return false, "A bot vote is already running." end
		if value == false and not slot.bot then return false, "There is no bot there." end
		if value ~= false and slot.bot then return false, "There is already a bot there." end
		room.botVote = { slot = i, value = value, by = player.UserId, ballots = { [player.UserId] = true },
			deadline = self.clock() + Rooms.BOT_VOTE_TIME }
		room.lastVote = nil
		self:settleVote(room)
		return true, nil
	elseif action == "ballot" then
		-- Your own ballot on the running bot vote: yes or no, changeable until it closes.
		if not room.botVote then return false, "There is no bot vote running." end
		if type(value) ~= "boolean" then return false, "Vote yes or no." end
		room.botVote.ballots[player.UserId] = value
		self:settleVote(room)
		return true, nil
	elseif action == "weapon" or action == "weapon2" or action == "avatar" then
		-- An avatar is a preset id or a kit code; Loadout.validAvatar hands back the canonical code,
		-- so what is stored is always something every client can draw.
		local clean = if action ~= "avatar" then (if type(value) == "string" and Weapons.BY_ID[value] then value else nil)
			else Loadout.validAvatar(value)
		if not clean then return false, "Unknown loadout." end
		local profile = self:profile(player.UserId)
		if action ~= "avatar" then
			-- Your two weapons are two different ones: picking the one in your other hand swaps them.
			local other = if action == "weapon" then "weapon2" else "weapon"
			if own[other] == clean then
				if not own[action] then return false, "You already have that weapon." end
				own[other] = own[action]; profile[other] = own[action]
			end
		end
		own[action] = clean; profile[action] = clean
	elseif phase ~= "pick" then
		-- The votes decide now: a host change mid-vote would rewrite what "keep current" means, or
		-- (a preset) clear everyone's arena ballots.
		return false, "The room is voting - settings are locked."
	elseif room.host ~= player.UserId then return false, "Only the host can change match settings."
	elseif action == "stage" then
		if value ~= "Random" and (type(value) ~= "string" or not Stages.BY_ID[value]) then return false, "Unknown map." end
		room.stage = value
	elseif action == "mode" then
		local ok = false
		for _, m in Rules.modes do if m.id == value then ok = true end end
		if not ok then return false, "Unknown mode." end
		room.mode = value
	elseif action == "time" then
		if not table.find(Rules.times, value) then return false, "Unknown time limit." end
		room.time = value
	elseif action == "preset" then
		local preset = nil
		for _, p in Rules.presets do if p.id == value then preset = p end end
		if not preset then return false, "Unknown preset." end
		for _, key in PRESET_KEYS do room[key] = preset.rules[key] end
		for _, slot in room.slots do slot.vote = nil end
	elseif action == "mapChoice" then
		if value ~= "host" and value ~= "vote" and value ~= "random" then return false, "Unknown map choice." end
		room.mapChoice = value
		for _, slot in room.slots do slot.vote = nil end
	elseif action == "mapSet" then
		if value ~= "all" and value ~= "ranked" then return false, "Unknown map set." end
		room.mapSet = value
		for _, slot in room.slots do
			if slot.vote and slot.vote ~= "Random" and not Rooms.inSet(Stages.BY_ID[slot.vote], value) then slot.vote = nil end
		end
	elseif action == "stocks" then
		if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > 5 then return false, "Stocks must be 1–5." end
		room.stocks = value
	elseif action == "items" then
		if type(value) ~= "boolean" then return false, "Invalid item setting." end
		room.items = value
	elseif action == "disasters" then
		if value ~= "off" and value ~= "stage" and value ~= "chaos" then return false, "Unknown disaster setting." end
		room.disasters = value
	else return false, "Unknown room action." end
	invalidate(room)
	return true, nil
end
-- The room settings a preset sets, and the one a room currently matches, if any: a preset is
-- a shortcut, not a mode, so changing one setting afterwards simply stops it matching.
function Rooms.presetOf(room: any): string?
	for _, p in Rules.presets do
		local same = true
		for _, key in PRESET_KEYS do
			if room[key] ~= p.rules[key] then same = false end
		end
		if same then return p.id end
	end
	return nil
end

-- Map sets, as on the web setup screen: everything, or the competitive rotation.
function Rooms.inSet(stage: any, set: string?): boolean
	return set ~= "ranked" or stage.ranked == true
end
function Rooms.mapPool(set: string?): { string }
	local out = {}
	for _, stage in Stages.LIST do
		if Rooms.inSet(stage, set) then table.insert(out, stage.id) end
	end
	return out
end
-- The map this fight is played on, decided once, at start. `rand(n)` returns 1..n.
-- Host: the host's pick (Random draws from the set). Random: any map in the set. Vote: one ballot
-- drawn at random, so a map with two votes is twice as likely as a map with one, and a Random
-- ballot becomes any map in the set; with no ballots it falls back to the host's pick.
function Rooms.resolveStage(room: any, rand: (number) -> number): string
	local pool = Rooms.mapPool(room.mapSet)
	local function any(): string return pool[rand(#pool)] end
	local function pick(id: string): string return if id == "Random" then any() else id end
	if room.mapChoice == "random" then return any() end
	if room.mapChoice == "vote" then
		local ballots = {}
		for _, slot in room.slots do
			if slot.vote then table.insert(ballots, slot.vote) end
		end
		if #ballots > 0 then return pick(ballots[rand(#ballots)]) end
	end
	return pick(room.stage)
end
function Rooms.roster(_self: any, room: any, rand: ((number) -> number)?): ({ any }, any)
	local stage = Rooms.resolveStage(room, rand or function(n: number): number return math.random(1, n) end)
	local roster = {}
	for _, slot in room.slots do
		table.insert(roster, { player = slot.player, avatar = slot.avatar, weapon = slot.weapon,
			kit = { slot.weapon, slot.weapon2 or slot.weapon }, team = slot.team, botLevel = slot.bot })
	end
	return roster, { mode = if room.mode == "timed" then "TimedTeams" else "StockTeams", timeLimit = room.time,
		stage = stage, stocks = room.stocks, items = room.items,
		disasters = room.disasters, weaponDrops = true }
end
return Rooms
