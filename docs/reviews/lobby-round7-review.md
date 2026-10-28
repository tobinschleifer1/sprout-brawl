# Lobby, round 7: review (2026-10-29)

One reviewer. **7.31** (faithful 7.4 · fits 7.1 · readability 7.6 · consistency 7.4 · hierarchy 7.0).
Up 0.05 from 7.26; almost there.

Claims: 1 false - the wall starts under the sign tops (y 237), so the 151-165 rows of sky over the
lounge are unchanged; it filled the gaps between and behind the stations instead (sky there 29-39%,
was 55-93%); 2 half true - the marquee is an arcade's (stepped crown, chase bulbs), but the arcade's
sky band is still 81% sky, its side thirds 95%; 3 true but untested by the renders - no two tags ever
collided there, and `clearTags` is single-pass.
Fixed: the wardrobe 50 px clear, the 3v3 render, the comment, the marquee no longer the billboard.
Regressed: the phone's NOTICE BOARD has no label (hidden whole rather than slid on screen); the
reflection's sword pokes out of the mirror at full strength.
Also: the wall swallows the props (couches 1.13-1.14:1 on its face, outlines 1.77:1); the windows
ignore the stations (the map board reads as another window, slivers of 7-15 px beside stations); the
dead billboard panel at the edge; the marquee's fighters are flat pictograms; the wall's pennants are
squares; people hidden behind cabinets (the shared x - the owner's call).
