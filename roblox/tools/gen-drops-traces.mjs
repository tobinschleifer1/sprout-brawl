// Record matches with weapon drops (DROPS in web/src/config.js), for tests/drops-parity.luau.
//
//     node tools/gen-drops-traces.mjs
//
// What a drop match adds to a plain one: drops falling, landing and fading on the match's seed;
// fighters on fists, arming with the next of their two weapons, throwing, the thrown weapon
// hitting and landing as a drop; a stock lost with a weapon in hand. So every frame records the
// drops, the thrown weapons in flight, each fighter's hands (armed, nextArm, the weapon, and what
// a weapon decides - size, weight, jumps, its mechanic) and the drop events.
//
// Scenarios are scripted: `ops` act on a chosen frame (write a field, put a drop somewhere), and
// `script` is each fighter's input frame by frame. The brawl's inputs come from a seeded generator
// here and are written into the trace, so the Luau replays exactly the same presses.
//
// Numbers are strings. See tools/gen-traces.mjs.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const { Match } = await import('../../web/src/engine/match.js');
const { STAGES } = await import('../../web/src/data/stages/index.js');
const { buildArmed } = await import('../../web/src/data/loadout.js');
const { emptyFrame } = await import('../../web/src/engine/input.js');
const { ITEMS } = await import('../../web/src/data/items.js');

const n = (v) => (typeof v === 'number' ? String(v) : v === undefined ? null : v);

function run(spec) {
  const data = STAGES.find((s) => s.id === spec.stage);
  let current = {};
  const input = { kb2Active: false, poll() {}, get(source) { return current[source] || emptyFrame(); } };
  const m = new Match({
    mode: spec.mode || 'StockFFA', stage: data, input, seed: spec.seed, stocks: spec.stocks ?? 3, weaponDrops: true,
    fighters: spec.who.map(([a, ws], i) => ({ ...buildArmed(a, ws), skin: 0, team: i, source: `p${i}`, isBot: false, name: `P${i}` })),
  });
  const rows = [];
  for (let frame = 0; frame < spec.frames; frame++) {
    for (const op of (spec.ops && spec.ops[frame]) || []) {
      if (op.set) for (const [k, kv] of Object.entries(op.set)) Object.assign(m.fighters[Number(k)], kv);
      if (op.drop) m.combat.spawnDrop(op.drop[0], op.drop[1]);
      if (op.dropAt != null) { const f = m.fighters[op.dropAt]; m.combat.spawnDrop(f.x + (op.dx || 0), f.y + 0.5); }
      if (op.item) { const f = m.fighters[op.item[0]]; m.combat.spawnItem(ITEMS[op.item[1]], f.x, f.y + 0.5); }
      if (op.proj) { const p = m.combat.projectiles.find((q) => q.weaponDrop); if (p) Object.assign(p, op.proj); }
    }
    current = {};
    for (let k = 0; k < m.fighters.length; k++) {
      const s = spec.script[frame] && spec.script[frame][k];
      current[`p${k}`] = Object.assign(emptyFrame(), s || {});
    }
    m.events.length = 0;
    m.step();
    const row = [m.state, n(m.combat.dropTimer)];
    row.push(m.combat.drops.map((d) => [n(d.x), n(d.y), n(d.vx), n(d.vy), String(d.onGround), n(d.life), d.look]));
    row.push(m.combat.projectiles.filter((p) => p.weaponDrop).map((p) => [n(p.x), n(p.y), n(p.vx), n(p.vy), n(p.life), p.weaponDrop]));
    for (const f of m.fighters) {
      row.push([n(f.x), n(f.y), n(f.vx), n(f.vy), f.state, f.moveId, n(f.mf), n(f.armed), n(f.nextArm), f.char.weapon.id,
        n(f.r), n(f.h), n(f.weight), n(f.jumpsLeft), n(f.percent), n(f.stocks), f.mech.id ?? null, n(f.ultCharge)]);
    }
    row.push(m.events.filter((e) => ['dropspawn', 'droptake', 'dropgone', 'arm', 'throwweapon', 'ultdenied', 'ko', 'respawn', 'pickup', 'bounce'].includes(e.type))
      .map((e) => [e.type, n(e.fighter), e.weapon ?? null, n(e.slot), e.reason ?? null]));
    rows.push(row);
    if (m.state === 'results') break;
  }
  return rows;
}

// A seeded stream for the brawl's inputs (not the match's own generator, which the match owns).
function lcg(seed) {
  let s = seed >>> 0;
  return () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296; };
}
const press = (f, k) => ({ [k]: true, anyPress: true });

