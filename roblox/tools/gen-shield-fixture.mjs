// The energy-shell shield at a spread of strengths, frames and impacts, for tests/shield-parity.luau.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const { shieldShapes, hash } = await import('../../web/src/render2d/shield.js');
const S = (v) => (typeof v === 'number' ? String(v) : v);
const cases = [];
for (const hp of [1, 0.72, 0.31, 0.29, 0.1, 0]) {
  for (const frame of [0, 4, 5, 17, 360, 123457]) {
    for (const hit of [null, { k: 1, x: 5.5, y: 3 }, { k: 0.4, x: -1, y: 9 }]) {
      cases.push({ hp: S(hp), frame, hit: hit && { k: S(hit.k), x: S(hit.x), y: S(hit.y) },
        shapes: shieldShapes(2.25, 4.5, 5.2, hp, frame, hit).map((sh) => sh.map(S)) });
    }
  }
}
const hashes = [];
for (let i = 0; i < 40; i++) hashes.push([i * 13, i * 977, S(hash(i * 13, i * 977))]);
fs.writeFileSync(path.join(HERE, '../tests/shield-fixture.json'), JSON.stringify({ cases, hashes }));
console.log(`shield fixture: ${cases.length} cases`);
