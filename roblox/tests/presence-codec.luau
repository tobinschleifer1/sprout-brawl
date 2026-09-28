--!strict
-- Lobby presence on the wire (shared/PresenceCodec): positions round-trip exactly, identity comes
-- from the roster, the roster's signature changes with identity and not with position, and nothing
-- a client is sent can make it draw garbage.
local Loader = require("./loader")
local P = Loader.load("PresenceCodec")

local people = {
	{ userId = 1, name = "ada", avatar = "k1aaaa", weapon = "Sword", x = 12.345678901234, z = 5.5, y = 0, facing = 1, moving = false },
	{ userId = 9876543210, name = "bo", avatar = "k1bbbb", weapon = "Pike", x = -140.1, z = 17.9, y = 2.25, facing = -1, moving = true },
	{ userId = 3, name = "cy", avatar = "k1cccc", weapon = "Axe", x = 0.1, z = 0.3, y = 5.9, facing = 1, moving = true },
}
local roster = P.index(P.roster(people))
local b = P.encode(4, people)
assert(buffer.len(b) == 10 + 3 * P.ENTRY, `three people are {buffer.len(b)} bytes`)
local back = P.decode(b, roster)
assert(#back == 3, "everyone comes back")
for i, e in back do
	local want = people[i]
	assert(e.userId == want.userId and e.area == 4, `{i}: who and where`)
	assert(e.x == want.x and e.z == want.z, `{i}: a position arrives exactly as sent ({e.x}, {e.z})`)
	assert(math.abs(e.y - want.y) < 1e-6, `{i}: the hop within a millionth`)
	assert(e.facing == want.facing and e.moving == want.moving, `{i}: facing and moving`)
	assert(e.name == want.name and e.avatar == want.avatar and e.weapon == want.weapon, `{i}: identity from the roster`)
end

-- Someone the roster does not know yet is left out, not drawn nameless.
local partial = P.index({ { userId = 1, name = "ada", avatar = "k1aaaa", weapon = "Sword" } })
local some = P.decode(b, partial)
assert(#some == 1 and some[1].userId == 1, "only people the roster knows are drawn")

-- Malformed: not a buffer, too short, the wrong length for its count - all nothing.
assert(#P.decode({}, roster) == 0 and #P.decode(nil, roster) == 0, "not a buffer")
assert(#P.decode(buffer.create(3), roster) == 0, "too short")
local long = buffer.create(buffer.len(b) + 1)
buffer.copy(long, 0, b)
assert(#P.decode(long, roster) == 0, "a length that disagrees with the count")
assert(#P.decode(P.encode(0, {}), roster) == 0, "an empty lobby")

-- The signature: identity changes it, position does not, and order does not matter once sorted.
local sig = P.signature(people)
local moved = table.clone(people)
moved[1] = table.clone(people[1]); moved[1].x += 3; moved[1].moving = true
assert(P.signature(moved) == sig, "moving does not re-send the roster")
for _, field in { "name", "avatar", "weapon", "userId" } do
	local changed = table.clone(people)
	changed[2] = table.clone(people[2])
	changed[2][field] = if field == "userId" then 5 else "other"
	assert(P.signature(changed) ~= sig, `a changed {field} re-sends the roster`)
end
assert(P.signature({ people[1], people[2] }) ~= sig, "someone leaving re-sends the roster")

-- A roster from the wire is only trusted where it has the shape of one.
local idx = P.index({ { userId = 2, name = "x" }, "junk", { name = "no id" }, 7 })
assert(idx[2] and idx[2].name == "x", "a good entry is kept")
local n = 0
for _ in idx do n += 1 end
assert(n == 1 and next(P.index(nil)) == nil and next(P.index("x")) == nil, "and only that")
print(`PASS presence codec: {P.ENTRY} bytes a person, positions exact, identity from the roster only on change, malformed input ignored`)
