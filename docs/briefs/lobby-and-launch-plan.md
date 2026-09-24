# Blockfall walkable 2D lobby and launch repair

## Corrected client direction

The client clarified that "lobby" means an explorable two-dimensional world, **not** a menu/HUD.
The player spawns as their fighter, runs and jumps through a factory concourse, and approaches
physical doors or workstations to choose a game. The earlier menu-first design is superseded.

## Client feedback and confirmed baseline

September 22, 2026. `roblox/check.sh` and the web test suite both exited 0 before editing.
Unrelated clothing asset folders are out of scope.

The four-fighter reproduction received a Match message and 119 Scene messages in four seconds,
but zero Snapshot messages and drew zero arena Frames. Studio reported oversized unreliable
payloads, approximately 350–400 bytes over the limit. This is why selecting more opponents can
produce a blank game even though the server is playing. The earlier two-fighter smoke test did
not cover this transport limit. Roblox documents that oversized unreliable events are dropped:
https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent

Ultimate (O), shield (I / Left Ctrl) and pickup (P) already exist in the keyboard sampler.
The discoverability bug is that the select screen and HUD never explain them. We will test the
actual bindings as well as making them visible; no combat balance change is required.

## Implementation order and acceptance criteria

1. Repair launch: send complete snapshots on reliable transport at a bounded 30 Hz, retain
   60 Hz simulation/input, and keep stale-frame rejection. This removes the unreliable payload
   ceiling without fragmenting a frame into partially arriving fighters. Test the real broadcast
   method and cadence, and run 2-, 3- and 4-fighter matches in Studio. Profile bandwidth/latency
   separately before scaling multiplayer beyond this four-fighter server.
2. Add a launch state: lobby -> requesting -> loading arena -> playing -> results -> lobby.
   Fight locks while pending; selection remains visible with progress until the first snapshot.
   Timeout/refusal shows a useful message and retry. Rejoining an existing owned match resends
   its description; a busy server never silently ignores a request.
3. Make controls discoverable: one Roblox binding definition feeds polling and the UI. Show a
   complete Controls page and compact in-match hints. Explain full-meter ultimate, held shield,
   nearby-item pickup and item use. Verify keyboard and gamepad press/hold behavior.
4. Spawn into a walkable side-scrolling 2D concourse. Open small settings panels only after the
   player interacts with a nearby world station; arena doors lead to a match confirmation.
5. Verify replay parity, direct properties, deliberate regression mutations, and fresh Studio
   GUI geometry plus real button-to-match operation. Document unverified device/performance work.

## Visual lobby plan

Keep the client's dark, gritty, rich pixel-art direction: charcoal metal panels, stepped edges,
an amber active/focus state, off-white body text and restrained teal arena accents. Background
silhouettes stay low-contrast; controls must remain easy to read. No new raster asset uploads
or unrelated monetization UI are needed for this first version.

The Iron Concourse is a long industrial hall with heavy stepped doorways, inset lights, steel
floor seams and rivets, structural columns, workshop props and optional jumping catwalks. The
camera follows the fighter horizontally. All destinations remain reachable along the main floor.
Actual stage-platform diagrams decorate the arena doors. World-space signs identify destinations;
only a small movement hint and nearby-interaction prompt stay on screen.

| Place in the hall | First-version content | Purpose |
|---|---|---|
| Spawn / concourse | Your fighter, left/right wayfinding, optional catwalks | Start in the world rather than a menu |
| Six arena doors | Foundry Floor, The Span, Smeltworks, Rooftops, Saltflat, Undertow | Choose a destination by walking to its door |
| Armoury | Twelve weapons and six cosmetic looks | Change loadout, then return to the same place in the hall |
| CPU roster station | Three slots, explicit Add/Remove, difficulty and weapon | Separate opponent count from difficulty |
| Rules desk | Stock/timed, FFA/teams, stocks, duration, independent items toggle | Configure the next fight |
| Field manual | Actual keyboard/gamepad bindings and ability explanations | Learn before entering an arena |

Move with WASD/arrows or a stick, jump with Space/gamepad A, and interact with E/gamepad X. You
must be within seven world units horizontally and three vertically of a station. A door selects
its own arena and offers Enter Arena; a workstation offers Return to Concourse, never Fight.
Back to Lobby dismisses the panel without teleporting the fighter or losing choices. Navigation
tabs are hidden at world stations. Panels lock while a launch is pending.

## Structural plan

- `Hub2D` owns the local playable world, camera, signs, proximity interaction and pooled art.
- `web/src/data/hub.js` defines geometry/destinations and generates `Data/Hub.luau` normally.
- `web/src/engine/lobby.js` and `shared/Lobby.luau` use the real fighter movement/collision while
  filtering combat inputs. Replay tests hold the two implementations together. The Roblox client
  uses this hub; the web game's existing entry screen is unchanged in this pass.
- `Select` is retained only as the station-panel view in the shipping Roblox flow.
- Put binding names and readable labels together in a pure client module shared with the sampler.
- Keep launch timing/state in a small testable client module, separate from UI drawing.
- Keep server-owned match startup/rejoin in MatchService; validate configurations before start.
- Persist choices for the current server session only. Never suggest durable saving exists.
- Match retry resets its input sequence with a new epoch, so packets from before a rejoin cannot
  contaminate the fresh predictor's history. The authoritative match itself is not restarted.

## Later lobby work, not promised in the first version

The first hub is local to each player and enters the current CPU-match flow; it is not yet a
shared social lobby with other players' avatars or independent concurrent match rooms.
Replicated lobby presence, party invitations, a ready check for real human opponents, private rooms/matchmaking, practice
drills, remappable controls, touch combat controls, audio/settings, and durable loadouts should
follow separately. No nonfunctional Ranked/Online/Shop buttons in this version. Before release,
playtest navigation at small resolutions and on a controller, and measure real multiplayer
latency and sustained network traffic.
