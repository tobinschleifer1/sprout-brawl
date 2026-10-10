// Global simulation constants. Frames are at 60 Hz. Distances in studs (1 stud ≈ 0.28 m).
export const FRAME = 1 / 60;
export const GRAVITY = 150;          // studs/s², combat gravity
export const LAUNCH_DRAG = 0.985;    // horizontal drag per frame while in hitstun/tumble
export const TUMBLE_THRESHOLD = 45;  // launch speed at which a hit causes tumble
export const HITSTUN_CAP = 60;
export const HITLAG_CAP = 12;
export const DI_MAX = 12;            // degrees of directional influence

// The launch curve: launch = (base + growth x damage x (percent x slope + floor)) x (100/weight).
//
// `slope` used to be 1/100 and players were dying far too cheaply - a signature killed from 97%
// and an ultimate from 68%, so a stock could end on one read at less than half the percent the
// damage numbers imply. Flattening it to 1/120 is the surgical version of "less knockback": at 0%
// the term is unchanged (the `floor` dominates), so nothing about early-percent play moves, and
// the reduction grows with percent, which is exactly where kills come from. At 100% a launch is
// 9% smaller, at 200% it is 14% smaller.
//
// `stunSlope` is the same curve at its ORIGINAL 1/100, and it exists because hitstun must not
// follow the launch down. It did, at first, and shortening hitstun at high percent silently
// deleted the guaranteed kill confirm of seven of the twelve weapons - combo.test.mjs caught it.
// How far a victim flies and how long they cannot act are separate design questions and the engine
// now treats them separately: less knockback, same combos.
export const KNOCKBACK = { slope: 1 / 120, stunSlope: 1 / 100, floor: 0.4 };

export const MOVE = {
  groundAccelFrames: 6,   // frames to reach run speed
  groundStopFrames: 6,
  airAccelFrames: 10,
  airDrag: 0.995,
  shortHopMul: 0.6,
  shortHopWindow: 4,
  fastFallMul: 1.6,
  jumpsquat: 3,
  turnFrames: 0,
};

export const SHIELD = { max: 50, regenPerSec: 8, drainPerSec: 1.5, damageMul: 1.2, breakStun: 90, resetHp: 25, perfectFrames: 4, dropFrames: 4 };

export const LEDGE = {
  maxGrabs: 3,
  invinc: [30, 15, 0],
  hangMax: 180,
  grabReach: 3.0,        // studs outside the ledge
  grabDepth: 6.0,        // studs below the ledge top
  hangOffsetX: 1.4,
  hangOffsetY: -3.2,
  options: {
    getup:  { frames: 24, inv: [1, 12], distance: 2.5 },
    roll:   { frames: 36, inv: [4, 20], distance: 8 },
    attack: { frames: 30, inv: [1, 8], distance: 2.5, damage: 7, base: 16, growth: 1.6, angle: 45, hitbox: { frames: [12, 16], offset: [2.6, 2.4], size: [4.5, 2.6] } },
  },
};

export const DASH = { frames: 18, speedMul: 1.6, cancelLightFrom: 6, cancelShieldFrom: 10 };
export const SPOT_DODGE = { frames: 24, inv: [3, 14] };
export const AIR_DODGE = { frames: 28, inv: [3, 13], distance: 6 };

export const GROUND_POUND = {
  hang: 8, speed: 70, landingLag: 22,
  dive: { damage: 10, base: 20, growth: 2.6, angle: 275, hitbox: { offset: [0, 0.6], size: [2.6, 3.2] } },
  shock: { damage: 5, base: 12, growth: 1.0, angle: 70, radius: 4, frames: 3 },
};

export const GRAB = {
  startup: 7, active: 3, whiffRecovery: 26, holdFrames: 14,
  hitbox: { offset: [2.2, 2.5], size: [3.4, 3.2] },
  throws: {
    forward: { damage: 7, base: 20, growth: 2.4, angle: 40 },
    back:    { damage: 7, base: 20, growth: 2.4, angle: 40, behind: true },
    up:      { damage: 6, base: 18, growth: 2.2, angle: 88 },
    down:    { damage: 8, base: 14, growth: 1.8, angle: 30 },
  },
};

export const TECH = { window: 8, inPlace: { frames: 30, inv: [1, 14] }, roll: { frames: 30, inv: [1, 14], distance: 8 } };
export const KNOCKDOWN = { frames: 26, getupInv: [1, 10] };
export const TAUNT_FRAMES = 90;
export const RESPAWN = { delay: 2.0, invinc: 120, height: 14 };
// spawnEvery was 25 seconds and despawnAfter 20, which in a three-minute match is about seven
// items, most of which timed out untouched. 14 seconds keeps one in play most of the time without
// the match becoming about the floor.
export const ITEMS = { spawnEvery: 14, despawnAfter: 22, knockOutDamage: 12 };
export const SUDDEN_DEATH = { percent: 300, shrinkEvery: 10, shrinkFactor: 0.8 };
export const INPUT_BUFFER = 6;

// Ultimates. Charge by landing hits; spend the whole meter in one activation. The meter is wiped
// when you lose a stock, so an ultimate is a reward for a run of pressure, not a consolation prize
// for dying. Chip damage (node ticks, cloud ticks) does not count - only real connections do.
// invincibleFrames is 22, not 30, because the activation freeze does not tick timers: 30 would
// have covered Colossus's entire active window (its blade lands on move-frame 25), making the
// biggest commitment in the game untradeable. 22 runs out before the blade does.
export const ULTIMATE = { hitsRequired: 20, freezeFrames: 26, invincibleFrames: 22 };

export const WEIGHT_CLASS = (w) => (w <= 90 ? 'Light' : w <= 105 ? 'Mid' : 'Heavy');
