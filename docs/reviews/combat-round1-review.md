# Combat core, round 1 review: 5.3 / 10 (getting better)

One independent Claude reviewer (brief: `combat-round1.md`). It measured headless in Lune with small
probes.

| Area | Weight | Score |
|---|---|---|
| Feel and clarity | 20% | 6.5 |
| Neutral and defence | 25% | 5.0 |
| Combos | 20% | 4.5 |
| Edge and recovery | 20% | 6.0 |
| Robustness | 15% | 4.5 |

## Ranked

1. **Walls make true combos** (design, a Roblox-only layer).
   - A scripted attacker against Saltflat's bunker face landed true combos at 300%: Gauntlets 45
     hits, Scythe 30, Boots 27, Daggers 24, Grimoire 23. At 600% it still made 9-12-hit combos with
     no KO.
   - On open floor the longest is 3 hits. A perfect victim (timed break, tech every 9 frames, DI)
     is still held 59-93% of the time at the wall.
   - Cause: `Fighter._physics`' wall branch (`else self.vx = 0`) zeroes any launch under
     `BOUNCE.speed` (30) but keeps the full hitstun.
   - Fix: a launched fighter touching a wall below 30 has its hitstun capped at 8. In memory that
     brings the longest combo to 2-3 hits.
2. **A block's hitlag freezes only the attacker** (a BUG in both builds).
   - `Combat` sets `attacker.hitlag` on a block, but `applyBlock` freezes nobody, so the
     defender's blockstun keeps ticking.
   - Every on-shield number is 3-12 frames worse than `Knockback.onBlock` (the web HUD) and
     `tools/frame-advantage` say. Sword jab: −3 declared, −8 real. Sword SigNeutral: −17, −27.
   - Fix: pass the hitlag to `applyBlock` and freeze the defender too, as a hit does.
3. **Grab out of shield needs no drop** (design).
   - `_stepShield` turns a grab or a light into a 7-frame grab.
   - Only 4 of 216 melee moves are safe against it, and 20 against a drop plus an opener. A shield
     can only be pressured by grabbing it.
   - Re-measure after fix 2. If it is still above 90% punishable, put the 4-frame drop in front of
     the shield's grab.
4. **The first ledge grab's getup is fully invincible** (design).
   - `grabLedge` gives 30 invincible frames and `_startLedgeAction` keeps them: 0 of the getup's 25
     frames are vulnerable.
   - `Stage.ledgeFor` never checks occupancy, so two fighters can hang on one ledge and there is
     no hogging.
   - Fix: clear the invincibility in `_startLedgeAction`, so each option's own window governs.
5. **The combo break rarely matters.** It needs a 4th hit, and the web's longest combos are 2-6;
   five weapons never reach 4. It works when timed, and is fine once walls stop locking.
6. **Seed 137 never ends, but not because of walls** (the bots and the weapons). The fighters
   reached the bunker 18 frames before the cap. The Blasters landed only Full Auto and Strafe, so
   it could not finish.
7. **Tooling:** `tools/frame-advantage` must subtract the attacker's block hitlag and add a
   grab-out-of-shield column.

## Claims

1. On shield: the numbers reproduce, but the measure was wrong. The real safe count is 20 of 216
   against a drop plus an opener, and 4 of 216 against the grab.
2. Walls soak up launches: true as a mechanism, false as seed 137's cause. "vx 0, vy 23" was one
   frame after the wall zeroed a vx −26.3, vy 25.5 launch.
3. Locks: none on open ground (the web's combo test passes 157/157), real at walls.

## What works

- No loops on open ground.
- Separate launch and stun curves.
- A timed break beats the attacker, and mashing is punished.
- Fading invincibility on ledge regrabs.
- Deterministic replays.
