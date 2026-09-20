--!strict
-- The fighter snapshot, round-tripped against a real Fighter.
--
-- This test exists because of a specific bug. The snapshot format changed from a positional array
-- to short named keys; the camera's call site was updated and the rigs' was not, so Rigs.pose read
-- `s.facing` from a table whose field is called `fc`. Nil is not an error in Luau until something
-- compares it, so the rigs drew with no facing, no tumble, no KO hiding and no invincibility, and
-- the only symptom was one line repeating in the console.
--
-- So the assertions here are about the SHAPE and not only the values: the decoded key set is
-- written out longhand, and renaming a field breaks this test rather than breaking a renderer in a
-- way nobody notices.

local Loader = require("./loader")
local Snapshot = Loader.load("Snapshot")
local Fighter = Loader.load("Fighter")
local Loadout = Loader.load("Loadout")

local function fail(msg: string): never
	error(msg, 0)
end

local checked = 0

-- The decoded field set, written out. If you are here because this failed, a field was renamed or
-- added: update every consumer in src/client before updating this list.
local EXPECTED = {
	"index", "x", "y", "vx", "vy", "facing", "state", "stateFrame", "moveFrame", "moveId",
	"percent", "stocks", "shield", "ultCharge", "alive", "onGround", "tumbling", "invincible",
	"item",
	"startupEff", "frameCount", "charge", "hitlag", "fastFalling", "ultCooldown", "techRoll", "ultShots", "hitstun",
	"chillStacks", "ledgeAction",
}

-- 1. FIELDS is a bijection. A duplicate wire name silently drops a field; a duplicate simulation
-- name silently overwrites one.
local seenSim, seenWire = {}, {}
for _, pair in Snapshot.FIELDS do
	local name, wire = pair[1], pair[2]
	if seenSim[name] then
		fail(`simulation name {name} appears twice in FIELDS`)
	end
	if seenWire[wire] then
		fail(`wire name {wire} is used by both {seenWire[wire]} and {name}`)
	end
	seenSim[name], seenWire[wire] = name, name
	checked += 2
end

-- 2. The decoded key set is exactly EXPECTED, both directions.
for _, name in EXPECTED do
	if not seenSim[name] then
		fail(`{name} is consumed by the client but is not in Snapshot.FIELDS`)
	end
	checked += 1
end
for name in seenSim do
	local found = false
	for _, e in EXPECTED do
		if e == name then
			found = true
		end
	end
	if not found then
		fail(`{name} is in Snapshot.FIELDS but not declared in this test`)
	end
	checked += 1
end

-- 3. Every field survives a real fighter, with its real value. Values are set to something
-- distinguishable first, because a field that is 0 on a fresh fighter round-trips correctly even
-- when it is read off entirely the wrong source.
local char = Loadout.build("Classic", "Sword")
local f = Fighter.new({ index = 3, char = char, x = 12.5, y = 7.25, stocks = 2 })
f.vx, f.vy = -4.5, 9.75
f.facing = -1
f:setState("hitstun")
f.sf, f.mf = 11, 23
f.moveId = "ForwardAir"
f.percent = 87.5
f.shield = 33.25
f.ultCharge = 14
f.alive = true
f.onGround = false
f.tumbling = true
f.invincible = 6
-- The pose fields. Every value here is distinct from every other and from the fresh-fighter
-- default, so a field read off the wrong source shows up as a wrong number rather than a matching 0.
f.startupEff = 9
f.frameCount = 41
f.charge = 17
f.hitlag = 5
f.fastFalling = true
f.ultCooldown = 27
f.techRoll = -1
f.ultShots = 4
f.hitstun = 13
f.effects.chill.stacks = 2
f.la = { kind = "attack", L = {} }

local EXPECT_VALUE: { [string]: any } = {
	index = 3, x = 12.5, y = 7.25, vx = -4.5, vy = 9.75, facing = -1,
	state = "hitstun", stateFrame = 11, moveFrame = 23, moveId = "ForwardAir",
	percent = 87.5, stocks = 2, shield = 33.25, ultCharge = 14,
	alive = true, onGround = false, tumbling = true, invincible = 6,
	startupEff = 9, frameCount = 41, charge = 17, hitlag = 5, fastFalling = true,
	ultCooldown = 27, techRoll = -1, ultShots = 4, hitstun = 13,
	-- Flattened out of f.effects.chill.stacks and f.la.kind respectively.
	chillStacks = 2, ledgeAction = "attack",
}

local decoded = Snapshot.decode(Snapshot.encode(f))
for name, want in EXPECT_VALUE do
	if decoded[name] ~= want then
		fail(`{name} round-tripped to {tostring(decoded[name])}, expected {tostring(want)}`)
	end
	checked += 1
end

-- 4. No field is silently nil on a live fighter. This is the assertion that would have caught the
-- original bug at the source rather than in a renderer: a field the wire does not actually carry
-- reads as nil here, whatever the consumer happens to call it.
for _, name in EXPECTED do
	if name ~= "item" and decoded[name] == nil then
		fail(`{name} decoded to nil from a live fighter - the wire is not carrying it`)
	end
	checked += 1
end

-- 5. An empty hand sends no item, and a full one sends its id and nothing else. The item is a live
-- object with a hitbox and timers; only its identity is allowed across.
if decoded.item ~= nil then
	fail(`a fighter holding nothing sent item = {tostring(decoded.item)}`)
end
f.item = { id = "Keg", hp = 3, def = {} }
if Snapshot.decode(Snapshot.encode(f)).item ~= "Keg" then
	fail("a held item did not send its id")
end
checked += 2

-- 6. Not on a ledge sends no ledge action. `la` is nil for all but a few frames of a match, so the
-- nil case is the common one and the flattening has to survive it rather than indexing nil.
f.la = nil
if Snapshot.decode(Snapshot.encode(f)).ledgeAction ~= nil then
	fail("a fighter not on a ledge sent a ledgeAction")
end
-- And a zeroed effect sends 0, not nil: channels.js compares chillStacks > 0.
f.effects.chill.stacks = 0
if Snapshot.decode(Snapshot.encode(f)).chillStacks ~= 0 then
	fail("an unchilled fighter did not send chillStacks = 0")
end
checked += 2

print(`checked {checked} snapshot values`)
print("Snapshot.encode/decode carries every field the client reads.")
