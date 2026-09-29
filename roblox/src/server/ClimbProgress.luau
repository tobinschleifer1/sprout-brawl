--!strict
-- Progress on the Skyline Climb: the furthest checkpoint each player has reached, how many times
-- they have reached the Summit, and their best full climb. Kept in the player's saved record
-- (AvatarStore, `climb`), because it is what rewards will be built on later.
--
-- The climbing itself runs on the client (the course is single-player and the fighter needs to
-- answer the stick on the frame it moves), so the server cannot watch it happen. What it can do is
-- refuse claims no climber could make: a checkpoint behind the one they are already past, a run of
-- checkpoints faster than MIN_STEP seconds each, a Summit time shorter than the course allows or
-- longer than they have actually been climbing. A best time only counts for a climb from the start.
--
-- Paid skips (SkipProducts) move a player one checkpoint on. What they bought is where they resume
-- (`best`), not what they climbed (`climbed`, which the leaderboards read); a climb with a skip in
-- it sets no best time, and the Summit counts only when its checkpoint was climbed to.

local ClimbProgress = {}
ClimbProgress.__index = ClimbProgress

ClimbProgress.MIN_STEP = 2          -- seconds per checkpoint advanced, at the very least
ClimbProgress.MIN_SUMMIT = 40       -- seconds for a whole climb from the start, at the very least

function ClimbProgress.new(store: any, checkpoints: number): any
	return setmetatable({ store = store, last = checkpoints - 1, sessions = {} }, ClimbProgress)
end

-- The saved progress, rebuilt from whatever is stored.
function ClimbProgress.record(self: any, userId: number): any
	local rec = self.store:load(userId)
	local c = if type(rec.climb) == "table" then rec.climb else {}
	local function int(v: any, lo: number, hi: number): number
		return if type(v) == "number" and v == v and v % 1 == 0 then math.clamp(v, lo, hi) else lo
	end
	local best = int(c.best, 0, self.last)
	rec.climb = {
		best = best,
		-- Records from before skips existed have no `climbed`: everything in them was climbed.
		climbed = if c.climbed == nil then best else math.min(int(c.climbed, 0, self.last), best),
		summits = int(c.summits, 0, 1e9),
		bestFrames = if type(c.bestFrames) == "number" and c.bestFrames == c.bestFrames and c.bestFrames % 1 == 0 and c.bestFrames > 0 then c.bestFrames else nil,
	}
	return rec.climb
end

function ClimbProgress.view(self: any, userId: number): any
	local c = self:record(userId)
	return { best = c.best, climbed = c.climbed, summits = c.summits, bestFrames = c.bestFrames }
end

-- Starting a climb, from `from` (0, or the furthest checkpoint they have reached). Returns where.
function ClimbProgress.enter(self: any, userId: number, from: any, now: number): number
	local best = self:record(userId).best
	local start = if from == 0 then 0 else best
	self.sessions[userId] = { reached = start, fromStart = start == 0, since = now, lastAt = now }
	return start
end

function ClimbProgress.leave(self: any, userId: number)
	self.sessions[userId] = nil
end

function ClimbProgress.climbing(self: any, userId: number): any
	return self.sessions[userId]
end

local function dirty(self: any, userId: number)
	self.store.dirty[userId] = self.store.dirty[userId] or self.store.clock()
end

function ClimbProgress.checkpoint(self: any, userId: number, index: any, now: number): boolean
	local s = self.sessions[userId]
	if not s or type(index) ~= "number" or index % 1 ~= 0 or index <= s.reached or index > self.last then return false end
	if now - s.lastAt < ClimbProgress.MIN_STEP * (index - s.reached) then return false end
	s.reached, s.lastAt = index, now
	if index == self.last then s.climbedLast = true end
	local c = self:record(userId)
	if index > c.best or index > c.climbed then
		c.best, c.climbed = math.max(c.best, index), math.max(c.climbed, index)
		dirty(self, userId)
	end
	return true
end

-- The Summit: counted once per climb, and a best time kept if the climb started at the bottom.
function ClimbProgress.summit(self: any, userId: number, frames: any, now: number): boolean
	local s = self.sessions[userId]
	if not s or s.reached ~= self.last or s.summited or not s.climbedLast then return false end
	s.summited = true
	local c = self:record(userId)
	c.summits += 1
	if s.fromStart and not s.skipped and type(frames) == "number" and frames == frames and frames % 1 == 0 then
		local seconds = frames / 60
		-- Not faster than the course allows, and not longer than they have been on it (plus a
		-- little for the frames the client counted before the server heard it had started).
		if seconds >= ClimbProgress.MIN_SUMMIT and seconds <= now - s.since + 2 then
			if not c.bestFrames or frames < c.bestFrames then c.bestFrames = frames end
		end
	end
	dirty(self, userId)
	return true
end

-- A paid skip: ONE checkpoint on from where the player is - their climb if they are on one, else
-- their saved progress - whichever product paid for it (so a tampered prompt cannot buy several
-- levels at one price, and a purchase that raced a climb still moves them one on). Saved as where
-- they resume; not as climbed. Returns the checkpoint moved to, or nil at the Summit already.
function ClimbProgress.skip(self: any, userId: number, now: number): number?
	local c = self:record(userId)
	local s = self.sessions[userId]
	local from = if s then s.reached else c.best
	if from >= self.last then return nil end
	local to = from + 1
	if s then
		s.reached, s.lastAt, s.skipped = to, now, true
	end
	if to > c.best then c.best = to end
	dirty(self, userId)
	return to
end

return ClimbProgress
