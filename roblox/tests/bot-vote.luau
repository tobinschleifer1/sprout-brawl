--!strict
-- The bot vote (Rooms.BOT_VOTE_TIME): ADD BOT on an empty pedestal, or REMOVE on a bot's, is a
-- proposal any player in the room can make, and a strict majority of the players in the room
-- decides.
--
--   * three players, the proposer and one more say yes: the bot is added; two players: both must
--     say yes; alone: your own yes is a majority, at once;
--   * a tie fails, a majority of no fails at once, and a vote still open after BOT_VOTE_TIME fails
--     when the room's clock ticks past it;
--   * a voter who leaves stops counting (and a smaller room can then have its majority); a player
--     who joins into the vote's slot cancels it; one vote at a time; ballots can change; only
--     people in the room vote; a ballot needs no fresh revision;
--   * a passed REMOVE takes the bot out; a passed ADD un-readies everyone, as any slot change does.
--
--     lune run tests/bot-vote
local Loader = require("./loader")
local Rooms = Loader.loadFrom("src/server/", "Rooms")
-- (every weapon unlocked: these rooms are not about levels - tests/progression is)
local newRooms = Rooms.new
Rooms.new = function(): any local r = newRooms(); r.levelOf = function(_: number): number return 50 end; return r end
-- (no wait before ADD BOT here: the queue test holds Rooms.BOT_WAIT; this one is about the rest)
Rooms.BOT_WAIT = 0

local function fail(msg: string): never
	error(msg, 0)
end

local now = 0
local function newRooms(): any
	local r = Rooms.new()
	r.clock = function() return now end
	return r
end
local function person(id: number): any return { UserId = id, DisplayName = "P" .. id } end
local function edit(model: any, p: any, action: string, value: any?, slot: number?): (boolean, string?)
	local room = model:get(p.UserId)
	return model:edit(p, { id = room and room.id, revision = room and room.revision, action = action, value = value, slot = slot })
end
-- a 3v3 room with `n` players in it; returns the model, the room and the people
local function roomOf(n: number): (any, any, { any })
	local model = newRooms()
	local people = {}
	local room
	for i = 1, n do
		people[i] = person(i)
		room = model:join(people[i], "Triples")
	end
	return model, room, people
end
local function emptySlot(room: any): number
	for i, slot in room.slots do if not slot.player and not slot.bot then return i end end
	return fail("no empty slot")
end

-- three players: two yes passes
do
	now = 0
	local model, room, p = roomOf(3)
	local i = emptySlot(room)
	assert(edit(model, p[1], "bot", "hard", i))
	if room.slots[i].bot then fail("one yes of three added the bot") end
	assert(edit(model, p[2], "ballot", true))
	if room.slots[i].bot ~= "hard" then fail("two yes of three did not add the bot") end
	if room.botVote then fail("a passed vote stayed open") end
	if not room.lastVote or not room.lastVote.passed then fail("the passed vote was not reported") end
	for _, slot in room.slots do if slot.ready then fail("adding a bot left someone ready") end end
end
-- two players: both must agree; a no from the other fails at once
do
	now = 0
	local model, room, p = roomOf(2)
	local i = emptySlot(room)
	assert(edit(model, p[1], "bot", "normal", i))
	if room.slots[i].bot then fail("one yes of two added the bot") end
	assert(edit(model, p[2], "ballot", false))
	if room.slots[i].bot or room.botVote then fail("a tie (one yes, one no) did not fail") end
	if not room.lastVote or room.lastVote.passed then fail("the failed vote was not reported as failed") end
	assert(edit(model, p[2], "bot", "easy", i))
	assert(edit(model, p[1], "ballot", true))
	if room.slots[i].bot ~= "hard" then fail("both of two saying yes did not add the bot") end
end
-- alone: instant
do
	now = 0
	local model, room, p = roomOf(1)
	local i = emptySlot(room)
	assert(edit(model, p[1], "bot", "normal", i))
	if room.slots[i].bot ~= "hard" or room.botVote then fail("a solo proposal did not pass at once") end
end
-- time runs out: fails on the tick past BOT_VOTE_TIME, not before
do
	now = 0
	local model, room, p = roomOf(3)
	local i = emptySlot(room)
	assert(edit(model, p[1], "bot", "normal", i))
	now = Rooms.BOT_VOTE_TIME - 0.01
	if #model:tick() ~= 0 or not room.botVote then fail("the vote closed before its time") end
	now = Rooms.BOT_VOTE_TIME + 0.01
	local changed = model:tick()
	if #changed ~= 1 or changed[1] ~= room then fail("the timed-out room was not reported for resending") end
	if room.botVote or room.slots[i].bot then fail("a vote one yes short at the deadline did not fail") end
end
-- a majority of no closes it at once
do
	now = 0
	local model, room, p = roomOf(3)
	local i = emptySlot(room)
	assert(edit(model, p[1], "bot", "normal", i))
	assert(edit(model, p[2], "ballot", false))
	if not room.botVote then fail("one no of three closed the vote") end
	assert(edit(model, p[3], "ballot", false))
	if room.botVote then fail("two no of three left the vote open") end
