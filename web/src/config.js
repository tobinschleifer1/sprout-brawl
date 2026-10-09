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

// WEAPON DROPS. A fighter carries TWO weapons and spawns holding neither, fighting with the fists
// kit (data/weapons/fists.js). Drops fall onto the stage; the pickup button over one arms you with
// whichever of your two you did not hold last, and the same button, armed, throws the weapon you
// hold - which lands as a drop anyone can take. Off unless the match asks (cfg.weaponDrops), so a
// match without it is the game exactly as it was.
//
//   firstAt / spawnEvery   seconds to the first drop, and between drops
//   maxOnStage             drops lying about at once, by fighters in the match: min(4, 1 + n/2)
//   despawnAfter           seconds a drop lies on the ground before it fades
//   reach                  how close (x, y studs from the fighter's feet) a drop has to be
//   throwMove              the throw's own frames: the weapon leaves on its first active frame
//   thrown                 the thrown weapon, for any weapon without its own (phase 2 gives each
//                          weapon its own): an arcing projectile that lands as a drop
export const DROPS = {
  firstAt: 2, spawnEvery: 5, despawnAfter: 14, reach: [3, 3.5],
  throwMove: { startup: 4, active: 1, recovery: 12 },
  thrown: { speed: 46, vy: 6, gravity: 40, lifetime: 50, damage: 7, base: 15, growth: 1.4, angle: 42, size: [2.4, 1.2] },
};
export const dropsOnStage = (fighters) => Math.min(4, 1 + Math.floor(fighters / 2));
export const SUDDEN_DEATH = { percent: 300, shrinkEvery: 10, shrinkFactor: 0.8 };
export const INPUT_BUFFER = 6;

// Combos that reward timing. docs/briefs/combo-system-plan.md has the design; fighter.js and
// combat.js implement it.
//
// A follow-up is PERFECT when its button went down during the previous move's strike - from its
// first active frame to `perfectLate` frames after its last - and no press of that button came in
// during the wind-up. Measured on the attacker's own move, which the client draws from prediction
// with no lag, so the window is the same at any ping. A press in the wind-up still chains: it is
// an ordinary link, which is what mashing gets.
//
// Damage scales down through a long combo from the `scaleFrom`th hit; knockback does not, so kill
// percents stay where the balance tables put them. From the `breakFrom`th hit the victim can break
// out with a Dodge pressed during that hit's freeze; an early or mashed Dodge locks the break out
// for the rest of the combo.
//
// The chase: a timed link into an aerial, or the first aerial within `chaseFrames` of a jump or
// dodge cancel off a landed hit, carries the attacker toward the fighter they just hit - aimed so
// the new move's hitbox meets where the victim will be when it comes out, at up to `chaseSpeed`.
// Every hit sends its victim away, so without it no aerial reaches the next one; mashed links do
// not chase, so they whiff, and the skill stays in the timing.
// The kill hit (readability): a hit whose launch, left alone, carries the victim past a blast line.
// The hit event says `kill`, so everyone on screen sees the KO coming before it lands. `drift` is how
// long after hitstun the launch is followed: the tumble a victim cannot yet act out of. A prediction,
// not a promise: DI and a recovery can still save them, which is the point of marking it.
// Measured over 24 bot matches: at 10, 83% of marked hits KO and half the side and top KOs are
// marked; at 30 it marked more but only 55% KO'd, every miss a victim who used their recovery. A
// bottom KO is a failed recovery seconds later, not a kill hit, and is never marked.
// It marks the hit and changes nothing else. A longer freeze on kill hits was tried and measured: it
// halved the top bot's edge over the one below (4.0x to 2.0x across 64 games), so it was changing
// fights, not just showing them.
export const KILL_HIT = { drift: 10 };

// Staling (depth): a move you keep landing does less. Each fighter remembers the last `memory`
// moves they landed; each time this move is among them costs `step` of its damage, down to `floor`
// - so eight of the same in a row land at 60%. Knockback grows with damage, so the launch falls
// with it. Mild on purpose: variety is rewarded and nothing becomes useless. Throws and the
// ultimate never stale, and a blocked or armoured hit is not a landed one.
// Bounces (depth): a launched fighter - in hitstun, or still tumbling - who meets a wall or a
// ceiling faster than `speed` rebounds at `restitution` of it, still launched: a combo off the
// wall, a ceiling that sends them back down. A tech on contact (shield, as for a floor) still
// saves them: off a wall as before, and now off a ceiling too.
export const BOUNCE = { speed: 30, restitution: 0.6 };

// Team play (combat phase 3). An assist: anyone besides the KO'er who hit the victim within
// `assistWindow` frames of the KO - in every mode - is credited and gets `assistMeter` ultimate
// charge (a landed hit is 1; the meter is ULTIMATE.hitsRequired).
export const TEAM = { assistWindow: 480, assistMeter: 3 };

export const STALE = { memory: 8, step: 0.05, floor: 0.6 };
export const staleMul = (landed, id) => {
  let n = 0;
  for (const m of landed) if (m === id) n++;
  return Math.max(STALE.floor, 1 - STALE.step * n);
};

export const COMBO = {
  perfectLate: 4, perfectStartupCut: 2, perfectMinStartup: 2, perfectDamage: 1, perfectCharge: 1.25,
  scaleFrom: 3, scaleStep: 0.08, scaleFloor: 0.5,
  breakFrom: 4, breakFrames: 16, breakInv: 20, breakPush: 30, breakCooldown: 360,
  chaseFrames: 24, chaseSpeed: 48,
};
// The share of a hit's damage that lands as the `hits`th hit of a combo.
export const comboScale = (hits) => (hits < COMBO.scaleFrom ? 1 : Math.max(COMBO.scaleFloor, 1 - COMBO.scaleStep * (hits - COMBO.scaleFrom + 1)));

// Ultimates. Charge by landing hits; spend the whole meter in one activation. The meter is wiped
// when you lose a stock, so an ultimate is a reward for a run of pressure, not a consolation prize
// for dying. Chip damage (node ticks, cloud ticks) does not count - only real connections do.
// invincibleFrames is 22, not 30, because the activation freeze does not tick timers: 30 would
// have covered Colossus's entire active window (its blade lands on move-frame 25), making the
// biggest commitment in the game untradeable. 22 runs out before the blade does.
export const ULTIMATE = { hitsRequired: 20, freezeFrames: 26, invincibleFrames: 22 };

export const WEIGHT_CLASS = (w) => (w <= 90 ? 'Light' : w <= 105 ? 'Mid' : 'Heavy');
