# Lobby revamp implementation handoff

Updated: 2026-09-24. Working directory: main project, not `.claude/worktrees/revamp`.
Design: [Blockfall revamp, lobby chapter](blockfall-revamp.html#lobby).

## Scope of this pass

Implement an L0 first slice: data-driven walkable preparation rooms entered from the three
existing mode gates; station-focused setup; a physical return exit; room-scoped cosmetic
presence. Preserve the current server-owned teams, explicit bots and ready checks. This is
not the complete sprite-art milestone; the new art pipeline in the separate revamp worktree
has not been merged into the main project.

## Baseline and environment

- Read root AGENTS.md. `roblox/check.sh` exited **0** before edits.
- Baseline log: `/tmp/blockfall-lobby-implementation-baseline.log`.
- Studio discovery returned no connected instances. No live visual or multi-client claim.
- Existing uncommitted gameplay/ability changes and unrelated clothing folders predate this
  pass and must be preserved. Do not revert them or assume they are part of this lobby work.

## Delivered first slice — verified headlessly

This is the functional L0 preparation-room slice, NOT the finished visual revamp or all of L0.

- The three existing mode gates now enter separate walkable preparation scenes after the
  server confirms membership. Room updates do not teleport a moving player or force a modal.
- Each scene has six reachable ground-floor stations: Concourse exit, Map Board, Weapon Rack,
  Lockers, Rules + Bots, and Ready Rail. Leaving returns to the gate's former location.
- RoomPanel is station-focused: no universal tab bar; Back to room closes it without leaving.
  Ready/start controls belong to Ready Rail; optional per-slot CPU controls belong to Rules.
  Server team validation, host-only rules, own-loadout edits and bot defaults are preserved.
- The physical rack draws all twelve weapons using the actual existing weapon renderer;
  the catalogue retains clickable weapon artwork. Gates have different machinery silhouettes,
  amber signage and industrial preparation props. These are pooled-geometry blockout/fallback
  visuals, NOT the new Aseprite art or the separate revamp branch's finished weapon pixels.
- Cosmetic presence is partitioned by server-derived room ID (0 = concourse). The server
  rejects stale/forged area packets and clamps positions against that room's geometry.
  Clients also ignore stale presence from another area. No cross-room preparation ghosts.
- Shared JavaScript/Luau Lobby movement supports scene changes, collision bounds, local
  stations and zero-velocity respawns. Web data remains authoritative; Hub.luau is generated.

### Files changed in this pass

- `web/src/data/hub.js`: gate landmarks and three preparation scene definitions.
- `web/src/engine/lobby.js`, `roblox/src/shared/Lobby.luau`: scene-aware movement/interaction.
- `roblox/src/client/Hub2D.luau`: physical preparation views, scene switching, rack artwork,
  gate silhouettes, room-status text and area-filtered peer rendering.
- `roblox/src/client/RoomPanel.luau`: station-specific modal behavior and rules/ready controls.
- `roblox/src/client/init.client.luau`: entry/exit/station dispatch and room-aware pose packets.
- `roblox/src/server/init.server.luau`: authoritative preparation-area presence partitioning.
- `web/test/hub.test.mjs`, `roblox/tools/gen-hub-trace.mjs`, and Roblox tests `hub-parity`,
  `hub-view`, `room-ui`, `multiplayer`: expanded direct properties and replay coverage.
- `roblox/src/shared/Data/Hub.luau`: regenerated, never hand-edited.

### Verification

- Final `roblox/check.sh`: **exit 0**. Log: `/tmp/blockfall-lobby-implementation-check.log`.
- Final `cd web && npm test`: **exit 0**. Log: `/tmp/blockfall-lobby-implementation-web.log`.
- `git diff --check`: passed.
- Replay now covers 12 weapons × 4 scenes = 76,800 frames / 614,400 fighter values,
  including scene-transfer resets. Direct JS tests reach all 18 preparation stations without
  jumping and assert scene bounds, harmless controls and reset behavior.
- Headless Hub2D test renders all preparation stations, checks finite/bounded geometry,
  verifies every weapon on the physical rack, unchanged position on room refresh, peer
  filtering and return-to-gate. The original concourse peak was 416 drawing primitives.
  Preparation scenery has its own <1,200 primitive assertion, not a runtime timing claim.
- The real server entry point still passes concurrent six/two-player match transport tests;
  new assertions cover preparation/concourse isolation, stale area rejection and room bounds.
- Six deliberate mutations all failed their intended tests: missing scene reset, removed rack
  artwork, auto-opening modals, accepting forged areas, cross-area presence broadcast, and
  selecting concourse stations inside a preparation room. Mutated ONLY the isolated copy
  `/tmp/blockfall-lobby-mutations.31AYcF`; restored each mutation afterward.
- `rojo build --output /tmp/Blockfall-lobby-L0.rbxlx`: **exit 0**. This is a fresh main-project
  build with the lobby changes and all pre-existing main-project edits. It has not been played.

### How to try it next

Open `/tmp/Blockfall-lobby-L0.rbxlx` in Studio, or build again from this main project's `roblox/`
directory. Start fresh Play (cached modules require a restart). Walk to 1v1/2v2/3v3 and press
E / controller X. Walk to each preparation station and interact; close its panel to keep moving.
Use Rules to deliberately enable CPUs if testing alone, then Ready Rail to ready/start.
Use the physical Concourse exit to leave the room. No new Rojo serve process was started and
no Studio instance was opened, stopped or controlled during this implementation pass.

**Live rendering and actual 2/4/6-client Studio behavior remain unverified.** Studio discovery
returned no connected instances. Headless draw tests cannot establish that the scene looks right.
The normal browser game's menu is not yet replaced: this pass ports and replays the shared
scene/movement logic, but full web lobby presentation remains work for the next milestone.

## Remaining after this slice

L1 final 8 px/stud atlas artwork/62 new drawings, animation-manifest integration, four-layer
bespoke scenery, UI map thumbnails, richer room discovery, robust acknowledged asset preload,
web lobby presentation integration, mobile movement controls, audio, reduced motion, real
2/4/6-client Studio QA and measured device performance. Keep bots off by default.

## Next implementation steps

1. Live-test this first slice, including return after a fight, host leave, focus and controller
   navigation. Fix any observed problem before layering final art over it.
2. Integrate with `.claude/worktrees/revamp` carefully: it has the art pipeline but not all of
   main's room/ability changes. Do not overwrite whole entry points or import old networking.
3. Build the web walkable view and R0/L1 sprite path. Replace the blockout with the approved
   8 px/stud assets; do not label pooled placeholders as completed pixel artwork.
4. Add map thumbnails, real room discovery (current join still chooses an available same-mode
   room), ready-rail occupancy graphics, acknowledged asset loading and the remaining L1–L3 work.

No commit or push was made. Account usage was nearly exhausted at handoff; no reset credit
was redeemed. Unfinished shield/ultimate follow-up work from earlier turns was not expanded or
claimed fixed by this lobby pass.

## Integrated with the revamp branch — 2026-09-25

The L0 slice above now lives on branch `revamp/sprites-disasters` (worktree
`.claude/worktrees/revamp`), applied unchanged as commit "Bring over the lobby L0 slice…"
together with the revamp's pixel-art weapons and animation manifest. The main checkout was only
read; its uncommitted copy is now redundant with the branch. Continue lobby work on the branch.

Review findings, fixed and covered by tests (each checked by breaking the code on purpose):

- **Matchmaking could strand players.** `Rooms.join` took the first open slot in `pairs` order,
  which Luau leaves unspecified. After some leaves, two 1v1 rooms could each hold one waiting
  player while newcomers landed in either at random. Joins now fill the fullest waiting room
  first, lowest id on a tie (`tests/rooms.luau`).
- **Own-loadout edits failed whenever a teammate readied.** Every edit had to match the room
  revision, and ready toggles bump it. The revision still guards consent and shared settings
  (a stale ready or host change is refused; a duplicate ready cannot flip twice); a player's own
  weapon/avatar is exempt (`tests/rooms.luau`).
- **Weapon tiles cut long weapons off and blurred the pixels.** The catalogue used one fixed
  window (1.5 ± 3.5 studs), which clipped the Pike. `Weapons2D.fit` now frames each weapon's real
  extent at a whole multiple of 8 px/stud, so the pixel art lands on whole screen pixels. Tiles
  also show the weapon's archetype (`tests/weapon-art.luau`, 60 tile sizes).
- **The map board now shows each stage's layout** — solids, lit caps, ledges, shelves, and a
  moving shelf's travel — drawn from the stage data itself (`RoomPanel.drawStage`,
  `tests/room-ui.luau`). luau-lsp caught this pass referencing colour constants before their
  declaration; the test now also asserts every thumbnail rectangle has a colour.

Checked and NOT a problem: `onFinished`'s `task.wait(6)` runs inside `task.spawn`, so it blocks
nothing. Rate-limited room actions are dropped silently; the panel keeps no pending state, so
nothing sticks, but a dropped click gives no feedback — a candidate for later polish.

Still unverified live: no Studio instance was connected on 2026-09-25.
