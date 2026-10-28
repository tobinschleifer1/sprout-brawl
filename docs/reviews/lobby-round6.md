# Lobby (arcade direction), round 6

Same owner's request, rubric, weights and bands as `lobby-round1.md`. Earlier: 5.65 / 5.55, 6.41,
6.67, 6.84, 7.08 (`lobby-round{1..5}-review.md`). One reviewer. Score fresh.

## What changed since round 5 (`git log -1` on `feature/lobby-arcade`)

- **The arcade's sky**: a marquee board stands on the canopy's beam - an indigo kit panel ringed with
  amber and teal bulbs, a joystick at each end - carrying 1v1 CABINETS (`PlazaArt.arcadeMarquee`).
- **Cut words**: a sign is shown with all of its words on the screen or not at all, measured on the
  canvas's own width (`Plaza2D.clearEdges`; 05 and 01 read "5" and "1" at 62% on); the billboard's
  lettering likewise ("BLO").
- **A name tag over a cabinet's number rises above it** instead of hiding the number
  (`Plaza2D.clearTags`; 06 lost its number).
- **The phone**: a short screen sees a little more of the roof (46 studs tall, not 38) and frames it a
  little lower, so the walking band clears the buttons' row and the billboard's BLOCKFALL clears the
  title card (framed lower alone, BLOCKFALL went under the card).
- **The lounge's title card** carries its status alone (the stairs have their own sign), about 40% wide.

Tried and reverted: drawing the lounge's stations larger to fill its sky. The lounge's camera fits the
room's width, so larger stations made it draw everyone smaller and left the sky over the stations the
same (174 px at 0.7, 176 at 0.9). The lounge's sky is not fixed this round.

## How to look at it

`.renders/lobby-r6/`: the eleven shots; `R5-*` round 5's; references `REF-*.png`. SVG sources beside
the PNGs.

## Claims to verify

1. No sign's words are cut by a screen edge in any shot, and no name tag is drawn over a sign while the
   sign stays up.
2. On the phone the walking band clears the buttons' row and BLOCKFALL clears the title card.
3. The arcade has no band of empty sky: the marquee fills the space between the district title and the
   canopy.

## What I am least sure about

- The marquee board may be too big and too saturated against the sky.
- The phone's people are about 17% smaller than before.
- The lounge's sky; the arcade's two rows still share an x (the owner's call: web data).

## What to return

Scores per area and the weighted overall with its band; a verdict on each claim with measurements;
which of round 5's findings are fixed; issues ranked by how much fixing each would raise the score,
each measured, with a concrete fix (name the function); what works. Be blunt.
