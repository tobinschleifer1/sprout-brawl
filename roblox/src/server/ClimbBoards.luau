--!strict
-- The Skyline Climb's leaderboards, across every server: FASTEST (the best full climb, from the
-- bottom to the Summit) and HIGHEST (the furthest checkpoint reached, ties broken by Summits).
--
-- Records go into two OrderedDataStores as they are set; the boards everyone sees are read back
-- once every two hours, on the two-hour marks of the clock (UTC 00:00, 02:00, ...), so every
-- server shows the same boards and says when the next ones come. A new server reads at once.
--
-- The stores and the clock are injected so tests/climb-boards.luau drives the real code, including
-- stores that fail - Studio without API access throws on every call, and a live store throttles.
-- A failed read keeps the boards that were showing and tries again in a minute; a failed write stays
-- queued. Nothing here is on the path of a climb: ClimbProgress has already saved the record.
--
-- OrderedDataStores hold integers, one per key. FASTEST stores frames (lower is better); HIGHEST
-- packs checkpoint * LEVEL_SPAN + Summits (higher is better), so one sort answers both.

local ClimbBoards = {}
ClimbBoards.__index = ClimbBoards

ClimbBoards.PERIOD = 2 * 60 * 60     -- seconds between the boards everyone sees
ClimbBoards.RETRY = 60               -- seconds before a failed read is tried again
ClimbBoards.SIZE = 25                -- rows on each board
ClimbBoards.LEVEL_SPAN = 1e6         -- Summits kept in a HIGHEST score before the checkpoint

-- opts: { speed = OrderedDataStore?, levels = OrderedDataStore?, clock = () -> number (os.time),
--         name = (userId) -> string? (yields; Players:GetNameFromUserIdAsync on a server) }
function ClimbBoards.new(opts: any): any
	return setmetatable({
		speed = opts.speed, levels = opts.levels, clock = opts.clock, nameOf = opts.name,
		pending = {},          -- userId -> { speed = frames?, levels = score? } waiting to be written
		sent = {},             -- userId -> { speed, levels } last written, so an unchanged record is not rewritten
		names = {},            -- userId -> name, cached for the session
		boards = { speed = {}, levels = {} },
		period = nil :: number?, -- the two-hour mark the boards on show were read for
		retryAt = 0,
		updatedAt = nil :: number?,
		offline = opts.speed == nil or opts.levels == nil,
	}, ClimbBoards)
end

function ClimbBoards.levelScore(best: number, summits: number): number
	return best * ClimbBoards.LEVEL_SPAN + math.min(summits, ClimbBoards.LEVEL_SPAN - 1)
end

-- A player's climb record (ClimbProgress:view) after it changed: queue what beats what was sent.
function ClimbBoards.submit(self: any, userId: number, view: any)
	if self.offline then return end            -- nowhere to write it: queue nothing
	local sent = self.sent[userId] or {}
	local p = self.pending[userId] or {}
	if view.bestFrames and (not sent.speed or view.bestFrames < sent.speed) then p.speed = view.bestFrames end
	-- HIGHEST ranks what was climbed, never what was bought (ClimbProgress: `climbed`).
	local climbed = view.climbed or view.best
	if climbed > 0 or view.summits > 0 then
		local score = ClimbBoards.levelScore(climbed, view.summits)
		if not sent.levels or score > sent.levels then p.levels = score end
	end
	if p.speed or p.levels then self.pending[userId] = p end
end

local function better(kind: string, a: number?, b: number?): number?
	if not a then return b end
	if not b then return a end
	return if kind == "speed" then math.min(a, b) else math.max(a, b)
end

-- Write what is queued. UpdateAsync keeps the better of the stored value and ours, so a player on
-- two servers, or a store holding a record from an older session, never loses their best.
-- The queue is swapped out first: a write yields, and a record submitted meanwhile must land in the
-- next queue, not in a table being walked (or be cleared by the write of an older value).
function ClimbBoards.flush(self: any)
	local batch = self.pending
	self.pending = {}
	local failed = false
	for userId, p in batch do
		local key = tostring(userId)
		for _, kind in { "speed", "levels" } do
			local value = p[kind]
			if value then
				local ok = pcall(function()
					self[kind]:UpdateAsync(key, function(old: any)
						if type(old) == "number" and better(kind, old, value) == old then return nil end
						return value
					end)
				end)
				local sent = self.sent[userId] or {}
				self.sent[userId] = sent
				if ok then
					sent[kind] = better(kind, sent[kind], value)
				else
					failed = true
					local q = self.pending[userId] or {}
					q[kind] = better(kind, q[kind], value)
					self.pending[userId] = q
				end
			end
		end
	end
	if failed then warn("[Blockfall] some climb records were not written yet; will retry") end
end

function ClimbBoards.due(self: any, now: number): boolean
	if self.offline then return false end
	return math.floor(now / ClimbBoards.PERIOD) ~= self.period and now >= self.retryAt
end

local function read(self: any, store: any, ascending: boolean): { any }?
	local rows: { any } = {}
	local ok = pcall(function()
		local page = store:GetSortedAsync(ascending, ClimbBoards.SIZE):GetCurrentPage()
		for _, entry in page do
			local id = tonumber(entry.key)
			if id and type(entry.value) == "number" then
				table.insert(rows, { rank = #rows + 1, userId = id, value = entry.value })
			end
		end
	end)
	return if ok then rows else nil
end

-- Read both boards for the current two-hour mark. Returns whether new boards were read.
function ClimbBoards.refresh(self: any, now: number): boolean
	local speed = read(self, self.speed, true)
	local levels = if speed then read(self, self.levels, false) else nil
	if not (speed and levels) then
		self.retryAt = now + ClimbBoards.RETRY
		if not self.failing then warn("[Blockfall] climb leaderboards could not be read; showing the last ones") end
		self.failing = true
		return false
	end
	for _, rows in { speed, levels } do
		for _, row in rows do
			if not self.names[row.userId] then
				local name: any = nil
				if self.nameOf then pcall(function() name = self.nameOf(row.userId) end) end
				self.names[row.userId] = if type(name) == "string" then name else `Climber {row.userId}`
			end
			row.name = self.names[row.userId]
		end
	end
	for _, row in levels do
		row.best = math.floor(row.value / ClimbBoards.LEVEL_SPAN)
		row.summits = row.value % ClimbBoards.LEVEL_SPAN
		row.value = nil
	end
	for _, row in speed do row.frames, row.value = row.value, nil end
	self.boards = { speed = speed, levels = levels }
	self.failing = false
	self.period = math.floor(now / ClimbBoards.PERIOD)
	self.updatedAt = now
	return true
end

-- What the client draws. Times are os.time() seconds: the client counts down to `nextAt` itself.
function ClimbBoards.view(self: any): any
	return {
		speed = self.boards.speed, levels = self.boards.levels, offline = self.offline,
		updatedAt = self.updatedAt,
		nextAt = if self.period then (self.period + 1) * ClimbBoards.PERIOD else nil,
	}
end

return ClimbBoards
