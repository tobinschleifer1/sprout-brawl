// Reference output of web/src/engine/rng.js, for tests/rng-parity.luau.
//
//     node tools/gen-rng-fixture.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const { makeRng } = await import('../../web/src/engine/rng.js');

// Seeds chosen to cover the edges: 0 (the state xorshift cannot leave, so it must be remapped),
// the top of the 32-bit range, and a few ordinary ones.
const out = [];
for (const seed of [1, 2, 12345, 0, 0xFFFFFFFF, 7]) {
  const r = makeRng(seed);
  const vals = [];
  for (let i = 0; i < 2000; i++) vals.push(r());
  out.push({ seed, first: vals.slice(0, 3).map(String), sum: String(vals.reduce((a, b) => a + b, 0)), last: String(vals[1999]) });
}
fs.writeFileSync(path.join(HERE, '../tests/rng-fixture.json'), JSON.stringify(out));
console.log(`rng fixture: ${out.length} seeds x 2000 values`);
