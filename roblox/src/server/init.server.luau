--!strict
-- Server-owned rooms; match traffic never reaches unrelated lobby players.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net)
local Plaza = require(Shared.Plaza)
local Rooms = require(script.Rooms)
local AvatarStore = require(script.AvatarStore)
local Cabinets = require(script.Cabinets)
local PLAZA = Plaza.DATA
local PLAZA_KIT: any = require(Shared.Data.AvatarKit)
local MatchService = require(script.MatchService)
Players.CharacterAutoLoads = false
local rooms = Rooms.new()
local arcade = Cabinets.new()
local cabinetServices: { [number]: any } = {}
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
	local seat = arcade.seatOf[player.UserId]
	if seat and cabinetServices[seat.n] and cabinetServices[seat.n]:rejoin(player) then return end
	hub(player)
	if room then publish(room) end
end)
Net.remote("RoomAction").OnServerEvent:Connect(function(player: Player, msg: any)
	if not loaded[player.UserId] or type(msg) ~= "table" or not admitted(player, "room", 0.08) then return end
	if msg.action == "leave" then leave(player); hub(player); Net.remote("RoomView"):FireClient(player, { left = true }); return end
	local room, why
	if msg.action == "join" and arcade.seatOf[player.UserId] then
		room, why = nil, "Get up from the cabinet first."
	elseif msg.action == "join" then room, why = rooms:join(player, msg.format)
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
	local seat = arcade.seatOf[player.UserId]
	local service = (room and services[room.id]) or (seat and cabinetServices[seat.n])
	if service then service:receiveInput(player, packed, matchId, epoch) end
end)
Net.remote("Setup").OnServerEvent:Connect(function(player: Player)
	if admitted(player, "hello", 1) then hub(player, "Use a 1v1, 2v2 or 3v3 entrance.") end
end)
local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
-- ---------------------------------------------------------------- the arcade ----
-- Cabinet fights: winner stays. Cabinets.luau decides; this turns its decisions into matches.
local function publishCabinets()
	local views = arcade:views(os.clock())
	for id, player in loaded do
		local room = rooms:get(id)
		if not room then Net.remote("Cabinets"):FireClient(player, views) end
	end
end
local startCabinet
local function endCabinet(n: number, winner: number?)
	local service = cabinetServices[n]
	cabinetServices[n] = nil
	local audience: { any } = if service and service.audience then table.clone(service.audience) else {}
	if service then service:stop() end
	arcade:finish(n, winner)
	for _, p in audience do if loaded[p.UserId] then hub(p) end end
	publishCabinets()
