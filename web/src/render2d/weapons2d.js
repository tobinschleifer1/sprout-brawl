// Weapons, drawn and animated in 2D.
//
// Two halves:
//   weaponPose(f)  - where the weapon is this frame: angle, offset, swing trail, muzzle flash.
//   drawWeapon()   - the weapon itself, in its own local frame (handle at 0,0, pointing along +X).
//
// Every weapon is authored pointing RIGHT along +X with the grip at the origin, so one drawing
// serves both facings: the renderer mirrors the whole fighter.
//
// Angles are radians, counter-clockwise, 0 = pointing forward, +PI/2 = pointing straight up.
// Swings are keyframed as [windup, contact, follow-through] and interpolated across the move's
// startup / active / recovery, so a swing always lines up with the frames that actually hit.

import { swing as swingPhase, easeOut, easeIn } from './channels.js';

const PI = Math.PI;
const TAU = PI * 2;
const D = (deg) => (deg * PI) / 180;

// How each move swings. `hold` weapons (blasters, grimoire) do not swing at all - they aim.
//   arc:   [windupAngle, contactAngle, endAngle]
//   trail: how much of the arc to smear behind the blade, in radians
const SWINGS = {
  jab:      { arc: [D(70), D(5), D(25)], trail: D(45), thrust: 0.35 },
  side:     { arc: [D(140), D(-25), D(-5)], trail: D(110) },
  down:     { arc: [D(35), D(-70), D(-50)], trail: D(80) },
  // Rising attacks cock BELOW the resting angle (-78) before they come up. They used to start at
  // -50, -40 and -30 — above rest, already on their way to the target — so the wind-up was the
  // weapon travelling toward you. There was nothing to read.
  up:       { arc: [D(-115), D(105), D(80)], trail: D(100) },
  nair:     { arc: [D(0), D(720), D(720)], trail: D(150), spin: true },
  fair:     { arc: [D(130), D(-15), D(5)], trail: D(105) },
  dair:     { arc: [D(-60), D(-95), D(-90)], trail: D(50) },
  uair:     { arc: [D(-110), D(115), D(95)], trail: D(110) },
  sigside:  { arc: [D(175), D(-40), D(-15)], trail: D(150), heavy: true },
  sigdown:  { arc: [D(150), D(-85), D(-65)], trail: D(140), heavy: true },
  signeut:  { arc: [D(-120), D(130), D(110)], trail: D(140), heavy: true },
};

// Per-weapon arc overrides. The shared SWINGS table is the sword's motion, and two weapons do not
// move like a sword at all:
//
//   AXE   every heavy is hauled to overhead and DROPPED. The cocked angle is high and behind
//         (140-175 degrees), the contact angle is at or below the floor line, and the arc between
//         them is the longest in the game — which the shared easing curve already renders as a
//         slow lift into a fast fall. Nothing about the axe needed new animation code, only
//         steeper numbers.
//   PIKE  thrusts rather than swings: tiny angular travel, large `thrust` offsets. The motion is
//         along the haft, not around it.
const SWING_BY_WEAPON = {
  Axe: {
    jab:     { arc: [D(60), D(-5), D(15)], trail: D(60), heavy: true },
    side:    { arc: [D(150), D(-30), D(-10)], trail: D(130), heavy: true },
    down:    { arc: [D(40), D(-80), D(-62)], trail: D(100), heavy: true },
    up:      { arc: [D(-120), D(100), D(70)], trail: D(120), heavy: true },
    fair:    { arc: [D(160), D(-20), D(0)], trail: D(140), heavy: true },
    dair:    { arc: [D(-40), D(-95), D(-90)], trail: D(60), heavy: true },
    uair:    { arc: [D(-115), D(110), D(90)], trail: D(130), heavy: true },
    // the three that define the weapon: overhead, held, then gravity
    sigside: { arc: [D(175), D(-38), D(-14)], trail: D(170), heavy: true },
    sigdown: { arc: [D(168), D(-88), D(-70)], trail: D(165), heavy: true },
    signeut: { arc: [D(-125), D(120), D(98)], trail: D(150), heavy: true },
  },
  // A THRUST reads through the body, not the prop.
  //
  // The first version tried to make the pike look long by sliding the weapon forward off the hand
  // (`thrust`, an offset along the haft) and rotating it barely 25 degrees. Both were wrong: at
  // 3.4 studs the grip ended up further from the hand than the fighter is tall, so it was capped
  // at 0.7 - and 25 degrees of rotation on a 5.9-stud pole is a couple of pixels of tip travel.
  // The weapon did not look like it was being thrust, it looked like it was hovering.
  //
  // The reach now comes from `armR.ext` in channels.js, which extends the ARM: the hand moves, so
  // the weapon goes with it and stays attached. That frees these arcs to do the other half of the
  // job - cocking the point back and low, then driving it up into the line, about 50 degrees of
  // travel, which is what makes the direction of a thrust readable at 480x270.
  Pike: {
    jab:     { arc: [D(-26), D(2), D(-8)], trail: D(26), thrust: 0.2 },
    side:    { arc: [D(-28), D(2), D(-8)], trail: D(28), thrust: 0.25 },
    down:    { arc: [D(-6), D(-34), D(-26)], trail: D(28), thrust: 0.2 },
    up:      { arc: [D(6), D(88), D(72)], trail: D(44), thrust: 0.2 },
    nair:    { arc: [D(0), D(720), D(720)], trail: D(150), spin: true },
    fair:    { arc: [D(-30), D(0), D(-10)], trail: D(30), thrust: 0.3 },
    dair:    { arc: [D(-56), D(-92), D(-86)], trail: D(34), thrust: 0.2 },
    uair:    { arc: [D(16), D(92), D(78)], trail: D(44), thrust: 0.2 },
    sigside: { arc: [D(-34), D(2), D(-10)], trail: D(32), thrust: 0.35, heavy: true },
    sigdown: { arc: [D(-4), D(-38), D(-28)], trail: D(32), thrust: 0.3, heavy: true },
    signeut: { arc: [D(10), D(92), D(76)], trail: D(48), thrust: 0.3, heavy: true },
  },
  // The hammer is the axe's arcs taken further: it is heavier than the axe and every heavy is a
  // lift and a drop, so the cocked angle is higher and the contact is at or below the floor line.
  Hammer: {
    jab:     { arc: [D(70), D(-8), D(12)], trail: D(70), heavy: true },
    side:    { arc: [D(158), D(-32), D(-10)], trail: D(140), heavy: true },
    down:    { arc: [D(46), D(-84), D(-66)], trail: D(110), heavy: true },
    up:      { arc: [D(-124), D(104), D(76)], trail: D(130), heavy: true },
    fair:    { arc: [D(166), D(-22), D(2)], trail: D(150), heavy: true },
    dair:    { arc: [D(-38), D(-96), D(-92)], trail: D(64), heavy: true },
    uair:    { arc: [D(-118), D(112), D(92)], trail: D(140), heavy: true },
    sigside: { arc: [D(178), D(-40), D(-16)], trail: D(175), heavy: true },
    sigdown: { arc: [D(172), D(-90), D(-72)], trail: D(170), heavy: true },
    signeut: { arc: [D(-130), D(124), D(100)], trail: D(158), heavy: true },
  },
  // A dagger is not a small sword: the arcs are short and they end pointing where the blade is
  // going, because at a 1.5-stud blade there is no arc long enough to read on its own. Measured on
  // the blade-vs-hitbox check in geometry.test.mjs, the shared sword arcs put this weapon 71 wrong.
  Daggers: {
    jab:     { arc: [D(58), D(14), D(30)], trail: D(44), thrust: 0.2 },
    side:    { arc: [D(72), D(6), D(24)], trail: D(66) },
    down:    { arc: [D(26), D(-52), D(-36)], trail: D(58) },
    up:      { arc: [D(-88), D(88), D(70)], trail: D(90) },
    nair:    { arc: [D(0), D(720), D(720)], trail: D(150), spin: true },
    fair:    { arc: [D(76), D(8), D(26)], trail: D(68) },
    dair:    { arc: [D(-54), D(-92), D(-86)], trail: D(44) },
    uair:    { arc: [D(-84), D(90), D(74)], trail: D(92) },
    sigside: { arc: [D(88), D(2), D(22)], trail: D(80), heavy: true },
    sigdown: { arc: [D(34), D(-60), D(-44)], trail: D(70), heavy: true },
    signeut: { arc: [D(-92), D(94), D(76)], trail: D(96), heavy: true },
  },
  // The flail's head is on four studs of chain: it travels further than anything else and it does
  // not stop where the swing stops, which is why every settle angle here overshoots.
  Flail: {
    jab:     { arc: [D(96), D(-2), D(34)], trail: D(96), heavy: true },
    side:    { arc: [D(170), D(-34), D(6)], trail: D(160), heavy: true },
    down:    { arc: [D(52), D(-78), D(-44)], trail: D(120), heavy: true },
    up:      { arc: [D(-128), D(112), D(74)], trail: D(140), heavy: true },
    nair:    { arc: [D(0), D(1080), D(1080)], trail: D(200), spin: true },
    fair:    { arc: [D(168), D(-18), D(18)], trail: D(160), heavy: true },
    dair:    { arc: [D(-42), D(-98), D(-88)], trail: D(72), heavy: true },
    uair:    { arc: [D(-122), D(118), D(88)], trail: D(150), heavy: true },
    sigside: { arc: [D(186), D(-40), D(24)], trail: D(190), heavy: true },
    sigdown: { arc: [D(40), D(-86), D(-52)], trail: D(140), heavy: true },
    signeut: { arc: [D(-134), D(128), D(96)], trail: D(160), heavy: true },
  },
};

