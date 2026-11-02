# feature/new-players, review round 1 (2026-11-02)

One reviewer (Claude, general-purpose). Score **6.8 / 10: almost there**. Pure logic solid and
mutation-held; the wiring (server Tutorial/Settings/pick handlers, client tutorial and queue state)
untested, and two ways to get stuck in it.

| # | Finding | Done |
|---|---|---|
| 1 | A SKIP dropped by the tutorial lane's rate limit left the player in a Training match that never ends, no card, no way out | done/skip never rate-limited; a repeated one is answered; the client resends until the lobby comes (tests/multiplayer) |
| 2 | No way out while a lesson runs | LEAVE on the goal bar (tests/tutorial) |
| 3 | Players seated by the queue widening, or by another's arrival, or taken out by the tutorial, kept FINDING A FIGHT up | everyone seated hears they left the queue; the tutorial dequeues out loud (tests/multiplayer) |
| 4 | Starter Picks sold with nothing left to pick | NOT NEEDED and refused below two locked weapons (tests/shop) |
| 5 | Keyboard tutorial offered on touch-only devices | not offered there |
| 6 | Music slider controls nothing | no change: the owner chooses a track (Audio.MUSIC) |
| 7 | H bindable (the COMBOS key); Jump to W moved Space to Aim up | H reserved; a key both actions shipped with is not swapped (tests/settings) |
| 8 | CPU hits a player held behind the end card; queue re-run every frame; goal bar over the HUD's ability pill | the fight ends with the last lesson; queue once a second; goal bar at 132 |

Not changed: Fighter.luau's "botLevel never changes during a match" comment - shared code, and
the JavaScript's own Training mode changes it too.
