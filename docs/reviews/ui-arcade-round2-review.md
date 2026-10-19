# UI arcade, round 2: review (Claude reviewer, 2026-10-19)

Scores: faithful 6.0 · fits Blockfall 6.0 · readability 5.5 · consistency 5.0 · hierarchy 5.5 ·
**overall 5.6** (up from 4.8; "getting better, not good enough").

Fixed from round 1: results ink blobs, KEEP CURRENT, LOCKER colour, odds band and footer row.
Partly: select labels (no collision, but shrunk to 8-11 px grey at 3.54:1), Locker odds still cuts a
row, Studio still flat (title the smallest text in its header), faithfulness (Shop has no gem/key).
Not fixed: HUD (card drawn at 0.92 opacity, so percents 4.23-4.60:1), Locker density.

Ranked issues:
1. Cream secondary buttons render with fill and stroke both #666157 (5.03:1): swollen, look disabled.
2. Bare white on mid-tone faces: OWNED 2.14, WORN 2.07, WEAR/ALL/THIS OPENING 3.19, HOLD H 2.77, HUD
   band names 3.58-4.30.
3. Shop passes: the VIP card overlaps itself (14 wrapped lines in 250 px); the 5-column row wraps
   (cell() leaves zero slack at 5).
4. HUD percent on the translucent card under 4.5; SHIELD 11 px; orange band names 3.58.
5. Press Start 2P at six sizes (8.4-19 px rendered) and missing from the odds windows: one window-title
   size >= 16 px, no pixel type under 12 px.
6. Locker grid clips its own first column/row borders; Locker odds clips a row; 41 px dead space.
7. Phone: CLAIM (PAID) overflows its pill; plaza district title on the billboard; Studio one tile row.
8. Select labels 8-9 px grey; the fighter's sword over the grid.
9. SUB on PANEL2 3.99:1; records blue 3.88 and green 3.53; faded chat line 1.23:1.
10. Studio: title size, flat identical tiles.
Missing still: icon-button column, card pattern, stepped corners, money pill, gem/key in the Shop.
