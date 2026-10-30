# Retention, round 3: Steps 0 and 1 as built (and plan v3)

Blockfall is a 2D platform fighter on Roblox (Luau under `roblox/`). The plan
`docs/briefs/retention-plan.md` (v3) scored 5.9 then 6.7 (`docs/reviews/retention-round{1,2}-review.md`).
This round scores the BUILD of Steps 0 and 1 (commit a293f61 on `feature/retention`), and briefly
whether v3 took up round 2's six asks. Score what is there; do not grade effort.

## What changed
- `roblox/src/server/Analytics.luau` (new): `Analytics.event(player, name, fields)`. Wired in
  `roblox/src/server/init.server.luau` (search `Analytics.event`).
- `roblox/src/client/NextGoal.luau` (new): the near-miss line. Shown from
  `roblox/src/client/init.client.luau` (search `NextGoal`) via `DropBanner.line`.
- `roblox/src/server/Rooms.luau`: `Rooms.requeue`, the `avoid` check in `Rooms.join`, and the
  rewritten first loop of `Rooms.matchQueue` (`openRoomFor`). Server action `requeue` in init.server.
- `roblox/src/client/SelectScreen.luau`: the `Requeue` button (search `NEW OPPONENTS`).
- `roblox/src/client/LobbySocial.luau`: `INVITE FRIENDS`, `LobbySocial.tick` and `QUIET` (the quiet
  queue), the quiet clock in `setQueue`.

## Read only these (plus what a claim needs)
The files above (only the named functions in the long ones), and the tests:
`roblox/tests/progression.luau` sections 6b and 8, `roblox/tests/social-ui.luau` (search "INVITE"
and "quiet"), `roblox/tests/select-screen.luau` (search "NEW OPPONENTS"), `roblox/tests/multiplayer.luau`
(search "NEW OPPONENTS").
Renders: `.renders/retention/play.png`, `sel.png`, `sel-phone.png` (look at them).

## Commands (cheap unless marked)
```bash
cd roblox
lune run tests/progression     # ~2 s
lune run tests/social-ui       # ~1 s
lune run tests/select-screen   # ~5 s
lune run tests/multiplayer     # ~20 s
python3 tools/mutate-movement.py --suite multiplayer   # ~1 min; others are minutes (expensive)
```

## Claims to verify
- CLAIM: a player who presses NEW OPPONENTS is never seated back in the room they left - by the
  queue, by a later queue arrival, or by FILL WITH BOTS - and the one left behind keeps the room.
- CLAIM: NEW OPPONENTS is refused once the fight has started.
- CLAIM: Analytics can never throw into the server's flow.
- CLAIM: the near-miss line picks the closer goal by the share still to go, ties to the level.
- CLAIM: every new test was mutation-checked (82 mutations caught across five suites).

## Questions
1. Bugs: anything in requeue / avoid / matchQueue that strands a player, double-seats one, leaks
   the `avoid` entry forever, or breaks the existing queue (fullest-first, forming at all-but-one)?
2. Does the near-miss line say the most useful thing? It shows only level and tier today (quests
   come in Step 3). Is the copy right? Is it readable stacked over two other banner lines?
3. Is NEW OPPONENTS placed and named well? INVITE FRIENDS? Does the quiet nudge read as help, not nag?
4. Are the analytics events the right ones to baseline Steps 1-3? What is missing?
5. Plan v3 vs round 2's asks: which were taken up, fudged or missed (one line each)?

## Rubric
Score 0-10 overall, and 0-10 each for: correctness, test strength, player-facing quality,
plan v3. Bands: under 4.5 bad - 4.5-6.5 getting better - 6.5-8 almost there - 8-10 workable.
Measure everything; do not grade effort. Rank what would raise the score. Under 900 words.
Do not edit any files.
