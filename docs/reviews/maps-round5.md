# Maps (arcade direction), round 5

Same owner's request, rubric, weights and bands as `maps-round1.md`. Earlier: 5.6 / 5.8, 6.2 / 5.95,
6.05 / 6.10, 6.0 / 6.10 (`maps-round{1..4}-review.md`). Two independent Claude reviewers. Score fresh.

## What changed since round 4 (`git log -1` on `feature/map-arcade`)

- **Landmarks keep their own shading** (`RealmArt.landmarkMap`): a landmark's colours are collected
  first and mapped as a set - their luminance order spread back over a band (on a daylight realm from
  the day floor up 0.28; on a dark realm from 60% of the ceiling to it), hue and saturation kept. Hazed
  colour by colour, round 4's tones all landed on one value. `tests/map-values` now also fails a landmark
  whose tones span under 1.2:1.
- **Daylight distance**: leans toward the horizon's hue (30%), and may keep up to half the sky's
  saturation (it was capped at 0.6x a dull rock). It must also clear the walking face and the lit band
  by 1.2:1 (`RealmArt.dayFloor`), not only the rock body by 1.5:1 - both tested.
- **Dark realms**: background no darker than 85% of its ceiling (a black suit stood on L 0.022).
- **Suns**: daylight suns hazed toward their own glow (toward the sky they read as a grey-blue moon) and
  clouds hazed half way on daylight realms, so the sun is the lightest thing in its sky; dark-realm moons
  hazed a little toward their sky. FreightLift's moon moved out from behind the timer.
- **Accents**: the crater rim drawn in the lava's orange (a darkened pale yellow went olive); each crystal
  has a glowing facet edge.
- **Lava seams** redrawn, a pixel wide, over the full-density courses (round 4 painted over them).
- **Daylight platforms** stand 3:1 against the sky a quarter of the way up from `sky[2]` toward its top
  (against `sky[2]` alone the high ones read 2.2:1; against the top itself wood went near-black).

## How to look at it

`.renders/maps-r5/`: `<Stage>-wide.png`, `<Stage>-fight.png` (close), `<Stage>-spread.png`; `R4-*`
round 4's; references `REF-*.png`. SVG sources beside them.

## Claims to verify

1. Every landmark's tones span at least 1.2:1, and no daylight scenery sits within 1.2:1 of the
   walking face or the lit band.
2. The sun is the lightest thing in each daylight sky.
3. Ashfall's and Smeltworks' glowing seams show on their walls.

## What I am least sure about

- Saltflat's pyramid now very pale (its sand is pale, so its scenery must be paler still).
- The belly is still half density; the courses are at the surface's density, not the fighters' finer
  kit pixel.
- Dark outfits on dark realms remain weak (the maps alone cannot give 3:1 against near-black).
- Platforms above the fight can still sit under the top HUD in close shots (declared, see round 4).

## What to return

Scores per area and overall; which round 4 findings are fixed and which are not; issues ranked by
impact with stage, measurement and a concrete fix (name the function); what works. Be blunt.
