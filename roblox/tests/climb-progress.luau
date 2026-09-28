--!strict
-- Skyline Climb progress: what is saved, and which claims are refused.
local Loader = require("./loader")
local AvatarStore = Loader.loadFrom("src/server/", "AvatarStore")
local ClimbProgress = Loader.loadFrom("src/server/", "ClimbProgress")
local PARKOUR = Loader.load("Data/Parkour")
local N = #PARKOUR.course.checkpoints

local data = {}
local ds = { GetAsync = function(_, k) return data[k] end, SetAsync = function(_, k, v) data[k] = v end }
local now = 0
local store = AvatarStore.new(ds, function() return now end)
local climb = ClimbProgress.new(store, N)

-- Nothing yet.
local v = climb:view(1)
assert(v.best == 0 and v.summits == 0 and v.bestFrames == nil, "a new climber has no progress")
-- A climb from the bottom, at a believable pace.
assert(climb:enter(1, 0, now) == 0)
assert(not climb:checkpoint(1, 1, now + 1), "a checkpoint one second in is too fast to be real")
now += 3
assert(climb:checkpoint(1, 1, now), "a believable checkpoint counts")
assert(not climb:checkpoint(1, 1, now + 10), "the same checkpoint twice does not count twice")
assert(not climb:checkpoint(1, 0, now + 10) and not climb:checkpoint(1, N, now + 10) and not climb:checkpoint(1, 2.5, now + 10), "backwards, past the end, or not a checkpoint")
now += 3
assert(not climb:checkpoint(1, 4, now), "three checkpoints in three seconds is too fast")
now += 20
assert(climb:checkpoint(1, 4, now), "skipping ahead is fine at a believable pace")
assert(climb:view(1).best == 4, "the furthest checkpoint is kept")
assert(not climb:summit(1, 60 * 60, now), "no Summit before the last checkpoint")
now += 60
assert(climb:checkpoint(1, N - 1, now), "reaching the Summit's checkpoint")
assert(climb:summit(1, 10 * 60, now), "reaching the Summit counts")
v = climb:view(1)
assert(v.summits == 1 and v.bestFrames == nil, "the Summit counts even when the time is refused")
assert(not climb:summit(1, 70 * 60, now), "one Summit per climb")
-- A good full run records a best time; a later slower one does not replace it.
climb:enter(1, 0, now)
for i = 1, N - 1 do now += 10; assert(climb:checkpoint(1, i, now)) end
assert(climb:summit(1, 78 * 60, now))
assert(climb:view(1).bestFrames == 78 * 60, "a believable full climb sets the best time")
climb:enter(1, 0, now)
for i = 1, N - 1 do now += 10; climb:checkpoint(1, i, now) end
climb:summit(1, 79 * 60, now)
assert(climb:view(1).bestFrames == 78 * 60 and climb:view(1).summits == 3, "a slower climb keeps the best")
-- A climb resumed from a checkpoint cannot set a best time: it is not the whole course.
local resumed = climb:enter(1, 5, now)
assert(resumed == N - 1, "resuming starts from the furthest checkpoint reached")
climb:enter(3, 0, now)
now += 20
assert(climb:checkpoint(3, 4, now))
climb:leave(3)
assert(climb:enter(3, 4, now) == 4, "a climber who got to 4 resumes at 4")
for i = 5, N - 1 do now += 12; assert(climb:checkpoint(3, i, now)) end
assert(climb:summit(3, 45 * 60, now) and climb:view(3).summits == 1, "a resumed climb's Summit counts")
assert(climb:view(3).bestFrames == nil, "but a resumed climb is not the whole course, so it sets no best time")
-- Claimed time longer than the time actually spent: refused.
climb:enter(2, 0, now)
for i = 1, N - 1 do now += 6; climb:checkpoint(2, i, now) end
assert(climb:summit(2, 500 * 60, now) and climb:view(2).bestFrames == nil, "a time longer than the climb took is refused")
-- Saved, and read back by a fresh server.
now += 100
store:tick()
local again = ClimbProgress.new(AvatarStore.new(ds, function() return now end), N)
v = again:view(1)
assert(v.best == N - 1 and v.summits == 3 and v.bestFrames == 78 * 60, "progress survives a new server")
-- Garbage in the record comes back clean.
data.u9 = { v = 1, active = 1, slots = { { name = "x", code = "k1" } }, climb = { best = 99, summits = -4, bestFrames = 0/0 } }
v = again:view(9)
assert(v.best == N - 1 and v.summits == 0 and v.bestFrames == nil, "a hostile record is cleaned")
print("PASS climb progress: pace checks, skipping ahead, one Summit per climb, best times only for believable full climbs, saved and cleaned")
