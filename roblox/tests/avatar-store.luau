--!strict
-- Saved characters, against fake DataStores: one that works, one that throttles, one that is off.
-- The property that matters most is the one a player would only discover too late - a record the
-- server failed to READ is never written over - so it gets the most direct test here.
local Loader = require("./loader")
local AvatarStore = Loader.loadFrom("src/server/", "AvatarStore")
local AvatarKit = Loader.load("AvatarKit")
local KIT = AvatarKit.KIT

local function fakeStore(failGets: number?, failSets: number?): any
	local data, writes = {}, 0
	local gets = 0
	return {
		data = data,
		writes = function() return writes end,
		GetAsync = function(_, key: string): any
			gets += 1
			if failGets and gets <= failGets then error("throttled") end
			return data[key]
		end,
		UpdateAsync = function(_, key: string, transform: any)
			local value = transform(data[key])
			if value == nil then return nil end
			if failSets and failSets > 0 then failSets -= 1; error("throttled") end
			writes += 1
			-- A DataStore stores a copy, not the table.
			data[key] = { v = value.v, active = value.active, slots = table.clone(value.slots), _revision = value._revision }
			return data[key]
		end,
	}
end
local now = 0
local clock = function() return now end
local KNIGHT, NINJA = KIT.presets[2].code, KIT.presets[3].code