function categoryOf(id) {
  if (!id) return null;
  if (id === 'Ultimate') return 'ult';
  if (id.startsWith('LightNeutral')) return 'jab';
  if (id.startsWith('LightSide')) return 'side';
  if (id === 'LightDown') return 'down';
  if (id === 'LightUp') return 'up';
  if (id === 'AirNeutral') return 'nair';
  if (id === 'AirForward') return 'fair';
  if (id === 'AirDown') return 'dair';
  if (id === 'AirUp') return 'uair';
  if (id === 'SigSide') return 'sigside';
  if (id === 'SigDown') return 'sigdown';
  if (id === 'SigNeutral') return 'signeut';
  return 'jab';
}

// Weapons that are aimed rather than swung. These get a recoil kick and a muzzle/cast flash on the
// frame the projectile actually leaves, instead of an arc.
const AIMED = { Blasters: true, Grimoire: 'cast', Longbow: true };

// The axe's rest angle is almost straight down and slightly behind: it is not being held, it is
// being dragged. Everything else rests at a carry angle.
const REST = { Sword: D(-78), Scythe: D(-72), Blasters: D(-60), Grimoire: D(-70), Axe: D(-104), Pike: D(-58),
  // The gauntlets and the shield rest near horizontal because they are worn, not carried; the
  // hammer rests lowest of anything but the axe; the flail's head hangs.
  Gauntlets: D(-28), Hammer: D(-98), Longbow: D(-84), Flail: D(-96), Shield: D(-20), Daggers: D(-66) };

// Where a projectile-spawning move actually fires, in absolute move frames.
const fireFrame = (f, m) => f.startupEff + 1;

export function weaponPose(f, t) {
  const wid = f.char.weapon ? f.char.weapon.id : null;
  const out = { angle: REST[wid] ?? D(-70), ox: 0, oy: 0, scale: 1, trail: null, flash: 0, charge: 0, hide: false, ult: null };
  if (!wid) return out;

  const s = f.state;
  const aimed = AIMED[wid];

  // idle / movement poses
  if (s === 'idle' || s === 'run' || s === 'dash') {
    out.angle = (REST[wid] ?? D(-70)) + Math.sin(t * 3 + f.index) * 0.06;
    if (s === 'run' || s === 'dash') out.angle += 0.25;
    // A weapon with `drag` is not carried, it is hauled: the head stays on the floor and the haft
    // trails BEHIND the direction of travel, so the fighter is visibly pulling it rather than
    // holding it. `out.drag` tells the renderer where the head is scraping so it can throw dirt.
    if (f.char.weapon && f.char.weapon.drag && f.onGround) {
      const moving = Math.abs(f.vx) > 1.5;
      out.angle = D(-104) - (moving ? 0.30 : 0.10) - Math.sin(t * 6 + f.index) * (moving ? 0.05 : 0.015);
      out.oy = -0.12;
      out.drag = { scrape: moving ? Math.min(1, Math.abs(f.vx) / f.char.runSpeed) : 0 };
    }
    return out;
  }
  if (s === 'shield' || s === 'shielddrop') { out.angle = D(-100); return out; }
  if (s === 'ledge' || s === 'tether') { out.angle = D(-110); return out; }
  if (s === 'knockdown' || s === 'ko') { out.hide = true; return out; }
  if (s === 'hitstun' || s === 'tumble') { out.angle = D(-120) + Math.sin(f.sf * 0.7) * 0.5; return out; }
  if (s === 'air' || s === 'helpless' || s === 'recovery') { out.angle = D(-95); return out; }
  if (s === 'groundpound') { out.angle = D(-90); return out; }

  if (s !== 'attack' || !f.move) return out;

  const m = f.move;
  const st = f.startupEff, act = m.active, rec = m.recovery, mf = f.mf;
  const cat = categoryOf(m.id);
  if (cat === 'ult') return ultimatePose(f, m, wid, out, t);
  const swing = (SWING_BY_WEAPON[wid] && SWING_BY_WEAPON[wid][cat]) || SWINGS[cat] || SWINGS.jab;

  // charge hold: the weapon sits at the top of the windup and vibrates
  if (m.charge && mf === st && f.charge > 0) {
    out.charge = Math.min(1, f.charge / m.charge.maxHold);
    out.angle = aimed ? D(0) : swing.arc[0];
    out.angle += Math.sin(f.charge * 0.6) * 0.05;
    return out;
  }

  if (aimed) {
    // Aim forward, kick back on the shot, settle. The flash peaks exactly when the projectile
    // leaves, which is the frame the engine spawns it.
    const fire = fireFrame(f, m);
    const since = mf - fire;
    out.angle = D(0);
    if (mf < fire) out.angle = D(-18) * (1 - mf / Math.max(1, fire));       // bringing it up
    else if (since >= 0 && since < 8) {
      const k = since / 8;
      out.angle = D(22) * (1 - k) * (1 - k);                               // recoil kick
      out.ox = -0.35 * (1 - k);
      out.flash = Math.max(0, 1 - since / 3);
    }
    if (aimed === 'cast' && since >= -3 && since < 10) out.flash = Math.max(out.flash, 1 - Math.abs(since) / 10);
    return out;
  }

  // A swing: windup across startup, contact across the active frames, settle across recovery —
  // timed by the SAME curve the body uses.
  //
  // This file used to run its own easing: k*k on the wind-up, 1-(1-k)^2 on the strike, and raw
  // linear k on the recovery. Against channels.js's back(easeOut(k)) that put the torso and the
  // weapon up to fifteen frames out of phase — on Crescent Rush the body was fully loaded on
  // frame 5 and held for sixteen frames while the sword was six percent of the way back, then the
  // sword arrived at its cocked pose one frame before the hitbox came out. Two animations played
  // over each other. And the linear recovery meant the follow-through spring existed in the torso
  // only; the prop slid home in a straight line.
  const ph = swingPhase(f, m);
  let from, to, k;
  if (ph.phase === 'wind') { from = REST[wid] ?? 0; to = swing.arc[0]; k = ph.e; }
  else if (ph.phase === 'strike') { from = swing.arc[0]; to = swing.arc[1]; k = ph.e; }
  // during the settle `e` already runs 1 -> 0 with an overshoot, so the weapon springs past its
  // end pose and comes back exactly as the body does
  else { from = swing.arc[1]; to = swing.arc[2]; k = 1 - ph.e; }
  out.angle = from + (to - from) * k;

  if (swing.thrust) out.ox = swing.thrust * (mf > st && mf <= st + act ? 1 : 0);

  // The trail smears behind the blade while it is actually live, and fades through recovery.
  if (mf > st && mf <= st + act + Math.min(rec, 8)) {
    const past = mf <= st + act ? 1 : 1 - (mf - st - act) / Math.min(rec, 8);
    out.trail = { from: out.angle - swing.trail * (out.angle > from ? -1 : 1), to: out.angle, alpha: past, heavy: !!swing.heavy };
  }
  return out;
}

