# Handoff to GPT (Codex), 2026-10-15

Claude is handing the Roblox work to GPT-6-Astra running in Codex. This is the whole brief:
read it top to bottom before touching anything, then work the task queue in order.

## Where things stand

All work is on the branch **`feature/character-rig`** (pushed to `origin`). It is **not merged to
`main`**, and the owner said to leave merging for now. Do not merge it, and do not push to `main`.

Done on that branch, each piece merged only when `roblox/check.sh` passed:

- **Character rework phases 1-4** (`docs/briefs/character-rework-plan.md`):
  - kit bodies for the six presets;
  - ten facial expressions (`src/client/Expressions.luau`);
  - the jointed rig (elbows and knees), with the posture layer (`Posture.luau`, `PostureArt.luau`);
  - movement feel: walk, run, jumps, reactions, plus trailing hair, capes and coats (`Movement.luau`, `Secondary.luau`).
- **Two Roblox-only weapons**:
  - the **Chakram** (twin returning rings);
  - **Rocket Boots** (kicks and thrust fuel).

  Their data is in `src/shared/RobloxWeapons.luau`, merged into the roster by `src/shared/Weapons.luau`. Tests: `tests/chakram.luau` and `tests/rocketboots.luau`.
- **Low-end performance**, two passes: 38% fewer property writes a frame, and 15% fewer live Frames. Notes are in `roblox/docs/match-performance.md`, the budget test is `tests/perf-budget.luau`, and the benchmark is `tools/perf-match.luau`.

Nothing above has been seen running in **Roblox Studio**. Every check so far is offline (Lune tests and rendered PNGs). Studio's keyboard input from the tools did not reach the game, so the owner is the one testing it live.

## The rules (the owner's, and they override `AGENTS.md` where they differ)

1. **Roblox only.** Do not modify anything under `web/`. The web build is paused.
2. **Replay-held code stays identical.** `roblox/check.sh` replays the JavaScript against these modules:
   - `src/client/Channels.luau`, `Rig.luau`, `AvatarCompose.luau` and `WeaponPose.luau`;
   - `src/shared/*`, the simulation;
   - the generated `src/shared/Data/**`, which you must never hand-edit.

   You may add Roblox-only behaviour to them **only gated on a field or id that no web weapon or data has**. The Chakram's `ring`, the boots' `fuelCost` and `ThrustFuel`, and `wid == "Chakram"` are the examples. Prefer new Roblox-only modules downstream (see `roblox/README.md`, "Roblox-only code").
3. **`cd roblox && ./check.sh` must exit 0** before any commit you call finished.
4. **Every test is mutation-checked.** After writing a test, break the code it covers on purpose, confirm the test fails, then restore the code. Say which mutations you tried in the commit message. Never weaken an existing assertion to make something pass. Performance budgets may be tightened, never loosened.
5. **Lowest devices first.** Roblox's Frame fallback (no EditableImage) is the target:
   - no per-frame picture changes, because a sprite whose picture changes rebuilds its Frames;
   - no extra sprites per fighter without measuring them (`tools/measure-movement.luau`, `tools/perf-match.luau`);
   - Frames cannot shear, so every sprite must reach Canvas2D as a rotation plus an axis scale (tests check this).
6. **Invariants:** the front hand sits exactly on the weapon grip; planted feet stay planted; nothing changes a hitbox, damage or timing unless the task is balance.
7. **Look at what you draw.** Render, then view the PNG:
   - `lune run tools/render-poses <out.json> <Weapon> <moves,csv> Classic`
   - `tools/render-fight.luau`
   - `tools/render-posture.luau`
   - then `node tools/fight-png.mjs <in.json> <out.png> <cols> <scale>`

   Check at match scale too: a fighter is about 26 px tall.
