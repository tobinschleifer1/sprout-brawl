// A weapon drop on the stage (DROPS in config.js), as shapes both builds draw
// (roblox/src/client/DropShapes.luau, held to this by tests/drop-parity.luau).
//
//   falling   a column of light above it, so you see where it will land before it does
//   always    a gold glow on the ground under it, pulsing
//   fresh     a pixel weapon cache: a wooden crate, iron bands, a gold clasp and a glint
//   thrown    the weapon itself, lying where it landed: `sprite` says which and how it lies
//   fading    in its last two seconds it blinks, as an item about to go does
//
// Pure and deterministic - driven by the match's frame counter, never wall-clock or a generator -
// so the two builds draw the same drop on the same frame. Shapes in world units, y up:
// ['r', x, y, w, h, colour, alpha] and ['e', cx, cy, rx, ry, colour, alpha].
export const FADE = 120;               // frames before it goes in which it blinks
export const BEAM = 12;                // the falling column's height

// `d` is a drop (combat.drops), `frame` the match frame. Returns { shapes, sprite }: `sprite` is
// { id, x, y, angle, alpha } for a thrown weapon lying there, drawn after the shapes; null for a
// fresh drop.
export function dropShapes(d, frame) {
  const out = [];
  const blink = d.onGround && d.life < FADE && Math.floor(frame / 8) % 2 === 0 ? 0.45 : 1;
  const pulse = 0.5 + 0.5 * Math.sin(frame * 0.12 + d.x);
  const bob = d.onGround ? Math.sin(frame * 0.08 + d.x) * 0.12 : 0;
  const y = d.y + bob;
  if (!d.onGround) {
    out.push(['r', d.x - 0.9, d.y, 1.8, BEAM, '#FFF3C4', 0.16 * blink]);
    out.push(['r', d.x - 0.35, d.y, 0.7, BEAM, '#FFFFFF', 0.22 * blink]);
  }
  out.push(['e', d.x, d.y + 0.15, 1.5 + 0.2 * pulse, 0.45, '#FFD54A', (0.22 + 0.14 * pulse) * blink]);
  if (d.look) {
    return { shapes: out, sprite: { id: d.look, x: d.x - 1, y: y + 0.45, angle: 0.25, alpha: blink } };
  }
  // the cache
  out.push(['r', d.x - 0.7, y, 1.4, 1.0, '#8A5A2B', blink]);
  out.push(['r', d.x - 0.78, y + 0.92, 1.56, 0.24, '#A6703A', blink]);              // the lid
  out.push(['r', d.x - 0.7, y + 0.22, 1.4, 0.14, '#4E3016', blink]);                // iron bands
  out.push(['r', d.x - 0.7, y + 0.62, 1.4, 0.14, '#4E3016', blink]);
  out.push(['r', d.x - 0.18, y + 0.4, 0.36, 0.32, '#FFD54A', blink]);              // the clasp
  // a glint that travels across the lid every two seconds
  const g = (frame % 120) / 120;
  if (g < 0.3) out.push(['r', d.x - 0.78 + g / 0.3 * 1.4, y + 0.98, 0.16, 0.16, '#FFFFFF', 0.9 * blink]);
  return { shapes: out, sprite: null };
}