// ------------------------------------------------------------------------- the ultimates -----
// One per weapon, and each one is the shape of its own move rather than a louder signature:
//   Sword     the blade grows to twice its length, goes straight up, and comes down once
//   Scythe    reaches out, holds, and crushes two fighters into a ball in front of you
//   Blasters  the pistols fold into a rifle that paints a target and fires three tracked rounds
//   Grimoire  the book goes overhead and the sky opens
function ultimatePose(f, m, wid, out, t) {
  const st = f.startupEff, act = m.active, rec = m.recovery, mf = f.mf;
  const k = mf <= st ? mf / Math.max(1, st)
    : mf <= st + act ? (mf - st) / Math.max(1, act)
    : 1 + (mf - st - act) / Math.max(1, rec);
  const inWindup = mf <= st, inActive = mf > st && mf <= st + act;
  const ak = mf - st;                                   // 1-based frame within the active window
  const recK = Math.min(1, (mf - st - act) / Math.max(1, rec));
  out.ult = { phase: inWindup ? 'windup' : inActive ? 'active' : 'end', k, wid };

  if (wid === 'Sword') {
    // The blade grows to weaponScale over the hoist and stays there, so the silhouette alone says
    // what is about to happen. The CHOP is deliberately timed to land on the LAST startup frame:
    // the hitbox and the crater both fire on active frame 1, and a chop that played across the
    // active frames instead had the floor erupting four frames before the sword reached it.
    const FULL = m.weaponScale || 2;
    const CHOP = 5, riseEnd = Math.max(1, st - CHOP);
    if (inWindup) {
      if (mf <= riseEnd) {                              // hoisted overhead, growing as it goes
        const r = mf / riseEnd;
        out.scale = 1 + (FULL - 1) * r;
        out.angle = (REST[wid] ?? 0) + (D(104) - (REST[wid] ?? 0)) * (r * r);
        out.oy = -r * 0.4;
        out.charge = r;
        out.ult.glow = r; out.ult.rise = r;
        return out;
      }
      const c = (mf - riseEnd) / CHOP;                  // and down, arriving as the active frames open
      out.scale = FULL;
      out.angle = D(104) + (D(-84) - D(104)) * (c * c * (3 - 2 * c));
      out.trail = { from: D(104), to: out.angle, alpha: 1, heavy: true };
      out.ult.glow = 1; out.ult.chop = c;
      return out;
    }
    // Planted in the floor while the crater runs outward. The blade SINKS: at full scale a 2x
    // sword held at -84 degrees is a 5-stud bar reaching well below the fighter's feet, and with
    // the edge glow on top of it that drew as a solid white rectangle through the character for
    // eight straight frames. Sinking it over six frames reads as buried, and the crater debris
    // at the floor carries the impact instead.
    const since = inActive ? ak : act + (mf - st - act);
    const sink = Math.min(1, since / 6);
    out.scale = FULL - (FULL - 1.05) * sink;
    out.ult.glow = 1 - sink * 0.75;                     // the edge cools once it is in the ground
    out.angle = D(-84) + Math.sin(since * 0.55) * 0.035;
    out.ult.planted = sink;
    out.ult.shock = inActive ? ak / Math.max(1, act) : 1;
    if (!inActive) {                                    // recovery: shoulder it, back to normal
      out.angle = D(-84) + ((REST[wid] ?? 0) - D(-84)) * recK;
      out.scale = 1.05 + (FULL - 1.05) * 0 + (1 - 1.05) * recK;
      out.ult.glow = (1 - sink * 0.75) * (1 - recK);
    }
    return out;
  }

  if (wid === 'Scythe') {
    const hold = (m.vortex && m.vortex.holdFrames) || 22;
    if (inWindup) {                                     // cocked back, blade high behind the head
      out.angle = (REST[wid] ?? 0) + (D(158) - (REST[wid] ?? 0)) * (k * k);
      out.charge = k;
      return out;
    }
    if (inActive && ak <= hold) {
      const h = ak / hold;
      // the arm reaches out and STAYS out: the hold is the move, so the pose has to hold too
      const reach = Math.min(1, ak / 5);
      out.angle = D(158) + (D(14) - D(158)) * (reach * reach * (3 - 2 * reach));
      out.ox = reach * 0.5;
      out.angle += Math.sin(ak * 1.7) * 0.05 * h;       // strain, rising as the ball tightens
      if (ak <= 6) out.trail = { from: D(158), to: out.angle, alpha: 1 - ak / 8, heavy: true };
      out.ult.pull = h;
      return out;
    }
    // the crush: whip the blade down through the ball
    const since = inActive ? ak - hold : (act - hold) + (mf - st - act);
    const w = Math.min(1, since / 8);
    out.angle = D(14) + (D(-92) - D(14)) * w;
    if (w < 1) out.trail = { from: D(14), to: out.angle, alpha: 1, heavy: true };
    out.ult.crush = w;
    if (!inActive) out.angle = D(-92) + ((REST[wid] ?? 0) - D(-92)) * recK;
    return out;
  }

  if (wid === 'Blasters') {
    // The two pistols fold into one long-barrelled rifle. `rifle` tells drawUltimate to draw the
    // barrel extension and scope, and to leave the second pistol holstered.
    const reload = (m.sniper && m.sniper.reload) || 16;
    out.ult.rifle = inWindup ? k : 1;
    out.ult.rounds = f.ultShots || 0;
    if (inWindup) { out.angle = D(-30) * (1 - k); out.charge = k; out.ox = -0.4 * (1 - k); return out; }
    out.angle = D(0);
    if (inActive) {
      // frames since the last trigger pull, read off the reload counter the engine already keeps
      const since = f.ultCooldown > 0 ? reload - f.ultCooldown : 99;
      if (since < 7) {
        const kk = since / 7;
        out.angle = D(26) * (1 - kk) * (1 - kk);        // hard recoil, this is a rifle now
        out.ox = -0.7 * (1 - kk);
        out.flash = Math.max(0, 1 - since / 2.5);
      } else {
        out.angle = Math.sin(t * 2.2) * D(1.2);         // holding the aim, breathing
      }
      out.ult.aiming = true;
    } else {
      out.angle = D(0) + ((REST[wid] ?? 0) - D(0)) * recK;
      out.ult.rifle = 1 - recK;
    }
    return out;
  }

  if (wid === 'Axe') {
    // REAVE. The wind-up is the only moment of effort: the fighter hauls the head back and low,
    // where its weight will do the most work once it starts moving. After that they are not
    // swinging it, they are being swung BY it — the angle just accelerates, three revolutions
    // getting faster, and the body leans out against the centrifugal pull.
    const A = m.hitboxes || [];
    if (inWindup) {
      out.angle = (REST[wid] ?? 0) + (D(-150) - (REST[wid] ?? 0)) * (k * k);
      out.charge = k; out.oy = -0.1;
      out.ult.haul = k;                          // renderer: strain lines and a dust scuff
      return out;
    }
    if (inActive) {
      // revolutions accelerate: the exponent is what sells "the weight has taken over"
      // PI*6 is three revolutions, which is what the move is described as. The exponent is 1.15,
      // not 1.45: at 1.45 the finisher box spun at 5.7 rev/s, making the one pass that actually
      // sends the least legible frame of the whole move.
      const spin = Math.pow(ak / Math.max(1, act), 1.15) * PI * 6.0;
      out.angle = D(-150) - spin;
      out.scale = m.weaponScale || 1.35;
      out.trail = { from: out.angle + D(300), to: out.angle, alpha: 1, heavy: true };
      out.ult.reave = ak / Math.max(1, act);
      out.ult.blur = [out.angle + D(115), out.angle + D(232)];
      return out;
    }
    out.angle = D(-84) + ((REST[wid] ?? 0) - D(-84)) * recK;
    out.scale = (m.weaponScale || 1.35) - ((m.weaponScale || 1.35) - 1) * recK;
    return out;
  }

  if (wid === 'Pike') {
    // LANCE CHARGE. The haft telescopes — `scale` ramps across the wind-up and stays out — and
    // then delivers a run of thrusts, each one further than the last. The angle barely moves;
    // everything is along the line, which is the whole identity of the weapon.
    const FULL = m.weaponScale || 1.9;
    if (inWindup) {
      out.angle = D(-58) + (D(-6) - D(-58)) * easeOut(k);
      out.scale = 1 + (FULL - 1) * k;
      out.charge = k;
      out.ult.extend = k;
      return out;
    }
    if (inActive) {
      out.scale = FULL;
      // FIVE thrusts, one per hitbox step, so a damage tick always lands on a visible punch
      const per = act / 5;
      const phase = (ak % per) / per;
      const punch = phase < 0.35 ? easeIn(phase / 0.35) : 1 - (phase - 0.35) / 0.65;
      out.angle = D(-6) + Math.sin(ak * 0.4) * D(3);
      // Small, now that the ARM extends on the punch (channels.js, ultChannels/Pike): the hand
      // carries most of the travel and this is just the haft sliding through the grip.
      out.ox = punch * 0.25;
      out.flash = punch > 0.8 ? (punch - 0.8) * 5 : 0;
      out.ult.lance = { punch, reach: ak / Math.max(1, act) };
      if (punch > 0.5) out.trail = { from: out.angle - D(8), to: out.angle, alpha: punch, heavy: true };
      return out;
    }
    out.angle = D(-6) + ((REST[wid] ?? 0) - D(-6)) * recK;
    out.scale = FULL - (FULL - 1) * recK;
    return out;
  }

  if (wid === 'Gauntlets') {
    // HUNDRED HANDS. There is nothing to swing, so the pose is the arms: wound back on the
    // wind-up, then a blur that does not resolve until the last punch.
    if (inWindup) { out.angle = D(-40) + (D(-110) - D(-40)) * (k * k); out.charge = k; out.ult.haul = k; return out; }
    if (inActive) {
      const p2 = ak / Math.max(1, act);
      out.angle = D(-6) + Math.sin(ak * 1.9) * D(26);
      out.ox = 0.12 + Math.abs(Math.sin(ak * 1.9)) * 0.2;
      out.ult.flurry = p2;
      out.ult.blur = [out.angle + D(26), out.angle - D(26)];
      if (ak > act - 10) { out.angle = D(2); out.ox = 0.32; out.ult.finish = (ak - (act - 10)) / 10; }
      return out;
    }
    out.angle = D(-6) + ((REST[wid] ?? 0) - D(-6)) * recK;
    return out;
  }

  if (wid === 'Hammer') {
    // UPHEAVAL. One strike into the floor, and then the hammer STAYS there for the whole move -
    // the fighter is holding the ground open while the columns come up under people. The old pose
    // was a lift-and-drop written for a different ultimate; a prop that falls and then does nothing
    // for sixty frames reads as the move having ended.
    const FULL = m.weaponScale || 1.4;
    const CHOP = 8, riseEnd = Math.max(1, st - CHOP);
    if (inWindup) {
      if (mf <= riseEnd) {
        const r = mf / riseEnd;
        out.scale = 1 + (FULL - 1) * r;
        out.angle = (REST[wid] ?? 0) + (D(120) - (REST[wid] ?? 0)) * (r * r);
        out.oy = -r * 0.4; out.charge = r;
        out.ult.haul = r; out.ult.glow = r;
        return out;
      }
      const c = (mf - riseEnd) / CHOP;
      out.scale = FULL;
      out.angle = D(120) + (D(-92) - D(120)) * (c * c * (3 - 2 * c));
      out.trail = { from: D(120), to: out.angle, alpha: 1, heavy: true };
      out.ult.glow = 1; out.ult.chop = c;
      return out;
    }
    if (inActive) {
      // planted, and shuddering every time another column goes up
      const U = m.upheaval;
      const beat = U ? (ak % U.every) / U.every : 0;
      out.scale = FULL * 0.96;
      out.angle = D(-92) + Math.sin(ak * 0.7) * 0.03;
      out.ult.planted = 1;
      out.ult.shock = 1 - beat;
      out.ult.glow = 0.4 + (1 - beat) * 0.6;
      return out;
    }
    out.angle = D(-92) + ((REST[wid] ?? 0) - D(-92)) * recK;
    out.scale = FULL * 0.96 - (FULL * 0.96 - 1) * recK;
    return out;
  }

  if (wid === 'Longbow') {
    // HEARTSEEKER. Forty-four frames of drawing, one release. The whole pose is the draw: the bow
    // comes level, the string hand pulls in, and the only fast thing in the move is the loose.
    if (inWindup) {
      const r = easeOut(k);
      out.angle = (REST[wid] ?? 0) + (D(-2) - (REST[wid] ?? 0)) * r;
      out.charge = k;
      out.ult.draw = k;                       // renderer: the string and the aiming line
      out.ox = -0.22 * k;                     // the whole bow drifts back as it is drawn
      return out;
    }
    if (inActive) {
      const kk = Math.min(1, ak / 5);
      out.angle = D(-2) + D(9) * (1 - kk) * (1 - kk);   // the snap forward on release
      out.ox = 0.26 * (1 - kk);
      out.flash = Math.max(0, 1 - ak / 3);
      out.ult.loose = kk;
      return out;
    }
    out.angle = D(-2) + ((REST[wid] ?? 0) - D(-2)) * recK;
    return out;
  }

  if (wid === 'Flail') {
    // ANCHOR. The head is thrown, and after that the fighter is not swinging anything - they are
    // walking around holding the other end of a chain. The old pose was a three-revolution spin
    // written for a different ultimate, and it made a move about positioning look like a move
    // about standing in one place.
    if (inWindup) {
      out.angle = (REST[wid] ?? 0) + (D(-150) - (REST[wid] ?? 0)) * (k * k);
      out.charge = k; out.ult.haul = k;
      return out;
    }
    if (inActive) {
      // the throw, then an arm held out along the chain for the rest of it
      const thrown = Math.min(1, ak / 6);
      out.angle = D(-150) + (D(-14) - D(-150)) * (thrown * thrown * (3 - 2 * thrown));
      if (thrown < 1) out.trail = { from: D(-150), to: out.angle, alpha: 1, heavy: true };
      // the head is gone: hide the prop and let the world-space chain BE the weapon
      out.hide = thrown >= 1;
      out.ult.anchored = thrown >= 1 ? 1 : 0;
      out.ox = 0.2 * thrown;
      return out;
    }
    out.hide = false;
    out.angle = D(-14) + ((REST[wid] ?? 0) - D(-14)) * recK;
    return out;
  }

  if (wid === 'Shield') {
    // LAST STAND. The shield plants and does not move: the whole performance is the fighter
    // behind it, so the prop's job here is to sit absolutely still and grow.
    if (inWindup) { out.angle = (REST[wid] ?? 0) + (D(-4) - (REST[wid] ?? 0)) * easeOut(k); out.ox = 0.2 * k; out.charge = k; out.ult.brace = k; return out; }
    if (inActive) {
      out.angle = D(-4);
      out.ox = 0.2 + Math.sin(ak * 0.9) * 0.04;
      out.scale = 1.12;
      out.ult.wall = ak / Math.max(1, act);
      if (ak > act - 12) { out.ult.release = (ak - (act - 12)) / 12; out.ox = 0.2 + out.ult.release * 0.14; out.scale = 1.12 + out.ult.release * 0.45; }
      return out;
    }
    out.angle = D(-4) + ((REST[wid] ?? 0) - D(-4)) * recK;
    out.ox = 0.2 * (1 - recK);
    return out;
  }

  if (wid === 'Daggers') {
    // THOUSAND CUTS. The blades are where the fighter is not: the pose flickers between two
    // extremes rather than travelling between them, which is the only way a teleport reads.
    if (inWindup) { out.angle = (REST[wid] ?? 0) + (D(-150) - (REST[wid] ?? 0)) * (k * k); out.charge = k; out.ult.haul = k; return out; }
    if (inActive) {
      const flip = Math.floor(ak / 3) % 2 ? 1 : -1;
      out.angle = D(20) * flip + Math.sin(ak * 2.6) * D(14);
      out.ox = 0.16 + (flip > 0 ? 0.16 : 0);
      out.ult.flurry = ak / Math.max(1, act);
      out.ult.blur = [out.angle + D(150), out.angle - D(150)];
      if (ak > act - 10) { out.angle = D(6); out.ox = 0.3; out.ult.finish = (ak - (act - 10)) / 10; }
      return out;
    }
    out.angle = D(6) + ((REST[wid] ?? 0) - D(6)) * recK;
    return out;
  }

  // Grimoire: the book goes overhead and stays there while the sky falls.
  if (inWindup) { out.angle = D(-70) + k * D(160); out.charge = k; out.oy = k * 0.3; return out; }
  out.angle = D(92) + Math.sin(mf * 0.5) * 0.05;
  out.oy = 0.3;
  if (inActive) {
    out.ult.runes = ak / Math.max(1, act);
    out.flash = 0.35;
    // a pulse of light each time a wave of orbs leaves the book
    const S = m.starfall;
    if (S) { const since = (ak - 1) % S.every; if (since < 6 && ak - 1 < S.perTarget * S.every) out.flash = 1 - since / 6; }
  } else {
    out.angle = D(92) + ((REST[wid] ?? 0) - D(92)) * recK;
  }
  return out;
}


