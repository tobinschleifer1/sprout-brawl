# Lobby, round 3: review (2026-10-28)

One reviewer. **6.67** (faithful 7.0 · fits 6.2 · readability 7.0 · consistency 7.2 · hierarchy 6.0).
Up from 6.41; the first round in "almost there".

Claims: 1 half true - no sign meets the title card, the district title or another sign (nearest 9 px
under the title), but the gap over what each names runs 7-26 px: `signAbove` takes hand-typed cell
heights, not the art's; 2 true by the rule, but the ink signs (SKEWERS, 1v1 OPEN ROOM) still render
with an olive 2 px halo that closes their counters - `letterSign` hides the stroke, the SVG exporter
may not honour UIStroke transparency (unverified in Studio); 3 false - each back cabinet sits on its
front one, sharing the outline row, 0 px apart: one two-tone locker per column.
Fixed: the arcade sign and the climb clear the title; the paving (white on it 2.3-2.7:1); the title
card (49% of the width); stall signs off their awnings; name tags; lounge people (93 px, market 103);
"1 CPU"; the hologram off the screen. Not fixed: the cabinets, flat screens, blank lift doors, dead
space - 167 px of sky over the arcade's cabinets, 175 px of empty floor under the lounge.
Also: the tip card still cuts people's legs (render taken inside its six seconds), and on the phone
covers a stall's counter; NOTICE BOARD cut to "ARD" at the phone's edge; `clearBanner` hid nothing
in any shot - the reviewer would keep the gap rule and drop the hiding.
