// The ultimate cutscene at every half-frame from -2 to 40 - its timing, the camera punch, the gold
// glow and the banner layout on three screen sizes - for tests/cinematic-parity.luau.
// Numbers travel as strings: Lune's JSON decoder keeps about 16 digits.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const { ultCinematic, punch, glowShapes, bannerLayout } = await import('../../web/src/render2d/ultCinematic.js');
const S = (v) => String(v);
const SCREENS = [[480, 270], [1280, 720], [812, 375], [400, 420]];
const rows = [];
for (let e = -2; e <= 40; e += 0.5) {
  const c = ultCinematic(e);
  const p = punch(3.5, 11, 5.2, -8.25, 6.5, c.zoom);
  const glow = glowShapes(c, -8.25, 4, 5.4).map((sh) => sh.map(S));
  const banners = SCREENS.map(([W, H]) => {
    const B = bannerLayout(c, W, H);
    return B ? [B.cx, B.cy, B.w, B.h, B.rot, B.alpha, B.stripe, B.portrait.x, B.portrait.y, B.portrait.size,
      B.weapon.x, B.weapon.y, B.weapon.size, B.text.x, B.text.y, B.text.size].map(S) : null;
  });
  rows.push({ e: S(e), c: [c.active, c.dim, c.zoom, c.slide, c.band, c.glow].map(S), p: [p.x, p.y, p.ppu].map(S), glow, banners });
}
fs.writeFileSync(path.join(HERE, '../tests/cinematic-fixture.json'), JSON.stringify({ screens: SCREENS, rows }));
console.log(`cinematic fixture: ${rows.length} frames`);