// ---------------------------------------------------------------------------- the weapons -----
// Drawn in local space: grip at (0,0), weapon extending along +X, one unit = one stud.

function poly(ctx, pts, fill) {
  ctx.beginPath();
  ctx.moveTo(pts[0][0], pts[0][1]);
  for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
  ctx.closePath();
  ctx.fillStyle = fill;
  ctx.fill();
}

function sword(ctx, p, L) {
  // Two values on the blade, not one. A flat primary-coloured wedge is a grey stick at gameplay
  // size; a lit upper bevel with a shaded lower one reads as an edge even at twenty pixels.
  poly(ctx, [[-0.5, -0.16], [0.0, -0.16], [0.0, 0.16], [-0.5, 0.16]], p.tertiary);         // grip
  poly(ctx, [[-0.46, -0.12], [-0.04, -0.12], [-0.04, -0.02], [-0.46, -0.02]], 'rgba(255,255,255,0.10)');
  poly(ctx, [[-0.68, 0], [-0.5, -0.24], [-0.38, 0], [-0.5, 0.24]], p.secondary);           // pommel, a diamond
  poly(ctx, [[-0.02, -0.60], [0.10, -0.44], [0.20, 0], [0.10, 0.44], [-0.02, 0.60],
             [-0.10, 0.40], [-0.10, -0.40]], p.secondary);                                 // swept crossguard
  poly(ctx, [[0.14, -0.19], [L - 0.45, -0.19], [L, 0], [L - 0.45, 0.19], [0.14, 0.19]], p.primary);
  poly(ctx, [[0.14, -0.19], [L - 0.45, -0.19], [L - 0.2, -0.07], [0.14, -0.05]], 'rgba(255,255,255,0.20)'); // lit bevel
  poly(ctx, [[0.14, 0.19], [L - 0.45, 0.19], [L - 0.2, 0.07], [0.14, 0.05]], 'rgba(0,0,0,0.22)');           // shaded bevel
  poly(ctx, [[0.14, -0.06], [L - 0.5, -0.06], [L - 0.4, 0], [L - 0.5, 0.06], [0.14, 0.06]], p.accent);      // fuller
}

