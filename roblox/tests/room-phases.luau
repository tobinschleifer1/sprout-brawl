--!strict
-- The room's way to the fight (Rooms.PICK_TIME): weapon select, then a vote for the arena, then a
-- vote on the rules, then the fight starts itself.
--
--   * pick -> map the moment every pedestal is filled and every player is ready; not while a slot
--     is open; PICK_TIME after the room fills, ready or not, and that countdown stops if it empties;
--   * map: most votes wins; a tie is drawn by the room's `rand` between the tied (only them);
--     nobody voting, or Random winning, draws an arena; it ends when every player has voted, or on
--     the tick past MAP_TIME, not before; bots do not vote;
--   * rules: the same between the presets and "current"; the winner's mode, stocks, time, items and
--     disasters are applied (but not its map choice - the arena is already voted); "current" and no
--     votes keep the room's rules; then state is "playing" and nothing advances it further;
--   * once the votes begin weapons, readiness, bots and the host's settings are locked; a vote is
--     refused outside its phase, an unknown arena or rule set is refused, ballots need no fresh
--     revision; START is gone;
--   * someone leaving mid-vote sends the room back to pick with the ballots cleared; a room back
--     from its fight (toPick) starts at pick again;
--   * the view carries the phase, the seconds left, each slot's ballots and the results.
--
--     lune run tests/room-phases
local Loader = require("./loader")
local Rooms = Loader.loadFrom("src/server/", "Rooms")
-- (no wait before ADD BOT here: the queue test holds Rooms.BOT_WAIT; this one is about the rest)
Rooms.BOT_WAIT = 0
local Rules = Loader.load("Data/Rules")
local Stages = Loader.load("Data/Stages")

local function fail(msg: string): never
	error(msg, 0)
end

local now = 0
local draws: { number } = {}       -- the `n` of every rand(n) the room asked for
local pickIndex = 1                -- what rand returns (clamped to n)
local function newRooms(): any
	local r = Rooms.new()
	r.clock = function() return now end
	r.rand = function(n: number): number
		table.insert(draws, n)
		return math.min(pickIndex, n)
	end
	return r
end
local function person(id: number): any return { UserId = id, DisplayName = "P" .. id } end
local function edit(model: any, p: any, action: string, value: any?, slot: number?): (boolean, string?)
	local room = model:get(p.UserId)
	return model:edit(p, { id = room and room.id, revision = room and room.revision, action = action, value = value, slot = slot })
end
-- a room of `format` with `n` players; every one readied
local function roomOf(format: string, n: number): (any, any, { any })
	local model = newRooms()
	local people = {}
	local room
	for i = 1, n do
		people[i] = person(i)
		room = model:join(people[i], format)
		model:advance(room)
	end
	return model, room, people
end
local function readyAll(model: any, room: any, people: { any })
	for _, p in people do
		assert(edit(model, p, "ready"))
		model:advance(room)
	end
end
-- a 1v1 room taken through pick into the map vote
local function atMap(): (any, any, { any })
	now = 0
	local model, room, p = roomOf("Duel", 2)
	readyAll(model, room, p)
	if room.phase ~= "map" then fail("setup: a full, ready 1v1 did not reach the map vote") end
	return model, room, p
end

-- pick -> map: everyone ready, and only when the room is full
do
	now = 0
	local model, room, p = roomOf("Duel", 1)
	assert(edit(model, p[1], "ready")); model:advance(room)
	if room.phase ~= "pick" then fail("a room with an open pedestal left pick") end
	if room.phaseEnds then fail("a room with an open pedestal is counting down") end
	local second = person(2)
	model:join(second, "Duel"); model:advance(room)
	if room.phase ~= "pick" then fail("a room left pick with a player not ready") end
	assert(edit(model, second, "ready")); model:advance(room)
	if room.phase ~= "pick" then fail("a room left pick with a player not ready (the join un-readied the first)") end
	assert(edit(model, p[1], "ready")); model:advance(room)
	if room.phase ~= "map" then fail("a full room with everyone ready did not go to the map vote") end
	if room.phaseEnds ~= Rooms.MAP_TIME then fail(`the map vote ends at {room.phaseEnds}, want {Rooms.MAP_TIME}`) end
	if edit(model, p[1], "start") then fail("START was accepted - the room starts itself") end
