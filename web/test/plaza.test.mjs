// The rooftop lobby: can you get everywhere, and nowhere you should not be?
import { MARKET, ROOMS, WALK, MESSAGES, STAMPS, CABINETS } from '../src/data/plaza.js';
import { Plaza, walkable } from '../src/engine/plaza.js';
import { emptyFrame } from '../src/engine/input.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };
const SCENES = [MARKET, ...Object.values(ROOMS)];
const frame = (x, y, jump = false) => ({ ...emptyFrame(), x, y, jump });

// Walk to a point the way a player would: to the bridge line, along the street, then into depth.
function walkTo(w, tx, tz) {
  const legs = [[null, 9], [tx, null], [null, tz], [tx, null]];
  for (const [lx, lz] of legs) {
    for (let n = 0; n < 4000; n++) {
      const dx = lx === null ? 0 : lx - w.p.x, dz = lz === null ? 0 : lz - w.p.z;
      if (Math.abs(dx) < 0.3 && Math.abs(dz) < 0.3) break;
      w.step(frame(Math.abs(dx) < 0.3 ? 0 : Math.sign(dx), Math.abs(dz) < 0.3 ? 0 : Math.sign(dz)));
    }
  }
  for (let n = 0; n < 30; n++) w.step(frame(0, 0));      // settle
}

// ---- 1. every station is reachable on foot from spawn, and is the one you would use there ----
{
  const bad = [];
  let n = 0;
  for (const scene of SCENES) for (const s of scene.stations) {
    const w = new Plaza(scene);
    walkTo(w, s.x, s.z);
    const near = w.nearest();
    if (!near || near.id !== s.id) bad.push(`${scene.id}/${s.id}: walked to (${w.p.x.toFixed(1)}, ${w.p.z.toFixed(1)}), nearest is ${near && near.id}`);
    n++;
  }
  check('every station can be walked to from spawn and is the one offered there', bad.length === 0,
    bad.length ? bad.slice(0, 6).join('; ') : `${n} stations across ${SCENES.length} scenes, including all ${CABINETS.length * 2} cabinet seats`);
}

// ---- 2. nobody leaves the floor or walks into a footprint, whatever they press ----
{
  let seed = 3, bad = null, frames = 0;
  const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return Math.floor(seed / 65536) / 32768; };
  for (const scene of SCENES) {
    const w = new Plaza(scene);
    let hold = frame(0, 0);
    for (let i = 0; i < 20000; i++) {
      if (i % 40 === 0) hold = frame(Math.round(rnd() * 2 - 1), Math.round(rnd() * 2 - 1), rnd() < 0.1);
      w.step(hold);
      frames++;
      if (!walkable(scene, w.p.x, w.p.z)) { bad = `${scene.id} frame ${i}: standing at (${w.p.x}, ${w.p.z})`; break; }
      if (w.p.y < 0) { bad = `${scene.id}: below the floor`; break; }
    }
    if (bad) break;
  }
  check('random walking never leaves the floor or enters a cabinet or kiosk', !bad, bad || `${frames} frames of random input across every scene`);
}

// ---- 2b. a cabinet is solid: walking into one stops at its edge (checked against the footprint
//          itself, not through walkable(), which the engine also uses) ----
{
  const bad = [];
  const c = CABINETS[0];
  const w = new Plaza(MARKET);
  walkTo(w, c.x - 8, c.z);
  for (let i = 0; i < 120; i++) w.step(frame(1, 0));
  const inFoot = (x, z) => MARKET.blocks.some((r) => x > r.x1 && x < r.x2 && z > r.z1 && z < r.z2);
  if (inFoot(w.p.x, w.p.z)) bad.push(`walked into cabinet 1, at x ${w.p.x.toFixed(2)}`);
  if (w.p.x < c.x - 3.5) bad.push(`stopped short of cabinet 1, at x ${w.p.x.toFixed(2)}`);
  const k = new Plaza(MARKET);
  walkTo(k, 0, 9);
  for (let i = 0; i < 120; i++) k.step(frame(0, 1));
  if (inFoot(k.p.x, k.p.z) || k.p.z > 12.01) bad.push(`walked into the kiosk, at z ${k.p.z.toFixed(2)}`);
  check('the cabinets and the kiosk are solid', bad.length === 0, bad.length ? bad.join('; ') : `stopped at x ${w.p.x.toFixed(2)} against cabinet 1 (edge ${c.x - 3}) and at z ${k.p.z.toFixed(2)} against the kiosk`);
}

// ---- 2c. the nearer of two reachable stations wins, and nothing is used mid-hop ----
{
  const scene = { ...ROOMS.Duel, stations: [
    { id: 'far', kind: 'Maps', x: 0, z: 9, rx: 6, rz: 6 }, { id: 'near', kind: 'Rules', x: 3, z: 9, rx: 6, rz: 6 } ] };
  const w = new Plaza(scene);
  w.setScene(scene, { x: 2.5, z: 9 });
  const first = w.nearest() && w.nearest().id;
  w.setScene(scene, { x: 0.5, z: 9 });
  const second = w.nearest() && w.nearest().id;
  w.step(frame(0, 0, true));
  w.step(frame(0, 0));
  const hopping = w.nearest();
  check('the nearest reachable station is offered, and none while hopping', first === 'near' && second === 'far' && hopping === null,
    `at x 2.5: ${first}; at x 0.5: ${second}; mid-hop: ${hopping && hopping.id}`);
}