8. **Git:**
   - Work on a new branch off `feature/character-rig` for each task: `feature/<name>`, `fix/<name>` or `chore/<name>`.
   - Make small commits. Messages explain WHY, not what. End each with `Co-Authored-By: GPT-6-Astra (Codex) <noreply@openai.com>`.
   - When a task is done and `check.sh` passes, merge it into `feature/character-rig` (fast-forward if you can) and push `feature/character-rig`.
   - If you are stopped part-way, commit what you have as `WIP: <task>` so it is not lost.
9. **When a decision belongs to the owner, do not make it.** Write the question down in "Questions for the owner" at the end of this file, commit that, and move to the next task.

## Task queue, in order (none needs the owner)

1. **Close the test gap in movement.** `tests/movement.luau` asserts that the run's shins never cross, but it does not catch `rootX = 0` in `src/client/Movement.luau`. That mutation makes both legs hang from one hip point, and they can't cross from a shared point, so the test still passes. Add a direct assertion that the two hips stay separate sockets through the stride, then mutation-check it.
2. **The still portraits use the old body.** These draw the old 7-piece pose with no face:
   - `src/client/KitPortrait.luau`, used by the avatar editor's tiles and the lobby member list;
   - `tools/kit-sheet.mjs`.

   Make the portraits use the same jointed body and the neutral face the fight uses, within the editor's draw budget (`tests/creator-ui.luau`). Render before and after.
3. **Stop the start-of-match hitch.** The first fight frame creates about 2,500 Instances in one burst (`roblox/docs/match-performance.md`, "not done"). Build the fighters' sprites during the countdown instead, and prove the first fight frame then creates far fewer. Keep the draw output identical (`tools/perf-raster.luau` compares two renders on pixels). Tighten `tests/perf-budget.luau` to match.
4. **A firmer balance check for the new weapons.** Run `tools/weapon-balance.luau` for Chakram, RocketBoots and Sword with 8 matches per opponent. If either new weapon falls outside 40-50% overall, tune its data in `RobloxWeapons.luau` (prefer reach, weight and damage over frame data), re-run, and record the numbers in the commit message. Keep `tests/chakram.luau` and `tests/rocketboots.luau` passing.
5. **Rocket Boots bots keep fuel for recovery.** Today a bot spends fuel freely, so it can arrive offstage with only the weak recovery hop. In `src/shared/Ai.luau`, gated on the `ThrustFuel` mechanic, keep at least the mechanic's `recoveryCost` in the tank when near a ledge or in the air. Add a test to `tests/rocketboots.luau`: a bot launched offstage reaches the ledge more often than before. Measure it.
6. **Review the whole branch.** Review `feature/character-rig` against `main` for correctness bugs, Roblox-runtime errors (nil fields on snapshots, previews, podium, plaza) and divergence from the rules above. Fix what you find, each fix with a test.
7. **Write the pull-request text** for `feature/character-rig` into `main`, as `docs/briefs/character-rig-pr.md`. Cover what changed and why, how it was verified, what has NOT been verified (Studio, devices), and the risks. Do not open the PR and do not merge.

## Needs the owner first (do not start these; ask)

- **Phase 5:** the `k2` code format and earned cosmetics (entitlements).
- **Phase 6:** emotes, a KO exit, victory poses. The owner dismissed the first set of questions, so ask again: how emotes are chosen, what a KO looks like, and podium poses by player or by weapon.
- **Phase 7:** a bigger part catalogue and the rebuilt character studio.
- **Phase 8:** attitudes.
- **More weapons.**
- **Merging to `main`.**
- **The EditableImage permission.** It is off in the place, under Experience Settings → Security. It is the owner's setting; it would make the image path work on capable devices.

## How to run this

From the repo, in a worktree on a task branch:

```bash
codex exec -m gpt-6-astra -c model_reasoning_effort=xhigh -s workspace-write \
  --add-dir "<repo>/.git" -C "<worktree>" - < docs/briefs/gpt-handoff.md
```

`roblox/tools/codex-handoff.sh` does exactly this and resumes after a usage limit.

## Questions for the owner

(Add them here, dated.)
