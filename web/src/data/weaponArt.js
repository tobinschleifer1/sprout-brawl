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
  // OATHBLADE. A foundry falchion: a clipped chopping tip, a sawtoothed spine near the hilt, and a
  // groove down the blade that glows with Momentum. Oxblood grip, cracked iron guard.
  Sword: G(6, 5, [
    '......S..................',
    '.....SS..................',
    '.....SSA.A.A.............',
    '.hh..SSPPPPPPPPPPPPPPP...',
    'hTThhSSlmmmmmmmmmmmmmPPP.',
    'hTThhSSPPPPPPPPPPPPPPPPPP',
    '.hh..SSddddddddddddPPPPP.',
    '.....SS..........dddd....',
    '.....SS..................',
    '......S..................',
  ], { h: '#5A2E2E', l: '#FFE7B0', m: '#FFB347', d: '#5F6B7C' }),

  // GRAVE BLOOM. A long bone-white snath with a crescent of violet soul-glass hanging from an iron
  // socket and a short forward spur. The glass carries the Bloom glow along its edge.
  Scythe: G(6, 2, [
    '...........................SSSS........',
    'TTTbbbbbbbbTTbbbbbbbbbbbbbbSSSSAAA.....',
    'TTTbbbbbbbbTTbbbbbbbbbbbbbbSSSSAAAAA...',
    '...........................SSSPP.......',
    '..........................SPPPPPP......',
    '..........................PPPPPPPP.....',
    '.........................GPPPPPPPP.....',
    '........................GPPPPPPPP......',
    '......................AGPPPPPPPP.......',
    '....................AAGPPPPPPP........',
    '.................AAAGPPPPPP............',
    '.............AAAAGGPPPP................',
    '.........AAAAGGGPPP....................',
    '......AAAAPPPPP........................',
    '....AAA................................',
  ], { b: '#E8E0CC' }),

  // TWIN RIVETS. Foundry rivet guns: a boxy housing, a fat nozzle, a brass grip, and the six-round
  // magazine shown as six pips along the side - the ammo count reads off the weapon itself.
  Blasters: G(3, 4, [
    '..SS.......',
    'PPPPPPPP...',
    'PAAAAAAPSSS',
    'PPPPPPPPSSn',
    'PGkGkGkP...',
    '.TTPPT.....',
    '..HHH......',
    '..HHH......',
    '...HH......',
  ], { k: '#1A2230', n: '#FFF3D0' }),

  // STARBOUND CODEX. An iron-bound ledger with a gear-shaped clasp that glows, corner plates, and
  // the page block showing along the fore-edge.
  Grimoire: G(6, 6, [
    'TTPPPPPPPPPP.',
    'TAAAAAAAAAAWW',
    'TPPPPPPPPPPWW',
    'TPSPPPPPPSPWW',
    'TPPPPGGGPPPWW',
    'TPPPGGwGGPPWW',
    'TPPPGwwwGPSWW',
    'TPPPGGwGGPPWW',
    'TPPPPGGGPPPWW',
    'TPSPPPPPPSPWW',
    'TPPPPPPPPPPWW',
    'TTPPPPPPPPPP.',
  ], { W: '#F0E7D2', w: '#FFFFFF' }),

  // HEADSMAN. A bearded executioner's axe: a haft you can see the weight on, a crescent bit edged
  // in rust-red that heats with Momentum, and a reverse spike.
  Axe: G(8, 10, [
    '....................................',
    '....................................',
    '........................TPr.........',
    '........................TPPr........',
    '........................TPPPr.......',
    '.......................TTPPPPr......',
    '.......................TTPPPPPr.....',
    '.................S.....TTPPPPPPr....',
    'SS...............SS...TTPPPPPPPr....',
    'SHHHHHHHSSSHHHHHHHHHHHHPPPPPPPPr....',
    'SHHHHHHHSSSHHHHHHHHHHHHPPPPPPPPPr...',
    'SS...............SS...TTPPPPPPPPr...',
    '.................S.....TTPPPPPPPPPr.',
    '......................TTPPPPPPPPPr..',
    '......................TTPPPPPPPPPPr.',
    '......................TPPPPPPPPPPPr.',
    '.....................TPPPPPPPPPrrr..',
    '....................TPPPPPPrrr......',
    '...................TPrrrr...........',
  ], { r: '#B4462E' }),

  // TOLLGATE. Almost all haft, three iron bands, a leaf point, and a crimson swallowtail pennant
  // under the head - it shows which way you face and roughly how far you reach, even zoomed out.
  Pike: G(13, 3, [
    '.........................................................G...',
    '.............................................SS.......AAAAA..',
    'SSPPPPPPPPPPPTTTTTTTTPPPPPPTPPPPPPPPPPTPPPPPPSSSSAAAAAAAAAAAA',
    'SSPPPPPPPPPPPTTTTTTTTPPPPPPTPPPPPPPPPPTPPPPPPSSSSAAAAAAAAAAA.',
    '.............................................SS.cccc..AAAA...',
    '................................................ccccccc......',
    '................................................cccccc.......',
    '................................................ccccccc......',
    '................................................cc..ccc......',
    '................................................c....cc......',
  ], { c: '#A8322E' }),

  // OVERDRIVE KNUCKLES. A hydraulic fist: a riveted bracer, twin pistons on the back of the hand,
  // exhaust vents, and three glowing knuckle plates that flare in Overdrive.
  Gauntlets: G(4, 4, [
    '....ii.ii...',
    '...SSSSSSS..',
    'TTTSPPPPPPG.',
    'TvTSPPPPPPPG',
    'TvTSkkkkkPPG',
    'TTTSPPPPPPG.',
    '...SSSSSSS..',
    '....ii.ii...',
  ], { v: '#FF9A4A', k: '#5A2018', i: '#C8CED8' }),

  // GROUNDBREAKER. A forge sledge: a stone head bound by two iron bands, a glowing crack through
  // its core that widens with Momentum, and a squared spike on the reverse.
  Hammer: G(10, 9, [
    '.............................sPPPPPPPPPs',
    '.............................sPPPPPPPPPs',
    '.............................IIIIIIIIIII',
    '.............................sPPPGPPPPPs',
    '.......................SSSSSSsPPPPGPPPPs',
    '.......................SSSSSSsPPPPPGPPPs',
    'SS...........................PPPPGPPPPs',
    'SHHHHHHHHHHHHHHHHHHHHHHHHHHHHPPPPGGPPPs',
    'SHHHHHHHHHHHHHHHHHHHHHHHHHHHHPPPPPGPPPs',
    'SS...........................PPPPPGPPPs',
    '.......................SSSSSSsPPPPGPPPPs',
    '.......................SSSSSSsPPPPGPPPPs',
    '.............................sPPPPGPPPPs',
    '.............................IIIIIIIIIII',
    '.............................sPPPPPPPPPs',
    '.............................sPPPPPPPPPs',
  ], { s: '#5A5048', I: '#2A2420' }),

  // HEARTSTRING. A recurve in green-bronze: limbs that sweep forward and flick back at the tips, a
  // wrapped grip, and a straight string - the one straight line on the weapon, and the read.
  Longbow: G(0, 12, [
    'aP.......',
    'a.PP.....',
    'a..PP....',
    'a...PP...',
    'a....PP..',
    'a....PP..',
    'a.....PP.',
    'a.....PP.',
    'a......PP',
    'a......PP',
    'a.....SSS',
    'a.....SSS',
    'a.....SSS',
    'a.....SSS',
    'a......PP',
    'a......PP',
    'a.....PP.',
    'a.....PP.',
    'a....PP..',
    'a....PP..',
    'a...PP...',
    'a..PP....',
    'a.PP.....',
    'aP.......',
  ], { a: '#F0E2C0' }),

  // WRECKING CHAIN. A riveted wrecking ball on a chain drawn link by link (the number of links IS
  // the reach), four heavy spikes, and a riveted band that catches the Snare glow.
  Flail: G(9, 7, [
    '......................................P.......',
    '......................................A.......',
    '....................................PPPPP.....',
    '..................................PPPPPPPPP...',
    '..................................PkPPPPPPP...',
    'SS...............................PPPPPPPPPPP..',
    'SHHHHHHHHHHSS.oo.oo.oo.oo.oo.oooPPPPPPPPPPPAA.',
    'SHHHHHHHHHHSS.oo.oo.oo.oo.oo.oooPGiGiGiGiGPAA.',
    'SS...............................PPPPPPPPPPP..',
    '..................................PPPPPPPPP...',
    '..................................PdddddddP...',
    '....................................PPPPP.....',
    '......................................A.......',
    '......................................P.......',
  ], { o: '#6E7684', k: '#C8CED8', i: '#FFFFFF', d: '#4A505C' }),

  // BASTION. A salvaged blast door carried as a tower shield: a riveted slab, a viewport slit that
  // shimmers gold in Counterguard's window, and hazard stripes along the bottom edge.
  Shield: G(3, 12, [
    'bbbbbbbbb',
    'bPPPPPPPb',
    'bPrPPPrPb',
    'bPPPPPPPb',
    'bPSSSSSPb',
    'bPPPPPPPb',
    'bPPPPPPPb',
    'bPPPPPPPb',
    'bPrPPPrPb',
    'bPPPPPPPb',
    'bPkkkkkPb',
    'bPkGGGkPb',
    'bPkkkkkPb',
    'bPPPPPPPb',
    'bPrPPPrPb',
    'bPPPPPPPb',
    'bPPPPPPPb',
    'bPSSSSSPb',
    'bPPPPPPPb',
    'bPrPPPrPb',
    'byzyzyzyb',
    'bzyzyzyzb',
    'bbbbbbbbb',
    '.TTTTTTT.',
  ], { b: '#B08A4A', r: '#8A6E4A', k: '#1A2230', y: '#E8B04A', z: '#2A303C' }),

  // TWINFANG. Two curved daggers with crimson crystal edges: the front blade curls up at the tip,
  // the reverse one trails behind the hand. The silhouette says "a pair" in any single frame.
  Daggers: G(10, 3, [
    '....................cc',
    '..................ccPP',
    'ee..........SSPPPPPPP.',
    'eePPPPPPPTTSSPPPPPPP..',
    '.ccccccTTTTSS.........',
    '...........SS.........',
  ], { c: '#FF4A6A', e: '#A0ACBE' }),

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
  const outline = greedy(halo, w, h, ox, oy, () => 0.9);
  const inPlace = greedy(cell, w, h, ox, oy, () => 1);
  const count = new Map();
  for (const row of cell) for (const c of row) if (c) count.set(c, (count.get(c) || 0) + 1);
  const base = [...count.entries()].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1))[0]?.[0];
  const painter = [
    ...greedy(cell.map((row) => row.map((c) => (c ? base : null))), w, h, ox, oy, () => 1),
    ...greedy(cell.map((row) => row.map((c) => (c && c !== base ? c : null))), w, h, ox, oy, () => 1),
  ];
  return [...outline, ...(painter.length < inPlace.length ? painter : inPlace)];
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

// The twelve weapons in the game, compiled against their own palettes. Rapier and Chakram have
// grids above but no weapon data yet, so they are not here until the engine has them.
import { WEAPONS } from './weapons/index.js';
export const WEAPON_SPRITES = Object.fromEntries(
  WEAPONS.filter((w) => GRIDS[w.id]).map((w) => [w.id, compile(GRIDS[w.id], w.palette)]),
);
