# Maps (arcade direction), round 1

Scored design review brief. Rules in `README.md` in this folder: measure everything, do not grade
effort; bands under 4.5 bad · 4.5-6.5 getting better · 6.5-8 almost there · 8-10 workable; rounds
continue until one scores above 8.

## The owner's request

> "work on map updates like the ui updates make it more similar to the ui and the characters go
> through the agent review and itterations with the same scoring system"

The UI rework this follows (`ui-arcade-round1..9`) took the menus to the owner's two references: a
Roblox simulator shop (big rounded windows, saturated cards, white outlined names) and a pixel UI kit
(buttons outlined in a darker shade of their own colour, a light band across the top, a dark lip
below; pixel lettering). It ended at 8.08 (Codex) and 7.6 (Claude). Blockfall is a 2D pixel-art
platform fighter on Roblox; its fighters are pixel sprites with ink outlines and two or three tones of
shading. The maps are nine floating-island stages, each dressed as a realm (Viking harbour, desert,
forge, pagoda garden, crystal mine...).

## What the maps are, in code

`roblox/src/client/RealmArt.luau` draws everything: `RealmArt.island` (the solid ground's rock body),
`RealmArt.surface` (its walking surface), `RealmArt.shelf` (drop-through platforms), and the sky
layers (`layer`: far ridge, landmark, near islands, clouds). Colours per realm are in
`roblox/src/client/Realms.luau`. The art only dresses the Stage's geometry; it never moves it, and it
is budgeted (`tests/perf-budget`, `tests/realms`): budgets may only be tightened.

## What changed this round (`git log -1` on `feature/map-arcade`)

- **Islands**: a one-pixel shine along the top, a lit band under the surface, rock in two-tone strata
  courses with a dark seam under each, a mid-dark step into a dark belly, a lit left and dark right
  edge, an ink rim (unchanged). The scattered dark cracks and lit stones are gone (the lava realms keep
  their glowing seams).
- **Walking surfaces**: the top row lit nearly to white (the UI's light band).
- **Platforms**: at least 6 rows (iron girders excepted), a shine and a light band on top, a dark lip
  under.
- **Landmarks** (Foundry's hall, the pyramid, the pagoda, the crystals...) hazed 40% toward the sky.
- **The fight camera now frames the fight clear of the HUD's player cards** (it never did: the
  setting existed and nothing set it). Not art, but it changes what the fight shots show.

## How to look at it

`.renders/maps-r1/`: `<Stage>-wide.png` is the whole map (a fixed wide camera, two fighters standing
on it); `<Stage>-fight.png` is the fight camera mid-brawl with the real HUD over it, at 1280 x 720.
`BEFORE-<Stage>-wide.png` is round 0. References: `REF-pixel-kit.png`, `REF-simulator-shop.png`, and
the finished UI: `REF-ui-shop.png`, `REF-ui-select-pick.png`, `REF-ui-hud-fight.png`,
`REF-ui-results.png`, `REF-ui-locker.png`. SVG sources beside the PNGs give exact colours.

## Rubric (score each 0-10, then the weighted overall)

| Area | Weight | What a 10 is |
|---|---|---|
| Faithful to the UI and the characters | 25% | Someone who has seen the menus and the fighters sees the same hand in the maps: the same outline, band-and-lip anatomy, palette discipline and pixel density |
| Fits Blockfall | 20% | Each realm reads as its place, and the set reads as one fighting game's worlds |
| Readability of play | 20% | Where you can stand is seen first: islands and platforms separate from the background at a glance, the fighters stay readable on every surface, the HUD never hides the fight |
| Consistency | 15% | The nine maps are one language; the same parts (rock, surface, platform, ledge, background) look like the same parts |
| Hierarchy and composition | 20% | Foreground, play space and background layered with clear depth; nothing in the background competes with the fight; no awkward overlaps |

## Claims to verify

1. Every walking surface and platform separates from what is behind it by at least 3:1 luminance
   contrast along its top edge.
2. No landmark or background layer is brighter or more saturated than the island the fight is on.
3. The fight camera never puts a fighter standing on the stage behind the HUD's cards.

## What I am least sure about

- The strata read as regular horizontal stripes: rock, or bricks, or wood?
- The landmarks may now be too faded on some realms, or still too strong on others (Foundry's hall).
- The near floating islands in the sky have no outline and no strata: a second language?
- Platform styles differ a lot by realm (planks, red temple, iron girder, crystal).

## What to return

Scores per area and overall; issues ranked by how much fixing each would raise the score, each with
the stage, what is wrong (measured where it can be) and a concrete fix (name the RealmArt function);
what works. Be blunt.