end
-- a voter leaving: the room shrinks, and the proposer's yes is now a majority of two? no - of one
do
	now = 0
	local model, room, p = roomOf(2)
	local i = emptySlot(room)
	assert(edit(model, p[1], "bot", "normal", i))
	model:leave(p[2])
	if room.slots[i].bot ~= "hard" then fail("after the other player left, the proposer's yes was not a majority") end
end
-- a voter who leaves stops counting, in the tally the screens show too: four players, two yes (not
-- a majority of four), one of the yeses leaves - one yes of three, still open, and shown as one
do
	now = 0
	local model, room, p = roomOf(4)
	local i = emptySlot(room)
	assert(edit(model, p[1], "bot", "normal", i))
	assert(edit(model, p[2], "ballot", true))
	if not room.botVote then fail("two yes of four closed the vote") end
	model:leave(p[2])
	local v = model:view(room).botVote
	if not v or v.yes ~= 1 or v.voters ~= 3 then fail(`after a yes-voter left, the view shows {v and v.yes} yes of {v and v.voters}`) end
end
-- a player joining into the vote's slot cancels it (the vote is on the LAST empty slot: joins fill
-- the lowest open slot first, so the fillers take the others and the joiner lands in this one)
do
	now = 0
	local model, room, p = roomOf(2)
	local i
	for k, slot in room.slots do if not slot.player and not slot.bot then i = k end end
	assert(edit(model, p[1], "bot", "normal", i))
	local joiner = person(9)
	-- fill every other empty slot first, so the joiner lands in the vote's
	local fillers = {}
	for k, slot in room.slots do
		if not slot.player and not slot.bot and k ~= i then
			local f = person(100 + k)
			table.insert(fillers, f)
			model:join(f, "Triples")
		end
	end
	model:join(joiner, "Triples")
	if room.slots[i].player ~= joiner then fail("the test did not put the joiner in the vote's slot") end
	if room.botVote then fail("a player taking the vote's slot did not cancel it") end
end
-- one at a time, changeable ballots, outsiders, no revision needed
do
	now = 0
	local model, room, p = roomOf(3)
	local i = emptySlot(room)
	assert(edit(model, p[1], "bot", "normal", i))
	local j
	for k, slot in room.slots do if not slot.player and not slot.bot and k ~= i then j = k end end
	if edit(model, p[2], "bot", "hard", j) then fail("a second vote started while one was running") end
	assert(edit(model, p[2], "ballot", false))
	assert(model:edit(p[2], { id = room.id, revision = -1, action = "ballot", value = true }), "a ballot needed a fresh revision")
	if room.slots[i].bot ~= "hard" then fail("changing a no to a yes did not count") end
	local outsider = person(77)
	if model:edit(outsider, { id = room.id, revision = room.revision, action = "ballot", value = true }) then fail("an outsider voted") end
	if edit(model, p[1], "ballot", true) then fail("a ballot was accepted with no vote running") end
	if edit(model, p[1], "bot", "normal", 1) then fail("a vote to put a bot over a player started") end
	if edit(model, p[1], "bot", "brutal", j) then fail("an unknown difficulty was accepted") end
end
-- removing a bot is a vote too
do
	now = 0
	local model, room, p = roomOf(2)
	local i = emptySlot(room)
	assert(edit(model, p[1], "bot", "hard", i)); assert(edit(model, p[2], "ballot", true))
	if not room.slots[i].bot then fail("setup: the bot was not added") end
	assert(edit(model, p[2], "bot", false, i))
	if not room.slots[i].bot then fail("one of two voting to remove took the bot out") end
	assert(edit(model, p[1], "ballot", true))
	if room.slots[i].bot then fail("both voting to remove did not take the bot out") end
	if edit(model, p[1], "bot", false, i) then fail("a vote to remove a bot that is not there started") end
end
-- the view carries the vote for the screens
do
	now = 2
	local model, room, p = roomOf(3)
	local i = emptySlot(room)
	assert(edit(model, p[1], "bot", "easy", i))
	now = 5
	local v = model:view(room).botVote
	if not v or v.slot ~= i or v.value ~= "hard" or v.yes ~= 1 or v.no ~= 0 or v.voters ~= 3 then fail("the view's vote is wrong") end
	if math.abs(v.left - (Rooms.BOT_VOTE_TIME - 3)) > 1e-9 then fail(`the view says {v.left}s left, want {Rooms.BOT_VOTE_TIME - 3}`) end
	if v.ballots[tostring(p[1].UserId)] ~= true then fail("the view does not show the proposer's yes") end
end

print(`PASS bot vote: anyone proposes, a strict majority of the room's players decides (two of three, both of two, alone at once), ties and timeouts ({Rooms.BOT_VOTE_TIME}s) fail, leavers stop counting, a joiner into the slot cancels it, one at a time, ballots change, removals vote too`)