end
startCabinet = function(cab: any)
	local seats = {}
	for _, side in Cabinets.SIDES do if cab.seats[side] then table.insert(seats, cab.seats[side].player) end end
	local roster = {}
	for i, p in seats do
		local prof = rooms:profile(p.UserId)
		table.insert(roster, { player = p, avatar = prof.avatar, weapon = prof.weapon, team = i - 1 })
	end
	if cab.cpu then
		local look = PLAZA_KIT.presets[(cab.number * 3) % #PLAZA_KIT.presets + 1].code
		table.insert(roster, { avatar = look, weapon = "Sword", team = 1, botLevel = "normal" })
	end
	generation += 1
	local service = MatchService.new(table.clone(seats), generation * 1000)
	cabinetServices[cab.number] = service
	service.onFinished = function(_: any, match: any)
		task.wait(6)
		if cabinetServices[cab.number] ~= service or service.match ~= match then return end
		local res = service:results()
		local winner = nil
		local first = res.rows and res.rows[1]
		if first then
			for _, entry in service:roster() do
				if entry.index == first.index then winner = entry.userId end
			end
		end
		endCabinet(cab.number, winner)
	end
	local pool = Rooms.mapPool("ranked")
	local ok, err = pcall(function()
		service:start(roster, { mode = "StockFFA", stocks = 3, stage = pool[math.random(1, #pool)] })
	end)
	if not ok then
		warn(`[Blockfall] cabinet {cab.number} failed to start: {err}`)
		cabinetServices[cab.number] = nil
		for _, p in arcade:cancel(cab.number) do hub(p, "The cabinet failed to start. Please sit down again.") end
	end
	publishCabinets()
end
Net.remote("CabinetAction").OnServerEvent:Connect(function(player: Player, msg: any)
	if not loaded[player.UserId] or type(msg) ~= "table" or not admitted(player, "cabinet", 0.2) then return end
	if rooms:get(player.UserId) then return end
	local action = msg.action
	if action == "sit" then
		local ok, why = arcade:sit(player, msg.cabinet, msg.side, os.clock())
		if not ok then
			Net.remote("Cabinets"):FireClient(player, arcade:views(os.clock()), why)
			return
		end
	elseif action == "stand" then
		arcade:stand(player)
	elseif action == "cpu" then
		local cab = arcade:vsCpu(player)
		if cab then
			startCabinet(cab)
			return
		end
	elseif action == "watch" then
		local n = msg.cabinet
		if arcade:watch(player, n) and cabinetServices[n] then
			if not cabinetServices[n]:addViewer(player) then arcade:stopWatching(player) end
		end
	elseif action == "unwatch" then
		local n = arcade:stopWatching(player)
		if n and cabinetServices[n] then cabinetServices[n]:removeViewer(player) end
		hub(player)
	else
		return
	end
	publishCabinets()
end)

-- Where a player says they are standing. Cosmetic - nothing is decided by it - but everyone else
-- draws it, so it has to be somewhere a player could be: on the floor of the scene they are in
-- (Plaza.walkable, the same test their own walking uses). A position off the floor is ignored and
-- the last good one kept.
Net.remote("HubPose").OnServerEvent:Connect(function(player: Player, pose: any)
	local room = rooms:get(player.UserId)
	local area = if room then room.id else 0
	if not loaded[player.UserId] or (room and room.state == "playing") or type(pose) ~= "table"
		or pose.area ~= area or not admitted(player, "pose", 0.08) or not finite(pose.x) or not finite(pose.z) then return end
	local scene = Plaza.scene(if room then room.format else nil)
	if not Plaza.walkable(scene, pose.x, pose.z) then return end
	poses[player.UserId] = { area = area, x = pose.x, z = pose.z,
		y = if finite(pose.y) then math.clamp(pose.y, 0, 6) else 0, facing = if pose.facing == -1 then -1 else 1,
		moving = pose.moving == true, at = os.clock() }
end)
-- Stamps and quick messages. Both are indices into fixed lists (Data/Plaza), so nothing a player
-- sends this way is free text and nothing needs filtering; the server checks the index, limits the
-- rate, and passes it to the people in the same place - the market, or one room - and no one else.
-- Nobody hears the lobby from inside a fight.
local STAMP_IDS: { [string]: boolean } = {}
for _, st in PLAZA.stamps do STAMP_IDS[st.id] = true end
local function areaOf(id: number): number?
	local room = rooms:get(id)
	if room and room.state == "playing" then return nil end
	return if room then room.id else 0
end
Net.remote("Social").OnServerEvent:Connect(function(player: Player, msg: any)
	if not loaded[player.UserId] or type(msg) ~= "table" then return end
	local kind = msg.kind
	local event: any
	if kind == "stamp" and type(msg.id) == "string" and STAMP_IDS[msg.id] then
		event = { kind = "stamp", id = msg.id }
	elseif kind == "say" and type(msg.index) == "number" and msg.index % 1 == 0 and msg.index >= 1 and msg.index <= #PLAZA.messages then
		event = { kind = "say", index = msg.index }
	else
		return
	end
	local area = areaOf(player.UserId)
	if area == nil or not admitted(player, "social", 1.2) then return end
	event.userId, event.name = player.UserId, player.DisplayName
	for id, other in loaded do
		if areaOf(id) == area then Net.remote("SocialEvent"):FireClient(other, event) end
	end
end)
-- Who is in the lobby, and where: for the member list and "warp to a friend".
Net.remote("Members").OnServerEvent:Connect(function(player: Player)
	if not loaded[player.UserId] or not admitted(player, "members", 0.5) then return end
	local list = {}
	for id, other in loaded do
		local room, pose = rooms:get(id), poses[id]
		local where, place
		if room and room.state == "playing" then
			where, place = `Fighting · {room.format}`, "fight"
		elseif room then
			where, place = `{PLAZA.rooms[room.format].name}`, "room"
		else
			local district = nil
			if pose and pose.area == 0 then
				for _, d in PLAZA.market.districts do
					if pose.x >= d.x1 and pose.x <= d.x2 then district = d end
				end
			end
			where, place = if district then district.name else "Neon Row", "market"
		end
		table.insert(list, { userId = id, name = other.DisplayName, avatar = rooms:profile(id).avatar, where = where, place = place,
			x = if pose and place == "market" then pose.x else nil, z = if pose and place == "market" then pose.z else nil })
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	Net.remote("Members"):FireClient(player, list)
end)
local elapsed, saveClock, cabinetClock = 0, 0, 0
RunService.Heartbeat:Connect(function(dt: number)
	elapsed += dt
	saveClock += dt
	for _, cab in arcade:due(os.clock()) do startCabinet(cab) end
	if saveClock >= 1 then
		saveClock = 0
		task.spawn(function() avatars:tick() end)
	end
	if elapsed < 0.1 then return end
	elapsed = 0
	cabinetClock += 0.1
	if cabinetClock >= 0.5 then
		cabinetClock = 0
		publishCabinets()
	end
	local groups: any = {}
	for id, player in loaded do
		local room, pose = rooms:get(id), poses[id]
		if not room or room.state ~= "playing" then
			local area = if room then room.id else 0
			local scene = Plaza.scene(if room then room.format else nil)
			if pose and pose.area ~= area then pose = nil end
			groups[area] = groups[area] or {}
			local p = rooms:profile(id)
			local entry = { area = area, userId = id, name = player.DisplayName, avatar = p.avatar, weapon = p.weapon,
				x = if pose then pose.x else scene.spawn.x, z = if pose then pose.z else scene.spawn.z, y = if pose then pose.y else 0,
				facing = if pose then pose.facing else 1, moving = pose ~= nil and pose.moving and os.clock() - pose.at < 0.3 }
			-- Seated at a cabinet: at the seat, facing the machine, whatever the client last said.
			local seat = arcade.seatOf[id]
			if seat and area == 0 then
				for _, st in PLAZA.market.stations do
					if st.kind == "Cabinet" and st.cabinet == seat.n and st.id == `Cab{seat.n}{seat.side}` then
						entry.x, entry.z, entry.y, entry.facing, entry.moving = st.x, st.z, 0, st.facing, false
					end
				end
			end
			-- Mid cabinet-fight or watching one: not on the floor.
			local busy = (seat and cabinetServices[seat.n]) or arcade.watching[id]
			if not busy then table.insert(groups[area], entry) end
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
	local cab = arcade:leave(player)
	if cab then
		local service = cabinetServices[cab.number]
		cabinetServices[cab.number] = nil
		local audience: { any } = if service and service.audience then table.clone(service.audience) else {}
		if service then service:stop() end
		arcade:cancel(cab.number)
		for _, p in audience do
			if p ~= player and loaded[p.UserId] then hub(p, "Your opponent left. The fight was called off.") end
		end
	end
	publishCabinets()
	avatars:release(id)
end)
-- A server shutting down writes every unsaved character first.
game:BindToClose(function()
	avatars:flushAll()
end)
