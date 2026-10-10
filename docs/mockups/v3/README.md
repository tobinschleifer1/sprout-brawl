# Study 03 — pixel platform fighter

## Interactive preview — 7 October

[Open the interactive GUI](index.html). Uses the new pixel artwork with keyboard-accessible controls and local state. The six-screen flow covers selection → map ballot → rules ballot → combat state examples → results, plus bazaar and character settings. Includes bot ballot, social panels, arcade watching, climb panels, damage/stocks/ultimate controls, editing undo/redo, part lock, and an unsaved-change prompt. Use **Show click targets** to discover controls.

Open `index.html` directly in a browser; no server or package installation is needed. Keep `prototype.js`, `prototype.css`, and the PNGs beside it. On narrow screens the desktop mockup scrolls horizontally; this is not a finalized mobile layout.

The artwork is static: changing a weapon updates source-backed stats, and editing changes local selection state, but neither re-renders the illustrated fighter. Poses, turn and zoom are documented preview controls rather than animation. Session data resets on reload. The six-screen art preview links to the earlier 33-state functional study for wider layout coverage.

Checked JavaScript syntax and local state transitions for selection, ballot flow, stock clamping, ultimate charge/use, undo/redo, locks, unsaved navigation and all six screen renders. Browser visual verification remains outstanding; the earlier browser preview was denied by the browser URL security policy. No gameplay modules changed.

This visual revision responds to the user's rejection of Study 02's panel-heavy appearance. **Previous style scores are withdrawn.** The live Studio UI and the user's pixel, Brawlhalla-like platform fighter direction are the references. The outdated design brief is not a source.

## Mockups

- [Weapon selection](weapon-select.png): large opposing fighters, live twelve-weapon roster, floating platforms, compact stats, primary Ready action.
- [Combat](combat.png): arena-first composition, percent damage, stocks and separate ultimate meters.
- [Character Studio, second revision](character-studio.png): full editor controls restored; [review](STUDIO-REVISION.md).
- [Four menu families](menu-families.png): daytime bazaar, Character Studio, arena vote, results podium.
- [Generation prompts and method](PROMPTS.md).

These are raster art-direction proposals. They do not change Roblox, replace its avatar renderer, or prove working interaction. The original [source inventory](../../reviews/roblox-ui-map-2026-10-05.md) and Study 02's 33 functional states remain the behavior reference. Six principal screens have a new visual treatment here; the remaining states inherit the rules below and still need final individual visual proofs.

## What changes visually

1. Fighters and the world establish the screen; controls sit around them. Preserve custom human avatars and weapon silhouettes, rather than introduce unrelated fantasy classes.
2. Use intentionally clustered pixel shading, strong silhouette outlines, stepped frame corners and small bevels. Export at a consistent pixel density with nearest-neighbor scaling; generated images themselves are not production sprites.
3. Keep bright sky-market scenery for the bazaar, subdued blue scenery for selection and warm dusk for the podium. Combat backgrounds need lower contrast and detail than these concept images.
4. Large outlined arcade headings belong on selection and results. During combat, percentage damage is the dominant text.
5. Gold marks the local selection or primary action. Confirmed Ready becomes green. Team identity uses shape plus color, not color alone.

## Remaining states: treatment and implementation requirements

