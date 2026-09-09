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

const PI = Math.PI;
const D = (deg) => (deg * PI) / 180;

// How each move swings. `hold` weapons (blasters, grimoire) do not swing at all - they aim.
//   arc:   [windupAngle, contactAngle, endAngle]
//   trail: how much of the arc to smear behind the blade, in radians
const SWINGS = {
  jab:      { arc: [D(70), D(5), D(25)], trail: D(45), thrust: 0.35 },
  side:     { arc: [D(140), D(-25), D(-5)], trail: D(110) },
  down:     { arc: [D(35), D(-70), D(-50)], trail: D(80) },
  up:       { arc: [D(-50), D(105), D(80)], trail: D(100) },
  nair:     { arc: [D(0), D(720), D(720)], trail: D(150), spin: true },
  fair:     { arc: [D(130), D(-15), D(5)], trail: D(105) },
  dair:     { arc: [D(-60), D(-95), D(-90)], trail: D(50) },
  uair:     { arc: [D(-30), D(115), D(95)], trail: D(110) },
  sigside:  { arc: [D(175), D(-40), D(-15)], trail: D(150), heavy: true },
  sigdown:  { arc: [D(150), D(-85), D(-65)], trail: D(140), heavy: true },
  signeut:  { arc: [D(-40), D(130), D(110)], trail: D(140), heavy: true },
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
const AIMED = { Blasters: true, Grimoire: 'cast' };

const REST = { Sword: D(-78), Scythe: D(-72), Blasters: D(-60), Grimoire: D(-70) };

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
  const swing = SWINGS[cat] || SWINGS.jab;

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

  // A swing: windup across startup, contact across the active frames, settle across recovery.
  const total = st + act + rec;
  let from, to, k;
  if (mf <= st) { from = REST[wid] ?? 0; to = swing.arc[0]; k = st ? mf / st : 1; k = k * k; }
  else if (mf <= st + act) { from = swing.arc[0]; to = swing.arc[1]; k = act ? (mf - st) / act : 1; k = 1 - (1 - k) * (1 - k); }
  else { from = swing.arc[1]; to = swing.arc[2]; k = rec ? (mf - st - act) / rec : 1; }
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
    // planted in the floor while the crater runs outward
    out.scale = FULL;
    out.ult.glow = 1;
    const since = inActive ? ak : act + (mf - st - act);
    out.angle = D(-84) + Math.sin(since * 0.55) * 0.035;
    out.ult.planted = Math.min(1, since / 10);
    out.ult.shock = inActive ? ak / Math.max(1, act) : 1;
    if (!inActive) {                                    // recovery: shoulder it, and it shrinks
      out.angle = D(-84) + ((REST[wid] ?? 0) - D(-84)) * recK;
      out.scale = FULL - (FULL - 1) * recK;
      out.ult.glow = 1 - recK;
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
  poly(ctx, [[-0.5, -0.16], [0.0, -0.16], [0.0, 0.16], [-0.5, 0.16]], p.tertiary);       // grip
  poly(ctx, [[-0.62, -0.22], [-0.44, -0.22], [-0.44, 0.22], [-0.62, 0.22]], p.secondary); // pommel
  poly(ctx, [[-0.06, -0.52], [0.14, -0.52], [0.14, 0.52], [-0.06, 0.52]], p.secondary);   // crossguard
  poly(ctx, [[0.14, -0.19], [L - 0.45, -0.19], [L, 0], [L - 0.45, 0.19], [0.14, 0.19]], p.primary);
  poly(ctx, [[0.14, -0.07], [L - 0.5, -0.07], [L - 0.4, 0], [L - 0.5, 0.07], [0.14, 0.07]], p.accent); // fuller
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
  poly(ctx, [[0.30, -0.20], [0.92, -0.20], [0.92, 0.02], [0.30, 0.02]], p.secondary);      // barrel
  poly(ctx, [[-0.30, 0.02], [0.02, 0.02], [0.14, 0.62], [-0.18, 0.62]], p.primary);        // grip
}

function grimoire(ctx, p) {
  poly(ctx, [[-0.55, -0.72], [0.62, -0.60], [0.62, 0.60], [-0.55, 0.72]], p.primary);      // cover
  poly(ctx, [[-0.55, -0.72], [0.62, -0.60], [0.62, -0.46], [-0.55, -0.58]], p.accent);     // lit edge
  poly(ctx, [[0.50, -0.58], [0.78, -0.54], [0.78, 0.54], [0.50, 0.58]], '#F0E7D2');         // pages
  poly(ctx, [[-0.66, -0.70], [-0.50, -0.70], [-0.50, 0.70], [-0.66, 0.70]], p.tertiary);   // spine
  ctx.beginPath(); ctx.arc(0.05, 0, 0.24, 0, PI * 2);
  ctx.fillStyle = p.glow || p.accent; ctx.fill();
}

const SHAPES = { Sword: (c, p) => sword(c, p, 2.35), Scythe: (c, p) => scythe(c, p, 2.9), Blasters: blaster, Grimoire: grimoire };

// Blade length per weapon, used to size the swing trail.
export const REACH = { Sword: 2.6, Scythe: 3.4, Blasters: 1.1, Grimoire: 0.9 };

export function drawWeapon(ctx, weaponId, palette, pose) {
  const shape = SHAPES[weaponId];
  if (!shape || pose.hide) return;
  ctx.save();
  ctx.rotate(-pose.angle);            // canvas y is down, world angles are y-up
  ctx.translate(pose.ox, pose.oy);
  if (pose.scale && pose.scale !== 1) ctx.scale(pose.scale, pose.scale);   // Colossus doubles the blade
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
    ctx.arc(0, 0, r * (0.55 + 0.45 * u), -a - w * 0.5, -a + w * 0.5);
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
    ctx.rotate(-pose.angle);
    ctx.translate(pose.ox, pose.oy);
    const L = (REACH.Sword || 2.6) * sc;
    // the edge itself burns
    ctx.globalAlpha = 0.30 + U.glow * 0.45;
    ctx.fillStyle = glow;
    ctx.fillRect(0.2, -0.30 * sc, L, 0.60 * sc);
    ctx.globalAlpha = 0.85 * U.glow;
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0.2, -0.10 * sc, L, 0.20 * sc);
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
    ctx.rotate(-pose.angle);
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
    ctx.rotate(-pose.angle);
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

  // ---- Grimoire: three rune rings, three speeds ----
  if (U.runes !== undefined) {
    ctx.save();
    ctx.rotate(-pose.angle);
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
  ctx.rotate(-pose.angle);
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
