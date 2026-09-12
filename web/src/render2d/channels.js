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

function attackChannels(ch, f, t) {
  const m = f.move; if (!m) return;
  const s = swing(f, m);
  const id = m.id || '';
  const cat = id.startsWith('LightNeutral') ? 'jab'
    : id.startsWith('LightSide') || id === 'ItemSwing' ? 'side'
    : id === 'LightDown' ? 'down' : id === 'LightUp' ? 'up'
    : id === 'AirNeutral' ? 'nair' : id === 'AirForward' ? 'fair'
    : id === 'AirDown' ? 'dair' : id === 'AirUp' ? 'uair'
    : id === 'SigSide' ? 'sigside' : id === 'SigDown' ? 'sigdown' : id === 'SigNeutral' ? 'signeut'
    : id === 'CounterBurst' ? 'burst' : id === 'ItemSpray' ? 'spray' : 'jab';
  ch.smear = s.smear * (m.heavy ? 1 : 0.7);

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

  switch (cat) {
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
  const ch = { lean: 0, bob: 0, sx: 1, sy: 1, spinY: 0, spinZ: 0, armL: { z: 0.25, x: 0 }, armR: { z: -0.25, x: 0 }, legL: 0, legR: 0, head: 0, opacity: 1, tint: null, rigRotZ: 0, yOff: 0, bubble: 0, visible: true, shakeX: 0, smear: 0 };
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
  if (f.tumbling && (s === 'air' || s === 'hitstun')) { ch.spinZ = -f.frameCount * 0.3 * f.facing; ch.smear = Math.max(ch.smear, 0.5); }
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
