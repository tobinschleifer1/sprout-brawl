# UI rework (arcade direction), round 9 (the last round)

Same rules, rubric and bands as round 1 (`ui-arcade-round1.md`: the owner's request, the two
references, the rubric). Earlier scores: round 1 4.8; round 2 5.6; round 3 5.9 and 6.2; round 4 6.35
and 7.0; round 5 6.7 and 7.4; round 6 6.8 and 7.6; round 7 6.9 and 7.76; round 8 7.3 (Claude) and
7.94 (Codex). Summaries in `ui-arcade-round{1..8}-review.md`. Score fresh; do not grade the change.
The owner has said this is the final revision, so also say what is left for later.

## What changed since round 8 (`git log -1` on `feature/ui-arcade` has the detail)

- **Brackets**: they sit on the chosen box's own stroke (5 px beyond the face with their ink, was 9).
  Boxes that can be chosen are `Ui.CHOSEN_GAP` (16) apart: Studio tiles, swatches and slot chips,
  maps, the weapon roster where it fits. The roster's captions start below the brackets. A bracketed
  card's ring is no longer gold. The Studio's editing slot and picked tiles wear brackets only.
- **Gold for you**: the People row marks you with a 3 px ink ring on a pale row (gold was 1.0:1).
- **Small white words** on coloured faces are outlined at 2 px everywhere (dock, badges, small
  buttons, secondary lines). OWNED and WORN are ink on green. Dark secondary lines are INK, not TEXT.
- **Scroll areas**: the Shop's and Locker's lists run to the window's foot. The message is a pill
  over the list, shown only while it has something to say (it used to keep a dead 38 px strip).
- **Card grids** are Ui.GAP apart (Shop, Locker, Workshop, hero to row, crates). The lint now
  measures item cards and brackets too, and compares only boxes on the same layer (an overlay is not
  a neighbour).
- **Phone**: the gem pill is narrower, so the SHOP title is clear; tab words fit 6 px inside their
  tabs; the Studio's parts row is 8 px clear of the grid well.
- **Plaza**: stall sign boards are twice as tall; the billboard's two lines carry a full ink
  outline (the render tool now draws Roblox's legacy text stroke).
- **Select**: vote counts read "VOTES · 1"; vote chips are 12 apart.

## How to look at it

`.renders/round9/*.png` (true fonts, headless Chrome) with SVG sources beside them; references
`REF-*.png`. Pale boxes in mounts and Studio tiles are runtime art. `cd roblox && tools/ui-lint.sh`
runs the spacing lint.

## Claims to verify

1. No text overlaps or is cut off on any screen, phones included (scroll edges excepted).
2. Outlined buttons, item cards and chosen boxes' brackets keep at least 8 px from their neighbours.
3. Chosen is one mark (ink-outlined brackets); gold on a box marks you or a pressed tab, nothing else.

## What I am least sure about

- No faint pattern on card faces; item art stays inside its well; no pixel hearts on the HUD.
- Selected tabs still use the gold face.

## What to return

Scores per area and overall; which round 8 findings are fixed and which are not; issues ranked by
impact with measurements and concrete fixes; what works; and, since this is the last round, the
short list worth doing later. Be blunt.
