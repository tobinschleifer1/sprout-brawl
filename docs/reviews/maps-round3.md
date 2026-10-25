# Maps (arcade direction), round 3

Same owner's request, rubric, weights and bands as `maps-round1.md`. Earlier: round 1 5.6 and 5.8,
round 2 6.2 and 5.95 (`maps-round{1,2}-review.md`). Two independent Claude reviewers. Score fresh.

## What changed since round 2 (`git log -2` on `feature/map-arcade`)

- **The floor in frame**: the camera keeps the main island's surface in view while the fight is within
  16 studs above it (`Camera2D.setFloor`, `FLOOR_REACH`); it stays above the cards (`tests/camera`).
- **`RealmArt.backdrop` keeps hue**: a light haze toward the mid sky, then saturation capped at the
  rock body's (`rock[3]`) and value lowered (hue kept) until no brighter than it. `tests/map-values`
  now checks saturation too.
- **The lit band**: drawn after the outline (no ink line under it), two rows of `rock[4]`, no shine row.
- **Rock body**: each seam one tone darker than the course it closes; lit chips along each course top.
- **Landmarks**: their distant islands are flat silhouettes (no lit top or surface colour); TheSpan's
  two flanking islands are gone; Ashfall's lava stops on the upper cone.
- **Platforms**: Ashfall's obsidian lifted (`Realms.shelfRamp`); iron girders keep their light band.
- **Rooftops' rock** is blue slate (it and the grass were one green slab).
- **Clouds** vary in size and height per realm (three each: a fourth went over the warm-up budget).
- **Renders**: two fight shots per stage now - `<Stage>-fight.png` a close exchange (frame 50 of a
  brawl, an ultimate going off: the usual view) and `<Stage>-spread.png` (frame 140, a fighter launched
  high, the camera at its widest). Round 2 showed only the spread one.

Not changed, by the budget: the rock body stays at half density (full density took the fight's first
frame over its build budget); only the lit band under the surface is at full density.

## How to look at it

`.renders/maps-r3/`: `<Stage>-wide.png`, `<Stage>-fight.png`, `<Stage>-spread.png`; `R2-*` round 2's
shots; references `REF-*.png`. SVG sources beside them.

## Claims to verify

1. Nothing behind the fight is lighter or more saturated than the island's rock body.
2. Every walking surface and platform top separates from what is behind it by at least 3:1.
3. The main floor is above the HUD cards in every fight and spread shot.

## What I am least sure about

- Sun discs and clouds are not hazed: still the brightest things on daylight realms.
- The half-density body against full-density fighters.
- Dark outfits against the darkest skies (Ashfall, FreightLift).

## What to return

Scores per area and overall; which round 2 findings are fixed and which are not; issues ranked by
impact with stage, measurement and a concrete fix (name the function); what works. Be blunt.
