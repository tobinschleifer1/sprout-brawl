--!strict
-- Switches for work released in stages (Roblox only).
--
-- STEP1: the retention plan's step 1 screens (docs/briefs/retention-plan.md) - the next-goal line,
-- NEW OPPONENTS, the quiet-queue nudge, INVITE FRIENDS and the first-session "start here". The plan
-- releases step 0's counting a few days BEFORE these, so they have a baseline: publish once with this
-- false, then switch it on.
local Features = {}
Features.STEP1 = true
return Features
