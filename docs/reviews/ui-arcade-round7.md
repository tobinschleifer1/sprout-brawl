# UI rework (arcade direction), round 7

Same rules, rubric and bands as round 1 (`ui-arcade-round1.md`: the owner's request, the two
references, the rubric). Earlier scores: round 1 4.8; round 2 5.6; round 3 5.9 and 6.2; round 4 6.35
and 7.0; round 5 6.7 and 7.4; round 6 6.8 (Claude) and 7.6 (Codex). Summaries in
`ui-arcade-round{1..6}-review.md`. Score fresh; do not grade the change.

## What changed since round 6 (`git log -1` on `feature/ui-arcade` has the detail)

- **A pixel motif on every card** (`Ui.mount`): each art well is a stepped pixel box - a pale tint
  of the card's colour inside a deeper edge, corners cut in two 3 px steps, no corner radius. Locker,
  Shop (hero and cells) and crate cards. Repainting a card repaints its mount.
- **Secondary lines** (`Ui.paintSecondary`): each choice measured at its worst across the card's
  gradient (white against the gradient's lightest top, ink against the base), the better one wins.
- **One "chosen" mark**: picked weapons on the select roster now wear the same stepped brackets as
  chosen vote cards and Studio tiles (the gold ring stays, at 3 px rather than 5).
- **Button gaps**: `Ui.GAP` = 14 px box to box, so 8 px between outer strokes: Locker WEAR/salvage,
  SAVE and outfit slots, filter chips; Shop tabs; Studio tabs, parts, poses and option tiles.
- **Crates**: cards fill the tab, the crate on a 280 x 190 mount, buttons at the foot.
- **Records**: the window's height follows the longer board (4 to 25 rows, up to 520 px).
- **Phone plaza**: stall names shrink to their boards; the billboard's second line #B8E0EE, shortened
  rather than shrunk below 11 px; on narrow screens the prompt sits under the title card instead of
  over your fighter; world lettering in its own layer under every HUD card.
- **Studio**: a 30 px gutter under the grid for the scroll chip, clear of the colours and footer.

## How to look at it

`.renders/round7/*.png` (true fonts, headless Chrome, each screen's own size) with SVG sources beside
them; references as `REF-*.png`. Pale boxes inside mounts and Studio tiles are where the game draws
item art and fighters at runtime; the tools do not draw them.

## Claims to verify

1. No text overlaps or is cut off on any screen, phones included (a list cut at a scrolling area's
   own edge is the scroll).
2. Neighbouring buttons keep at least 8 px between outer strokes everywhere.
3. One selected treatment across the screens (brackets), with gold reserved for "you".

## What I am least sure about

- Some mid-tone faces have no word colour reaching 4.5:1 across their whole gradient: on the kit's
  red, ink is 3.6:1 and white 2.7:1 at the top; on violet, ink is 4.1:1. Measure the rarity faces the
  cards actually use. Should those cards deepen, or is the measured best-of-two enough?
- On a phone the prompt under the title card covers the billboard's BLOCKFALL while it shows (a tip
  fades after six seconds; an action prompt stays while you stand at a station).
- Windows keep rounded corners; the stepped motif is on art wells and selection only.

## What to return

Scores per area and overall; which round 6 findings are fixed and which are not; issues ranked by
impact with measurements and concrete fixes; what works. Be blunt.
