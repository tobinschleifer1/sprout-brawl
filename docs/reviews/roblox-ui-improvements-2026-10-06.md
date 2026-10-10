# Blockfall UI design study 02 — 6 October 2026

**Style correction:** The user rejected the prior visual direction. Previous theme scores are withdrawn. See [Study 03 — pixel platform fighter](../mockups/v3/README.md) for the new raster concepts and remaining limitations. Functional source inventory below remains useful.

[Interactive designs](../mockups/blockfall-live-ui.html) · [Six-screen visual board](../mockups/v2/previews/design-board.png) · [Previous study](../mockups/blockfall-live-ui-v1.html) · [Original live UI inventory](roblox-ui-map-2026-10-05.md)

This revision uses the running **Blockfall-ultfx.rbxlx** Studio build. The outdated revamp brief was not used. It develops the current sky bazaar, pixel fighters, dusk room background, navy cards, gold selection, bevelled buttons, and green/orange teams.

## What improved

| Area | Earlier weakness | Revised design |
|---|---|---|
| Game identity | Generic CSS fighter and emoji weapon symbols; approximate display type. | Twelve fighter/weapon portraits read from the live Roblox canvas and EditableImages, plus the eight live pixel stamps and fourteen quick-chat messages; the actual Luckiest Guy font from the installed Studio resources. Weapon role, difficulty and all four stat values come from the live modules. |
| Room selection | Repeated layouts and weak distinction between selection, voting and progression. | A stable Pick → Arena → Rules phase header, a four-column armory, player pedestals, explicit local identity and readiness. Ready toggles readiness without advancing the review to a new phase. |
| Bot voting | The state could imply that one player’s vote added a bot. | Difficulty choice, ballot, personal response and remaining time are separate. A YES vote leaves the room awaiting others. The example-opponent control outside the game previews the passed state. |
| Arena vote | Nearly identical thumbnails and mostly passive controls. | Nine recognisable illustrative arena compositions plus Random. The chosen card has gold, a check, vote count and a text confirmation. The choice can be changed. |
| Rules vote | Uneven information and decorative emphasis. | Every card aligns Win / Items / Disasters in the same rows. The selected ballot and clock occupy stable positions. |
| Character Studio | Fake option labels, weak save state, very limited interactions. | Live category and option names, category paging, selected option/colour, undo/redo, part lock, random part, pose selection, turn, new slot and save state. Session-only persistence remains prominent. Part thumbnails are illustrative; the main fighter is a captured pose. |
| Arcade | Open-seat and ongoing-match actions were mixed together. | Separate open-seat and occupied cabinet designs. The spectator exit is top right, away from the HUD. |
| Match HUD | Oversized two-player cards; players interleaved by team; stock labels competed with damage on phones. | Compact centred duel tiles, team-grouped larger rosters, clear damage hierarchy, stock/KO mode distinction, cropped portraits, segmented ultimate meters and a local marker. Stock labels sit below damage in the six-player phone layout. |
| Match events | Several different situations were combined into a single example. | Separate countdown, disaster/combo, break, ultimate, denied ability, knockout, eliminated and combo-guide designs. |
| Climb | A hard-coded purchase price and incomplete recovery states. | Price is deferred to the real Roblox purchase prompt. Checkpoint, restart confirmation, empty records and current-player record get separate designs. |
| Results | Two-player cards stretched across the whole screen and weapons could cover neighbouring fighters. | Centred duel podium, equal-width team cards, cropped weapon overhangs, readable result status, and a GG action that previews feedback locally. |
| Viewport coverage | A portrait phone sketch with very small labels. | Dedicated 844 × 390 landscape compositions alongside 1440 × 810 desktop. Three team-mode phone boards were explicitly checked. |

## Deliverables

- **33 interactive screen/state examples** in the standalone prototype.
- **45 SVG boards:** all 33 desktop states, six phone states, three desktop 3v3 states and three phone 3v3 states.
- A six-screen PNG visual board and PNGs of the key desktop/phone designs in `docs/mockups/v2/previews/`.
- Editable design source, the live art snapshot, the real avatar option labels, and repeatable build/render scripts.

