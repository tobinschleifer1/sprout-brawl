# Combat core, round 2 review: 5.9 / 10 (getting better)

One independent Claude reviewer (brief: `combat-round2.md`). Measured headless, nothing in Studio.

| Area | Weight | Round 1 | Round 2 |
|---|---|---|---|
| Feel and clarity | 20% | 6.5 | 6.5 |
| Neutral and defence | 25% | 5.0 | 5.5 |
| Combos | 20% | 4.5 | 6.0 |
| Edge and recovery | 20% | 6.0 | 6.5 |
| Robustness | 15% | 4.5 | 5.0 |

- **Fixed:**
  - Wall locks: 47 hits → at most 6 across 15 weapons × 6 patterns.
  - The block freeze: both sides freeze alike.
  - The ledge getup is hittable.
- **Not fixed:** grab out of shield, ledge hogging, the frame tool's mechanics.

## Ranked

1. **The Flail's Snare (SigDown) crashes the simulation every time it catches someone.**
   - Its `vortex` has no `escapePerPress`, `escapeCap`, `escapeBite` or `diPerFrame`, and
     `Combat.luau` does arithmetic on them.
   - Fix: Roblox-only defaults (the Scythe's values: 4, 16, 8, 0.17).
2. **The wall stun cap also cuts vertical launches.** A victim against a wall still drifts into it
   under an 80-88° launcher, so 23 of 44 grounded launchers lose over 40% of their hitstun there.
   Fix: cap only when the sideways speed lost is at least half the vertical (flatter than about
   63°). Tested: 42 of 44 keep their stun, and wall chains stay at 4 or less.
3. **Grab out of shield still beats nearly everything.** Only 22-35 of 157 moves can escape it.
   Fix: `SHIELD_GRAB_DELAY` 4, so a shield grab pays the drop.
4. **The Chakram has a 14-hit chain on open floor** at 100% (SigNeutral and a jab mash). It is
   breakable from hit 4. This one is for the weapons subject.
5. **`tools/frame-advantage` is wrong for 31 of 157 moves**, because it does not model the weapon
   mechanics.
6. **`LEDGE_ACTION_CLEARS` also wipes respawn and ultimate invincibility.** Fix: subtract only what
   the grab granted.

## Claims

All true.

The seed-bound statistics were re-measured honestly. The readability margin is thin: 42% against a
40% bar.
