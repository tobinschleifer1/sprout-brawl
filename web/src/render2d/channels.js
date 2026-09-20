// Animation channels: the pose of a fighter for one frame, as plain numbers.
//
// Nothing in here touches a renderer — it reads fighter state and returns a channel bag that a
// painter interprets however it likes. Everything is procedural; there are no sprite sheets, so
// what carries over from hand-drawn fighting-game animation is not artwork but TIMING.
//
// The five principles this file is built on, and what each one fixes:
//
//   ANTICIPATION       Every attack pulls back before it goes forward, and the pull-back
//                      overshoots slightly before it snaps. This is not decoration: it is the
//                      frame the defending player reads. An attack without one is unreactable
//                      regardless of what the frame data says.
//   SLOW IN / SLOW OUT Nothing moves linearly. The old version lerped every pose on a raw `k`,
//                      which is why the moveset read as a slideshow of positions rather than as
//                      motion. Wind-ups ease OUT (fast away from rest, settling into the cocked
//                      pose); strikes ease IN hard (the fastest frames are the contact frames).
//   FOLLOW THROUGH     Recovery is a damped settle that overshoots rest and comes back, not a
//                      straight line home. This is where weight lives — a heavy move settles
//                      slowly and wobbles, a jab snaps back and is done.
//   OVERLAPPING ACTION Head, off-arm and legs LAG the torso by a few frames. Driving every limb
//                      from the same instant is what makes a puppet look like a puppet.
//   MOVING HOLD        The active frames are never frozen. A held pose still drifts, because a
//                      completely static frame reads as a dropped frame, not as a held one.
//
// Channels:
//   lean      body tilt, radians, positive = leaning into the attack
//   bob/yOff  vertical offsets in studs
//   sx/sy     squash and stretch
//   armL/armR shoulder rotation, z = swing in the side-on plane, x = swing across it
//   legL/legR hip rotation
//   spinZ     rotation in the screen plane; folded into rigRotZ below
//   spinY     rotation about the fighter's own vertical axis, rendered as an sx squeeze
//   smear     0-1; how much motion streak the painter should add this frame
//   tint      an emissive flash colour, or null

const PI = Math.PI;
const F = PI / 2;                       // arm straight forward
const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);

// ---------------------------------------------------------------------------- easing ----
// Fast away from rest, settling in. Wind-ups use this.
export const easeOut = (k) => 1 - (1 - k) * (1 - k);
// Slow away from rest, fastest at the end. Strikes use this, so the quickest frames of the whole
// move are the ones where the hitbox is live.
export const easeIn = (k) => k * k * k;
const easeInOut = (k) => (k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2);
// Overshoot past the target and come back. Anticipation uses this: the cock goes a little too far
// and rebounds, which is what makes a wind-up read as loaded rather than as a position.
const back = (k, amt = 1.7) => { const c = k - 1; return 1 + (amt + 1) * c * c * c + amt * c * c; };
// A damped spring, for settles. `d` is how fast it dies; higher settles quicker.
const settle = (k, freq = 3.2, d = 5) => (k >= 1 ? 1 : 1 - Math.cos(k * freq * PI) * Math.exp(-d * k));

// Where a move is, with all the easing already applied. Every attack reads from this rather than
// working out its own phase, so timing is consistent across the whole moveset.
export function swing(f, m) {
  const st = f.startupEff, act = m.active, rec = m.recovery, mf = f.mf;
  if (mf <= st) {
    const k = st ? mf / st : 1;
    // The wind-up spends its last third loaded and trembling rather than still arriving.
    return { phase: 'wind', k, e: back(easeOut(k), 1.1), hold: k > 0.68, smear: 0 };
  }
  if (mf <= st + act) {
    const k = act ? (mf - st) / act : 1;
    // The strike itself: the first two frames cover most of the distance, then a moving hold.
    const snap = clamp(k * 3.2, 0, 1);
    // `1 - k*2.2` reached zero a fifth of the way in, so a two-frame active window — every jab in
    // the game — got exactly 0 on both of its frames and never smeared at all.
    return { phase: 'strike', k, e: easeIn(snap), hold: false, smear: 1 - clamp(k, 0, 1) };
  }
  const k = rec ? (mf - st - act) / rec : 1;
  return { phase: 'settle', k, e: 1 - settle(k, m.heavy ? 2.6 : 3.4, m.heavy ? 3.4 : 6), hold: false, smear: 0 };
}

// Overlapping action, done properly: re-evaluate the swing a few FRAMES earlier and use that
// value. The first version subtracted a constant from the eased value, which is an amplitude
// offset rather than a delay — because the master curve reaches 1.0 within a frame or two and then
// holds, the trailing limbs spent the whole move at a fixed offset and never actually lagged.
function lagged(f, m, frames) {
  if (f.mf <= frames) return f.mf <= f.startupEff ? 0 : 1;
  const shadow = { mf: f.mf - frames, startupEff: f.startupEff, move: m };
  const s2 = swing(shadow, m);
  return s2.phase === 'wind' ? -s2.e : s2.e;
}

// Which ordinary categories a thrusting weapon replaces. Rising attacks stay rotational: you
// cannot thrust upward off a line that runs forward, and the pike's up-angled moves genuinely are
// swings of the point.
const THRUSTABLE = { jab: 'thrust', side: 'thrust', fair: 'thrust', sigside: 'thrust', down: 'thrustlow', sigdown: 'thrustlow', dair: 'thrustlow' };