end
-- pick -> map on the clock: PICK_TIME after the room fills, ready or not
do
	now = 100
	local model, room = roomOf("Duel", 2)
	if room.phaseEnds ~= 100 + Rooms.PICK_TIME then fail(`a full room counts down to {room.phaseEnds}, want {100 + Rooms.PICK_TIME}`) end
	now = 100 + Rooms.PICK_TIME - 0.01
	model:tick()
	if room.phase ~= "pick" then fail("the pick phase ended before PICK_TIME") end
	now = 100 + Rooms.PICK_TIME
	local changed = model:tick()
	if room.phase ~= "map" or #changed ~= 1 then fail("the pick phase did not end at PICK_TIME") end
end
-- the countdown stops when the room stops being full, and starts afresh when it fills again
do
	now = 0
	local model, room, p = roomOf("Duel", 2)
	now = 20
	model:leave(p[2]); model:advance(room)
	if room.phaseEnds then fail("the countdown kept running with a pedestal open") end
	now = 50
	model:join(person(3), "Duel"); model:advance(room)
	if room.phaseEnds ~= 50 + Rooms.PICK_TIME then fail("the countdown did not start afresh when the room filled again") end
	now = 0 + Rooms.PICK_TIME + 1
	model:tick()
	if room.phase ~= "pick" then fail("the old countdown moved the refilled room on") end
end
-- a bot fills a pedestal: two players and a bot in a 2v2... and the bot never votes
do
	now = 0
	local model, room, p = roomOf("Doubles", 3)
	local open
	for i, slot in room.slots do if not slot.player and not slot.bot then open = i end end
	assert(edit(model, p[1], "bot", "normal", open)); assert(edit(model, p[2], "ballot", true))
	model:advance(room)
	if not room.slots[open].bot then fail("setup: the bot was not voted in") end
	readyAll(model, room, p)
	if room.phase ~= "map" then fail("a room filled by a bot with every player ready did not go to the map vote") end
	if edit(model, p[1], "bot", false, open) then fail("a vote to remove a bot started during the map vote") end
	for _, q in p do assert(edit(model, q, "vote", "Undertow")) end
	model:advance(room)
	if room.phase ~= "rules" then fail("the map vote waited for the bot") end
end

-- the map vote: most votes wins, early when everyone has voted
do
	local model, room, p = atMap()
	assert(model:edit(p[1], { id = room.id, revision = -1, action = "vote", value = "Undertow" }), "a map vote needed a fresh revision")
	model:advance(room)
	if room.phase ~= "map" then fail("the map vote ended with a player still to vote") end
	if edit(model, p[1], "weapon", "Hammer") then fail("a weapon change was accepted during the map vote") end
	if edit(model, p[1], "ready") then fail("a ready press was accepted during the map vote") end
	if edit(model, p[1], "stage", "Undertow") then fail("the host set the map during the map vote") end
	if edit(model, p[1], "preset", "chaos") then fail("the host changed the rules during the map vote") end
	if edit(model, p[1], "rule", "chaos") then fail("a rules vote was accepted during the map vote") end
	if edit(model, p[2], "vote", "Atlantis") then fail("an unknown arena was accepted") end
	assert(edit(model, p[2], "vote", "Undertow"))
	model:advance(room)
	if room.phase ~= "rules" or room.stage ~= "Undertow" or room.mapResult ~= "Undertow" then
		fail(`two votes for the Undertow gave phase {room.phase}, stage {room.stage}`)
	end
	if room.mapChoice ~= "host" then fail("the voted arena is not what the fight will be played on") end
	if Rooms.resolveStage(room, function() return 1 end) ~= "Undertow" then fail("the match would not be played on the voted arena") end
	if room.phaseEnds ~= Rooms.RULES_TIME then fail(`the rules vote ends at {room.phaseEnds}, want {Rooms.RULES_TIME}`) end
	if edit(model, p[1], "vote", "FoundryFloor") then fail("a map vote was accepted during the rules vote") end
end
-- three players: two votes beat one
do
	now = 0
	local model, room, p = roomOf("Triples", 6)
	readyAll(model, room, p)
	local a, b = Stages.LIST[2].id, Stages.LIST[3].id
	for i, q in p do assert(edit(model, q, "vote", if i <= 4 then a else b)) end
	table.clear(draws)
	model:advance(room)
	if room.stage ~= a then fail(`four votes to two picked {room.stage}`) end
	if #draws ~= 0 then fail("a clear winner was drawn at random") end
