--!strict
-- Server-owned rooms; match traffic never reaches unrelated lobby players.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net)
local Hub = require(Shared.Data.Hub)
local Rooms = require(script.Rooms)
local AvatarStore = require(script.AvatarStore)
local MatchService = require(script.MatchService)
Players.CharacterAutoLoads = false
local rooms = Rooms.new()
-- Saved characters. GetDataStore itself can fail (no DataStore service in a local test server);
-- the store then runs session-only rather than taking the lobby down with it.
local okStore, dataStore = pcall(function()
	return game:GetService("DataStoreService"):GetDataStore("BlockfallCharacters1")
end)
local avatars = AvatarStore.new(if okStore then dataStore else nil)
avatars.wait = function(n: number) task.wait(n) end
local services: any = {}
local poses: any = {}
local limits: any = {}
local loaded: any = {}
local generation = 0
local function admitted(player: Player, lane: string, interval: number): boolean
	local id, now = player.UserId, os.clock()
	limits[id] = limits[id] or {}
	if now < (limits[id][lane] or 0) then return false end
	limits[id][lane] = now + interval
	return true
end
local function members(room: any): { Player }
	local list = {}
	for _, slot in room.slots do if slot.player then table.insert(list, slot.player) end end
	return list
end
local function publish(room: any)
	for _, player in members(room) do Net.remote("RoomView"):FireClient(player, rooms:view(room)) end
end
local function hub(player: Player, why: string?)
	poses[player.UserId] = nil
	local profile = rooms:profile(player.UserId)
	Net.remote("Select"):FireClient(player, { ready = true, error = why,
		last = { slots = { { avatarId = profile.avatar, weaponId = profile.weapon } } } })
end
local function resetRoom(room: any, why: string?)
	local service = services[room.id]
	if service then service:stop(); services[room.id] = nil end
	room.state, room.revision = "setup", room.revision + 1
	for _, slot in room.slots do slot.bot, slot.ready = nil, false end
	for _, player in members(room) do hub(player, why) end
	publish(room)
end
local function leave(player: Player)
	local room = rooms:leave(player)
	if not room then return end
	if room.state == "playing" then resetRoom(room, "A player left. Fight cancelled; ready up again.")
	else publish(room) end
end
-- Player objects that have left, weakly held: a Hello that yielded on the DataStore must not put a
-- departed player back into the lobby. By object, not user id, so a rejoin is a fresh start.
local departed: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function sendAvatars(player: Player, why: string?)
	local view = avatars:view(player.UserId)
	view.error = why
	Net.remote("AvatarView"):FireClient(player, view)
