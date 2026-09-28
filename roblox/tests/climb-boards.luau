--!strict
-- The Skyline Climb leaderboards: what is written, how the boards are ranked and decoded, the
-- two-hour schedule every server shares, and stores that fail.
local Loader = require("./loader")
local ClimbBoards = Loader.loadFrom("src/server/", "ClimbBoards")
local PERIOD = ClimbBoards.PERIOD

-- An OrderedDataStore: integers by key, sorted pages, UpdateAsync with "nil means leave it".
local function ordered(): any
	local s: any = { data = {}, failing = false, writes = 0, reads = 0 }
	s.calls = 0
	function s.UpdateAsync(_, key, fn)
		s.calls += 1
		if s.failing then error("throttled") end
		local new = fn(s.data[key])
		if new ~= nil then s.data[key] = new; s.writes += 1 end
	end
	function s.GetSortedAsync(_, ascending, size)
		s.reads += 1
		if s.failing then error("throttled") end
		local list = {}
		for k, v in s.data do table.insert(list, { key = k, value = v }) end
		table.sort(list, function(a, b) if a.value == b.value then return a.key < b.key end
			return if ascending then a.value < b.value else a.value > b.value end)
		local page = {}
		for i = 1, math.min(size, #list) do page[i] = list[i] end
		return { GetCurrentPage = function() return page end }
	end
	return s
end

local speed, levels = ordered(), ordered()
local now = 5 * PERIOD + 1234
local lookups = 0
local b = ClimbBoards.new({ speed = speed, levels = levels, clock = function() return now end,
	name = function(id) lookups += 1; if id == 13 then error("no such user") end return `player{id}` end })

-- 1. Records go in; only what improves is written.
b:submit(1, { best = 8, summits = 3, bestFrames = 90 * 60 })
b:submit(2, { best = 8, summits = 1, bestFrames = 75 * 60 })
b:submit(3, { best = 5, summits = 0 })
b:submit(4, { best = 0, summits = 0 })
b:flush()
assert(speed.data["1"] == 90 * 60 and speed.data["2"] == 75 * 60 and speed.data["3"] == nil, "full climbs go on FASTEST")
assert(levels.data["3"] == ClimbBoards.levelScore(5, 0) and levels.data["4"] == nil, "a climber who never left the bottom is not on HIGHEST")
local writes = speed.writes + levels.writes
b:submit(1, { best = 8, summits = 3, bestFrames = 95 * 60 })
b:flush()
assert(speed.writes + levels.writes == writes, "nothing is rewritten when the record did not improve")
local calls = speed.calls + levels.calls
b:submit(1, { best = 8, summits = 3, bestFrames = 90 * 60 })
b:flush()
assert(speed.calls + levels.calls == calls, "an equal record is not even sent to the store")
b:submit(1, { best = 8, summits = 4, bestFrames = 95 * 60 })
b:flush()
assert(levels.data["1"] == ClimbBoards.levelScore(8, 4) and speed.data["1"] == 90 * 60, "a new Summit moves HIGHEST; a slower time leaves FASTEST")
-- A better value stored by another server (or an older session) is never replaced by a worse one.
speed.data["5"], levels.data["5"] = 60 * 60, ClimbBoards.levelScore(8, 50)
b:submit(5, { best = 6, summits = 0, bestFrames = 99 * 60 })
b:flush()
assert(speed.data["5"] == 60 * 60 and levels.data["5"] == ClimbBoards.levelScore(8, 50), "the store keeps the better record")
writes = speed.writes + levels.writes
b:submit(6, { best = 0, summits = 0, bestFrames = 60 * 60 })
speed.data["6"], levels.data["6"] = 60 * 60, 0
b:flush()
b.sent[6] = nil
assert(speed.writes + levels.writes == writes, "an equal stored time is left alone")
speed.data["6"], levels.data["6"] = nil, nil

-- 2. Reading the boards: ranked, decoded, named.
b:submit(13, { best = 2, summits = 0 })
b:flush()
assert(b:due(now), "a new server reads the boards at once")
assert(b:refresh(now), "the boards are read")
local v = b:view()
local order = {}
for _, r in v.speed do table.insert(order, r.userId) end
assert(table.concat(order, ",") == "5,2,1", `FASTEST is lowest time first: {table.concat(order, ",")}`)
assert(v.speed[1].rank == 1 and v.speed[1].frames == 60 * 60 and v.speed[1].name == "player5", "rows carry rank, time and name")
order = {}
for _, r in v.levels do table.insert(order, r.userId) end
assert(table.concat(order, ",") == "5,1,2,3,13", `HIGHEST is furthest, then most Summits: {table.concat(order, ",")}`)
assert(v.levels[2].best == 8 and v.levels[2].summits == 4 and v.levels[4].best == 5 and v.levels[4].summits == 0, "HIGHEST decodes checkpoint and Summits")
assert(v.levels[5].name == "Climber 13", "a name that cannot be looked up still gets a row")
assert(v.updatedAt == now and v.nextAt == 6 * PERIOD, "the boards say when they were read and when the next come")

-- 3. The schedule: every two hours on the clock's marks, the same for every server.
b:submit(9, { best = 8, summits = 1, bestFrames = 50 * 60 })
b:flush()
now = 6 * PERIOD - 1
assert(not b:due(now), "a record set now waits for the next two-hour mark")
assert(b:view().speed[1].userId == 5, "and the boards on show do not change before it")
now = 6 * PERIOD
assert(b:due(now), "on the mark, the boards are due")
local names = lookups
b:refresh(now)
assert(b:view().speed[1].userId == 9 and b:view().nextAt == 7 * PERIOD, "the new record shows on the next boards")
assert(lookups == names + 1, `names are looked up once a session ({lookups - names} lookups for one new climber)`)
assert(not b:due(now + PERIOD - 1), "and not again for two hours")
local other = ClimbBoards.new({ speed = speed, levels = levels })
other:refresh(now + 600)
assert(other:view().nextAt == b:view().nextAt, "a server started later shows the same next update")

-- 4. Stores that fail: the boards on show stay, reads retry in a minute, writes stay queued.
now = 7 * PERIOD
speed.failing = true
assert(b:due(now) and not b:refresh(now), "a failed read")
assert(b:view().speed[1].userId == 9 and b:view().nextAt == 7 * PERIOD, "keeps the boards that were showing")
assert(not b:due(now + 30) and b:due(now + ClimbBoards.RETRY), "and tries again in a minute, not every tick")
b:submit(20, { best = 3, summits = 0, bestFrames = nil })
b:submit(21, { best = 8, summits = 1, bestFrames = 70 * 60 })
b:flush()
assert(levels.data["21"] == ClimbBoards.levelScore(8, 1) and b.pending[21] and b.pending[21].speed, "a failed write stays queued, the half that worked does not")
speed.failing = false
b:flush()
assert(speed.data["21"] == 70 * 60 and not b.pending[21], "and is written when the store answers")
levels.failing = true
assert(not b:refresh(now + ClimbBoards.RETRY) and b:view().nextAt == 7 * PERIOD, "one board failing is a failed read too")
levels.failing = false
assert(b:refresh(now + 2 * ClimbBoards.RETRY) and b:view().nextAt == 8 * PERIOD, "the retry reads the boards")

-- A write yields; a better time submitted while it waits is written next, not lost.
local during = true
local update = speed.UpdateAsync
speed.UpdateAsync = function(store, key, fn)
	if during and key == "30" then during = false; b:submit(30, { best = 8, summits = 2, bestFrames = 55 * 60 }) end
	return update(store, key, fn)
end
b:submit(30, { best = 8, summits = 1, bestFrames = 65 * 60 })
b:flush()
assert(speed.data["30"] == 65 * 60 and b.pending[30] and b.pending[30].speed == 55 * 60, "a record set during a write waits for the next")
b:flush()
assert(speed.data["30"] == 55 * 60 and levels.data["30"] == ClimbBoards.levelScore(8, 2), "and is written then")
speed.UpdateAsync = update

-- 5. The board is only so long.
for id = 100, 160 do b:submit(id, { best = 1, summits = 0 }) end
b:flush()
b:refresh(9 * PERIOD)
assert(#b:view().levels == ClimbBoards.SIZE and b:view().levels[ClimbBoards.SIZE].rank == ClimbBoards.SIZE, "a board is SIZE rows")

-- 6. No stores at all (Studio without API access): offline, and nothing is tried.
local off = ClimbBoards.new({})
off:submit(1, { best = 8, summits = 1, bestFrames = 3000 })
off:flush()
assert(off:view().offline and not off:due(0) and #off:view().speed == 0, "no stores: the boards say they are offline")
assert(next(off.pending) == nil, "and nothing is queued for a store that is not there")
print(`PASS climb boards: improving records only, better record kept, ranked and decoded, every {PERIOD // 3600} hours on the clock, failures kept and retried`)
