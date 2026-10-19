# UI rework (arcade direction), round 6

Same rules, rubric and bands as round 1 (`ui-arcade-round1.md`: the owner's request, the two
references, the rubric). Earlier scores: round 1 4.8; round 2 5.6; round 3 5.9 and 6.2; round 4 6.35 and 7.0; round 5 6.7 (Claude) and 7.4
(Codex). Summaries in `ui-arcade-round{1,2,3,4,5}-review.md`. Score fresh; do not grade the change.

## What changed since round 5 (`git log -1` on `feature/ui-arcade` has the detail)

Selected art cards wear stepped pixel corner brackets (Studio tiles, map and rules votes); words on
faces by one measured rule (secondary lines ink wherever white is under 3:1; names and titles on pale
faces ink); Locker cards one action row (WEAR plus a small gem salvage button) with taller art; select
fighters at ease, clear of the roster; Shop's current section tab selected; billboard lettering fits
its sign; phone tip fades after six seconds; 8 px between button faces; scroll chip below the grid;
one close size; notice band 40 px.

## How to look at it

`.renders/round6/*.png` (true fonts, headless Chrome, each screen's own size) with SVG sources beside
them; references as `REF-*.png`. Pale empty boxes are runtime art and fighters, not drawn by the tool.

## Claims to verify

1. No text overlaps or is cut off on any screen, phones included (a list cut at a scrolling area's
   own edge is the scroll).
2. Every word meets its surface's rule.
3. One selected treatment across the screens.

## What I am least sure about

- No faint pattern behind item art yet; windows keep rounded corners (the brackets are the stepped
  motif, on selection only).
- Crates and Records windows are still taller than their content.
- Ink names on gold, grey and green cards beside white names on blue and violet ones: one rule, two
  looks.

## What to return

Scores per area and overall; which round 3 findings are fixed / not; issues ranked by impact with
measurements and fixes; what works. Be blunt.
