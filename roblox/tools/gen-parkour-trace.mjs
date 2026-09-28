// Climb the real web/src/engine/parkour.js with scripted and pseudo-random input, for
// tests/parkour-parity.luau: every frame's fighter state, checkpoint, falls and clock, from several
// starting checkpoints, through the moving girders, lifts and sinking planks.
import fs from 'node:fs';
import { Parkour } from '../../web/src/engine/parkour.js';
import { COURSE, COURSE_WEAPON } from '../../web/src/data/parkour.js';
import { buildLoadout } from '../../web/src/data/loadout.js';
const FIELDS = ['x', 'y', 'vx', 'vy', 'facing', 'state', 'onGround'];
const S = (v) => (typeof v === 'number' ? String(v) : v);
const char = buildLoadout('Classic', COURSE_WEAPON);
let seed = 21;
const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return Math.floor(seed / 65536) / 32768; };
const cases = [];
for (const from of [0, 1, 2, 3, 4, 5, 6, 7, 8]) {   // 8: on the Summit, finished: the clock must not run
  const pk = new Parkour(COURSE, char, from);
  const frames = [];
  let hold = { x: 1, y: 0 }, jumpAt = 20, held = 0;
  for (let i = 0; i < 1500; i++) {
    if (i % 40 === 0) hold = { x: rnd() < 0.8 ? 1 : (rnd() < 0.5 ? -1 : 0), y: rnd() < 0.1 ? -1 : 0 };
    const jump = i === jumpAt;
    if (jump) { held = 8 + Math.floor(rnd() * 20); jumpAt = i + 18 + Math.floor(rnd() * 30); }
    const input = { x: hold.x, y: hold.y, jump, jumpHeld: held > 0, downTap: rnd() < 0.01 };
    if (held > 0) held--;
    pk.step(input);
    const f = pk.fighter;
    frames.push({ input, values: FIELDS.map((k) => S(f[k])), reached: pk.reached, deaths: pk.deaths, frames: pk.frames,
      platform: f.platform ? f.platform.id : '', events: pk.drain().map((e) => e.type + ':' + (e.checkpoint ?? e.frames)).join(',') });
  }
  cases.push({ from, frames });
}
fs.writeFileSync(new URL('../tests/parkour-fixture.json', import.meta.url), JSON.stringify({ fields: FIELDS, weapon: COURSE_WEAPON, cases }));
console.log(`parkour trace: ${cases.length} climbs, ${cases.length * 1500} frames`);
