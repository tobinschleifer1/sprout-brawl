# Stages, round 1 review: 4.6 / 10 (getting better, just)

One independent Claude reviewer (brief: `stages-round1.md`).

| Area | Weight | Score |
|---|---|---|
| Layouts | 25% | 5.0 |
| Hazards | 25% | 4.5 |
| Disasters | 15% | 3.5 |
| Readability | 20% | 5.5 |
| Robustness | 15% | 4.0 |

## Ranked

1. **Undertow's tide drowns with no input.**
   - Buoyancy reaches only `depth` 12 below the surface, but the tide rises 17 studs in `rise` 3 s.
     A floater sinks behind it and dies 21 s after entering the water.
   - Fix: `rise` 8 s (or `depth` 30), through a Roblox stage tuning layer (`StageTuning.luau`,
     like `WeaponTuning`, kept out of the replays).
   - Not alone: with rise 8, matches average 446 s and 2 of 10 time out, because the bots never
     climb out (issue 2).
2. **Bots have no water, hazard or disaster logic.** Their recovery steers for `stage.main`. On
   Smeltworks, main is only the west island, so bots over the east floor steer into the pit.
3. **Helpless never ends in water.** A swimmer cannot leave it at low tide. This is a behaviour
   change for the owner: entering water clears helpless.
4. **A disaster's hit wipes the attacker's kill credit** (a bug in both builds). `Disasters.hit`
   passes no attacker, and `applyHit` sets `lastHitBy` nil. Keep the old credit when there is no
   attacker.
5. **Disasters fire but never kill.**
   - 101 hits, 0 lethal. The earthquake hit once in 15 firings.
   - Try lavasurge base 75, tsunami base 70, earthquake damage 10 and tremor damage 6, then verify.
   - FoundryFloor, TheSpan and FreightLift have no disasters at all.
6. **The tide's rise has no warning.** Draw a high-water line for the last 3 s of low tide.
7. **The HUD cards cover the low-tide water** on Undertow.

## Claims

- The table is true.
- Undertow is mainly the stage, made worse by the bots.
- Smeltworks' third is the bots' recoveries, not hazards.
- Disasters fire 2-4.5 a match, but mostly change nothing.
- Every stage kills by the bottom: 79-95% of KOs, and 97% of those are failed recoveries.

## What works

- Match lengths vary by stage (136-245 s).
- On 7 of 9 stages the hazards are not unfair killers.
- Disaster scheduling is reliable.
- Most hazards have ramped warnings.
- No stalemates.
