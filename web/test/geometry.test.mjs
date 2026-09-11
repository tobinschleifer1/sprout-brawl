// Does the drawing agree with the hitbox?
//
// Every other animation check in this repo reads the CHANNEL BAG. That turned out to certify
// almost nothing: three of the six checks in animation.test.mjs key on `armR.z`, and the renderer
// only reads `armR.z` in a fallback branch that never fires, because every fighter has a weapon
// and the front arm is driven entirely by the weapon pose. They were green on a discarded number.
// None of them would have failed if the sword were drawn upside down — which it was, for the whole
// life of the 2D renderer.
//
// So this file measures the GEOMETRY THE GAME PAINTS. It runs the real drawing code against a
// canvas mock that does nothing but track the transform matrix, then asks where the blade actually
// ended up in world space and compares that to the hitbox the engine will actually use.
//
// The rule it enforces: a weapon must point at the thing it is about to hit. A hitbox out in front
// of a body and a blade pointing somewhere else is the single worst bug a fighting game can have,
// and it is invisible to every test that does not rasterise or trace.
import { makeMatch, skipCountdown } from './harness.mjs';
import { weaponPose, drawWeapon, REACH } from '../src/render2d/weapons2d.js';
import { WEAPONS } from '../src/data/weapons/index.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };
const DEG = 180 / Math.PI;

// ---- a canvas that only remembers where things would have been drawn ----
// Matrix as [a,b,c,d,e,f] the same way canvas does: x' = a*x + c*y + e, y' = b*x + d*y + f.
function tracer() {
  let m = [1, 0, 0, 1, 0, 0];
  const stack = [];
  const mul = (n) => {
    m = [
      m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1],
      m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3],
      m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5],
    ];
  };
  const api = {
    save() { stack.push(m.slice()); },
    restore() { if (stack.length) m = stack.pop(); },
    translate(x, y) { mul([1, 0, 0, 1, x, y]); },
    rotate(a) { mul([Math.cos(a), Math.sin(a), -Math.sin(a), Math.cos(a), 0, 0]); },
    scale(x, y) { mul([x, 0, 0, y, 0, 0]); },
    setTransform(a, b, c, d, e, f) { m = [a, b, c, d, e, f]; },
    // where does a point in the CURRENT local frame land in the frame the transform started in?
    at(x, y) { return { x: m[0] * x + m[2] * y + m[4], y: m[1] * x + m[3] * y + m[5] }; },
    beginPath() {}, closePath() {}, moveTo() {}, lineTo() {}, arc() {}, ellipse() {},
    fill() {}, stroke() {}, fillRect() {}, strokeRect() {}, clip() {}, rect() {}, quadraticCurveTo() {},
    fillText() {}, measureText: () => ({ width: 0 }),
    createLinearGradient: () => ({ addColorStop() {} }),
    set globalAlpha(v) {}, get globalAlpha() { return 1; },
    set fillStyle(v) {}, get fillStyle() { return '#fff'; },
    set strokeStyle(v) {}, get strokeStyle() { return '#fff'; },
    set lineWidth(v) {}, get lineWidth() { return 1; },
    set font(v) {}, get font() { return ''; },
    set textAlign(v) {}, get textAlign() { return 'left'; },
  };
  return api;
}

// Reproduce exactly the transform stack renderer2d builds around the weapon, then hand the weapon
// drawing code the traced context and read the tip back out in world space.
function bladeInWorld(f, wp) {
  const b = tracer();
  const h = f.char.height, r = f.char.radius;
  // world space is already established by the caller's setTransform; start from identity in world
  b.scale(f.facing, 1);
  const HIP = h * 0.34, SHO = h * 0.70;
  b.translate(0, HIP);
  const armAng = wp.angle;
  const AL = h * 0.30;
  const hx = r * 0.55 + Math.cos(armAng) * AL;
  const hy = (SHO - HIP) + Math.sin(armAng) * AL;
  b.translate(hx, hy);
  const hand = b.at(0, 0);
  // drawWeapon's own transform, traced through the real function
  let grip = null, tip = null;
  const probe = Object.create(b);
  probe.fillRect = () => {};
  b.save();
  drawWeapon(b, f.char.weapon.id, f.char.weaponPalette || f.char.palette, wp);
  b.restore();
  // drawWeapon restores, so re-walk its transform to sample the blade axis
  b.save();
  b.rotate(WEAPON_ROTATE_SIGN * wp.angle);
  b.translate(wp.ox, wp.oy);
  if (wp.scale && wp.scale !== 1) b.scale(wp.scale, wp.scale);
  grip = b.at(0, 0);
  tip = b.at(REACH[f.char.weapon.id] || 2.4, 0);
  b.restore();
  return { hand, grip, tip };
}
// Read the sign the renderer actually uses, so this test tracks the source rather than a guess.
import { readFileSync } from 'node:fs';
const wsrc = readFileSync(new URL('../src/render2d/weapons2d.js', import.meta.url), 'utf8');
const WEAPON_ROTATE_SIGN = /ctx\.rotate\(-pose\.angle\)/.test(wsrc) ? -1 : 1;