function scythe(ctx, p, L) {
  poly(ctx, [[-0.7, -0.11], [L, -0.11], [L, 0.11], [-0.7, 0.11]], p.tertiary);            // shaft
  poly(ctx, [[L - 0.22, -0.2], [L + 0.1, -0.2], [L + 0.1, 0.2], [L - 0.22, 0.2]], p.secondary); // tang
  // crescent: an arc swept back from the head, tapering to a point
  const cx = L - 0.1, cy = 1.55, r = 1.62;
  ctx.beginPath();
  ctx.arc(cx, cy, r, D(250), D(310));
  ctx.lineTo(cx + Math.cos(D(310)) * (r - 0.42), cy + Math.sin(D(310)) * (r - 0.42));
  ctx.arc(cx, cy, r - 0.42, D(310), D(250), true);
  ctx.closePath();
  ctx.fillStyle = p.primary; ctx.fill();
  ctx.beginPath();
  ctx.arc(cx, cy, r - 0.08, D(256), D(304));
  ctx.strokeStyle = p.accent; ctx.lineWidth = 0.09; ctx.stroke();
}

function blaster(ctx, p) {
  poly(ctx, [[-0.34, -0.30], [0.42, -0.30], [0.42, 0.06], [-0.34, 0.06]], p.primary);      // slide
  poly(ctx, [[-0.30, -0.26], [0.36, -0.26], [0.36, -0.16], [-0.30, -0.16]], p.accent);     // top rail
  poly(ctx, [[-0.34, -0.02], [0.42, -0.02], [0.42, 0.06], [-0.34, 0.06]], 'rgba(0,0,0,0.28)'); // shaded underside
  poly(ctx, [[0.30, -0.20], [0.92, -0.20], [0.92, 0.02], [0.30, 0.02]], p.secondary);      // barrel
  poly(ctx, [[0.30, -0.20], [0.92, -0.20], [0.92, -0.13], [0.30, -0.13]], 'rgba(255,255,255,0.18)');
  poly(ctx, [[0.10, -0.42], [0.22, -0.42], [0.22, -0.28], [0.10, -0.28]], p.secondary);    // the sight
  poly(ctx, [[-0.30, 0.02], [0.02, 0.02], [0.14, 0.62], [-0.18, 0.62]], p.primary);        // grip
  poly(ctx, [[-0.22, 0.06], [-0.04, 0.06], [0.04, 0.50], [-0.12, 0.50]], 'rgba(0,0,0,0.22)');
  poly(ctx, [[0.06, 0.04], [0.30, 0.04], [0.30, 0.12], [0.06, 0.12]], p.tertiary);         // trigger guard
}

function grimoire(ctx, p) {
  poly(ctx, [[-0.55, -0.72], [0.62, -0.60], [0.62, 0.60], [-0.55, 0.72]], p.primary);      // cover
  poly(ctx, [[-0.55, -0.72], [0.62, -0.60], [0.62, -0.46], [-0.55, -0.58]], p.accent);     // lit edge
  poly(ctx, [[-0.55, 0.46], [0.62, 0.40], [0.62, 0.60], [-0.55, 0.72]], 'rgba(0,0,0,0.26)'); // shaded edge
  poly(ctx, [[0.50, -0.58], [0.78, -0.54], [0.78, 0.54], [0.50, 0.58]], '#F0E7D2');         // pages
  poly(ctx, [[0.50, -0.58], [0.78, -0.54], [0.78, -0.40], [0.50, -0.44]], 'rgba(0,0,0,0.16)');
  poly(ctx, [[-0.66, -0.70], [-0.50, -0.70], [-0.50, 0.70], [-0.66, 0.70]], p.tertiary);   // spine
  poly(ctx, [[0.44, -0.30], [0.70, -0.28], [0.70, -0.14], [0.44, -0.16]], p.secondary);    // clasps
  poly(ctx, [[0.44, 0.14], [0.70, 0.12], [0.70, 0.26], [0.44, 0.24]], p.secondary);
  ctx.beginPath(); ctx.arc(0.05, 0, 0.24, 0, PI * 2);
  ctx.fillStyle = p.glow || p.accent; ctx.fill();
  ctx.beginPath(); ctx.arc(0.05, 0, 0.12, 0, PI * 2);
  ctx.fillStyle = 'rgba(255,255,255,0.55)'; ctx.fill();
}

function axe(ctx, p, L) {
  // A haft you can see the weight on: thick, dark, and long, with a head that is most of the mass.
  // The haft is drawn in `hilt`, a value light enough to read: at p.tertiary (#2E2A26) it was
  // 1.02:1 against the animation sheet's background and 3.75 studs of the weapon simply vanished,
  // leaving a grey head floating near the fighter's feet with nothing connecting it to the hand.
  poly(ctx, [[-0.85, -0.14], [L - 0.2, -0.14], [L - 0.2, 0.14], [-0.85, 0.14]], p.hilt || p.secondary);
  poly(ctx, [[-0.95, -0.22], [-0.7, -0.22], [-0.7, 0.22], [-0.95, 0.22]], p.secondary);        // butt cap
  poly(ctx, [[0.1, -0.2], [0.34, -0.2], [0.34, 0.2], [0.1, 0.2]], p.secondary);                // grip wrap
  // the head: a broad bearded blade biting forward, plus a spike on the reverse
  const h = L - 0.5;
  ctx.beginPath();
  ctx.moveTo(h, -0.2);
  ctx.lineTo(h + 0.5, -1.25);
  ctx.lineTo(L + 0.34, -0.9);
  ctx.lineTo(L + 0.5, 0.1);
  ctx.lineTo(h + 0.62, 1.1);
  ctx.lineTo(h, 0.24);
  ctx.closePath();
  ctx.fillStyle = p.primary; ctx.fill();
  // The cheek of the head, a value darker: a solid slab of one colour reads as cardboard, and the
  // axe head is the biggest single shape any weapon in the game puts on screen.
  ctx.beginPath();
  ctx.moveTo(h, -0.2); ctx.lineTo(h + 0.44, -0.95); ctx.lineTo(h + 0.62, 0.05); ctx.lineTo(h + 0.5, 0.85); ctx.lineTo(h, 0.24);
  ctx.closePath();
  ctx.fillStyle = 'rgba(0,0,0,0.26)'; ctx.fill();
  // a bright edge along the bite, which is the part that has to read at gameplay size
  ctx.beginPath();
  ctx.moveTo(h + 0.5, -1.25); ctx.lineTo(L + 0.34, -0.9); ctx.lineTo(L + 0.5, 0.1); ctx.lineTo(h + 0.62, 1.1);
  ctx.strokeStyle = p.accent; ctx.lineWidth = 0.16; ctx.stroke();
  poly(ctx, [[h - 0.28, -0.34], [h - 0.02, -0.78], [h + 0.1, -0.3], [h + 0.1, 0.3], [h - 0.02, 0.62], [h - 0.28, 0.34]], p.secondary);  // reverse spike
  poly(ctx, [[-0.85, -0.14], [L - 0.2, -0.14], [L - 0.2, -0.05], [-0.85, -0.05]], 'rgba(255,255,255,0.12)');  // lit side of the haft
}

function pike(ctx, p, L) {
  // Almost all haft. The point is small and the shape is a line, because the whole weapon is reach.
  poly(ctx, [[-1.5, -0.09], [L - 0.6, -0.09], [L - 0.6, 0.09], [-1.5, 0.09]], p.primary);      // haft
  poly(ctx, [[-1.62, -0.16], [-1.36, -0.16], [-1.36, 0.16], [-1.62, 0.16]], p.secondary);      // counterweight
  for (let i = 0; i < 3; i++) {                                                                 // binding rings
    const x = -0.9 + i * 1.15;
    poly(ctx, [[x, -0.13], [x + 0.16, -0.13], [x + 0.16, 0.13], [x, 0.13]], p.tertiary);
  }
  // langets and the head
  poly(ctx, [[L - 0.75, -0.2], [L - 0.3, -0.2], [L - 0.3, 0.2], [L - 0.75, 0.2]], p.secondary);
  poly(ctx, [[-1.5, -0.09], [L - 0.6, -0.09], [L - 0.6, -0.03], [-1.5, -0.03]], 'rgba(255,255,255,0.16)');   // lit side of the haft
  poly(ctx, [[-1.5, 0.04], [L - 0.6, 0.04], [L - 0.6, 0.09], [-1.5, 0.09]], 'rgba(0,0,0,0.20)');             // and the shaded one
  poly(ctx, [[0.55, -0.15], [1.5, -0.15], [1.5, 0.15], [0.55, 0.15]], p.tertiary);                           // the leather grip
  ctx.beginPath();
  ctx.moveTo(L - 0.35, -0.26);
  ctx.lineTo(L + 0.55, 0);
  ctx.lineTo(L - 0.35, 0.26);
  ctx.closePath();
  ctx.fillStyle = p.accent; ctx.fill();
  poly(ctx, [[L - 0.35, 0.04], [L + 0.42, 0.02], [L - 0.35, 0.26]], 'rgba(0,0,0,0.26)');                     // the point has a near face
  ctx.beginPath(); ctx.moveTo(L - 0.3, -0.04); ctx.lineTo(L + 0.5, -0.01);
  ctx.strokeStyle = p.glow || p.accent; ctx.lineWidth = 0.07; ctx.stroke();
}


// ------------------------------------------------------- the six weapons added from the brief -----

