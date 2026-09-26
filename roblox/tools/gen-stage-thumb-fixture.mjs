// Every stage's map-select thumbnail, and the Random tile, at four sizes, for tests/stage-thumb.luau.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const { stageThumb, randomThumb } = await import('../../web/src/render2d/stageThumb.js');
const { STAGES } = await import('../../web/src/data/stages/index.js');
const SIZES = [[100, 60], [160, 90], [237, 133], [58, 40]];
const S = (sh) => sh.map((v) => (typeof v === 'number' ? String(v) : v));
const stages = STAGES.map((s) => ({ id: s.id, sizes: SIZES.map(([w, h]) => stageThumb(s, w, h).map(S)) }));
const random = SIZES.map(([w, h]) => randomThumb(w, h).map(S));
fs.writeFileSync(path.join(HERE, '../tests/stage-thumb-fixture.json'), JSON.stringify({ sizes: SIZES, stages, random }));
console.log(`stage thumbnails: ${stages.length} stages x ${SIZES.length} sizes`);
