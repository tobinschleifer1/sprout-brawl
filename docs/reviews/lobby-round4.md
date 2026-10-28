# Lobby (arcade direction), round 4

Same owner's request, rubric, weights and bands as `lobby-round1.md`. Earlier: 5.65 / 5.55, 6.41,
6.67 (`lobby-round{1..3}-review.md`). One reviewer. Score fresh.

## What changed since round 3 (`git log -1` on `feature/lobby-arcade`)

- **No tip card over the roof on a wide screen** (`Plaza2D.drawScene`): the title card's directions
  now say which way things are ("East: 1v1 at the cabinets, rooms at the gates, the climb · West: your
  look at the tailor's"), so the card at the bottom is only ever an action (E + what it does). A
  narrow screen keeps its six-second tip at the bottom left.
- **Ink signs without a halo** (`Plaza2D.letterSign`): the outline on a pale face is disabled, not just
  transparent. The olive halo round SKEWERS and 1v1 OPEN ROOM in round 3 was partly the render tool:
  `tools/recorder.luau` drew a fully transparent UIStroke; it now skips one, as Roblox does.
- **The arcade**: the back row drawn at 0.8 scale as well as darker (`Plaza2D.CAB_FAR_SCALE`), its
  numbers on its own marquees; the canopy lowered over the machines (`Plaza2D.CANOPY_H`, from 15 studs
  to about 10.5), taking out the band of empty sky and posts between beam and cabinets.
- **The lounge** framed higher on its stations (`Plaza2D.LOUNGE_LIFT`): the floor under its front
  edge is about an eighth of the screen, not a quarter.

Not changed, and why: the two cabinet rows still overlap at the same x. The rows stand 4.5 studs apart
in depth (the generated plaza data, `web/src/data/plaza.js`), a cabinet is 7 studs tall, and moving
the machines in the data is a change to the web build, which is the owner's call (Roblox-only for
now). The sign gaps over station art still use hand-measured heights.

## How to look at it

`.renders/lobby-r4/`: the eleven shots; `R3-*` round 3's; references `REF-*.png`. The district title
shows for three seconds as you walk in. SVG sources beside the PNGs.

## Claims to verify

1. On a 1280 x 720 screen nothing covers people on the roof: no card sits over the walking band in
   any market or lounge shot.
2. The ink-lettered signs (SKEWERS, 1v1 OPEN ROOM) have no halo: ink on the face at 10:1 or better.
3. The arcade reads as two rows - the back row smaller and darker - under a canopy close over it.

## What I am least sure about

- The overlapping cabinet rows (above).
- The title card's directions are now a long-ish line (about 790 px).
- The lounge's sky above the stations got bigger as its floor got smaller.
- Whether the arcade's name tags over the back row's numbers crowd.

## What to return

Scores per area and the weighted overall with its band; a verdict on each claim with measurements;
which of round 3's findings are fixed; issues ranked by how much fixing each would raise the score,
each measured, with a concrete fix (name the function); what works. Be blunt.
