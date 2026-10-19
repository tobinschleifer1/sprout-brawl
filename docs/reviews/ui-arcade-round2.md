# UI rework (arcade direction), round 2

Same rules, rubric and bands as round 1 (`ui-arcade-round1.md`; read it for the owner's request, the
two references and the rubric). Round 1 scored **4.8**; its findings are summarised in
`ui-arcade-round1-review.md`. Score this round fresh against the rubric - do not grade the change.

## What changed since round 1 (commit on `feature/ui-arcade`, see `git log -1`)

- Results (`PodiumView.luau`): dark stat values and names are no longer outlined; the place label is
  white outlined in its band's own shade.
- Select (`SelectScreen.luau`): weapon names shrink to fit their tile (`SelectScreen.fitSize`); the
  KEEP CURRENT rule card has a teal band; CPU chips are tan.
- Odds & details (`LockerScreen.luau`, `ShopScreen.luau`): a blue title band, the footer in its own
  row, the list ending above it.
- Studio (`AvatarEditor.luau`): tiles and swatches carry own-colour borders; labels 12 px minimum; a
  sky gradient behind the character; swatch rows hold exactly half the palette; the scroll chip is a
  dark pill on the grid's edge; the title in pixel lettering.
- Shop: prices on dark pills (green OWNED, gold CLAIM, grey for waiting / not for sale), the whole
  card buys, the day's priciest item on a wide hero card, columns that fill the row (3 beside the
  hero, 4 clothing, 4 keys, 5 passes), meta shortened to "Rarity · Weapon", 60 px header, a plain
  white X.
- Locker: 60 px header; the balance as currency pills with pixel gem and key icons (`Ui.icon`,
  `Ui.currency` in `Ui.luau`, drawn as Frames).
- Window titles in the pixel kit's lettering (`Ui.TITLE` = Font.Arcade, Press Start 2P).
- Status pills (HUD clock, ultimate, climb clock) are indigo coloured faces with border and lip;
  chat and the climb readout are pale windows with bands.
- HUD: the damage percent on the pale card is the damage ramp deepened to at least 4.5:1
  (`Hud.cardPercent`), not outlined; the floating label over the fighter is unchanged.
- Plaza: the LOCKER button is purple.
- The render tools now paint in Roblox's ZIndex order, honour list padding and pill radii, and wrap
  Builder Sans by its stand-in font's width.

## How to look at it

`.renders/round2/*.png` are true-font renders from headless Chrome at each screen's own size
(1280 x 720; phones 844 x 390 and 390 x 844). The SVG sources sit beside them for exact numbers. The
references are copied in as `REF-*.png`. Same warning as before: pale empty boxes are where the game
draws item art and fighters at runtime.

## Claims to verify

1. Every card percent on the HUD is at least 4.5:1 against the card (#FFF8EC).
2. No text is cut off or overlapping on any of the 23 screens, phones included.
3. Each screen now follows one rule: pale window - dark bare words; coloured face - white words
   outlined in its own shade; over the world - white or gold words outlined in ink.
4. The Shop shows both references: the simulator's red header, hero card, saturated cards and dark
   price pills; the pixel kit's lettering, gem/key icons and bevelled buttons.

## What I am least sure about

- Press Start 2P for window titles: does it read as the pixel kit, or as a clash beside Fredoka?
- The plaza and the social bar still use wide text buttons; the simulator's square icon-button
  column is not done.
- The Studio's tiles are empty cream cards in these renders (fighters are drawn at runtime): is the
  screen's frame good enough to judge?
- The Locker cards are as dense as before (three lines, two buttons).
- The hero card's art area is large and empty here; in game it holds the item's art.

## What to return

As round 1: scores per area and overall, then issues ranked by impact with measurements and concrete
fixes, then what works. Say which round 1 findings are fixed, which are not, and anything new.
