import { HITSTUN_CAP, HITLAG_CAP, DI_MAX, KNOCKBACK, FRAME, GRAVITY, LAUNCH_DRAG, KILL_HIT } from '../config.js';

// launch = (base + growth × damage × (percent × slope + floor)) × (100 / weight)
// See KNOCKBACK in config.js for why the slope is 1/140 and not 1/100.
export function launchSpeed(base, growth, damage, percentAfterHit, weight) {
  const scaled = base + growth * damage * (percentAfterHit * KNOCKBACK.slope + KNOCKBACK.floor);
  return scaled * (100 / weight);
}

// How long the victim is stunned, as its own curve. Everything that launches must compute this
// alongside the launch and hand both to applyHit - see KNOCKBACK in config.js for why they are
// two numbers and not one.
export function stunSpeed(base, growth, damage, percentAfterHit, weight) {
  const scaled = base + growth * damage * (percentAfterHit * KNOCKBACK.stunSlope + KNOCKBACK.floor);
  return scaled * (100 / weight);
}

export function hitstun(launch) {
  return Math.min(6 + Math.floor(launch * 0.4), HITSTUN_CAP);
}

export function blockstun(damage) {
  return 4 + Math.floor(damage * 0.8);
}

export function hitlag(damage, heavy) {
  return Math.min(3 + Math.floor(damage * 0.35) + (heavy ? 2 : 0), HITLAG_CAP);
}

// Returns {vx, vy}. facing is +1/-1. di is the victim's stick {x, y} in -1..1 or null.
export function velocity(launch, angleDeg, facing, di) {
  let angle = angleDeg;
  if (di) {
    const rad = (angleDeg * Math.PI) / 180;
    // component of the stick perpendicular to the launch direction bends the angle
    const perpendicular = -di.x * facing * Math.sin(rad) + di.y * Math.cos(rad);
    angle += Math.max(-1, Math.min(1, perpendicular)) * DI_MAX;
  }
  const rad = (angle * Math.PI) / 180;
  return { vx: Math.cos(rad) * launch * facing, vy: Math.sin(rad) * launch };
}

// Whether a fighter at (x, y) moving at (vx, vy), in hitstun for `stun` frames, leaves through a side
// or the top of `blast` before they could act - the fighter's own airborne integration (gravity, the
// tumble's terminal speed, hitstun drag), with no DI and nothing in the way. The bottom is left out:
// a launch downward meets the floor first far more often than it falls past one.
export function carriesOut(x, y, vx, vy, stun, blast) {
  const frames = stun + KILL_HIT.drift;
  for (let i = 0; i < frames; i++) {
    vy -= GRAVITY * FRAME;
    if (vy < -80) vy = -80;
    if (i < stun) vx *= LAUNCH_DRAG;
    x += vx * FRAME; y += vy * FRAME;
    if (x < blast.left || x > blast.right || y > blast.top) return true;
  }
  return false;
}

// On-block advantage for a move hitting on its first active frame (for the frame data screen).
export function onBlock(move) {
  return blockstun(move.damage) - ((move.active - 1) + move.recovery);
}
