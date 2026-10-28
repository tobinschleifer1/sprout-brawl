# Lobby (arcade direction), round 3

Same owner's request, rubric, weights and bands as `lobby-round1.md`. Earlier: 5.65 / 5.55, 6.41
(`lobby-round{1,2}-review.md`). One reviewer. Score fresh.

## What changed since round 2 (`git log -1` on `feature/lobby-arcade`)

- **The arcade**: the back row of cabinets in its dark shades (`PlazaArt.cabinetPair(true)`, drawn for
  cabinets deeper than `Plaza2D.CAB_BACK`), so the rows read as near and far rather than one locker;
  a wider control deck with a stick and two buttons. A cabinet's state - READY · n, IN PLAY /
  VS CPU (and who is watching), a win streak - and SIT HERE and the records leader are kit tags now,
  not bare words. The canopy sign is smaller, so it clears the district title.
- **Signs stand on their feet** (`placeSign` takes the card's foot, not its centre): `signAbove` is
  one gap everywhere (the stalls' signs sank 3 px into their awnings; a two-line card hung lower).
- **Signs step aside from the district title** while it shows - three seconds as you walk in
  (`Plaza2D.clearBanner`); the climb's sign now stands on the scaffold's top deck under its flag.
- **Ink letters on pale faces** (`Plaza2D.letterSign`): a face white reads under 2:1 on - the gold
  lift, the skewer stall's yellow - is lettered in ink, as the UI's yellows are.
- **Name tags** outlined at 2 px in ink (a UIStroke; TextStroke is 1 px).
- **The paving** a mid-tone stone in bigger flags with darker joints (`RealmArt.paving`): white names
  read on it at 2:1 or better; pale, it was the biggest light mass on screen.
- **The lounge** fitted to its stations, stairs to ready rail, not the island's width: its people are
  bigger again.
- **The title card** shorter: "1v1 at the cabinets · rooms at the gates · your look at the tailor's"
  (it had grown to 81% of the screen). "1 CPU", not "1 CPUs". The kiosk's hologram sits under the
  billboard's screen.

## How to look at it

`.renders/lobby-r3/`: the eleven shots; `R2-*` round 2's; references `REF-*.png`. The district title
shows for three seconds as you walk in and the tip for six; the renders are taken in both. The
cabinets' state tags show only with a match on (not in these renders; `tests/plaza-view` draws them).

## Claims to verify

1. No sign on screen meets the title card, the district title or another sign; each hangs the same gap
   over the top of what it names.
2. Every sign's words read: white outlined on a deep face, ink on a pale one.
3. The arcade's two rows of cabinets read as two rows, not one stack.

## What I am least sure about

- The cabinets are still side-on boxes; the back row is darker, not moved.
- The paving's new grey may now be dull beside the bright signs and sky.
- Signs hiding for the title's three seconds - a player walking in sees the title, then the signs.
- The lounge's lower half is still empty floor and island.

## What to return

Scores per area and the weighted overall with its band; a verdict on each claim with measurements;
which of round 2's findings are fixed; issues ranked by how much fixing each would raise the score,
each measured, with a concrete fix (name the function); what works. Be blunt.
