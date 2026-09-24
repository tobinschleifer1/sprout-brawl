// Basic sprites: one placeholder frame for every key pose in the animation manifest.
//
// These are the "basic animations for the moment". Each frame is the game's OWN pose at that key -
// channels.js and weaponPose run on a posed fighter exactly as they do in a match - rasterised as a
// pixel mannequin at the real sprite scale (8 px per stud) with the real weapon art in its hand.
// So the timing, the angles and the proportions are already right; what a hand-drawn replacement
// adds is character, not correctness. An artist draws over these, frame for frame.
//
// Usage: node web/tools/basic-sprites.mjs <outDir>   -> <outDir>/<Sheet>.png + index.json
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { Raster } from './png.mjs';
import { manifest, PX_PER_STUD } from '../src/data/animations.js';
import { WEAPON_SPRITES, OUTLINE } from '../src/data/weaponArt.js';
import { buildLoadout } from '../src/data/loadout.js';
import { posedFighter } from '../src/render2d/preview.js';
import { channelsFor } from '../src/render2d/channels.js';
import { weaponPose } from '../src/render2d/weapons2d.js';

// 14 x 12 studs: enough for an overhead swing and a pike held level. Anything longer (the pike
// raised straight up, Colossus's doubled blade) is clipped at the cell edge - these are reference
// frames, and in the real pipeline the weapon is its own layer anyway.
export const CELL = { w: 112, h: 96, footX: 44, footY: 80 };
const SHEET_MAX = 1024;                                          // Roblox's image upload limit
const PI = Math.PI;

// A canvas-shaped rasteriser: an affine stack and fillRect, which is all the mannequin needs.
class Pen {
  constructor(r, clip) { this.r = r; this.clip = clip; this.m = [1, 0, 0, 1, 0, 0]; this.stack = []; }
  save() { this.stack.push(this.m.slice()); }
  restore() { this.m = this.stack.pop(); }
  apply(n) { const [a, b, c, d, e, f] = this.m; const [A, B, C, D, E, F] = n;
    this.m = [a * A + c * B, b * A + d * B, a * C + c * D, b * C + d * D, a * E + c * F + e, b * E + d * F + f]; }
  translate(x, y) { this.apply([1, 0, 0, 1, x, y]); }
  rotate(t) { const c = Math.cos(t), s = Math.sin(t); this.apply([c, s, -s, c, 0, 0]); }
  scale(x, y) { this.apply([x, 0, 0, y, 0, 0]); }
  // Fill every pixel whose centre falls inside the transformed rectangle.
  fillRect(x, y, w, h, hex, a = 1) {
    if (w < 0) { x += w; w = -w; } if (h < 0) { y += h; h = -h; }
    const [A, B, C, D, E, F] = this.m, det = A * D - B * C;
    if (Math.abs(det) < 1e-12) return;
    const pts = [[x, y], [x + w, y], [x, y + h], [x + w, y + h]].map(([u, v]) => [A * u + C * v + E, B * u + D * v + F]);
    const xs = pts.map((p) => p[0]), ys = pts.map((p) => p[1]);
    for (let py = Math.floor(Math.min(...ys)); py <= Math.ceil(Math.max(...ys)); py++) {
      for (let px = Math.floor(Math.min(...xs)); px <= Math.ceil(Math.max(...xs)); px++) {
        const X = px + 0.5 - E, Y = py + 0.5 - F;
        const u = (D * X - C * Y) / det, v = (-B * X + A * Y) / det;
        const c = this.clip;
        if (px < c.x || py < c.y || px >= c.x + c.w || py >= c.y + c.h) continue;   // stay inside the cell
        if (u >= x && u < x + w && v >= y && v < y + h) this.r.set(px, py, hex, a);
      }
    }
  }
}

const shade = (hex, k) => '#' + [1, 3, 5].map((i) => Math.round(parseInt(hex.slice(i, i + 2), 16) * k).toString(16).padStart(2, '0')).join('');