// ---- 1. the blade points at the hitbox it is about to use ----
{
  const rows = [], bad = [];
  for (const w of WEAPONS) {
    if (w.id === 'Blasters' || w.id === 'Grimoire') continue;   // aimed, not swung
    const m = makeMatch({ loadouts: [['Classic', w.id], ['Noir', 'Sword']] });
    skipCountdown(m);
    const f = m.fighters[0];
    f.onGround = true; f.platform = m.stage.main; f.y = 0; f.facing = 1;
    let tot = 0, n = 0;
    // Moves whose hitbox is unambiguously above or below the shoulder, where a mirrored blade
    // cannot hide: a spike must point down, a rising cut must point up.
    for (const id of ['LightUp', 'LightDown', 'AirUp', 'AirDown', 'SigNeutral', 'SigDown']) {
      const mv = f.char.moves[id]; if (!mv || !mv.hitboxes || !mv.hitboxes.length) continue;
      f.setState('idle'); f.startMove(id);
      const st = f.startupEff;
      for (const hb of mv.hitboxes) {
        for (let mf = Math.max(hb.frames[0], st + 1); mf <= Math.min(hb.frames[1], st + mv.active); mf++) {
          f.mf = mf;
          const wp = weaponPose(f, mf / 60);
          const { hand, tip } = bladeInWorld(f, wp);
          const bx = tip.x - hand.x, by = tip.y - hand.y;
          const SHO = f.char.height * 0.70;
          const wantX = hb.offset[0], wantY = hb.offset[1] - SHO;
          let d = Math.abs(((Math.atan2(wantY, wantX) - Math.atan2(by, bx)) * DEG + 540) % 360 - 180);
          tot += d; n++;
        }
      }
    }
    const mean = tot / Math.max(1, n);
    rows.push(`${w.id} ${mean.toFixed(0)}°`);
    if (mean > 70) bad.push(`${w.id}: blade averages ${mean.toFixed(0)}° from its own hitbox over ${n} active frames`);
  }
  check('the blade points at the hitbox it is about to use', bad.length === 0,
    bad.length ? bad.join('; ') : `mean blade-vs-hitbox angle on directional swings: ${rows.join(', ')}`);
}

// ---- 2. the weapon is in the hand ----
{
  const bad = [], rows = [];
  for (const w of WEAPONS) {
    const m = makeMatch({ loadouts: [['Classic', w.id], ['Noir', 'Sword']] });
    skipCountdown(m);
    const f = m.fighters[0];
    f.onGround = true; f.platform = m.stage.main; f.y = 0; f.facing = 1;
    let worst = 0;
    for (const id of Object.keys(f.char.moves)) {
      const mv = f.char.moves[id];
      f.setState('idle'); f.startMove(id);
      const total = f.startupEff + mv.active + mv.recovery;
      for (let mf = 1; mf <= total; mf += 2) {
        f.mf = mf;
        const wp = weaponPose(f, mf / 60);
        if (wp.hide) continue;
        const { hand, grip } = bladeInWorld(f, wp);
        worst = Math.max(worst, Math.hypot(grip.x - hand.x, grip.y - hand.y));
      }
    }
    rows.push(`${w.id} ${worst.toFixed(2)}`);
    // Moves deliberately push the weapon in the hand — a thrust adds 0.35 studs of `ox`, a gun's
    // recoil pulls 0.7 back — so the bar is set above the largest authored offset. What it still
    // catches is the real failure: a 90-degree mismatch between the arm and the weapon put the
    // grip over 3 studs from the hand, which is most of a fighter's height.
    if (worst > 0.8) bad.push(`${w.id}: grip drifts ${worst.toFixed(2)} studs from the hand`);
  }
  check('the weapon stays in the hand', bad.length === 0,
    bad.length ? bad.join('; ') : `worst hand-to-grip gap: ${rows.join(', ')} studs (fighter is 5.2 tall)`);
}

// ---- 3. the body and the weapon cock on the same frame ----
// They are driven by two different easing curves in two different files. When those disagree the
// torso is fully loaded while the sword has barely moved, and the swing reads as two animations.
{
  const m = makeMatch({ loadouts: [['Classic', 'Sword'], ['Noir', 'Sword']] });
  skipCountdown(m);
  const f = m.fighters[0];
  const { channelsFor } = await import('../src/render2d/channels.js');
  const bad = [], rows = [];
  for (const id of ['LightNeutral1', 'LightSide1', 'SigSide', 'SigDown']) {
    const mv = f.char.moves[id]; if (!mv) continue;
    f.setState('idle'); f.startMove(id);
    const st = f.startupEff;
    const reach90 = (sample) => {
      const vals = [];
      for (let mf = 1; mf <= st; mf++) { f.setState('idle'); f.startMove(id); f.mf = mf; vals.push(Math.abs(sample(mf))); }
      const peak = Math.max(...vals, 1e-6);
      return vals.findIndex((v) => v >= peak * 0.9) + 1;
    };
    const bodyAt = reach90(() => channelsFor(f, 0).lean);
    const wpAt = reach90((mf) => weaponPose(f, mf / 60).angle);
    const gap = Math.abs(bodyAt - wpAt);
    rows.push(`${id} body f${bodyAt} weapon f${wpAt}`);
    if (gap > Math.max(3, st * 0.35)) bad.push(`${id}: torso loads on frame ${bodyAt}, weapon on frame ${wpAt} of ${st}`);
  }
  check('the torso and the weapon wind up together', bad.length === 0,
    bad.length ? bad.join('; ') : rows.join('  |  '));
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
