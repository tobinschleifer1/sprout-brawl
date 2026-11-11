# Weapons, round 1 review: the roster as built, 4.45 / 10 (bad design, by a hair)

One independent Claude reviewer (brief: `weapons-round1.md`). It measured everything in the worktree.
The art figures come from rasterising the shipping renderer in Lune.

| Area | Weight | Score |
|---|---|---|
| Identity | 25% | 5.5 |
| Balance | 25% | 3.5 |
| Depth and risk/reward | 20% | 5.0 |
| Readability | 15% | 3.0 |
| Roster consistency | 15% | 5.0 |

## What it found, ranked

1. **Art against hitbox: 155 of 216 melee moves disagree.**
   - On 137 moves a live box reaches 2 studs or more past anything drawn.
   - On 110 the blade sticks 1.5 studs or more out of every live box.
   - On horizontal moves the blade sits a median 16° below its box.
   - Worst: Axe 16/16, Flail and Hammer 15/15, Sword 14/16. Best: Rocket Boots 1/16, Blasters 4/11.
   - `web/test/geometry.test.mjs` checks only 6 up/down moves, so it never saw this.
   - Proposed: while a move is active, turn the blade (client only) to point at its largest live box, and draw the trail out to that box's far edge. Simulated, aiming alone takes the blades outside their box from 110 to 46.
2. **The Grimoire dominates through Runebrand.** It is a 15-frame projectile travelling 41 studs that launches 122 at 100%, and made 158 of the Grimoire's 194 KOs. Measured fix: damage 15→12, base 32→28, growth 4.4→3.6, which took the Grimoire from 82% to 69%. Cutting its range, its startup or the weight barely moved it.
3. **The bottom three are weapon problems, not only bot ones.** Blasters, Longbow and Whip stay at the bottom under every bot plan the reviewer tried.
   - Whip: the lash's second box goes to base 16, growth 0.4, angle 20, shoving people out to tip range. Measured 10→19%.
   - Blasters: Pop Shot, Double Tap and Strafe get +1 damage; Scattergun gets base 34 and growth 6.4. Measured 15→23%.
   - Blasters again: it cannot finish a stock, at 0.86 KOs a game and a median KO at 157%.
   - Longbow: no fix measurable, because the bot never presses Power Shot.
4. **The Scythe's sweet spot is worth nothing.** Reaper's Arc's handle launches 124 and its tip 128. Measured fix: cut the handle box to 11 damage, base 22, growth 3.0, offset [3.6, 2.8], size [5.8, 3.6]. That took the Scythe from 73% to 64%.
5. **Rocket Boots' ultimate never KOs**, from 0 to 400%. The first kick pops the victim over hits 2 and 3. Measured fix: give boxes 1 and 2 angle 20, base 3, growth 0.1, and box 3 base 30, growth 4.0. It then KOs at 142-146%, inside the roster's band of 132-213%.
6. **Clones and twins.**
   - The Chakram's and the Boots' normals are the Sword's, number for number.
   - Daggers and Gauntlets average 0.7 frames, 0.5 damage and 0.31 studs apart, on the same mechanic.
   - Hammer and Axe are near-twins too.
   - The Gauntlets' blurb says "lightest, fastest", but the Daggers are both. Gauntlets jumps 3→2 measured 76→70%.
   - Orbit Throw launches 28 at 100%, so the Eclipse Ring ultimate makes 60% of the Chakram's KOs.
7. **For the bot subject.** No bot tactic presses a neutral heavy. In 84 games each: Starfall 0, Counterguard 2, Power Shot 3, Overcharge 4, Overdrive Blow 5, Earthshatter 0. `wantsKill` always presses side+heavy, which on the Blasters is Full Auto, a move that cannot KO. So five weapons' signatures are never tested by the round robin.

## The claims

1. The round robin: true, and reproducible (the seeds are fixed). A weapon's standard error is about 3 points over 280 games; a single 20-game cell is about ±11.
2. Four archetype plans: true, and the "exactly four" comment is stale.
   - What survives a plan swap: Grimoire and Scythe on top (70% under the generic bot); Blasters, Longbow and Whip at the bottom.
   - Mostly the bot: the Pike (34% → 47% with a spacing plan).
   - Unproven: the Gauntlets' 76%.
3. The Sword's art: true, and roster-wide.
4. Boots' 234 launch: false as a threat. The table ignored `knockbackMul` and the whiff, and in play the ultimate never KOs.
5. Startups: true as tabled but misleading. The fastest move you can *open* with is 3 frames (Gauntlets, Daggers) to 9 (Hammer).

## What works

- The ultimates' 132-213% kill band.
- The mechanics' payoffs, 15 to 75 kill-%.
- The short-reach weapons' art.
- The Chakram's zoning.
- The matrix tools.
