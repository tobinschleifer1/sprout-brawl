// Weapon art as pixel grids: the revised "salvage-forged" arsenal.
//
// Every weapon is authored as a grid at EIGHT PIXELS PER STUD - the drawing scale in the revamp
// plan, chosen because at the camera's widest zoom one of these pixels is one screen pixel at
// 1080p, so nothing is ever minified into mush. Grids are compiled at load into merged rectangles,
// [x, y, w, h, hex, alpha] in studs, and both builds draw exactly those rectangles: the web through
// fillRect, Roblox through Canvas2D.rect (see gen-data.mjs). That ends the old divergence where
// Roblox approximated the web's polygons with staircases; the two now draw the same weapon.
//
// GRID CONVENTION. Text rows run top to bottom in the canvas-authoring sense the original shapes in
// render2d/weapons2d.js were written in: row index grows with +y. Columns grow with +x, the weapon
// points along +x, and (ox, oy) is the grid corner that sits on the grip point (0, 0). Keeping the
// old shapes' orientation means every weapon still sits in the hand at the same angle it always did.
//
// REACH IS A RULE, NOT A STYLE. Players judge range by eye, so each grid's forward extent matches
// the old shape's to within one pixel. test/weapon-art.test.mjs measures it.
//
// Legend: '.' empty. P S T A G H = the weapon palette's primary, secondary, tertiary, accent, glow,
// hilt. Any other character is looked up in the grid's own `ink` table (a literal hex colour).

export const OUTLINE = '#120E16';
export const PX = 1 / 8;

const G = (ox, oy, rows, ink = {}) => ({ ox, oy, rows, ink });

