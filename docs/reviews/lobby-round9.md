# Lobby (arcade direction), round 9

Same owner's request, rubric, weights and bands as `lobby-round1.md`. Earlier: 5.65 / 5.55, 6.41,
6.67, 6.84, 7.08, 7.26, 7.31, 7.35 (`lobby-round{1..8}-review.md`). One reviewer. Score fresh.

## What changed since round 8 (`git log -1` on `feature/lobby-arcade`)

- **The lounge's wall is a rooftop terrace's** (`PlazaArt.loungeWall`): plaster in courses of panels
  (one flat colour was 53% of the band behind the stations), a striped awning parapet for its top (it
  read as an interior cornice), and in each window a far island and a cloud, so it looks out from high
  up. Its skirting is a mid indigo: ink outlines read on it at 2:1 or better (1.47:1). The pink couch
  stands clear of the stairs' door.
- **Windows between the stations' edges**, each half a stud or more from any station's art, none where
  the gap is narrower than a window (`Plaza2D.stationHalf`; one stood 3 px from the weapon rack).
- **The arcade's bunting**: every pennant drawn, both strands running to their ends at the marquee,
  kept apart (`PlazaArt.bunting`; every other pennant, strands stopping short, the sides 90% sky).
- **One pennant**, shared by the bunting and the wall (they were drawn two ways).
- **The marquee's fighters** wear helmets and hold swords with crossguards.
- **A slid sign drops under any sign it meets** (NOTICE BOARD's covered the MASKS awning on the phone).

Not changed: the arcade's two rows share an x (web data: the owner's call); the billboard's lettering
hides whole at an edge.

## How to look at it

`.renders/lobby-r9/`: the eleven shots; `R8-*` round 8's; references `REF-*.png`. SVG sources beside
the PNGs.

## Claims to verify

1. The lounge reads as a rooftop terrace, and every prop against its wall keeps 2:1 or better at its
   outline.
2. The arcade's side thirds are mostly pennants, not sky, between the title and the canopy.
3. On the phone no two signs meet, and every station on screen has its name.

## What I am least sure about

- The bunting may now be too busy.
- The wall's awning beside the title card.
- The arcade's rows (above).

## What to return

Scores per area and the weighted overall with its band; a verdict on each claim with measurements;
which of round 8's findings are fixed; issues ranked by how much fixing each would raise the score,
each measured, with a concrete fix (name the function); what works. Be blunt.
