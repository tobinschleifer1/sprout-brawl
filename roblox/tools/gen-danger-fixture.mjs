// Danger (render2d/danger.js) at a spread of weights, blast boxes, percents and frames, for
// tests/danger-parity.luau.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const { dangerPercent, dangerLevel, dangerShapes } = await import('../../web/src/render2d/danger.js');
const { STAGES } = await import('../../web/src/data/stages/index.js');
const S = (v) => (typeof v === 'number' ? String(v) : v);
const percents = [];
for (const st of STAGES) for (const w of [72, 82, 94, 100, 110, 118, 125]) percents.push({ weight: w, blast: st.blast, at: dangerPercent(w, st.blast) });
const shapes = [];
for (const k of [0, 0.01, 0.2, 0.5, 0.66, 0.67, 0.9, 1]) for (const frame of [0, 1, 17, 55, 300, 4321]) {
  shapes.push({ k, frame, shapes: dangerShapes(-4.5, 2.25, 5.2, k, frame).map((sh) => sh.map(S)) });
}
const levels = [];
for (const at of [60, 140]) for (const p of [0, 39, 40, 41, 70, 100, 119, 120, 121, 200, 999]) levels.push([p, at, S(dangerLevel(p, at))]);
fs.writeFileSync(path.join(HERE, '../tests/danger-fixture.json'), JSON.stringify({ percents, shapes, levels }));
console.log(`danger fixture: ${percents.length} danger percents, ${shapes.length} drawings, ${levels.length} levels`);
