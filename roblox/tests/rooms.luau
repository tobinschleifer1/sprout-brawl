--!strict
local Loader = require("./loader")
local Rooms = Loader.loadFrom("src/server/", "Rooms")
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
	assert(not edit(people[2], "start"), "guest cannot start")
	assert(edit(people[1], "start"))
	assert(not edit(people[1], "start"), "duplicate start cannot create another match")
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
print("PASS rooms: 2/4/6 humans, equal teams, readiness, ownership, bots opt-in, stale edits, host transfer, cleanup, fullest-room-first and loadout edits that survive a teammate's ready, host-only disasters (off by default)")
