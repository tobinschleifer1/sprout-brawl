// Stage geometry, checked against what a fighter can actually do.
//
// A platform-fighter map is only as good as its distances, and distances are only meaningful
// relative to the movement envelope: how high a double jump reaches, how far a run-off jump
// carries, how far a recovery travels. All three are MEASURED by running the engine, not derived
// from the constants, so retuning a weapon's jump or recovery re-scores every map automatically.
import { makeMatch, skipCountdown } from './harness.mjs';
import { STAGES } from '../src/data/stages/index.js';
import { WEAPONS } from '../src/data/weapons/index.js';
import { StageRuntime } from '../src/engine/stage.js';
import { RESPAWN } from '../src/config.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };
const EMPTY_IN = { x: 0, y: 0, jump: false, light: false, heavy: false, dodge: false, guard: false,
  grab: false, taunt: false, pickup: false, jumpHeld: false, guardHeld: false, heavyHeld: false,
  lightHeld: false, downTap: false, anyPress: false };

// ---------------------------------------------------------------- movement envelope ----
// Fly a fighter with a scripted input and report how far it got.
function envelope(weaponId) {
  const run = (script, frames = 200) => {
    const m = makeMatch({ loadouts: [['Classic', weaponId], ['Noir', weaponId]], stageId: 'TheSpan' });
    skipCountdown(m);
    for (let i = 0; i < 200; i++) m.step();
    const f = m.fighters[0];
    f.x = 0; f.y = 0; f.vx = 0; f.vy = 0; f.onGround = true; f.platform = m.stage.main; f.setState('idle');
    f.jumpsLeft = f.char.jumps; f.recoveryUsed = false;
    m.fighters[1].x = 70; m.fighters[1].invincible = 99999;
    let maxY = 0, maxX = 0;
    for (let i = 0; i < frames; i++) {
      m._input.set('p0', Object.assign({}, EMPTY_IN, script(i, f)));
      m.step();
      maxY = Math.max(maxY, f.y);
      maxX = Math.max(maxX, Math.abs(f.x));
      if (f.onGround && i > 20) break;
    }
    return { maxY, maxX };
  };

  // straight up: jump, then double jump at the apex
  const up = run((i, f) => (i === 0 || (i > 26 && i < 29)) ? { jump: true, jumpHeld: true } : { jumpHeld: true });
  // run off and jump: full horizontal reach with both jumps and air drift
  const across = run((i, f) => {
    const o = { x: 1 };
    if (i === 0 || (i > 26 && i < 29)) { o.jump = true; o.jumpHeld = true; } else o.jumpHeld = true;
    return o;
  });
  // recovery: fall, then use the up-special
  const rec = run((i, f) => {
    if (i < 6) return { x: 1 };
    if (i === 8) return { x: 1, heavy: true, heavyHeld: true, y: 1 };
    return { x: 1 };
  });
  return { jumpHeight: up.maxY, jumpDistance: across.maxX, recoveryDistance: rec.maxX };
}

const ENV = {};
for (const w of WEAPONS) ENV[w.id] = envelope(w.id);
const worst = {
  jumpHeight: Math.min(...WEAPONS.map((w) => ENV[w.id].jumpHeight)),
  jumpDistance: Math.min(...WEAPONS.map((w) => ENV[w.id].jumpDistance)),
};

console.log('MOVEMENT ENVELOPE (measured by flying each weapon)');
console.log('  weapon     double-jump height   run-off jump reach');
for (const w of WEAPONS) {
  const e = ENV[w.id];
  console.log(`  ${w.id.padEnd(10)} ${e.jumpHeight.toFixed(1).padStart(10)} studs ${e.jumpDistance.toFixed(1).padStart(16)} studs`);
}
console.log(`  worst case: ${worst.jumpHeight.toFixed(1)} up, ${worst.jumpDistance.toFixed(1)} across\n`);

