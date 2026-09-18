--!strict
-- A seeded random number generator that produces the SAME sequence as web/src/engine/rng.js.
--
-- xorshift32: shifts and xors only, no multiply, so bit32 reproduces it exactly with no 32-bit
-- multiply workaround. tests/rng-parity.luau compares 20,000 outputs across six seeds against the
-- JavaScript, because a generator that is "close enough" is a generator that desyncs a match
-- twenty seconds in.

local Rng = {}

function Rng.make(seed: number): () -> number
	-- 0 is the one state xorshift cannot leave, so it is mapped away rather than left to stick.
	local x = bit32.band(seed, 0xFFFFFFFF)
	if x == 0 then
		x = 0x9E3779B9
	end
	return function(): number
		x = bit32.bxor(x, bit32.lshift(x, 13))
		x = bit32.bxor(x, bit32.rshift(x, 17))
		x = bit32.bxor(x, bit32.lshift(x, 5))
		return x / 4294967296
	end
end

return Rng