| Family | Apply this visual treatment | Required states retained |
|---|---|---|
| Social | Small pixel-framed tray above bazaar footer; keep world visible | Eight stamps, fourteen actual messages, people/warp availability, five destinations, close |
| Arcade / watch | Context prompt attached to cabinet; compact navy seat card | Sit, stand, CPU, watch; persistent Stop Watching in spectator HUD |
| Walkable lounge | Reuse bazaar world language with team banners | Phase badge and Room reopen button; hide, leave, pending vote |
| Character Studio | Tailor backdrop, large preview and compact part grid | Presets plus five groups; actual categories, slots, name, undo/redo, locks, poses, turn, zoom, delete and unsaved confirmation; session-only saving |
| Pick / ready | Selection illustration structure with scalable team platforms | 1v1, 2v2, 3v3; own marker, role/difficulty, open slot, bot difficulty/proposal/ballot, confirmed Ready, Leave and Hide |
| Map vote | Pixel map previews with shared navy label strips | Nine real maps plus Random, selected ballot, voter identity/count, timer, tie behavior |
| Rules vote | Four compact arcade plaques over subdued selection sky | Tournament 1v1, Casual, Chaos, Keep Current; actual settings, counts and timer |
| Secondary room boards | Same frame kit; keep navigation subordinate | Maps, Weapons, Rules, Players; host permissions, pending server response |
| Notices | Small centered pixel-framed notice; world dimmed | Waiting without fake progress; actionable error with acknowledgement |
| Climb / records | Sparse combat-like HUD over actual climb course | Checkpoint, time, falls, best, restart, leave, distinct paid skip; speed/level rankings, local player, empty/loading |
| Fight overlays | Short bold pixel lettering; protect fighters and ledges | Countdown/GO, stage title, combo, dodge, disaster, ultimate, sudden death, KO/GAME, eliminated and spectator states |
| Results | Posed avatars on stepped islands, compact actual results | 2/4/6 participants; accurate ranking/stats, GG feedback and actual server return status |
| Developer | Existing developer overlay | F3 only; no decorative redesign required |

## Self-review

Weights: pixel fighter/theme fit 40%, visual hierarchy 25%, behavior fidelity 25%, small-screen adaptability 10%. Scores are design judgment, not user approval or usability-test results. Previous pass is reassessed at **4/10 for theme fit**, triggering this revision under the requested below-5 rule.

| New concept | Theme | Hierarchy | Fidelity | Adaptability | Weighted score |
|---|---:|---:|---:|---:|---:|
| Weapon selection | 8.5 | 8 | 6.5 | 6 | 7.7 |
| Combat | 8 | 7.5 | 7 | 6 | 7.5 |
| Bazaar | 8.5 | 8 | 7 | 6 | 7.8 |
| Character Studio | 8 | 8 | 6.5 | 6 | 7.4 |
| Arena vote | 8 | 8 | 8 | 6 | 7.8 |
| Results | 8.5 | 8 | 7.5 | 6 | 7.9 |

Style now reads as a pixel platform fighter. The first Character Studio image scored 7.4 because it omitted editing controls. The [second revision](STUDIO-REVISION.md) restores these and scores 7.7; it supersedes the editor quadrant in the board. Mobile and six-player proofs remain outstanding for this art direction.

## Corrections needed before implementation

- Generated selection has two heart icons beside '3 stocks'; remove those icons or render three real stock indicators. Use source stats, not generated bar counts: Sword 6/6/7/6 and Scythe 6/6/6/5, on ten-block scales. Retain role and difficulty, Hide, and vote-controlled bot actions from live source.
- Generated weapons and poses are illustrative, not replacements for the exact twelve live weapon assets. Any avatar silhouette/animation change is a separate art implementation decision.
- Combat fighters are larger than requested and background detail competes with action. Preserve actual camera scale, collisions and stage geometry; reduce background contrast. Use the live ten-block ultimate meter and shield/ability status. The sample clock denotes timed mode; hide it for stock mode as live logic does.
- Character Studio must include Presets, Close, slot/name controls, undo/redo, part locks and selected option labels. Hair/color examples must be replaced by real AvatarKit options. It is not a complete editor specification by itself.
- Voting and results text/stats are examples; render actual server values. 'Returning to room' appears only when that transition is genuinely pending.
- These images suggest richer background art. Do not silently replace existing levels or alter mechanics to match an illustration.

No gameplay code changed. Images were visually inspected; Roblox implementation, mobile interaction and performance are not verified by this pass.
