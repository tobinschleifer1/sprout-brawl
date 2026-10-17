// The grids the Roblox build draws that the web build does not export: Roblox-only weapons'
// grids (LOCAL_GRIDS), one-of-a-pair units (SINGLE_GRIDS), and gridOf, which also reads any grid
// out of web/src/data/weaponArt.js's source. Shared by gen-roblox-art.mjs (the game's art) and
// cosmetic-sheet.mjs (skin designs), so the two can never disagree about a weapon's shape.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = path.dirname(fileURLToPath(import.meta.url));
export const WEB = path.join(HERE, '../../web/src/data');
// Roblox-only weapons and their palettes (must match RobloxWeapons.luau)
export const ROBLOX_PALETTES = {
  Chakram: { primary: '#C0C8D4', secondary: '#1E4A4A', tertiary: '#0F2626', accent: '#F4E8C0', glow: '#3CE8C8' },
  RocketBoots: { primary: '#D76B32', secondary: '#465366', tertiary: '#17212D', accent: '#FFE3AF', glow: '#62E8FF' },
};
export const G = (ox, oy, rows, ink = {}) => ({ ox, oy, rows, ink });
// Grids for weapons weaponArt.js has none for (the web is left as it is): one boot, ankle-anchored,
// drawn once on each foot (GPT-6-Astra's design).
export const LOCAL_GRIDS = {
  RocketBoots: G(4, 8, [
    '..TTTTTT......',
    '..TAAAAT......',
    '..TPPPST......',
    '..TPGGST......',
    '.TSPGGST......',
    '.TSPPPST......',
    '.TSPPPPTTT....',
    '.TSSPPPPPATT..',
    '.TTSSSSSSSST..',
    '..TTTTTTTTTT..',
  ]),
};
// One of a pair, for weapons held one in each hand (src/client/DualWield.luau). The web's grids
// draw the pair as one picture in one hand; these are the single unit each hand holds. A weapon
// whose grid is already one unit (Blasters, Gauntlets) needs none: each hand draws its grid.
// Reach is kept: the dagger's tip is as far ahead of its grip as the pair's front blade (11 px).
export const SINGLE_GRIDS = {
  Daggers: G(4, 3, [
    '..............AC',
    '.....SS.....AAPq',
    '.....SS.ACCCcPS.',
    'eTjTjGGASSSSSS..',
    '.TTTTSS.........',
    '.....SS.........',
  ], { c: '#FF4A6A', C: '#FFB0BE', q: '#8A1A30', e: '#A0ACBE', j: '#4A3A5A' }),
  Chakram: G(4, 4, [
    '..PPPPP..',
    '.PPGGGPP.',
    'PPG...GPP',
    'PG.....GP',
    'PG.....GP',
    'PG.....GP',
    'PPG...GPP',
    '.PPGGGPP.',
    '..PPPPP..',
  ]),
};
const { WEAPON_BY_ID } = await import(`${WEB}/weapons/index.js`);
export const paletteOf = (id) => ROBLOX_PALETTES[id] || WEAPON_BY_ID[id].palette;
// weaponArt.js exports every grid it holds, including ones (the Chakram) it has no weapon data for
const { GRIDS } = await import(`${WEB}/weaponArt.js`);
export const gridOf = (id) => {
  const g = LOCAL_GRIDS[id] || GRIDS[id];
  if (!g) throw new Error(`no grid for ${id}`);
  return g;
};