// The mannequin: the renderer's skeleton (render2d/renderer2d.js _fighter and _arm) with every
// part a plain block. Proportions are the renderer's own - HIP 0.34h, SHO 0.70h, HEAD 0.78h.
function drawMannequin(p, f, ch, wp, pal, wid) {
  const h = f.h, r = f.r, HIP = h * 0.34, SHO = h * 0.70, HEAD = h * 0.78;
  const lw = r * 0.42, ll = HIP;
  p.save();
  p.scale(f.facing, 1);
  if (ch.rigRotZ) { const pv = h * (ch.rotPivot ?? 0.5); p.translate(0, pv); p.rotate(ch.rigRotZ * f.facing); p.translate(0, -pv); }
  p.translate(0, (ch.bob || 0) + (ch.yOff || 0));
  let far = true;
  for (const [rot, dx] of [[ch.legL, -r * 0.30], [ch.legR, r * 0.30]]) {
    p.save(); p.translate(dx, HIP); p.rotate(-rot);
    p.fillRect(-lw / 2, -ll, lw, ll, far ? shade(pal.tertiary, 0.74) : pal.tertiary);
    p.restore(); far = false;
  }
  p.fillRect(-r * 0.56, HIP - h * 0.05, r * 1.12, h * 0.10, pal.secondary);
  p.save(); p.translate(0, HIP); p.rotate(-ch.lean); p.scale(ch.sx, ch.sy);
  const arm = (colour, a, front) => {
    const w = r * 0.34, L = h * 0.30 * (a.ext || 1);
    p.save(); p.translate(front ? r * 0.55 : -r * 0.35, SHO - HIP); p.rotate(a.z + (a.x || 0));
    p.fillRect(-w / 2, -L, w, L, colour); p.fillRect(-w * 0.7, -L - w * 0.8, w * 1.4, w * 1.1, colour);
    p.restore();
  };
  arm(shade(pal.secondary, 0.74), ch.armL, false);
  p.fillRect(-r * 0.80, 0, r * 1.60, SHO - HIP, pal.secondary);
  p.fillRect(-r * 0.80, (SHO - HIP) * 0.42, r * 1.60, (SHO - HIP) * 0.22, pal.accent);   // the belt
  const hs = r * 1.15;
  p.save(); p.translate(0, HEAD - HIP); p.rotate(-(ch.head || 0) * 0.4);
  p.fillRect(-hs / 2, -hs * 0.15, hs, hs, pal.primary);
  p.fillRect(hs * 0.12, hs * 0.38, hs * 0.2, hs * 0.2, '#1B1526');                        // an eye, facing forward
  p.restore();
  const armAng = wid ? wp.angle : ch.armR.z - PI / 2;
  arm(pal.primary, { z: armAng + PI / 2, x: ch.armR.x, ext: ch.armR.ext }, true);
  if (wid && !wp.hide && WEAPON_SPRITES[wid]) {
    const AL = h * 0.30 * (ch.armR.ext || 1);
    p.save();
    p.translate(r * 0.55 + Math.cos(armAng) * AL, (SHO - HIP) + Math.sin(armAng) * AL);
    p.rotate(wp.angle); p.translate(wp.ox || 0, wp.oy || 0);
    if (wp.scale && wp.scale !== 1) p.scale(wp.scale, wp.scale);
    for (const [x, y, w, hh, colour, a] of WEAPON_SPRITES[wid]) p.fillRect(x, y, w, hh, colour, a);
    p.restore();
  }
  p.restore(); p.restore();
}

// One cell: returns false when the game has no pose for that state (the key stays "planned").
export function renderCell(raster, cx, cy, loadout, key, wid) {
  let f, ch, wp;
  try {
    if (key.move) {
      f = posedFighter(loadout, key.move, key.mf);
    } else {
      const s = key.sample;
      f = posedFighter(loadout, null, s.sf || 0, { state: s.state, onGround: s.onGround, vx: s.vx, frameCount: s.frameCount });
      Object.assign(f, { vy: s.vy || 0, fastFalling: !!s.fastFalling, tumbling: !!s.tumbling, techRoll: s.techRoll || 0,
        la: s.la || null, shield: s.shield ?? 50, hitstun: s.hitstun || 0 });
    }
    ch = channelsFor(f, 0);
    wp = wid ? weaponPose(f, 0) : null;
  } catch (e) { return false; }
  if (!ch || ch.visible === false) return false;
  const p = new Pen(raster, { x: cx, y: cy, w: CELL.w, h: CELL.h });
  p.m = [PX_PER_STUD, 0, 0, -PX_PER_STUD, cx + CELL.footX, cy + CELL.footY];   // world is y-up
  drawMannequin(p, f, ch, wp || {}, loadout.palette, wid);
  // The numbers the game used for this pose, for the artist: what the basic frame was drawn from.
  const deg = (v) => Math.round(((v || 0) * 180) / PI);
  return { lean: deg(ch.lean), weapon: wp && !wp.hide ? deg(wp.angle) : null, squash: [+ch.sx.toFixed(2), +ch.sy.toFixed(2)],
    smear: +(ch.smear || 0).toFixed(2), spin: deg(ch.rigRotZ || ch.spinZ), opacity: +(ch.opacity ?? 1).toFixed(2) };
}

