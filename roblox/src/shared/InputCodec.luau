--!strict
-- Packing an input frame into one integer, and back.
--
-- Split out of Net so it can be tested: Net touches ReplicatedStorage at require time and cannot
-- load outside Roblox, and this is the half where a mistake is silent. A flag written to the wrong
-- bit does not error - it produces a fighter that shields when you told it to grab, in one
-- direction only, and only over the network.

local Input = require(script.Parent.Input)

local InputCodec = {}

-- An input frame is fifteen booleans and two axes. Sending it as a table costs roughly 40x what
-- the bits are worth, per frame, per player, so it travels as one integer.
--
-- The axes are NOT tri-state. A gamepad stick gives the engine fractional x, which decides walk
-- against run and bends DI by angle; quantising it to -1/0/1 at the wire would silently delete
-- both on every controller. Five bits each, 1/15th of a unit, is finer than the engine's own
-- deadzone and leaves the whole frame inside 25 bits.
local FLAGS = { "jump", "light", "heavy", "dodge", "guard", "grab", "taunt", "pickup", "ult",
	"jumpHeld", "guardHeld", "heavyHeld", "lightHeld", "downTap", "anyPress" }

local AXIS_STEPS = 15
-- Fifteen flags, then five bits of x, then five of y. Exported so the server's bounds check and
-- the packer cannot drift apart: widening the frame and forgetting the validator would let the
-- extra bits through unvalidated.
InputCodec.MAX_PACKED = 2 ^ 25

local function quantise(v: number): number
	-- math.round, not floor(v + 0.5): v is signed here, and the two disagree on negative halves.
	-- Both ends of the stick have to round the same way or left and right are not symmetric.
	--
	-- One clamp, not two. Clamping v to [-1, 1] before scaling as well as clamping the result is
	-- unreachable by construction, and a mutation test proved it: deleting the inner one changes no
	-- output at all. Redundant guards that cannot fire are not defence, they are something a reader
	-- has to work out is pointless.
	return math.clamp(math.round(v * AXIS_STEPS), -AXIS_STEPS, AXIS_STEPS) + AXIS_STEPS
end

local function dequantise(n: number): number
	return (n - AXIS_STEPS) / AXIS_STEPS
end

function InputCodec.packFrame(f: Input.Frame): number
	local n = 0
	for i, key in FLAGS do
		if (f :: any)[key] then
			n = bit32.bor(n, bit32.lshift(1, i - 1))
		end
	end
	n = bit32.bor(n, bit32.lshift(quantise(f.x), 15))
	n = bit32.bor(n, bit32.lshift(quantise(f.y), 20))
	return n
end

function InputCodec.unpackFrame(n: number): Input.Frame
	local f = Input.emptyFrame()
	for i, key in FLAGS do
		(f :: any)[key] = bit32.band(bit32.rshift(n, i - 1), 1) == 1
	end
	f.x = dequantise(bit32.band(bit32.rshift(n, 15), 31))
	f.y = dequantise(bit32.band(bit32.rshift(n, 20), 31))
	return f
end

-- Merge an older frame into a newer one, for draining a jitter buffer that has backed up.
--
-- Presses are EDGE triggered and must survive: dropping the older frame loses a jump outright,
-- which is how the old MAX_QUEUED overflow behaved and is the worst possible way to lose an input.
-- Holds and the two axes are LEVELS, so the newer sample is simply the truth and the older one is
-- stale. The result is one frame that did everything both frames did, at the newer position.
--
-- This can put two presses on one frame that the player made on two - a light and a heavy become a
-- frame with both. That only happens while the buffer is draining, and a move coming out a frame
-- early beats a move not coming out at all.
local PRESSES = { "jump", "light", "heavy", "dodge", "guard", "grab", "taunt", "pickup", "ult",
	"downTap", "anyPress" }
local HOLDS = { "jumpHeld", "guardHeld", "heavyHeld", "lightHeld" }

function InputCodec.coalesce(older: Input.Frame, newer: Input.Frame): Input.Frame
	local out = Input.emptyFrame()
	out.x, out.y = newer.x, newer.y
	for _, key in HOLDS do
		(out :: any)[key] = (newer :: any)[key]
	end
	for _, key in PRESSES do
		(out :: any)[key] = (older :: any)[key] or (newer :: any)[key]
	end
	return out
end

-- Every press bit cleared, every held bit kept. This is what the server feeds a fighter when the
-- client's next frame has not arrived: holding a direction through a hiccup is right, and firing a
-- second jump out of a repeated packet is not.
function InputCodec.holdOnly(f: Input.Frame): Input.Frame
	local out = Input.emptyFrame()
	out.x, out.y = f.x, f.y
	out.jumpHeld, out.guardHeld = f.jumpHeld, f.guardHeld
	out.heavyHeld, out.lightHeld = f.heavyHeld, f.lightHeld
	-- Every press bit stays false, `guard` included. Shielding survives a dropped packet on
	-- `guardHeld` alone (Fighter enters and holds shield from that), whereas a repeated
	-- `guard` press would refill the tech buffer every starved frame and hand the player a free
	-- automatic tech for the duration of their packet loss.
	return out
end

return InputCodec