end
-- a tie: drawn by rand between the tied only, in a fixed (sorted) order, whatever order the
-- ballots were counted in - three ways, two votes each, for every arena trio in the roster
do
	for first = 1, #Stages.LIST - 2 do
		local trio = { Stages.LIST[first + 2].id, Stages.LIST[first].id, Stages.LIST[first + 1].id }
		local sorted = table.clone(trio)
		table.sort(sorted)
		for k = 1, 3 do
			now = 0
			local model, room, p = roomOf("Triples", 6)
			readyAll(model, room, p)
			for i, q in p do assert(edit(model, q, "vote", trio[(i - 1) % 3 + 1])) end
			table.clear(draws)
			pickIndex = k
			model:advance(room)
			pickIndex = 1
			if draws[1] ~= 3 then fail(`a three-way tie asked rand for 1..{draws[1]}`) end
			if room.stage ~= sorted[k] then fail(`rand {k} in a tie of {table.concat(trio, ",")} drew {room.stage}, want {sorted[k]}`) end
		end
	end
end
-- a room set to "random" or to a standing vote: the vote phase still decides, from fresh ballots,
-- and the voted arena is what the fight is played on
do
	for _, choice in { "random", "vote" } do
		now = 0
		local model, room, p = roomOf("Duel", 2)
		assert(edit(model, p[1], "mapChoice", choice))
		if choice == "vote" then for _, q in p do assert(edit(model, q, "vote", "Smeltworks")) end end
		readyAll(model, room, p)
		if room.phase ~= "map" then fail(`a "{choice}" room skipped the map vote`) end
		if room.slots[1].vote or room.slots[2].vote then fail("ballots from before the map vote were carried into it") end
		for _, q in p do assert(edit(model, q, "vote", "Undertow")) end
		model:advance(room)
		if room.mapChoice ~= "host" or Rooms.resolveStage(room, function(n) return n end) ~= "Undertow" then
			fail(`a "{choice}" room would not fight on the voted arena`)
		end
	end
end
-- nobody votes: on the tick past MAP_TIME, not before, an arena is drawn
do
	local model, room = atMap()
	now = Rooms.MAP_TIME - 0.01
	model:tick()
	if room.phase ~= "map" then fail("the map vote ended before MAP_TIME") end
	now = Rooms.MAP_TIME
	table.clear(draws)
	pickIndex = 2
	local changed = model:tick()
	pickIndex = 1
	if room.phase ~= "rules" or #changed ~= 1 then fail("the map vote did not end at MAP_TIME") end
	local pool = Rooms.mapPool("all")
	if draws[1] ~= #pool or room.stage ~= pool[2] then fail(`no votes drew {room.stage} from 1..{draws[1]}, want {pool[2]} from {#pool}`) end
end
-- Random winning draws an arena too: the room never fights on "Random"
do
	local model, room, p = atMap()
	for _, q in p do assert(edit(model, q, "vote", "Random")) end
	model:advance(room)
	if room.stage == "Random" or not Stages.BY_ID[room.stage] then fail(`Random won and the arena is {room.stage}`) end
end

-- the rules vote
local function atRules(): (any, any, { any })
	local model, room, p = atMap()
	for _, q in p do assert(edit(model, q, "vote", "Undertow")) end
	model:advance(room)
	if room.phase ~= "rules" then fail("setup: the room did not reach the rules vote") end
	return model, room, p