function gauntlets(ctx, p) {
  // No weapon: a bracer and a fist. The shortest thing in the game, so what has to read is the
  // SILHOUETTE of a wrapped hand rather than any detail on it.
  poly(ctx, [[-0.5, -0.30], [0.18, -0.34], [0.18, 0.34], [-0.5, 0.30]], p.secondary);      // bracer
  poly(ctx, [[-0.5, -0.30], [0.18, -0.34], [0.18, -0.20], [-0.5, -0.16]], p.accent);       // lit edge
  poly(ctx, [[0.14, -0.38], [0.86, -0.34], [0.94, 0], [0.86, 0.34], [0.14, 0.38]], p.primary); // fist
  poly(ctx, [[0.42, -0.30], [0.90, -0.24], [0.90, -0.08], [0.42, -0.12]], 'rgba(255,255,255,0.22)');
  poly(ctx, [[0.42, 0.14], [0.90, 0.10], [0.90, 0.26], [0.42, 0.30]], 'rgba(0,0,0,0.26)');
  for (let i = 0; i < 3; i++) poly(ctx, [[0.66, -0.26 + i * 0.22], [0.92, -0.24 + i * 0.22], [0.92, -0.14 + i * 0.22], [0.66, -0.16 + i * 0.22]], p.glow || p.accent); // knuckles
}

function hammer(ctx, p, L) {
  // A long haft and a head that is most of the weight. Bigger and blockier than the axe's, with a
  // spike on the reverse so the silhouette is not symmetrical - that is what tells them apart at
  // twenty pixels.
  poly(ctx, [[-1.1, -0.15], [L - 0.25, -0.15], [L - 0.25, 0.15], [-1.1, 0.15]], p.hilt || p.secondary);
  poly(ctx, [[-1.1, -0.15], [L - 0.25, -0.15], [L - 0.25, -0.05], [-1.1, -0.05]], 'rgba(255,255,255,0.14)');
  poly(ctx, [[-1.24, -0.24], [-0.96, -0.24], [-0.96, 0.24], [-1.24, 0.24]], p.secondary);   // butt cap
  const h = L - 0.55;
  poly(ctx, [[h, -1.05], [L + 0.62, -1.05], [L + 0.62, 1.05], [h, 1.05]], p.primary);       // the head
  poly(ctx, [[h, -1.05], [L + 0.62, -1.05], [L + 0.62, -0.55], [h, -0.55]], 'rgba(255,255,255,0.20)');
  poly(ctx, [[h, 0.55], [L + 0.62, 0.55], [L + 0.62, 1.05], [h, 1.05]], 'rgba(0,0,0,0.30)');
  ctx.strokeStyle = p.accent; ctx.lineWidth = 0.14;
  ctx.beginPath(); ctx.moveTo(L + 0.62, -1.05); ctx.lineTo(L + 0.62, 1.05); ctx.stroke();   // the face
  poly(ctx, [[h - 0.62, -0.30], [h, -0.42], [h, 0.42], [h - 0.62, 0.30]], p.secondary);     // reverse spike
}

function longbow(ctx, p, L) {
  // Drawn as a bow held at the grip: two limbs curving away and a string between the tips. The
  // string is the read - it is the only straight line on the weapon.
  ctx.strokeStyle = p.primary; ctx.lineWidth = 0.22; ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(0.1, -L);
  ctx.quadraticCurveTo(0.95, -L * 0.45, 1.0, 0);
  ctx.quadraticCurveTo(0.95, L * 0.45, 0.1, L);
  ctx.stroke();
  ctx.strokeStyle = 'rgba(255,255,255,0.35)'; ctx.lineWidth = 0.08;
  ctx.beginPath();
  ctx.moveTo(0.16, -L * 0.9); ctx.quadraticCurveTo(0.9, -L * 0.4, 0.94, 0); ctx.stroke();
  ctx.strokeStyle = p.accent; ctx.lineWidth = 0.06;                                          // the string
  ctx.beginPath(); ctx.moveTo(0.1, -L); ctx.lineTo(0.1, L); ctx.stroke();
  poly(ctx, [[0.62, -0.42], [1.02, -0.42], [1.02, 0.42], [0.62, 0.42]], p.secondary);        // the grip
  ctx.lineCap = 'butt';
}

function flail(ctx, p, L) {
  // Handle, chain, ball. The chain is drawn as discrete links because a smooth line at this scale
  // reads as a stick, and a stick is the pike.
  poly(ctx, [[-0.9, -0.14], [0.35, -0.14], [0.35, 0.14], [-0.9, 0.14]], p.hilt || p.secondary);
  poly(ctx, [[-1.02, -0.2], [-0.8, -0.2], [-0.8, 0.2], [-1.02, 0.2]], p.secondary);
  const links = 5, span = L - 1.0;
  for (let i = 0; i < links; i++) {
    const x = 0.4 + (i / links) * span;
    poly(ctx, [[x, -0.11], [x + span / links * 0.7, -0.11], [x + span / links * 0.7, 0.11], [x, 0.11]], i % 2 ? p.tertiary : p.secondary);
  }
  const bx = L + 0.1;
  ctx.beginPath(); ctx.arc(bx, 0, 0.52, 0, TAU);                                             // the ball
  ctx.fillStyle = p.primary; ctx.fill();
  ctx.beginPath(); ctx.arc(bx - 0.14, -0.14, 0.2, 0, TAU);
  ctx.fillStyle = 'rgba(255,255,255,0.28)'; ctx.fill();
  for (let i = 0; i < 6; i++) {                                                              // spikes
    const a = (i / 6) * TAU + 0.3;
    poly(ctx, [[bx + Math.cos(a) * 0.45, Math.sin(a) * 0.45],
      [bx + Math.cos(a) * 0.86, Math.sin(a) * 0.86],
      [bx + Math.cos(a + 0.4) * 0.45, Math.sin(a + 0.4) * 0.45]], p.accent);
  }
}

function shieldWeapon(ctx, p, L) {
  // A kite shield seen edge-on-ish: tall, a boss in the middle, a rim that catches the light. It
  // is drawn ACROSS the arm rather than along it, because that is how a shield is carried.
  poly(ctx, [[-0.2, -L], [0.5, -L * 0.82], [0.72, 0], [0.5, L * 0.82], [-0.2, L], [-0.36, 0]], p.primary);
  poly(ctx, [[-0.2, -L], [0.5, -L * 0.82], [0.56, -L * 0.5], [-0.24, -L * 0.6]], 'rgba(255,255,255,0.24)');
  poly(ctx, [[-0.2, L], [0.5, L * 0.82], [0.56, L * 0.5], [-0.24, L * 0.6]], 'rgba(0,0,0,0.26)');
  ctx.strokeStyle = p.accent; ctx.lineWidth = 0.1;
  ctx.beginPath();
  ctx.moveTo(-0.2, -L); ctx.lineTo(0.5, -L * 0.82); ctx.lineTo(0.72, 0); ctx.lineTo(0.5, L * 0.82); ctx.lineTo(-0.2, L);
  ctx.stroke();
  ctx.beginPath(); ctx.arc(0.22, 0, 0.3, 0, TAU);                                            // the boss
  ctx.fillStyle = p.secondary; ctx.fill();
  ctx.beginPath(); ctx.arc(0.22, 0, 0.14, 0, TAU);
  ctx.fillStyle = p.glow || p.accent; ctx.fill();
}

function daggers(ctx, p, L) {
  // TWO blades, offset from each other, because one dagger is a short sword. The second is drawn
  // behind and reversed - the silhouette has to say "a pair" in the frame it is on screen.
  poly(ctx, [[-0.62, -0.10], [-0.16, -0.10], [-0.16, 0.10], [-0.62, 0.10]], p.tertiary);     // back grip
  poly(ctx, [[-0.2, -0.20], [-0.05, -0.20], [-0.05, 0.20], [-0.2, 0.20]], p.secondary);
  poly(ctx, [[-0.05, -0.11], [-L * 0.62, -0.05], [-L * 0.78, 0], [-L * 0.62, 0.05], [-0.05, 0.11]], 'rgba(160,172,190,0.9)'); // reversed blade
  poly(ctx, [[-0.5, -0.13], [0.0, -0.13], [0.0, 0.13], [-0.5, 0.13]], p.secondary);          // front grip
  poly(ctx, [[-0.08, -0.26], [0.1, -0.26], [0.1, 0.26], [-0.08, 0.26]], p.tertiary);         // guard
  poly(ctx, [[0.1, -0.15], [L - 0.28, -0.13], [L, 0], [L - 0.28, 0.13], [0.1, 0.15]], p.primary);
  poly(ctx, [[0.1, -0.15], [L - 0.28, -0.13], [L - 0.2, -0.04], [0.1, -0.05]], 'rgba(255,255,255,0.26)');
  poly(ctx, [[0.1, 0.05], [L - 0.2, 0.04], [L - 0.28, 0.13], [0.1, 0.15]], 'rgba(0,0,0,0.24)');
  ctx.strokeStyle = p.glow || p.accent; ctx.lineWidth = 0.05;
  ctx.beginPath(); ctx.moveTo(0.2, 0); ctx.lineTo(L - 0.24, 0); ctx.stroke();
}

