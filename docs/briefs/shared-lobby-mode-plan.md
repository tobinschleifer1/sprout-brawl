# Shared 2D lobby — revised client requirements

The planned visual and spatial overhaul is now included in
[`blockfall-revamp.html`](blockfall-revamp.html#lobby) (2026-09-24): the Iron Concourse,
three mode entrances, walkable preparation rooms, station-focused setup, animation briefs
and L0–L3 delivery gates. That design is not implemented by this document update.
The room ownership, bot defaults and multiplayer requirements below remain in force.

This supersedes the six-arena-door layout in `lobby-and-launch-plan.md`.
The client released the main project for updates on 2026-09-22. Do not start/stop or control
their Studio session. Restart Play manually after sync because ModuleScripts are cached.

## Implementation delivered (2026-09-22)

- Three walkable world portals: 1v1, 2v2, 3v3. The compact room panel appears only after entry.
- Server-owned rooms admit 2/4/6 people with equal teams; a player belongs to one room.
- Map, own weapon/avatar, stocks, items, optional CPUs/difficulty and readiness live inside
  the room. All twelve weapon choices display actual Weapons2D artwork on embedded canvases.
- Bots default off (including legacy web/Roblox defaults), and reset off after a match.
- Only hosts change shared settings or bots. Nobody can overwrite another human slot.
  Changes invalidate readiness; full teams and every human ready are required to start.
- Each room runs its own MatchService and receives only its own match/scene/snapshot/events/
  results. Unique match IDs and input epochs reject unrelated/stale input.
- Shared cosmetic lobby poses are finite-checked, bounded and rate-limited; identity and
  loadout come from the server. Peers use real fighter artwork with smoothed positions.
- Host migration on setup leave; mid-fight departure cancels the affected room, not others.
  Completion tears down its simulation and returns the room to setup. Empty rooms are removed.
- Six-player HUD wraps without overlap at 360×640, 800×600 and 1280×720.

## Verification and remaining live QA

`roblox/check.sh` and `(cd web && npm test)` passed with exit 0 both in an isolated copy
and again in the main project after merge. `git diff --check` also passed.
New executable tests: `rooms`, `multiplayer`, `room-ui`; expanded `hub-view` checks peers.
The actual server entry point and MatchService ran a six-person room and a simultaneous
two-person room with a ninth uninvolved player, through 300 simulation frames. Each member
received 150 complete snapshots; input and results routing, cancellation, host migration,
return-to-room, optional bots and bounded presence were directly asserted.

Six deliberate mutations were caught: incomplete-team start, global match broadcast, missing
weapon art, overflowing HUD, broken ready toggle and missing lobby peers. The incomplete-team
mutation initially exposed a test gap; an explicit ready-host/empty-opponent assertion was
added and the mutation then failed. Mutation sources were restored in a separate nonsynced copy.

These are headless runtime tests, NOT a real multi-client Studio playtest. Actual 2/4/6-client
visual/input/network QA remains for a fresh Studio session. Matchmaking is within the same
Roblox server; cross-server queues/teleports are not part of this implementation.

The later ability goal superseded that deferral. Shield/ultimate input fixes and all-twelve-weapon
live Studio verification are recorded in `ability-fix-verification.md` (2026-09-23).

## Required player flow

Spawn in a shared, walkable 2D hub with other connected players. There are exactly three
play entrances: **1v1**, **2v2**, **3v3**. Arena names are not lobby destinations.

Approach an entrance -> interact -> choose map -> choose loadout and see weapon artwork ->
configure optional bots/rules -> join the room -> ready check -> match -> return to hub.

Bots are OFF by default. Empty places remain visibly open for human players; they must never
be filled by hidden auto-bots. Enabling CPUs is an explicit choice for empty places only.
Starting requires two complete sides (one, two or three fighters each), counting only joined
humans and deliberately enabled bots. No free-for-all option in this lobby flow.

## Work required, in order

1. **Deferred: shield / ultimate defect:** reproduce the reported full-meter failure in a real arena.
   Observe focus state, sampled O/I/Ctrl, packed input, server receipt, fighter state, meter,
   denial events, prediction state and rendered shield/ultimate. Fix the observed cause rather
   than merely adding key labels. Keep server authority. Add a regression at the failing layer.
   Surface readiness/denial feedback and identify the local player's meter clearly.
2. **Mode data and six-fighter support:** define the three modes once in web data, generate
   the Roblox copy, extend configuration and HUD layout to six fighters, and directly test
   complete equal teams. Existing general-purpose engine modes need not be deleted.
3. **Room service:** replace the one global match with server-owned rooms. Each has an ID,
   format, host, map/rules, fixed team slots, readiness and lifecycle state. A user belongs to
   at most one room/match. Send snapshots and events only to that room's members; unrelated
   lobby players must not be pulled into a fight by a global broadcast.
4. **Real-player slots:** clients choose only their own loadout/readiness. The server derives
   identity from the sender, admits human members and validates host edits. Cancel readiness
   after a map/rule/roster change. Rate-limit requests and reject cross-room or stale revisions.
   Disconnect/leave must release the place, cancel pending launch if required, and transfer
   hosting or close an empty room cleanly. Never overwrite another player's choice with a bot.
5. **Shared hub presence:** relay bounded, rate-limited cosmetic lobby movement and loadout
   identity; show/interpolate other connected avatars. Membership/room transitions are
   authoritative. A cosmetic hub position cannot award damage, grant items or join a match.
6. **World and room view:** only three mode portals in the concourse. Interacting opens that
   mode's room setup, containing map choices, team slots, loadouts, bots and ready controls.
   Keep the world visible behind the panel, with an explicit Leave / Back to Hub action.
7. **Weapon artwork:** display the actual equipped weapon art beside each choice and in the
   local loadout preview, using the existing pooled renderer. Do not substitute emoji or text
   for images and do not add an unrelated icon system. Highlight the chosen weapon by outline
   and label as well as colour. Cull/reuse preview geometry instead of creating it every frame.

## Test matrix before calling multiplayer complete

- Two real clients in 1v1; four in 2v2; six in 3v3. Everybody sees the correct teammates,
  opponents, loadouts, map and match result. Assert all fighter states fit the transport.
- A seventh player remains in the hub while a six-player match runs. Separate rooms never
  receive each other's Match/Snapshot/Scene/Results traffic.
- Bots disabled on fresh setup, reconnect and rematch. CPU enable/disable occupies only the
  selected empty slot. A no-bot room with missing players waits rather than silently launching.
- Host/member disconnect during setup, countdown and fight; duplicate ready/start messages;
  rejected stranger edits; room teardown and rejoin input-sequence reset.
- O at full meter and held I/Ctrl inside an actual arena, plus release, hitstun, ground/air
  restrictions, chat focus, controller equivalents and visible ability feedback.
- Weapon previews for all twelve choices; readable six-player HUD; replay, type-check and
  direct properties, with deliberate regression mutations in a nonsynced test copy.

## Previous evidence / ability limits

Before this implementation, the concourse was local and entered a one-human CPU-match flow.
That flow is now replaced by the room/presence implementation described above.

The client confirmed ultimate failed **inside a fight with a full meter**, so do not attribute
the report to an empty meter or to the lobby's intentionally disabled combat.

A read-only-source isolated diagnostic passed keyboard I -> input sampler -> codec -> server
queue -> real Match -> Snapshot -> shield bubble channels, and O with 20 charge -> Ultimate,
for all twelve weapons. That rules out neither a Studio input/focus problem nor a prediction/
rendering failure. No live-session fix has yet been established. Studio remains untouched at
the client's explicit request; live tracing must wait until they release their test session.