export const GRIDS = {
  // OATHBLADE. A knightly broadsword: a bevelled blade with a fuller that carries the glow, a gilt
  // crossguard set with a gem, an oxblood-wrapped grip and a gilt pommel stone.
  Sword: G(6, 5, [
    '.....UUUU................',
    '......uu.................',
    '......uuTT...............',
    '......uuSTAAAAAAAAAAAA...',
    'UUjhjhzuSTPPPPPPPPPPPPA..',
    'GuhjhjGGSTGGGGGGGGGGggPAA',
    'yyjhjhuzSTPPPPPPPPPPPPS..',
    '......uuSTSSSSSSSSSSSS...',
    '......uuTT...............',
    '......uu.................',
    '.....UyyU................',
  ], { h: '#5A2E2E', j: '#8E4A3E', u: '#C9A24A', U: '#FFE08A', y: '#7A5A24', z: '#FFFFFF', g: '#E9FBFF' }),

  // GRAVE BLOOM. A long bone-white snath bound at the grip, an iron socket holding a soul gem, and a
  // crescent of violet soul-glass whose cutting edge runs bright with the Bloom glow.
  Scythe: G(6, 2, [
    '..........................AAAAAA.......',
    'BBnnBBBBBBBBBBBBBBBBBBBnnBSSGSSSSAAAA..',
    'nnnnnnnnnnnnnnnnnnnnnnnnnnSSGSSAAAAA...',
    '..........................TTTAGPP......',
    '............................AGggPPP....',
    '...........................AGPgPPPPP...',
    '..........................AGPPPPPPPP...',
    '........................AGPPPPPPPPPQ...',
    '......................AGPPPPPPPPPPQ....',
    '....................AGPPPPPPPPPPQQ.....',
    '.................AGPPPPPPPPPPPQQ.......',
    '..............AGPPPPPPPPPPPQQQ.........',
    '...........AGPPPPPPPPPPQQQQ............',
    '........AGPPPPPPPPQQQQQ................',
    '.....AGPPPPQQQQQQQ.....................',
    '...AGQQQQQQ............................',
  ], { b: '#E8E0CC', B: '#FFF8E8', n: '#A89C84', Q: '#241C30', g: '#F2DCFF' }),

  // TWIN RIVETS. Foundry rivet guns: a bevelled housing, a fat nozzle, a brass grip, and the
  // magazine shown as glowing pips along the side - the ammo count reads off the weapon itself.
  Blasters: G(3, 4, [
    '..SS.......',
    'AAAAAAAA...',
    'PkPkPkPPSAT',
    'PGPGPGPPSSn',
    'SSSSSSSS...',
    '.TTTTkT....',
    '..jHHk.....',
    '..HjH......',
    '..HHT......',
  ], { k: '#1A2230', n: '#FFF3D0', j: '#F0D29A' }),

  // STARBOUND CODEX. An iron-bound ledger with gilt corner plates, a glowing ringed star on the
  // cover, a clasp across the fore-edge and the page block showing behind it.
  Grimoire: G(6, 6, [
    'mmSSSSSSSSmm.',
    'mmPPPPPPPPmmW',
    'PPPPPPPPPPPWp',
    'PPPPGGGPPPPWW',
    'PPPGPAPGPPPWp',
    'PPPGAwAGPmmmG',
    'PPPGPAPGPmmmp',
    'PPPPGGGPPPPWW',
    'PPPPPPPPPPPWp',
    'PPPPPPPPPPPWW',
    'PPPPPPPPPPPWp',
    'mmPPPPPPPPmmW',
    'mTTTTTTTTTTm.',
  ], { W: '#F0E7D2', w: '#FFFFFF', m: '#C9A24A', p: '#BFB49C' }),

  // HEADSMAN. A bearded executioner's axe: a banded haft, a crescent bit with a bright edge over
  // rust-red, a rune on the cheek that glows, and a reverse spike.
  Axe: G(8, 10, [
    '....................................',
    '....................................',
    '........................AAe.........',
    '........................PPPe........',
    '........................PPPre.......',
    '.......................APPPPre......',
    '.......................PPPPPPre.....',
    '.......................PPPPPPPre....',
    '.SS......SS......S....SSPPPPPPre....',
    'hSShhhhhhSShhhhhhASSSSSSPPGPPPPre...',
    'dSSddddddSSddddddSSSSSSSPPGGPPPre...',
    '.SS......SS......S....SSPPPGPPPre...',
    '.......................PPPPPPPPPre..',
    '......................APPPPPPPPPre..',
    '......................PPPPPPPPPPPre.',
    '.....................APPPPPPPPPPTre.',
    '....................APPPPPPPPTre....',
    '...................APPPPTTTTe.......',
    '...................TTTTe............',
  ], { h: '#7A5E42', d: '#3A2A1A', e: '#F4F6FA', r: '#B4462E' }),

  // TOLLGATE. Almost all haft, wrapped at the grip and banded twice, a leaf point with a glowing
  // fuller, and a crimson swallowtail pennant under the head - it shows which way you face and
  // roughly how far you reach, even zoomed out.
  Pike: G(13, 3, [
    '.....................................................AAA.G...',
    '.............................................ASSS..AAAAAAA...',
    'aaaaaaaaaaaaaTjTjTjTjaaaaaaSaaaaaaaaaaSaaaaaaSSSSAGGGGGGGGGAA',
    'dddddddddddddjTjTjTjTddddddSddddddddddSddddddSSSSAwwwwwwwAAA.',
    '.............................................SSScccccAAAA....',
    '...............................................Skkkkkkk......',
    '...............................................SYYcccc.......',
    '...............................................Scccccccc.....',
    '...............................................Scc..cccc.....',
    '...............................................Sc.....cc.....',
  ], { a: '#E8D4A0', d: '#8A7048', j: '#5A4028', w: '#FFFFFF', c: '#A8322E', k: '#D84A3E', Y: '#F2C94A' }),

  // OVERDRIVE KNUCKLES. A hydraulic fist: a bracer with a vent, twin pistons on the back of the
  // hand, and glowing knuckle plates that flare in Overdrive.
  Gauntlets: G(4, 4, [
    '....ii.ii...',
    '...AAAAAAA..',
    'iTTPPPPPPPG.',
    'TvTPPPPPPPvA',
    'TvTPkkkkkkPG',
    'TvTPPPPPPPvS',
    'iTTPPPPPPPG.',
    '...SSSSSSS..',
    '....ii.ii...',
  ], { v: '#FF9A4A', k: '#5A2018', i: '#C8CED8' }),

  // GROUNDBREAKER. A forge sledge: a stone head bound by two riveted iron bands and a collar, a
  // glowing crack through its core, on a wrapped haft.
  Hammer: G(10, 9, [
    '.............................sAAAAAAAAAA',
    '.............................sPPPPPPPPPs',
    '.............................sIRIIRIIRII',
    '.............................sPPPPGPPPPs',
    '.............................sPPPPGPPPPs',
    '.......................AAAAAAsPPPPPGPPPs',
    '.......................SSSSSSsPPPPGPPPPs',
    'A......................SSSSSSsPPPPGPPPPs',
    'SAHAHAHhhhhhhhhhhhhhhhhSSSSSSsPPPPPGgPPs',
    'SHIHIHIddddddddddddddddSSSSSSsPPPgPGPPPs',
    'I......................SSSSSSsPPPPGPPPPs',
    '.......................SSSSSSsPPPPGPPPPs',
    '.......................IIIIIIsPPPPPGPPPs',
    '.............................sPPPPGPPPPs',
    '.............................sIRIIRIIRII',
    '.............................sPPPPPPPPPs',
    '.............................sssssssssss',
  ], { s: '#5A5048', I: '#2A2420', h: '#9A7A52', d: '#4A3420', R: '#D8DCE2', g: '#FFE08A' }),

  // HEARTSTRING. A recurve in green-bronze with pale-edged limbs and glowing tips, a wrapped grip
  // with an arrow rest, and a straight string - the one straight line on the weapon, and the read.
  Longbow: G(0, 12, [
    'aL.......',
    'aALP.....',
    'a..LP....',
    'a...LP...',
    'a....LP..',
    'a....LP..',
    'a.....LP.',
    'a.....LP.',
    'a......LP',
    'a......LP',
    'a.....SwS',
    'a.....SSG',
    'a.....SwG',
    'a.....SSS',
    'a......LP',
    'a......LP',
    'a.....LP.',
    'a.....LP.',
    'a....LP..',
    'a....LP..',
    'a...LP...',
    'a..LP....',
    'aALP.....',
    'aL.......',
  ], { a: '#F0E2C0', L: '#E8F4C8', w: '#3A2A1A' }),

  // WRECKING CHAIN. A spiked wrecking ball on a chain drawn link by link (the number of links IS
  // the reach), a band round its middle that catches the Snare glow, on a wrapped haft.
  Flail: G(9, 7, [
    '......................................A.......',
    '......................................A.......',
    '....................................AAAAA.....',
    '.................................AAAPPPPPAAA..',
    '.................................APkkPPPPPPA..',
    'S..........SS....................APkPPPPPPPT..',
    'ShShShShShhSS.oO.oO.oO.oO.oO.oO.APPPPPPPPPPPA.',
    'SdSdSdSdSddSS.Oo.Oo.Oo.Oo.Oo.Oo.AGiGGiGGiGGiTA',
    'S..........SS...................APPPPPPPPPPPT.',
    '.................................APPPPPPPPPT..',
    '.................................APPPPPPPPPT..',
    '.................................AATPPPPPTTA..',
    '....................................ATTTT.....',
    '......................................A.......',
    '......................................A.......',
  ], { o: '#6E7684', O: '#9AA2B0', k: '#E8ECF2', i: '#FFFFFF', h: '#9A7A52', d: '#4A3420' }),

  // BASTION. A salvaged blast door carried as a tower shield: a gilt-rimmed riveted slab, a
  // viewport slit that shimmers in Counterguard's window, and hazard stripes along the bottom edge.
  Shield: G(3, 12, [
    'bbbbbbbbb',
    'bBPPPPPPb',
    'bBrPPPrPb',
    'bBPPPPPPb',
    'bBPPPPPPb',
    'bBSSSSSPb',
    'bBPPPPPPb',
    'bBPPPPPPb',
    'bBrPPPrPb',
    'bBPPPPPPb',
    'bBkkkkkPb',
    'bBkGwGkPb',
    'bBkkkkkPb',
    'bBPPPPPPb',
    'bBrPPPrPb',
    'bBPPPPPPb',
    'bBPPPPPPb',
    'bBSSSSSPb',
    'bBPPPPPPb',
    'bBrPPPrPb',
    'byzyzyzyb',
    'bzyzyzyzb',
    'bBPPPPPPb',
    'bbbbbbbbb',
    '.TTTTTTT.',
  ], { b: '#B08A4A', B: '#E8C47A', r: '#8A6E4A', k: '#1A2230', y: '#E8B04A', z: '#2A303C', w: '#FFFFFF' }),

  // TWINFANG. Two curved daggers with crimson crystal edges: the front blade curls up at the tip,
  // the reverse one trails behind the hand. The silhouette says "a pair" in any single frame.
  Daggers: G(10, 3, [
    '....................AC',
    '...........SS.....AAPq',
    'ee.........SS.ACCCcPS.',
    'ePPPPPPTjTjGGASSSSSS..',
    '.qqqqqqqqqqSS.........',
    '...........SS.........',
    '......................',
  ], { c: '#FF4A6A', C: '#FFB0BE', q: '#8A1A30', e: '#A0ACBE', j: '#4A3A5A' }),

  // DUELIST (new, not yet in the engine). A slim silver blade, a gold basket hilt and a blue plume.
  Rapier: G(5, 4, [
    '..pp........................',
    '.pppS.......................',
    'TTHSSS......................',
    'TTHSSPPPPPPPPPPPPPPPPPPPPPPw',
    'TTHSSS......................',
    '....S.......................',
    '....S.......................',
  ], { p: '#6EA8FF', w: '#F2F5FA' }),

  // ORBIT (new, not yet in the engine). Twin throwing rings with a teal inner light.
  Chakram: G(1, 5, [
    '..PPPPP.......PPPPP..',
    '.PPGGGPP.....PPGGGPP.',
    'PPG...GPP...PPG...GPP',
    'PG.....GP...PG.....GP',
    'PG.....GP...PG.....GP',
    'PG.....GP...PG.....GP',
    'PPG...GPP...PPG...GPP',
    '.PPGGGPP.....PPGGGPP.',
    '..PPPPP.......PPPPP..',
  ]),
};

