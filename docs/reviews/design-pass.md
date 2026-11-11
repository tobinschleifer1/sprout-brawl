# The design pass, November 2026

The owner, 2026-11-11: improve weapon design first, then the whole game's design, through every
system, with the scored review loop. That loop is the one in `README.md` and the `ui-review` skill:

1. Make the round's changes.
2. Prove them with tests, each one mutation-checked.
3. Write a brief.
4. Have **one** independent reviewer score the round in the background.
5. Record the score and loop.

Three rounds per subject. A subject stops early once a round scores above 8, and if 8 is not
reached by round three it carries on.

## Rules for this pass

- **Roblox only.** The web build is paused (owner, 2026-10-11), so the web's simulation, data and
  replay-held client modules are not edited for design changes. Weapons from the web are tuned by
  a Roblox-only layer in `roblox/src/shared/Weapons.luau`, which already copies the generated
  roster and appends `RobloxWeapons.luau`. The replay checks read `Data/Weapons` directly and are
  unaffected. New mechanics go in Roblox-only modules.
- Never edit `roblox/src/shared/Data/**` or the generated fixtures.
- `check.sh` exits 0 on every commit. Every new test is broken on purpose once to show it fails,
  and the fault goes in `tools/mutate-movement.py`.
- Each subject gets a branch off `main` (`feature/design-<subject>`) in its own worktree. Nothing
  merges to `main` until the owner says so.

## Subjects, in order

| # | Subject | Last score | State |
|---|---|---|---|
| 1 | Weapons: the 15-weapon roster, its moves, mechanics, balance, art against hitbox | 4.45 at round 1 | round 2 |
| 2 | Bot AI: how bots fight, per weapon and level | 4.1 at round 1 | round 2 |
| 3 | Combat core: hitstun, knockback, shield, dodge, ledge, combos and breaks | never scored | |
| 4 | Stage hazards and disasters | rounds 1-2 (`../hazard-design-review.md`), round 3 outstanding | |
| 5 | Items and weapon drops | never scored | |
| 6 | Match formats and rules: stocks, FFA, teams, ranked, rooms | never scored | |
| 7 | Maps | 6.08 / 6.25 at round 5; round 6 brief never reviewed | |
| 8 | New players and the tutorial | 6.8 at round 1 | |
| 9 | Progression, economy, crates, retention | 7.0 at retention round 4 | |
| 10 | Lobby and plaza | 7.43 at round 9 | |
| 11 | UI | 8.08 / 7.6 at arcade round 9 | |
| 12 | Characters, cosmetics and the character studio | never scored | |
| 13 | Movement and animation: run, jumps, air, attack poses | never scored as a whole (the run was reworked 2026-11-08..11) | |
| 14 | The climb (parkour) | never scored | |
| 15 | Social: parties, invites, rooms with friends | never scored | |

The order runs from the owner's ask (weapons) to what most changes how a fight plays (the bots,
then combat), then the systems around the fight. Subjects already near 8 come late, since they
mostly need one confirming round each.

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
| 2026-11-11 | Bots | 1 | **4.1** (bad) | dead-opponent freeze, drowning, main-only stage sense, side+heavy kill press, no neutral heavies, unreachable air finishers (`bots-round1-review.md`) |
| 2026-11-11 | Stages | 1 | **4.6** (getting better) | Undertow's tide drowns on its own, disasters never kill, a disaster wipes kill credit (`stages-round1-review.md`, on `feature/design-stages`) |
