--!strict
-- Skyline Climb progress: what is saved, and which claims are refused.
local Loader = require("./loader")
local AvatarStore = Loader.loadFrom("src/server/", "AvatarStore")
local ClimbProgress = Loader.loadFrom("src/server/", "ClimbProgress")
local PARKOUR = Loader.load("Data/Parkour")
local N = #PARKOUR.course.checkpoints

local data = {}
local ds = { GetAsync = function(_, k) return data[k] end, UpdateAsync = function(_, k, fn) local v = fn(data[k]); if v then data[k] = v end; return v end }
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
-- Paid skips: one checkpoint on from where you are; saved to resume from, never counted as climbed.
do
	local t = now + 1000
	assert(climb:enter(20, 0, t) == 0)
	assert(climb:skip(20, t) == 1, "a skip moves you one checkpoint on")
	local v20 = climb:view(20)
	assert(v20.best == 1 and v20.climbed == 0 and climb:climbing(20).reached == 1, "saved to resume from, not as climbed")
	t += 3
	assert(climb:checkpoint(20, 2, t), "climbing on from a skipped checkpoint counts")
	assert(climb:view(20).climbed == 2 and climb:view(20).best == 2, "and what you climb to is climbed")
	for _ = 3, N - 1 do assert(climb:skip(20, t)) end
	assert(climb:climbing(20).reached == N - 1 and climb:skip(20, t) == nil, "at the Summit there is nothing left to skip")
	assert(not climb:summit(20, 90 * 60, t) and climb:view(20).summits == 0, "a Summit reached by a skip is not a Summit")
	assert(climb:view(20).climbed == 2, "nor is anything skipped past")
	-- Resuming at a Summit you bought, then claiming it: refused too.
	climb:leave(20)
	assert(climb:enter(20, "best", t) == N - 1 and not climb:summit(20, 90 * 60, t), "resuming at the Summit claims nothing")
	-- Back to the bottom with a bought Summit saved: a skip is one on from where you ARE, and what
	-- you climb now counts as climbed even below the checkpoint you bought.
	climb:leave(20)
	assert(climb:enter(20, 0, t) == 0 and climb:skip(20, t) == 1, "a skip from the bottom is to checkpoint 1, whatever is saved")
	t += 5
	assert(climb:checkpoint(20, 3, t) and climb:view(20).climbed == 3 and climb:view(20).best == N - 1,
		"climbing to 3 counts as climbed, below the Summit you bought")
	-- A climb with a skip in it that is then climbed to the Summit: the Summit counts, the time does not.
	t += 100
	climb:enter(21, 0, t)
	t += 5
	climb:skip(21, t)
	for i = 2, N - 1 do t += 10; assert(climb:checkpoint(21, i, t)) end
	assert(climb:summit(21, 60 * 60, t) and climb:view(21).summits == 1, "climbed to the Summit after a skip: it counts")
	assert(climb:view(21).bestFrames == nil, "but a climb with a skip in it sets no best time")
	-- Not on a climb: the skip moves where you will resume.
	climb:enter(22, 0, t)
	t += 20
	assert(climb:checkpoint(22, 3, t))
	climb:leave(22)
	assert(climb:skip(22, t) == 4 and climb:view(22).best == 4 and climb:view(22).climbed == 3, "off the climb, a skip moves your resume point")
	assert(climb:enter(22, "best", t) == 4, "and you resume there")
end
-- Records from before skips: everything in them was climbed. A hostile one cannot claim more
-- climbed than reached.
data.u30 = { v = 1, active = 1, slots = { { name = "x", code = "k1" } }, climb = { best = 5, summits = 1 } }
data.u31 = { v = 1, active = 1, slots = { { name = "x", code = "k1" } }, climb = { best = 2, climbed = 7 } }
assert(again:view(30).climbed == 5, "an old record's progress was all climbed")
assert(again:view(31).climbed == 2, "climbed is never more than reached")
-- Rewards: granted at their checkpoint, to a climber who climbed there - never a skipper, never
-- from anywhere else, never twice.
do
	local REWARDS = PARKOUR.course.rewards
	local crown = REWARDS[1]
	local t = now + 5000
	-- Climbed to Crown Perch on this climb: the crown.
	climb:enter(50, 0, t)
	t += 400
	assert(climb:checkpoint(50, crown.checkpoint - 1, t))
	assert(climb:reward(50, crown.id, REWARDS) == nil, "not before reaching its checkpoint")
	t += 5
	assert(climb:checkpoint(50, crown.checkpoint, t))
	assert(climb:reward(50, "notAReward", REWARDS) == nil, "an unknown reward is nothing")
	assert(climb:reward(50, crown.id, REWARDS) == crown, "climbed to Crown Perch: the crown is granted")
	assert(table.find(climb:view(50).rewards, crown.id), "and it is theirs")
	assert(climb:reward(50, crown.id, REWARDS) == nil, "not twice")
	-- Skipped to it: refused, standing in the same place.
	climb:enter(51, 0, t)
	t += 400
	assert(climb:checkpoint(51, crown.checkpoint - 1, t))
	t += 5
	assert(climb:skip(51, t) == crown.checkpoint)
	assert(climb:reward(51, crown.id, REWARDS) == nil and #climb:view(51).rewards == 0, "skipped to Crown Perch: no crown")
	-- Climbed there before, resuming there: granted. Somewhere else on the climb: refused.
	climb:leave(50)
	climb:enter(52, 0, t)
	t += 400
	assert(climb:checkpoint(52, crown.checkpoint, t))
	climb:leave(52)
	climb:enter(52, 0, t)
	assert(climb:reward(52, crown.id, REWARDS) == nil, "climbed there before, but at the bottom now: refused")
	climb:leave(52)
	assert(climb:enter(52, "best", t) == crown.checkpoint and climb:reward(52, crown.id, REWARDS) == crown, "resuming where you climbed to: granted")
	climb:leave(52)
	climb:enter(53, 0, t)
	assert(climb:reward(53, REWARDS[2].id, REWARDS) == nil, "from the bottom: refused")
	climb:leave(53)
	assert(climb:reward(53, crown.id, REWARDS) == nil, "off the climb: refused")
end
print("PASS climb progress: pace checks, skipping ahead, one Summit per climb, best times only for believable full climbs, saved and cleaned")
