# UI rework (arcade direction), round 5

Same rules, rubric and bands as round 1 (`ui-arcade-round1.md`: the owner's request, the two
references, the rubric). Earlier scores: round 1 4.8; round 2 5.6; round 3 5.9 and 6.2; round 4 6.35 (Claude) and 7.0
(Codex). Summaries in `ui-arcade-round{1,2,3,4}-review.md`. Score fresh; do not grade the change.

## What changed since round 4 (`git log -1` on `feature/ui-arcade` has the detail)

Social panels open above the square buttons' real height; secondary lines on pale rarity faces are
bare in the face's deep shade; one selected face (gold, dark words) everywhere; Shop section tabs;
Locker four columns, more space between its buttons, crate cards to content, SAVE/VIP right-aligned;
select YOU/P2 badges white outlined, vote timer dark; Studio key hints dark and bare; plaza tip in the
main text colour; climb timer white.

## How to look at it

`.renders/round5/*.png` (true fonts, headless Chrome, each screen's own size) with SVG sources beside
them; references as `REF-*.png`. Pale empty boxes are runtime art and fighters, not drawn by the tool.

## Claims to verify

1. No text overlaps or is cut off on any screen, phones included (a list cut at a scrolling area's
   own edge is the scroll).
2. Every word meets its surface's rule.
3. One selected treatment across the screens.

## What I am least sure about

- The select fighter's raised sword still crosses the roster (fighters are sprite frames over the
  canvas; shrinking them would break the 20%-of-screen legibility rule the select test holds).
- Locker cards are still three lines and two buttons; Records still has empty list space.
- No card pattern, no stepped pixel corners; phone billboard lettering is world art, not UI.

## What to return

Scores per area and overall; which round 3 findings are fixed / not; issues ranked by impact with
measurements and fixes; what works. Be blunt.
