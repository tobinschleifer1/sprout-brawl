// Walk the real web/src/engine/plaza.js through every scene with scripted and pseudo-random input,
// for tests/plaza-parity.luau: position, speed, hop, facing, state and the station on offer, every
// frame, plus scene changes and warps mid-walk.
import fs from 'node:fs';
import { Plaza } from '../../web/src/engine/plaza.js';
import { MARKET, ROOMS } from '../../web/src/data/plaza.js';
const FIELDS = ['x', 'z', 'y', 'vx', 'vz', 'vy', 'facing', 'state', 'sf'];
const S = (v) => (typeof v === 'number' ? String(v) : v);
const cases = [];
let seed = 11;
const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return Math.floor(seed / 65536) / 32768; };
for (const scene of [MARKET, ...Object.values(ROOMS)]) {
  for (let run = 0; run < 3; run++) {
    const w = new Plaza(scene);
    const frames = [];
    let hold = { x: 0, y: 0, jump: false };
    for (let i = 0; i < 3000; i++) {
      // Past +-1 as well: a gamepad or a hand-built frame can overshoot, and the engine clamps.
      if (i % 35 === 0) hold = { x: [-1, 0, 1, 0.5, -0.3, 1.8][Math.floor(rnd() * 6)], y: [-1, 0, 1, 0.7, -2.5][Math.floor(rnd() * 5)], jump: false };
      const input = { x: hold.x, y: hold.y, jump: rnd() < 0.02 };
      let event = '';
      if (i === 1500 && scene.warps.length) { event = 'warp:' + scene.warps[run % scene.warps.length].id; w.warp(scene.warps[run % scene.warps.length].id); }
      if (i === 2200) { event = 'scene'; w.setScene(scene); }
      w.step(input);
      const near = w.nearest(), d = w.district();
      frames.push({ input, event, values: FIELDS.map((k) => S(w.p[k])), near: near ? near.id : '', district: d ? d.id : '' });
    }
    cases.push({ scene: scene.id, frames });
  }
}
// Scripted edges the random walks almost never land on exactly.
//  - Along a cabinet's side, exactly on its edge: footprints are open at their edges, so this passes.
//  - Two stations at exactly the same distance: the first listed wins.
import { CABINETS } from '../../web/src/data/plaza.js';
const scripted = (scene, at, inputs, label) => {
  const w = new Plaza(scene);
  w.setScene(scene, at);
  const frames = inputs.map((input) => {
    w.step(input);
    const near = w.nearest(), d = w.district();
    return { input, event: '', values: FIELDS.map((k) => S(w.p[k])), near: near ? near.id : '', district: d ? d.id : '' };
  });
  cases.push({ scene: scene.id, inline: scene === MARKET ? undefined : scene, at, label, frames });
};
const c = CABINETS[0];
scripted(MARKET, { x: c.x - 3, z: c.z - 3 }, Array.from({ length: 90 }, () => ({ x: 0, y: 1, jump: false })), 'along a cabinet edge');
const tie = { ...ROOMS.Duel, id: 'TieScene', stations: [
  { id: 'first', kind: 'Maps', x: -2, z: 9, rx: 5, rz: 5 }, { id: 'second', kind: 'Rules', x: 2, z: 9, rx: 5, rz: 5 } ] };
scripted(tie, { x: 0, z: 9 }, Array.from({ length: 5 }, () => ({ x: 0, y: 0, jump: false })), 'equidistant stations');
fs.writeFileSync(new URL('../tests/plaza-fixture.json', import.meta.url), JSON.stringify({ fields: FIELDS, cases }));
console.log(`plaza trace: ${cases.length} walks, ${cases.reduce((n, c) => n + c.frames.length, 0)} frames`);
