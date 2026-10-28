# Lobby (arcade direction), round 8

Same owner's request, rubric, weights and bands as `lobby-round1.md`. Earlier: 5.65 / 5.55, 6.41,
6.67, 6.84, 7.08, 7.26, 7.31 (`lobby-round{1..7}-review.md`). One reviewer. Score fresh.

## What changed since round 7 (`git log -1` on `feature/lobby-arcade`)

- **The lounge's wall rises to the title card** (`Plaza2D.WALL_H` 24.5 studs; at 15 it started under
  the stations' signs and the sky over them was untouched). Its face is pale plaster, its deep indigo
  only a skirting under the couches (`PlazaArt.loungeWall`; on deep indigo the couches were 1.13:1 and
  outlines 1.77:1). Its windows stand in the gaps between the stations, not behind them (the map board
  read as one more window). Its pennants are pointed.
- **The arcade's sky**: two strands of big pointed pennants either side of the marquee
  (`PlazaArt.bunting`; one thin strand left the side thirds 95% sky). The marquee's fighters are
  outlined, two-toned and armed, as Blockfall's are (they were flat pictograms).
- **A station on screen keeps its name**: a sign over the screen's edge slides back on, 4 px in, while
  its point is on the screen (NOTICE BOARD's went whole on the phone); a cabinet's number still goes.
- **Your reflection is unarmed**: its sword reached out past the mirror at full strength.
- **Name tags** unpile over and over until none meet, and again after rising off a cabinet's number.

Not changed: the arcade's two rows share an x (web data: the owner's call); the billboard's lettering
still hides whole at an edge.

## How to look at it

`.renders/lobby-r8/`: the eleven shots; `R7-*` round 7's; references `REF-*.png`. SVG sources beside
the PNGs.

## Claims to verify

1. The lounge has no band of empty sky over its stations (within 60 px of the title card), and every
   prop in it reads against the wall (2:1 or better at its outline).
2. The arcade's side thirds are no longer mostly sky.
3. On the phone every station on screen has its name.

## What I am least sure about

- The lounge's wall may now read as an indoor room while the market is outdoors - is the lounge still
  a rooftop?
- The bunting may be busy.
- The arcade's rows (above).

## What to return

Scores per area and the weighted overall with its band; a verdict on each claim with measurements;
which of round 7's findings are fixed; issues ranked by how much fixing each would raise the score,
each measured, with a concrete fix (name the function); what works. Be blunt.
