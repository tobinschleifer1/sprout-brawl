# Retention, round 3 review: Steps 0 and 1 as built - 6.6 / 10 (almost there, just)

One independent Claude reviewer (brief: `retention-round3.md`). Correctness 6.5, test strength 6.0,
player-facing 6.5, plan v3 7.5.

## Found, and what was done
1. **NEW OPPONENTS could re-pair the same two players** (both press it, or one leaves and queues
   again: the room is gone and the queue formed a new one with both). `avoid` held a room id.
   -> Now it holds the PEOPLE left, both ways, for `Rooms.AVOID_SECONDS` (60 s, so two players on a
   quiet server are never kept apart for good), honoured by `join`, the open-place loop, the
   new-room loop (a group of players who do not avoid each other) and FILL WITH BOTS. Tested: both
   press, leave-then-queue, fill, expiry, forget.
2. **`avoid` leaked** past unqueue and leaving the server. -> `Rooms.forget` on both.
3. **`session_start` counted every Hello** (a client rejoining a delayed arena says Hello again).
   -> Once per visit. Tested through the real server.
4. **FILL WITH BOTS could stay on its pulse colour.** -> Repainted when the quiet ends. Tested.
5. The quiet nudge replaced the waiting count. -> Added to it.
6. Step 1.7 (first-session "start here") was not built. -> Built: a new player's 1v1 pulses and the
   note says where to start, until they choose.
7. `match_finished` lacked format and cpu. -> `format, cpu, counted` (a capped match is its own
   event); added `unqueue`, `left_match`, and client impressions through a `Track` remote that takes
   only `Analytics.CLIENT`'s names, one a second.
8. Step 1 shipped with no switch for a baseline. -> `Shared/Features.STEP1`.
9. Analytics with a throwing service, and its field values. -> Tested.
10. **The near-miss line was never looked at.** Rendering it (tools/render-ui results 812 375
    earned) showed three stacked strips covering most of the podium's stat cards on a phone. -> One
    strip, the drop line's old footprint, turning through level/rank, next goal and drop every 3 s.

Not done: the phase mismatch between `join` and `openRoomFor` (older than this work; a room in a
vote is always full, so `join` cannot seat anyone there).
