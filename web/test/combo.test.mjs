// Combo validity, asserted against the ENGINE, not against a model of it.
//
// The previous version of this file compared hitstun to startup and called the difference "slack".
// That ignored three things the engine actually does: hitstun ends when a launched victim lands,
// the follow-up has to physically reach, and a spot dodge is invincible on frames 3-14. Ten of the
// twenty routes it certified were escapable in a real match. Everything here now runs the match.
import { WEAPONS } from '../src/data/weapons/index.js';
import { confirmsAt, edges, koPercent } from './balance.mjs';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };
const GRID = [0, 20, 40, 60, 80, 100, 120, 140, 160, 180];

// Where does a signature actually start killing? Used to tell a kill confirm from a damage combo.
function sigKO(w, id) {
  const m = w.moves[id];
  const box = (m.hitboxes || []).find((h) => h.base != null);
  const src = m.summon?.blast || box || m;
  return koPercent(src.base ?? m.base, src.growth ?? m.growth, src.damage ?? m.damage, 100, { angle: m.angle });
}

// Measure every advertised heavy route once; every assertion below reads this table.
// `confirmed` = landed while the victim was still in HITSTUN, i.e. genuinely unescapable.
// `punish`    = landed on the recovery of the dodge they used to escape. A real frame trap and a
//               real option, but a read - and calling it guaranteed is exactly the mistake that
//               shipped ten broken routes in two earlier passes of this system.
const table = new Map();
for (const w of WEAPONS) {
  for (const e of edges(w).filter((x) => x.kind === 'heavy')) {
    const rs = GRID.map((p) => confirmsAt(w.id, e.from, e.dir, e.to, p));
    table.set(`${w.id}|${e.from}|${e.dir}|${e.to}`, {
      e, w, ko: sigKO(w, e.to),
      confirm: GRID.filter((p, i) => rs[i].confirmed),
      punish: GRID.filter((p, i) => rs[i].punish),
    });
  }
}
const rowsFor = (w) => [...table.values()].filter((r) => r.w === w);

// ---- 1. every advertised route does something: a guaranteed confirm, or at least a frame trap ----
for (const w of WEAPONS) {
  const dead = rowsFor(w).filter((r) => !r.confirm.length && !r.punish.length)
    .map((r) => `${r.e.from}-${r.e.dir}->${r.e.to}`);
  check(`${w.id}: no advertised cash-out is inert`, dead.length === 0,
    dead.length ? `DEAD: ${dead.join(', ')}` : `${rowsFor(w).length} routes, each either guaranteed or a frame trap against a dodge`);
}

// ---- 2. every weapon has a real KILL CONFIRM: unescapable at a percent where the follow-up kills --
for (const w of WEAPONS) {
  const kills = rowsFor(w).filter((r) => r.ko != null && r.confirm.some((p) => p >= r.ko - 20));
  check(`${w.id}: has a guaranteed kill confirm`, kills.length > 0,
    kills.length
      ? kills.map((r) => `${w.moves[r.e.from].label}->${w.moves[r.e.to].label} confirms ${r.confirm[0]}-${r.confirm[r.confirm.length - 1]}%, KOs ${r.ko}%`).join('; ')
      : 'every route to a killing signature is escapable - the weapon cannot close a stock on a confirm');
}

// ---- 3. the early game stays a read: nothing is guaranteed into a kill below 60% ----
for (const w of WEAPONS) {
  const early = rowsFor(w).filter((r) => r.ko != null && r.ko <= 60 && r.confirm.includes(0));
  check(`${w.id}: no guaranteed kill from 0%`, early.length === 0,
    early.length ? `DEGENERATE: ${early.map((r) => r.e.from + '->' + r.e.to).join(', ')}` : 'low percent is poking and reads, as intended');
}

// ---- 4. chain graphs stay acyclic ----
for (const w of WEAPONS) {
  const adj = {};
  for (const e of edges(w)) (adj[e.from] ||= []).push(e.to);
  const seen = {}, stack = {};
  let cycle = null;
  const walk = (n, path) => {
    if (stack[n]) { cycle = [...path, n].join(' -> '); return true; }
    if (seen[n]) return false;
    seen[n] = stack[n] = true;
    for (const t of adj[n] || []) if (walk(t, [...path, n])) return true;
    stack[n] = false; return false;
  };
  for (const n of Object.keys(adj)) if (!seen[n] && walk(n, [])) break;
  check(`${w.id}: chain graph is acyclic`, !cycle, cycle ? `INFINITE: ${cycle}` : `${Object.keys(adj).length} chaining moves, every branch terminates`);
}

