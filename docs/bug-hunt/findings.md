# Bug hunt findings (2026-10-22)

Plan: `plan.md`. Status: **fixed** (with a test, mutation-checked), **open**, or **design** (works,
but worth the owner's call).

## Part 1: every picture draws (`tools/sweep-art.luau`, now `tests/item-art` in check.sh)

Drew all 144 cosmetics and crates at the four tile sizes the game uses (576 drawings), through a
recording canvas, checking for errors, empty art, art outside its tile, NaN rects and magenta.

| # | Finding | Status |
|---|---|---|
| 1 | **Titles drew nothing.** `ItemArt.plan` returns "title" but `ItemArt.draw` had no branch for it, so the 5 titles' Locker/Shop tiles were empty mounts. Now a pixel nameplate in the rarity's colour. | fixed |
| 2 | **Six effects drew outside their tile**, over neighbouring cards (tiles do not clip): Ghost Rise up to 349 px past a 190 px tile, Event Horizon and Black Hole 61 px, Lightning 24 px, Meteor and Drop Pod 9 px. `FxArt.sized` fits by width at the art's anchor; tall or off-centre art overflowed. Now fitted by both sides around the art's own box. | fixed |
| 3 | Clothing worn below the head (shoes, mitts, shorts, trousers, capes) is drawn on a whole figure about 30 px tall, so the item itself is a few pixels: hard to tell what you are buying. A crop to the item's body part would show it. | design |
| 4 | Emote and victory-pose tiles all show the same yellow default fighter with a sword and look nearly alike at tile size. | design |

Contact sheet of every tile: `lune run tools/sweep-art <out.json>`, then `node tools/gui-svg.mjs`.

## Part 2: every screen at every size and in extreme states

Recorded every screen at 390x844, 667x375, 844x390, 1024x600, 1366x768 and 1920x1080, linted them, and
looked at the worst. Then again with the largest values a player can have (`BF_EXTREME=1` in
`tools/render-ui.luau`: 20-letter names, 999% damage, a 999,999,999 balance).

| # | Finding | Status |
|---|---|---|
| 5 | **Studio, phone (844x390), outfit tab: the two palettes ran 60 px into SAVE AS NEW / SAVE & WEAR**, and the top palette ran off the editor's right edge. A short screen now lays every palette side by side in one strip, each scrolling sideways and scrolled to your colour. | fixed |
| 6 | **Select, phone: roster portraits 1-2 px apart**, and a picked one's brackets on its neighbour (the fallback gap when the full one did not fit). The portraits now shrink to keep the gap; on a 667 px phone a compact mode: 2 px rings 12 apart, no brackets. | fixed |
| 7 | **Select, every size: a bot vote's YES and NO overlapped** (-3 to 5 px between outlines: 4% of the card), and VOTE RUNNING touched the difficulty chips. Ui.GAP spacing; the question, tally and chip words shrink to fit (they ran past the card on a 667 px phone). | fixed |
| 8 | Select, phone: the fighter cards sat 3 px above READY (a scaled 18 px gap). Now at least Ui.GAP. | fixed |
| 9 | Studio header: the editing slot's brackets came 6 px from the tab row. The header row is 2 px shorter and higher. | fixed |
| 10 | **Shop and Locker: a 999,999,999 balance overflowed its gem pill** into the key pill. Pills now widen to their value (`Ui.setCurrency`). | fixed |
| 11 | **People: a 20-letter name and "(YOU)" wrapped onto the place line** below it. The name shrinks to one line. | fixed |
| 12 | **People: your row's heavier ring was reset to 2 px** by the next line, so "(YOU)" was the only mark. | fixed |
| 13 | Locker, Shop, Results in portrait (390x844) are broken - Locker title under its pills, tabs off screen, 4 columns of 80 px cards. **Not reachable today**: the game sets no ScreenOrientation, so phones run landscape. Matters only if portrait is ever allowed. | open (low) |
| 14 | Shop on a landscape phone shows only the hero card before you scroll (a 390 px tall window). | design |

Checked and not bugs: HUD names past 20 letters (truncated with "…" in Roblox; the render tool does
not draw truncation); the results podium's hammer (it rests on the pillar's slab above the card);
the HUD's stock squares over the weapon name at 9 stocks (stocks top out at 5).

