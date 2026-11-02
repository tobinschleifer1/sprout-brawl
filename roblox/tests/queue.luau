--!strict
-- PLAY's queue (Rooms.queue): a player picks 1v1, 2v2 or 3v3 and waits in the lobby; a room forms
-- once the queue holds all but one of a fight's players (2 of 2, 3 of 4, 5 of 6), a newcomer takes
-- an open place in a room already forming, ADD BOT may be proposed BOT_WAIT seconds after the last
-- one in and a passed vote fills every open place, FILL WITH BOTS takes the queue into a room at
-- once, and every bot has two different weapons and plays at the room's newest player's level.
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

-- Bots go easier on new players (Rooms.botLevel): the least experienced person in the room decides
-- - easy below level 4, normal below 8, hard from 8 - and Ranked's are hard. The room shows it and
-- the match plays it.
do
	now = 0
	local levels: { [number]: number } = {}
	local m = model()
	m.levelOf = function(id: number): number return levels[id] or 1 end
	for _, case in { { 1, "easy" }, { 3, "easy" }, { 4, "normal" }, { 7, "normal" }, { 8, "hard" }, { 30, "hard" } } do
		levels[50] = case[1]
		m:queue(player(50), "Duel")
		local room = m:fillWithBots(player(50))
		if not room then fail("FILL WITH BOTS opened no room") end
		local roster = m:roster(room, function() return 1 end)
		if roster[2].botLevel ~= case[2] or m:view(room).slots[2].bot ~= case[2] then
			fail(`a level {case[1]} player's bot plays {tostring(roster[2].botLevel)}, not {case[2]}`)
		end
		m:leave(player(50))
	end
	-- a mixed room: its newest player decides
	levels[51], levels[52] = 20, 2
	local p51, p52 = player(51), player(52)
	m:queue(p51, "Triples"); m:queue(p52, "Triples")
	now = 100                                   -- (waited past both brackets, so they share a room)
	local room = m:fillWithBots(p51)
	if not room or m:get(52) ~= room then fail("the two were not seated together") end
	if m:roster(room)[3].botLevel ~= "easy" then fail("a room with a level 2 player in it plays hard bots") end
	m:leave(p52)
	if m:view(room).slots[3].bot ~= "hard" then fail("with the new player gone the bots stayed easy") end
	-- Ranked: hard, whoever is in it (a level 1 cannot be in Ranked; this asks the rule, not the gate)
	local r = { rooms = {}, ranked = true, slots = { { player = player(53) }, { bot = "hard" } } }
	levels[53] = 1
	if Rooms.botLevel(m, r) ~= "hard" then fail("Ranked's bots are not hard") end
end

-- New players meet new players (Rooms.bracket, Rooms.near): levels 1-4, 5-11 and 12+ are seated
-- with their own first; after 20 s queued one bracket either side, after 45 s anyone; Ranked has
-- no brackets.
do
	if Rooms.bracket(1) ~= 1 or Rooms.bracket(4) ~= 1 or Rooms.bracket(5) ~= 2 or Rooms.bracket(11) ~= 2 or Rooms.bracket(12) ~= 3 then
		fail("the brackets are not 1-4, 5-11, 12+")
	end
	local levels: { [number]: number } = { [61] = 1, [62] = 30, [63] = 2, [64] = 6, [65] = 13 }
	local function setup(): any
		local m = model()
		m.levelOf = function(id: number): number return levels[id] or 1 end
		return m
	end
	-- a level 1 and a level 30 do not meet at once; a second level 2 meets the level 1 at once
	now = 0
	local m = setup()
	m:queue(player(61), "Duel")
	m:queue(player(62), "Duel")
	if m:get(61) or m:get(62) then fail("a level 1 and a level 30 player were paired at once") end
	m:queue(player(63), "Duel")
	local room = m:get(61)
	if not room or m:get(63) ~= room then fail("two new players queued together were not paired") end
	if not m:queued(62) then fail("the level 30 player lost their place in the queue") end
	-- the veteran waits on; a newcomer's open room is not theirs either, until they have waited
	now = 0
	m = setup()
	m:queue(player(61), "Doubles"); m:queue(player(63), "Doubles"); m:queue(player(1), "Doubles")
	local newRoom = m:get(61)
	if not newRoom or #m.queues.Doubles ~= 0 then fail("three new players did not form a 2v2") end
	m:queue(player(65), "Doubles")
	if m:get(65) then fail("a level 13 player took a place in a room of new players at once") end
	now = 19
	m:tick()
	if m:get(65) then fail("a level 13 player was seated with level 1s before 20 s") end
	now = 30
	m:tick()
	if m:get(65) then fail("one bracket's reach seated a level 13 with level 1s (two brackets apart)") end
	now = 45
	local changed, formats = m:tick()
	if m:get(65) ~= newRoom then fail("after 45 s the level 13 player was still not seated") end
	if not table.find(changed, newRoom) or not table.find(formats, "Doubles") then fail("the tick that seated them did not report it") end
	-- one bracket apart: after 20 s, not before
	now = 0
	m = setup()
	m:queue(player(61), "Duel"); m:queue(player(64), "Duel")
	if m:get(61) then fail("a level 1 and a level 6 were paired at once") end
	now = 19.9
	m:tick()
	if m:get(61) then fail("a level 1 and a level 6 were paired before 20 s") end
	now = 20
	m:tick(false)                             -- (the server's frames between its once-a-second queue runs)
	if m:get(61) then fail("a tick told to leave the queue alone seated people") end
	m:tick()
	if not m:get(61) or m:get(61) ~= m:get(64) then fail("a level 1 and a level 6 were not paired after 20 s") end
	-- leaving the queue forgets the wait
	now = 0
	m = setup()
	local p61 = player(61)                      -- (the same player object: the queue finds people by it)
	m:queue(p61, "Duel")
	now = 50
	m:dequeue(p61); m:forget(p61)
	m:queue(p61, "Duel"); m:queue(player(62), "Duel")
	if m:get(61) then fail("a wait from an earlier queue counted") end
	-- Ranked: no brackets
	now = 0
	m = setup()
	levels[66], levels[67] = 10, 40
	m:queue(player(66), "Ranked"); m:queue(player(67), "Ranked")
	if not m:get(66) or m:get(66) ~= m:get(67) then fail("Ranked kept a level 10 and a level 40 apart") end
end
print("PASS queue: one waits in the lobby, a room forms at all-but-one (2/2, 3/4, 5/6), a newcomer takes an open place, ADD BOT waits 10s, a passed vote fills every place, FILL WITH BOTS brings the queue, bots with two different weapons and gentler for new players (easy <4, normal <8, hard, Ranked hard), level brackets that widen at 20 s and 45 s, leave and switch")
