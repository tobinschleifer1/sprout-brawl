// Kit character -> cells -> rectangles. The pure half of drawing a kit character, ported line for
// line to roblox/src/client/AvatarCompose.luau and replayed against it by check.sh.
//
// compose(spec) stacks every chosen option's layers onto the five puppet pieces and resolves each
// cell to a colour. piece(grid, lod) then outlines it and cuts it into as few rectangles as
// possible, because in Roblox every rectangle is a Frame and Frames are the renderer's budget.
//
// LOD. A cell is about 0.105 studs. At the camera's widest zoom on a small window that is under one
// screen pixel, and a Frame narrower than a pixel either vanishes or doubles depending on where it
// lands - a face shimmers. So every piece can also be cut at HALF resolution: each 2x2 block becomes
// one cell, kept if at least two of its four cells are painted, coloured by the colour with the most
// WEIGHT in the block. Eyes, mouths and ink carry extra weight (avatarParts.js ROLES), so a one-cell
// eye still wins the block it sits in and a zoomed-out face keeps its features.
//
// Colour arithmetic rounds with Math.round on non-negative values only, which is what lets the
// Luau use math.floor(x + 0.5) and match it exactly.

import { KIT_PARTS, KIT_ROLES, KIT_FIXED, KIT_CATEGORIES, KIT_COLOURS, OUTLINE, sanitizeKit } from '../data/avatarKit.js';

export const PIECES = ['head', 'torso', 'arm', 'leg', 'pelvis'];
export const OUTLINE_ALPHA = 0.85;
export const SHADE_DARK = 0.72;
export const FAR_SHADE = 0.74;      // the far arm and leg, darkened rather than made see-through

const hex2 = (n) => n.toString(16).toUpperCase().padStart(2, '0');
const rgb = (hex) => [parseInt(hex.slice(1, 3), 16), parseInt(hex.slice(3, 5), 16), parseInt(hex.slice(5, 7), 16)];
const toHex = (c) => '#' + hex2(c[0]) + hex2(c[1]) + hex2(c[2]);

export const darken = (hex, k) => toHex(rgb(hex).map((v) => Math.round(v * k)));
// Lightening scales the channels up rather than mixing toward white, which keeps the hue: brown hair
// highlighted toward white turns grey, scaled up it stays brown.
export const lighten = (hex) => toHex(rgb(hex).map((v) => Math.round(Math.min(255, v * 1.25 + 20))));
export const mix = (a, b) => { const x = rgb(a), y = rgb(b); return toHex([0, 1, 2].map((i) => Math.round((x[i] + y[i]) / 2))); };
// Luma, in integers, so the tie-break below is exact in both languages.
export const luma = (hex) => { const c = rgb(hex); return c[0] * 299 + c[1] * 587 + c[2] * 114; };

// Every role letter -> the colour it paints for this character.
export function resolveRoles(spec) {
  const slot = (id) => { const c = KIT_COLOURS.find((x) => x.id === id); return c.list[spec.colours[id]]; };
  const out = {};
  for (const [ch, r] of Object.entries(KIT_ROLES)) {
    let col;
    if (r.fixed) col = KIT_FIXED[r.fixed];
    else if (r.mix) col = mix(slot(r.slot), slot(r.mix));
    else if (r.shade === 'dark') col = darken(slot(r.slot), SHADE_DARK);
    else if (r.shade === 'light') col = lighten(slot(r.slot));
    else col = slot(r.slot);
    out[ch] = { hex: col, weight: r.weight || 1 };
  }
  return out;
}

// The layers this spec draws, in paint order. Sorting on (z, seq) with seq unique is a strict total
// order, so Luau's unstable table.sort produces the same sequence.
export function layersOf(spec) {
  const list = [];
  let seq = 0, trim = 0;
  for (const cat of KIT_CATEGORIES) {
    const o = cat.options.find((x) => x.id === spec.parts[cat.id]);
    if (o.trim && o.trim > trim) trim = o.trim;
    for (const L of o.layers) list.push({ L, seq: seq++ });
  }
  list.sort((a, b) => (a.L.z - b.L.z) || (a.seq - b.seq));
  return { layers: list.map((x) => x.L), trim };
}

