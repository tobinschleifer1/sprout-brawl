# UI rework (arcade direction), round 3

Same rules, rubric and bands as round 1 (`ui-arcade-round1.md`: the owner's request, the two
references, the rubric). Round 1 scored 4.8, round 2 5.6 (`ui-arcade-round1-review.md`,
`ui-arcade-round2-review.md`). Score this round fresh against the rubric - do not grade the change.

## What changed since round 2 (`git log -1` on `feature/ui-arcade` has the detail)

- Render tool: 0 px text outlines were being drawn by the SVG as a default stroke; they are not any
  more, so pale buttons now render as Roblox draws them. Pale buttons use the window's dark text.
- White words on coloured faces (buttons, price pills, WORN, HUD band names) are outlined in the
  face's darker shade; HUD bands deepened; HUD cards opaque; SHIELD 12 px.
- Shop: passes three to a row, taller; cells with a pixel of slack (five-column rows no longer
  wrap); CLAIM pill with "Paid for · tap to claim" on the card; gem and key balance in the header.
- Pixel lettering (Press Start 2P) only on windows' own title bands, at one size; smaller bands
  inside windows use Fredoka.
- Secondary text #6B5A49 (was #806E5C); records' blue and green deepened; chat rendered through the
  game's own handler.
- Locker: five columns filling the grid, padded so card borders are not clipped.
- Select: long weapon names shortened (DAGGERS, FLAIL, BOOTS, HAMMER, AXE), white over the sky.
- Plaza: SHOP, LOCKER, CHARACTER are square icon buttons with pixel coin, chest and shirt icons
  (`Ui.iconButton`); the district banner is not drawn on narrow screens.
- Studio tiles have a pale gradient.

## How to look at it

`.renders/round3/*.png`: true-font renders from headless Chrome at each screen's own size; SVG
sources beside them for exact numbers; references as `REF-*.png`. Pale empty boxes are where the
game draws item art and fighters at runtime.

## Claims to verify

1. No text is cut off or overlapping on any of the 23 screens, phones included (scroll areas
   excepted: a list cut at the bottom edge of a scrolling area is the scroll).
2. Every word meets the rule for its surface, and white words on coloured faces carry an outline.
3. The plaza's icon buttons read as the reference simulator's side buttons.

## What I am least sure about

- The social bar (STAMP / SAY / PEOPLE / MAP) is still wide text buttons beside the new squares.
- The Locker cards are still dense (three lines, two buttons).
- The Studio on a phone shows a single row of tiles.
- No card pattern and no stepped pixel corners.

## What to return

Scores per area and overall; which round 2 findings are fixed and which are not; issues ranked by
impact with measurements and concrete fixes; what works. Be blunt.