// ------------------------------------------------------------------- the ultimate bodies -----
// Each of these is written against the SAME phase boundaries weapons2d.js's ultimatePose uses, so
// the fighter and the prop are performing one move rather than two. `weapons2d` owns the weapon;
// this owns the person holding it.
function ultChannels(ch, f, m, t) {
  const wid = f.char.weapon ? f.char.weapon.id : null;
  const st = f.startupEff, act = m.active, rec = m.recovery, mf = f.mf;
  const wind = mf <= st, live = mf > st && mf <= st + act;
  const k = wind ? mf / Math.max(1, st) : live ? (mf - st) / Math.max(1, act) : 1;
  const ak = mf - st;                                    // frame within the active window
  const out = Math.min(1, (mf - st - act) / Math.max(1, rec));   // 0 -> 1 across recovery
  // Everything below builds a pose for the frame; the recovery blend at the bottom returns it to
  // neutral through the same damped settle the ordinary moves use, so no ultimate snaps home.
  const strain = (a) => (f.mf % 2 ? a : -a);

  if (wid === 'Sword') {
    // COLOSSUS. Hoist a sword twice its own length overhead, hold it, and fall with it.
    const CHOP = 5, riseEnd = Math.max(1, st - CHOP);
    if (wind && mf <= riseEnd) {
      const r = easeOut(mf / riseEnd);
      ch.armL.z = 0.6 + 2.4 * r; ch.armR.z = -0.6 - 2.3 * r;
      ch.sy = 1 + 0.26 * r; ch.sx = 1 - 0.14 * r;
      ch.bob = 0.55 * r; ch.head = -0.35 * r;
      ch.legL = -0.35 * r; ch.legR = -0.28 * r;
      ch.shakeX = strain(0.10 * r);                       // the weight is already winning
    } else if (wind) {
      const c = easeIn((mf - riseEnd) / CHOP);            // the drop: everything comes down at once
      ch.armL.z = 3.0 - 2.6 * c; ch.armR.z = -2.9 + 2.4 * c;
      ch.sy = 1.26 - 0.5 * c; ch.sx = 0.86 + 0.38 * c;
      ch.bob = 0.55 - 0.85 * c; ch.lean = 0.34 * c;
      ch.legL = -0.35 + 0.9 * c; ch.legR = -0.28 - 0.5 * c;
      ch.head = -0.35 + 0.7 * c;
      ch.smear = c;
    } else {
      // planted: buried to the crossguard, braced against a floor that is coming apart
      const q = live ? 1 - Math.min(1, ak / 8) : 0;
      ch.sy = 0.78 + 0.2 * (1 - q); ch.sx = 1.22 - 0.18 * (1 - q);
      ch.lean = 0.32 - 0.14 * (1 - q); ch.bob = -0.3 + 0.2 * (1 - q);
      ch.armL.z = 0.4; ch.armR.z = -0.5; ch.legL = 0.55; ch.legR = -0.78;
      ch.head = 0.35;
      if (live) ch.shakeX = strain(0.16 * (1 - ak / Math.max(1, act)));
    }
  } else if (wid === 'Scythe') {
    // SOUL TETHER. The pull is isometric: nothing moves fast, everything strains.
    const hold = (m.vortex && m.vortex.holdFrames) || 22;
    if (wind) {
      const r = easeOut(k);
      ch.armR.z = -1.5 * r; ch.armL.z = 0.4 + 1.5 * r;
      ch.lean = -0.55 * r; ch.sx = 1 - 0.12 * r; ch.sy = 1 + 0.1 * r;
      ch.legL = 0.4 * r; ch.legR = -0.35 * r; ch.head = -0.25 * r;
    } else if (live && ak <= hold) {
      const h = ak / hold, reach = Math.min(1, ak / 5);
      // reaching hand out, body hauling BACKWARDS against it - the ball is being dragged in
      ch.armR.z = -1.5 + (F + 0.35 + 1.5) * easeOut(reach);
      ch.armL.z = 1.9 - 0.5 * reach;
      ch.lean = -0.55 + 0.75 * easeOut(reach) - 0.35 * h;
      ch.legR = 0.6 * reach - 0.5 * h; ch.legL = -0.45 * reach + 0.4 * h;
      ch.sx = 1 + 0.08 * Math.sin(h * PI); ch.sy = 1 - 0.06 * Math.sin(h * PI);
      ch.head = -0.2 * h;
      ch.shakeX = strain(0.06 + 0.14 * h);                // grip failing as the ball tightens
      ch.bob = -0.18 * h;
    } else {
      const since = live ? ak - hold : (act - hold) + (mf - st - act);
      const c = easeIn(Math.min(1, since / 8));
      ch.armR.z = (F + 0.35) - 2.5 * c; ch.armL.z = 1.4 - 1.0 * c;
      ch.lean = 0.16 + 0.26 * c; ch.sy = 1 - 0.3 * c; ch.sx = 1 + 0.24 * c;
      ch.legR = 0.9 * c; ch.legL = -0.6 * c; ch.bob = -0.35 * c;
      ch.smear = Math.max(0, 1 - since / 6);
    }
  } else if (wid === 'Blasters') {
    // DEADEYE. A rifle stance: square, still, and every shot is felt through the shoulder.
    const reload = (m.sniper && m.sniper.reload) || 16;
    if (wind) {
      const r = easeOut(k);
      ch.armR.z = -0.6 + (F + 0.6) * r; ch.armL.z = -0.3 + 0.9 * r;   // support hand comes up
      ch.lean = 0.18 * r; ch.sx = 1 - 0.08 * r; ch.sy = 1 + 0.04 * r;
      ch.legL = -0.3 * r; ch.legR = 0.45 * r; ch.head = -0.15 * r;
    } else if (live) {
      const since = f.ultCooldown > 0 ? reload - f.ultCooldown : 99;
      const kick = since < 7 ? (1 - since / 7) * (1 - since / 7) : 0;
      ch.armR.z = F; ch.armL.z = 0.6;
      ch.lean = 0.18 - 0.42 * kick;                        // driven back into the shoulder
      ch.sx = 1 - 0.08 + 0.1 * kick; ch.sy = 1 + 0.04 - 0.06 * kick;
      ch.legL = -0.3 - 0.25 * kick; ch.legR = 0.45 + 0.3 * kick;
      ch.head = -0.15 - 0.2 * kick;
      ch.shakeX = strain(0.18 * kick);
      ch.smear = kick * 0.6;
      ch.bob = Math.sin(t * 2.2) * 0.06;                   // breathing on the scope between shots
    } else {
      ch.armR.z = F * (1 - out); ch.armL.z = 0.6 * (1 - out); ch.legR = 0.45 * (1 - out);
    }
  } else if (wid === 'Axe') {
    // REAVE. The fighter stops fighting the weight and goes with it: three revolutions, the body
    // turning with the head and leaning out against the pull the whole way.
    if (wind) {
      const r = easeOut(k);
      ch.armR.z = -1.7 * r; ch.armL.z = 0.4 + 1.2 * r;
      ch.lean = -0.5 * r;                                  // wound all the way back and low
      ch.sy = 1 - 0.2 * r; ch.sx = 1 + 0.16 * r;
      ch.legL = 0.55 * r; ch.legR = -0.5 * r; ch.bob = -0.4 * r; ch.head = -0.3 * r;
      ch.shakeX = strain(0.12 * r);
    } else if (live) {
      const p = ak / Math.max(1, act);
      // the body turns WITH the axe - same accelerating curve weapons2d spins the head on
      // spinY, NOT spinZ: spinZ is rotation in the SCREEN plane, which drew the fighter
      // cartwheeling through three somersaults. A fighter turning with a swing rotates about their
      // own vertical axis, which this renderer draws as the body narrowing and widening.
      ch.spinY = Math.pow(p, 1.15) * PI * 6.0;
      ch.lean = 0.20 + 0.12 * p;                           // leaning out against the swing
      ch.armR.z = -0.3; ch.armL.z = -0.25;                 // both arms locked to the haft
      ch.sx = 1 + 0.14 * p; ch.sy = 1 - 0.1 * p;
      ch.legL = 0.3; ch.legR = -0.3;
      ch.smear = 0.5 + 0.5 * p;
      ch.bob = -0.2 - 0.2 * p;
    } else {
      // the release: dizzy, over-rotated, hauling itself back upright
      ch.lean = 0.34 * (1 - out); ch.sx = 1 + 0.14 * (1 - out);
      ch.armL.z = 1.1 * (1 - out); ch.armR.z = -0.9 * (1 - out);
      ch.head = 0.3 * (1 - out) * Math.cos(out * PI * 2);
      ch.bob = -0.4 * (1 - out);
    }
  } else if (wid === 'Pike') {
    // LANCE CHARGE. Couched: body low over the front knee, lance along the line, and every thrust
    // is the whole fighter travelling forward rather than an arm moving.
    const FULLEXT = 1.75;
    if (wind) {
      const r = easeOut(k);
      ch.armR.z = -0.6 + (F + 0.6) * r; ch.armR.ext = 1 - 0.28 * r;   // drawn all the way in
      ch.armL.z = 0.5 + 0.8 * r;
      ch.lean = 0.10 + 0.18 * r; ch.sy = 1 - 0.16 * r; ch.sx = 1 + 0.1 * r;
      ch.legR = -0.4 * r; ch.legL = 0.5 * r; ch.bob = -0.35 * r; ch.head = -0.1 * r;
    } else if (live) {
      const per = act / 5, phase = (ak % per) / per;
      const punch = phase < 0.35 ? easeIn(phase / 0.35) : 1 - (phase - 0.35) / 0.65;
      const step = Math.floor(ak / per) / 5;               // how far into the reach ramp
      ch.armR.z = F; ch.armR.ext = 1 - 0.28 + (FULLEXT - 0.72) * punch * (0.7 + 0.3 * step);
      ch.armL.z = 1.3 - 0.5 * punch;
      ch.lean = 0.24 + 0.16 * punch;
      ch.legR = 1.0 * punch - 0.4 * (1 - punch); ch.legL = -0.75 * punch + 0.5 * (1 - punch);
      ch.sx = 1 + 0.12 * punch; ch.sy = 1 - 0.16 - 0.05 * punch;
      ch.bob = -0.35 - 0.15 * punch;
      ch.head = -0.1 - 0.12 * punch;
      ch.smear = punch > 0.6 ? punch : 0;
    } else {
      ch.lean = 0.28 * (1 - out); ch.armR.z = F * (1 - out); ch.armR.ext = 1 + 0.5 * (1 - out);
      ch.bob = -0.35 * (1 - out); ch.sy = 1 - 0.16 * (1 - out);
    }
  } else if (wid === 'Gauntlets') {
    // HUNDRED HANDS. No weapon, so the body IS the move: wound back, then a torso that never
    // stops turning, then one straight right that puts everything behind it.
    if (wind) {
      const r = easeOut(k);
      ch.armR.z = -1.5 * r; ch.armL.z = 0.4 + 1.0 * r;
      ch.lean = -0.4 * r; ch.legL = 0.4 * r; ch.legR = -0.35 * r;
      ch.sx = 1 - 0.08 * r; ch.bob = -0.2 * r;
    } else if (live) {
      const p2 = ak / Math.max(1, act);
      const beat = Math.sin(ak * 1.9);
      ch.armR.z = F + beat * 0.5; ch.armR.ext = 1 + 0.28 * Math.abs(beat);
      ch.armL.z = -0.4 - beat * 0.5;
      ch.lean = 0.2 + beat * 0.12;
      ch.spinY = beat * 0.5;
      ch.sx = 1 + 0.06 * Math.abs(beat);
      ch.smear = 0.7;
      ch.bob = -0.14;
      if (ak > act - 10) { const f2 = (ak - (act - 10)) / 10; ch.armR.z = F; ch.armR.ext = 1 + 0.5 * f2; ch.lean = 0.42; ch.spinY = 0; ch.smear = 1; }
    } else {
      ch.lean = 0.42 * (1 - out); ch.armR.z = F * (1 - out); ch.armR.ext = 1 + 0.4 * (1 - out);
    }
  } else if (wid === 'Hammer') {
    // UPHEAVAL. The lift is the same enormous effort it always was; what changed is the after -
    // the fighter stays down over a planted hammer, shuddering as each column goes up, instead of
    // recovering from a slam that is already over.
    const CHOP = 8, riseEnd = Math.max(1, st - CHOP);
    if (wind && mf <= riseEnd) {
      const r = easeOut(mf / riseEnd);
      ch.armL.z = 0.6 + 2.4 * r; ch.armR.z = -0.6 - 2.3 * r;
      ch.sy = 1 + 0.3 * r; ch.sx = 1 - 0.16 * r;
      ch.bob = 0.7 * r; ch.head = -0.4 * r;
      ch.legL = -0.4 * r; ch.legR = -0.32 * r;
      ch.shakeX = strain(0.16 * r);
    } else if (wind) {
      const c = easeIn((mf - riseEnd) / CHOP);
      ch.armL.z = 3.0 - 2.7 * c; ch.armR.z = -2.9 + 2.5 * c;
      ch.sy = 1.3 - 0.58 * c; ch.sx = 0.84 + 0.44 * c;
      ch.bob = 0.7 - 1.05 * c; ch.lean = 0.34 * c;
      ch.legL = -0.4 + 1.0 * c; ch.legR = -0.32 - 0.55 * c;
      ch.head = -0.4 + 0.8 * c;
      ch.smear = c;
    } else if (live) {
      const U = m.upheaval;
      const beat = U ? 1 - (ak % U.every) / U.every : 0;
      ch.sy = 0.78 - 0.04 * beat; ch.sx = 1.24 + 0.04 * beat;
      ch.lean = 0.3; ch.bob = -0.34;
      ch.armL.z = 0.4; ch.armR.z = -0.5; ch.legL = 0.6; ch.legR = -0.8; ch.head = 0.36;
      ch.shakeX = strain(0.06 + 0.2 * beat);      // the floor kicking, once per column
    } else {
      ch.lean = 0.3 * (1 - out); ch.sy = 1 - 0.22 * (1 - out); ch.sx = 1 + 0.24 * (1 - out);
      ch.bob = -0.34 * (1 - out); ch.legL = 0.6 * (1 - out); ch.legR = -0.8 * (1 - out);
    }
  } else if (wid === 'Longbow') {
    // HEARTSEEKER. The draw is the move. The string hand comes back past the ear, the whole body
    // settles into the shot, and the release is two frames of everything letting go at once.
    if (wind) {
      const r = easeOut(k);
      ch.armR.z = -0.5 + (F + 0.5) * r; ch.armR.ext = 1 + 0.18 * r;   // bow arm out and locked
      ch.armL.z = -0.2 - 1.0 * r;                                      // string hand back
      ch.lean = -0.12 * r; ch.head = -0.16 * r;
      ch.sx = 1 - 0.06 * r; ch.sy = 1 + 0.04 * r;
      ch.legL = -0.3 * r; ch.legR = 0.35 * r;
      ch.bob = -0.1 * r;
      ch.shakeX = strain(0.04 + 0.12 * r * r);    // the draw weight, rising the longer it is held
    } else if (live) {
      const kk = Math.min(1, ak / 5);
      ch.armR.z = F + 0.5; ch.armR.ext = 1 + 0.18 + 0.12 * (1 - kk);
      ch.armL.z = -1.2 + 1.6 * kk;                                     // the string hand snaps open
      ch.lean = -0.12 + 0.2 * kk;
      ch.sx = 0.94 + 0.16 * kk; ch.sy = 1.04 - 0.1 * kk;
      ch.legL = -0.3; ch.legR = 0.35;
      ch.smear = 1 - kk;
      ch.head = -0.16 + 0.1 * kk;
    } else {
      ch.armR.z = (F + 0.5) * (1 - out); ch.armL.z = 0.4 * (1 - out);
      ch.lean = 0.08 * (1 - out); ch.legR = 0.35 * (1 - out);
    }
  } else if (wid === 'Flail') {
    // ANCHOR. A wind-up, a throw, and then the fighter is simply WALKING with a rope in their
    // hands - braced, leaning against the pull, free to move. The spin this used to play belonged
    // to a different ultimate and made a move about where you stand look like one about not moving.
    if (wind) {
      const r = easeOut(k);
      ch.armR.z = -1.8 * r; ch.armL.z = 0.4 + 1.3 * r;
      ch.lean = -0.5 * r; ch.sy = 1 - 0.18 * r; ch.sx = 1 + 0.14 * r;
      ch.legL = 0.5 * r; ch.legR = -0.45 * r; ch.bob = -0.35 * r; ch.head = -0.28 * r;
      ch.shakeX = strain(0.12 * r);
    } else if (live) {
      const thrown = Math.min(1, ak / 6);
      // the throw
      ch.armR.z = -1.8 + (F + 2.1) * easeIn(thrown);
      ch.armL.z = 1.7 - 1.3 * thrown;
      ch.lean = -0.5 + 0.78 * thrown;
      ch.smear = 1 - thrown;
      // and then the haul: both hands on the chain, weight back, and it breathes
      if (thrown >= 1) {
        ch.armR.z = F - 0.25 + Math.sin(t * 2.4) * 0.06;
        ch.armL.z = F - 0.75 + Math.sin(t * 2.4 + 0.6) * 0.06;
        ch.lean = 0.28;
        ch.legR = 0.55; ch.legL = -0.4;
        ch.sx = 1.06; ch.sy = 0.97;
        ch.bob = -0.18 + Math.sin(t * 2.2) * 0.05;
        ch.head = 0.12;
        ch.shakeX = strain(0.05);
      }
    } else {
      ch.lean = 0.28 * (1 - out); ch.armR.z = (F - 0.25) * (1 - out); ch.armL.z = (F - 0.75) * (1 - out);
      ch.legR = 0.55 * (1 - out); ch.bob = -0.18 * (1 - out);
    }
  } else if (wid === 'Shield') {
    // LAST STAND. The only ultimate in the game whose performance is holding still. Everything
    // that lands on it is absorbed into a body that compresses and does not move, and the release
    // is the first thing that does.
    if (wind) {
      const r = easeOut(k);
      ch.armL.z = 0.4 + 1.1 * r; ch.armR.z = -0.4 - 0.6 * r;
      ch.lean = 0.26 * r; ch.sy = 1 - 0.14 * r; ch.sx = 1 + 0.12 * r;
      ch.legR = 0.7 * r; ch.legL = -0.5 * r; ch.bob = -0.24 * r; ch.head = 0.2 * r;
    } else if (live) {
      const rel = ak > act - 12 ? (ak - (act - 12)) / 12 : 0;
      ch.armL.z = 1.5; ch.armR.z = -1.0;
      ch.lean = 0.26 - 0.1 * rel;
      ch.sy = 0.86 - 0.06 * (1 - rel) + 0.34 * rel;
      ch.sx = 1.12 + 0.06 * (1 - rel) - 0.2 * rel;
      ch.legR = 0.7; ch.legL = -0.5; ch.head = 0.2;
      ch.bob = -0.24 + 0.3 * rel;
      ch.shakeX = strain(0.06 + 0.1 * Math.sin(ak * 0.5));
      ch.smear = rel;
    } else {
      ch.lean = 0.2 * (1 - out); ch.armL.z = 1.5 * (1 - out); ch.armR.z = -1.0 * (1 - out);
      ch.sy = 1 + 0.18 * (1 - out); ch.bob = 0.06 * (1 - out);
    }
  } else if (wid === 'Daggers') {
    // THOUSAND CUTS. A body that is never where it was a frame ago. The flicker is deliberate: it
    // alternates between two poses rather than easing between them, because easing would read as
    // one fighter moving quickly instead of one who keeps arriving somewhere else.
    if (wind) {
      const r = easeOut(k);
      ch.armR.z = -1.4 * r; ch.armL.z = 0.4 + 1.2 * r;
      ch.lean = -0.36 * r; ch.sx = 1 - 0.1 * r; ch.bob = -0.24 * r;
      ch.legL = 0.4 * r; ch.legR = -0.3 * r; ch.head = -0.2 * r;
    } else if (live) {
      const flip = Math.floor(ak / 3) % 2 ? 1 : -1;
      ch.armR.z = F * flip; ch.armL.z = -F * flip * 0.7;
      ch.armR.ext = 1 + 0.35;
      ch.lean = 0.3 * flip;
      ch.spinY = flip > 0 ? 0 : PI * 0.85;              // facing away on the off beat
      ch.opacity = 0.8;
      ch.smear = 1;
      ch.bob = -0.16;
      if (ak > act - 10) { const f2 = (ak - (act - 10)) / 10; ch.spinY = 0; ch.opacity = 1; ch.lean = 0.44; ch.armR.z = F; ch.armR.ext = 1 + 0.5 * f2; }
    } else {
      ch.lean = 0.44 * (1 - out); ch.armR.z = F * (1 - out); ch.armR.ext = 1 + 0.4 * (1 - out);
    }
  } else {
    // GRIMOIRE - ASTRAL RAIN. The book goes up and the fighter opens out under it, arched back,
    // pulsing with every wave that leaves the pages.
    if (wind) {
      const r = easeOut(k);
      ch.armL.z = 0.4 + 2.5 * r; ch.armR.z = -0.4 - 2.4 * r;
      ch.lean = -0.45 * r; ch.sy = 1 + 0.2 * r; ch.sx = 1 - 0.12 * r;
      ch.bob = 0.45 * r; ch.head = -0.5 * r;
      ch.legL = -0.3 * r; ch.legR = -0.25 * r;
    } else if (live) {
      ch.armL.z = 2.9; ch.armR.z = -2.8; ch.lean = -0.45; ch.head = -0.5;
      ch.legL = -0.3; ch.legR = -0.25;
      const S = m.starfall;
      // one pulse per wave: the fighter is the pump, not a statue
      let pulse = 0;
      if (S) { const since = (ak - 1) % S.every; if (since < 10 && ak - 1 < S.perTarget * S.every) pulse = 1 - since / 10; }
      ch.sy = 1.2 + 0.18 * pulse; ch.sx = 0.88 - 0.1 * pulse;
      ch.bob = 0.45 + 0.35 * pulse + Math.sin(t * 1.8) * 0.08;
      ch.opacity = 1;
      ch.shakeX = strain(0.1 * pulse);
    } else {
      ch.armL.z = 2.9 * (1 - out); ch.armR.z = -2.8 * (1 - out);
      ch.lean = -0.45 * (1 - out); ch.sy = 1 + 0.2 * (1 - out); ch.bob = 0.45 * (1 - out);
      ch.head = -0.5 * (1 - out);
    }
  }

  // Every ultimate settles through the same damped spring the ordinary moves use, so the last
  // frames read as a fighter recovering their balance rather than as a pose being switched off.
  if (!wind && !live) {
    const d = 1 - settle(out, 2.4, 3.2);
    for (const key of ['lean', 'bob', 'head', 'legL', 'legR', 'shakeX', 'smear']) ch[key] *= d;
    ch.sx = 1 + (ch.sx - 1) * d; ch.sy = 1 + (ch.sy - 1) * d;
    ch.armL.z *= d; ch.armR.z *= d;
    ch.armR.ext = 1 + (ch.armR.ext - 1) * d;
  }
}

