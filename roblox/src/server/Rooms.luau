--!strict
-- Server-owned membership and setup, independent of transport and simulation.
local Shared = game:GetService("ReplicatedStorage").Shared
local Hub = require(Shared.Data.Hub)
local Weapons = require(Shared.Data.Weapons)
local Avatars = require(Shared.Data.Avatars)
local Stages = require(Shared.Data.Stages)
local Rooms = {}
Rooms.__index = Rooms

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
	for _, entry in Hub.stations do if entry.id == format then spec = entry end end
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
			state = "setup", revision = 0, stage = "FoundryFloor", stocks = 3, items = true, slots = {} }
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
			team = slot.team, bot = slot.bot, ready = slot.ready == true, weapon = slot.weapon, avatar = slot.avatar })
	end
	return { id = room.id, host = room.host, format = room.format, name = room.name,
		state = room.state, revision = room.revision, stage = room.stage, stocks = room.stocks,
		items = room.items, slots = slots, canStart = self:canStart(room) }
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
	local own_loadout = msg.action == "weapon" or msg.action == "avatar"
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
	elseif action == "weapon" or action == "avatar" then
		local catalog = if action == "weapon" then Weapons.BY_ID else Avatars.BY_ID
		if type(value) ~= "string" or not catalog[value] then return false, "Unknown loadout." end
		own[action] = value; self:profile(player.UserId)[action] = value
	elseif room.host ~= player.UserId then return false, "Only the host can change match settings."
	elseif action == "stage" then
		if type(value) ~= "string" or not Stages.BY_ID[value] then return false, "Unknown map." end
		room.stage = value
	elseif action == "stocks" then
		if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > 5 then return false, "Stocks must be 1–5." end
		room.stocks = value
	elseif action == "items" then
		if type(value) ~= "boolean" then return false, "Invalid item setting." end
		room.items = value
	elseif action == "bot" then
		local i = msg.slot
		if type(i) ~= "number" or i % 1 ~= 0 or i < 1 or i > #room.slots then return false, "Invalid slot." end
		local slot = room.slots[i]
		if slot.player then return false, "Cannot replace a player with a bot." end
		if value ~= false and value ~= "easy" and value ~= "normal" and value ~= "hard" then return false, "Unknown difficulty." end
		slot.bot = value or nil
		slot.weapon, slot.avatar = "Sword", "Classic"
	else return false, "Unknown room action." end
	invalidate(room)
	return true, nil
end
function Rooms.roster(_self: any, room: any): ({ any }, any)
	local roster = {}
	for _, slot in room.slots do
		table.insert(roster, { player = slot.player, avatar = slot.avatar, weapon = slot.weapon,
			team = slot.team, botLevel = slot.bot })
	end
	return roster, { mode = "StockTeams", stage = room.stage, stocks = room.stocks, items = room.items }
end
return Rooms
