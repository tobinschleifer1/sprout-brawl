--!strict
-- The loading screen's fight (LoadingFight; Roblox only): two top-difficulty bots, a plain Sword
-- and a plain Grimoire, in a local Training match, drawn by the client's own FightScene.
--
-- What it holds: the two are who they should be and wear nothing; over a minute both land hits and
-- both cast their ultimates more than once (the meters refill on a clock); neither ever runs out of
-- lives; every frame draws, without one renderer failure; and a long hitch is skipped, not caught up.
--
--     lune run tests/loading-fight
local Loader = require("./loader")
local Recorder = require("../tools/recorder")
local Canvas = Loader.loadFrom("src/client/", "Canvas2D")
local LoadingFight = Loader.loadFrom("src/client/", "LoadingFight")

local shapes = Recorder.install(Canvas)
local c = Recorder.canvas(Canvas, 960, 540)
local fight = LoadingFight.new(c, function() return { X = 960, Y = 540 } :: any end, 7)

-- 1. Who fights.
local weapons = {}
for i, f in fight.match.fighters do
	weapons[i] = f.char.weapon and f.char.weapon.id or f.char.weaponId
	assert(f.isBot and f.botLevel == LoadingFight.LEVEL and LoadingFight.LEVEL == "impossible", `fighter {i} is not a top-difficulty bot`)
	local skins = f.char.cosmetics and f.char.cosmetics.skins
	assert(not skins or next(skins) == nil, `fighter {i} wears a skin`)
end
assert(#fight.match.fighters == 2 and weapons[1] == "Sword" and weapons[2] == "Grimoire", `the fight is {weapons[1]} v {weapons[2]}`)

-- (a Training match respawns forever: in a stock match the loser of a long load would vanish)
assert(fight.match.training and not fight.match.timed, "the fight is not a Training match: someone will run out of lives")

-- 2. Half a minute of it.
local SECONDS = 30
for n = 1, SECONDS * 60 do
	table.clear(shapes)
	fight:step(1 / 60)
	assert(#shapes > 0, `frame {n} drew nothing`)
	for _, f in fight.match.fighters do assert(f.alive or f.koTimer > 0, `a fighter ran out of lives at frame {n}`) end
end
assert(not fight.failed, "the renderer failed during the fight")
for i = 1, 2 do
	assert((fight.hits[i] or 0) >= 3, `{weapons[i]} landed {fight.hits[i] or 0} hits in {SECONDS} s`)
	assert((fight.ults[i] or 0) >= 2, `{weapons[i]} cast {fight.ults[i] or 0} ultimates in {SECONDS} s`)
end

-- 3. A hitch: five seconds in one drawn frame runs MAX_STEPS simulation frames, not three hundred.
local at = fight.frame
fight:step(5)
assert(fight.frame - at == LoadingFight.MAX_STEPS, `a 5 s hitch ran {fight.frame - at} frames`)

print(`PASS loading fight: Sword v Grimoire, top bots, no skins; in {SECONDS} s hits {fight.hits[1]} / {fight.hits[2]}, ultimates {fight.ults[1]} / {fight.ults[2]}; every frame drawn; a hitch skipped`)
