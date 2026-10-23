# Maps (arcade direction), round 2

Same owner's request, rubric, weights and bands as `maps-round1.md` (read it first). Round 1 scored
5.6 and 5.8 ("getting better, not good enough"); summary in `maps-round1-review.md`. Two independent
Claude reviewers each round. Score fresh; do not grade the change.

## What changed since round 1 (`git log -1` on `feature/map-arcade`)

- **Value order.** Everything behind the fight goes through `RealmArt.backdrop`: hazed toward the
  realm's mid sky (half way from `far` to `sky[1]`, not the pale horizon `sky[3]`), and never lighter
  than the island's lit rock `rock[4]` (`tests/map-values` holds it on every realm). That covers the
  landmarks and the far ridge. The far ridge is one flat tone (its lit edge cost the warm-up budget).
- **Rock palettes** (`roblox/src/shared/Realms.luau`, `rock`): each realm its own saturated hue (warm
  stone, jade, sandstone, violet, rust...). The dark realms' rock is lifted above their skies.
- **Rock body** (`RealmArt.island`): three courses under the lit band, 3-6 rows deep, seams in the
  soft tone (`R[2]`, not the dark `R[1]`). Joints only in the top course (in all three, the warm-up
  went over budget). Plain rock below, into the belly and lip.
- **The rock's lit band at full density**: drawn in the walking surface's sprite (`RealmArt.surface`)
  at the fighters' pixel size. The body stays at half density: at full density the fight's first
  frame went over its build budget (1,061 rectangles for the worst stage against 800), and budgets
  only tighten.
- **No near floating islands** (`layer("near")` is empty): drawn as islands they read as platforms at
  play height; as silhouettes they hung behind high platforms. **Clouds** placed per realm and above
  the fight's band.
- **Camera**: room for the HUD's top band (clock and key hints, 92 px at 720) as well as the cards.
  A spread fight zooms out about 15% more for it; a close fight does not change.
- **Smeltworks' vent grates** have a shine along their top.

## How to look at it

`.renders/maps-r2/`: `<Stage>-wide.png`, `<Stage>-fight.png` (fight camera, HUD over it, 1280x720);
`R1-*` are round 1's shots; references `REF-*.png`. SVG sources beside the PNGs.

## Claims to verify

1. Nothing behind the fight is lighter than the island's lit rock, on any realm.
2. Every walking surface and platform top separates from what is behind it by at least 3:1.
3. No fighter in the fight shots is behind any part of the HUD.

## What I am least sure about

- The rock body may now read too plain under its band: courses at soft contrast.
- The body is still half density against full-density surfaces and fighters (the budget's call).
- The fight shots are zoomed out further (a spread brawl, plus the top band): fighters are small.
- Dark realms (Ashfall, Smeltworks, FreightLift): is the island now a clear step above the sky?

## What to return

Scores per area and overall; which round 1 findings are fixed and which are not; issues ranked by
how much fixing each would raise the score, with stage, measurement and a concrete fix (name the
function); what works. Be blunt.