end
Net.remote("Hello").OnServerEvent:Connect(function(player: Player)
	if not admitted(player, "hello", 1) then return end
	-- Their saved character before anything shows them: the hub, the room and the roster all read
	-- the profile's avatar. load() yields on the DataStore and is cached after the first time.
	rooms:profile(player.UserId).avatar = avatars:active(player.UserId)
	if departed[player] then return end      -- left while the DataStore was answering
	loaded[player.UserId] = player
	sendAvatars(player)
	local room = rooms:get(player.UserId)
	if room and services[room.id] and services[room.id]:rejoin(player) then return end
	hub(player)
	if room then publish(room) end
end)
Net.remote("RoomAction").OnServerEvent:Connect(function(player: Player, msg: any)
	if not loaded[player.UserId] or type(msg) ~= "table" or not admitted(player, "room", 0.08) then return end
	if msg.action == "leave" then leave(player); hub(player); Net.remote("RoomView"):FireClient(player, { left = true }); return end
	local room, why
	if msg.action == "join" then room, why = rooms:join(player, msg.format)
	else
		room = rooms:get(player.UserId)
		local ok
		ok, why = rooms:edit(player, msg)
		if not ok then
			local view = if room then rooms:view(room) else { left = true }
			view.error = why
			Net.remote("RoomView"):FireClient(player, view)
			return
		end
	end
	if not room then Net.remote("RoomView"):FireClient(player, { left = true, error = why }); return end
	publish(room)
	if msg.action == "start" then
		generation += 1
		local service = MatchService.new(members(room), generation * 1000)
		services[room.id] = service
		service.onFinished = function(_: any, match: any)
			task.wait(6)
			if services[room.id] == service and service.match == match then resetRoom(room) end
		end
		local roster, opts = rooms:roster(room)
		local ok, err = pcall(function() service:start(roster, opts) end)
		if not ok then warn(`[Blockfall] room launch failed: {err}`); resetRoom(room, "Arena failed to load. Please try again.") end
	end
end)
Net.remote("Avatar").OnServerEvent:Connect(function(player: Player, msg: any)
	if not loaded[player.UserId] or not admitted(player, "avatar", 0.15) then return end
	local ok, why = avatars:apply(player.UserId, msg)
	if ok then
		local room = rooms:setAvatar(player, avatars:active(player.UserId))
		if room then publish(room) end
	end
	sendAvatars(player, why)
end)
Net.remote("Input").OnServerEvent:Connect(function(player: Player, packed: any, matchId: any, epoch: any)
	local room = rooms:get(player.UserId)
	local service = room and services[room.id]
	if service then service:receiveInput(player, packed, matchId, epoch) end
end)
Net.remote("Setup").OnServerEvent:Connect(function(player: Player)
	if admitted(player, "hello", 1) then hub(player, "Use a 1v1, 2v2 or 3v3 entrance.") end
end)
local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
Net.remote("HubPose").OnServerEvent:Connect(function(player: Player, pose: any)
	local room = rooms:get(player.UserId)
	local area = if room then room.id else 0
	if not loaded[player.UserId] or (room and room.state == "playing") or type(pose) ~= "table"
		or pose.area ~= area or not admitted(player, "pose", 0.08) or not finite(pose.x) or not finite(pose.y) then return end
	local scene = if room then Hub.rooms[room.format] else Hub
	poses[player.UserId] = { area = area, x = math.clamp(pose.x, scene.main.x1 + 3, scene.main.x2 - 3),
		y = math.clamp(pose.y, 0, 60), facing = if pose.facing == -1 then -1 else 1,
		moving = pose.moving == true, at = os.clock() }
end)
local elapsed, saveClock = 0, 0
RunService.Heartbeat:Connect(function(dt: number)
	elapsed += dt
	saveClock += dt
	if saveClock >= 1 then
		saveClock = 0
		task.spawn(function() avatars:tick() end)
	end
	if elapsed < 0.1 then return end
	elapsed = 0
	local groups: any = {}
	for id, player in loaded do
		local room, pose = rooms:get(id), poses[id]
		if not room or room.state ~= "playing" then
			local area = if room then room.id else 0
			local scene = if room then Hub.rooms[room.format] else Hub
			if pose and pose.area ~= area then pose = nil end
			groups[area] = groups[area] or {}
			local p = rooms:profile(id)
			table.insert(groups[area], { area = area, userId = id, name = player.DisplayName, avatar = p.avatar, weapon = p.weapon,
				x = if pose then pose.x else scene.spawn.x, y = if pose then pose.y else scene.spawn.y,
				facing = if pose then pose.facing else 1, moving = pose ~= nil and pose.moving and os.clock() - pose.at < 0.3 })
		end
	end
	for id, player in loaded do
		local room = rooms:get(id)
		if not room or room.state ~= "playing" then
			Net.remote("HubPresence"):FireClient(player, groups[if room then room.id else 0] or {})
		end
	end
end)
Players.PlayerRemoving:Connect(function(player: Player)
	leave(player)
	local id = player.UserId
	loaded[id], poses[id], limits[id], rooms.profiles[id] = nil, nil, nil, nil
	departed[player] = true
	avatars:release(id)
end)
-- A server shutting down writes every unsaved character first.
game:BindToClose(function()
	avatars:flushAll()
end)
