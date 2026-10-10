# Blockfall Roblox UI map — live Studio build, 5 October 2026

**Style correction:** The user rejected the prior visual direction. Previous theme scores are withdrawn. See [Study 03 — pixel platform fighter](../mockups/v3/README.md) for the new raster concepts and remaining limitations. Functional source inventory below remains useful.

**Updated designs:** [Study 02, 6 October](roblox-ui-improvements-2026-10-06.md) expands the prototype to 33 states and includes rendered boards. Its grades supersede the provisional first-pass grades below.

This audit is based on the running `Blockfall-ultfx.rbxlx` Studio play session and its Client ModuleScripts. The local `roblox/src/client` checkout is older: it still names `Hub2D` and has no `Plaza2D`, `AvatarEditor`, `SelectScreen`, or `PodiumView`. It is **not** a reliable visual reference for this audit. The companion [interactive mockups](../mockups/blockfall-live-ui.html) are proposals; they do not change the Roblox game.

## Live design language

The live build is a bright sky-island arcade, not an iron foundry. I observed blue sky and white pixel clouds, floating stone and grass, bazaar stalls, a large Blockfall billboard, a fighter rendered as pixel art, and bold outlined cartoon headings. Its `Ui` module defines LuckiestGuy display text, GothamBlack labels, navy panels, heavy ink outlines, bevelled buttons with a shine and bottom lip, pale keycaps, rounded status pills, and a palette led by gold, blue, green, pink, purple and red. Map voting and results use a darker dusk sky as a distinct arena-adjacent mood. The mockups retain this vocabulary.

## State journey

```text
Skyhold Bazaar / Champions' Square
  ├─ wardrobe or CHARACTER → Character Studio → save/wear or close
  ├─ T/Y/P/M → stamps / quick messages / people / bazaar map warp
  ├─ arcade cabinet → sit / VS CPU / watch → fight or STOP WATCHING
  ├─ 1v1, 2v2, 3v3 gate → room SelectScreen
  │    ├─ pick weapon, team pedestal, bot proposal/ballot, READY
  │    ├─ map vote → rules vote → loading
  │    ├─ HIDE → walkable lounge → ROOM ▲ reopens select
  │    └─ optional room boards → RoomPanel Maps / Weapons / Rules / Players
  └─ Skyline Climb → progress HUD / checkpoint / skip / restart / leave
       └─ Records → speed and level boards
Fight → countdown → active HUD / alerts / ultimate / KO → results podium → room or bazaar
```

The client entry point in Studio is `Players.<local player>.PlayerScripts.Client`. It creates or requires all surfaces below. `Canvas2D` renders the world into `Blockfall.World`; most text and controls live in separate `ScreenGui`s. Studio has a Client and Server play DataModel. I checked the live `PlayerGui` and captured the bazaar, character studio, pick screen, map vote, and fight HUD. I did not claim every possible state was seen live; the rest is mapped from the Studio scripts.

## Complete live screen and HUD inventory