// ---- 3. the bridges are the only way across the gaps ----
{
  const bad = [];
  const gaps = [[-90, 'tailor/square'], [90, 'square/arcade'], [190, 'arcade/gates']];
  for (const [x, name] of gaps) {
    if (!walkable(MARKET, x, 9)) bad.push(`${name}: no bridge at z 9`);
    for (const z of [3, 5, 13, 16]) if (walkable(MARKET, x, z)) bad.push(`${name}: open gap at z ${z}`);
  }
  // And walking straight across off the bridge line stops at the edge.
  const w = new Plaza(MARKET);
  walkTo(w, 70, 3);
  for (let i = 0; i < 300; i++) w.step(frame(1, 0));
  if (w.p.x > 85) bad.push(`walked off the front of Neon Square to x ${w.p.x}`);
  check('districts join only by their plank bridges', bad.length === 0, bad.length ? bad.join('; ') : 'three gaps, each crossable at the bridge and a sheer drop either side of it');
}

// ---- 4. sliding: running diagonally into a wall keeps moving along it ----
{
  const w = new Plaza(MARKET);
  walkTo(w, -60, 17.5);
  const x0 = w.p.x;
  for (let i = 0; i < 60; i++) w.step(frame(1, 1));
  check('running diagonally into the back wall slides along it', w.p.x > x0 + 10 && w.p.z <= 18,
    `from x ${x0.toFixed(1)} to ${w.p.x.toFixed(1)} in a second, pinned at depth ${w.p.z.toFixed(2)}`);
}

// ---- 5. the lobby is harmless: only direction and hop are read ----
{
  const a = new Plaza(MARKET), b = new Plaza(MARKET);
  for (let i = 0; i < 600; i++) {
    const base = frame(i < 300 ? 1 : -1, i % 120 < 60 ? 1 : -1, i % 97 === 0);
    a.step(base);
    b.step({ ...base, light: true, heavy: true, ult: true, guard: true, grab: true, dodge: true, pickup: true, taunt: true });
  }
  check('pressing every combat button changes nothing in the lobby', JSON.stringify(a.p) === JSON.stringify(b.p),
    `after 600 frames: (${a.p.x.toFixed(2)}, ${a.p.z.toFixed(2)}) both ways`);
}

// ---- 6. the hop lands, facing follows the stick, states follow the motion ----
{
  const w = new Plaza(MARKET);
  const seen = new Set();
  let peak = 0;
  w.step(frame(0, 0, true));
  for (let i = 0; i < 120; i++) { w.step(frame(-1, 0)); peak = Math.max(peak, w.p.y); seen.add(w.p.state); }
  for (let i = 0; i < 60; i++) { w.step(frame(0, 0)); seen.add(w.p.state); }
  check('a hop goes up and lands; facing and state follow the stick', peak > 2 && w.p.y === 0 && w.p.facing === -1 && seen.has('air') && seen.has('run') && seen.has('idle') && w.p.state === 'idle',
    `peak ${peak.toFixed(2)} studs, landed, facing ${w.p.facing}, states ${[...seen].join('/')}`);
}

// ---- 7. warps, spawns, words and stamps ----
{
  const bad = [];
  for (const scene of SCENES) {
    if (!walkable(scene, scene.spawn.x, scene.spawn.z)) bad.push(`${scene.id} spawn is not on the floor`);
    for (const wp of scene.warps) {
      const w = new Plaza(scene);
      if (!w.warp(wp.id) || w.p.x !== wp.x || w.p.z !== wp.z) bad.push(`${scene.id}: warp ${wp.id} did not land`);
      if (!walkable(scene, wp.x, wp.z)) bad.push(`${scene.id}: warp ${wp.id} is off the floor`);
      if (!w.district()) bad.push(`${scene.id}: warp ${wp.id} is in no district`);
    }
  }
  for (const m of MESSAGES) if (m.length > 20) bad.push(`message too long for a bubble: ${m}`);
  if (new Set(MESSAGES).size !== MESSAGES.length) bad.push('a quick message is listed twice');
  for (const s of STAMPS) {
    const w = s.rows[0].length;
    if (s.rows.some((r) => r.length !== w)) bad.push(`stamp ${s.id} has ragged rows`);
    for (const r of s.rows) for (const ch of r) if (ch !== '.' && !s.ink[ch]) bad.push(`stamp ${s.id}: no ink '${ch}'`);
  }
  check('warps land on the floor in a district; messages fit a bubble; stamps are well formed', bad.length === 0,
    bad.length ? bad.slice(0, 6).join('; ') : `${MARKET.warps.length} warps, ${MESSAGES.length} messages, ${STAMPS.length} stamps`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
