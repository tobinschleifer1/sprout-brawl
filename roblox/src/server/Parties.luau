--!strict
-- Parties (Roblox only; the owner's ask, 2026-11-04): players in the same server group up to fight
-- together. One invites another; the invited player gets a pop-up - JOIN NAME'S PARTY? - and joins
-- on JOIN. The first to invite leads; the leader picks the fight from PLAY, and the whole party goes
-- into one room, on one side (Rooms.queueParty). Leaving hands the lead to the next member; a party
-- left with one player is gone.
--
-- Pure bookkeeping by user id, with no Players or remotes, so the rules are tested in Lune
-- (tests/parties.luau). The server checks who may be invited (someone in this server, loaded) and
-- sends each player what they should see (Parties.view).
local Parties = {}
Parties.__index = Parties

-- the biggest side a fight has (3v3), so a party always fits one side of some fight
Parties.MAX = 3
-- an invite not answered by then is gone (the pop-up counts down from it)
Parties.INVITE_SECONDS = 30

function Parties.new(clock: (() -> number)?): any
	return setmetatable({ of = {} :: { [number]: any }, invites = {} :: { [number]: { [number]: number } },
		clock = clock or os.clock }, Parties)
end

-- The party `id` is in, or nil when on their own.
function Parties.partyOf(self: any, id: number): any
	return self.of[id]
end

-- Who `id` fights with: their party's members, leader first, or just them.
function Parties.members(self: any, id: number): { number }
	local p = self.of[id]
	return if p then table.clone(p.members) else { id }
end

function Parties.isLeader(self: any, id: number): boolean
	local p = self.of[id]
	return p == nil or p.leader == id
end

-- `from` invites `to`. Returns true, or false and why.
function Parties.invite(self: any, from: number, to: number): (boolean, string?)
	if from == to then return false, "You cannot invite yourself." end
	local mine = self.of[from]
	if mine and table.find(mine.members, to) then return false, "They are already in your party." end
	if self.of[to] then return false, "They are already in a party." end
	if mine and mine.leader ~= from then return false, "Only your party leader can invite." end
	if mine and #mine.members >= Parties.MAX then return false, `A party is at most {Parties.MAX}.` end
	self.invites[to] = self.invites[to] or {}
	self.invites[to][from] = self.clock() + Parties.INVITE_SECONDS
	return true, nil
end

-- Is there an invite from `from` to `to` still open?
function Parties.invited(self: any, to: number, from: number): boolean
	local at = self.invites[to] and self.invites[to][from]
	return at ~= nil and self.clock() < at
end

-- `to` accepts `from`'s invite. Returns the party, or nil and why.
function Parties.accept(self: any, to: number, from: number): (any, string?)
	if not Parties.invited(self, to, from) then
		if self.invites[to] then self.invites[to][from] = nil end
		return nil, "That invite has run out."
	end
	if self.of[to] then return nil, "Leave your party first." end
	local p = self.of[from]
	if p and p.leader ~= from then return nil, "They are no longer leading their party." end
	if p and #p.members >= Parties.MAX then return nil, "Their party is full." end
	if not p then
		p = { leader = from, members = { from } }
		self.of[from] = p
	end
	table.insert(p.members, to)
	self.of[to] = p
	-- (in a party now: every other invite to them is moot)
	self.invites[to] = nil
	return p, nil
end

function Parties.decline(self: any, to: number, from: number)
	if self.invites[to] then self.invites[to][from] = nil end
end

-- `id` leaves their party. Returns who is left in it (to tell them), possibly empty.
function Parties.leave(self: any, id: number): { number }
	local p = self.of[id]
	if not p then return {} end
	self.of[id] = nil
	table.remove(p.members, table.find(p.members, id) :: number)
	if p.leader == id then p.leader = p.members[1] end
	local left = table.clone(p.members)
	-- (a party of one is no party)
	if #p.members < 2 then
		for _, m in p.members do self.of[m] = nil end
		table.clear(p.members)
	end
	return left
end

-- `id` left the server: out of their party, and every invite to or from them gone. Returns the
-- players to tell (the party left behind, and anyone they had invited).
function Parties.forget(self: any, id: number): { number }
	local tell = Parties.leave(self, id)
	self.invites[id] = nil
	for to, from in self.invites do
		if from[id] then
			from[id] = nil
			if not table.find(tell, to) then table.insert(tell, to) end
		end
	end
	return tell
end

-- What `id` sees: their party (leader first), whether they lead it, the invites waiting for them
-- with the seconds left, and whom they have invited. `nameOf(userId)` names a player.
function Parties.view(self: any, id: number, nameOf: (number) -> string): any
	local now = self.clock()
	local members = {}
	for _, m in Parties.members(self, id) do
		table.insert(members, { id = m, name = nameOf(m), leader = self.of[id] ~= nil and self.of[id].leader == m })
	end
	local invites = {}
	for from, at in self.invites[id] or {} do
		if now < at then table.insert(invites, { from = from, name = nameOf(from), left = math.ceil(at - now) }) end
	end
	table.sort(invites, function(a, b) return a.left > b.left end)
	local sent = {}
	for to, from in self.invites do
		if from[id] and now < from[id] then table.insert(sent, to) end
	end
	table.sort(sent)
	return { members = members, leader = Parties.isLeader(self, id), invites = invites, sent = sent, max = Parties.MAX }
end

return Parties