| Surface / distinct states | Current content and behavior | Live Studio source | Proposed improvement |
|---|---|---|---|
| Bazaar world and wayfinding | Skyhold Bazaar title, district reveal, directions, floating island market, stalls, giant billboard, arcade cabinets, 2v2/3v3 gates, tailor, climb, record board, other players and name tags. Movement keycaps and proximity `USE` prompt. `CHARACTER` quick access. | `Plaza2D`, `PlazaArt`, `RealmArt`, `Shared.Data.Plaza`, `Shared.Plaza`, `Ui` | Preserve the world and art. Make the current district, nearest destination and the active interaction easier to read without obscuring the fighter or stalls. |
| Bazaar social | Bottom key buttons `STAMP`, `SAY`, `PEOPLE`, `MAP`; eight stamps, fourteen fixed quick messages, room member list with warp-to-player where possible, five map warp destinations, small six-line activity log; stamp or speech bubble over players. | `LobbySocial`, `Plaza2D.drawOverhead` | Give each panel a consistent heading, visible close/back, and status on unavailable warps. Keep the social bar below gameplay. |
| Character Studio | Full-screen modal with fighter slots, add slot, undo/redo, random, close; live fighter preview in stand/run/jump/attack/cheer, turn/face zoom; editable name; groups Presets, Body, Face, Hair, Outfit, Extras; category tabs, option tiles, colour swatches, lock/random part; save as new, save & wear, delete, and unsaved-change confirmation. Session-only saving is explicitly stated. | `AvatarEditor`, `AvatarKit`, `KitPortrait`, `Ui` | Keep the generous preview and part grid. Raise the selected part and save state, make the session-only message impossible to miss, and separate destructive confirmation from ordinary controls. |
| Arcade cabinet and watching | Eight paired 1v1 cabinets, seat/stand/VS CPU/watch intents. A spectator sees match render with a `STOP WATCHING` button. | `Plaza2D.seatStation`, `cabinetIntent`, `Client` `CabinetAction`, `BlockfallWatching` | Use a compact cabinet status card showing seats, opponent, and available action. Keep spectator exit visible throughout. |
| Walkable lounge | Private room world after 1v1/2v2/3v3 gate; room status line shows ready humans, CPUs, map and rules. Stairway returns to bazaar. Map/weapon/rules/player stations can reopen selection; `ROOM ▲` reopens from hidden select. | `Plaza2D.setRoom`, `loungeItems`, `SelectScreen.minimise` | Keep the lounge navigable. Put a small persistent phase/room badge beside `ROOM ▲` so hiding does not hide an imminent vote. |
| Room pick phase | Dusk sky, round weapon portraits (12), fighter on each team pedestal, green/orange team cards, weapon role/difficulty and four stat bars, empty slot with bot difficulty, add/remove bot vote, `READY`, `LEAVE`, `HIDE`, room rule summary and phase countdown. At first entry the screen opens automatically. | `SelectScreen` `Pagepick`, `Shared.Rooms`, `WeaponStats` | Keep the signature roster and pedestals. Enlarge weapon identity and label one player's own pedestal unmistakably. Show ready/bot ballot feedback close to the action. |
| Map vote | Nine named realm thumbnails plus Random, vote counts, one's gold selection, voter chips, countdown. Most votes wins; tie random. | `SelectScreen` `Pagemap`, `Stage2D`, `Realms` | Preserve the actual map art. Strengthen map names at smaller sizes and show vote state and remaining seconds in one scan path. |
| Rules vote | Four large cards: Tournament 1v1, Casual, Chaos and Keep Current; each shows win condition, items, disasters, vote total and selected border, plus voter chips and clock. | `SelectScreen` `Pagerules`, `Shared.Data.Rules` | Use a compact comparison grid; highlight the changed rule facts when a card is chosen. |
| Room board panels | `RoomPanel` offers Maps (host/vote/random and all/ranked set), Weapons (12 with art and role), Rules (presets, stock/timed, lives/time, items, disasters, bot slots), Players (team roster, Ready, host Start), plus a small waiting/error notice. These remain in the Studio scripts though station interactions currently route most room stations to `SelectScreen`. | `RoomPanel`, `StageThumb`, `Weapons2D`; `Client` station dispatch | Treat boards as secondary configuration views, avoiding duplication with the main select. Show who may edit each control and when a choice is awaiting server confirmation. |
| Join/loading/failure | Room and match requests use the smaller `RoomPanel.Notice`: blue `GET READY` without button while waiting, red `HOLD ON` with OK for a problem. Timeout requests rejoin. | `RoomPanel.say`, `Client` `Select`/`Match`/launch timeout | Preserve the small, contextual notice. Give the player the room and exact next step; never invent percentage progress. |
| Skyline Climb | Dedicated course and HUD: checkpoint, timer, falls, furthest progress, brief banners, controls, records, leave, conditional restart and optional paid skip; a purchase prompt pauses the course. | `ParkourView`, `Shared.Data` course and progress, `Client` Climb remotes | Give checkpoint/time/falls a compact stable cluster and separate paid skip from restart. Show current vs best clearly. |
| Climb Records | Two ranked boards (speed and level), local player's record, status and close. | `ClimbRecords` | Preserve both rankings; improve the current-player anchor and empty/loading states. |
| Match opening | Stage name callout, countdown and GO, combo guide through countdown. | `Hud`, `FightScene`, `Callouts`, `ComboGuide` | Let the stage and fighters remain visible. Keep the countdown central and the guide lower priority. |
| Active match HUD | Per-fighter bottom tiles with team/player band and shape, name, weapon, big damage %, stock blocks, 10-block ultimate, local shield status; floating mark+percent over live fighters; top timed-mode clock (hidden in stock), key hints, ready/denied ultimate pill. | `Hud`, `HudColors`, `AbilityStatus`, `Bindings` | Preserve percent as the biggest value and gold local outline. Increase separation of meter and shield text; allow six-player layouts to retain identity. |
| Fight events | Combo hits/damage, perfect/finisher, break cooldown and `DODGE!` prompt, disaster warning/impact, sudden death and low clock, KO/GAME callouts, ultimate cinematic name/caster. Eliminated tiles dim. | `Hud`, `ComboHud`, `DisasterShapes`, `UltCinematic`, `UltBanner` | Use one clear priority order so disaster, combo, ultimate and countdown text do not compete. Keep urgent status close to the related fighter when possible. |
| Results | Full-screen dusk podium with stepped pillars, posed fighters, rank cards and stats, winner title, `SAY GG!` button and brief bubble. Remains until next match; next room view brings pick screen back. | `PodiumView`, `Podium`, `Hud.showResults`, `Client` | Keep the podium as the emotional end state. Add a small, honest return cue while preserving the automated server flow. |
| Developer overlay | F3 toggles frame, interpolation, connection and server stats on `Blockfall.PerfOverlay`. | `Client`, `PerfMonitor` | Document only; no player-facing redesign needed. |