// ---------------------------------------------------------------- per-stage geometry ----
function geometry(data) {
  const st = new StageRuntime(data);
  const solids = st.solids.map((s) => ({ id: s.id, x1: s.x1, x2: s.x2, top: s.top }))
    .sort((a, b) => a.x1 - b.x1);
  // horizontal gaps between solid islands at floor level
  const gaps = [];
  for (let i = 1; i < solids.length; i++) {
    if (Math.abs(solids[i].top - solids[i - 1].top) > 6) continue;   // different tiers, not a gap
    const g = solids[i].x1 - solids[i - 1].x2;
    if (g > 0.5) gaps.push({ from: solids[i - 1].id, to: solids[i].id, width: g });
  }
  const shelves = st.platforms.filter((p) => !p.solid);
  return { st, solids, gaps, shelves };
}

console.log('STAGE GEOMETRY');
for (const data of STAGES) {
  const { st, solids, gaps, shelves } = geometry(data);
  const b = st.blast, m = st.main;
  const width = Math.max(...solids.map((s) => s.x2)) - Math.min(...solids.map((s) => s.x1));
  console.log(`  ${data.name} — ${data.archetype}`);
  console.log(`    playable width ${width.toFixed(0)}   solids ${solids.length}   shelves ${shelves.length}   ledges ${st.ledges.length}   hazards ${data.hazards.length}`);
  console.log(`    blast: side ${(b.right - m.x2).toFixed(0)}/${(m.x1 - b.left).toFixed(0)} from the ledges, ceiling ${b.top}, floor ${b.bottom}`);
  if (gaps.length) console.log(`    gaps: ${gaps.map((g) => `${g.width.toFixed(0)} studs (${g.from}->${g.to})`).join(', ')}`);
  console.log(`    shelf heights: ${shelves.map((p) => p.top.toFixed(0)).join(', ') || '(none)'}`);
}
console.log();

// ---- 1. every shelf must be reachable from the ground below it ----
for (const data of STAGES) {
  const { st, shelves } = geometry(data);
  const unreachable = [];
  for (const p of shelves) {
    // the highest solid or shelf underneath this one is what you jump from
    let floor = -Infinity;
    for (const q of st.platforms) {
      if (q === p || q.top >= p.top - 0.5) continue;
      if (q.x2 < p.x1 - 6 || q.x1 > p.x2 + 6) continue;
      floor = Math.max(floor, q.top);
    }
    if (floor === -Infinity) floor = st.main.top;
    const climb = p.top - floor;
    if (climb > worst.jumpHeight) unreachable.push(`${p.id} needs ${climb.toFixed(1)} of ${worst.jumpHeight.toFixed(1)}`);
  }
  check(`${data.name}: every shelf is reachable`, unreachable.length === 0,
    unreachable.length ? unreachable.join('; ') : `${shelves.length} shelves, all within a double jump of the ground under them`);
}

// ---- 2. gaps in the floor must be crossable, but not free ----
for (const data of STAGES) {
  const { gaps } = geometry(data);
  if (!gaps.length) { check(`${data.name}: floor gaps`, true, 'no floor gaps — a continuous island'); continue; }
  const tooWide = gaps.filter((g) => g.width > worst.jumpDistance * 0.85);
  const trivial = gaps.filter((g) => g.width < 6);
  check(`${data.name}: floor gaps are crossable and meaningful`, tooWide.length === 0 && trivial.length === 0,
    tooWide.length ? `TOO WIDE: ${tooWide.map((g) => g.width.toFixed(0)).join(', ')} vs a ${worst.jumpDistance.toFixed(0)} jump`
      : trivial.length ? `TRIVIAL: ${trivial.map((g) => g.width.toFixed(0)).join(', ')} — a gap under 6 studs is a step, not a decision`
      : gaps.map((g) => `${g.width.toFixed(0)} studs (${(g.width / worst.jumpDistance * 100).toFixed(0)}% of a jump)`).join(', '));
}

