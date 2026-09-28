--!strict
-- The arcade's cabinets: who sits where, when a fight starts, who wins the seat, who is watching.
-- After the P4A lobby - sit at a cabinet, and whoever sits across from you is your opponent; the
-- winner keeps the seat and builds a streak, the loser gets up; anyone can walk up and watch.
--
-- Pure bookkeeping, like Rooms: no transport, no simulation, a clock passed in. init.server.luau
-- turns its decisions into matches and messages; tests/cabinets.luau drives it directly.

local Shared = game:GetService("ReplicatedStorage").Shared
local PLAZA: any = require(Shared.Data.Plaza)

local Cabinets = {}
Cabinets.__index = Cabinets

Cabinets.COUNTDOWN = 4        -- seconds from the second player sitting down to the fight starting
Cabinets.SIDES = { "A", "B" }

function Cabinets.new(): any
	local self: any = setmetatable({ cabs = {}, seatOf = {}, watching = {} }, Cabinets)
	for _, c in PLAZA.cabinets do
		self.cabs[c.number] = { number = c.number, seats = {}, state = "open", streak = nil, spectators = {}, startAt = nil }
	end
	return self
end

function Cabinets.get(self: any, n: any): any
	return if type(n) == "number" then self.cabs[n] else nil
end

-- Take a seat. Refused if you are already seated or watching, the seat is taken, or the cabinet is
-- mid-fight. The second player sitting starts the countdown.
function Cabinets.sit(self: any, player: any, n: any, side: any, now: number): (boolean, string?)
	local cab = self:get(n)
	if not cab or (side ~= "A" and side ~= "B") then return false, "No such seat." end
	if self.seatOf[player.UserId] then return false, "You are already sitting down." end
	if cab.state == "playing" then return false, "A fight is on at this cabinet. Watch, or wait for the winner." end
	if cab.seats[side] then return false, "Someone is sitting there." end
	cab.seats[side] = { player = player, since = now }
	self.seatOf[player.UserId] = { n = n, side = side }
	self:stopWatching(player)
	if cab.seats.A and cab.seats.B then
		cab.state, cab.startAt = "countdown", now + Cabinets.COUNTDOWN
	end
	return true, nil
end

-- Get up. Not mid-fight (leaving a fight is a disconnect's job). Getting up during the countdown
-- cancels it. Returns the cabinet.
function Cabinets.stand(self: any, player: any): any
	local at = self.seatOf[player.UserId]
	if not at then return nil end
	local cab = self.cabs[at.n]
	if cab.state == "playing" then return nil end
	cab.seats[at.side] = nil
	self.seatOf[player.UserId] = nil
	if cab.streak and cab.streak.userId == player.UserId then cab.streak = nil end
	cab.state, cab.startAt = "open", nil
	return cab
end

-- Alone at a cabinet: fight the CPU.
function Cabinets.vsCpu(self: any, player: any): any
	local at = self.seatOf[player.UserId]
	if not at then return nil end
	local cab = self.cabs[at.n]
	-- "open" also means alone: a second player sitting down always starts the countdown, so there
	-- is no separate check for someone across (a mutation test showed it could never fire).
	if cab.state ~= "open" then return nil end
	cab.state, cab.cpu = "playing", true
	return cab
end

-- Countdowns that have run out: those cabinets start now.
function Cabinets.due(self: any, now: number): { any }
	local out = {}
	for n = 1, #PLAZA.cabinets do
		local cab = self.cabs[n]
		if cab.state == "countdown" and now >= cab.startAt then
			cab.state, cab.startAt, cab.cpu = "playing", nil, false
			table.insert(out, cab)
		end
	end
	return out
end

-- The fight is over. The winner keeps their seat and their streak grows (or starts); the loser gets
-- up. Against the CPU nobody loses the seat, and a win counts. Returns the players who got up.
function Cabinets.finish(self: any, n: number, winnerUserId: number?): { any }
	local cab = self.cabs[n]
	local up = {}
	if not cab then return up end
	for _, side in Cabinets.SIDES do
		local seat = cab.seats[side]
		if seat and not cab.cpu and winnerUserId and seat.player.UserId ~= winnerUserId then
			cab.seats[side] = nil
			self.seatOf[seat.player.UserId] = nil
			table.insert(up, seat.player)
		end
	end
	if winnerUserId then
		if cab.streak and cab.streak.userId == winnerUserId then
			cab.streak.wins += 1
		else
			local name = "?"
			for _, side in Cabinets.SIDES do
				local seat = cab.seats[side]
				if seat and seat.player.UserId == winnerUserId then name = seat.player.DisplayName end
			end
			cab.streak = { userId = winnerUserId, name = name, wins = 1 }
		end
	end
	cab.state, cab.cpu = "open", nil
	for p in cab.spectators do self.watching[p.UserId] = nil end
	table.clear(cab.spectators)
	return up
end

-- A fight cut short (a player left): everyone gets up, nobody wins.
function Cabinets.cancel(self: any, n: number): { any }
	local cab = self.cabs[n]
	local out = {}
	for _, side in Cabinets.SIDES do
		local seat = cab.seats[side]
		if seat then
			table.insert(out, seat.player)
			self.seatOf[seat.player.UserId] = nil
		end
	end
	table.clear(cab.seats)
	cab.state, cab.startAt, cab.cpu, cab.streak = "open", nil, nil, nil
	for p in cab.spectators do self.watching[p.UserId] = nil end
	table.clear(cab.spectators)
	return out
end

function Cabinets.watch(self: any, player: any, n: any): boolean
	local cab = self:get(n)
	if not cab or cab.state ~= "playing" or self.seatOf[player.UserId] then return false end
	self:stopWatching(player)
	cab.spectators[player] = true
	self.watching[player.UserId] = n
	return true
end

function Cabinets.stopWatching(self: any, player: any): number?
	local n = self.watching[player.UserId]
	if not n then return nil end
	self.cabs[n].spectators[player] = nil
	self.watching[player.UserId] = nil
	return n
end

-- A player leaving the game: out of any seat (cancelling a fight they were in) and any audience.
-- Returns the cabinet whose fight was cancelled, if one was.
function Cabinets.leave(self: any, player: any): any
	self:stopWatching(player)
	local at = self.seatOf[player.UserId]
	if not at then return nil end
	local cab = self.cabs[at.n]
	if cab.state == "playing" then
		return cab
	end
	self:stand(player)
	return nil
end

-- What everyone on the market floor is told about the arcade.
function Cabinets.views(self: any, now: number): { any }
	local out = {}
	for n = 1, #PLAZA.cabinets do
		local cab = self.cabs[n]
		local seats = {}
		for _, side in Cabinets.SIDES do
			local seat = cab.seats[side]
			if seat then seats[side] = { userId = seat.player.UserId, name = seat.player.DisplayName } end
		end
		local watchers = 0
		for _ in cab.spectators do watchers += 1 end
		table.insert(out, { number = n, state = cab.state, seats = seats, cpu = cab.cpu == true,
			startsIn = if cab.startAt then math.max(0, cab.startAt - now) else nil,
			streak = if cab.streak then { userId = cab.streak.userId, name = cab.streak.name, wins = cab.streak.wins } else nil,
			watchers = watchers })
	end
	return out
end

return Cabinets