end
do
	local model, room, p = atRules()
	if edit(model, p[1], "rule", "anarchy") then fail("an unknown rule set was accepted") end
	if edit(model, p[1], "stocks", 5) then fail("the host changed the stocks during the rules vote") end
	if edit(model, p[1], "bot", "easy", 1) then fail("a bot vote started during the rules vote") end
	assert(model:edit(p[1], { id = room.id, revision = -1, action = "rule", value = "chaos" }), "a rule vote needed a fresh revision")
	model:advance(room)
	if room.state ~= "setup" then fail("the rules vote ended with a player still to vote") end
	now += 4
	local view = model:view(room)
	if view.phase ~= "rules" or view.mapResult ~= "Undertow" or view.slots[1].ruleVote ~= "chaos" or view.slots[2].ruleVote ~= nil then
		fail("the view does not show the rules phase, the arena and the ballots")
	end
	if math.abs(view.phaseLeft - (room.phaseEnds - now)) > 1e-9 then fail(`the view says {view.phaseLeft}s left`) end
	assert(edit(model, p[2], "rule", "chaos"))
	model:advance(room)
	local chaos
	for _, preset in Rules.presets do if preset.id == "chaos" then chaos = preset.rules end end
	if room.state ~= "playing" then fail("the rules vote did not start the fight") end
	if room.ruleResult ~= "chaos" then fail("the rules result was not recorded") end
	for _, k in { "mode", "stocks", "time", "items", "disasters" } do
		if room[k] ~= chaos[k] then fail(`chaos won but {k} is {tostring(room[k])}, want {tostring(chaos[k])}`) end
	end
	if room.mapChoice ~= "host" or room.stage ~= "Undertow" then fail("the winning rules overrode the voted arena") end
	local revision = room.revision
	now += 1000
	if model:advance(room) or #model:tick() ~= 0 or room.revision ~= revision then fail("a playing room was moved on") end
	if edit(model, p[1], "rule", "casual") then fail("a vote was accepted in a playing room") end
end
-- "current", and nobody voting, keep the room's rules
for _, votes in { { "current", "current" }, {} } do
	local model, room, p = atRules()
	local before = { mode = room.mode, stocks = room.stocks, time = room.time, items = room.items, disasters = room.disasters }
	for i, v in votes do assert(edit(model, p[i], "rule", v)) end
	if #votes == 0 then now = room.phaseEnds - 0.01; model:tick(); if room.state ~= "setup" then fail("the rules vote ended before RULES_TIME") end; now = room.phaseEnds; model:tick() else model:advance(room) end
	if room.state ~= "playing" then fail("the rules vote did not end") end
	if room.ruleResult ~= "current" then fail(`with votes {table.concat(votes, ",")} the rules result is {room.ruleResult}`) end
	for k, v in before do if room[k] ~= v then fail(`keeping the current rules changed {k}`) end end
end
-- two against one in the rules too, with a tie broken by rand
do
	now = 0
	local model, room, p = roomOf("Triples", 6)
	readyAll(model, room, p)
	for _, q in p do assert(edit(model, q, "vote", "Undertow")) end
	model:advance(room)
	for i, q in p do assert(edit(model, q, "rule", if i <= 4 then "tournament" else "casual")) end
	model:advance(room)
	if room.ruleResult ~= "tournament" or room.items ~= false then fail("four rule votes to two did not win") end
end

-- someone leaving mid-vote sends the room back to pick, ballots cleared
do
	local model, room, p = atRules()
	assert(edit(model, p[1], "rule", "casual"))
	model:leave(p[2]); model:advance(room)
	if room.phase ~= "pick" or room.slots[1].ruleVote or room.slots[1].vote then fail("a leaver mid-vote did not send the room back to pick with the ballots cleared") end
	if room.slots[1].ready then fail("back at pick, a player was still ready") end
	local joiner = person(9)
	model:join(joiner, "Duel")
	readyAll(model, room, { p[1], joiner })
	if room.phase ~= "map" or room.slots[1].vote then fail("the refilled room did not vote again from scratch") end
end
-- back from the fight: pick again
do
	local model, room, p = atRules()
	for _, q in p do assert(edit(model, q, "rule", "current")) end
	model:advance(room)
	room.state = "setup"
	room.lastVote = { passed = true, value = "normal", slot = 2 }
	Rooms.toPick(room)
	if room.lastVote or room.botVote then fail("a room back from its fight still reports its last bot vote") end
	model:advance(room)
	if room.phase ~= "pick" or room.slots[1].ruleVote then fail("a room back from its fight did not start at pick") end
	if not room.phaseEnds then fail("a full room back from its fight is not counting down to the map vote") end
end

print(`PASS room phases: pick -> map (everyone ready, or {Rooms.PICK_TIME}s once full) -> rules -> playing; most votes wins, ties drawn by rand between the tied, no votes or Random draws an arena, "current" and no votes keep the rules`)
print(`  each vote ends when all have voted or on the tick past its time ({Rooms.MAP_TIME}s, {Rooms.RULES_TIME}s); bots do not vote; weapons, ready, bots and settings lock; votes outside their phase and unknown choices are refused; leavers send the room back to pick; no START`)
