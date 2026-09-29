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
// Skips (bought checkpoints): mid-climb, forward by one and by several, backwards (refused), and to
// the Summit - which finishes the climb and stops its clock with no summit event.
for (const plan of [{ from: 0, at: 30, to: 1 }, { from: 2, at: 50, to: 5 }, { from: 4, at: 40, to: 2 }, { from: 6, at: 20, to: 8 }]) {
  const pk = new Parkour(COURSE, char, plan.from);
  const frames = [];
  for (let i = 0; i < 200; i++) {
    const input = { x: i % 50 < 30 ? 1 : 0, y: 0, jump: i % 37 === 5, jumpHeld: i % 37 < 15, downTap: false };
    const skip = i === plan.at ? plan.to : undefined;
    if (skip !== undefined) pk.skipTo(skip);
    pk.step(input);
    const f = pk.fighter;
    frames.push({ input, skip, values: FIELDS.map((key) => S(f[key])), reached: pk.reached, deaths: pk.deaths, frames: pk.frames,
      skipped: pk.skipped, done: pk.done,
      platform: f.platform ? f.platform.id : '', events: pk.drain().map((e) => e.type + ':' + (e.checkpoint ?? e.frames)).join(',') });
  }
  cases.push({ from: plan.from, frames });
}
// Set-downs onto every moving foothold, falling as a jump lands, at six points of its cycle. Random
// climbs almost never land on a slider, and a landing on one was the bug both builds shared: every
// one was thrown off the side (web/src/engine/stage.js collide). These hold the port to the fix.
const still = { x: 0, y: 0, jump: false, jumpHeld: false, downTap: false };
for (const d of COURSE.platforms.filter((p) => p.moving)) {
  const M = d.moving.x || d.moving.y;
  for (let k = 0; k < 6; k++) {
    const pk = new Parkour(COURSE, char, 0);
    const wait = Math.round((k / 6) * M.period * 60);
    for (let i = 0; i < wait; i++) pk.step(still);
    pk.drain();
    const drop = { wait, id: d.id, dy: 0.3, vy: -30 };
    const p = pk.stage.platforms.find((q) => q.id === d.id);
    Object.assign(pk.fighter, { x: p.cx, y: p.top + drop.dy, vx: 0, vy: drop.vy, onGround: false, platform: null });
    const frames = [];
    for (let i = 0; i < 40; i++) {
      pk.step(still);
      const f = pk.fighter;
      frames.push({ input: still, values: FIELDS.map((key) => S(f[key])), reached: pk.reached, deaths: pk.deaths, frames: pk.frames,
        platform: f.platform ? f.platform.id : '', events: pk.drain().map((e) => e.type + ':' + (e.checkpoint ?? e.frames)).join(',') });
    }
    cases.push({ from: 0, drop, frames });
  }
}
fs.writeFileSync(new URL('../tests/parkour-fixture.json', import.meta.url), JSON.stringify({ fields: FIELDS, weapon: COURSE_WEAPON, cases }));
console.log(`parkour trace: ${cases.length} climbs and set-downs, ${cases.reduce((n, c) => n + c.frames.length, 0)} frames`);