const S = [];
const TWO = [['Classic', ['Sword', 'Gauntlets']], ['Noir', ['Hammer', 'Daggers']]];

// 1. Nobody touches anything: drops fall from DROPS.firstAt, every spawnEvery, up to the cap, and
//    fade after despawnAfter seconds on the ground - all on seed 11.
S.push({ name: 'drops fall, cap and fade', stage: 'FoundryFloor', seed: 11, who: TWO, frames: 1900, script: [], ops: {} });

// 2. Arm, throw, hit, land, re-arm with the other weapon; then jump, arm and throw in the air.
{
  const script = [], ops = {};
  const at = (f, k, inp) => { (script[f] ||= [])[k] = inp; };
  for (let f = 0; f < 6; f++) { at(f + 212, 0, { anyPress: true }); at(f + 212, 1, { anyPress: true }); }
  ops[300] = [{ set: { 0: { x: -4, vx: 0 }, 1: { x: 4, vx: 0, percent: 40 } } }, { drop: [-4, 1] }];
  at(320, 0, press(0, 'pickup'));
  at(340, 0, press(0, 'pickup'));                      // throw the sword at P1
  ops[420] = [{ set: { 0: { x: 1, vx: 0 } } }];        // stand where it landed (near P1)
  at(430, 0, press(0, 'pickup'));                      // re-arm: the gauntlets
  at(460, 0, press(0, 'pickup'));                      // and throw them
  ops[560] = [{ drop: [-10, 1] }, { set: { 0: { x: -10, vx: 0 } } }];
  at(570, 0, press(0, 'jump'));
  ops[585] = [{ set: { 0: {} } }];
  for (let f = 586; f < 600; f++) at(f, 0, { x: 0 });
  at(578, 0, press(0, 'pickup'));                      // in the air over the drop
  at(590, 0, press(0, 'pickup'));                      // throw in the air
  at(620, 0, press(0, 'ult'));                         // unarmed ultimate: denied
  at(650, 0, press(0, 'jump'));                        // and arm in the air: a drop where P0 is, mid-jump
  ops[660] = [{ dropAt: 0 }];
  at(660, 0, press(0, 'pickup'));
  at(680, 0, press(0, 'pickup'));                      // throw on the way down: lands mid-throw, still throws
  S.push({ name: 'arm, throw, re-arm, in the air', stage: 'FoundryFloor', seed: 3, who: TWO, frames: 800, script, ops });
}

// 3. A stock lost with a weapon in hand: back on fists.
{
  const script = [], ops = {};
  const at = (f, k, inp) => { (script[f] ||= [])[k] = inp; };
  for (let f = 0; f < 6; f++) at(f + 212, 0, { anyPress: true });
  ops[300] = [{ set: { 0: { x: -4, vx: 0 } } }];
  ops[350] = [{ dropAt: 0 }];
  at(360, 0, press(0, 'pickup'));                      // standing by now, so this arms
  ops[380] = [{ set: { 0: { x: 400 } } }];
  S.push({ name: 'KO with a weapon in hand', stage: 'FoundryFloor', seed: 5, who: TWO, frames: 600, script, ops });
}

// 4. Reach and items: a drop just out of reach (3.2 studs off, past DROPS.reach's 3) is not taken,
//    one just inside it (2.9) is; armed with an item in reach, pickup takes the item, not a throw;
//    holding it, pickup throws the weapon.
{
  const script = [], ops = {};
  const at = (f, k, inp) => { (script[f] ||= [])[k] = inp; };
  for (let f = 0; f < 6; f++) at(f + 212, 0, { anyPress: true });
  ops[300] = [{ set: { 0: { x: -6, vx: 0 } } }];
  ops[350] = [{ dropAt: 0, dx: 3.2 }];
  at(370, 0, press(0, 'pickup'));                      // out of reach: nothing
  ops[400] = [{ set: { 0: { x: -6 + 3.2 - 2.9, vx: 0 } } }];
  at(410, 0, press(0, 'pickup'));                      // in reach: armed
  ops[440] = [{ item: [0, 'RivetGun'] }];
  at(460, 0, press(0, 'pickup'));                      // the item, not a throw
  at(490, 0, press(0, 'pickup'));                      // holding it: the throw
  S.push({ name: 'reach and items', stage: 'FoundryFloor', seed: 9, who: TWO, frames: 560, script, ops });
}

