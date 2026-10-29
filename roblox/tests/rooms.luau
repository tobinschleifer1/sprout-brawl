--!strict
local Loader = require("./loader")
local Rooms = Loader.loadFrom("src/server/", "Rooms")
-- (every weapon unlocked: these rooms are not about levels - tests/progression is)
local newRooms = Rooms.new
Rooms.new = function(): any local r = newRooms(); r.levelOf = function(_: number): number return 50 end; return r end
-- (no wait before ADD BOT here: the queue test holds Rooms.BOT_WAIT; this one is about the rest)
Rooms.BOT_WAIT = 0
local function player(id: number): any return { UserId = id, DisplayName = `Player{id}`, Name = `Player{id}` } end
for size, format in { "Duel", "Doubles", "Triples" } do
	local model = Rooms.new()
	local people, room = {}, nil
	for i = 1, size * 2 do
		people[i] = player(i)
		local joined = model:join(people[i], format)
		if room then assert(joined == room, "same mode finds open human slots") else room = joined end
		assert(not model:canStart(room), "joining never auto-readies people")
		for _, slot in room.slots do assert(not slot.bot, "bots OFF by default") end
	end
	assert(#room.slots == size * 2)
	local function edit(p: any, action: string, value: any?, slot: number?): boolean
		return model:edit(p, { id = room.id, revision = room.revision, action = action, value = value, slot = slot })
	end
	assert(not edit(player(99), "stage", "Undertow"), "outsiders cannot edit")
	assert(not edit(people[2], "stage", "Undertow"), "only host chooses map")
	assert(not edit(people[1], "bot", "hard", 2), "bots never replace people")
	assert(not edit(people[1], "stocks", 0/0), "reject NaN")
	assert(not model:edit(people[1], { id = room.id, revision = room.revision - 1, action = "ready" }), "reject stale revision")
	assert(edit(people[2], "weapon", "Hammer"))
	assert(room.slots[2].weapon == "Hammer" and room.slots[1].weapon == "Sword", "loadout is sender-owned")
	for _, p in people do assert(edit(p, "ready")) end
	assert(model:canStart(room), "full ready teams can start")
	assert(edit(people[1], "stage", "Undertow"))
	assert(not model:canStart(room), "map change resets readiness")
	for _, p in people do assert(edit(p, "ready")) end
	-- nobody presses start: everyone ready moves the room to the map vote, the map vote to the rules
	-- vote, and the rules vote starts the fight (Rooms.PICK_TIME)
	assert(not edit(people[1], "start"), "the host cannot start: the votes do")
	assert(model:advance(room) and room.phase == "map", "everyone ready moves the room to the map vote")
	for _, p in people do assert(edit(p, "vote", "Undertow")) end
	assert(model:advance(room) and room.phase == "rules" and room.stage == "Undertow", "the map vote picks the map")
	for _, p in people do assert(edit(p, "rule", "current")) end
	assert(model:advance(room) and room.state == "playing", "the rules vote starts the fight")
	assert(not model:advance(room), "a started room cannot start another match")
	local roster, opts = model:roster(room)
	local counts = {0,0}
	for _, entry in roster do counts[entry.team + 1] += 1; assert(entry.player) end
	assert(counts[1] == size and counts[2] == size and opts.mode == "StockTeams")
	local nextRoom = model:join(player(99), format)
	assert(nextRoom ~= room, "ongoing/full room cannot capture unrelated players")
	model:leave(people[1])
	assert(room.host == people[2].UserId and not model:get(1), "host transfers and membership released")
	for i = 2, #people do model:leave(people[i]) end
	assert(not model.rooms[room.id], "empty rooms removed")
end
do
	local m = Rooms.new()
	local joined, why = m:join(player(50), "Wardrobe")
	assert(joined == nil and why and next(m.rooms) == nil, "the wardrobe is a station, not a fight: joining it must open no room")
end
local model, p = Rooms.new(), player(1)
local room = model:join(p, "Duel")
assert(not model:canStart(room), "solo never launches with implicit bots")
assert(model:edit(p, { id=room.id, revision=room.revision, action="ready" }))
assert(not model:canStart(room), "even a ready host cannot launch an empty opposing team")
assert(not model:edit(p, { id=room.id, revision=room.revision, action="start" }))
assert(model:edit(p, { id=room.id, revision=room.revision, action="ready" }))
assert(not model:join(player(2), "FoundryFloor"), "only three formats accepted")
assert(model:edit(p, { id=room.id, revision=room.revision, action="bot", slot=2, value="hard" }))
assert(model:edit(p, { id=room.id, revision=room.revision, action="ready" }))
assert(model:canStart(room), "explicit CPU can fill an opponent slot")
assert(model:edit(p, { id=room.id, revision=room.revision, action="bot", slot=2, value=false }))
assert(not model:canStart(room), "removing CPU reopens the slot")
-- Fullest-first: two half-empty 1v1 rooms must not split newcomers at random.
do
	local model = Rooms.new()
	local a, b, c, d = player(11), player(12), player(13), player(14)   -- kept: leave matches by object
	local r1 = model:join(a, "Duel"); model:join(b, "Duel")
	local r2 = model:join(c, "Duel"); model:join(d, "Duel")
	assert(r1 ~= r2, "two full rooms")
	model:leave(b); model:leave(d)
	-- r1 and r2 now each hold one waiting player. Fill r2 back to full to make it the fuller one
	-- only after a third room exists, then check a newcomer joins a half room, never a new one.
	local joined = model:join(player(15), "Duel")
	assert(joined == r1 or joined == r2, "a newcomer completes a waiting room rather than opening a third")
	local other = if joined == r1 then r2 else r1
	local next = model:join(player(16), "Duel")
	assert(next == other, "the next newcomer completes the other waiting room")
	-- With one room at 1/2 and one at 3/4 (2v2), the 3/4 room fills first.
	local m2 = Rooms.new()
	local ps = {}
	for i = 21, 28 do ps[i] = player(i) end
	local ra = m2:join(ps[21], "Doubles")
	for i = 22, 24 do m2:join(ps[i], "Doubles") end
	local rb = m2:join(ps[25], "Doubles")
	for i = 26, 28 do m2:join(ps[i], "Doubles") end
	assert(ra ~= rb)
	-- Rooms.leave matches the slot by the player OBJECT, so leave with the same tables.
	m2:leave(ps[22]); m2:leave(ps[23]); m2:leave(ps[26])   -- ra: 2 open, rb: 1 open
	assert(m2:join(player(29), "Doubles") == rb, "the fuller room fills first")
end
-- Your own loadout survives a teammate's ready toggle; a stale READY does not.
do
	local model = Rooms.new()
	local a, b = player(31), player(32)
	local room = model:join(a, "Duel"); model:join(b, "Duel")
	local seen = room.revision
	assert(model:edit(b, { id = room.id, revision = room.revision, action = "ready" }))
	assert(model:edit(a, { id = room.id, revision = seen, action = "weapon", value = "Axe" }), "own loadout ignores a teammate's revision bump")
	assert(room.slots[1].weapon == "Axe")
	assert(not model:edit(a, { id = room.id, revision = seen, action = "ready" }), "a stale ready is still refused")
	assert(not model:edit(a, { id = room.id, revision = seen, action = "stage", value = "Undertow" }), "a stale host change is still refused")
	assert(not model:edit(a, { id = room.id + 1, revision = room.revision, action = "weapon", value = "Axe" }), "another room's loadout edit is refused")
end
-- Natural disasters: off by default, host-only, validated, carried into the match.
do
	local model = Rooms.new()
	local a, b = player(41), player(42)
	local room = model:join(a, "Duel"); model:join(b, "Duel")
	assert(room.disasters == "off", "disasters are off by default")
	local function edit(p: any, v: any): boolean
		return (model:edit(p, { id = room.id, revision = room.revision, action = "disasters", value = v }))
	end
	assert(not edit(b, "chaos"), "a guest cannot turn disasters on")
	assert(not edit(a, "apocalypse") and not edit(a, true), "unknown settings are refused")
	assert(edit(a, "chaos") and room.disasters == "chaos")
	local _, opts = model:roster(room)
	assert(opts.disasters == "chaos", "the setting reaches the match")
	assert(model:view(room).disasters == "chaos", "and every member sees it")
end
-- Map choice, map sets and voting, after Brawlhalla's custom rooms.
do
	local model = Rooms.new()
	local a, b, c, d = player(51), player(52), player(53), player(54)
	local room = model:join(a, "Doubles"); model:join(b, "Doubles"); model:join(c, "Doubles"); model:join(d, "Doubles")
	local function edit(p: any, action: string, v: any, rev: number?): boolean
		return (model:edit(p, { id = room.id, revision = rev or room.revision, action = action, value = v }))
	end
	assert(room.mapChoice == "host" and room.mapSet == "all", "the host picks from every map by default")
	-- a counting random source: rand(n) returns the next scripted value
	local script_: { number } = {}
	local function rand(n: number): number
		local v = table.remove(script_, 1) or 1
		assert(v >= 1 and v <= n, `scripted pick {v} outside 1..{n}`)
		return v
	end
	-- host picks
	assert(edit(a, "stage", "Undertow"))
	assert(Rooms.resolveStage(room, rand) == "Undertow", "host choice is the host's pick")
	assert(not edit(b, "vote", "Saltflat"), "no voting while the host picks")
	assert(edit(a, "stage", "Random"), "Random is a valid pick")
	local ranked = Rooms.mapPool("ranked")
	assert(#ranked == 3, `three ranked maps, got {#ranked}`)
	assert(edit(a, "mapSet", "ranked"))
	script_ = { 2 }
	assert(Rooms.resolveStage(room, rand) == ranked[2], "Random draws from the map set")
	assert(not edit(b, "mapChoice", "vote"), "a guest cannot change how the map is chosen")
	assert(not edit(a, "mapChoice", "coin"), "unknown map choice refused")
	assert(not edit(a, "mapSet", "silly"), "unknown map set refused")
	-- voting
	assert(edit(a, "mapChoice", "vote"))
	for _, p in { a, b, c, d } do assert(edit(p, "ready")) end
	assert(model:canStart(room))
	local stale = room.revision
	assert(not edit(b, "vote", "Smeltworks"), "a vote for a map outside the set is refused")
	assert(edit(b, "vote", "TheSpan", stale - 5), "a vote is your own, like your loadout: no revision check")
	assert(model:canStart(room), "voting un-readies nobody")
	assert(edit(c, "vote", "TheSpan") and edit(d, "vote", "Random"))
	local view = model:view(room)
	assert(view.mapChoice == "vote" and view.mapSet == "ranked", "everyone sees how the map is chosen")
	assert(view.slots[2].vote == "TheSpan" and view.slots[4].vote == "Random", "and who voted for what")
	-- ballots in slot order: b TheSpan, c TheSpan, d Random. Draw ballot 3 (Random), then map 3.
	script_ = { 3, 3 }
	assert(Rooms.resolveStage(room, rand) == ranked[3], "a Random ballot becomes any map in the set")
	script_ = { 1 }
	assert(Rooms.resolveStage(room, rand) == "TheSpan", "a drawn ballot is the map")
	-- two of three ballots for The Span: over many draws it wins about two thirds of the time
	local wins, N = 0, 3000
	local seed = 7
	local function lcg(n: number): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return (seed // 65536) % n + 1
	end
	for _ = 1, N do
		if Rooms.resolveStage(room, lcg) == "TheSpan" then wins += 1 end
	end
	assert(wins > N * 0.66 and wins < N * 0.84, `The Span with 2 of 3 ballots (plus a third of the Random one) won {wins}/{N}`)
	-- narrowing the set drops ballots that left it; changing the method clears them
	assert(edit(a, "mapSet", "all") and edit(b, "vote", "Smeltworks"))
	assert(edit(a, "mapSet", "ranked") and room.slots[2].vote == nil, "a ballot for a map that left the set is dropped")
	assert(edit(a, "mapChoice", "random"))
	for _, slot in room.slots do assert(slot.vote == nil, "changing the method clears the ballots") end
	-- no ballots: the host's pick
	assert(edit(a, "mapChoice", "vote") and edit(a, "stage", "FreightLift"))
	assert(Rooms.resolveStage(room, rand) == "FreightLift", "with nobody voting the host's pick stands")
	local _, opts = model:roster(room, function() return 1 end)
	assert(opts.stage == "FreightLift", "the resolved map reaches the match")
end
-- The battle builder: mode, time limit and presets, host-only, carried into the match.
do
	local Rules = Loader.load("Data/Rules")
	local model = Rooms.new()
	local a, b = player(61), player(62)
	local room = model:join(a, "Duel"); model:join(b, "Duel")
	local function edit(p: any, action: string, v: any): boolean
		return (model:edit(p, { id = room.id, revision = room.revision, action = action, value = v }))
	end
	assert(room.mode == "stock" and room.time == 180, "a room starts as a 3-minute-capable stock match")
	local _, opts = model:roster(room, function() return 1 end)
	assert(opts.mode == "StockTeams", "stock rooms run StockTeams")
	assert(not edit(b, "mode", "timed"), "a guest cannot change the mode")
	assert(not edit(a, "mode", "brawlball") and not edit(a, "time", 7) and not edit(a, "time", "180"), "unknown mode and times are refused")
	assert(edit(a, "mode", "timed") and edit(a, "time", 240))
	_, opts = model:roster(room, function() return 1 end)
	assert(opts.mode == "TimedTeams" and opts.timeLimit == 240, "a timed room runs TimedTeams on its own clock")
	assert(model:view(room).mode == "timed" and model:view(room).time == 240, "every member sees the rules")
	-- presets set every rule at once
	for _, p in { a, b } do assert(edit(p, "ready")) end
	assert(not edit(b, "preset", "tournament"), "a guest cannot apply a preset")
	assert(not edit(a, "preset", "anything"), "unknown preset refused")
	for _, preset in Rules.presets do
		assert(edit(a, "preset", preset.id), `preset {preset.id} applies`)
		for key, value in preset.rules do
			assert(room[key] == value, `preset {preset.id} sets {key} to {tostring(value)}, room has {tostring(room[key])}`)
		end
		assert(model:view(room).preset == preset.id, `the room shows it is on {preset.id}`)
		assert(not model:canStart(room), "a preset is a rule change: everyone re-readies")
	end
	-- a preset is a shortcut, not a mode: changing one rule stops it matching
	assert(edit(a, "preset", "tournament"))
	assert(edit(a, "stocks", 5) and model:view(room).preset == nil, "one changed rule and the room is no longer on the preset")
	-- a preset clears ballots, which may be for maps outside its set
	assert(edit(a, "mapSet", "all") and edit(a, "mapChoice", "vote") and edit(b, "vote", "Smeltworks") and edit(a, "preset", "tournament"))
	assert(room.slots[2].vote == nil, "applying a preset clears the ballots")
end
-- Weapon drops: two weapons each, always two different ones, and the room's match has drops on.
do
	local model, a = Rooms.new(), player(70)
	local room = model:join(a, "Duel")
	local function edit(action: string, value: any?, slot: number?, revision: number?): boolean
		return model:edit(a, { id = room.id, revision = revision or room.revision, action = action, value = value, slot = slot })
	end
	local mine = room.slots[1]
	assert(mine.weapon == "Sword" and mine.weapon2 == "Scythe", "a newcomer brings two different weapons, the first two starters")
	assert(edit("weapon2", "Axe") and mine.weapon == "Sword" and mine.weapon2 == "Axe", "weapon2 sets the second hand alone")
	assert(edit("weapon", "Axe") and mine.weapon == "Axe" and mine.weapon2 == "Sword", "picking the other hand's weapon swaps the two")
	assert(edit("weapon2", "Axe") and mine.weapon == "Sword" and mine.weapon2 == "Axe", "and back, from the second hand")
	assert(not edit("weapon2", "Nonsense") and mine.weapon2 == "Axe", "an unknown second weapon is refused")
	assert(edit("weapon2", "Pike", nil, room.revision - 3) and mine.weapon2 == "Pike", "your second weapon is your own: a stale revision does not refuse it")
	local seen = model:view(room).slots[1]
	assert(seen.weapon == "Sword" and seen.weapon2 == "Pike", "the room view carries both weapons")
	-- the pair is remembered: a new room starts with it
	model:leave(a)
	room = model:join(a, "Duel")
	assert(room.slots[1].weapon == "Sword" and room.slots[1].weapon2 == "Pike", "the profile keeps both weapons")
	-- a bot brings a second weapon, not its sword again
	assert(edit("bot", "hard", 2))
	local bot = room.slots[2]
	assert(bot.bot and bot.weapon and bot.weapon2 and bot.weapon2 ~= bot.weapon, "a bot brings two different weapons")
	local roster, opts = model:roster(room, function() return 1 end)
	assert(opts.weaponDrops == true, "a room's match has weapon drops on")
	for i, entry in roster do
		local slot = room.slots[i]
		assert(entry.kit and entry.kit[1] == slot.weapon and entry.kit[2] == slot.weapon2 and entry.weapon == slot.weapon,
			"every fighter's roster entry carries its pair")
	end
	room.phase = "map"
	assert(not edit("weapon2", "Axe") and room.slots[1].weapon2 == "Pike", "the second weapon locks with the first once the votes begin")
end
print("PASS rooms: two weapons each (different, swapped on a repeat, remembered, a bot's too) and drops on for room matches; 2/4/6 humans, equal teams, readiness, ownership, bots opt-in, stale edits, host transfer, cleanup, fullest-room-first and loadout edits that survive a teammate's ready, host-only disasters (off by default), map choice by host, vote or random, map sets and weighted ballots, stock or timed, time limits and presets")
