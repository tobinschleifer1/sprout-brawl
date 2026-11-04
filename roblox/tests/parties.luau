--!strict
-- Parties (Roblox only): invites, joining, leading, leaving - and a party's fight, every member in
-- one room on one side, the queue filling the rest.
--
--     lune run tests/parties
local Loader = require("./loader")
local Parties = Loader.loadFrom("src/server/", "Parties")
local Rooms = Loader.loadFrom("src/server/", "Rooms")

local t = 0
local function clock(): number return t end

-- 1. Invites and joining.
do
	local P = Parties.new(clock)
	assert(not P:invite(1, 1), "a player invited themselves")
	assert(P:invite(1, 2) and P:invited(2, 1), "an invite was not recorded")
	-- the invite is shown to the invited, with its time, and to the inviter as sent
	local v2 = P:view(2, function(id) return `P{id}` end)
	assert(#v2.invites == 1 and v2.invites[1].from == 1 and v2.invites[1].name == "P1" and v2.invites[1].left == Parties.INVITE_SECONDS,
		"the invited player is not shown the invite")
	local v1 = P:view(1, function(id) return `P{id}` end)
	assert(#v1.sent == 1 and v1.sent[1] == 2 and #v1.members == 1 and v1.leader, "the inviter does not see the invite as sent")
	-- it runs out
	t = Parties.INVITE_SECONDS + 1
	assert(not P:invited(2, 1) and #P:view(2, function() return "" end).invites == 0, "an invite outlived its time")
	assert(not P:accept(2, 1), "a run-out invite was accepted")
	-- accepted, the inviter leads a party of two
	t = 0
	assert(P:invite(1, 2))
	local party = P:accept(2, 1)
	assert(party and party.leader == 1 and #party.members == 2 and P:partyOf(1) == party and P:partyOf(2) == party, "accepting did not make a party")
	local m = P:members(2)
	assert(m[1] == 1 and m[2] == 2, "the leader is not first")
	assert(P:isLeader(1) and not P:isLeader(2) and P:isLeader(99), "the lead is wrong")
	assert(not P:accept(2, 1), "the same invite was accepted twice")
	-- only the leader invites; nobody already in a party is invited; at most MAX
	assert(not P:invite(2, 3), "a member who is not the leader invited")
	assert(P:invite(1, 3) and P:accept(3, 1), "the leader could not invite a third")
	assert(#P:members(1) == Parties.MAX and Parties.MAX == 3, "the party is not three")
	assert(not P:invite(1, 4), "a full party invited a fourth")
	assert(P:invite(5, 6) and P:accept(6, 5))
	assert(not P:invite(1, 5), "someone in another party was invited")
	-- an invite to someone who has since joined another party is refused on accept
	local Q = Parties.new(clock)
	assert(Q:invite(1, 2) and Q:invite(3, 2))
	assert(Q:accept(2, 1))
	assert(not Q:accept(2, 3), "accepted a second party while in the first")
	assert(#Q:view(2, function() return "" end).invites == 0, "joining a party left other invites showing")
	-- a leader with room to spare still cannot invite someone in another party
	local O = Parties.new(clock)
	assert(O:invite(1, 2) and O:accept(2, 1) and O:invite(5, 6) and O:accept(6, 5))
	assert(not O:invite(1, 6), "someone in another party was invited")
	-- invited, then leading a party of your own: the old invite is refused on accept
	local L = Parties.new(clock)
	assert(L:invite(3, 2) and L:invite(2, 4) and L:accept(4, 2))
	assert(L:invited(2, 3) and not L:accept(2, 3) and L:partyOf(2).leader == 2, "a party's leader joined another party")
	-- declined
	local D = Parties.new(clock)
	assert(D:invite(1, 2)); D:decline(2, 1)
	assert(not D:accept(2, 1), "a declined invite was accepted")
end

-- 2. Leaving.
do
	local P = Parties.new(clock)
	assert(P:invite(1, 2) and P:accept(2, 1) and P:invite(1, 3) and P:accept(3, 1))
	local left = P:leave(1)
	assert(#left == 2 and P:partyOf(2) and P:partyOf(2).leader == 2, "the lead did not pass to the next member")
	assert(P:partyOf(1) == nil and P:isLeader(1), "the leaver is still in the party")
	left = P:leave(3)
	assert(#left == 1 and left[1] == 2 and P:partyOf(2) == nil, "a party of one was kept")
	-- leaving the server: out of the party, and the invites to and from them gone
	local Q = Parties.new(clock)
	assert(Q:invite(4, 1) and Q:invite(1, 2) and Q:accept(2, 1) and Q:invite(1, 3))
	local tell = Q:forget(1)
	assert(Q:partyOf(2) == nil and not Q:invited(3, 1) and not Q:invited(1, 4), "a departed player's party or invites remain")
	assert(table.find(tell, 2) and table.find(tell, 3), "those left behind and those invited were not told")
end

-- 3. A party's fight (Rooms.queueParty).
local newRooms = Rooms.new
local function rooms(): any local r = newRooms(); r.levelOf = function(_: number): number return 50 end; r.clock = clock; return r end
local function player(id: number): any return { UserId = id, DisplayName = `Player{id}`, Name = `Player{id}` } end
local function side(room: any, players: { any }): number?
	local team = nil
	for _, p in players do
		local found = nil
		for _, slot in room.slots do if slot.player == p then found = slot.team end end
		if found == nil or (team ~= nil and found ~= team) then return nil end
		team = found
	end
	return team
end
do
	-- three into a 3v3: one new room, all on one side, the rest open
	local R = rooms()
	local a, b, c = player(1), player(2), player(3)
	local changed = R:queueParty({ a, b, c }, "Triples")
	local room = changed and changed[1]
	assert(room and room.format == "Triples" and R:get(1) == room and R:get(2) == room and R:get(3) == room, "the party was not seated together")
	assert(side(room, { a, b, c }) ~= nil, "the party was split between the sides")
	assert(room.host == 1, "the leader does not host")
	-- solo players queued after fill the other side, not the party's
	for id = 10, 12 do R:queue(player(id), "Triples") end
	R:tick()
	local others = {}
	for _, slot in room.slots do if slot.player and slot.player.UserId >= 10 then table.insert(others, slot.player) end end
	assert(#others == 3 and side(room, others) ~= nil and side(room, others) ~= side(room, { a, b, c }), "the queue did not fill the other side")
	-- a room with places open on both sides: the party takes one side, not some of each
	local T = rooms()
	local solo = player(20)
	T:join(solo, "Triples")
	local x, y, z = player(21), player(22), player(23)
	local seatedIn = T:queueParty({ x, y, z }, "Triples")[1]
	assert(seatedIn == T:get(20) and side(seatedIn, { x, y, z }) ~= nil and side(seatedIn, { x, y, z }) ~= side(seatedIn, { solo }),
		"the party was spread over both sides of a room")
	-- a second party of two finds the open side of a 2v2 a first party of two is in
	local S = rooms()
	local first = S:queueParty({ player(1), player(2) }, "Doubles")[1]
	local second = S:queueParty({ player(3), player(4) }, "Doubles")[1]
	assert(first == second and side(first, { player(1), player(2) }) == nil, "two parties of two did not meet")
	local s1, s2 = 0, 0
	for _, slot in first.slots do
		if slot.player and slot.player.UserId <= 2 then s1 += 1 end
		if slot.player and slot.player.UserId >= 3 then s2 += 1 end
	end
	assert(s1 == 2 and s2 == 2, "the parties are not seated")
	local teamOf = {}
	for _, slot in first.slots do if slot.player then teamOf[slot.player.UserId] = slot.team end end
	assert(teamOf[1] == teamOf[2] and teamOf[3] == teamOf[4] and teamOf[1] ~= teamOf[3], "a party was split")
	-- two friends pick 1v1: a room of their own, against each other
	local D = rooms()
	local duel = D:queueParty({ player(1), player(2) }, "Duel")[1]
	assert(duel and D:get(1) == duel and D:get(2) == duel and duel.slots[1].team ~= duel.slots[2].team, "two friends could not 1v1")
	-- too many for the side; Ranked alone; a member already in a room
	local E = rooms()
	local none, why = E:queueParty({ player(1), player(2), player(3) }, "Doubles")
	assert(none == nil and why and string.find(why, "too many", 1, true), "three were seated in a 2v2 side")
	none, why = E:queueParty({ player(1), player(2) }, "Ranked")
	assert(none == nil and why and string.find(why, "alone", 1, true), "a party queued for Ranked")
	E:join(player(2), "FFA4")
	none, why = E:queueParty({ player(1), player(2) }, "FFA4")
	assert(none == nil and why and string.find(why, "Player2", 1, true) and E:get(1) == nil, "a member already in a room was seated twice")
	-- a member queued alone is taken out of that queue when the party goes in
	local F = rooms()
	local p1, p2 = player(1), player(2)
	F:queue(p2, "FFA6")
	assert(F:queued(2) == "FFA6")
	F:queueParty({ p1, p2 }, "FFA4")
	assert(F:queued(2) == nil and F:get(2) ~= nil, "a party member stayed in their own queue")
end

print("PASS parties: invites shown and timed, accepted into a party the inviter leads, the leader alone invites, at most three, declined and run-out invites refused; leaving passes the lead and a party of one ends; leaving the server clears it all; a party's fight seats it on one side, the queue fills the other, two parties of two meet, two friends can 1v1, too many and Ranked refused")
