--!strict
-- Server-owned rooms; match traffic never reaches unrelated lobby players.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net)
local Plaza = require(Shared.Plaza)
local PresenceCodec = require(Shared.PresenceCodec)
local Rooms = require(script.Rooms)
local AvatarStore = require(script.AvatarStore)
local ClimbProgress = require(script.ClimbProgress)
local ClimbBoards = require(script.ClimbBoards)
local Purchases = require(script.Purchases)
local SkipProducts = require(Shared.SkipProducts)
local PARKOUR: any = require(Shared.Data.Parkour)
local PLAZA = Plaza.DATA
local MatchService = require(script.MatchService)
local Locker = require(script.Locker)
local Mint = require(script.Mint)
local Passes = require(script.Passes)
local Shop = require(script.Shop)
local Products = require(Shared.Products)
local Economy = require(script.Economy)
Players.CharacterAutoLoads = false
local rooms = Rooms.new()
-- Saved characters. GetDataStore itself can fail (no DataStore service in a local test server);
-- the store then runs session-only rather than taking the lobby down with it.
local okStore, dataStore = pcall(function()
	return game:GetService("DataStoreService"):GetDataStore("BlockfallCharacters1")
end)
local avatars = AvatarStore.new(if okStore then dataStore else nil, nil, { sessionOnly = RunService:IsStudio() })
-- Cosmetics owned and worn (Locker); every match reads what a player wears from here.
local locker = Locker.new({ store = avatars, studio = RunService:IsStudio() })
MatchService.cosmeticsFor = function(player: Player) return locker:loadout(player.UserId) end
if RunService:IsStudio() then MatchService.botCosmetics = Locker.botLoadout end
-- Serials and copies in existence (Mint), and earning things (Economy): drops, crates, crafting.
local okMint, mintStore = pcall(function()
	return game:GetService("DataStoreService"):GetDataStore("BlockfallMint1")
end)
local mint = Mint.new(if okMint then mintStore else nil, nil, RunService:IsStudio())
-- Roblox's paid random items policy, per player: asked once a session; unknown or failed is restricted.
local restrictedFor: { [number]: boolean } = {}
local function restricted(userId: number): boolean
	if restrictedFor[userId] == nil then
		local player = Players:GetPlayerByUserId(userId)
		if not player then return true end
		local ok, policy = pcall(function() return game:GetService("PolicyService"):GetPolicyInfoForPlayerAsync(player) end)
		if not ok or type(policy) ~= "table" then return true end      -- asked again next time
		restrictedFor[userId] = policy.ArePaidRandomItemsRestricted ~= false
	end
	return restrictedFor[userId]
end
-- Game passes (Passes; in Studio every available one is owned), and the shop (Shop).
local MarketplaceService = game:GetService("MarketplaceService")
local passes = Passes.new({ market = MarketplaceService, studio = RunService:IsStudio() })
avatars.wardrobe = function(userId: number) return passes:owns(userId, "wardrobe") end
-- Clothing is worn only by its owner (AvatarStore: on save, and every time a character is used).
avatars.owns = function(userId: number, id: string): boolean return locker:owns(userId, id) end
locker.vip = function(userId: number) return passes:owns(userId, "vip") end
local economy = Economy.new({ store = avatars, mint = mint,
	paidAllowed = function(userId: number): boolean return not restricted(userId) end,
	vip = function(userId: number): boolean return passes:owns(userId, "vip") end })
local shop = Shop.new({ economy = economy, passes = passes, restricted = restricted })
-- the weapons a player may pick, and whether Ranked is open to them, go by their saved level
rooms.levelOf = function(userId: number): number return economy:level(userId) end
local loaded: any = {}
local function sendEconomy(player: Player, event: any?)
	if loaded[player.UserId] ~= player then return end
	local view = economy:view(player.UserId)
	view.shop = shop:view(player.UserId)
	view.event = event
	Net.remote("EconomyView"):FireClient(player, view)
