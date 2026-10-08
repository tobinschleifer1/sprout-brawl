// Weapon drops drawn at a spread of states and frames, for tests/drop-parity.luau: falling and
// landed, fresh and thrown, long-lived and about to fade.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const { dropShapes } = await import('../../web/src/render2d/dropShapes.js');
const S = (v) => (typeof v === 'number' ? String(v) : v);
const cases = [];
for (const look of [null, 'Hammer', 'Daggers']) {
  for (const onGround of [false, true]) {
    for (const life of [840, 300, 119, 64, 1]) {
      for (const frame of [0, 7, 8, 30, 35, 119, 120, 1234]) {
        const d = { x: -3.75, y: 14.25, onGround, life, look };
        const { shapes, sprite } = dropShapes(d, frame);
        cases.push({ look, onGround, life, frame, shapes: shapes.map((sh) => sh.map(S)),
          sprite: sprite && { id: sprite.id, x: S(sprite.x), y: S(sprite.y), angle: S(sprite.angle), alpha: S(sprite.alpha) } });
      }
    }
  }
}
fs.writeFileSync(path.join(HERE, '../tests/drop-fixture.json'), JSON.stringify({ cases }));
console.log(`drop fixture: ${cases.length} cases`);
