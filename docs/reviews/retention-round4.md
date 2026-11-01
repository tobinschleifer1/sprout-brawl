# Retention, round 4: Step 2 as built (the cap, the Road to 50)

Blockfall is a 2D platform fighter on Roblox (Luau under `roblox/`). Plan: `docs/briefs/retention-plan.md`
(v3), Step 2. Earlier rounds: plan 5.9 and 6.7, Step 0/1 build 6.6 (`docs/reviews/retention-round{1,2,3}-review.md`).
Score the BUILD of Step 2 on `feature/retention`. Do not grade effort.

## What changed
- `roblox/src/shared/Progression.luau`: `levelReward`, `TITLES`, `KEY_WEEK`, `week`.
- `roblox/src/server/Economy.luau`: `_matchFinished` (three states: counted / progressing / not
  counted; `FIRST_METER`; welcome back, `WELCOME_AWAY`/`WELCOME_EVERY`; `least()`), `_progress`
  (the Road to 50 loop and its watermark `progress.paid`, VIP on level Sparks, the weekly ranked
  key cap, `opts.rested`).
- `roblox/src/shared/Inventory.luau`: `SOURCES` (+level, +mastery), `HEADROOM`, `add(..., headroom)`,
  the sanitised `progress` fields (paid, keyWeek, keyCount, seen, welcomed).
- `roblox/src/shared/Cosmetics.luau`: titles Veteran/Elite/Master (`source = "level"`).
- `roblox/src/server/MatchService.luau`, `results()`: per row `humanFoe` and `title`.
- Client: `DropBanner.progressText` (rewards summary, key cap), `DropBanner.text` (capped states),
  `DropBanner.lines` (welcome back), `NextGoal.levelReward`, `LobbySocial` (`NextReward` line),
  `PodiumView` (`PlayerTitle`).

## Read only these (only the named functions in the long files), plus the tests
`roblox/tests/progression.luau` sections 5, 5c, 7; `roblox/tests/economy.luau` (search "capped");
`roblox/tests/podium-view.luau` (search "title"); `roblox/tests/match-launch.luau` (search "humanFoe").

## Commands (cheap)
```bash
cd roblox && lune run tests/progression && lune run tests/economy && lune run tests/podium-view
```

## Claims to verify
- CLAIM: past 12 counted matches in an hour, a match with a human opponent pays XP, rank points and
  level rewards but no drop, first win or ranked Sparks/keys; with only bots it pays nothing.
- CLAIM: every level 2-50 pays exactly once, however many levels one match crosses, including levels
  reached before Step 2 shipped (back-pay through the watermark, once).
- CLAIM: a level title cannot be lost to a full locker, nor dropped when the record is read back.
- CLAIM: ranked boost keys are at most 3 per UTC week (Monday-Sunday).
- CLAIM: every new test was mutation-checked.

## Questions
1. Exploits: can anything here be farmed or double-paid (alts, bots in a mixed match - one human
   opponent plus bots counts as "humanFoe" -, the watermark, the welcome crate, the key week)?
2. Back-pay: a player at level 30 when this ships gets levels 2-30 at once (~1,500 Sparks, 6
   crates, 3 keys) on their next match. Right call? Any risk?
3. Does the player understand what happened? (Strip wording, the "Drops rest for N min" line, the
   NEXT reward line on PLAY, titles on the podium.)
4. Anything in Step 2 of the plan that was not built, or built differently?

## Rubric
Score 0-10 overall, and each of: correctness, exploit-resistance, test strength, player-facing
quality. Bands: under 4.5 bad - 4.5-6.5 getting better - 6.5-8 almost there - 8-10 workable.
Measure everything; rank what would raise the score. Under 900 words. Do not edit files.