## Shared design rules for implementation

- **Keep the live identity.** Use the current `Ui` colour and type tokens as the source: gold for the primary decision, green for a confirmed ready state, red for leave/error, blue for ordinary navigation, navy with a heavy ink edge for cards, and a bright sky for the bazaar. The dusk sky belongs to room voting and results. Replace the mockup's schematic fighter and terrain with the live game's art.
- **Give each phase one lead action.** Bazaar leads with proximity `USE`; the studio leads with Save/Wear; room pick leads with Ready; votes lead with the selected ballot and clock; climb leads with checkpoint/time; combat leads with damage and stocks. The smaller secondary controls should not compete with those calls.
- **Explain actual room state.** Put the phase, seconds left, roster readiness and whether the server accepted a selection in fixed places. A proposed bot is a ballot; a pending join is a waiting notice; an error names a route back to the room. Do not show fake loading percentages or imply an unconfirmed vote succeeded.
- **Keep six fighters identifiable.** Match tiles need team colour *and* shape, short names, readable percent, stock, and a local gold marker. The mockup's 2v2/3v3 selector previews the larger pick, HUD and podium states. The narrow preview stacks six HUD tiles in two rows.
- **Respect session limits.** Character Studio must say that saves last only until leaving while persistence is disabled. Paid climb skip needs a distinct purchase action. Spectator mode needs a persistent exit and no local combat prompts.

## Mockup grading and revisions

[Open the interactive mockup](../mockups/blockfall-live-ui.html). It contains 23 selectable views and a 1v1/2v2/3v3 selector. It uses drawn stand-ins for fighters and scenes; it is a design proposal, not a Roblox build or a saved character. Scores below are my **provisional design assessment** of theme fit, information hierarchy, state accuracy and coverage, each out of 10. I could compare against the live Studio captures and inspect the HTML/JS structure, but the browser denied local-file preview, so these scores do not certify final rendered spacing or legibility.

| View family | First pass | After revision 1 | Final after revision 2 | Reason for final score |
|---|---:|---:|---:|---|
| Bazaar and social panels | 7.8 | 7.8 | **8.1** | Current sky bazaar vocabulary and exact five warp destinations; panel actions remain examples. |
| Character Studio and unsaved confirmation | 7.0 | 7.8 | **7.8** | Six real groups and categories can be switched; explicit session-only saving. Option art remains schematic. |
| Arcade and spectating | 6.8 | 7.6 | **7.8** | Cabinet actions and persistent exit; spectator no longer displays local ability prompts. |
| Walkable room and secondary boards | 7.6 | 7.6 | **7.6** | Room phase stays visible while select is hidden; server permission copy is present. |
| Pick, ready and bot ballot | 6.9 | 7.8 | **8.0** | Twelve weapons, pedestals and 2/4/6 slot layouts; bot vote stays separate from Ready. |
| Map and rules voting | 7.8 | 7.8 | **7.8** | Nine live map names plus Random and four rule choices with selection and clock. Thumbnail art is schematic. |
| Join/loading/error notice | 7.1 | 7.1 | **7.7** | Waiting and error are distinct; waiting no longer shows an acknowledgement action. |
| Climb and records | 7.6 | 7.6 | **7.6** | Course HUD, restart, paid skip and two records boards are covered. |
| Fight opening, active, event and ultimate | 6.9 | 7.4 | **7.7** | Final pass adds 2/4/6 fighter HUD counts and a narrow six-tile layout. Effects remain diagrammatic. |
| Results podium | 6.8 | 7.6 | **7.7** | Final pass shows 2/4/6 finish slots and server-driven return cue. |

The first revision repaired the spectator, larger room, podium and Studio group gaps. The second repaired six-fighter combat, live destination names and notice behavior. No family scored below 5; all reached at least 7.5 within two revisions, so I stopped. Browser rendering in the desktop app remains unverified and should be reviewed before implementation.

## Source mismatch and implementation handoff

The current local checkout cannot safely receive UI implementation from this audit because it does not contain the Studio version of the modules listed above. When implementation is requested, first bring the live place's source into a versioned repository or identify its matching Git revision, then follow the repository's JS/Luau parity rule where shared behavior changes. This audit does not edit `roblox/src` or generated data.