// 5. Every weapon's own throw (phase 2): armed, thrown at a fighter 5 studs away with another
//    behind them - the pike goes through both, the shield skips off the floor, the rest land.
for (const w of ['Sword', 'Scythe', 'Blasters', 'Grimoire', 'Axe', 'Pike', 'Gauntlets', 'Hammer', 'Longbow', 'Flail', 'Shield', 'Daggers']) {
  const script = [], ops = {};
  const at = (f, k, inp) => { (script[f] ||= [])[k] = inp; };
  for (let f = 0; f < 6; f++) for (let k = 0; k < 3; k++) at(f + 212, k, { anyPress: true });
  ops[300] = [{ set: { 0: { x: -6, vx: 0, facing: 1 }, 1: { x: -1, vx: 0, percent: 100 }, 2: { x: 3, vx: 0, percent: 50 } } }];
  ops[340] = [{ set: { 0: { x: -6, vx: 0, facing: 1 }, 1: { x: -1, vx: 0 }, 2: { x: 3, vx: 0 } } }, { dropAt: 0 }];
  at(350, 0, press(0, 'pickup'));
  at(360, 0, press(0, 'pickup'));
  S.push({ name: `${w} thrown`, stage: 'FoundryFloor', seed: 13, frames: 520, script, ops,
    who: [['Classic', [w, w]], ['Noir', ['Sword', 'Sword']], ['Ember', ['Sword', 'Sword']]] });
}

// ...and the shield with nobody in the way, so it skips off the floor and lands.
{
  const script = [], ops = {};
  const at = (f, k, inp) => { (script[f] ||= [])[k] = inp; };
  for (let f = 0; f < 6; f++) at(f + 212, 0, { anyPress: true });
  ops[300] = [{ set: { 0: { x: -14, vx: 0, facing: 1 }, 1: { x: 40 } } }];
  ops[340] = [{ set: { 0: { x: -14, vx: 0, facing: 1 } } }, { dropAt: 0 }];
  at(350, 0, press(0, 'pickup'));
  at(360, 0, press(0, 'pickup'));
  S.push({ name: 'Shield skips', stage: 'FoundryFloor', seed: 13, frames: 520, script, ops, who: [['Classic', ['Shield', 'Shield']], ['Noir', ['Sword', 'Sword']]] });
  // and into the SIDE of a solid, below its top, where it stops like anything else (no skip)
  const wall = JSON.parse(JSON.stringify({ script, ops }));
  wall.ops[366] = [{ proj: { x: -36.5, y: -2, vx: 40, vy: -1 } }];
  S.push({ name: 'Shield into a wall', stage: 'FoundryFloor', seed: 13, frames: 520, ...wall, who: [['Classic', ['Shield', 'Shield']], ['Noir', ['Sword', 'Sword']]] });
}

// 6. A brawl: four fighters, eight different weapons (four mechanics among them), seeded random
//    inputs - walking, jumping, lights, heavies, dodges and a lot of pickups - for twenty seconds.
{
  const rnd = lcg(2024);
  const script = [];
  const axis = [0, 0, 0, 0];
  for (let f = 0; f < 1500; f++) {
    script[f] = [];
    for (let k = 0; k < 4; k++) {
      if (rnd() < 0.05) axis[k] = [-1, 0, 1][Math.floor(rnd() * 3)];
      const inp = { x: axis[k], y: rnd() < 0.05 ? (rnd() < 0.5 ? 1 : -1) : 0 };
      const r = rnd();
      if (r < 0.06) Object.assign(inp, press(k, 'pickup'));
      else if (r < 0.10) Object.assign(inp, press(k, 'light'));
      else if (r < 0.12) Object.assign(inp, press(k, 'heavy'));
      else if (r < 0.14) Object.assign(inp, press(k, 'jump'));
      else if (r < 0.15) Object.assign(inp, press(k, 'dodge'));
      script[f][k] = inp;
    }
  }
  S.push({ name: 'four-fighter brawl', stage: 'FoundryFloor', seed: 21, stocks: 3, frames: 1500, script, ops: {},
    who: [['Classic', ['Sword', 'Gauntlets']], ['Noir', ['Pike', 'Scythe']], ['Ember', ['Hammer', 'Blasters']], ['Moss', ['Daggers', 'Axe']]] });
}

const scenarios = S.map((spec) => ({ ...spec, rows: run(spec) }));
fs.writeFileSync(path.join(HERE, '../tests/trace-drops.json'), JSON.stringify({ scenarios }));
const frames = scenarios.reduce((s, x) => s + x.rows.length, 0);
const ev = (t) => scenarios.reduce((s, x) => s + x.rows.reduce((a, r) => a + r[r.length - 1].filter((e) => e[0] === t).length, 0), 0);
console.log(`drops traces: ${scenarios.length} scenarios, ${frames} frames, ${ev('dropspawn')} drops, ${ev('arm')} arms, ${ev('throwweapon')} throws, ${ev('dropgone')} faded`);