// ---- 3. spawns must be over solid ground and not on top of each other ----
for (const data of STAGES) {
  const { st } = geometry(data);
  const bad = [];
  data.spawns.forEach((x, i) => {
    const over = st.solids.some((s) => x > s.x1 + 1 && x < s.x2 - 1);
    if (!over) bad.push(`spawn ${i} at x=${x} is over a gap`);
  });
  for (let i = 0; i < 4; i++) for (let j = i + 1; j < 4; j++) {
    if (Math.abs(data.spawns[i] - data.spawns[j]) < 5) bad.push(`spawns ${i} and ${j} are ${Math.abs(data.spawns[i] - data.spawns[j])} apart`);
  }
  check(`${data.name}: spawns are safe and spread`, bad.length === 0,
    bad.length ? bad.join('; ') : `${data.spawns.length} spawns, first four spread across the floor`);
}

// ---- 4. the roster must be genuinely varied, not one shape six times ----
{
  const shapes = STAGES.map((d) => {
    const { solids, gaps, shelves } = geometry(d);
    return `${solids.length}s/${shelves.length}p/${gaps.length}g/${d.hazards.length}h`;
  });
  const dupes = shapes.filter((s, i) => shapes.indexOf(s) !== i);
  check('the stage roster is varied', dupes.length <= 1,
    `${STAGES.length} stages, shapes: ${shapes.join('  ')}${dupes.length > 1 ? '  DUPLICATES: ' + dupes.join(',') : ''}`);
  const archetypes = new Set(STAGES.map((d) => d.archetype));
  check('every stage has a distinct archetype', archetypes.size === STAGES.length,
    [...archetypes].join(', '));
}

// ---- 5. a ranked stage must be hazardless, and there must be at least one ----
{
  const ranked = STAGES.filter((d) => d.ranked);
  const dirty = ranked.filter((d) => d.hazards.length);
  check('ranked stages are hazardless', ranked.length >= 1 && dirty.length === 0,
    ranked.length ? `${ranked.length} ranked (${ranked.map((d) => d.name).join(', ')})${dirty.length ? ' but ' + dirty.map((d) => d.name).join(',') + ' has hazards' : ''}` : 'no ranked stage');
}

// ---- 6. blast zones must be far enough that a ledge-side hit is not an instant KO ----
for (const data of STAGES) {
  const { st, solids } = geometry(data);
  const leftEdge = Math.min(...solids.map((s) => s.x1));
  const rightEdge = Math.max(...solids.map((s) => s.x2));
  const l = leftEdge - st.blast.left, r = st.blast.right - rightEdge;
  const ceil = st.blast.top;
  check(`${data.name}: blast zones give room to recover`, l >= 40 && r >= 40 && ceil >= 60,
    `side room ${l.toFixed(0)}/${r.toFixed(0)} studs (want 40+), ceiling ${ceil} (want 60+)`);
}

// ---- 7. a spawn must have ground under it at respawn height ----
// Rooftops shipped a spawn inside a tower's body with no platform below: P4 lost a stock in under
// three seconds with no input, and the "spawns are over solid ground" check above missed it because
// it only tested x, never whether anything existed at the height you actually appear at.
for (const data of STAGES) {
  const { st } = geometry(data);
  const bad = [];
  data.spawns.forEach((x, i) => {
    const under = st.platforms.some((p) => x > p.x1 + 0.5 && x < p.x2 - 0.5 && p.top <= RESPAWN.height + 0.5);
    const insideBody = st.solids.some((sp) => x > sp.x1 && x < sp.x2 && RESPAWN.height < sp.top && RESPAWN.height > sp.bottom);
    if (!under) bad.push(`slot ${i} (x=${x}) has no platform at or below respawn height ${RESPAWN.height}`);
    else if (insideBody) bad.push(`slot ${i} (x=${x}) spawns inside a solid's body`);
  });
  check(`${data.name}: every spawn has ground beneath it`, bad.length === 0,
    bad.length ? bad.join('; ') : `all ${data.spawns.length} spawns land on something`);
}

