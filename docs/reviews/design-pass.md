# The design pass, November 2026

The owner, 2026-11-11: improve weapon design first, then the whole game's design, through every
system, with the scored review loop. That loop is the one in `README.md` and the `ui-review` skill:

1. Make the round's changes.
2. Prove them with tests, each one broken on purpose to show it fails.
3. Write a brief.
4. Have **one** independent reviewer score the round in the background. Up to three reviews may
   run at once on different subjects, but usage is kept down: briefs carry the measurements, and
   reviewers are asked to spot-check rather than re-derive them.
5. Record the score and loop.

Three rounds per subject. A subject stops early once a round scores above 8, and if 8 is not
reached by round three it carries on.

## Rules for this pass

- **Roblox only. Never edit `web/`**, not even to fix a bug (the owner, 2026-11-11). The one web
  change made before that, combat round 2's block freeze, stays as it is. Shared simulation is
  changed through Roblox-only layers that the replays switch off:
  - `RobloxRules.luau`: every `*parity*` test sets `.on = false`.
  - `WeaponTuning.luau`: the replays build `Loadout.build(..., true)`.
  - The bots' layer: planned, behind a flag the AI replay turns off.
- Never edit `roblox/src/shared/Data/**` or the generated fixtures.
- `check.sh` exits 0 on every commit. Every new test is broken on purpose once, and the fault goes
  in `tools/mutate-movement.py`.
- Everything is on `feature/design-pass`, which merged the per-subject branches (weapons, combat,
  stages, bots) on 2026-11-11. Nothing merges to `main` until the owner says so.

## Subjects, in order

Fifteen subjects became eleven on 2026-11-11: neighbours were merged so that each review covers
more for its cost.

| # | Subject | Last score | State |
|---|---|---|---|
| 1 | Weapons: the 15-weapon roster, its moves, mechanics, balance, art against hitbox | 5.05 at round 2 | round 3 built; its review waits on the bots' round 2 |
| 2 | Bot AI: how bots fight, per weapon and level | 4.1 at round 1 | round 2 built, in review |
| 3 | Combat core: hitstun, knockback, shield, dodge, ledge, combos and breaks | 5.9 at round 2 | round 3 |
| 4 | Stages: layouts, hazards, disasters (their look was the maps rounds, 6.08 / 6.25 at round 5) | 4.6 at round 1 | round 2 |
| 5 | The match: items, weapon drops, formats, rules, rooms | never scored | |
| 6 | New players and the tutorial | 6.8 at round 1 | |
| 7 | Progression, economy, crates, retention | 7.0 at retention round 4 | |
| 8 | Lobby, plaza, social and parties | 7.43 at lobby round 9 | |
| 9 | UI | 8.08 / 7.6 at arcade round 9 | |
| 10 | Characters, cosmetics and the character studio | never scored | |
| 11 | Movement and animation (run, jumps, air, attack poses), and the climb | never scored | |

## Found on the way, for later subjects

- **Combat core: walls soak up launches.** Under the round-2 weapon tuning, fuzz seed 137 (Blasters,
  impossible, against Whip, hard, on Saltflat) never ended. Both fighters were pressed against the
  right face of the bunker (solid #3, x -20..-12). The wall soaked up every sideways launch: at 277%
  and 499%, Bullwhip Snap lifted its victim 2 studs and moved it nowhere. A fighter against a wall
  cannot be knocked out sideways, which is a stalemate with bots and a safe spot for a human. A
  wall bounce or a wall tech is the usual answer. `tests/solid-ground` now replays its seeds on the
  untuned roster, the matches they were found in.

## Log

| Date | Subject | Round | Score | Notes |
|---|---|---|---|---|
| 2026-11-11 | Weapons | 1 | **4.45** (bad) | baseline; art and hitbox disagree on 155/216 moves, Grimoire's Runebrand dominates, Blasters/Longbow/Whip are weak weapons, the bot never presses neutral heavy (`weapons-round1-review.md`) |
| 2026-11-11 | Combat core | 1 | **5.3** (getting better) | true combos against walls, block hitlag freezes only the attacker (a bug), shield grab needs no drop, first ledge getup fully invincible (`combat-round1-review.md`) |
| 2026-11-11 | Weapons | 2 | **5.05** (getting better) | aim halves the art/box disagreement; Grimoire, Scythe, Redline fixed; the bottom three wait on the bot's kill move (`weapons-round2-review.md`) |
| 2026-11-11 | Bots | 1 | **4.1** (bad) | dead-opponent freeze, drowning, main-only stage sense, side+heavy kill press, no neutral heavies, unreachable air finishers (`bots-round1-review.md`) |
| 2026-11-11 | Stages | 1 | **4.6** (getting better) | Undertow's tide drowns on its own, disasters never kill, a disaster wipes kill credit (`stages-round1-review.md`) |
| 2026-11-11 | Combat core | 2 | **5.9** (getting better) | wall locks, block freeze and ledge fixed; the Flail's Snare crashes the sim; the wall cap also cuts vertical launches (`combat-round2-review.md`) |
