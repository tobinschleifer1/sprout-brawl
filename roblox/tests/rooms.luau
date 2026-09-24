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
print("PASS rooms: 2/4/6 humans, equal teams, readiness, ownership, bots opt-in, stale edits, host transfer and cleanup")