The original live UI map remains the inventory of the Roblox code. This study expands its visual coverage rather than claiming every dynamic combination was played in Studio. Review navigation and the sample opponent/mode controls sit outside the depicted game interface.

## Grading

Scores are design judgments, not player-test results. The rubric is theme fit (25%), information hierarchy (25%), functional state clarity (25%), coverage (15%), and viewport fit (10%). The native SVG boards were rendered and visually inspected, including the dense 3v3 phone layouts. The standalone HTML browser integration has not been visually verified; the earlier local-file browser restriction remains.

The first study’s grades were provisional. Its placeholder art and lack of rendered inspection made those grades too generous as a readiness assessment. The following grades supersede them for these designs.

| Family | First revised pass | After refinement 1 | Final after refinement 2 | Remaining limitation |
|---|---:|---:|---:|---|
| Room selection / votes / notices | 7.0 | 7.8 | **8.3** | Ballots and timers use local sample data; arena art is illustrative. |
| Bazaar / social / arcade / spectator | 7.8 | 8.0 | **8.0** | Background scene is a UI composition, not a replacement for the live world art. |
| Character Studio | 6.9 | 7.4 | **7.6** | Part thumbnails and pose selections illustrate the interface; this prototype does not rebuild the live avatar renderer. |
| Climb / records / recovery | 7.7 | 8.0 | **8.0** | Course rendering, purchases and persistent records require the existing game systems. |
| Fight HUD / event states | 7.1 | 7.8 | **8.2** | VFX and timings remain static examples. Touch/controller combat controls are not invented here. |
| Results | 7.2 | 7.9 | **8.1** | Fighter poses are captured references; use the live victory/defeat animations in implementation. |

Overall criteria: theme **8.3**, hierarchy **8.2**, state clarity **7.8**, coverage **8.7**, and viewport fit **7.6**. With the weights above, the result is **8.1 / 10**. The stopping threshold is 7.5. No family fell below 5; each reached 7.5 within the maximum of two refinement passes. Refinement 1 corrected oversized duel cards, the clipped phone stat row, and weak typography. Refinement 2 corrected the 3v3 phone slot collision, portrait overhangs, small-screen stock placement, result-status contrast and missing editor controls.

## Source evidence

Live Studio instance: `b3573a88-fb3a-4664-ae58-5e90695b82ec`, **Blockfall-ultfx.rbxlx**.

- `Players.<local player>.PlayerScripts.Client.SelectScreen`: live roster, cards, readiness, ballot and phase behavior.
- `Client.WeaponStats` and `ReplicatedStorage.Shared.Data.Weapons`: the real role, difficulty, damage, defense, dexterity and speed values for all twelve weapons.
- `ReplicatedStorage.Shared.Data.AvatarKit`: real editor groups, categories and option names.
- `ReplicatedStorage.Shared.Data.Plaza`: social and destination reference, supplementing the previous audit.
- `PlayerGui.Blockfall.World`: read-only capture of drawn Frame positions, sizes, rotation, colour and opacity, plus the pixels of existing EditableImages. No deferred `AbsolutePosition` values were used.
- Installed Studio `LuckiestGuy-Regular.ttf`: the existing game display font, distributed here with its Apache 2.0 license and attribution. The Roblox implementation should keep using its current `Ui` font token.

## Validation and practical limits

- JavaScript syntax check passed.
- 396 combinations of screen, room format, viewport and stock/timed mode generated without undefined values or invalid dimensions.
- State checks verified weapon selection, Ready staying in the pick phase, arena/rules ballot changes, undo/redo, a new session character slot, and a YES vote not automatically adding a bot.
- All 45 exported SVG boards parsed successfully. The native vector exports and key phone/desktop PNGs were inspected; the supplied visual board uses the same scene generator as the prototype.
- `roblox/check.sh` passed. These are design artifacts; no gameplay or live UI modules were changed.

Implementation should start from the Studio build’s matching source revision. The local Luau checkout was older than the live UI during the original audit. Bring those modules into version control before applying this design, then reuse `Ui`, `Fighter2D`, `Stage2D`, `SelectScreen`, `AvatarEditor`, `Hud` and `PodiumView`; the prototype’s SVGs are design references, not a proposed replacement renderer.
