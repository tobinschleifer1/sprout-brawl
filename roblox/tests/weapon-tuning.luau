--!nocheck
-- The Roblox-only weapon tuning (src/shared/WeaponTuning.luau, applied by Weapons.luau): the game
-- plays the tuned numbers, the generated data is never touched, and the replays that hold the engine
-- to the web still get the web's numbers (Loadout.build's `untuned`).
--
--     lune run tests/weapon-tuning
local Loader = require("./loader")

local function same(a: any, b: any): boolean
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in a do if not same(v, b[k]) then return false end end
	for k in b do if a[k] == nil then return false end end
	return true
end

-- A private set of modules (loadFrom's own cache), so this test's tuning cannot leak into the
-- shipping one, and the shipping one cannot change what this test expects.
local ROOT = "src/shared/"
local Tuning = Loader.loadFrom(ROOT, "WeaponTuning")
local Generated = Loader.loadFrom(ROOT, "Data/Weapons")
local before = Tuning.copy(Generated.LIST)
local sword = Generated.BY_ID.Sword
local L1 = sword.moves.LightNeutral1
assert(L1.startup == 5 and L1.active == 2 and L1.recovery == 8 and L1.hitboxes[1].frames[1] == 6,
	"the Sword's first slash is not the 5/2/8 move these checks were written for")
Tuning.FOR = { Sword = { moves = { LightNeutral1 = { startup = 7, damage = 4, hitboxes = { { size = { 3.0, 2.2 } } } } } } }
local Weapons = Loader.loadFrom(ROOT, "Weapons")
local Loadout = Loader.loadFrom(ROOT, "Loadout")

-- 1. The game plays the tuned move; its derived numbers follow.
local tuned = Weapons.BY_ID.Sword.moves.LightNeutral1
assert(tuned.startup == 7 and tuned.damage == 4, "the tuned numbers are not what the game reads")
assert(tuned.total == 7 + 2 + 8, `the tuned move's total is {tuned.total}, not recomputed`)
assert(tuned.hitboxes[1].frames[1] == 8 and tuned.hitboxes[1].frames[2] == 9,
	"the hitbox stayed on the old active frames when the startup moved")
assert(tuned.hitboxes[1].size[1] == 3.0 and tuned.hitboxes[1].offset[1] == L1.hitboxes[1].offset[1],
	"a hitbox's size was not replaced, or its offset was not kept")
for i, w in Weapons.LIST do
	if w.id == "Sword" then
		assert(w == Weapons.BY_ID.Sword, "the list and the index disagree on the tuned Sword")
	else
		assert(w == Weapons.UNTUNED_LIST[i], `{w.id}, not tuned, is not the weapon it was`)
	end
end

-- 2. The generated data is exactly as it was, and the untuned roster is it.
assert(same(before, Generated.LIST), "tuning changed the generated weapon data")
assert(Weapons.UNTUNED_BY_ID.Sword == sword and sword.moves.LightNeutral1.startup == 5, "the untuned Sword is not the generated one")

-- 3. The game builds tuned fighters; the replays build the web's.
assert(Loadout.build("Classic", "Sword").moves.LightNeutral1.startup == 7, "the game's loadout is not tuned")
assert(Loadout.build("Classic", "Sword", true).moves.LightNeutral1.startup == 5, "a replay's loadout is tuned")
local armed = Loadout.buildArmed("Classic", { "Sword", "Axe" }, true)
assert(armed.kit[1].moves.LightNeutral1.startup == 5, "a replay's armed kit is tuned")
assert(Loadout.buildArmed("Classic", { "Sword", "Axe" }).kit[1].moves.LightNeutral1.startup == 7, "the game's armed kit is not tuned")

-- 4. Mistakes are errors, not changes that silently do nothing.
local function fails(patch: any, expect: string)
	local ok, err = pcall(Tuning.apply, sword, patch)
	assert(not ok and string.find(tostring(err), expect, 1, true), `a bad patch did not fail with "{expect}": {tostring(err)}`)
end
fails({ moves = { Nonesuch = { damage = 1 } } }, "has no move Nonesuch")
fails({ moves = { LightNeutral1 = { startpu = 3 } } }, "LightNeutral1.startpu does not exist")
fails({ stats = { set = { weigth = 90 } } }, "does not exist")
fails({ moves = { LightNeutral1 = { active = 4 } } }, "must give its frames")
local longer = Tuning.apply(sword, { moves = { LightNeutral1 = { active = 4, hitboxes = { { frames = { 6, 9 } } } } } })
assert(longer.moves.LightNeutral1.total == 5 + 4 + 8 and longer.moves.LightNeutral1.hitboxes[1].frames[2] == 9, "a longer active window with its frames given was not applied")
local added = Tuning.apply(sword, { moves = { LightNeutral1 = { add = { armor = 5 } } } })
assert(added.moves.LightNeutral1.armor == 5 and sword.moves.LightNeutral1.armor == nil, "add did not add, or added to the original")
local OtherTuning = Loader.loadFrom("tests/../src/shared/", "WeaponTuning")
OtherTuning.FOR = { Nonesuch = { stats = {} } }
local ok, err = pcall(Loader.loadFrom, "tests/../src/shared/", "Weapons")
assert(not ok and string.find(tostring(err), "no weapon Nonesuch", 1, true), "tuning for a weapon that does not exist loaded")

-- 5. The shipping tuning loads, and every weapon it names exists (Weapons.luau errors otherwise).
local Shipping = Loader.load("Weapons")
local count = 0
for id in Loader.load("WeaponTuning").FOR do
	assert(Shipping.UNTUNED_BY_ID[id], `the shipping tuning names {id}`)
	count += 1
end
print(`PASS weapon tuning: the game reads the tuned move (total and hitbox frames follow it), the generated data is untouched, replays build the web's weapons, bad patches fail loudly; {count} weapons tuned in the shipping build`)
