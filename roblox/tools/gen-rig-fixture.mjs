// The jointed rig's fixture: web/src/render2d/rig.js driven over ordinary poses and every edge it
// has (a hand at the shoulder, a thrust past full reach, a planted foot under a deep crouch or a hop,
// a full tuck, a knockdown's unplanted foot), for tests/rig-parity.luau to replay through Rig.luau.
// Regenerated on every check.sh run and gitignored, like every fixture here.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const R = await import('../../web/src/render2d/rig.js');

let seed = 20261011;
const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
const span = (lo, hi) => lo + (hi - lo) * rnd();

const arms = [], legs = [];
const arm = (sx, sy, ang, ext, bend, h) => arms.push({ in: [sx, sy, ang, ext, bend, h], out: R.armPose(sx, sy, ang, ext, bend, h) });
const leg = (hx, hy, rot, ll, bob, planted, tuck) => legs.push({ in: [hx, hy, rot, ll, bob, planted, tuck], out: R.legPose(hx, hy, rot, ll, bob, planted, tuck) });

// edges
for (const ang of [0, Math.PI / 2, Math.PI, -Math.PI / 2, 2.9, -3.1]) {
  arm(0.6, 1.9, ang, 1, 0, 5.2);          // at rest
  arm(0.6, 1.9, ang, 0, 0, 5.2);          // the hand at the shoulder
  arm(-0.4, 1.9, ang, 1.75, 1, 5.2);      // a full thrust, more than two bones' reach
  arm(0.6, 1.9, ang, 0.3, 1, 5.2);        // pulled in, fully bent
}
for (const rot of [0, 0.35, -0.35, 1.4, -2.9]) {
  leg(-0.33, 1.77, rot, 1.77, 0, true, 0);
  leg(0.33, 1.77, rot, 1.77, -0.6, true, 0);   // a deep crouch on planted feet
  leg(0.33, 1.77, rot, 1.77, 0.5, true, 0);    // a hop: the foot cannot reach the floor
  leg(0.33, 1.77, rot, 1.77, -0.6, false, 1);  // airborne, fully tucked
  leg(0.33, 1.77, rot, 1.77, 1.77, true, 0);   // a foot pulled right up to the hip
}
// the ordinary spread
for (let i = 0; i < 400; i++) {
  arm(span(-0.5, 0.7), span(1, 2.5), span(-3.2, 3.2), span(0, 2), rnd() < 0.3 ? 0 : rnd(), span(4, 7));
  leg(span(-0.4, 0.4), span(1.4, 2.4), span(-3.2, 3.2), span(1.4, 2.4), span(-0.8, 0.8), rnd() < 0.5, rnd() < 0.5 ? 0 : rnd());
}

fs.writeFileSync(path.join(HERE, '../tests/rig-fixture.json'), JSON.stringify({ rig: R.RIG, arms, legs }));
console.log(`rig fixture: ${arms.length} arms, ${legs.length} legs`);
