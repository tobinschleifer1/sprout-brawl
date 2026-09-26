// The shield as an energy shell, after the user's references: a bright rim with a softer glow
// outside it, a faint fill, and lightning veins crawling inside that re-form every few frames. As
// it weakens, gaps open in the rim and it flickers - a shell breaking into fragments. Where it
// is struck, the rim flares and a ripple runs out from the impact.
//
// Pure and deterministic - the crackle comes from an integer hash of the frame, not a random
// generator - so both builds draw the same shell (roblox/src/client/Shield.luau, held to this by
// tests/shield-parity.luau). Shapes, in world units, y up: ['e', cx, cy, rx, ry, colour, alpha]
// and ['l', x0, y0, x1, y1, width, colour, alpha].

export const RIM = 28;          // rim segments
export const VEINS = 7;         // lightning veins inside
export const CRACKLE = 5;       // frames a vein pattern holds before it re-forms

// An integer hash in [0, 1): exact in doubles, so JavaScript and Luau agree to the bit.
export function hash(i, j) {
  return (((i * 7919 + j * 104729 + 12345) % 2147483647) * 16807 % 2147483647) / 2147483647;
}

// `hp` is 0..1 (the channel's bubble), `frame` an integer clock, `hit` null or
// { k: 1 fresh .. 0 gone, x, y } - the last impact, from the effects state.
export function shieldShapes(x, cy, h, hp, frame, hit) {
  const out = [];
  if (!(hp > 0)) return out;
  const R = h * 0.62 * (0.55 + hp * 0.45);
  const flash = hit ? hit.k : 0;
  const low = hp < 0.3;
  const flicker = low ? 0.55 + 0.45 * (Math.floor(frame / 3) % 2) : 1;
  const tick = Math.floor(frame / CRACKLE);
  const P = (a, r) => [x + Math.cos(a) * r, cy + Math.sin(a) * r];

  // body of the shell
  out.push(['e', x, cy, R * 1.12, R * 1.12, '#3FB8FF', 0.12 * flicker]);
  out.push(['e', x, cy, R, R, '#4FC8FF', (0.28 + 0.2 * flash) * flicker]);
  out.push(['e', x, cy, R * 0.72, R * 0.72, '#BFF4FF', 0.08 * flicker]);

  // the lightning veins: rim to the inside, three zigzag legs each
  for (let v = 0; v < VEINS; v++) {
    let a = hash(v, tick) * Math.PI * 2;
    let [px, py] = P(a, R * 0.96);
    for (let leg = 1; leg <= 3; leg++) {
      a += (hash(v * 10 + leg, tick) - 0.5) * 0.9;
      const [qx, qy] = P(a, R * (0.96 - leg * 0.2));
      out.push(['l', px, py, qx, qy, 0.14, '#E6FDFF', 0.7 * flicker]);
      px = qx; py = qy;
    }
  }

  // the rim, with gaps opening as the shield weakens, and a glow outside it
  const gap = (1 - hp) * 0.55;
  const hitA = hit ? Math.atan2(hit.y - cy, hit.x - x) : 0;
  for (let i = 0; i < RIM; i++) {
    if (hash(i + 100, Math.floor(frame / 6)) < gap) continue;
    const a0 = (i / RIM) * Math.PI * 2, a1 = ((i + 1) / RIM) * Math.PI * 2;
    // how close this segment is to the impact, 1 at the impact
    let near = 0;
    if (hit) {
      const mid = (a0 + a1) / 2;
      const d = Math.abs(Math.atan2(Math.sin(mid - hitA), Math.cos(mid - hitA)));
      near = Math.max(0, 1 - d / 0.7) * flash;
    }
    const [x0, y0] = P(a0, R * 1.06), [x1, y1] = P(a1, R * 1.06);
    out.push(['l', x0, y0, x1, y1, 0.6, '#5FD0FF', 0.35 * flicker]);
    const [u0, v0] = P(a0, R), [u1, v1] = P(a1, R);
    out.push(['l', u0, v0, u1, v1, 0.3 + 0.55 * near, near > 0.3 ? '#FFFFFF' : '#DFFBFF', Math.min(1, 0.9 * flicker + near)]);
  }

  // the ripple running out from a fresh impact
  if (hit && flash > 0) {
    const rr = R * (1 + (1 - flash) * 0.3);
    for (let s = -4; s < 4; s++) {
      const a0 = hitA + s * 0.2, a1 = a0 + 0.2;
      const [x0, y0] = P(a0, rr), [x1, y1] = P(a1, rr);
      out.push(['l', x0, y0, x1, y1, 0.26, '#FFFFFF', 0.8 * flash * (1 - Math.abs(s + 0.5) / 4)]);
    }
  }
  return out;
}
