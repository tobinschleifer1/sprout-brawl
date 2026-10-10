// Danger (readability): a fighter close to being KO'd smokes, so everyone can see who is one good
// hit from gone without reading the HUD (roblox/src/client/Danger.luau, held to this by
// tests/danger-parity.luau).
//
// "Close" is measured, not guessed: dangerPercent is the lowest percent at which REF - a strong,
// ordinary hit from the middle of the stage - carries a fighter of that weight out
// (knockback.carriesOut, the kill hit's own prediction). Smoke starts LEAD points before it and is
// at full strength SPAN points later. Pure and deterministic on the match frame.
import { launchSpeed, stunSpeed, hitstun, velocity, carriesOut } from '../engine/knockback.js';

// REF is tuned to where fighters really go out: across 24 bot matches the median side or top KO was
// at 122% (a quarter by 105%), and REF puts a 100-weight on Foundry Floor at 122% - so smoke starts
// around 100%. A first REF (growth 5) put it at 251%, past nearly every real KO.
export const DANGER = { ref: { damage: 15, base: 30, growth: 8.5, angle: 45 }, lead: 20, span: 60, puffs: 6, rise: 3.4 };

const cache = new Map();
export function dangerPercent(weight, blast) {
  const key = `${weight}|${blast.left}|${blast.right}|${blast.top}`;
  if (cache.has(key)) return cache.get(key);
  const R = DANGER.ref;
  let found = 999;
  for (let p = 0; p <= 400; p++) {
    const after = p + R.damage;
    const v = velocity(launchSpeed(R.base, R.growth, R.damage, after, weight), R.angle, 1, null);
    if (carriesOut(0, 0, v.vx, v.vy, hitstun(stunSpeed(R.base, R.growth, R.damage, after, weight)), blast)) { found = p; break; }
  }
  cache.set(key, found);
  return found;
}

// How much danger, 0 (none) to 1, for `percent` against a danger percent of `at`.
export function dangerLevel(percent, at) {
  const k = (percent - (at - DANGER.lead)) / DANGER.span;
  return k < 0 ? 0 : k > 1 ? 1 : k;
}

// Smoke rising off the top of a fighter at (x, y) `h` tall, at danger `k`, on match frame `frame`:
// ['r', x, y, w, h, colour, alpha] in world units, y up. Embers join it past two thirds.
export function dangerShapes(x, y, h, k, frame) {
  const out = [];
  if (k <= 0) return out;
  const n = 1 + Math.floor((DANGER.puffs - 1) * k + 0.5);
  for (let i = 0; i < n; i++) {
    const phase = (frame * 0.018 * (1 + k) + i / n) % 1;
    const px = x + Math.sin(phase * 6 + i * 2.1) * 0.45;
    const py = y + h * 0.95 + phase * DANGER.rise;
    const s = 0.7 + 0.8 * phase;
    // mid-grey: a dark smoke vanished against the night stages, a pale one against the bright ones
    out.push(['r', px - s / 2, py - s / 2, s, s, '#9C9790', (1 - phase) * (0.35 + 0.45 * k)]);
    if (k > 0.66 && i % 2 === 0) out.push(['r', px - 0.13, py + 0.1, 0.26, 0.26, '#FF7A3A', (1 - phase) * 0.9]);
  }
  return out;
}

// The bullwhip's mark (CRACK, whip.js): a gold crack-sigil over the head of the fighter its tip
// marked, so everyone can see the next tip on them will crack - blinking through its last second.
// `left` is frames until it fades. ['r', x, y, w, h, colour, alpha], world units, y up.
export const MARK = { lift: 1.0, blinkFrom: 60 };
export function markShapes(x, y, h, left, frame) {
  const out = [];
  if (!(left > 0)) return out;
  const a = left < MARK.blinkFrom && Math.floor(frame / 4) % 2 === 1 ? 0.35 : 1;
  const cx = x, cy = y + h + MARK.lift;
  const s = 0.45 + 0.06 * Math.sin(frame * 0.3);
  for (const [colour, pad] of [['#120E16', 0.1], ['#FFD25A', 0]]) {
    out.push(['r', cx - 0.11 - pad, cy - s - pad, 0.22 + 2 * pad, 2 * s + 2 * pad, colour, a]);
    out.push(['r', cx - s - pad, cy - 0.11 - pad, 2 * s + 2 * pad, 0.22 + 2 * pad, colour, a]);
  }
  out.push(['r', cx - 0.08, cy - 0.08, 0.16, 0.16, '#FFFFFF', a]);
  return out;
}