// The pixel-art outline: any empty pixel touching a filled one, inside a cell's bounds.
function outline(r, x0, y0) {
  const filled = (x, y) => x >= x0 && y >= y0 && x < x0 + CELL.w && y < y0 + CELL.h && r.px[(y * r.w + x) * 4 + 3] > 0;
  const ring = [];
  for (let y = y0; y < y0 + CELL.h; y++) for (let x = x0; x < x0 + CELL.w; x++) {
    if (filled(x, y)) continue;
    if (filled(x - 1, y) || filled(x + 1, y) || filled(x, y - 1) || filled(x, y + 1)) ring.push([x, y]);
  }
  for (const [x, y] of ring) r.set(x, y, OUTLINE, 0.9);
}

export function buildSheets() {
  const m = manifest();
  const sheets = [];
  const loadout = (wid) => buildLoadout('Classic', wid);
  // Shared animations: drawn with the Sword in hand, since the body animations are shared and the
  // weapon moves with them; the real pipeline puts the weapon on its own layer.
  const sharedCells = m.shared.flatMap((a) => a.keys.map((k, i) => ({ anim: a.id, key: i, name: k.name, sample: k.sample, basic: k.basic !== false })));
  sheets.push({ id: 'Shared', wid: 'Sword', cells: sharedCells });
  for (const w of m.weapons) {
    sheets.push({ id: w.id, wid: w.id, cells: w.moves.flatMap((mv) => mv.keys.map((k, i) => ({
      anim: mv.id, key: i, name: k.name, from: k.from, to: k.to, move: mv.id,
      mf: Math.floor((k.from + k.to - 1) / 2) + 1, basic: true }))) });
  }
  const out = [];
  const cols = Math.floor(SHEET_MAX / CELL.w), perSheet = cols * Math.floor(SHEET_MAX / CELL.h);
  for (const s of sheets) {
    for (let part = 0; part * perSheet < s.cells.length; part++) {
      const cells = s.cells.slice(part * perSheet, (part + 1) * perSheet);
      const id = s.cells.length > perSheet ? `${s.id}-${part + 1}` : s.id;
      const r = new Raster(cols * CELL.w, Math.ceil(cells.length / cols) * CELL.h);
      const index = [];
      cells.forEach((c, i) => {
        const x = (i % cols) * CELL.w, y = Math.floor(i / cols) * CELL.h;
        const drawn = c.basic && renderCell(r, x, y, loadout(s.wid), c.move ? { move: c.move, mf: c.mf } : { sample: c.sample }, s.wid);
        if (drawn) outline(r, x, y);
        index.push({ sheet: id, anim: c.anim, key: c.key, name: c.name, x, y, w: CELL.w, h: CELL.h, basic: !!drawn, mf: c.mf ?? null, ref: drawn || null });
      });
      out.push({ id, width: r.w, height: r.h, raster: r, index });
    }
  }
  return out;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const dir = process.argv[2] || 'art/basic';
  fs.mkdirSync(dir, { recursive: true });
  const sheets = buildSheets();
  const index = {};
  for (const s of sheets) {
    fs.writeFileSync(path.join(dir, `${s.id}.png`), s.raster.png());
    index[s.id] = { width: s.width, height: s.height, cell: CELL, frames: s.index };
  }
  fs.writeFileSync(path.join(dir, 'index.json'), JSON.stringify(index));
  const all = sheets.reduce((t, s) => t + s.index.length, 0), drawn = sheets.reduce((t, s) => t + s.index.filter((f) => f.basic).length, 0);
  console.log(`wrote ${sheets.length} sheets to ${dir}: ${drawn} of ${all} key poses have a basic sprite`);
}