// Paint every piece. A cell is null or { hex, weight }.
export function compose(raw) {
  const spec = sanitizeKit(raw);
  const roles = resolveRoles(spec);
  const { layers, trim } = layersOf(spec);
  const out = {};
  for (const id of PIECES) {
    const P = KIT_PARTS[id];
    const cells = Array(P.w * P.h).fill(null);
    const mask = Array(P.w * P.h).fill(false);
    for (const L of layers) {
      if (L.part !== id) continue;
      for (let r = 0; r < L.rows.length; r++) {
        const row = L.rows[r];
        for (let c = 0; c < row.length; c++) {
          const ch = row[c];
          if (ch === '.') continue;
          const x = L.x + c, y = L.y + r;
          if (x < 0 || y < 0 || x >= P.w || y >= P.h) continue;
          if (L.hair && y < trim) continue;
          const i = y * P.w + x;
          if (L.clip && !mask[i]) continue;
          cells[i] = roles[ch];
          if (L.base) mask[i] = true;
        }
      }
    }
    out[id] = { w: P.w, h: P.h, cells };
  }
  return out;
}

// Half resolution: see the header.
export function halve(g) {
  const w = Math.ceil(g.w / 2), h = Math.ceil(g.h / 2);
  const cells = Array(w * h).fill(null);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const score = new Map();
    let painted = 0;
    for (let dy = 0; dy < 2; dy++) for (let dx = 0; dx < 2; dx++) {
      const sx = x * 2 + dx, sy = y * 2 + dy;
      if (sx >= g.w || sy >= g.h) continue;
      const c = g.cells[sy * g.w + sx];
      if (!c) continue;
      painted++;
      score.set(c.hex, (score.get(c.hex) || 0) + c.weight);
    }
    if (painted < 2) continue;
    let best = null, bestScore = -1;
    for (const [hex, s] of score) {
      if (s > bestScore || (s === bestScore && (luma(hex) < luma(best) || (luma(hex) === luma(best) && hex < best)))) { best = hex; bestScore = s; }
    }
    cells[y * w + x] = { hex: best, weight: 1 };
  }
  return { w, h, cells };
}

// Cells -> as few rectangles as possible. The same greedy cut as weaponArt.js: grow each run right,
// then down while the whole span matches. Rectangles are [col, row, w, h, hex, alpha] in cells.
function greedy(get, w, h, alpha) {
  const used = Array(w * h).fill(false);
  const out = [];
  for (let r = 0; r < h; r++) for (let c = 0; c < w; c++) {
    const col = get(c, r);
    if (!col || used[r * w + c]) continue;
    let cw = 1;
    while (c + cw < w && get(c + cw, r) === col && !used[r * w + c + cw]) cw++;
    let ch = 1;
    grow: while (r + ch < h) {
      for (let k = 0; k < cw; k++) if (get(c + k, r + ch) !== col) break grow;
      ch++;
    }
    for (let j = 0; j < ch; j++) for (let k = 0; k < cw; k++) used[(r + j) * w + c + k] = true;
    out.push([c, r, cw, ch, col, alpha]);
  }
  return out;
}

// A piece as rectangles: the outline (the silhouette grown by one cell, drawn first) and then the
// cheaper of two cuts of the colours - in place, or painter's (the commonest colour over the whole
// silhouette, everything else on top of it).
export function piece(g) {
  const { w, h, cells } = g;
  const hexAt = (c, r) => (c >= 0 && r >= 0 && c < w && r < h && cells[r * w + c] ? cells[r * w + c].hex : null);
  const halo = (c, r) => (hexAt(c, r) || hexAt(c - 1, r) || hexAt(c + 1, r) || hexAt(c, r - 1) || hexAt(c, r + 1) ? OUTLINE : null);
  const outline = greedy(halo, w, h, OUTLINE_ALPHA);
  const inPlace = greedy(hexAt, w, h, 1);
  const count = new Map();
  for (const c of cells) if (c) count.set(c.hex, (count.get(c.hex) || 0) + 1);
  let base = null, n = -1;
  for (const [hex, k] of count) if (k > n || (k === n && hex < base)) { base = hex; n = k; }
  const painter = [
    ...greedy((c, r) => (hexAt(c, r) ? base : null), w, h, 1),
    ...greedy((c, r) => { const x = hexAt(c, r); return x && x !== base ? x : null; }, w, h, 1),
  ];
  return [...outline, ...(painter.length < inPlace.length ? painter : inPlace)];
}

// Everything a renderer needs for one character: rectangles per piece at full and half resolution.
export function kitSprites(raw) {
  const g = compose(raw);
  const out = {};
  for (const id of PIECES) out[id] = { full: piece(g[id]), half: piece(halve(g[id])) };
  return out;
}

// The far limb's copy of a rectangle list: every colour darkened, the outline left alone.
export const shadeRects = (rects) => rects.map((r) => (r[4] === OUTLINE ? r : [r[0], r[1], r[2], r[3], darken(r[4], FAR_SHADE), r[5]]));