const KEYS = { P: 'primary', S: 'secondary', T: 'tertiary', A: 'accent', G: 'glow', H: 'hilt' };

function colourOf(ch, grid, palette) {
  if (grid.ink[ch]) return grid.ink[ch];
  const key = KEYS[ch];
  if (!key) throw new Error(`weaponArt: unknown ink '${ch}'`);
  return palette[key] || (key === 'glow' ? palette.accent : key === 'hilt' ? palette.secondary : null) || '#FF00FF';
}

// Grid -> colour per cell, plus the silhouette grown by one pixel. The grown silhouette is drawn
// first in the outline colour and the weapon over it, which leaves a one-pixel dark ring. Drawn that
// way the ring is one solid blob and merges into a handful of rectangles; drawn as the ring alone it
// shatters into a rectangle per pixel along every diagonal, and rectangles are Frames in Roblox.
// It replaces the old "contour pass" (the whole shape redrawn dark and offset), which was a second
// copy of the weapon for a worse silhouette.
export function paint(grid, palette) {
  const h = grid.rows.length + 2, w = Math.max(...grid.rows.map((r) => r.length)) + 2;
  const cell = Array.from({ length: h }, () => Array(w).fill(null));
  grid.rows.forEach((row, r) => [...row].forEach((ch, c) => {
    if (ch !== '.') cell[r + 1][c + 1] = colourOf(ch, grid, palette);
  }));
  const halo = Array.from({ length: h }, (_, r) => Array.from({ length: w }, (_, c) => {
    const n = (rr, cc) => rr >= 0 && cc >= 0 && rr < h && cc < w && cell[rr][cc];
    return n(r, c) || n(r - 1, c) || n(r + 1, c) || n(r, c - 1) || n(r, c + 1) ? OUTLINE : null;
  }));
  return { cell, halo, w, h, ox: grid.ox + 1, oy: grid.oy + 1 };
}