end
-- VIP shows: a gold name and a [VIP] chat tag, read by every client from this attribute.
local function markVip(player: Player)
	local vip = passes:owns(player.UserId, "vip")
	pcall(function() player:SetAttribute("VIP", vip) end)       -- (a test's stand-in player has no attributes)
end
avatars.wait = function(n: number) task.wait(n) end
local climbs = ClimbProgress.new(avatars, #PARKOUR.course.checkpoints)
-- The climb's leaderboards, shared by every server and re-read every two hours (ClimbBoards). No
-- ordered stores (a local test server): the boards say they are offline.
local okBoards, fastest, highest = pcall(function()
	local service = game:GetService("DataStoreService")
	return service:GetOrderedDataStore("BlockfallClimbFastest1"), service:GetOrderedDataStore("BlockfallClimbHighest1")
end)
local boards = ClimbBoards.new({ speed = if okBoards then fastest else nil, levels = if okBoards then highest else nil,
	clock = os.time, name = function(userId: number) return Players:GetNameFromUserIdAsync(userId) end })
local services: any = {}
local launchRoom: (any) -> ()      -- defined beside RoomAction; the tick uses it too
local poses: any = {}
local limits: any = {}
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
-- Everyone queued for `format` sees the queue's new count.
local function sendQueue(format: string?)
	if not format or not rooms.queues or not rooms.queues[format] then return end
	for _, p in rooms.queues[format] do
		Net.remote("QueueView"):FireClient(p, rooms:queueView(p.UserId))
	end
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
	Rooms.toPick(room)             -- back to weapon select: the next fight votes its map and rules again
	for _, player in members(room) do hub(player, why) end
	publish(room)
end
local function leave(player: Player)
	local room = rooms:leave(player)
	if not room then return end
	if room.state == "playing" then resetRoom(room, "A player left. Fight cancelled; ready up again.")
	else rooms:advance(room); publish(room) end
end
-- Player objects that have left, weakly held: a Hello that yielded on the DataStore must not put a
-- departed player back into the lobby. By object, not user id, so a rejoin is a fresh start.
local departed: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any
-- The lobby roster each player was last sent (PresenceCodec.signature): it goes again only on change.
local presenceSig: { [number]: string } = {}
local function sendAvatars(player: Player, why: string?)
	local view = avatars:view(player.UserId)
	view.error = why
	Net.remote("AvatarView"):FireClient(player, view)
end
local helloBusy: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any
Net.remote("Hello").OnServerEvent:Connect(function(player: Player)
	if departed[player] or helloBusy[player] or not admitted(player, "hello", 1) then return end
	helloBusy[player] = true
	-- Their saved character before anything shows them: the hub, the room and the roster all read
	-- the profile's avatar. load() yields on the DataStore and is cached after the first time.
	rooms:profile(player.UserId).avatar = avatars:active(player.UserId)
	helloBusy[player] = nil
	if departed[player] then return end      -- left while the DataStore was answering
	loaded[player.UserId] = player
	presenceSig[player.UserId] = nil         -- a (re)loaded client has no roster yet
	sendAvatars(player)
	markVip(player)
	shop:grantPassItems(player.UserId)
	Net.remote("LockerView"):FireClient(player, locker:view(player.UserId))
	sendEconomy(player)
	local climbView = climbs:view(player.UserId)
	Net.remote("ClimbView"):FireClient(player, climbView)
	Net.remote("ClimbBoards"):FireClient(player, boards:view())
	-- A record set before the boards existed, or on a server whose write never landed.
	boards:submit(player.UserId, climbView)
	local room = rooms:get(player.UserId)
	if room and services[room.id] and services[room.id]:rejoin(player) then return end
	hub(player)
	if room then publish(room) end
end)
-- The fight a room's votes have just finished choosing: started once, when its state turns to
-- "playing" (after the rules vote - Rooms.advance), whether by a ballot or by the clock.
launchRoom = function(room: any)
	if room.state ~= "playing" or services[room.id] then return end
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
Net.remote("RoomAction").OnServerEvent:Connect(function(player: Player, msg: any)
	if not loaded[player.UserId] or type(msg) ~= "table" or not admitted(player, "room", 0.08) then return end
	if msg.action == "leave" then leave(player); hub(player); Net.remote("RoomView"):FireClient(player, { left = true }); return end
	local room, why
	if msg.action == "queue" then
		-- PLAY: into the queue for a format; anyone it seats goes straight into their room
		local changed
		changed, why = rooms:queue(player, msg.format)
		sendQueue(msg.format)
		Net.remote("QueueView"):FireClient(player, rooms:queueView(player.UserId), why)
		for _, r in changed or {} do rooms:advance(r); publish(r); launchRoom(r) end
		return
	elseif msg.action == "unqueue" then
		local format = rooms:dequeue(player)
		Net.remote("QueueView"):FireClient(player, rooms:queueView(player.UserId))
		if format then sendQueue(format) end
		return
	elseif msg.action == "fill" then
		-- FILL WITH BOTS: the queue for this player's format into a room now, bots in the rest
		local format = rooms:queued(player.UserId)
		room, why = rooms:fillWithBots(player)
		if format then sendQueue(format) end
		Net.remote("QueueView"):FireClient(player, rooms:queueView(player.UserId), why)
		if not room then return end
	elseif msg.action == "join" then
		-- (gone: the gates are; a fight is found through PLAY's queue)
		room, why = nil, "Press PLAY to find a fight."
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
	rooms:advance(room)            -- everyone ready, everyone voted: the room moves on (Rooms.PICK_TIME)
	publish(room)
	launchRoom(room)
end)
-- a finished match counts toward the player's drop meter; a drop arrives with its results
MatchService.onPlayerResult = function(userId: number, results: any, row: any)
	local player = loaded[userId]
	if not player then return end
	while avatars.busy[userId] and loaded[userId] == player do task.wait() end
	if loaded[userId] ~= player then return end
	local out = economy:matchFinished(userId, results, row)
	if loaded[userId] ~= player then return end
	sendEconomy(player, { match = out })
	if out.drop and out.drop.kind == "item" then Net.remote("LockerView"):FireClient(player, locker:view(userId)) end
end
Net.remote("Economy").OnServerEvent:Connect(function(player: Player, msg: any)
	if loaded[player.UserId] ~= player or not admitted(player, "economy", 0.25) then return end
	local ok, res = economy:apply(player.UserId, msg)
	if loaded[player.UserId] ~= player then return end
	sendEconomy(player, if ok then { done = type(msg) == "table" and msg.action, result = res } else { error = res })
	if ok then Net.remote("LockerView"):FireClient(player, locker:view(player.UserId)) end
end)
Net.remote("Locker").OnServerEvent:Connect(function(player: Player, msg: any)
	if loaded[player.UserId] ~= player or not admitted(player, "locker", 0.15) then return end
	local _, why = locker:apply(player.UserId, msg)
	local view = locker:view(player.UserId)
	view.error = why
	Net.remote("LockerView"):FireClient(player, view)
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
-- `view`: the snapshot frame the client was drawing, for lag compensation (MatchService.start)
Net.remote("Input").OnServerEvent:Connect(function(player: Player, packed: any, matchId: any, epoch: any, view: any)
	local room = rooms:get(player.UserId)
	local service = room and services[room.id]
	if service then service:receiveInput(player, packed, matchId, epoch, view) end
end)
Net.remote("Setup").OnServerEvent:Connect(function(player: Player)
	if admitted(player, "hello", 1) then hub(player, "Press PLAY to find a fight.") end
end)
local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
-- ---------------------------------------------------------------- the Skyline Climb ----
-- The climb runs on the client; the server keeps progress and refuses claims no climber could make
-- (ClimbProgress). A climber is off the lobby floor until they come back.
Net.remote("Climb").OnServerEvent:Connect(function(player: Player, msg: any)
	local id = player.UserId
	if not loaded[id] or type(msg) ~= "table" or not admitted(player, "climb", 0.2) then return end
	local now = os.clock()
	if msg.action == "enter" then
		if rooms:get(id) then return end
		local start = climbs:enter(id, msg.from, now)
		local view = climbs:view(id)
		view.start = start
		Net.remote("ClimbView"):FireClient(player, view)
		return
	elseif msg.action == "leave" then
		climbs:leave(id)
	elseif msg.action == "checkpoint" then
		if not climbs:checkpoint(id, msg.index, now) then return end
	elseif msg.action == "summit" then
		if not climbs:summit(id, msg.frames, now) then return end
	elseif msg.action == "studioSkip" then
		-- A free skip, for testing the course in Studio before its Developer Products exist. The same
		-- one-checkpoint skip a purchase makes (so it counts the same: resumed from, never climbed).
		-- Never on a live server: RunService:IsStudio() is false there, and this does nothing.
		if not RunService:IsStudio() or not climbs:climbing(id) then return end
		local to = climbs:skip(id, now)
		if not to then return end
		local view = climbs:view(id)
		view.skipTo = to
		Net.remote("ClimbView"):FireClient(player, view)
		return
	elseif msg.action == "reward" then
		-- A pickup at the top of the climb: granted only where it lies, to someone who climbed there
		-- (ClimbProgress.reward). Its avatar part is then theirs to wear - the creator is told.
		local r = climbs:reward(id, msg.id, PARKOUR.course.rewards)
		if not r then return end
		local view = climbs:view(id)
		view.earned = r.id
		Net.remote("ClimbView"):FireClient(player, view)
		sendAvatars(player)
		return
	else
		return
	end
	local view = climbs:view(id)
	boards:submit(id, view)
	Net.remote("ClimbView"):FireClient(player, view)
end)
-- ---------------------------------------------------------------- purchases ----
-- Paid skips on the climb (SkipProducts): one checkpoint on from where the player is, saved as
-- where they resume. Purchases applies a receipt once and grants it only once saved. A product id
-- of 0 is one not created yet in the Creator Dashboard: nothing is registered, nothing sold.
-- Every purchase id ever granted, one key each (Purchases), beyond the record's own last fifty.
local okReceipts, receiptStore = pcall(function()
	return game:GetService("DataStoreService"):GetDataStore("BlockfallReceipts1")
end)
local purchases = Purchases.new({ store = avatars, player = function(userId: number) return loaded[userId] end,
	receipts = if okReceipts then receiptStore else nil })
for index, productId in SkipProducts.IDS do
	if productId ~= 0 then
		purchases:on(productId, function(player: Player, receipt: any): boolean
			local id = player.UserId
			local to = climbs:skip(id, os.clock())
			if not to then
				-- Already at the Summit (it raced a climb). Paid for and nothing to move; granted,
				-- since asking Roblox again would not change that.
				warn(`[Blockfall] {id} bought a skip at the Summit (purchase {receipt.PurchaseId})`)
				return true
			end
			if to ~= index then
				warn(`[Blockfall] {id} bought the skip into {index} and was moved into {to}: one checkpoint on, always`)
			end
			local view = climbs:view(id)
			if climbs:climbing(id) then view.skipTo = to end
			Net.remote("ClimbView"):FireClient(player, view)     -- the boards: unchanged, a skip is not climbing
			return true
		end)
	end
end
-- The shop's products: Forge Key bundles, the featured shop's tiers, clothing tiers and packs
-- (Products; ids of 0 are not created yet and register nothing). Every grant is once per purchase
-- id, in the record's own write.
local function onShopReceipt(player: Player, receipt: any): boolean
	local ok, res = shop:receipt(player.UserId, receipt.ProductId, tostring(receipt.PurchaseId))
	if ok and loaded[player.UserId] == player then
		sendEconomy(player, { purchased = res })
		Net.remote("LockerView"):FireClient(player, locker:view(player.UserId))
		sendAvatars(player)        -- clothing bought can be worn in the Character Studio
	end
	return ok
end
for _, b in Products.KEYS do if b.id ~= 0 then purchases:on(b.id, onShopReceipt) end end
for _, t in Products.FEATURED do if t.id ~= 0 then purchases:on(t.id, onShopReceipt) end end
for _, t in Products.CLOTHING do if t.id ~= 0 then purchases:on(t.id, onShopReceipt) end end
for _, t in Products.PACKS do if t.id ~= 0 then purchases:on(t.id, onShopReceipt) end end
Net.remote("Shop").OnServerEvent:Connect(function(player: Player, msg: any)
	if loaded[player.UserId] ~= player or not admitted(player, "shop", 0.25) then return end
	local ok, event = shop:request(player.UserId, msg)
	if loaded[player.UserId] ~= player then return end
	sendEconomy(player, if ok then event else { error = event })
	if ok and event.purchased then
		Net.remote("LockerView"):FireClient(player, locker:view(player.UserId))
		sendAvatars(player)
	end
end)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
	if not purchased or loaded[player.UserId] ~= player then return end
	local id = passes:bought(player.UserId, passId)
	if not id then return end
	markVip(player)
	shop:grantPassItems(player.UserId)
	sendEconomy(player, { purchased = { kind = "pass", id = id } })
	Net.remote("LockerView"):FireClient(player, locker:view(player.UserId))
	sendAvatars(player)        -- the Wardrobe raises how many characters they may keep
end)
game:GetService("MarketplaceService").ProcessReceipt = function(receipt: any)
	return if purchases:process(receipt) == "granted"
		then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Writes go out every half-minute; the boards everyone sees are read on the two-hour marks. Both
-- yield on DataStores, so one job at a time.
local boardsBusy = false
local function boardsJob()
	if boardsBusy then return end
	boardsBusy = true
	boards:flush()
	if boards:due(os.time()) and boards:refresh(os.time()) then
		for _, player in loaded do Net.remote("ClimbBoards"):FireClient(player, boards:view()) end
	end
	boardsBusy = false
end

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
local elapsed, saveClock, boardsClock, mintClock = 0, 0, 30, 0
RunService.Heartbeat:Connect(function(dt: number)
	elapsed += dt
	saveClock += dt
	boardsClock += dt
	if boardsClock >= 30 then
		boardsClock = 0
		task.spawn(boardsJob)
	end
	-- bot votes whose ten seconds ran out (Rooms.BOT_VOTE_TIME): closed, and the room resent
	for _, room in rooms:tick() do publish(room); launchRoom(room) end
	if saveClock >= 1 then
		saveClock = 0
		task.spawn(function() avatars:tick() end)
	end
	mintClock += dt
	if mintClock >= 120 then
		-- serial counts out to every server, and the counts players are looking at read back in
		mintClock = 0
		task.spawn(function() mint:flush(); mint:refreshWanted(20) end)
	end
	if elapsed < 0.1 then return end
	elapsed = 0
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
			-- Climbing: not on the floor.
			if not climbs:climbing(id) then table.insert(groups[area], entry) end
		end
	end
	-- Positions as a buffer; who is who only when that changed for this player (PresenceCodec).
	local packed: any = {}
	for area, list in groups do
		packed[area] = { buf = PresenceCodec.encode(area, list), sig = PresenceCodec.signature(list), list = list }
	end
	for id, player in loaded do
		local room = rooms:get(id)
		if not room or room.state ~= "playing" then
			local area = if room then room.id else 0
			local p = packed[area] or { buf = PresenceCodec.encode(area, {}), sig = "", list = {} }
			local roster = nil
			if presenceSig[id] ~= p.sig then
				presenceSig[id] = p.sig
				roster = PresenceCodec.roster(p.list)
			end
			Net.remote("HubPresence"):FireClient(player, p.buf, roster)
		end
	end
end)
Players.PlayerRemoving:Connect(function(player: Player)
	sendQueue(rooms:dequeue(player))
	leave(player)
	local id = player.UserId
	loaded[id], poses[id], limits[id], rooms.profiles[id], presenceSig[id] = nil, nil, nil, nil, nil
	departed[player] = true
	passes:forget(id)
	shop:forget(id)
	restrictedFor[id] = nil
	climbs:leave(player.UserId)
	avatars:release(id)
end)
-- A server shutting down writes every unsaved character first.
game:BindToClose(function()
	mint:flush()
	avatars:flushAll()
end)