function attackChannels(ch, f, t) {
  const m = f.move; if (!m) return;
  const s = swing(f, m);
  const id = m.id || '';
  // An ultimate is not a big signature and it cannot borrow a signature's timing: `swing` finishes
  // its strike curve within a handful of frames, which is right for a 4-frame active window and
  // meaningless across the 54 that Reave is live for. Every ultimate in the game used to fall
  // through this map's default and play the JAB body pose - six bespoke weapon performances above
  // a fighter doing a jab - so they get their own function, phased the same way the weapon is.
  if (id === 'Ultimate') return ultChannels(ch, f, m, t);
  const cat = id.startsWith('LightNeutral') ? 'jab'
    : id.startsWith('LightSide') || id === 'ItemSwing' ? 'side'
    : id === 'LightDown' ? 'down' : id === 'LightUp' ? 'up'
    : id === 'AirNeutral' ? 'nair' : id === 'AirForward' ? 'fair'
    : id === 'AirDown' ? 'dair' : id === 'AirUp' ? 'uair'
    : id === 'SigSide' ? 'sigside' : id === 'SigDown' ? 'sigdown' : id === 'SigNeutral' ? 'signeut'
    : id === 'CounterBurst' ? 'burst' : id === 'ItemSpray' ? 'spray' : 'jab';
  ch.smear = s.smear * (m.heavy ? 1 : 0.7);

  // A weapon can declare that it THRUSTS. A thrust is not a small swing: the reach comes from the
  // body driving along a line - shoulder, hip, back leg - and from the arm extending, not from the
  // prop rotating. The pike was animated as a sword with a tiny arc, which is why a spear read as
  // a short sword, and its reach was faked by sliding the prop off the end of the hand.
  const cat2 = (f.char.weapon && f.char.weapon.thrusts && THRUSTABLE[cat]) ? THRUSTABLE[cat] : cat;

  if (m.kind === 'counter') {
    ch.armL.z = 0.9; ch.armR.z = -0.9; ch.sy = 0.92; ch.sx = 1.08; ch.tint = '#3E4F2E';
    ch.bob = Math.sin(t * 22) * 0.04;     // a counter is a held stance: keep it breathing
    return;
  }

  // A small tremble through a loaded wind-up, and a hard contact flash on the strike's first
  // frames. Both are shared by every move so the whole roster reads the same way.
  // Driven off the move's own frame counter, not wall-clock: at t*90 it aliased against 60Hz into
  // a shimmer, and 0.05 studs is a quarter of a pixel anyway.
  if (s.hold) { ch.shakeX = (f.mf % 2 ? 1 : -1) * 0.22; }
  if (s.phase === 'strike' && s.k < 0.25 && m.heavy) ch.tint = '#FFFFFF';

  // `w` walks from rest (0) through the cocked pose and out to full extension (1), so each move
  // below only has to name three poses and the easing does the rest.
  // In the settle phase `e` already runs 1 -> 0 (full extension back to rest, overshooting past
  // it on the way), so it IS w. Writing `1 - s.e` here ran every recovery backwards: the fighter
  // started recovery at rest and travelled OUT to full extension, which is why nothing ever
  // crossed rest and the follow-through test failed on every move.
  const w = s.phase === 'wind' ? -s.e : s.e;
  // the same walk, two and three frames behind, for the limbs that trail the torso
  const wLag2 = lagged(f, m, 2), wLag3 = lagged(f, m, 3), wLag4 = lagged(f, m, 4);

  switch (cat2) {
    case 'jab':
      ch.armR.z = w < 0 ? -0.55 * -w : F * w;
      ch.armL.z = -0.25 - 0.5 * Math.abs(wLag2);
      ch.lean = w < 0 ? -0.12 * -w : 0.2 * w;
      ch.legR = 0.18 * w; ch.legL = -0.1 * w;
      ch.sx = 1 + 0.06 * Math.max(0, w);
      break;
    case 'side':
      ch.armR.z = w < 0 ? -1.1 * -w : (F + 0.25) * w;
      ch.armL.z = 0.25 - 0.9 * Math.max(0, wLag3);
      ch.lean = w < 0 ? -0.32 * -w : 0.42 * w;
      ch.legR = 0.5 * Math.max(0, w); ch.legL = -0.35 * Math.max(0, w);
      ch.sx = 1 + 0.14 * Math.max(0, w); ch.sy = 1 - 0.06 * Math.max(0, w);
      ch.head = -0.18 * Math.max(0, wLag3);
      break;
    case 'down':
      ch.sy = 1 - 0.28 * Math.abs(w); ch.sx = 1 + 0.22 * Math.abs(w);
      ch.lean = 0.34 * Math.abs(w);
      ch.legR = w < 0 ? -0.3 * -w : 1.4 * w; ch.legL = -0.25 * Math.abs(w);
      ch.armR.z = 0.55 * w; ch.armL.z = 0.6;
      ch.head = 0.22 * Math.max(0, w);
      break;
    case 'up':
      ch.armR.z = w < 0 ? -0.7 * -w : (F + 0.9) * w;
      ch.armL.z = -0.3 - 0.7 * Math.max(0, wLag3);
      ch.lean = -0.2 * Math.max(0, w);
      ch.sy = 1 + 0.12 * Math.max(0, w); ch.sx = 1 - 0.07 * Math.max(0, w);
      ch.legL = -0.3 * Math.max(0, w); ch.legR = 0.2 * Math.max(0, w);
      ch.bob = 0.18 * Math.max(0, w);
      break;
    case 'nair':
      // A spin, and now it actually renders: spinY squeezes the body horizontally as it turns.
      ch.spinY = easeInOut(clamp(f.mf / Math.max(1, f.startupEff + m.active + m.recovery), 0, 1)) * PI * 4;
      ch.armL.z = 1.5; ch.armR.z = -1.5; ch.legL = 0.6; ch.legR = -0.6;
      ch.sy = 0.96;
      break;
    case 'fair':
      ch.armR.z = w < 0 ? -1.15 * -w : (F + 0.15) * w;
      ch.armL.z = 0.2 - 0.8 * Math.max(0, wLag3);
      ch.lean = 0.45 * w;
      ch.legL = -0.55 - 0.2 * Math.max(0, w); ch.legR = -0.7 + 0.35 * Math.max(0, w);
      ch.head = -0.2 * Math.max(0, wLag4);
      break;
    case 'dair':
      if (w < 0) { ch.armL.z = 2.9 * -w; ch.armR.z = -2.9 * -w; ch.sy = 1 - 0.1 * -w; ch.legL = -0.4 * -w; ch.legR = -0.4 * -w; }
      else { ch.armL.z = 2.9 - 2.6 * w; ch.armR.z = -2.9 + 2.6 * w; ch.sy = 1 + 0.2 * w; ch.sx = 1 - 0.12 * w; ch.head = 0.45 * w; ch.legL = 0.5 * w; ch.legR = 0.4 * w; }
      break;
    case 'uair':
      ch.armR.z = w < 0 ? -0.5 * -w : (F + 1.1) * w;
      ch.armL.z = -0.3 - 0.9 * Math.max(0, wLag2);
      ch.sy = 1 + 0.16 * Math.max(0, w); ch.sx = 1 - 0.09 * Math.max(0, w);
      ch.legL = -0.7 * Math.max(0, w); ch.legR = -0.5 * Math.max(0, w);
      ch.lean = -0.25 * Math.max(0, w);
      break;
    case 'sigside':
      ch.lean = w < 0 ? -0.55 * -w : 0.55 * w;
      ch.armR.z = w < 0 ? -1.6 * -w : (F + 0.35) * w;
      ch.armL.z = 0.3 - 1.1 * Math.max(0, wLag3);
      ch.sx = 1 + 0.24 * Math.max(0, w) - 0.12 * Math.max(0, -w);
      ch.sy = 1 - 0.08 * Math.max(0, w) + 0.12 * Math.max(0, -w);
      ch.legR = 0.75 * Math.max(0, w); ch.legL = -0.5 * Math.max(0, w);
      ch.head = -0.25 * Math.max(0, wLag4);
      ch.bob = -0.12 * Math.max(0, -w);
      break;
    case 'sigdown':
      // An overhead slam: the arms go UP on the wind-up and come DOWN through the strike. The
      // first version held them low through the whole wind-up and raised them as the hitbox came
      // out, which is the motion played backwards — there was no overhead frame to read at all.
      ch.armL.z = w < 0 ? 0.6 + 2.4 * -w : 0.6 - 1.4 * w;
      ch.armR.z = w < 0 ? -0.6 - 2.4 * -w : -0.6 + 1.4 * w;
      ch.sy = w < 0 ? 1 + 0.16 * -w : 1 - 0.26 * w;      // stretch up, then compress into the floor
      ch.sx = w < 0 ? 1 - 0.1 * -w : 1 + 0.22 * w;
      ch.legL = 0.3 * Math.max(0, -w) - 0.5 * Math.max(0, w);
      ch.legR = -0.3 * Math.max(0, -w) + 0.5 * Math.max(0, w);
      ch.bob = 0.3 * Math.max(0, -w) - 0.22 * Math.max(0, w);
      ch.head = 0.3 * Math.max(0, wLag3) - 0.2 * Math.max(0, -w);
      break;
    case 'signeut':
      ch.armR.z = w < 0 ? -1.2 * -w : (F + 0.8) * w;
      ch.armL.z = -0.3 - 1.0 * Math.max(0, wLag3);
      ch.sy = 1 + 0.2 * Math.max(0, w) - 0.14 * Math.max(0, -w);
      ch.sx = 1 - 0.1 * Math.max(0, w) + 0.16 * Math.max(0, -w);
      ch.lean = -0.3 * Math.max(0, w);
      ch.bob = 0.24 * Math.max(0, w);
      ch.legL = -0.4 * Math.max(0, w); ch.legR = 0.3 * Math.max(0, w);
      break;
    case 'burst':
      ch.sx = 1 + 0.3 * Math.max(0, w); ch.sy = 1 + 0.3 * Math.max(0, w);
      ch.armL.z = 1.6 * Math.max(0, w); ch.armR.z = -1.6 * Math.max(0, w);
      break;
    case 'spray':
      ch.armR.z = F * 0.85; ch.armL.z = -0.4;
      ch.lean = 0.2; ch.shakeX = Math.sin(t * 40) * 0.06;
      break;
    case 'thrust':
      // Cock: weight back over the rear leg, spear hand drawn in to the ribs. Drive: the whole
      // body travels, the arm extends along the line, the rear leg straightens behind it.
      ch.armR.z = w < 0 ? -0.5 * -w : F * Math.max(0, w);
      ch.armR.ext = 1 + (w < 0 ? -0.22 * -w : 0.62 * w);    // draws IN on the cock, out on the drive
      ch.armL.z = 0.55 - 1.0 * Math.max(0, wLag3);
      ch.lean = w < 0 ? -0.3 * -w : 0.38 * w;
      ch.legR = 0.95 * Math.max(0, w) - 0.25 * Math.max(0, -w);
      ch.legL = -0.7 * Math.max(0, w) + 0.3 * Math.max(0, -w);
      ch.sx = 1 + 0.1 * Math.max(0, w); ch.sy = 1 - 0.06 * Math.max(0, w) + 0.05 * Math.max(0, -w);
      ch.head = -0.14 * Math.max(0, wLag2);
      ch.bob = -0.2 * Math.max(0, w) + 0.1 * Math.max(0, -w);
      break;
    case 'thrustlow':
      // The same drive aimed at the ankles: the fighter drops into it rather than leaning into it.
      ch.armR.z = w < 0 ? -0.4 * -w : (F + 0.55) * Math.max(0, w);
      ch.armR.ext = 1 + (w < 0 ? -0.18 * -w : 0.52 * w);
      ch.armL.z = 0.5 - 0.8 * Math.max(0, wLag3);
      ch.sy = 1 - 0.3 * Math.max(0, w) + 0.08 * Math.max(0, -w);
      ch.sx = 1 + 0.2 * Math.max(0, w);
      ch.lean = 0.4 * Math.max(0, w) - 0.2 * Math.max(0, -w);
      ch.legR = 1.3 * Math.max(0, w); ch.legL = -0.55 * Math.max(0, w);
      ch.bob = -0.3 * Math.max(0, w);
      ch.head = 0.2 * Math.max(0, wLag3);
      break;
  }
  // Charge hold: the whole body compresses and vibrates, and the vibration gets faster the longer
  // it is held, so a fully charged move is visibly about to go off.
  if (m.charge && f.mf === f.startupEff && f.charge > 0) {
    const c = clamp(f.charge / m.charge.maxHold, 0, 1);
    const p = Math.sin(f.charge * (0.4 + c * 0.9)) * (0.03 + c * 0.05);
    ch.sx += p; ch.sy -= p;
    ch.shakeX = Math.sin(f.charge * (1.2 + c * 2)) * (0.04 + c * 0.1);
    ch.tint = c > 0.85 ? '#FFFFFF' : '#FFF6DC';
  }
}