// Cells -> as few rectangles as possible, greedy: grow each run right, then down while the whole
// span matches. Fewer rectangles is fewer Frames in Roblox, and Frames are the renderer's budget.
function greedy(cell, w, h, ox, oy, alphaOf) {
  const used = Array.from({ length: h }, () => Array(w).fill(false));
  const out = [];
  for (let r = 0; r < h; r++) for (let c = 0; c < w; c++) {
    const col = cell[r][c];
    if (!col || used[r][c]) continue;
    let cw = 1;
    while (c + cw < w && cell[r][c + cw] === col && !used[r][c + cw]) cw++;
    let ch = 1;
    // No `used` check going down, and that is not an oversight: a cell below this run can only
    // be used by a rectangle that started in an earlier row and grew through this one, and then
    // the cell above it in THIS row would be used too - so it could never have joined the run.
    // The guard could not fire; a mutation test showed deleting it changed nothing.
    grow: while (r + ch < h) {
      for (let k = 0; k < cw; k++) if (cell[r + ch][c + k] !== col) break grow;
      ch++;
    }
    for (let j = 0; j < ch; j++) for (let k = 0; k < cw; k++) used[r + j][c + k] = true;
    out.push([+((c - ox) * PX).toFixed(4), +((r - oy) * PX).toFixed(4), +(cw * PX).toFixed(4), +(ch * PX).toFixed(4), col, alphaOf(col)]);
  }
  return out;
}

// Two ways to cut a painted grid into rectangles, and each weapon keeps whichever is cheaper:
//   in place  - every colour merged where it sits;
//   painter's - the weapon's commonest colour laid over its WHOLE silhouette (so it merges as one
//               solid shape instead of a shape full of holes), every other colour on top of it.
// Neither wins everywhere: painter's helps a weapon with one dominant material and costs one whose
// details cut the base into bands. Rectangles are Frames in Roblox, so the cheaper one is taken.
export function merge({ cell, halo, w, h, ox, oy }) {
  return [...greedy(halo, w, h, ox, oy, () => 0.9), ...body(cell, w, h, ox, oy)];
}