// ---- 5. declared frame data must match the hitbox windows that actually drive the engine ----
for (const w of WEAPONS) {
  const bad = [];
  for (const [id, m] of Object.entries(w.moves)) {
    for (const h of m.hitboxes || []) {
      if (h.frames[0] < m.startup + 1 || h.frames[1] > m.startup + m.active) {
        bad.push(`${id} ${JSON.stringify(h.frames)} vs active window [${m.startup + 1},${m.startup + m.active}]`);
      }
    }
  }
  check(`${w.id}: declared startup/active matches every hitbox window`, bad.length === 0,
    bad.length ? bad.join('; ') : `${Object.keys(w.moves).length} moves consistent - onBlock, chainGap and VFX timing all read the declared numbers`);
}

// ---- 6. no two weapons share an identical move in any slot ----
{
  const SLOTS = ['AirNeutral', 'AirForward', 'AirUp', 'AirDown', 'LightNeutral1', 'LightSide1', 'LightUp', 'LightDown'];
  const dupes = [];
  for (const slot of SLOTS) {
    const sig = (w) => { const m = w.moves[slot]; return m && [m.startup, m.active, m.recovery, m.damage, m.base, m.growth, m.angle, m.kind,
      JSON.stringify(m.applies || null), m.pullVictim || 0, JSON.stringify((m.hitboxes || []).map((h) => h.size))].join('/'); };
    const seen = new Map();
    for (const w of WEAPONS) { const k = sig(w); if (!k) continue; if (seen.has(k)) dupes.push(`${slot}: ${seen.get(k)} == ${w.id}`); else seen.set(k, w.id); }
  }
  check('no two weapons share an identical move', dupes.length === 0,
    dupes.length ? dupes.join('; ') : `${SLOTS.length} slots x ${WEAPONS.length} weapons, every one distinct`);
}


// ---- 7. the file headers must match the measurement ----
// This system shipped wrong confirm percentages twice: first from a formula that ignored landing and
// reach, then from a simulation that could not tell a combo from a dodge-whiff punish. Both times
// the numbers in the weapon files were confidently sourced and wrong. So the headers are no longer
// trusted prose - they are parsed and checked against the table measured above.
{
  const fs = await import('node:fs');
  const dir = new URL('../src/data/weapons/', import.meta.url);
  const band = (ps) => (ps.length ? (ps[0] === ps[ps.length - 1] ? `${ps[0]}%` : `${ps[0]}-${ps[ps.length - 1]}%`) : null);

  for (const w of WEAPONS) {
    const src = fs.readFileSync(new URL(`${w.id.toLowerCase()}.js`, dir), 'utf8');
    const header = src.slice(0, src.indexOf('export default'));
    const problems = [];

    // e.g.  //   Rising Cut +Heavy   -> Skyward   CONFIRM 120-160%   trap  20-100%   kills 129%
    const line = /->\s+(.+?)\s{2,}(?:CONFIRM\s+(\d+(?:-\d+)?%)|trap only\s+(\d+(?:-\d+)?%))/g;
    const claims = [];
    for (const m of header.matchAll(line)) claims.push({ to: m[1].trim(), confirm: m[2] || null });
    if (claims.length === 0) problems.push('header quotes no routes at all');

    for (const c of claims) {
      const rows = rowsFor(w).filter((r) => w.moves[r.e.to].label === c.to);
      if (!rows.length) { problems.push(`header names '${c.to}', which is not a cash-out target`); continue; }
      const hit = rows.find((r) => band(r.confirm) === c.confirm);
      if (!hit) {
        const measured = rows.map((r) => `${w.moves[r.e.from].label} CONFIRM ${band(r.confirm) || 'none'}`).join(' | ');
        problems.push(`claims '-> ${c.to} CONFIRM ${c.confirm || 'none'}', measured: ${measured}`);
      }
    }
    check(`${w.id}: header percentages match the measurement`, problems.length === 0,
      problems.length ? problems.slice(0, 4).join('; ') : `${claims.length} quoted routes, every band reproduces`);
  }
}

// ---- report the measured table, so a tuning change shows its effect ----
console.log('\nMEASURED (simulated; victim spot-dodges on their first actionable frame)');
console.log('  CONFIRM = landed while still in hitstun.  trap = landed on the dodge\'s recovery, a read.');
for (const w of WEAPONS) {
  console.log(`  ${w.id}`);
  for (const r of rowsFor(w)) {
    const b = (ps) => ps.length ? `${ps[0]}-${ps[ps.length - 1]}%` : '-';
    const label = `${w.moves[r.e.from].label} +Heavy${r.e.dir === '*' ? '' : ' ' + r.e.dir}`;
    console.log(`    ${label.padEnd(28)} -> ${w.moves[r.e.to].label.padEnd(14)} CONFIRM ${b(r.confirm).padEnd(11)} trap ${b(r.punish).padEnd(11)} KO ${r.ko ?? '--'}%`);
  }
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
