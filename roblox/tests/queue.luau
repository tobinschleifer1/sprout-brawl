--!strict
-- PLAY's queue (Rooms.queue): a player picks 1v1, 2v2 or 3v3 and waits in the lobby; a room forms
-- once the queue holds all but one of a fight's players (2 of 2, 3 of 4, 5 of 6), a newcomer takes
-- an open place in a room already forming, ADD BOT may be proposed BOT_WAIT seconds after the last
-- one in and a passed vote fills every open place, FILL WITH BOTS takes the queue into a room at
-- once, and every bot plays on hard with two different weapons.
--     lune run tests/queue
local Loader = require("./loader")
local Rooms = Loader.loadFrom("src/server/", "Rooms")

local function fail(msg: string): never error(msg, 0) end
local function player(id: number): any return { UserId = id, DisplayName = "P" .. id } end
local now = 0
local function model(): any
	local m = Rooms.new()
	m.clock = function() return now end
	return m
end
local function humans(room: any): number
	local n = 0
	for _, slot in room.slots do if slot.player then n += 1 end end
	return n
end

-- one waits in the lobby; a 2v2 forms at three, the fourth takes the open place
do
	now = 0
	local m = model()
	local p = { player(1), player(2), player(3), player(4) }
	local changed = m:queue(p[1], "Doubles")
	if #(changed or {}) ~= 0 or m:get(1) then fail("one queued player was put in a room") end
	local v = m:queueView(1)
	if not v.queued or v.waiting ~= 1 or v.needed ~= 4 or v.formAt ~= 3 then fail("the queue's view is wrong") end
	m:queue(p[2], "Doubles")
	if m:get(1) then fail("two of four formed a room") end
	changed = m:queue(p[3], "Doubles")
	local room = m:get(1)
	if not room or #(changed or {}) ~= 1 or humans(room) ~= 3 or m:get(2) ~= room or m:get(3) ~= room then
		fail("three of four did not form one room")
	end
	if m:queued(1) or m:queued(3) then fail("seated players are still queued") end
	m:queue(p[4], "Doubles")
	if m:get(4) ~= room or humans(room) ~= 4 then fail("the fourth did not take the open place") end
end

-- ADD BOT waits BOT_WAIT seconds after the last one in, then a passed vote fills every open place
do
	now = 100
	local m = model()
	for i = 1, 5 do m:queue(player(i), "Triples") end
	local room = m:get(1)
	if not room or humans(room) ~= 5 then fail("five of six did not form a 3v3") end
	local open = 0
	for i, slot in room.slots do if not slot.player then open = i end end
	-- (the edit compares players by object: use the seated ones)
	local seated = {}
	for _, slot in room.slots do if slot.player then seated[slot.player.UserId] = slot.player end end
	local function propose(by: number): (boolean, string?)
		return m:edit(seated[by], { id = room.id, revision = room.revision, action = "bot", value = "easy", slot = open })
	end
	local ok, why = propose(1)
	if ok then fail("a bot was proposed the moment the room formed") end
	if not why or not string.find(why, "Waiting for players", 1, true) then fail(`the early ADD BOT said {why}`) end
	if m:view(room).botWait <= 0 then fail("the room's view does not count down to ADD BOT") end
	now = 100 + Rooms.BOT_WAIT - 0.1
	if propose(1) then fail("a bot was proposed before BOT_WAIT ran out") end
	now = 100 + Rooms.BOT_WAIT
	if not propose(1) then fail("no bot could be proposed after BOT_WAIT") end
	-- one yes of five is no majority; two more make three of five
	if room.slots[open].bot then fail("one of five added the bot") end
	m:edit(seated[2], { id = room.id, revision = room.revision, action = "ballot", value = true })
	m:edit(seated[3], { id = room.id, revision = room.revision, action = "ballot", value = true })
	if room.slots[open].bot ~= "hard" then fail("three of five did not add a hard bot (asked for easy)") end
end

-- a passed vote fills EVERY open place (a 2v2 of two players, both yes)
do
	now = 200
	local m = model()
	local a, b = player(1), player(2)
	m:queue(a, "Doubles"); m:queue(b, "Doubles"); m:queue(player(3), "Doubles")
	local room = m:get(1)
	local seated = {}
	for _, slot in room.slots do if slot.player then seated[slot.player.UserId] = slot.player end end
	m:leave(seated[3])
	now = 200 + Rooms.BOT_WAIT
	local first = nil
	for i, slot in room.slots do if not slot.player and not first then first = i end end
	assert(m:edit(seated[1], { id = room.id, revision = room.revision, action = "bot", value = "normal", slot = first }))
	m:edit(seated[2], { id = room.id, revision = room.revision, action = "ballot", value = true })
	for i, slot in room.slots do
		if not slot.player and slot.bot ~= "hard" then fail(`place {i} took no bot after the vote passed`) end
	end
end

-- FILL WITH BOTS: alone in a 3v3 queue, into a room at once with five hard bots, each with two
-- different weapons; anyone else queued for it comes along
do
	now = 300
	local m = model()
	local rolls = 0
	-- (each bot's two draws come out the same - 1 and 1, 2 and 2 - so only the step that keeps them
	-- apart can give it two weapons; and each bot's differ from the last's)
	m.rand = function(n: number): number rolls += 1; return ((rolls - 1) // 2) % n + 1 end
	local a, b = player(1), player(2)
	m:queue(a, "Triples"); m:queue(b, "Triples")
	local room = m:fillWithBots(a)
	if not room or m:get(2) ~= room then fail("FILL WITH BOTS did not bring the other queued player") end
	local bots, pairs = 0, {}
	for _, slot in room.slots do
		if slot.bot then
			bots += 1
			if slot.bot ~= "hard" then fail("a bot is not on hard") end
			if not slot.weapon or not slot.weapon2 or slot.weapon == slot.weapon2 then fail("a bot's two weapons are not two") end
			pairs[slot.weapon .. "+" .. slot.weapon2] = true
		end
	end
	if bots ~= 4 then fail(`FILL WITH BOTS added {bots} bots to two players`) end
	local kinds = 0
	for _ in pairs do kinds += 1 end
	if kinds < 2 then fail("every bot took the same weapons: not drawn at random") end
	if m:queued(1) or m:queued(2) then fail("filled players are still queued") end
	if m:fillWithBots(player(9)) then fail("someone not queued filled a room") end
end

-- 1v1 waits for a pair; leaving the queue takes you out of it; a seated player cannot queue
do
	now = 400
	local m = model()
	local a, b = player(1), player(2)
	m:queue(a, "Duel")
	if m:get(1) then fail("one queued 1v1 player was put in a room") end
	m:dequeue(a)
	if m:queued(1) or m:queueView(1).queued then fail("leaving the queue did not") end
	m:queue(a, "Duel"); m:queue(b, "Duel")
	local room = m:get(1)
	if not room or m:get(2) ~= room then fail("two 1v1 players did not meet") end
	local again, why = m:queue(a, "Doubles")
	if again or not why then fail("a seated player queued again") end
	if m:queue(player(5), "Quad") then fail("an unknown format queued") end
	-- switching formats moves you, it does not queue you twice
	local c = player(6)
	m:queue(c, "Doubles"); m:queue(c, "Triples")
	if m:queued(6) ~= "Triples" or #m.queues.Doubles ~= 0 then fail("switching formats left you in the old queue") end
end
print("PASS queue: one waits in the lobby, a room forms at all-but-one (2/2, 3/4, 5/6), a newcomer takes an open place, ADD BOT waits 10s, a passed vote fills every place, FILL WITH BOTS brings the queue, bots hard with two different weapons, leave and switch")
