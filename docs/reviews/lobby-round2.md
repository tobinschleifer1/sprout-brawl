# Lobby (arcade direction), round 2

Same owner's request, rubric, weights and bands as `lobby-round1.md`. Earlier: 5.65 / 5.55
(`lobby-round1-review.md`). From this round on, **one reviewer a round** (the owner's call). Score fresh.

## What changed since round 1 (`git log -1` on `feature/lobby-arcade`)

- **Every station named**: the notice board, the roof map and the three lifts have kit signs
  (`Plaza2D.marketItems`). Each lift says what it is - 1v1 OPEN ROOM gold, 2v2 CREW LIFT blue, 3v3
  FREIGHT LIFT pink - and its header is a kit panel in that colour (band, lip) over the doors
  (`PlazaArt.lift`).
- **One lettering in the world**: the stall names are kit signs in their awning's colour, hung over
  the awning (the navy boards are gone from `PlazaArt.stallBack`); the billboard's BLOCKFALL is in the
  UI's display face. Name tags stay outlined body text, as the HUD's small labels are.
- **Signs hang at the same gap over what they name** (`Plaza2D.signAbove`, `SIGN_GAP`); a lounge
  station's sign sits at the top of its own art (`stationArt` returns it).
- **The lounge in view whole**: its camera scale fits the room's width, so the stairs and the ready
  rail are on screen; no district banner in a lounge (it said THE WAR ROOM over the title card's own
  THE WAR ROOM). Rules is violet, not pink. Screens are a deep shade of their station's colour, not ink.
  The stairs down are a kit doorway.
- **The tip goes after six seconds on every screen** (it never went on a wide one).
- **The roofs' ends and back are inked** (`Plaza2D.drawGround`): the ends were pale paving on pale sky.
- **The arcade**: its beam deep indigo with teal bulbs, its sign 1v1 CABINETS (not THE ARCADE under
  THE ARCADE GROVE); each cabinet's side a coloured kit panel and a lit screen, a stick and buttons on
  its deck (`PlazaArt.cabinetPair`).
- **Copy**: the title card says "1v1 at the arcade's cabinets · rooms of every size at the fighters'
  gates"; the billboard says THE ARCADE IS OPEN when you are alone, not "1 ON THE ROOF"; the climb's
  district is CLIMBERS' YARD (the station is SKYLINE CLIMB; "SKY CLIMB" read as a typo of it). The
  kiosk's beam stops under the billboard.

## How to look at it

`.renders/lobby-r2/`: the same eleven shots; `R1-*` round 1's; references `REF-*.png`. The district
title (THE ARCADE GROVE...) shows for three seconds as you walk in, and the tip for six; the renders
catch both. SVG sources beside the PNGs.

## Claims to verify

1. Every station in the market and the lounges has its name on a kit sign, and no sign on screen meets
   the title card.
2. In a lounge every station's sign hangs the same distance over the top of its own art, and the whole
   room - stairs to ready rail - is on a 1280 x 720 screen.
3. The world has one sign style: every stall, station and district sign is a kit card; the only other
   world lettering is the billboard and people's name tags.

## What I am least sure about

- The lounge's people are smaller now (the room fits the screen's width).
- The arcade's sign still sits just under the district title in the first three seconds.
- The cabinets: side-on, still the same layout; the back row stands over the front.
- Saturated signs everywhere may be too many coloured cards.
- The paving's own look (pale flagstones) is unchanged.

## What to return

Scores per area and the weighted overall with its band; a verdict on each claim with measurements;
which of round 1's findings are fixed; issues ranked by how much fixing each would raise the score,
each measured, with a concrete fix (name the function); what works. Be blunt.