function body(cell, w, h, ox, oy) {
  const inPlace = greedy(cell, w, h, ox, oy, () => 1);
  const count = new Map();
  for (const row of cell) for (const c of row) if (c) count.set(c, (count.get(c) || 0) + 1);
  const base = [...count.entries()].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1))[0]?.[0];
  const painter = [
    ...greedy(cell.map((row) => row.map((c) => (c ? base : null))), w, h, ox, oy, () => 1),
    ...greedy(cell.map((row) => row.map((c) => (c && c !== base ? c : null))), w, h, ox, oy, () => 1),
  ];
  return painter.length < inPlace.length ? painter : inPlace;
}

export function compile(grid, palette) { return merge(paint(grid, palette)); }

// Forward extent of the drawn body (outline excluded), in studs from the grip - the number the
// reach test compares against the old shape's.
export function forwardExtent(grid) {
  const w = Math.max(...grid.rows.map((r) => r.length));
  let last = 0;
  for (const row of grid.rows) for (let c = 0; c < w; c++) if (row[c] && row[c] !== '.') last = Math.max(last, c + 1);
  return (last - grid.ox) * PX;
}

// THE AWAKENED FORM. While its ultimate runs, a weapon is drawn ablaze: the dark outline becomes a
// line of its own glow colour, a softer aura burns one pixel beyond that, and every glowing inlay
// runs white-hot. Same grid, same grip, same reach - light is only ever ADDED round the outside - so
// a hitbox drawn to the everyday weapon is still drawn to this one. Hand-drawn fighters do exactly
// this for a super: the prop does not change shape, it lights up. Roblox draws it (Weapons2D).
export const AURA_ALPHA = 0.45;
export function paintAwakened(grid, palette) {
  const p = paint(grid, palette);
  const glow = palette.glow || palette.accent;
  const w = p.w + 2, h = p.h + 2;
  const blank = () => Array.from({ length: h }, () => Array(w).fill(null));
  const cell = blank(), ring = blank(), aura = blank();
  p.cell.forEach((row, r) => row.forEach((c, k) => { if (c) cell[r + 1][k + 1] = c.toUpperCase() === glow.toUpperCase() ? '#FFFFFF' : c; }));
  const near = (g, r, c) => [[-1, 0], [1, 0], [0, -1], [0, 1]].some(([dr, dc]) => g[r + dr]?.[c + dc]);
  for (let r = 0; r < h; r++) for (let c = 0; c < w; c++) if (!cell[r][c] && near(cell, r, c)) ring[r][c] = glow;
  for (let r = 0; r < h; r++) for (let c = 0; c < w; c++) if (!cell[r][c] && !ring[r][c] && near(ring, r, c)) aura[r][c] = glow;
  return { cell, ring, aura, w, h, ox: p.ox + 1, oy: p.oy + 1 };
}
// Painted back to front as SOLID shapes - the aura's whole extent, then the ring's, then the weapon
// over both - the same trick as the outline halo: drawn as rings alone they shatter into a
// rectangle per pixel along every diagonal.
export function compileAwakened(grid, palette) {
  const a = paintAwakened(grid, palette);
  const glow = palette.glow || palette.accent;
  const upTo = (...layers) => a.cell.map((row, r) => row.map((_, c) => (layers.some((g) => g[r][c]) ? glow : null)));
  return [
    ...greedy(upTo(a.cell, a.ring, a.aura), a.w, a.h, a.ox, a.oy, () => AURA_ALPHA),
    ...greedy(upTo(a.cell, a.ring), a.w, a.h, a.ox, a.oy, () => 1),
    ...body(a.cell, a.w, a.h, a.ox, a.oy),
  ];
}

// The twelve weapons in the game, compiled against their own palettes. Rapier and Chakram have
// grids above but no weapon data yet, so they are not here until the engine has them.
import { WEAPONS } from './weapons/index.js';
export const WEAPON_SPRITES = Object.fromEntries(
  WEAPONS.filter((w) => GRIDS[w.id]).map((w) => [w.id, compile(GRIDS[w.id], w.palette)]),
);
export const AWAKENED_SPRITES = Object.fromEntries(
  WEAPONS.filter((w) => GRIDS[w.id]).map((w) => [w.id, compileAwakened(GRIDS[w.id], w.palette)]),
);