const SHAPES = { Sword: (c, p) => sword(c, p, 2.35), Scythe: (c, p) => scythe(c, p, 2.9), Blasters: blaster, Grimoire: grimoire,
  Axe: (c, p) => axe(c, p, 2.9), Pike: (c, p) => pike(c, p, 5.4),
  Gauntlets: gauntlets, Hammer: (c, p) => hammer(c, p, 3.1), Longbow: (c, p) => longbow(c, p, 1.5),
  Flail: (c, p) => flail(c, p, 3.6), Shield: (c, p) => shieldWeapon(c, p, 1.5), Daggers: (c, p) => daggers(c, p, 1.5) };

// Blade length per weapon, used to size the swing trail.
export const REACH = { Sword: 2.6, Scythe: 3.4, Blasters: 1.1, Grimoire: 0.9, Axe: 3.2, Pike: 5.9,
  Gauntlets: 1.0, Hammer: 3.7, Longbow: 1.2, Flail: 4.2, Shield: 1.3, Daggers: 1.7 };

// A palette whose every entry is the same dark value, for the contour pass below.
const CONTOUR = new Proxy({}, { get: () => 'rgba(22,18,26,0.62)' });

export function drawWeapon(ctx, weaponId, palette, pose) {
  const shape = SHAPES[weaponId];
  if (!shape || pose.hide) return;
  ctx.save();
  // The world transform already flips Y (setTransform(ppu,0,0,-ppu,...)), so negating here flipped
  // it a second time and every weapon in the game was drawn vertically mirrored. Measured against
  // each move's own hitbox on the swings where up and down are unambiguous, the blade averaged
  // 120 degrees away from the thing it was about to hit; without the negation, 36. The spike
  // (AirDown, hitbox below the feet) was drawn pointing overhead.
  ctx.rotate(pose.angle);
  ctx.translate(pose.ox, pose.oy);
  if (pose.scale && pose.scale !== 1) ctx.scale(pose.scale, pose.scale);   // Colossus doubles the blade

  // CONTOUR PASS. Every weapon is drawn twice: once flat in a dark value, offset a tenth of a stud
  // back and down, then properly on top. That is the whole trick — at gameplay zoom a weapon is
  // twenty to thirty pixels of mid-grey against a sky of mid-grey, and without a contour the sword
  // disappeared into the backdrop the moment it left the fighter's silhouette. An outline stroke
  // will not do it, because these shapes are five or six separate polygons with no common path;
  // re-running the shape in one colour gives a true silhouette for free.
  ctx.save();
  ctx.translate(-0.11, -0.11);
  shape(ctx, CONTOUR);
  ctx.restore();
  shape(ctx, palette);
  if (pose.charge > 0) {              // charging glows along the weapon
    ctx.globalAlpha = 0.25 + pose.charge * 0.5;
    ctx.fillStyle = palette.glow || '#FFFFFF';
    ctx.fillRect(0, -0.1, REACH[weaponId] || 2, 0.2);
    ctx.globalAlpha = 1;
  }
  ctx.restore();
}