The phone sizes that broke are now in `tools/ui-lint.sh` (28 screens), so check.sh keeps them fixed.

## Part 3: long fuzzed matches (`tools/fuzz-matches.luau`)

`lune run tools/fuzz-matches <matches> <first seed>` plays random bot matches on the real server
simulation - any mode, 2-6 fighters, any weapons, avatars, bot levels, items, weapon drops,
disasters, stage - for up to 8 minutes each, checking every frame: no Lua error; positions,
velocities and damage finite; damage 0-999; stocks never negative; nobody alive past the blast zone
for a second; nobody's body inside a solid platform for half a second; every match ends.
`FUZZ_TRACE=seed:fighter:frame` prints that fighter's last 40 frames. 400 matches (970 minutes of
fights) take 2.5 minutes. No errors, no NaN, no damage or stock faults, nobody stranded past the
blast zone.

| # | Finding | Status |
|---|---|---|
| 15 | **Fighters passed up through solid platforms.** A fighter who bumps their head under a solid is placed exactly at its underside (`y = bottom - h`); next frame the check `py + h <= sp.bottom` fails by a rounding error (-11.2 + 5.2 is not exactly -6.0), so a rising move - an up-special, a double jump - carries them through, inside the stage. 35 of 400 fuzzed matches. Found on Ashfall Summit, seed 2: fall off the edge, drift under, jump, recover. Fix: `py + h <= sp.bottom + 0.001` (tested: removes those 35). **Shared simulation**: `roblox/src/shared/Stage.luau:372` mirrors `web/src/engine/stage.js` `collide`, so the fix belongs in both builds (parity), and the owner's rule is no web changes - the owner approved the web change (2026-10-23). | fixed |
| 16 | **A grab drops the grabbed fighter inside a solid.** The grab snaps the victim to the grabber's front with no collision; beside Saltflat's bunker (a solid block on the floor) that puts them inside it, and they walk out through it. Seed 131 frame 2799 (`FUZZ_TRACE=131:3:2803`). About 15 of 400 matches. Shared simulation: `Stage.clearX` in both builds now places a held or thrown fighter out of any solid, on the holder's side. | fixed |
| 17 | Stock team matches can run past 8 minutes: two impossible bots (Blasters vs Chakram, Faultline) traded for 8 minutes with one KO at 166-200%; a 5-stock 2v2 on Undertow still going. Balance/AI rather than a bug, but there is no clock on a stock match, so nothing ends it. | design |

### Part 3, continued: fixing the ways into solid ground (2026-10-23)

The owner approved changing the shared simulation in both builds. With #15 and #16 fixed, the fuzzer
(now measuring the body as the game's own footing test does: 0.6 of the radius) found three more:

| # | Finding | Status |
|---|---|---|
| 18 | **Corner tunnelling.** Falling diagonally past a solid's top corner, a fighter's body slid into the band beside it while the feet were still above the top; the landing missed (centre too far out) and the side check only stops a fighter coming from fully outside, so they moved on into the solid (Saltflat's bunker, seed 137). The side check now also catches one entering from outside the footing band, if their feet were below the top last frame (not one standing at the edge of a rising foothold - the web climb test caught that). Both builds. | fixed |
| 19 | **Redline Reversal (Rocket Boots' ultimate) ran straight through a block standing on its platform** - it moves the kicker a fixed step a frame and clamped only to the platform's ends. Roblox-only code. | fixed |
| 20 | **A vortex ultimate dragged its victim through solids**, and the Rundown ultimate could land its user inside one beside the target. Both builds, through `clearX`. | fixed |
| 21 | 3 of 1,200 fresh fuzzed matches still end up inside a solid (seeds 1254, 1302 and one in 3000-3399), down from about 1 in 8. Not traced yet. | open |

`tests/solid-ground` replays the seven seeds that found these with every invariant checked each
frame, in check.sh; each fix's removal makes it fail (mutation-checked).
