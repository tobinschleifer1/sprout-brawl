# Brief: emotes and victory poses (phase 6, Roblox only)

For GPT-6-Astra (Codex), 2026-10-19. Branch `feature/emotes`, off `feature/clothing`, in its own
worktree. Read `AGENTS.md` and `roblox/README.md` first; their rules are not optional.

## What the owner decided

From `docs/briefs/crates-and-monetisation-plan.md`, "Phase 6: answered":

1. **Taunt plus a direction picks one of four equipped emotes.** Neutral, forward (toward the way the
   fighter faces), up, down: the stick held on the frame the taunt starts.
2. No KO departure item. Do not build one.
3. **One victory pose per player** (not per weapon), shown on the results podium for the winner(s).
4. **Emotes and poses are items.** Four emotes and one pose free for everyone; the rest come from
   crates, the shop and VIP, owned and worn like every other cosmetic.

## What exists

- The simulation already has a `taunt` state: `src/shared/Fighter.luau` (search `taunt`), 90 frames
  (`Config.TAUNT_FRAMES`), any press after frame 10 cancels it. **Do not change the simulation** - it
  is replay-held against the JavaScript (`check.sh`). The emote is presentation only: the taunt's
  timing, cancel rules and vulnerability stay exactly as they are.
- The replay-held pose for `taunt` is in `src/client/Channels.luau`. Do not edit Channels. Override it
  from a new Roblox-only module, the way `src/client/Kicks.luau` overrides the legs for Rocket Boots
  (see how `Posture.luau` and `Fighter2D.luau` consult `Kicks` and `DualWield`).
- Cosmetics: `src/shared/Cosmetics.luau` (`TYPES`, `add`), `src/shared/Inventory.luau` (`SLOTS`, what a
  loadout carries, sanitising), `src/server/Locker.luau` (WEAR / TAKE OFF, ownership checks),
  `src/client/LockerScreen.luau` (cards, wear), `src/client/ItemArt.luau` (thumbnails),
  `src/shared/Loot.luau` (crate pools; `tests/loot.luau` checks the odds tables still sum).
- What a fighter wears reaches every client as `char.cosmetics` (`MatchService` hook `cosmeticsFor`,
  read in `FxPlayer.luau`). Server effect events go out through `MatchService` (`m.events`, the
  `Events` remote) and are drawn in `FxPlayer.spawn`; `respawn` is a recent example of a Roblox-only
  event drawn from what the fighter wears.
- The podium: `src/client/PodiumView.luau` draws winners with `Fighter2D` in a victory pose.
- The plaza lobby (`src/client/Plaza2D.luau`, `LobbySocial.luau`) - emotes in the lobby are welcome
  if they fit cleanly, but matches and the podium come first.

## What to build

1. **The catalogue.** New cosmetic types `emote` and `victory_pose`. About 12 emotes and 6 poses:
   - free for everyone (source `"free"`, owned by all, never in a crate, not tradeable): four emotes
     (one for each direction by default) and one pose;
   - the rest: crate items across rarities (keep `Loot`'s tables valid and every crate item
     craftable), two shop-only, and one VIP emote (source `"pass"`, add it to
     `Products.PASS_ITEMS.vip`).
   Names and descriptions are yours; make each read clearly at fight scale (a five-stud fighter ~130
   px tall, and at the half-detail level).
2. **Wearing them.** Four emote slots (neutral, forward, up, down) and one pose slot in the loadout,
   sanitised like the others, worn from the Locker (an emote card needs a way to pick its slot).
   An empty slot plays that direction's free emote.
3. **Playing them.** When a fighter enters `taunt`, the server records the direction held on that
   frame and sends an `emote` event (fighter, slot); every client poses that fighter with the emote
   for the taunt's duration, ending cleanly if the taunt is cancelled. A Roblox-only module
   (`Emotes.luau`) produces the pose: keyframed limb, torso and head channels in the same form
   `Kicks` produces, sampled by the taunt's frame. Weapons stay in hand unless the emote says
   otherwise (a sheath, a spin).
4. **Victory poses.** The podium poses each winner with their worn pose (the free one by default).
5. **Thumbnails.** `ItemArt` draws each emote and pose as a still of its key frame.

## The bar

- `cd roblox && ./check.sh` exits 0 and `cd web && npm test` passes. No change under `web/`, none in
  `roblox/src/shared/Data/**`, none to generated fixtures or traces.
- New tests registered in `check.sh`: catalogue (every emote/pose distinct from its neighbours and
  from the plain taunt; free items owned by everyone), slots and sanitising, the event (the right
  slot for each direction, facing taken into account), the pose sampler (continuous between
  keyframes, ends at the stance), the podium using the worn pose. **Assert properties directly**,
  not only that something ran.
- **Mutation-check every test**: add entries to `roblox/tools/mutate-movement.py` in a new suite and
  run it; every mutation must be caught for the stated reason.
- Performance: an emote must not add sprites beyond what a pose already draws; measure with the
  existing budget tests (`tests/cosmetics.luau` and the Fighter2D budgets) and **never loosen a
  budget**.
- Nothing has to be seen in Studio by you; say plainly in your summary what was not visually checked.
  Render key frames with `tools/render-poses.luau` (or a sibling) and look at them yourself.

## When you finish

Commit on `feature/emotes` with messages that explain why (AGENTS.md "Commits"), ending with:

    Co-Authored-By: GPT-6-Astra (Codex) <noreply@openai.com>

If your sandbox cannot write git metadata, leave the work uncommitted in the worktree and write a
summary to `docs/briefs/gpt-emotes-report.md`: what you built, every test and mutation, what you
measured, and what you could not check.