// The swing smear, drawn behind the fighter's arm in world space around the shoulder.
export function drawTrail(ctx, weaponId, palette, trail, scale) {
  if (!trail) return;
  const r = (REACH[weaponId] || 2.4) * (scale || 1);
  const steps = 14;
  const a0 = trail.from, a1 = trail.to;
  for (let i = 0; i < steps; i++) {
    const u = i / (steps - 1);
    const a = a0 + (a1 - a0) * u;
    const w = (trail.heavy ? 0.42 : 0.26) * (0.35 + 0.65 * u);
    ctx.globalAlpha = trail.alpha * (0.10 + 0.75 * u * u);
    ctx.beginPath();
    ctx.arc(0, 0, r * (0.55 + 0.45 * u), a - w * 0.5, a + w * 0.5);
    ctx.lineWidth = (trail.heavy ? 0.9 : 0.55) * (0.4 + 0.6 * u);
    ctx.strokeStyle = u > 0.82 ? '#FFFFFF' : (palette.glow || palette.accent || '#FFFFFF');
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
}

// The parts of an ultimate that are not the weapon itself: afterimage blades, the reaper's moon,
// a second pistol, the rune stack. Drawn in the same local frame as drawWeapon.
export function drawUltimate(ctx, weaponId, palette, pose, t = 0) {
  const U = pose.ult;
  if (!U) return;
  const shape = SHAPES[weaponId];
  const glow = palette.glow || palette.accent || '#FFFFFF';
  const sc = pose.scale || 1;

  // ---- Sword: energy running the length of an oversized blade ----
  if (weaponId === 'Sword' && U.glow) {
    ctx.save();
    ctx.rotate(pose.angle);
    ctx.translate(pose.ox, pose.oy);
    const L = (REACH.Sword || 2.6) * sc;
    // The edge burns - along the EDGE, not across the whole blade. Filling the full width washed
    // an already-doubled sword into one white rectangle at 480x270.
    ctx.globalAlpha = 0.22 + U.glow * 0.38;
    ctx.fillStyle = glow;
    ctx.fillRect(0.2, -0.24 * sc, L, 0.14 * sc);
    ctx.fillRect(0.2, 0.10 * sc, L, 0.14 * sc);
    ctx.globalAlpha = 0.55 * U.glow;
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0.2, -0.05 * sc, L, 0.10 * sc);
    // sparks climbing the blade while it is held overhead
    if (U.rise !== undefined) {
      ctx.fillStyle = '#FFFFFF';
      for (let i = 0; i < 5; i++) {
        const u = ((t * 1.6 + i / 5) % 1);
        ctx.globalAlpha = (1 - u) * U.rise;
        ctx.fillRect(0.3 + u * L, -0.5 * sc + (i % 2) * sc, 0.22, 0.22);
      }
    }
    // the chop drags a wedge of light behind the edge
    if (U.chop !== undefined) {
      ctx.globalAlpha = 0.55;
      poly(ctx, [[0.2, 0], [L, -1.5 * sc], [L, 1.5 * sc]], glow);
    }
    ctx.globalAlpha = 1;
    ctx.restore();
  }

  // ---- Scythe: the ball of purple-black energy the victims are being crushed into ----
  // Drawn here in the hand's frame at the reach of the blade, so it tracks the arm exactly.
  if (U.pull !== undefined || U.crush !== undefined) {
    const closing = U.crush === undefined ? U.pull : 1;
    const burst = U.crush !== undefined ? U.crush : 0;
    ctx.save();
    ctx.rotate(pose.angle);
    ctx.translate((REACH.Scythe || 3.4) * 0.75, 0);
    const R = (1.0 + closing * 1.9) * (1 - burst * 0.55) + burst * 5.5;
    // black core with a violet corona: the corona is what reads at 480x270, the core is what
    // makes it look like something is being crushed rather than something glowing
    ctx.globalAlpha = 0.30 + closing * 0.25;
    ctx.fillStyle = '#B36BFF';
    ctx.beginPath(); ctx.arc(0, 0, R * 1.45, 0, PI * 2); ctx.fill();
    ctx.globalAlpha = 0.95 - burst * 0.8;
    ctx.fillStyle = '#150B22';
    ctx.beginPath(); ctx.arc(0, 0, R, 0, PI * 2); ctx.fill();
    ctx.globalAlpha = 0.9;
    ctx.strokeStyle = '#C79BFF'; ctx.lineWidth = 0.14 + burst * 0.3;
    ctx.beginPath(); ctx.arc(0, 0, R * 1.12, 0, PI * 2); ctx.stroke();
    // matter spiralling in
    ctx.fillStyle = '#E4CCFF';
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * PI * 2 - t * 4.5;
      const rr = R * (2.6 - closing * 1.4) * (1 - burst);
      ctx.globalAlpha = (0.8 - burst) * (0.35 + 0.65 * closing);
      ctx.fillRect(Math.cos(a) * rr - 0.13, Math.sin(a) * rr - 0.13, 0.26, 0.26);
    }
    ctx.globalAlpha = 1;
    ctx.restore();
  }

  // ---- Blasters: the pistol extended into a rifle ----
  if (U.rifle) {
    const r = U.rifle;
    ctx.save();
    ctx.rotate(pose.angle);
    ctx.translate(pose.ox, pose.oy);
    // barrel extension
    poly(ctx, [[0.85, -0.17], [0.85 + 1.9 * r, -0.17], [0.85 + 1.9 * r, 0.02], [0.85, 0.02]], palette.secondary || '#6B7382');
    poly(ctx, [[0.72 + 1.9 * r, -0.26], [0.95 + 1.9 * r, -0.26], [0.95 + 1.9 * r, 0.08], [0.72 + 1.9 * r, 0.08]], palette.primary || '#9AA6B4');
    // scope, and its lens catching the light
    poly(ctx, [[0.05, -0.62], [0.95, -0.62], [0.95, -0.34], [0.05, -0.34]], palette.primary || '#9AA6B4');
    ctx.fillStyle = '#FF4A4A';
    ctx.globalAlpha = 0.55 + 0.45 * Math.sin(t * 9);
    ctx.beginPath(); ctx.arc(0.88, -0.48, 0.13, 0, PI * 2); ctx.fill();
    ctx.globalAlpha = 1;
    // bipod, so it reads as a rifle in silhouette
    poly(ctx, [[1.3, 0.02], [1.42, 0.02], [1.62, 0.62], [1.5, 0.62]], palette.tertiary || '#4A505C');
    poly(ctx, [[1.3, 0.02], [1.42, 0.02], [1.22, 0.62], [1.1, 0.62]], palette.tertiary || '#4A505C');
    ctx.restore();
    // rounds left, as pips above the shoulder
    if (U.aiming) {
      ctx.save();
      for (let i = 0; i < 3; i++) {
        ctx.globalAlpha = i < U.rounds ? 0.95 : 0.22;
        ctx.fillStyle = i < U.rounds ? '#FF6B4A' : '#FFFFFF';
        ctx.fillRect(-0.9 + i * 0.42, -2.6, 0.3, 0.55);
      }
      ctx.globalAlpha = 1;
      ctx.restore();
    }
  }

  // ---- Axe: the haul, and the blur of three revolutions ----
  // These branches were missing entirely. `ultimatePose` authored ult.haul, ult.reave, ult.blur,
  // ult.extend and ult.lance and NOTHING read any of them — the two newest ultimates were the only
  // ones in the game with no bespoke art, which is the same dead-channel defect that had already
  // been found twice on this project.
  if (U.haul !== undefined) {
    // strain: the fighter is winning against the weight, barely. Lines pull back along the haft.
    ctx.save();
    ctx.rotate(pose.angle);
    ctx.globalAlpha = 0.35 + U.haul * 0.45;
    ctx.strokeStyle = glow; ctx.lineWidth = 0.1;
    for (let i = 0; i < 4; i++) {
      const o2 = -0.5 - i * 0.42;
      ctx.beginPath();
      ctx.moveTo(o2, -0.5 + i * 0.28); ctx.lineTo(o2 - 0.7 - U.haul * 1.1, -0.5 + i * 0.28);
      ctx.stroke();
    }
    ctx.restore();
  }
  if (U.reave !== undefined && shape) {
    // Concentric rings tracking the head, brightening as the revolutions accelerate, plus two
    // afterimage heads so the eye can follow a shape that is turning faster than 60Hz can show.
    const r = (REACH.Axe || 3.2) * sc;
    for (let i = 0; i < 3; i++) {
      ctx.globalAlpha = (0.10 + U.reave * 0.22) * (1 - i * 0.26);
      ctx.strokeStyle = i === 0 ? '#FFFFFF' : glow;
      ctx.lineWidth = 0.5 - i * 0.12;
      ctx.beginPath(); ctx.arc(0, 0, r * (0.72 + i * 0.16), 0, TAU); ctx.stroke();
    }
    // grit torn off the floor by the circle
    ctx.globalAlpha = 0.5 * U.reave;
    ctx.fillStyle = '#6B5A44';
    for (let i = 0; i < 10; i++) {
      const a = (i / 10) * TAU + U.reave * 14;
      ctx.fillRect(Math.cos(a) * r * 1.05 - 0.16, Math.sin(a) * r * 1.05 - 0.16, 0.32, 0.32);
    }
    ctx.globalAlpha = 1;
  }
  if (U.blur && shape) {
    for (let i = 0; i < U.blur.length; i++) {
      ctx.save();
      ctx.globalAlpha = 0.30 - i * 0.10;
      ctx.rotate(U.blur[i]);
      if (sc !== 1) ctx.scale(sc, sc);
      shape(ctx, palette);
      ctx.restore();
    }
    ctx.globalAlpha = 1;
  }

  // ---- Pike: the lance, and the line it owns ----
  if (U.extend !== undefined || U.lance) {
    const k = U.lance ? 1 : U.extend;
    const reach = (REACH.Pike || 5.9) * (pose.scale || 1);
    ctx.save();
    ctx.rotate(pose.angle);
    ctx.translate(pose.ox, pose.oy);
    // The telescoping segment: drawn separately and stretched ONLY along the haft, because the
    // uniform ctx.scale that used to carry this also made the shaft 1.9x thick and threw the
    // counterweight three studs out behind the fighter.
    ctx.globalAlpha = 0.9;
    ctx.fillStyle = palette.secondary || '#6E7C8A';
    ctx.fillRect(1.2, -0.07, reach * 0.72 * k, 0.14);
    ctx.globalAlpha = 0.55 + 0.45 * (U.lance ? U.lance.punch : k);
    ctx.fillStyle = glow;
    ctx.fillRect(1.2, -0.03, reach * 0.72 * k, 0.06);
    if (U.lance) {
      // the lane: a bright line down the length the hitbox actually reaches, so the threatened
      // space is visible rather than implied
      const lane = 1.2 + reach * 0.72 + U.lance.reach * 14;
      ctx.globalAlpha = 0.16 + U.lance.punch * 0.34;
      ctx.fillStyle = glow;
      ctx.fillRect(1.2, -0.5, lane, 1.0);
      ctx.globalAlpha = 0.7 * U.lance.punch;
      ctx.fillStyle = '#FFFFFF';
      ctx.fillRect(lane - 1.6, -0.16, 1.6, 0.32);           // the point, where it currently is
      for (let i = 0; i < 5; i++) {                         // afterimage points behind it
        ctx.globalAlpha = (0.5 - i * 0.09) * U.lance.punch;
        ctx.fillRect(lane - 3.0 - i * 2.1, -0.1, 1.1, 0.2);
      }
    }
    ctx.globalAlpha = 1;
    ctx.restore();
  }

  // ---- Grimoire: three rune rings, three speeds ----
  if (U.runes !== undefined) {
    ctx.save();
    ctx.rotate(pose.angle);
    ctx.translate(1.1, 0);
    for (let i = 0; i < 3; i++) {
      const r = 1.5 + i * 1.25;
      const spin = t * (1.4 - i * 0.45) * (i % 2 ? -1 : 1);
      ctx.globalAlpha = 0.75 - i * 0.16;
      ctx.strokeStyle = glow; ctx.lineWidth = 0.14;
      ctx.beginPath(); ctx.arc(0, 0, r, 0, PI * 2); ctx.stroke();
      const n = 4 + i * 2;
      ctx.fillStyle = i === 0 ? '#FFFFFF' : glow;
      for (let s2 = 0; s2 < n; s2++) {
        const a = (s2 / n) * PI * 2 + spin;
        ctx.fillRect(Math.cos(a) * r - 0.11, Math.sin(a) * r - 0.11, 0.22, 0.22);
      }
    }
    ctx.globalAlpha = 1;
    ctx.restore();
  }
}

// The muzzle flash (blasters) and cast burst (grimoire), drawn at the business end of the weapon.
// Lives here rather than in the renderer so the animation sheet shows exactly what the match does.
export function drawMuzzle(ctx, weaponId, palette, pose, t = 0) {
  if (!pose.flash) return;
  const k = pose.flash;
  const reach = REACH[weaponId] || 1;
  ctx.save();
  ctx.rotate(pose.angle);
  ctx.translate(reach + pose.ox, pose.oy);
  ctx.globalAlpha = k;
  if (weaponId === 'Grimoire') {
    const R = 1.5 * k;
    ctx.strokeStyle = palette.glow || '#7DE8FF';
    ctx.lineWidth = 0.13;
    ctx.beginPath(); ctx.arc(0, 0, R * 1.25, 0, PI * 2); ctx.stroke();
    ctx.beginPath(); ctx.arc(0, 0, R * 0.68, 0, PI * 2); ctx.stroke();
    ctx.fillStyle = palette.glow || '#7DE8FF';
    for (let i = 0; i < 6; i++) {
      const a = (i / 6) * PI * 2 + t * 3;
      ctx.fillRect(Math.cos(a) * R * 1.25 - 0.09, Math.sin(a) * R * 1.25 - 0.09, 0.18, 0.18);
    }
    ctx.fillStyle = '#FFFFFF';
    ctx.beginPath(); ctx.arc(0, 0, R * 0.3, 0, PI * 2); ctx.fill();
  } else {
    const R = 1.0 * k;
    ctx.fillStyle = '#FFF3D0';
    for (let i = 0; i < 5; i++) {
      const a = (i / 5) * PI * 2 + 0.35;
      const l = R * (i % 2 ? 0.7 : 1.5);
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.lineTo(Math.cos(a) * l, Math.sin(a) * l);
      ctx.lineTo(Math.cos(a + 0.5) * l * 0.35, Math.sin(a + 0.5) * l * 0.35);
      ctx.closePath(); ctx.fill();
    }
    ctx.fillStyle = palette.glow || '#FFC44D';
    ctx.beginPath(); ctx.arc(0, 0, R * 0.5, 0, PI * 2); ctx.fill();
    ctx.fillStyle = '#FFFFFF';
    ctx.beginPath(); ctx.arc(0, 0, R * 0.24, 0, PI * 2); ctx.fill();
  }
  ctx.globalAlpha = 1;
  ctx.restore();
}