// ---- 8. the kill curve must be monotonic ----
// Once a launch kills, every harder launch must also kill. A solid sitting in the launch corridor
// breaks this: Rooftops KO'd at 22-32%, then let the victim SURVIVE from 34-128%. Kill percent has
// to be a function of damage, or the stage is lying to the player.
for (const data of STAGES) {
  const results = [];
  for (let pct = 0; pct <= 180; pct += 10) {
    const m = makeMatch({ stageId: data.id, loadouts: [['Classic', 'Sword'], ['Noir', 'Sword']] });
    // Hazards off: this assertion is about the launch CORRIDOR, and a vent or a dust devil killing
    // the victim independently would read as a geometry failure it isn't.
    m.stage.hazards = [];
    skipCountdown(m);
    for (let i = 0; i < 200; i++) m.step();
    const [a, v] = m.fighters;
    // Stand them on the MAIN island, not at world x=0 — on a split-floor stage x=0 is the hole,
    // and "the victim fell in the pit" is not the same thing as "the launch corridor is blocked".
    const mm = m.stage.main;
    const cx = (mm.x1 + mm.x2) / 2;
    a.x = cx - 3; v.x = cx; a.facing = 1; v.facing = -1;
    for (const f of [a, v]) { f.onGround = true; f.platform = mm; f.y = mm.top; f.vx = 0; f.vy = 0; f.invincible = 0; }
    v.setState('idle'); v.percent = pct;
    a.setState('idle'); a.startMove('SigSide');
    let died = false;
    for (let i = 0; i < 260; i++) { m.step(); if (!v.alive) { died = true; break; } }
    results.push({ pct, died });
  }
  // Below 80% a death can be legitimate stage character - falling into Smeltworks' pit at 0% is
  // the pit doing its job. What must never happen is a launch at KILL percent being caught by
  // geometry while a weaker one killed, because then kill percent stops being a function of damage.
  const kill = results.filter((r) => r.pct >= 80);
  const firstKill = kill.findIndex((r) => r.died);
  const survivedAfter = firstKill < 0 ? [] : kill.slice(firstKill).filter((r) => !r.died).map((r) => r.pct + '%');
  const low = results.filter((r) => r.pct < 80 && r.died).map((r) => r.pct + '%');
  check(`${data.name}: kill percent rises with damage`, firstKill >= 0 && survivedAfter.length === 0,
    firstKill < 0 ? 'a centre-stage side signature never KOs at 80-180% — nothing on this stage can close a stock sideways'
      : survivedAfter.length ? `KOs from ${kill[firstKill].pct}% but SURVIVES at ${survivedAfter.join(', ')} — geometry is catching launches at kill percent`
      : `monotonic from ${kill[firstKill].pct}% up${low.length ? `; low-percent deaths at ${low.join(', ')} (stage hazard geometry)` : ''}`);
}

// ---- 7. every stage runs a full bot match without breaking ----
{
  const bad = [];
  for (const data of STAGES) {
    const m = makeMatch({ mode: 'StockFFA', stocks: 1, stageId: data.id,
      loadouts: [['Classic', 'Sword'], ['Noir', 'Blasters'], ['Ember', 'Scythe'], ['Moss', 'Grimoire']] });
    m.itemsOn = true;
    m.fighters.forEach((f) => { f.isBot = true; f.botLevel = 'hard'; });
    skipCountdown(m);
    let n = 0;
    while (m.state !== 'results' && n < 60 * 300) {
      m.step(); n++;
      for (const f of m.fighters) if (![f.x, f.y, f.vx, f.vy, f.percent].every(Number.isFinite)) { bad.push(`${data.id}: non-finite`); n = 1e9; break; }
    }
    if (m.state !== 'results') bad.push(`${data.id}: unfinished after 5 min`);
  }
  check('every stage plays a full 4-player match', bad.length === 0,
    bad.length ? bad.join('; ') : `${STAGES.length} stages x 4 fighters, all reached a result with no NaN`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
