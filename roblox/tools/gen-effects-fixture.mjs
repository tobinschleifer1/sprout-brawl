// Every effect event, and the per-frame dirt and orb sparks, spawned from the same random numbers
// and stepped; the state and the shapes at each step, for tests/effects-parity.luau.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const { newEffects, spawnEffect, stepEffect, effectShapes, dragDirt, orbSparks } = await import('../../web/src/render2d/effects.js');

// the random numbers, as strings so the Luau reads the same doubles
let seed = 12345;
const pool = [];
for (let i = 0; i < 20000; i++) { seed = (seed * 1103515245 + 12345) % 2147483648; pool.push(seed / 2147483648); }
let at = 0;
const rand = () => pool[at++];
const glows = ['#B77DFF', null, '#7DE8FF', '#FFD37A'];
const glow = (i) => glows[i] ?? null;
const heights = [4.8, 5.2, 5.6, 4.4];
const height = (i) => heights[i] ?? 5;

const E = (type, extra = {}) => ({ type, x: 3.25, y: 7.5, ...extra });
const cases = [
  ['light hit', [E('hit', { attacker: 0 })]], ['heavy hit', [E('hit', { attacker: 2, heavy: true })]],
  ['hit by glowless', [E('hit', { attacker: 1, heavy: true })]], ['explosion', [E('explosion', { radius: 4.5 }), E('explosion')]],
  ['block', [E('block'), E('block', { perfect: true, victim: 2 }), E('block', { victim: 0 })]], ['ko', [E('ko', { fighter: 5 })]],
  ['projectile', [E('projectile'), E('beam')]], ['land', [E('land'), E('land', { hard: true })]],
  ['ultimate', [E('ultimate', { fighter: 0 }), E('ultready')]], ['soulescape', [E('soulescape')]],
  ['crater', [E('crater', { first: true, radius: 3.2 }), E('crater', { radius: 2 })]],
  ['rundown', [E('rundown'), E('rundown', { last: true })]], ['upheaval', [E('upheaval')]],
  ['heartseeker', [E('heartseeker')]], ['anchor', [E('anchorset'), E('anchorsnap')]],
  ['aegis', [E('aegis'), E('aegisbreak')]], ['bleed', [E('bleedmark'), E('exsanguinate', { marks: 15 }), E('exsanguinate', { marks: 3 })]],
  ['soul', [E('soulgrab'), E('soulorb'), E('soulorb'), E('soulorb'), E('soulburst', { radius: 5 })]],
  ['snipe', [E('snipe'), E('starfall'), E('mark')]], ['misc', [E('counter'), E('freeze'), E('summonbreak'), E('nothing')]],
  ['movement', [E('jump', { fighter: 1 }), E('doublejump', { fighter: 2 }), E('dash', { fighter: 0 }), E('dodge', { fighter: 3 }), E('ledge', { fighter: 0 }), E('land', { fighter: 2 }), E('land', { fighter: 9 })]],
  ['new impacts', [E('tech', { fighter: 0 }), E('shieldbreak', { fighter: 1 }), E('grabhit'), E('itembreak'), E('projectilebreak'), E('spring'), E('teleport'), E('pickup')]],
];
const S = (v) => (typeof v === 'number' ? String(v) : v === null ? null : v);
const dump = (fx) => ({
  parts: fx.parts.map((p) => [p.x, p.y, p.vx, p.vy, p.life, p.max, p.c, p.s].map(S)),
  rings: fx.rings.map((r) => [r.x, r.y, r.r, r.life, r.max, r.c, r.heavy, r.rot].map(S)),
  shake: S(fx.shake),
  shields: Object.keys(fx.shields).sort().map((k) => [k, S(fx.shields[k].life), S(fx.shields[k].x), S(fx.shields[k].y)]),
  shapes: effectShapes(fx).map((sh) => sh.map(S)),
});
const out = [];
for (const [name, events] of cases) {
  const start = at;
  const fx = newEffects();
  for (const e of events) spawnEffect(fx, e, glow, rand, height);
  const steps = [dump(fx)];
  for (const dt of [1 / 60, 0.05, 0.1, 0.2]) { stepEffect(fx, dt); steps.push(dump(fx)); }
  out.push({ name, events, start, steps });
}
// the per-frame emitters
{
  const start = at;
  const fx = newEffects();
  for (let i = 0; i < 40; i++) {
    dragDirt(fx, 1.5 + i * 0.1, 0, i % 2 ? 1 : -1, 12.5, (i % 5) / 4, '#556070', rand);
    orbSparks(fx, -2, 6, i % 2 ? 30 : -30, i % 3 ? '#FF00AA' : null, rand);
  }
  const steps = [dump(fx)];
  stepEffect(fx, 0.1); steps.push(dump(fx));
  out.push({ name: 'dirt and orb sparks', emitters: true, start, steps });
}
fs.writeFileSync(path.join(HERE, '../tests/effects-fixture.json'), JSON.stringify({ pool: pool.slice(0, at).map(String), glows, heights, cases: out }));
console.log(`effects fixture: ${out.length} cases, ${at} random numbers`);
