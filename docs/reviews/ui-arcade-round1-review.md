# UI arcade, round 1: review (Claude reviewer, 2026-10-19)

Scores: faithful 4.5 · fits Blockfall 5.0 · readability 5.0 · consistency 5.0 · hierarchy 4.5 ·
**overall 4.8** ("getting better, not good enough").

Issues, by impact (the reviewer's, summarised; measurements from the SVGs):

1. Results: stat values and names were dark text with a dark outline (1.09:1 fill to stroke), ink blobs;
   PodiumView outlined them directly, bypassing Ui.text's "dark words bare" rule.
2. Select (pick): weapon labels 12 px caps on an 86 px pitch collide ("GAUNTLETWAR HAMMER").
3. Odds & details: the footer overflows the window and runs under BACK; the list cuts a row mid-glyph;
   the only window with no title band.
4. Studio: the scroll chip is buried under tiles; a swatch orphans onto a second row; 44 labels under
   12 px; the flattest screen - tiles should be cards, the preview a stage, not a pale slab.
5. Faithfulness: the simulator is half-quoted (thin 44 px header, no hero card, no pattern, prices as
   green buttons not dark pills, no icon column / money pill) and the pixel kit reduced to a bevel (no
   pixel lettering, no stepped corners, no gem/key/trophy icons - currency is a plain string).
6. Consistency: three surface languages (dark HUD pills, dark chat window, slate chips, the climb's
   blue glass) and four text treatments. One rule: pale window -> dark bare text; coloured face -> white
   text, tone outline; over the world -> white/gold, ink outline.
7. HUD: damage % white on cream (1.01:1), living on its outline; SHIELD 11 px; band names 4.3:1.
8. Shop: cards leave 82-122 px dead space at the right; sections share no columns; subtitles cramped.
9. Select (rules): KEEP CURRENT's band is cream with white text (1.22:1): looks disabled.
10. Plaza: LOCKER is olive mud (2.99:1), reads as disabled.
11. Locker: cards dense (three lines, two full-width buttons), bottom 35% of the window empty.

Keep: the tone system; Ui.button's band and lip; dark text on cream (14.27:1); rarity gradient cards;
Records; Locker crates; the error notice; select map/rules vote cards; gold-on-ink world titles.
