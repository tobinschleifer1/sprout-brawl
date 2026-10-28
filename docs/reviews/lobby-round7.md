# Lobby (arcade direction), round 7

Same owner's request, rubric, weights and bands as `lobby-round1.md`. Earlier: 5.65 / 5.55, 6.41,
6.67, 6.84, 7.08, 7.26 (`lobby-round{1..6}-review.md`). One reviewer. Score fresh.

## What changed since round 6 (`git log -1` on `feature/lobby-arcade`)

- **The lounge is a room**: a back wall behind its stations (`PlazaArt.loungeWall`) - a kit wall with
  ink top, light band, deep indigo face and dark lip, six tall windows onto the sky, and pennants in
  the stations' colours along its top. Its upper fifth was empty sky.
- **The arcade's marquee** is an arcade's: a stepped crown over the board, chase bulbs all round, two
  pixel fighters squaring up either side of 1v1 CABINETS (`PlazaArt.arcadeMarquee`), and strings of
  pennants from its corners out along the canopy (`PlazaArt.bunting`). Round 6's was a flat slab, 51%
  one indigo, copying the square's billboard. Both new pieces are cached sprites (one draw each).
- **Name tags stagger** in a crowd: one whose words meet another's rises a row (`Plaza2D.clearTags`).
- **Whole cards at the edges**: a sign shows only with its whole card on screen (`Plaza2D.clearEdges`;
  NOTICE BOARD lost its left frame).
- **The wardrobe's sign** stands on the awning, 16 px or more under the district title
  (`Plaza2D.BANNER_CLEAR`; it was 9 px).
- **Your reflection** in the tailor's mirror is behind glass at 0.4 (`Plaza2D.MIRROR_GLASS`): at 0.1 it
  read as a second player in the doorway.
- The 3v3 lounge render is a 3v3 room (six places, 2/4 ready).

Not changed: the arcade's two rows share an x (web data: the owner's call); the billboard is still
hidden whole when it would be cut at an edge.

## How to look at it

`.renders/lobby-r7/`: the eleven shots; `R6-*` round 6's; references `REF-*.png`. SVG sources beside
the PNGs.

## Claims to verify

1. The lounge has no band of empty sky over its stations: its wall fills it, in the kit's anatomy.
2. The arcade's marquee reads as an arcade's, not the square's billboard, and no band of the arcade's
   sky is more than half empty.
3. In the crowd shots no two name tags' words overlap.

## What I am least sure about

- The lounge's wall may be heavy - a big indigo mass behind bright stations.
- The bunting may be busy.
- The arcade's rows (above).

## What to return

Scores per area and the weighted overall with its band; a verdict on each claim with measurements;
which of round 6's findings are fixed; issues ranked by how much fixing each would raise the score,
each measured, with a concrete fix (name the function); what works. Be blunt.