export function channelsFor(f, t) {
  const ch = { lean: 0, bob: 0, sx: 1, sy: 1, spinY: 0, spinZ: 0, armL: { z: 0.25, x: 0, ext: 1 }, armR: { z: -0.25, x: 0, ext: 1 }, legL: 0, legR: 0, head: 0, opacity: 1, tint: null, rigRotZ: 0, yOff: 0, bubble: 0, visible: true, shakeX: 0, smear: 0 };
  const s = f.state, sf = f.sf;
  const runPhase = f.frameCount * 0.38;
  switch (s) {
    case 'idle': {
      // Two breathing rates slightly out of step, so an idle fighter never looks like a loop.
      const b1 = Math.sin(t * 2.6 + f.index), b2 = Math.sin(t * 1.7 + f.index * 2.1);
      // Amplitudes are for a 480x270 backbuffer at ~5 px per stud, and at four players it drops
      // to ~3. Anything under about 0.2 studs is a sub-pixel no-op: the old idle bob of 0.07 studs
      // was a third of a pixel. These are the smallest values that actually move.
      ch.bob = b1 * 0.26 + b2 * 0.1;
      ch.armL.z = 0.3 + b1 * 0.06; ch.armR.z = -0.3 - Math.sin(t * 2.6 + f.index - 0.35) * 0.06;
      ch.head = b2 * 0.05;
      ch.sy = 1 + b1 * 0.04; ch.sx = 1 - b1 * 0.04;
      break;
    }
    case 'run': {
      const sp = Math.min(1, Math.abs(f.vx) / f.char.runSpeed);
      ch.legL = Math.sin(runPhase) * 0.95 * sp; ch.legR = -Math.sin(runPhase) * 0.95 * sp;
      // Arms lag the legs by a fifth of a cycle — a run where they are exactly opposed is a march.
      ch.armL.x = -Math.sin(runPhase - 0.6) * 0.75 * sp; ch.armR.x = Math.sin(runPhase - 0.6) * 0.75 * sp;
      ch.lean = 0.2 * sp;
      // Two bounces per stride, and the body compresses on each footfall.
      const stride = Math.abs(Math.sin(runPhase));
      ch.bob = stride * 0.14 * sp;
      ch.sy = 1 - (1 - stride) * 0.05 * sp; ch.sx = 1 + (1 - stride) * 0.05 * sp;
      ch.head = -0.08 * sp + Math.sin(runPhase - 1.1) * 0.05 * sp;
      break;
    }
    case 'dash': {
      // A dash is mostly its first four frames: hard lean, then it eases toward a run posture.
      const k = clamp(sf / 8, 0, 1);
      ch.lean = 0.5 - 0.12 * easeOut(k);
      ch.legL = 1.0 - 0.3 * k; ch.legR = -0.9 + 0.3 * k;
      ch.armL.z = 0.9; ch.armR.z = -0.85;
      ch.sx = 1.14 - 0.08 * easeOut(k); ch.sy = 0.9 + 0.06 * easeOut(k);
      ch.smear = 1 - k;
      break;
    }
    case 'jumpsquat': { const k = clamp(sf / 4, 0, 1); ch.sy = 0.82 - 0.06 * k; ch.sx = 1.14 + 0.05 * k; ch.legL = 0.35 * k; ch.legR = -0.35 * k; ch.head = 0.12 * k; break; }
    case 'air': case 'helpless': case 'recovery':
      if (f.vy > 6) {
        // rising: stretched, arms trailing below
        const r = clamp(f.vy / 60, 0, 1);
        ch.sy = 1 + 0.12 * r; ch.sx = 1 - 0.08 * r;
        ch.armL.z = 2.4; ch.armR.z = -2.5; ch.legL = -0.65; ch.legR = -0.5;
        ch.head = -0.1;
      } else if (f.vy < -6) {
        // falling: arms come up, legs reach for the ground
        const r = clamp(-f.vy / 45, 0, 1);
        ch.armL.z = 1.2 - 0.3 * r; ch.armR.z = -1.2 + 0.3 * r;
        ch.legL = 0.35 * r; ch.legR = -0.25 * r;
        ch.sy = f.fastFalling ? 1.12 : 1 + 0.04 * r; ch.sx = f.fastFalling ? 0.9 : 1;
        ch.lean = f.fastFalling ? 0.15 : 0;
      } else {
        // the apex: the moment worth holding, so it gets its own pose
        // The apex had no time term at all — zero motion for as long as a fighter hung there.
        const hang = Math.sin(t * 4.5 + f.index);
        ch.armL.z = 1.7 + hang * 0.12; ch.armR.z = -1.7 - hang * 0.1;
        ch.legL = -0.2 + hang * 0.1; ch.legR = 0.15 - hang * 0.08;
        ch.sy = 0.98 + hang * 0.02; ch.sx = 1.02 - hang * 0.02; ch.head = hang * 0.1;
      }
      if (s === 'helpless') { ch.spinZ = t * 5; ch.armL.z = 2.2; ch.armR.z = -2.2; ch.opacity = 0.9; }
      if (s === 'recovery') { ch.spinY = sf * 0.5; ch.armL.z = 3; ch.armR.z = -3; ch.sy = 1.12; ch.smear = clamp(1 - sf / 12, 0, 1); }
      break;
    case 'landing': {
      // Squash on contact, then a damped settle back to standing rather than a flat six frames.
      const k = clamp(sf / 10, 0, 1);
      const q = 1 - settle(k, 3.0, 6);
      ch.sy = 1 - 0.2 * q; ch.sx = 1 + 0.16 * q;
      ch.legL = 0.3 * q; ch.legR = -0.3 * q;
      ch.bob = -0.14 * q; ch.head = 0.12 * q;
      break;
    }
    case 'attack': attackChannels(ch, f, t); if (!f.onGround) { ch.legL += 0.3; ch.legR -= 0.3; } break;
    case 'hitstun': {
      // The reaction leans AWAY from where the hit came from, and the first frames are the loudest.
      const away = f.vx >= 0 ? 1 : -1;
      const fresh = clamp(1 - sf / 10, 0, 1);
      ch.lean = -0.55 * fresh * away * f.facing;
      ch.armL.z = 2.2 + Math.sin(sf * 0.8) * 0.5 * fresh;
      ch.armR.z = -2.0 - Math.sin(sf * 0.8 + 1) * 0.5 * fresh;
      ch.head = -0.35 * fresh;
      ch.legL = 0.5 + Math.sin(sf * 0.7) * 0.3 * fresh; ch.legR = -0.4 - Math.sin(sf * 0.7) * 0.3 * fresh;
      ch.sx = 1 + 0.1 * fresh; ch.sy = 1 - 0.08 * fresh;
      ch.shakeX = sf < 4 ? (sf % 2 ? 0.18 : -0.18) : 0;
      ch.smear = fresh * 0.6;
      break;
    }
    case 'knockdown': {
      // Was a single frozen frame for its whole duration. A downed fighter still breathes, and a
      // stirring body is how a player reads that the wake-up is coming.
      ch.rigRotZ = -PI / 2 + 0.1; ch.rotPivot = 0; ch.yOff = 0.7;
      const br = Math.sin(sf * 0.22);
      ch.armL.z = 1.2 + br * 0.18; ch.armR.z = -1.2 - br * 0.14;
      ch.sy = 0.95 + br * 0.03; ch.head = br * 0.2; ch.bob = br * 0.1;
      break;
    }
    case 'tech': ch.opacity = 0.6; if (f.techRoll) { ch.spinZ = -sf * 0.42; ch.smear = clamp(1 - sf / 10, 0, 1); } else { const k = clamp(sf / 8, 0, 1); const q = 1 - settle(k, 3, 7); ch.sy = 1 - 0.16 * q; ch.sx = 1 + 0.12 * q; } break;
    case 'shield': case 'shielddrop': {
      const k = clamp(sf / 4, 0, 1);
      ch.sy = 1 - 0.12 * easeOut(k); ch.sx = 1 + 0.06 * easeOut(k);
      ch.armL.z = 0.9 * easeOut(k); ch.armR.z = -0.9 * easeOut(k);
      ch.head = 0.1 * easeOut(k);
      if (s === 'shield') { ch.bubble = Math.max(0.25, f.shield / 50); ch.bob = Math.sin(t * 5) * 0.03; }
      break;
    }
    case 'stunned': ch.lean = Math.sin(sf * 0.3) * 0.3; ch.head = Math.sin(sf * 0.5) * 0.35; ch.armL.z = 1.0 + Math.sin(sf * 0.4) * 0.3; ch.armR.z = -1.0 - Math.sin(sf * 0.4 + 2) * 0.3; ch.spinY = Math.sin(sf * 0.12) * 0.6; ch.tint = sf % 12 < 6 ? '#F4C531' : null; break;
    case 'spotdodge': { const k = clamp(sf / 10, 0, 1); const q = Math.sin(k * PI); ch.opacity = 1 - 0.65 * q; ch.sy = 1 - 0.14 * q; ch.sx = 1 + 0.1 * q; ch.lean = -0.35 * q; break; }
    case 'airdodge': ch.opacity = 0.35; ch.spinZ = sf * 0.45; ch.smear = clamp(1 - sf / 14, 0, 1); break;
    case 'ledge': ch.armL.z = 2.9; ch.armR.z = -2.9; ch.legL = 0.35 + Math.sin(t * 3) * 0.06; ch.legR = -0.2; ch.head = -0.3; ch.bob = Math.sin(t * 4) * 0.22; ch.lean = -0.12 + Math.sin(t * 2.2) * 0.05; break;
    case 'ledgeaction': { const k = f.la?.kind; if (k === 'attack') { ch.armR.z = sf > 8 ? PI / 2 : -0.8; ch.lean = 0.3; ch.smear = sf > 8 ? 0.6 : 0; } else if (k === 'roll') { ch.spinZ = -sf * 0.34; ch.opacity = 0.7; ch.smear = 0.5; } else { ch.lean = -0.2; ch.armL.z = 1.4; ch.armR.z = -1.4; ch.sy = 1.06; } break; }
    case 'grab': { const k = clamp(sf / 8, 0, 1); ch.armL.z = 1.4 + F * easeIn(k); ch.armR.z = -1.4 + (F + 1.4) * easeIn(k); ch.lean = 0.1 + 0.25 * easeIn(k); ch.smear = sf > 6 && sf < 11 ? 0.7 : 0; break; }
    case 'holding': ch.armL.z = PI / 2; ch.armR.z = PI / 2; ch.lean = 0.15; ch.sx = 1.05; ch.bob = Math.sin(t * 6) * 0.16; break;
    case 'grabbed': ch.armL.z = 1.6; ch.armR.z = -1.6; ch.legL = Math.sin(sf * 0.6) * 0.85; ch.legR = -Math.sin(sf * 0.6 + 0.8) * 0.85; ch.head = -0.2 + Math.sin(sf * 0.9) * 0.12; break;
    case 'groundpound': if (sf <= 8) { const k = clamp(sf / 8, 0, 1); ch.sy = 1 - 0.2 * back(k, 1.2); ch.sx = 1 + 0.15 * back(k, 1.2); ch.armL.z = 2.9 * k; ch.armR.z = -2.9 * k; ch.bob = 0.2 * k; } else { ch.sy = 1.28; ch.sx = 0.84; ch.armL.z = 3.1; ch.armR.z = -3.1; ch.legL = 0; ch.legR = 0; ch.smear = 0.8; } break;
    case 'tether': ch.armL.z = 2.9; ch.armR.z = -2.9; ch.sy = 1.15; ch.sx = 0.9; ch.lean = Math.sin(t * 7) * 0.08; break;
    case 'frozen': ch.tint = '#A9D8F0'; ch.armL.z = 1.2; ch.armR.z = -1.2; break;
    case 'taunt': ch.bob = Math.abs(Math.sin(sf * 0.25)) * 0.5; ch.spinY = sf * 0.14; ch.armL.z = 2.6 + Math.sin(sf * 0.5) * 0.45; ch.armR.z = -0.4; break;
    case 'ko': ch.visible = false; break;
    case 'respawn': ch.yOff = Math.sin(t * 4) * 0.3; ch.opacity = 0.85; ch.armL.z = 1.2; ch.armR.z = -1.2; break;
  }
  // Tumble spins from the MOMENT OF THE HIT, not off the fighter's lifetime counter. frameCount
  // is set once at construction and only ever incremented, so `-frameCount * 0.3` meant the body
  // snapped to an essentially arbitrary angle the instant a tumble began, spun from there, and
  // snapped back when it ended. What a launch is supposed to read as is a body that starts
  // upright and goes over; what it read as was a body that teleported into a pose.
  if (f.tumbling && (s === 'air' || s === 'hitstun')) {
    const since = Math.max(0, f.frameCount - f.lastHitFrame);
    ch.spinZ = -since * 0.3 * f.facing;
    ch.smear = Math.max(ch.smear, 0.5);
  }
  if (f.invincible > 0 && s !== 'ledge' && s !== 'respawn' && f.frameCount % 6 < 3) ch.opacity *= 0.55;
  if (f.effects.chill.stacks > 0 && !ch.tint) ch.tint = ['#C9E6F5', '#A9D8F0', '#7FC0E6'][f.effects.chill.stacks - 1];
  if (f.hitlag > 0) ch.shakeX = (f.frameCount % 2 ? 0.12 : -0.12);

  // spinZ is rotation in the screen plane, which IS rigRotZ — they were separate channels and
  // spinZ was wired to nothing, so air dodges, tech rolls and helpless falls all set a spin that
  // rendered as a static pose. Folded here rather than at every call site.
  if (ch.spinZ) ch.rigRotZ += ch.spinZ;
  // spinY is rotation about the fighter's own vertical axis. In 2D that is a horizontal squeeze:
  // the body narrows as it turns edge-on and widens again. Same reason — it was dead.
  if (ch.spinY) ch.sx *= Math.max(0.12, Math.abs(Math.cos(ch.spinY)));
  return ch;
}
