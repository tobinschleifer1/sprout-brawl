# Maps (arcade direction), round 6

Same owner's request, rubric, weights and bands as `maps-round1.md`. Earlier: 5.6 / 5.8, 6.2 / 5.95,
6.05 / 6.10, 6.0 / 6.10, 6.08 / 6.25 (`maps-round{1..5}-review.md`). Two independent Claude reviewers.
Score fresh.

## What changed since round 5 (`git log -1` on `feature/map-arcade`)

- **A depth ladder**: far ridge, then landmark, then island. The far ridge (`RealmArt.backdrop(..., far)`)
  now sits beyond the landmark's band - lighter than its top by day, darker than its floor at night.
  `tests/map-values` fails a far ridge not lighter than 90% of its landmark's area (day) or not darker
  than 90% of it (night).
- **Landmark tones placed by area** (`RealmArt.landmarkMap`): each colour's place in the band is its
  share of the landmark's visible area, darkest first, stretched to the band's ends - spread by
  luminance alone, a landmark of two big near tones stayed 1.05:1. Daylight band 0.2 above the day floor
  (`RealmArt.DAY_BAND`); a daylight landmark's shade side leans toward the deep sky, its lit side toward
  the horizon (a hue step as well as a value step). The span test is now by area, 10th to 90th
  percentile, at least 1.2:1.
- **Night saturation**: distance may keep up to 0.75 of the mid sky's saturation if that is more than the
  rock's (`RealmArt.distanceSat`; by day 0.5, as before).
- **Dark realms' rock lifted** (Ashfall, Smeltworks, FreightLift), giving their backgrounds more value
  room under the ceiling.
- **Undertow**: the tide's sea is also drawn behind the island (`HazardArt.back`, before the stage), so
  what shows under its belly is the water, not the sky's grey far sea. Tested: water over the island
  fails, no water behind it fails.
- **Signatures**: the rainbow's bands in their own colours (accents, 20% toward the sky); crystals glow
  along the lit ridge to the tip; Ashfall's crater rim one row with a hot core, not a 3-row bar; lava
  cracks walk jaggedly instead of straight bars; FreightLift's moon moved clear of the clouds (0.62,
  0.32); Saltflat's sand and rock warmer; palm fronds olive.

## How to look at it

`.renders/maps-r6/`: `<Stage>-wide.png`, `<Stage>-fight.png` (close, real HUD), `<Stage>-spread.png`;
`R5-*` round 5's; references `REF-*.png`. SVG sources beside the PNGs give exact colours. Never judge
from Quick Look or rsvg.

## Claims to verify

1. On every realm the far ridge, landmark and island are in depth order by value: by day the ridge is
   lighter than 90% of the landmark's area, at night darker than 90% of it; and every landmark's tones
   span at least 1.2:1 by area (10th to 90th percentile).
2. Undertow shows no grey column under its island: the colour under the belly is the tide's water.
3. TheSpan's rainbow bands are each more saturated than the sky directly behind them.

## What I am least sure about

- Daylight scenery against the near-white shine row is still about 1.0:1; only the ink rim separates it.
  Pushing the day floor over `top[3]` leaves no room to shade the landmark.
- Dark outfits on dark landmarks: by area the darkest 10% of Ashfall's landmark is L 0.046, Faultline's
  0.045 - about 1.46-1.48:1 against a black suit (L 0.015). Better than 1.12:1, not 1.5.
- The rainbow's every third row left out reads as stripes.
- Platforms under the top HUD in close shots, and the belly at half density, are unchanged (pulling the
  camera out to clear them shrinks the fighters; the belly is held by the frame budget).
- Courses still about 2.4x the fighters' pixel.

## What to return

Per-area scores, the weighted overall and its band; which of round 5's findings are fixed; issues ranked
by how much fixing each would raise the score, each measured, with a concrete fix (name the function);
what works. Be blunt.
