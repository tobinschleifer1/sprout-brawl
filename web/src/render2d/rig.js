// The jointed rig: where elbows and knees go. Pure numbers, no canvas - both renderers draw from
// it (renderer2d.js, and Fighter2D.luau through its line-for-line port Rig.luau, replayed against
// this file by check.sh), so the two builds put every joint in the same place.
//
// A limb is two EQUAL bones between a root (shoulder, hip) and an end (hand, foot). Equal bones are
// what make this solvable without dividing by anything: the joint sits on the perpendicular bisector
// of root-to-end, `off` to one side of the midpoint, and when the end is out of reach the limb lies
// straight and both bones stretch to cover it, as the one-piece arm always stretched for a thrust.
//
// THE GRIP IS AN INVARIANT. The hand is not where the bones happen to end: it is the exact point the
// weapon is drawn from (renderer2d.js, `hx`/`hy`), the point every blade-to-hitbox test checks, and
// the arm is solved to meet it. Bones a little longer than the shoulder-to-hand distance are what
// bend the elbow at rest; the `bend` channel lengthens them further for a wind-up - more elbow, the
// hand exactly where it was. Nothing here moves a weapon, a hitbox or a frame of timing.
//
// Directions follow the rig: local +X is forward (the fighter's facing is a mirror applied outside),
// +Y is up.

export const RIG = {
  hip: 0.34, shoulder: 0.70, head: 0.78,   // joint heights, fractions of the fighter's height
  arm: 0.30,                               // shoulder to hand, fraction of height, before `ext`
  armBone: 0.155,                          // each arm bone at rest: 2 x 0.155 > 0.30, so a soft elbow
  armBend: 0.06,                           // added to each bone at bend = 1: about a right angle
  legBone: 0.515,                          // each leg bone, fraction of the leg: a soft knee at rest
  tuck: 0.45,                              // knee = 1 pulls the foot this far in toward the hip
};

// A limb from (sx, sy) toward the unit direction (ux, uy), its end `d` along it, two bones of length
// `bone`. `side` +1 puts the joint clockwise of the limb (an elbow: below an arm pointing forward,
// behind one hanging down); -1 anticlockwise (a knee: in front of a leg pointing down).
// Returns the joint (jx, jy), the end (ex, ey) and the length each bone is drawn at.
export function solveLimb(sx, sy, ux, uy, d, bone, side) {
  const half = d / 2;
  const off = Math.sqrt(Math.max(0, bone * bone - half * half)) * side;
  return {
    jx: sx + ux * half + uy * off, jy: sy + uy * half - ux * off,
    ex: sx + ux * d, ey: sy + uy * d,
    len: Math.max(bone, half),
  };
}

// An arm from its shoulder, pointing at `ang` (the weapon convention: 0 forward, PI/2 up), its hand
// `ext` times the arm's length away - exactly where the one-piece arm put its hand.
export function armPose(sx, sy, ang, ext, bend, h) {
  const bone = h * (RIG.armBone + RIG.armBend * bend);
  return solveLimb(sx, sy, Math.cos(ang), Math.sin(ang), h * RIG.arm * ext, bone, 1);
}

// A leg from its hip, rotated by `rot` (positive swings the foot back) at length `ll` - where the
// one-piece leg put its foot. A PLANTED foot (on the ground, the rig upright) stays where it would
// be without the body's `bob`, so a body that drops into a crouch bends its knees instead of
// pushing its feet through the floor. `tuck` (0-1) draws the foot in toward the hip: knees up.
export function legPose(hx, hy, rot, ll, bob, planted, tuck) {
  const dx0 = -Math.sin(rot), dy0 = -Math.cos(rot);
  const fx = hx + dx0 * ll;
  const fy = hy + dy0 * ll - (planted ? bob : 0);
  let vx = fx - hx, vy = fy - hy;
  const k = 1 - RIG.tuck * Math.max(0, Math.min(1, tuck));
  vx *= k; vy *= k;
  const d = Math.sqrt(vx * vx + vy * vy);
  // A foot exactly at the hip has no direction of its own; it keeps the leg's.
  const ux = d > 1e-9 ? vx / d : dx0, uy = d > 1e-9 ? vy / d : dy0;
  return solveLimb(hx, hy, ux, uy, d, ll * RIG.legBone, -1);
}
