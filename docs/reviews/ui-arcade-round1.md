# UI rework (arcade direction), round 1

Scored design review brief (see `README.md` in this folder for the rules: measure everything, do not
grade effort; three rounds per subject; stop early above 8).

## The owner's request

> "ui needs to be reworked here are 2 designs that i would like to use maybe a mix of the two. the ui
> now looks bad and it does not fit the feel of the game. i had an agent working on new ui however i
> still did not like the results ... make sure its faithful and well adapted to our game."

The two references (look at them first):

- `.renders/round1/REF-simulator-shop.png` — a Roblox simulator's shop: a big rounded white window
  under a bold red header with a white title and X; saturated item cards (teal, purple, blue, gold)
  with a light-to-colour gradient and a faint pattern, icons breaking out of the card, white outlined
  names, dark price pills; a stack of square colourful icon buttons down the left; a green money pill
  and level bar at the bottom.
- `.renders/round1/REF-pixel-kit.png` — a pixel UI kit: MENU / START / SIGN IN buttons with a thick
  outline in a darker shade of the button's own colour, a light band across the top and a dark lip
  below, white pixel lettering with a darker outline; round grey icon buttons; a heart health bar,
  sliders, a gem, a key, a trophy, hearts, a sword.

The previous agent's direction ("Clean Modern": flat, hairline borders, light outlines) is what the
owner rejected. Blockfall itself: a 2D pixel-art platform fighter on Roblox — pixel sprites, a
bright pixel sky and rooftop plaza, chunky pixel weapons.

## What changed (commit 6e92056 on `feature/ui-arcade`)

- `roblox/src/client/Ui.luau` — a new default theme `arcade` (`Ui.THEMES.arcade`): Fredoka One
  display, Builder Sans labels, 10 px corners, 3 px borders; `light` windows (palette `LIGHT`:
  PANEL #FFF8EC, PANEL2 #F4E7CF, EDGE #DECAA6, TEXT #2B2140, SUB #806E5C); `tone` borders
  (`Ui.tone`: a box's border is its own colour darkened 58%); the `arcade` bevel (a rounded light band
  over the top 30% of a button, a 5 px dark lip along its foot); new builders `Ui.card`,
  `Ui.paintCard`, `Ui.faceText`, `Ui.pricePill`; `Ui.text` no longer outlines dark words.
- Screens restyled onto it: `ShopScreen.luau` and `LockerScreen.luau` (rarity-coloured cards, WORN
  badge, coloured crate cards, light odds window), `Plaza2D.luau` (teal title card, pale prompt
  card), `Hud.luau`, `AvatarEditor.luau`, `LobbySocial.luau`, `SelectScreen.luau`,
  `ClimbRecords.luau`, `ParkourView.luau`, `PodiumView.luau`, `RoomPanel.luau` (the words on their
  windows moved to the window's colours).

You should not need to read more than `Ui.luau` (380 lines) plus whichever screen a finding is about.

## How to look at it

The screenshots in `.renders/round1/*.jpg` were taken in a real browser at 1280 x 720 (scaled to
800 x 450), with the game's fonts loaded. The SVG sources are `.renders/*.svg` — open them as text to
read exact colours, sizes and positions (every box is a `<rect>`, every word a `<text>`).

**Two warnings about the pictures:**
1. Empty pale boxes inside cards, the studio's tiles and the character preview are where the game
   draws pictures (item art, fighters) at runtime; these tools do not draw them. Judge the frames,
   not their emptiness.
2. Do not convert the SVGs with Quick Look, `rsvg` or similar to look at them: they drop the Google
   Fonts import and fall back to Arial/Times. If you render them yourself, use a browser.

Commands (all cheap): `cd roblox && tools/render-gallery.sh ../.renders` re-renders every screen
(~1 min). `cd roblox && ./check.sh` (~1 min) must pass and does.

## Claims to verify (mine; check the ones that matter, say when one is wrong)

1. Dark words on the pale window (#2B2140 on #FFF8EC) are at least 7:1 contrast; secondary
   (#806E5C on #FFF8EC) at least 4.5:1.
2. White words outlined in the card's darker shade read on every rarity colour, including the pale
   Common grey (#B8C0CC) and Legendary gold (#FFB730).
3. Every button wears an outline in its own colour darkened, a light top band and a dark lip, as the
   pixel kit's do.
4. No screen at 1280 x 720 has text cut off or overlapping (I saw none in the Locker, Shop, Studio,
   records, results, select screens).
5. The look is one language across all 17 screenshots.

## What I am least sure about

- The Studio is flat and empty-looking: a big cream grid and a pale-blue stage. Even with pictures
  in, is it the weakest screen?
- The HUD over the fight keeps the dark pills (clock, prompts) and pale cards: is that consistent
  with the rest, or a second language?
- The Shop's card subtitles ("Rare Weapon skin · Sword") run edge to edge and look cramped.
- The plaza's district title ("CHAMPIONS' SQUARE") is gold outlined in ink — the only gold title.
- Nothing yet uses the references' icons (gem, key, trophy, hearts, coin) or the simulator's
  square icon-button column.
- Phone layouts (`.renders/*-phone.svg`) were not screenshotted this round.

## Rubric (score each 0–10, then the weighted overall)

| Area | Weight | What a 10 is |
|---|---|---|
| Faithful to the references | 25% | Someone who knows both references sees both in it, and it reads as a deliberate mix, not one with a nod to the other |
| Fits Blockfall | 20% | Belongs with pixel-art sprites, a pixel sky and a fighting game; not a generic simulator skin |
| Readability | 20% | Every word readable at a glance at 1280 x 720, measured contrast, sizes that suit their job |
| Consistency | 15% | One visual language: the same parts look the same everywhere |
| Hierarchy and layout | 20% | The important thing on each screen is seen first; spacing, alignment, nothing cut off or cramped |

Bands: under 4.5 bad design · 4.5–6.5 getting better, not good enough · 6.5–8 almost there · 8–10
workable.

## What to return

Scores per area and overall; then the issues ranked by how much fixing each would raise the score,
each with the screen, what is wrong (measured where it can be), and a concrete fix. Name what works,
briefly, so it is kept. Be blunt: the owner has already rejected one direction.
