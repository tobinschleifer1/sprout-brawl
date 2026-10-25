# Maps (arcade direction), round 4

Same owner's request, rubric, weights and bands as `maps-round1.md`. Earlier: round 1 5.6 / 5.8,
round 2 6.2 / 5.95, round 3 6.05 / 6.10 (`maps-round{1,2,3}-review.md`). Two independent Claude
reviewers. Score fresh.

## What changed since round 3 (`git log -1` on `feature/map-arcade`)

- **Separation, not equality** (`RealmArt.backdrop`): every far ridge and landmark colour sits 1.5:1
  from the island's rock body - on a daylight realm lighter and paler (value up, saturation down, hue
  kept: atmospheric distance), on a dark realm darker - and never more saturated than the rock.
  `tests/map-values` checks it on every realm (with a fixed 1.5, not the code's constant).
- **Signature accents** (`RealmArt.accent`): lava and the crater's glow, the forge's furnace doors and
  the hall's gold trim keep their colour, capped only in value; up to 8% of a landmark's area. (The
  hall's whole roof and TheSpan's rainbow are too big to be accents: they take the haze.)
- **Platforms and surfaces on light skies**: on a daylight realm the platform ramp is darkened (hue
  kept) until its face stands 3:1 under the sky (`RealmArt.shelfRamp`), and the shine on platforms and
  walking surfaces is a small step inside the face, not a push toward white.
- **Full-density courses**: the rock's lit band and its three courses are now drawn at the fighters'
  pixel size, in the surface sprite; the half-density body below them is plain rock (cheaper, which
  pays for it). The belly below remains half density.
- **Sun and clouds**: daylight suns hazed toward the sky with a faint, tighter halo; clouds mixed 30%
  toward the mid sky; Smeltworks' sun up out of the play band.
- **Smeltworks' rock** is blue-grey iron (it and Ashfall read as one realm); **Ashfall's rock** and
  the darkest stops of Ashfall's and FreightLift's skies lifted; **iron girders** 6 rows.

Not changed: platforms above the fight can sit under the top HUD in close shots - pulling them into
frame would zoom fights out further, against the "fighters small" finding; the fighters themselves are
never covered. Dark outfits on dark skies: the maps cannot give 3:1 against a near-black suit; a light
rim on fighters would be a character change, not a map one.

## How to look at it

`.renders/maps-r4/`: `<Stage>-wide.png`, `<Stage>-fight.png` (close), `<Stage>-spread.png`; `R3-*`
round 3's; references `REF-*.png`. SVG sources beside them.

## Claims to verify

1. Every far ridge and landmark colour is 1.5:1 from the island's rock body (accents excepted, under 8%
   of a landmark) and no more saturated.
2. Every platform face on a daylight realm stands 3:1 under the sky.
3. The rock courses are at the fighters' pixel size.

## What I am least sure about

- Daylight scenery may now read washed out (pale and desaturated) next to the saturated UI.
- The belly is still half density.
- Darkened daylight platforms (Foundry's wood) may read too brown.

## What to return

Scores per area and overall; which round 3 findings are fixed and which are not; issues ranked by
impact with stage, measurement and a concrete fix (name the function); what works. Be blunt.
