// Renders every weapon grid to one PNG sheet at 10x, on the game's dark ground, for looking at.
import fs from 'node:fs';
import { Raster } from './png.mjs';
import { GRIDS, paint } from '../src/data/weaponArt.js';
import { WEAPONS } from '../src/data/weapons/index.js';

const S = 10, PAD = 3;
const extra = { Rapier: { primary: '#DDE3EC', secondary: '#C9A043', tertiary: '#2A3550', accent: '#F2F5FA', glow: '#6EA8FF', hilt: '#C9A043' },
  Chakram: { primary: '#C0C8D4', secondary: '#1E4A4A', tertiary: '#0F2626', accent: '#F4E8C0', glow: '#3CE8C8' } };
const byId = Object.fromEntries(WEAPONS.map((w) => [w.id, w.palette]));
const ids = Object.keys(GRIDS);
const painted = ids.map((id) => paint(GRIDS[id], byId[id] || extra[id]));
const colW = Math.max(...painted.map((p) => p.w)) + PAD * 2, rowH = painted.map((p) => p.h + PAD * 2);
const cols = 2, rows = Math.ceil(ids.length / cols);
const H = Array.from({ length: rows }, (_, r) => Math.max(rowH[r * 2] || 0, rowH[r * 2 + 1] || 0));
const r = new Raster(colW * cols * S, H.reduce((a, b) => a + b, 0) * S);
r.rect(0, 0, r.w, r.h, '#0B1017');
let y0 = 0;
for (let i = 0; i < ids.length; i++) {
  const p = painted[i], cx = (i % cols) * colW + PAD, cy = y0 + PAD;
  for (let rr = 0; rr < p.h; rr++) for (let cc = 0; cc < p.w; cc++) {
    const col = p.cell[rr][cc];
    if (col) r.rect((cx + cc) * S, (cy + rr) * S, S, S, col, col === '#120E16' ? 0.9 : 1);
  }
  r.rect((cx + p.ox) * S - 1, (cy + p.oy) * S - 1, 3, 3, '#7FD4FF');   // the grip point
  if (i % cols === cols - 1) y0 += H[Math.floor(i / cols)];
}
fs.writeFileSync(process.argv[2] || '/tmp/weapons.png', r.png());
console.log('wrote', ids.length, 'weapons');
