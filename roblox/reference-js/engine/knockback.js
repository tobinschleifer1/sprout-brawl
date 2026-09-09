import { HITSTUN_CAP, HITLAG_CAP, DI_MAX } from '../config.js';

// launch = (base + growth × damage × (percent/100 + 0.4)) × (100 / weight)
export function launchSpeed(base, growth, damage, percentAfterHit, weight) {
  const scaled = base + growth * damage * (percentAfterHit / 100 + 0.4);
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

// On-block advantage for a move hitting on its first active frame (for the frame data screen).
export function onBlock(move) {
  return blockstun(move.damage) - ((move.active - 1) + move.recovery);
}
