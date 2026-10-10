// A seeded random number generator that produces the SAME sequence in JavaScript and in Luau.
//
// The engine used Math.random in three places, which is fine for a local prototype and wrong for
// everything the Roblox build needs: a server-authoritative match has to be replayable, a desync
// investigation needs the same inputs to produce the same frame, and the port's parity tests cannot
// compare two runs that disagree by design.
//
// xorshift32, deliberately. It is shifts and xors only - no multiply - so Luau's bit32 reproduces
// it exactly without any 32-bit-multiply workaround, and tests/rng-parity checks the first 20,000
// outputs of both against each other. The quality is far beyond what jittering a drip needs.
export function makeRng(seed) {
  // 0 is the one state xorshift cannot leave, so it is mapped away rather than left to stick.
  let x = (seed >>> 0) || 0x9E3779B9;
  return function rng() {
    x ^= (x << 13) >>> 0; x >>>= 0;
    x ^= x >>> 17;
    x ^= (x << 5) >>> 0; x >>>= 0;
    return x / 4294967296;
  };
}
