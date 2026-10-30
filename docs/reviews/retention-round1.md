# Retention, round 1: the plan

Review `docs/briefs/retention-plan.md`: a plan to make Blockfall players keep playing and come back.
Blockfall is a 2D platform fighter on Roblox (Luau port under `roblox/`). Score the PLAN, not effort.

## Read (and nothing else unless a claim needs checking)
- `docs/briefs/retention-plan.md` - the plan (the subject).
- `roblox/src/shared/Progression.luau` - levels, unlocks, the Ranked ladder as built (~150 lines).
- `roblox/src/server/Economy.luau`, functions `_matchFinished`, `_progress`, `qualifies` - how a
  match pays today (drop meter, first win, XP, rank, hourly cap of 12 counted matches).
- `docs/briefs/crates-and-monetisation-plan.md`, sections "Other reasons to come back" and "Spending
  Robux" - what was already promised, and the pricing principles (Sparks never sold; no paid random
  items for restricted players).

## Claims to verify
- CLAIM: levels 16-50 currently pay nothing beyond XP. (Check `Economy._progress`.)
- CLAIM: progress cannot be farmed beyond 12 counted matches an hour, and a match counts only after
  45 s of play with a hit dealt or taken.
- CLAIM: nothing in the game today gives a reason to return on a given day except the first-win bonus
  and the featured shop's daily rotation.

## Questions
1. Is the build ORDER right - does it strengthen the weakest loop first for the least work? What
   would you move, and why?
2. What is missing that would matter more than something listed? (Think: new-player first session,
   lapsed players, solo players with no friends online, low-population servers where queues are slow.)
3. What here could backfire - feel like a chore, pressure, pay-to-win, or be exploitable (e.g.
   quests farmed against bots, friend bonus farmed with alts, streak abuse)? Concrete fixes.
4. Are the reward numbers in step 1 sane next to the economy (Sparks craft costs 30-1200ish, Forge
   Key sold at 75 R$, first win 25 Sparks, ranked win 15)? Give numbers if not.
5. For steps 1-3, is the design specific enough to build without guessing? Name the gaps.

## Rubric
Score 0-10 overall, and 0-10 each for: order/prioritisation, completeness, risk handling,
economy sanity, buildability. Bands: under 4.5 bad - 4.5-6.5 getting better - 6.5-8 almost there -
8-10 workable. Measure everything; do not grade effort. Say what would raise the score, ranked.
Keep the report under 900 words. Do not edit any files.
