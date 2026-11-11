# Weapons, round 2 review: 5.05 / 10 (getting better)

One independent Claude reviewer (brief: `weapons-round2.md`), economical by request: spot checks of
56 games, about ±5.6 points.

| Area | Weight | Round 1 | Round 2 |
|---|---|---|---|
| Identity | 25% | 5.5 | 5.5 |
| Balance | 25% | 3.5 | 4.0 |
| Depth and risk/reward | 20% | 5.0 | 5.5 |
| Readability | 15% | 3.0 | 5.0 |
| Roster consistency | 15% | 5.0 | 5.5 |

## Round 1's findings

- **Fixed:** the Grimoire (82% to 71%), the Scythe's sweet spot (tip 128, handle 65), and Redline Reversal (kills at 142%).
- **Partly fixed:** art against hitbox. Moves that disagree fell from 165 to 96 of 200, and the result holds on the first and last active frames too.
- **Mostly not fixed:**
  - The bottom three: Blasters 23%, Whip 15%, Longbow 15%.
  - The Blasters still cannot finish a stock: 442 damage a KO in the mirror, against 129-231 for the rest.
  - The clones and twins are untouched.

## Ranked for round 3

1. **The bottom three.**
   - The bot presses Full Auto 990 times for every 59 Scattergun, so its kill move is the Blasters' problem. Full Auto base 20, growth 3.2 measured 21% → 27%.
   - Whip: Bullwhip Snap startup 16 → 12, 12% → 18%. Cutting the lights' recovery did nothing.
   - Longbow: Rainfall startup 24 → 18 is untested.
   - The real lever is the bot's `wantsKill`.
2. **Readability.**
   - What is left is weapons drawn longer than their boxes. Extend the Pike's boxes to its art: LightDown +3.7, LightUp +3.2, SigNeutral +3.0, AirNeutral +2.5 studs. That buffs the Pike (34%) as well.
   - Aiming at the tip was worse (106 moves disagree).
   - The aim freezes motion: 13 of 30 sweeping moves now sweep under 5°. The fix is to work out the turn once, on the first active frame, and add it to the drawn swing from then on.
3. **The Gauntlets will not come down** (73%). Neither jumps nor damage moved them. Try speed: LightSide1 and LightNeutral1 startup +1.
4. **Clones and twins cap identity.** That needs a design decision, not tuning.
5. **The round robin uses about 13 of each weapon's 17 moves** (LightUp and AirFinisher never; SigNeutral almost never). That is the bot subject's.
6. **Small:** `weapon-design` should check the Gauntlets' "shortest reach" (3.17 studs against the Daggers' 3.34).

## Claims

All three are true.

The snap the brief worried about is authored. The drawn swings already jump a median 110° on the first active frame, and the aim adds a median of 1°.
