// Draw kit characters to an SVG contact sheet, for looking at the part art without Studio.
//
//     node tools/kit-sheet.mjs out.svg [presets|<category>|random] [--half]
//
// The same composer the game uses (web/src/render2d/avatarCompose.js), laid out on the rig's
// standing proportions from Fighter2D.luau. `qlmanage -t -s 1600 -o <dir> out.svg` turns it into a
// PNG. A development aid only: nothing in check.sh runs it.
import fs from 'node:fs';
const { kitSprites, shadeRects, PIECES } = await import('../../web/src/render2d/avatarCompose.js');
const { KIT_PARTS, KIT_CATEGORIES, KIT_PRESETS, DEFAULT_KIT, sanitizeKit } = await import('../../web/src/data/avatarKit.js');

const [out = 'kit.svg', modeArg = 'presets', flag] = process.argv.slice(2);
const HALF = flag === '--half';
// `<category>:head` draws heads only, three times larger, for judging faces.
const [mode, zoom] = modeArg.split(':');
const HEADS = zoom === 'head';
const H = 5.2, R = 1.1, HIP = H * 0.34, SHO = H * 0.70, HEADY = H * 0.78, HS = R * 1.15, PW = HS / 12;
const SCALE = HEADS ? 80 : 46;           // svg px per stud
const CELLW = HEADS ? 200 : 150, CELLH = HEADS ? 230 : 330;

// One piece's rectangles placed with a transform: (tx, ty) the joint, `rot` radians, ph the
// vertical cell size.
function place(svg, rects, id, tx, ty, rot, ph) {
  const P = KIT_PARTS[id], k = HALF ? 2 : 1;
  const ox = P.ox / k, oy = P.oy / k, pw = PW * k, phk = ph * k;
  const c = Math.cos(rot), s = Math.sin(rot);
  for (const [col, row, w, h, hex, a] of rects) {
    const x = (col - ox) * pw, y = (oy - row - h) * phk;
    const pts = [[x, y], [x + w * pw, y], [x + w * pw, y + h * phk], [x, y + h * phk]]
      .map(([px, py]) => [tx + px * c - py * s, ty + px * s + py * c]);
    svg.push(`<polygon points="${pts.map(([px, py]) => `${(px * SCALE).toFixed(2)},${(-py * SCALE).toFixed(2)}`).join(' ')}" fill="${hex}" fill-opacity="${a}"/>`);
  }
}

function figure(svg, spec, cx, cy, label) {
  const sp = kitSprites(spec);
  const pick = (id) => (HALF ? sp[id].half : sp[id].full);
  svg.push(`<g transform="translate(${cx},${cy})">`);
  const L = H * 0.30;
  if (HEADS) {
    place(svg, pick('head'), 'head', 0, 0, 0, PW);
    svg.push('</g>');
    svg.push(`<text x="${cx}" y="${cy + 70}" font-size="15" text-anchor="middle" fill="#ddd" font-family="Helvetica">${label} · ${pick('head').length}</text>`);
    return;
  }
  place(svg, shadeRects(pick('leg')), 'leg', -R * 0.30, HIP, -0.12, HIP / 17);
  place(svg, pick('leg'), 'leg', R * 0.30, HIP, 0.12, HIP / 17);
  place(svg, pick('pelvis'), 'pelvis', 0, HIP, 0, H * 0.10 / 5);
  place(svg, shadeRects(pick('arm')), 'arm', -R * 0.35, SHO, -0.18, L / 15);
  place(svg, pick('torso'), 'torso', 0, HIP, 0, (SHO - HIP) / 18);
  place(svg, pick('head'), 'head', 0, HEADY, 0, PW);
  place(svg, pick('arm'), 'arm', R * 0.55, SHO, 0.22, L / 15);
  svg.push('</g>');
  const n = PIECES.reduce((t, id) => t + pick(id).length, 0) + pick('arm').length + pick('leg').length;
  svg.push(`<text x="${cx}" y="${cy + 28}" font-size="13" text-anchor="middle" fill="#ddd" font-family="Helvetica">${label}</text>`);
  svg.push(`<text x="${cx}" y="${cy + 44}" font-size="10" text-anchor="middle" fill="#888" font-family="Helvetica">${n} rects</text>`);
}

let entries = [];
if (mode === 'presets') entries = KIT_PRESETS.map((p) => [sanitizeKit({ parts: { ...DEFAULT_KIT.parts, ...p.parts }, colours: { ...DEFAULT_KIT.colours, ...p.colours } }), p.name]);
else if (mode === 'random') {
  let seed = 7;
  const rnd = (n) => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; };
  const { KIT_COLOURS } = await import('../../web/src/data/avatarKit.js');
  for (let i = 0; i < 24; i++) {
    const parts = {}, colours = {};
    for (const c of KIT_CATEGORIES) parts[c.id] = c.options[rnd(c.options.length)].id;
    for (const c of KIT_COLOURS) colours[c.id] = rnd(c.list.length);
    entries.push([{ parts, colours }, `#${i}`]);
  }
} else {
  const cat = KIT_CATEGORIES.find((c) => c.id === mode);
  if (!cat) throw new Error('unknown mode ' + mode);
  entries = cat.options.map((o) => [{ parts: { ...DEFAULT_KIT.parts, [cat.id]: o.id }, colours: DEFAULT_KIT.colours }, o.name]);
}

const cols = Math.max(3, Math.ceil(Math.sqrt(entries.length * CELLH / CELLW))), rows = Math.ceil(entries.length / cols);
// Square, because qlmanage crops its thumbnails to a square.
const side = Math.max(cols * CELLW, rows * CELLH);
const svg = [`<svg xmlns="http://www.w3.org/2000/svg" width="${side}" height="${side}" shape-rendering="crispEdges">`,
  `<rect width="100%" height="100%" fill="#2A3340"/>`];
entries.forEach(([spec, label], i) => figure(svg, spec, (i % cols) * CELLW + CELLW / 2, Math.floor(i / cols) * CELLH + CELLH - (HEADS ? 90 : 60), label));
svg.push('</svg>');
fs.writeFileSync(out, svg.join('\n'));
console.log(`${entries.length} figures -> ${out}`);
