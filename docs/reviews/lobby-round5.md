# Lobby (arcade direction), round 5

Same owner's request, rubric, weights and bands as `lobby-round1.md`. Earlier: 5.65 / 5.55, 6.41,
6.67, 6.84 (`lobby-round{1..4}-review.md`). One reviewer. Score fresh.

## What changed since round 4 (`git log -1` on `feature/lobby-arcade`)

- **The action card stands in the key hints' row** at the bottom left, under the walking band (it sat
  over the band's front 45 px); the hints step aside while it shows (`Plaza2D.drawScene`).
- **No tip card on any screen**: the phone's covered a stall and the back of the walking band. The title
  card's directions say which way things are: "East: cabinets, gates, climb · West: tailor" - short, so
  the card is about a third of the width (it was 62%, 94% on a phone).
- **The arcade's canopy low over the machines** (`Plaza2D.CANOPY_H` 52 cells): its beam within 2 studs
  of the back row's marquees (107 px of sky and posts before).
- **A name tag over a cabinet's number hides the number** (`Plaza2D.clearTags`): Corsair's sat on 06's.
- **A sign mostly off the screen's side is hidden** (`Plaza2D.clearEdges`): NOTICE BOARD read "ARD".
- **The lifts show how many a side**: one, two or three figures in the lift's colour on its doors
  (`PlazaArt.lift`).

Not changed: the cabinet rows still share an x (positions are generated web data - the owner's call).

## How to look at it

`.renders/lobby-r5/`: the eleven shots; `R4-*` round 4's; references `REF-*.png`. SVG sources beside
the PNGs.

## Claims to verify

1. No HUD card sits over the walking band in any shot, at 1280 x 720 or on the phone.
2. Every sign on screen is at least 60% on it, and no name tag is drawn over a sign.
3. Each district reads as what it is for without its sign: the lifts by their figures, the arcade by
   its machines under one low canopy.

## What I am least sure about

- The action card at the bottom left is further from where you look (the fighter, mid-screen).
- The two cabinet rows (above).
- The lounge's sky above the stations.

## What to return

Scores per area and the weighted overall with its band; a verdict on each claim with measurements;
which of round 4's findings are fixed; issues ranked by how much fixing each would raise the score,
each measured, with a concrete fix (name the function); what works. Be blunt.
