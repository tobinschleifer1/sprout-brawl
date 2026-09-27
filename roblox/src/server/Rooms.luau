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

function Rooms.new(): any
	return setmetatable({ rooms = {}, membership = {}, nextId = 0, profiles = {} }, Rooms)
end
function Rooms.profile(self: any, id: number): any
	if not self.profiles[id] then self.profiles[id] = { weapon = "Sword", avatar = "Classic" } end
	return self.profiles[id]
end
function Rooms.get(self: any, id: number): any
	return self.rooms[self.membership[id]]
end
local function invalidate(room: any)
	room.revision += 1
	for _, slot in room.slots do slot.ready = false end
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
			mapChoice = "host", mapSet = "all", mode = "stock", time = 180 }
		for i = 1, spec.teamSize * 2 do room.slots[i] = { team = (i - 1) % 2 } end
		self.rooms[room.id], place = room, 1
	end
	local profile = self:profile(player.UserId)
	local slot = room.slots[place]
	slot.player, slot.weapon, slot.avatar = player, profile.weapon, profile.avatar
	self.membership[player.UserId] = room.id
	invalidate(room)
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
			team = slot.team, bot = slot.bot, ready = slot.ready == true, weapon = slot.weapon, avatar = slot.avatar,
			vote = slot.vote })
	end
	return { id = room.id, host = room.host, format = room.format, name = room.name,
		state = room.state, revision = room.revision, stage = room.stage, stocks = room.stocks,
		items = room.items, disasters = room.disasters, slots = slots, canStart = self:canStart(room),
		mapChoice = room.mapChoice, mapSet = room.mapSet, mode = room.mode, time = room.time,
		preset = Rooms.presetOf(room) }
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
	local own_loadout = msg.action == "weapon" or msg.action == "avatar" or msg.action == "vote"
	if msg.revision ~= room.revision and not own_loadout then
		return false, "Room changed. Please use the refreshed choices."
	end
	if room.state ~= "setup" then return false, "This fight has already started." end
	local own = nil
	for _, slot in room.slots do if slot.player == player then own = slot end end
	if not own then return false, "You are not in this room." end
	local action, value = msg.action, msg.value
	if action == "ready" then
		own.ready = not own.ready; room.revision += 1; return true, nil
	elseif action == "start" then
		if room.host ~= player.UserId or not self:canStart(room) then return false, "Fill both teams and ready every player first." end
		room.state = "playing"; room.revision += 1; return true, nil
	elseif action == "vote" then
		-- Your own ballot: like your loadout it is exempt from the revision check, and unlike the
		-- shared rules it un-readies nobody - a vote changes no-one's consent to the fight.
		if room.mapChoice ~= "vote" then return false, "The host picks the map in this room." end
		if value ~= "Random" and not (type(value) == "string" and Stages.BY_ID[value] and Rooms.inSet(Stages.BY_ID[value], room.mapSet)) then
			return false, "Unknown map."
		end
		own.vote = value
		room.revision += 1
		return true, nil
	elseif action == "weapon" or action == "avatar" then
		-- An avatar is a preset id or a kit code; Loadout.validAvatar hands back the canonical code,
		-- so what is stored is always something every client can draw.
		local clean = if action == "weapon" then (if type(value) == "string" and Weapons.BY_ID[value] then value else nil)
			else Loadout.validAvatar(value)
		if not clean then return false, "Unknown loadout." end
		own[action] = clean; self:profile(player.UserId)[action] = clean
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
	elseif action == "bot" then
		local i = msg.slot
		if type(i) ~= "number" or i % 1 ~= 0 or i < 1 or i > #room.slots then return false, "Invalid slot." end
		local slot = room.slots[i]
		if slot.player then return false, "Cannot replace a player with a bot." end
		if value ~= false and value ~= "easy" and value ~= "normal" and value ~= "hard" then return false, "Unknown difficulty." end
		slot.bot = value or nil
		-- A bot wears a ready-made character (by slot, so it is stable), which also shows every
		-- player what the kit can do before they open the creator.
		slot.weapon, slot.avatar = "Sword", if value then BOT_LOOKS[(i * 5) % #BOT_LOOKS + 1] else "Classic"
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
			team = slot.team, botLevel = slot.bot })
	end
	return roster, { mode = if room.mode == "timed" then "TimedTeams" else "StockTeams", timeLimit = room.time,
		stage = stage, stocks = room.stocks, items = room.items,
		disasters = room.disasters }
end
return Rooms
