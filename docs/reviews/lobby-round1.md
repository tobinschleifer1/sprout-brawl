# Lobby (arcade direction), round 1

Scored design review brief. Rules in `README.md` in this folder: measure everything, do not grade
effort; bands under 4.5 bad · 4.5-6.5 getting better · 6.5-8 almost there · 8-10 workable; rounds
continue until one scores above 8.

## The owner's request

> "start working on the lobby same agent review system"

It follows the UI rework (`ui-arcade-round1..9`, ended 8.08 / 7.6) and the maps (`maps-round1..6`,
parked at 6.48 / 6.25), whose request was to make them "more similar to the ui and the characters". The
same goal holds here: the lobby should look made by the same hand as the menus and the fighters.
References: a pixel UI kit (buttons outlined in a darker shade of their own colour, a light band across
the top, a dark lip below; pixel lettering), a Roblox simulator shop (big rounded windows, saturated
cards, white outlined names), and the finished game UI and a fight.

## What the lobby is, in code

The Skyhold Bazaar: rooftop islands walked beat-'em-up style (x along the street, z into depth), with
districts (Tailor's Terrace, Champions' Square, the Arcade Grove, Fighters' Gates, the Skyline Climb)
and the private lounges a fight is prepared in. `roblox/src/client/Plaza2D.luau` draws it and owns its
HUD; `PlazaArt.luau` builds the props as pixel art in eighth-of-a-stud cells; the island bodies are the
maps' `RealmArt` (realm `Realms.LOBBY`); people are the fighters' own `Fighter2D`. Station names, stall
signs and name tags are TextLabels projected from world points. The HUD around it (title card, key
hints, prompt, the square buttons bottom right) was in the UI rounds.

## What changed this round (`git log -1` on `feature/lobby-arcade`)

- **Props outlined** (`PlazaArt.outline`): every solid prop - stalls, billboard, kiosk, water tower,
  cabinets, stools, lifts, boutique, boards, couches, plants - gets an ink line round its silhouette,
  as the fighters and the islands have (not under its base, nor on the climb's scaffold or the string
  lights). Bare, they were flat colour on pale paving.
- **Station names on signs** (`Plaza2D.placeSign`): a card in the UI's kit (coloured face, its own
  darker border, a light band, a dark lip) with white words outlined in its shade, instead of bare amber
  or brown words floating over the roof. Each lounge station in the HUD's own colour (map board blue,
  weapon rack orange, rules purple, ready rail green, the stairs pink); the wardrobe pink, the climb
  orange, records and cabinet numbers indigo, the arcade teal.
- **Lounge desks** (`kitBox`): the stations were near-black slabs; now a desk in a darker shade of the
  station's colour and a frame round its screen in the colour itself, each with an ink outline, light
  band and dark lip.
- **The arcade**: its canopy beam in the kit's anatomy (teal, band, lip, bulbs) with THE ARCADE on it;
  it was an ink bar with pin stripes and the sign sat behind the district title. Cabinet numbers on
  their own marquees (the front row's sat on the back row's cabinets).
- **Name tags** outlined whole in ink (a 0.55 stroke left them grey on the pale sky and paving).

## How to look at it

`.renders/lobby-r1/`: `square`, `square-crowd` (12 others about), `board`, `tailor`, `arcade`,
`arcade-crowd`, `gates`, `climb`, `phone` (844 x 390), `lounge-duel`, `lounge-triples`; `BEFORE-*` the
same shots before this round. References `REF-*.png` (`REF-map-fight.png` is a fight, for the fighters
and the maps). SVG sources beside the PNGs give exact colours. Never judge from Quick Look or rsvg.

## Rubric (score each 0-10, then the weighted overall)

| Area | Weight | What a 10 is |
|---|---|---|
| Faithful to the UI and the characters | 25% | Someone who has seen the menus and the fighters sees the same hand: outline, band-and-lip anatomy, palette discipline, pixel density |
| Fits Blockfall | 20% | A rooftop bazaar of a pixel fighting game; each district reads as what it is for (shop, arcade, gates, climb, tailor) |
| Readability | 20% | Where to go and what each station does is seen first; people, names and signs read on every background; the HUD never hides what you need |
| Consistency | 15% | Districts, lounges, props and signs are one language |
| Hierarchy and composition | 20% | The stations and people lead, the scenery recedes; nothing crowds or overlaps awkwardly; the screen's space is used well |

## Claims to verify

1. Every solid prop in the market and the lounges has an ink outline along its silhouette (its base
   excepted).
2. Every station's name is on a sign in the UI's kit, and its white words read at 4.5:1 or better
   against their outline and face.
3. No world sign overlaps the district title, the title card or another sign in any shot.

## What I am least sure about

- The paving: a pale flagstone band with no ink rim at its front edge, unlike the maps' islands.
- Fighters' Gates' lifts are blank grey doors that do not say 1v1 / 2v2 / 3v3 until you stand there.
- The tip card covers people near the front of the roof in the crowd shots.
- A lot of empty sky above the stations on a wide screen.
- The lounge desks may be too loud, and the lounge's right-hand station is cut by the screen edge.

## What to return

Scores per area and the weighted overall with its band; a verdict on each claim with measurements;
issues ranked by how much fixing each would raise the score, each with the shot, what is wrong
(measured) and a concrete fix (name the function); what works. Be blunt.
