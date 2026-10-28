# Lobby, round 5: review (2026-10-28)

One reviewer. **7.08** (faithful 7.2 · fits 6.7 · readability 7.6 · consistency 7.3 · hierarchy 6.6).
Up from 6.84; almost there. (Its first run lost its connection and was resumed.)

Claims: 1 true at 1280 x 720 (cards 23 px or more under the band), false on the phone - the button row
sits on the band's front 32 px across 74% of the width; 2 true as worded but not in spirit - marquees 05
and 01 are 62% on screen and read "5" and "1", the billboard is cut to "BLO", and 06's number is simply
hidden under Corsair's tag; 3 lifts yes (figures read as counts, though blue and pink are 1.04 and
1.13:1 on the doors, carried by their ink), the arcade only partly - the canopy is 23 px over the back
marquees but the sky moved above it (180 px, 25% of the screen), and the rows still share an x.
Fixed: the action card off the band, tips, the title card (32% wide), "ARD", blank doors. Not fixed:
stacked rows, the arcade's sky, the lounge's 210 px of sky and its 58%-wide card, the phone's buttons.
Also: `clearEdges` reads `gui.AbsoluteSize`, stale at start - use the canvas's width.
