--!strict
-- The input codec, round-tripped.
--
-- Exhaustive over the flags, because that is affordable: fifteen booleans is 32768 combinations and
-- every one is checked against every one of the 31 quantised axis values on both axes. A codec test
-- that spot-checks a few frames is a codec test that passes while two bits are swapped.

local Loader = require("./loader")
local InputCodec = Loader.load("InputCodec")
local Input = Loader.load("Input")

local FLAGS = { "jump", "light", "heavy", "dodge", "guard", "grab", "taunt", "pickup", "ult",
	"jumpHeld", "guardHeld", "heavyHeld", "lightHeld", "downTap", "anyPress" }

local checked = 0
local function fail(msg: string): never
	error(msg, 0)
end

-- 1. Every flag combination, axes at rest.
for mask = 0, 2 ^ #FLAGS - 1 do
	local f = Input.emptyFrame()
	for i, key in FLAGS do
		(f :: any)[key] = bit32.band(bit32.rshift(mask, i - 1), 1) == 1
	end
	local back = InputCodec.unpackFrame(InputCodec.packFrame(f))
	for _, key in FLAGS do
		if (back :: any)[key] ~= (f :: any)[key] then
			fail(`flag {key} did not survive the round trip at mask {mask}`)
		end
		checked += 1
	end
	if back.x ~= 0 or back.y ~= 0 then
		fail(`axes moved on a frame that had none: {back.x}, {back.y}`)
	end
end

-- 2. Every representable axis value, on both axes, independently.
for step = -15, 15 do
	local v = step / 15
	local f = Input.emptyFrame()
	f.x, f.y = v, -v
	local back = InputCodec.unpackFrame(InputCodec.packFrame(f))
	if math.abs(back.x - v) > 1e-12 or math.abs(back.y + v) > 1e-12 then
		fail(`axis {v} round-tripped to {back.x}, {back.y}`)
	end
	checked += 2
end

-- 3. Quantisation is symmetric. Left and right must lose exactly the same amount, or a stick held
-- at the same angle in each direction produces two different DI angles.
for i = 0, 1000 do
	local v = i / 1000
	local pos = InputCodec.unpackFrame(InputCodec.packFrame((function()
		local f = Input.emptyFrame(); f.x = v; return f
	end)())).x
	local neg = InputCodec.unpackFrame(InputCodec.packFrame((function()
		local f = Input.emptyFrame(); f.x = -v; return f
	end)())).x
	if math.abs(pos + neg) > 1e-12 then
		fail(`asymmetric quantisation at {v}: +{pos} vs {neg}`)
	end
	if math.abs(pos - v) > 1 / 30 + 1e-12 then
		fail(`axis {v} quantised to {pos}, further than half a step`)
	end
	checked += 2
end

-- 4. Out of range input is clamped, not wrapped. A client is free to send x = 9, and the packer
-- must not let it land in the y field.
for _, v in { -9, -1.5, 1.5, 9, 1e9 } do
	local f = Input.emptyFrame()
	f.x = v
	local packed = InputCodec.packFrame(f)
	if packed >= InputCodec.MAX_PACKED or packed < 0 then
		fail(`x = {v} packed to {packed}, outside MAX_PACKED`)
	end
	local back = InputCodec.unpackFrame(packed)
	if math.abs(back.x) > 1 or back.y ~= 0 then
		fail(`x = {v} escaped its field: got x={back.x} y={back.y}`)
	end
	checked += 2
end

-- 5. holdOnly clears every press and keeps every hold. Named explicitly rather than looped, so
-- that a flag added to the frame shape and forgotten here shows up as a missing assertion rather
-- than passing by default.
local held = Input.emptyFrame()
for _, key in FLAGS do
	(held :: any)[key] = true
end
held.x, held.y = 1, -1
local h = InputCodec.holdOnly(held)
for _, key in { "jump", "light", "heavy", "dodge", "guard", "grab", "taunt", "pickup", "ult", "downTap", "anyPress" } do
	if (h :: any)[key] then
		fail(`holdOnly kept the press bit {key}, which would re-fire it every starved frame`)
	end
	checked += 1
end
for _, key in { "jumpHeld", "guardHeld", "heavyHeld", "lightHeld" } do
	if not (h :: any)[key] then
		fail(`holdOnly dropped the hold bit {key}`)
	end
	checked += 1
end
if h.x ~= 1 or h.y ~= -1 then
	fail(`holdOnly dropped the stick: {h.x}, {h.y}`)
end
checked += 2

-- coalesce: draining a backed-up jitter buffer must not lose a press.
--
-- Every press is checked on BOTH sides of the merge, because a coalesce that simply returned the
-- newer frame would pass a test that only put presses on the newer one - and it would lose every
-- input the player made while their connection hiccuped, which is precisely the case this exists
-- for. The holds and axes are checked to come from the newer frame only.
local PRESS_KEYS = { "jump", "light", "heavy", "dodge", "guard", "grab", "taunt", "pickup", "ult",
	"downTap", "anyPress" }
local HOLD_KEYS = { "jumpHeld", "guardHeld", "heavyHeld", "lightHeld" }

for _, key in PRESS_KEYS do
	for _, onOlder in { true, false } do
		local older, newer = Input.emptyFrame(), Input.emptyFrame()
		;(if onOlder then older else newer :: any)[key] = true
		local m = InputCodec.coalesce(older, newer)
		if not (m :: any)[key] then
			fail(`coalesce lost the press {key} from the {if onOlder then "older" else "newer"} frame`)
		end
		checked += 1
	end
end

-- Holds and axes are levels: the newer frame is the truth and the older one is stale.
local older, newer = Input.emptyFrame(), Input.emptyFrame()
older.x, older.y = 1, 1
newer.x, newer.y = -1, 0
for _, key in HOLD_KEYS do
	(older :: any)[key] = true
end
local m = InputCodec.coalesce(older, newer)
if m.x ~= -1 or m.y ~= 0 then
	fail(`coalesce took the stale axes: {m.x}, {m.y}`)
end
for _, key in HOLD_KEYS do
	if (m :: any)[key] then
		fail(`coalesce kept the stale hold {key} after the newer frame released it`)
	end
	checked += 1
end
checked += 2

print(`checked {checked} codec values`)
print("InputCodec round-trips every flag combination and every axis step.")
