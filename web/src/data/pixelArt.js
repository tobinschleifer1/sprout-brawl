// Hand-drawn characters: the grids a player paints, and the alphabet they paint in.
//
// The fighter in this game is a PUPPET, not a sprite: a head, a torso, two arms and two legs, each
// rotated and squashed every frame by channels.js. A single drawn sprite could not be animated by
// any of that - it would throw away the wind-ups, the follow-through, the smears, the weapon in the
// hand, the axe dragging on the floor. So a player draws the PARTS, and the rig animates what they
// drew exactly as it animates the built-in shapes. Draw only a head and the rest of the character
// stays procedural; draw everything and none of the animation changes.
//
// Cells are palette INDICES, not colours. `1` is "whatever this character's head colour is", so a
// drawing keeps working when the player moves a swatch - they can draw the shape once and recolour
// it forever. Seven inks plus transparent is a deliberately small palette; it is also the reason a
// character is a few hundred bytes instead of a bitmap.

// Grid sizes, chosen from the rig's own proportions (h = 5.2, r = 1.1):
//   head   1.27 x 1.27 studs, square
//   torso  1.76 x 1.87 studs, near square
//   arm    0.37 x 1.56 studs, and the leg 0.46 x 1.77 - both far taller than they are wide, but a
//          four-pixel-wide grid is miserable to draw in, so they get five and the art is stretched
//          to the limb. Nobody has ever noticed a limb being 20% wide.
export const PART_GRIDS = {
  head: { w: 12, h: 12, name: 'Head' },
  torso: { w: 12, h: 13, name: 'Torso' },
  arm: { w: 5, h: 14, name: 'Arms' },
  leg: { w: 5, h: 14, name: 'Legs' },
};
export const PART_IDS = Object.keys(PART_GRIDS);

// The ink a cell can hold. `.` is transparent - drawing IS shaping, so a character's silhouette
// comes from where the player left the grid empty.
export const INKS = [
  { id: '.', name: 'Erase', slot: null },
  { id: '1', name: 'Head colour', slot: 'primary' },
  { id: '2', name: 'Torso colour', slot: 'secondary' },
  { id: '3', name: 'Leg colour', slot: 'tertiary' },
  { id: '4', name: 'Trim', slot: 'accent' },
  { id: '5', name: 'Highlight', slot: 'glow' },
  { id: 'k', name: 'Outline', fixed: '#1b1526' },
  { id: 'w', name: 'White', fixed: '#ffffff' },
];
export const INK_IDS = INKS.map((i) => i.id);
const INK_SET = new Set(INK_IDS);

// Resolve a cell to a real colour for this character, or null for transparent.
export function inkColour(ch, palette) {
  const ink = INKS.find((i) => i.id === ch);
  if (!ink || ink.id === '.') return null;
  return ink.fixed || palette[ink.slot] || '#ff00ff';
}

export const blankPart = (part) => '.'.repeat(PART_GRIDS[part].w * PART_GRIDS[part].h);

// Rebuild a grid out of known-good cells. Same contract as the avatar sanitiser: whatever arrives,
// a valid grid of exactly the right length comes out, because this feeds the renderer directly.
export function sanitizePart(part, raw) {
  const g = PART_GRIDS[part];
  if (!g) return null;
  const want = g.w * g.h;
  const src = typeof raw === 'string' ? raw : '';
  let out = '';
  for (let i = 0; i < want; i++) { const c = src[i]; out += (c && INK_SET.has(c)) ? c : '.'; }
  return out;
}

// An `art` bag holds only the parts the player actually drew. A part that is empty or absent falls
// back to the built-in shape, so "draw just a hat" is a supported way to use this.
export function sanitizeArt(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const out = {};
  for (const part of PART_IDS) {
    if (raw[part] == null) continue;
    const px = sanitizePart(part, raw[part]);
    if (px && /[^.]/.test(px)) out[part] = px;      // an all-transparent part is the same as none
  }
  return Object.keys(out).length ? out : null;
}

export const hasArt = (avatar, part) => !!(avatar && avatar.art && avatar.art[part]);

// Read and write single cells without the caller doing index arithmetic.
export const cellAt = (px, part, x, y) => px[y * PART_GRIDS[part].w + x] || '.';
export function setCell(px, part, x, y, ink) {
  const g = PART_GRIDS[part];
  if (x < 0 || y < 0 || x >= g.w || y >= g.h) return px;
  const i = y * g.w + x;
  return px.slice(0, i) + ink + px.slice(i + 1);
}
