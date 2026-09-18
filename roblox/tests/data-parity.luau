--!strict
-- Does the generated Luau data layer actually say what the JavaScript says?
--
--   lune run tests/data-parity
--
-- src/shared/Data/*.luau is emitted from web/src/data/**.js by tools/gen-data.mjs. That the two
-- agree is not self-evident just because one was generated from the other: an emitter can drop a
-- field, round a number, quote a key wrongly, or turn an array into a dictionary. So the generator
-- also writes tests/data-fixture.json - exactly what it was handed - and this walks the two trees
-- against each other, in both directions, comparing every leaf.
--
-- Both directions matters. Checking only that the JavaScript's fields survived would pass an
-- emitter that invented extra ones.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Loader = require("./loader")

local Weapons = Loader.load("Data/Weapons")
local Avatars = Loader.load("Data/Avatars")
local Stages = Loader.load("Data/Stages")
local Items = Loader.load("Data/Items")
local Loadout = Loader.load("Loadout")

local fixture = serde.decode("json", fs.readFile("tests/data-fixture.json"))

local failures: { string } = {}
local leaves = 0

local function fail(msg: string)
	if #failures < 15 then
		table.insert(failures, msg)
	end
end

-- serde decodes JSON arrays into 1-indexed Luau arrays and JSON objects into dictionaries, which
-- is the same shape the emitter produces - so this is a plain structural comparison. An array the
-- emitter wrote as a dictionary shows up as key `1` (number) against key `"1"` (string).
local function compare(js: any, lua: any, path: string)
	local jt, lt = typeof(js), typeof(lua)
	if jt ~= lt then
		fail(string.format("%s: JS has %s, Luau has %s", path, jt, lt))
		return
	end
	if jt ~= "table" then
		leaves += 1
		if js ~= lua then
			fail(string.format("%s: JS has %s, Luau has %s", path, tostring(js), tostring(lua)))
		end
		return
	end
	for k, v in js do
		local got = lua[k]
		if got == nil then
			fail(string.format("%s.%s: present in the JavaScript, missing from the Luau", path, tostring(k)))
		else
			compare(v, got, path .. "." .. tostring(k))
		end
	end
	for k in lua do
		if js[k] == nil then
			fail(string.format("%s.%s: emitted into the Luau, not present in the JavaScript", path, tostring(k)))
		end
	end
end

compare(fixture.weapons, Weapons.LIST, "weapons")
compare(fixture.avatars, Avatars.LIST, "avatars")
compare(fixture.base, Avatars.BASE, "avatars.BASE")
compare(fixture.stages, Stages.LIST, "stages")
compare(fixture.items, Items.LIST, "items")

-- The BY_ID lookups must hold the SAME tables as the lists, the way WEAPON_BY_ID does in the
-- JavaScript. A copy would work everywhere until something mutated a move at runtime.
local function checkLookup(label: string, mod: any)
	for i, entry in mod.LIST do
		leaves += 1
		if not rawequal(mod.BY_ID[entry.id], entry) then
			fail(string.format("%s.BY_ID[%q] is not the same table as LIST[%d]", label, tostring(entry.id), i))
		end
	end
end
checkLookup("Weapons", Weapons)
checkLookup("Avatars", Avatars)
checkLookup("Stages", Stages)
checkLookup("Items", Items)

-- Counts, so a generator that silently emitted an empty list cannot pass by comparing nothing.
local counts: { { any } } = {
	{ "weapons", #Weapons.LIST, 12 },
	{ "avatars", #Avatars.LIST, 6 },
	{ "stages", #Stages.LIST, 6 },
	{ "items", #Items.LIST, 5 },
}
for _, c in counts do
	leaves += 1
	if (c[2] :: number) ~= (c[3] :: number) then
		fail(string.format("%s: %d generated, expected %d", c[1] :: string, c[2] :: number, c[3] :: number))
	end
end

-- Every move must carry the derived fields weapons/index.js fills in at import time. A generator
-- that snapshotted the data BEFORE that loop ran would produce a table that looks complete and
-- breaks the first time anything is thrown.
--
-- One correction to the note this used to carry: the engine does NOT read `move.total`. It is
-- written by weapons/index.js for every move and by combat.js for the Bulwark's swing, and read
-- nowhere in the simulation, the renderer or the UI - Fighter recomputes the same sum itself from
-- startupEff. It is checked here anyway, because it is still evidence that the derivation loop ran.
local moves = 0
for _, w in Weapons.LIST do
	for id, m in w.moves do
		moves += 1
		leaves += 4
		if m.id ~= id then
			fail(string.format("%s.%s: move.id is %s", tostring(w.id), tostring(id), tostring(m.id)))
		end
		if m.total ~= m.startup + m.active + m.recovery then
			fail(string.format("%s.%s: total %s, expected %s", tostring(w.id), tostring(id), tostring(m.total), tostring(m.startup + m.active + m.recovery)))
		end
		if typeof(m.kind) ~= "string" then
			fail(string.format("%s.%s: kind is %s", tostring(w.id), tostring(id), tostring(m.kind)))
		end
		if typeof(m.hitboxes) ~= "table" then
			fail(string.format("%s.%s: hitboxes is %s", tostring(w.id), tostring(id), tostring(m.hitboxes)))
		end
	end
end

-- Loadout.build is hand-written Luau, not generated, so every one of the 72 avatar x weapon
-- combinations is checked against the JavaScript's. applyStats multiplies BASE, applies absolute
-- overrides and rounds - three chances to be subtly wrong in a way nothing else here would see.
local loadouts = 0
for _, row in fixture.loadouts do
	local L = Loadout.build(row.avatar, row.weapon)
	loadouts += 1
	for _, k in { "id", "name", "archetype" } do
		leaves += 1
		if L[k] ~= row[k] then
			fail(string.format("loadout %s:%s .%s = %s, JS says %s",
				tostring(row.avatar), tostring(row.weapon), k, tostring(L[k]), tostring(row[k])))
		end
	end
	-- The stats arrive as decimal STRINGS and are parsed here, so the comparison is bit-exact
	-- rather than "exact to however many digits Lune's JSON decoder kept". See gen-data.mjs.
	for k, want in row.stats do
		leaves += 1
		local expect = tonumber(want)
		if L[k] ~= expect then
			fail(string.format("loadout %s:%s .%s = %.17g, JS says %s",
				tostring(row.avatar), tostring(row.weapon), tostring(k), L[k], tostring(want)))
		end
	end
end

-- Precedence, pinned on a synthetic weapon. No weapon in the roster today both multiplies AND
-- overrides the same stat, so the 72 real loadouts above pass whichever order applyStats uses -
-- verified by swapping the two branches and watching nothing fail. The JavaScript applies the
-- multiplier first and lets the absolute override win; the day a weapon uses both on one stat,
-- this is what stops the Roblox build quietly disagreeing.
do
	local synthetic = { stats = { mul = { runSpeed = 2, weight = 0.5 }, set = { runSpeed = 7 } } }
	local out = Loadout.applyStats(synthetic)
	leaves += 2
	if out.runSpeed ~= 7 then
		fail(string.format("applyStats: set must beat mul on the same stat, got runSpeed %s", tostring(out.runSpeed)))
	end
	if out.weight ~= Avatars.BASE.weight * 0.5 then
		fail(string.format("applyStats: mul alone should scale BASE, got weight %s", tostring(out.weight)))
	end
	-- jumps is rounded and floored at 1, so a multiplier that would drop it below one must not
	leaves += 1
	local none = Loadout.applyStats({ stats = { mul = { jumps = 0.1 } } })
	if none.jumps ~= 1 then
		fail(string.format("applyStats: jumps must floor at 1, got %s", tostring(none.jumps)))
	end
end

-- and the move tables must be SHARED with the weapon, not copied, exactly as in the JavaScript
local sample = Loadout.build("Classic", "Sword")
leaves += 1
if not rawequal(sample.moves, Weapons.BY_ID.Sword.moves) then
	fail("Loadout.build copied the move table instead of sharing it")
end

print(string.format("compared %d leaves across %d weapons (%d moves), %d avatars, %d stages, %d items, %d loadouts",
	leaves, #Weapons.LIST, moves, #Avatars.LIST, #Stages.LIST, #Items.LIST, loadouts))
if #failures > 0 then
	print(string.format("\n%d MISMATCHES:", #failures))
	for _, f in failures do
		print("  " .. f)
	end
	process.exit(1)
end
print("Luau data matches web/src/data/**.js exactly.")
