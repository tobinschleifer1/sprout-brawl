// The ultimate's cutscene beat, as a pure function of how many frames ago it was activated.
//
// The engine already stops the world for ULTIMATE.freezeFrames (26) when an ultimate fires, the
// caster included, and makes the caster invincible for ULTIMATE.invincibleFrames (22). This decides
// what those frames LOOK like, identically in both builds (roblox/src/client/UltCinematic.luau,
// replayed by tests/cinematic-parity.luau): the scene dims, the camera punches in on the caster,
// a banner sweeps across - 6 frames in, 12 held, 6 out, all inside the freeze - and the caster
// glows gold for exactly the frames they cannot be hit, so opponents can SEE the invincibility.
//
// Driven by the frame count and nothing else: a Roblox client times it from snapshot frames, the
// web from match.frame, so every screen shows the same beat on the same frame.
import { ULTIMATE } from '../config.js';

export const FREEZE = ULTIMATE.freezeFrames;
export const INVINCIBLE = ULTIMATE.invincibleFrames;
export const BAND = { in: 6, hold: 12, out: 6 };
export const ZOOM = 1.35;
export const DIM = 0.65;                 // overlay alpha: the scene at 35% brightness

const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
const easeOut = (k) => 1 - (1 - k) * (1 - k);

// Whether an ultimate's cutscene is finished with, so its record can be dropped. NOT the same as
// "not active": a Roblox client draws a few frames behind its newest snapshot, so the event always
// arrives while the drawn frame is still short of it - elapsed is negative - and a renderer that
// dropped the record then never showed the cutscene at all. Only the far side ends it.
export function ultOver(elapsed) {
  return elapsed >= Math.max(FREEZE, INVINCIBLE);
}

export function ultCinematic(elapsed) {
  const e = elapsed;
  if (!(e >= 0) || e >= FREEZE) return { active: false, dim: 0, zoom: 1, slide: 1, band: 0, glow: e >= 0 && e < INVINCIBLE };
  // dim: in over 4 frames, out over the last 4 of the freeze
  const dim = DIM * Math.min(clamp(e / 4, 0, 1), clamp((FREEZE - e) / 4, 0, 1));
  // camera: punch in over 8 frames, ease back over the last 4
  const zoom = 1 + (ZOOM - 1) * Math.min(easeOut(clamp(e / 8, 0, 1)), clamp((FREEZE - e) / 4, 0, 1));
  // banner: slide from -1 (off left) to 0 (centred), hold, then to +1 (off right)
  const outAt = BAND.in + BAND.hold;
  let slide, band;
  if (e < BAND.in) { slide = -1 + easeOut(e / BAND.in); band = e / BAND.in; }
  else if (e < outAt) { slide = 0; band = 1; }
  else { const k = clamp((e - outAt) / BAND.out, 0, 1); slide = k * k; band = 1 - k; }
  return { active: true, dim, zoom, slide, band, glow: e < INVINCIBLE };
}

// Where the camera looks while it punches in: the caster's centre pulled toward the middle of the
// screen as far as the zoom has gone, so at full zoom the caster is framed and at zoom 1 the
// camera is exactly where the ordinary follow-camera put it.
export function punch(x, y, ppu, fx, fy, zoom) {
  const k = (zoom - 1) / (ZOOM - 1);
  return { x: x + (fx - x) * k, y: y + (fy - y) * k, ppu: ppu * zoom };
}

// The gold behind the caster for the frames they cannot be hit, as the shape list the disaster
// painter already takes. The body occludes the middle, so what shows is a gold rim around it.
export const GOLD = '#FFD45A';
export function glowShapes(c, fx, fy, h) {
  if (!c.glow) return [];
  const cy = fy + h * 0.5;
  return [
    ['e', fx, cy, h * 0.62, h * 0.72, GOLD, 0.30],
    ['e', fx, cy, h * 0.46, h * 0.60, GOLD, 0.55],
    ['e', fx, cy, h * 0.34, h * 0.52, '#FFF4C8', 0.45],
  ];
}

// The banner in screen pixels for a W x H screen. A band tilted up to the right slides across
// the screen; along it sit the caster (feet on the band's lower edge), their weapon, then the
// ultimate's name. `along(d)` is a point d pixels from the band's centre along its axis - y grows
// downward on both screens, so a negative tilt climbs to the right.
export const TILT = -0.14;
export function bannerLayout(c, W, H) {
  if (!c.active || c.band <= 0) return null;
  // Sized off the narrower of height and a 16:9 width, so a tall phone screen still fits the name.
  const h = Math.min(H, W * 0.5625) * 0.17;
  const cx = W / 2 + c.slide * W * 1.15, cy = H * 0.40;
  const cos = Math.cos(TILT), sin = Math.sin(TILT);
  const along = (d, n = 0) => [cx + cos * d - sin * n, cy + sin * d + cos * n];
  const [px, py] = along(-h * 2.1, h * 0.5);
  const [wx, wy] = along(-h * 0.9);
  const [tx, ty] = along(h * 1.6);
  return { cx, cy, w: W * 1.6, h, rot: TILT, alpha: c.band, stripe: h * 0.1,
    portrait: { x: px, y: py, size: h * 1.3 },
    weapon: { x: wx, y: wy, size: h * 0.85 },
    text: { x: tx, y: ty, size: h * 0.42 } };
}
