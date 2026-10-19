# UI rework (arcade direction), round 8

Same rules, rubric and bands as round 1 (`ui-arcade-round1.md`: the owner's request, the two
references, the rubric). Earlier scores: round 1 4.8; round 2 5.6; round 3 5.9 and 6.2; round 4 6.35
and 7.0; round 5 6.7 and 7.4; round 6 6.8 and 7.6; round 7 6.9 (Claude) and 7.76 (Codex). Summaries
in `ui-arcade-round{1..7}-review.md`. Score fresh; do not grade the change.

## What changed since round 7 (`git log -1` on `feature/ui-arcade` has the detail)

- **Button spacing, everywhere, checked by a lint.** `roblox/tools/ui-lint.sh` records all 23
  screens and measures *every* pair of outlined buttons, not a named list. Pairs closer than 8 px
  between outer strokes fail (scroll-clipped parts and windows layered over others excepted), and
  it now runs in `check.sh`. Fixed by it:
  - Climb's buttons;
  - the Studio's header tools, row seams (tabs to parts to grid, poses to TURN/FACE), LOCK and
    RANDOM PART, the save pair, the slot chips and the swatches;
  - the odds window's two toggles;
  - the plaza dock (now 14 px apart);
  - select's LEAVE and HIDE;
  - Locker tabs to filters.
- **Selection:** the stepped brackets are outlined in ink (gold on cream was 1.2:1), and colour
  swatches wear small brackets instead of a gold ring. A bracketed card keeps a 3 px ring. The vote
  clock's edge is ink, not gold.
- **Phone Studio:** each palette is one row, the grid shrinks to 60 px, and nothing reaches the
  footer.
- **Phone plaza:**
  - the prompt sits bottom-left above the dock, clear of the screen's middle (your fighter) and of
    the billboard;
  - stall sign boards are wider, so their names are not shrunk to 9 px;
  - sign lettering is lightened until it reaches 4.5:1 on the board;
  - the billboard's second line is white.
- **Long names fit their box** (`Ui.fit`: TextScaled up to the label's own size): Shop and Locker
  card names, Studio tile names (inset 6 px). The render tool now draws TextScaled. WEAR IN STUDIO
  is 12 px.
- **Workshop:** cells 212 px, CRAFT clear of both the price and the card's lip.
- **Window titles** asked at 30 (drawn ~21 px, was ~17). Combo hint line shortened.

## How to look at it

`.renders/round8/*.png` (true fonts, headless Chrome, each screen's own size) with SVG sources beside
them; references `REF-*.png`. Pale boxes inside mounts and Studio tiles are runtime art and fighters.
`cd roblox && tools/ui-lint.sh` re-runs the spacing lint in a few seconds.

## Claims to verify

1. No text overlaps or is cut off on any screen, phones included (a list cut at a scrolling area's
   own edge is the scroll).
2. Outlined buttons keep at least 8 px between outer strokes on every screen.
3. "Chosen" is one mark: ink-outlined stepped brackets on cards, tiles and swatches. Tabs and toggles
   show their state by a gold face, as the pixel kit's pressed button does.

## What I am least sure about

- Tabs still use the gold face for "selected", and gold also marks "you" (your HUD card, People row).
  Should selected tabs move to another hue?
- No faint pattern on card faces; item art stays inside its well rather than breaking out of it.
- The HUD has no hearts or other pixel-kit health styling.

## What to return

Scores per area and overall; which round 7 findings are fixed and which are not; issues ranked by
impact with measurements and concrete fixes; what works. Be blunt.
