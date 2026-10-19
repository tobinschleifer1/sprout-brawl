# UI rework (arcade direction), round 4

Same rules, rubric and bands as round 1 (`ui-arcade-round1.md`: the owner's request, the two
references, the rubric). Earlier scores: round 1 4.8; round 2 5.6; round 3 5.9 (Claude) and 6.2
(Codex). Summaries in `ui-arcade-round{1,2,3}-review.md`. Score fresh; do not grade the change.

## What changed since round 3 (`git log -1` on `feature/ui-arcade` has the detail)

HUD cards opaque after updates too; Workshop CRAFT moved off the price, taller cells; Studio's saved
characters start after the title; the phone Shop chooses its columns by width (passes one to a row,
as tall as their perks); select status bands deepened and outlined; climb's small band in Fredoka;
repainted bands recolour their title's outline; one red X close everywhere; People status colours
deepened; the plaza and social bar are one row of square pixel-icon buttons on one grid, the hint
card above them; render tools: no 0 px outlines in select renders, Nunito Sans now loads for Builder
Sans (body text was Arial Black before), Fredoka wraps at 0.55 em.

## How to look at it

`.renders/round4/*.png` (true fonts, headless Chrome, each screen's own size) with SVG sources beside
them; references as `REF-*.png`. Pale empty boxes are runtime art and fighters, not drawn by the tool.

## Claims to verify

1. No text overlaps or is cut off on any screen, phones included (a list cut at a scrolling area's
   own edge is the scroll).
2. Every word meets its surface's rule.
3. One button language in the plaza.

## What I am least sure about

- Locker cards are still dense; Crates and Records have empty space.
- No card pattern, no stepped pixel corners, no money pill / level bar.
- The select fighter's sword still crosses the roster.

## What to return

Scores per area and overall; which round 3 findings are fixed / not; issues ranked by impact with
measurements and fixes; what works. Be blunt.
