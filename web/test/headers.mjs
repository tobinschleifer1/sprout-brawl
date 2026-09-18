// Regenerate the "signature cash-outs" table in each weapon file's header from the measurement.
//
//     npm run headers
//
// combo.test.mjs PARSES those tables and fails when they disagree with the engine, because they
// have shipped wrong twice. Run this after any tuning change that moves a confirm window or a kill
// percent - twelve tables rewritten by hand is how they went stale the last two times. It is
// idempotent: a second run reports the same line counts and changes nothing.
import fs from 'node:fs';
import { WEAPONS } from '../src/data/weapons/index.js';
import { confirmsAt, edges, koPercent } from './balance.mjs';

const GRID = [0, 20, 40, 60, 80, 100, 120, 140, 160, 180, 200, 220, 240, 260];
const band = (ps) => (ps.length ? (ps[0] === ps.at(-1) ? `${ps[0]}%` : `${ps[0]}-${ps.at(-1)}%`) : null);

function sigKO(w, id) {
  const m = w.moves[id];
  const boxes = (m.hitboxes || []).length ? m.hitboxes : [m];
  const sources = m.summon?.blast ? [m.summon.blast] : boxes;
  let best = null;
  for (const src of sources) {
    const ko = koPercent(src.base ?? m.base, src.growth ?? m.growth, src.damage ?? m.damage, 100, { angle: src.angle ?? m.angle });
    if (ko != null && (best === null || ko < best)) best = ko;
  }
  return best;
}
const DIR = { neutral: '', side: '+Side', down: '+Down', up: '+Up', '*': '' };

for (const w of WEAPONS) {
  const rows = [];
  for (const e of edges(w).filter((x) => x.kind === 'heavy')) {
    const rs = GRID.map((p) => confirmsAt(w.id, e.from, e.dir, e.to, p));
    rows.push({ e, confirm: band(GRID.filter((p, i) => rs[i].confirmed)), trap: band(GRID.filter((p, i) => rs[i].punish)), ko: sigKO(w, e.to) });
  }
  // One line per distinct outcome; dirs that measure identically collapse into the plainest one.
  const groups = new Map();
  for (const r of rows) {
    const key = `${r.e.from}|${r.e.to}|${r.confirm}|${r.trap}`;
    const g = groups.get(key);
    if (!g) groups.set(key, { ...r, dirs: [r.e.dir] });
    else g.dirs.push(r.e.dir);
  }
  const out = [...groups.values()].filter((r) => r.confirm || r.trap);
  out.sort((a, b) => (b.confirm ? 1 : 0) - (a.confirm ? 1 : 0) || (a.confirm || a.trap).localeCompare(b.confirm || b.trap));
  const tag = (r) => {
    const d = r.dirs.includes('neutral') || r.dirs.includes('*') ? '' : DIR[r.dirs[0]];
    return `+Heavy${d}`;
  };
  const fw = Math.max(...out.map((r) => w.moves[r.e.from].label.length));
  const tw = Math.max(...out.map((r) => tag(r).length));
  const ow = Math.max(...out.map((r) => w.moves[r.e.to].label.length));
  const lines = out.map((r) => {
    const from = w.moves[r.e.from].label.padEnd(fw);
    const to = w.moves[r.e.to].label.padEnd(ow);
    const ko = `kills ${r.ko === null ? ' n/a' : String(r.ko).padStart(4)}${r.ko === null ? '' : '%'}`;
    const mid = r.confirm
      ? `CONFIRM ${r.confirm.padStart(9)}   trap ${(r.trap || '-').padStart(8)}   `
      : `trap only ${(r.trap || '-').padStart(9)}                 `;
    return `//   ${from} ${tag(r).padEnd(tw)} -> ${to}   ${mid}${ko}`;
  });

  const path = new URL(`../src/data/weapons/${w.id.toLowerCase()}.js`, import.meta.url);
  const src = fs.readFileSync(path, 'utf8');
  const all = src.split('\n');
  const idx = all.reduce((acc, l, i) => (/^\/\/\s.*->\s.*(CONFIRM|trap only)/.test(l) ? [...acc, i] : acc), []);
  if (!idx.length) { console.log(`${w.id}: NO TABLE FOUND`); continue; }
  const first = idx[0], last = idx.at(-1);
  if (last - first + 1 !== idx.length) { console.log(`${w.id}: table lines are not contiguous`); continue; }
  fs.writeFileSync(path, [...all.slice(0, first), ...lines, ...all.slice(last + 1)].join('\n'));
  console.log(`${w.id}: ${idx.length} lines -> ${lines.length}`);
}