-- 1. A new player: the default character, nothing written until they change something.
local ds = fakeStore()
local store = AvatarStore.new(ds, clock)
local view = store:view(1)
assert(#view.slots == 1 and view.slots[1].code == AvatarKit.defaultCode() and view.active == 1 and view.saving, "a new player gets one default character, with saving on")
store:tick(); now += 100; store:tick()
assert(ds.writes() == 0, "nothing was changed, so nothing should be written")

-- 2. Edits are batched: one write after the delay, not one per click.
assert(store:apply(1, { action = "save", slot = 1, code = KNIGHT, name = "Sir" }))
assert(store:apply(1, { action = "save", slot = 2, code = NINJA, name = "Kage" }))
assert(store:active(1) == NINJA, "saving a character puts it on")
store:tick()
assert(ds.writes() == 0, "wrote before the save delay")
now += AvatarStore.SAVE_DELAY
store:tick()
assert(ds.writes() == 1, `a burst of edits should be one write, was {ds.writes()}`)
-- ...and it reads back in a fresh server.
local again = AvatarStore.new(ds, clock):view(1)
assert(#again.slots == 2 and again.slots[1].name == "Sir" and again.slots[2].code == NINJA and again.active == 2, "the characters did not survive a new server")

-- 3. Slot rules.
assert(not store:apply(1, { action = "save", slot = 4, code = KNIGHT }), "a slot past the end + 1 was accepted")
for i = 3, AvatarStore.MAX_SLOTS do assert(store:apply(1, { action = "save", slot = i, code = KNIGHT })) end
assert(not store:apply(1, { action = "save", slot = AvatarStore.MAX_SLOTS + 1, code = KNIGHT }), "a ninth character was accepted")
assert(not store:apply(1, { action = "save", slot = 1, code = "Classic" }), "a preset id is not a kit character")
assert(not store:apply(1, { action = "wear", slot = 0.5 }) and not store:apply(1, { action = "wear", slot = 99 }), "a bad slot was worn")
assert(store:apply(1, { action = "wear", slot = 5 }))
assert(store:apply(1, { action = "delete", slot = 2 }))
assert(store:view(1).active == 4, "deleting a character before the one you wear should keep you in it")
assert(store:apply(1, { action = "delete", slot = 4 }))
assert(store:view(1).active == 4 and #store:view(1).slots == 6, "deleting the one you wear puts on the one that slid into its place")
for _ = 1, 5 do assert(store:apply(1, { action = "delete", slot = 1 })) end
assert(not store:apply(1, { action = "delete", slot = 1 }), "the last character was deleted")

-- 4. A throttled read that recovers on retry loads normally.
local flaky = fakeStore(2)
flaky.data.u5 = { v = 1, active = 1, slots = { { name = "Old", code = KNIGHT } } }
local s2 = AvatarStore.new(flaky, clock)
assert(s2:active(5) == KNIGHT and s2:view(5).saving, "two throttled reads and a good one should load the record")

-- 5. A read that never succeeds: the player can still play and change characters, and the record
--    in the DataStore is NEVER written over.
local down = fakeStore(99)
down.data.u7 = { v = 1, active = 1, slots = { { name = "Precious", code = KNIGHT } } }
local s3 = AvatarStore.new(down, clock)
local v3 = s3:view(7)
assert(not v3.saving and type(v3.note) == "string", "a failed read should say saving is off")
assert(s3:apply(7, { action = "save", slot = 1, code = NINJA }) and s3:active(7) == NINJA, "a player with saving off can still change character")
now += 100; s3:tick(); s3:release(7); s3:flushAll()
assert(down.writes() == 0 and down.data.u7.slots[1].name == "Precious", "a record that could not be read was written over")

-- 6. A failed write stays dirty and is retried.
local sticky = fakeStore(nil, 1)
local s4 = AvatarStore.new(sticky, clock)
assert(s4:apply(9, { action = "save", slot = 1, code = KNIGHT }))
now += 100; s4:tick()
assert(sticky.writes() == 0 and s4.dirty[9], "a failed write should leave the record dirty")
s4:tick()
assert(sticky.writes() == 1 and not s4.dirty[9], "the retry did not write")

-- 7. Whatever is in the DataStore comes back as a valid wardrobe.
local hostile: { any } = { nil, 5, "x", { slots = "no" }, { slots = { 1, 2 } }, { active = 99, slots = { { code = "k1zz", name = string.rep("A", 500) } } },
	{ active = -1, slots = table.create(40, { name = "<script>", code = KNIGHT }) } }
for i = 1, 7 do
	local rec = AvatarStore.sanitize(hostile[i])
	assert(#rec.slots >= 1 and #rec.slots <= AvatarStore.MAX_SLOTS, `hostile record {i}: {#rec.slots} slots`)
	assert(rec.active >= 1 and rec.active <= #rec.slots, `hostile record {i}: active {rec.active}`)
	for _, sl in rec.slots do
		assert(AvatarKit.canonical(sl.code) == sl.code, `hostile record {i}: code {sl.code}`)
		assert(#sl.name <= AvatarStore.MAX_NAME and not string.find(sl.name, "[<>]"), `hostile record {i}: name {sl.name}`)
	end
end
-- Earned parts: saved only once earned; the record keeps what was earned, cleaned when read.
do
	local AvatarKit = Loader.load("AvatarKit")
	local spec = AvatarKit.decode(AvatarKit.defaultCode()) :: any
	spec.parts.headwear = "skylineCrown"
	local crowned = AvatarKit.encode(spec)
	local st = AvatarStore.new(nil, function() return 0 end)
	local ok, why = st:apply(77, { action = "save", slot = 1, code = crowned })
	assert(not ok and string.find(why or "", "Skyline Climb"), "an earned part cannot be saved before it is earned")
	assert(#st:view(77).unlocked == 0, "nothing earned yet")
	assert(st:grant(77, "skylineCrown") and not st:grant(77, "skylineCrown"), "granted once")
	assert(st:apply(77, { action = "save", slot = 1, code = crowned }), "and then it can be worn")
	assert(st:view(77).unlocked[1] == "skylineCrown", "the creator is told it is unlocked")
	spec.parts.neck = "summitMantle"
	assert(not st:apply(77, { action = "save", slot = 2, code = AvatarKit.encode(spec) }), "the other one is still locked")
	local clean = AvatarStore.sanitize({ rewards = { "skylineCrown", 5, "skylineCrown", string.rep("x", 60) } })
	assert(#clean.rewards == 1 and clean.rewards[1] == "skylineCrown", "a stored list is cleaned: strings, once each, short")
end
print("PASS character store: defaults, batched writes that read back, slot rules, retried reads and writes, a failed read never overwrites, hostile records sanitised")
