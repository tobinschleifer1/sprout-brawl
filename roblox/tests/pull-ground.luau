-- A pull (a whip's hit, hit.pull) moves its victim directly, outside the collision step. Caught
-- stepping off an edge - feet just under the surface - it put them back over the island where no
-- landing catches you, and they fell through the floor (the bug hunt's fuzzer, seed 1254). Now the
-- pull lifts them onto the surface it brought them over, then keeps them out of any solid.
local Loader = require("./loader")
local Match, Loadout = Loader.load("Match"), Loader.load("Loadout")
local Stages = Loader.load("Data/Stages")

local function fail(msg: string): never error(msg, 0) end
local m = Match.new({ mode = "Training", stage = Stages.BY_ID.FoundryFloor, seed = 1, fighters = {
	{ char = Loadout.build("Classic", "Whip"), isBot = true, botLevel = "dummy", team = 0, source = "a" },
	{ char = Loadout.build("Classic", "Sword"), isBot = true, botLevel = "dummy", team = 1, source = "b" } } })
local main = m.stage.main
local attacker, victim = m.fighters[1], m.fighters[2]
-- the victim just past the left edge, a frame into the fall; the attacker on the island to the right
victim:reset(main.x1 - 0.7, main.top - 0.12, { state = "air", invincible = 0 })
attacker:reset(main.x1 + 6, main.top, { state = "idle", invincible = 0 })
victim:applyHit({ damage = 4, launch = 6, stun = 6, angle = 0, facing = -1, hitlag = 6, attacker = attacker, attackerX = attacker.x, pull = 1.5 })
if victim.y ~= main.top then fail(`a pulled victim was left {main.top - victim.y} under the surface it was pulled over`) end
if victim.x + victim.r * 0.6 <= main.x1 then fail("the pull did not bring the victim onto the island") end
print("PASS pull ground: a victim pulled back over an edge stands on the surface, not just under it")
