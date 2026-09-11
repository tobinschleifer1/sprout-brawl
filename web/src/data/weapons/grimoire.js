// GRIMOIRE - magic. The slowest, heaviest, floatiest loadout, and the only weapon that leaves
// things on the stage after the move ends: a trap that arms and a beam that has to be charged.
//
// Its mechanic (`Light`) fills only while standing perfectly still on the ground, and any hit taken
// strips a segment. Three segments take 165 frames and cut Starfall's 26-frame windup to 5. It is
// the one weapon rewarded for holding ground rather than pressing buttons.
//
// Every cash-out goes to Runebrand. Glyph Trap arms for 20 frames before it can trigger, so a mine
// can never be a combo ender no matter what the frame data says, and Starfall is a charged beam.
// Both are neutral-game tools you press directly.
//
// Combo language:
//   Light,Light,Light          Spark, Spark, Nova              short range, keeps you safe
//   Light,Light+Up / Up+Light  Updraft                         launcher into an up-air
//   Light+Side,Light+Side      Hex Bolt, Backlash              the only ranged light, into a punish
//   Down+Light                 Ward                            trips under 60%
//
// Signature cash-outs, measured against a dodging victim (CONFIRM = unescapable, trap = a read):
//   Nova     +Heavy        -> Runebrand       CONFIRM  40-180%   trap   0-20%    kills 120%
//   Updraft  +Heavy        -> Runebrand       CONFIRM  80-180%   trap   0-60%    kills 120%
//   Backlash +Heavy        -> Runebrand       CONFIRM 160-180%   trap  0-140%    kills 120%

export default {
  id: 'Grimoire', name: 'Grimoire', archetype: 'Heavy zoner', tagline: 'Own the ground you stand on',
  blurb: 'Slow, heavy and floaty. Controls space with summons and a chargeable beam, and hits hard enough that one read ends a stock.',
  difficulty: 3,
  stats: { set: { weight: 108 }, mul: { runSpeed: 0.92, airSpeed: 0.94, fallSpeed: 0.88, jumpVelocity: 1.02 } },
  palette: { primary: '#2B2350', secondary: '#6E5FC0', tertiary: '#171233', accent: '#EFE6FF', glow: '#7DE8FF' },
  trail: '#9FD9FF',
  mechanic: { id: 'Light', segments: 3, fillFrames: 55, windupPerSegment: 7 },
  recovery: { kind: 'puff', vy: 64, vx: 13 },        // highest and narrowest: it goes up, not across
  signature: 'SigNeutral',

  moves: {
    LightNeutral1: { label: 'Spark', startup: 6, active: 2, recovery: 10, damage: 3, base: 10, growth: 0.8, angle: 45, grounded: true,
      chains: { neutral: 'LightNeutral2', side: 'LightSide1', up: 'LightUp', down: 'LightDown' },
      hitboxes: [{ frames: [7, 8], offset: [2.2, 2.8], size: [2.8, 2.4] }] },
    LightNeutral2: { label: 'Spark', startup: 5, active: 2, recovery: 11, damage: 3, base: 11, growth: 0.9, angle: 45, grounded: true,
      chains: { neutral: 'LightNeutral3', up: 'LightUp', down: 'LightDown' },
      hitboxes: [{ frames: [6, 7], offset: [2.4, 2.8], size: [2.8, 2.4] }] },
    LightNeutral3: { label: 'Nova', startup: 8, active: 3, recovery: 18, damage: 6, base: 17, growth: 1.7, angle: 55, grounded: true, extraHitstun: 7,
      chainsHeavy: 'SigSide',
      hitboxes: [{ frames: [9, 11], offset: [1.6, 2.8], size: [4.6, 4.0] }] },

    LightSide1: { label: 'Hex Bolt', startup: 9, active: 2, recovery: 14, damage: 4, base: 12, growth: 1.0, angle: 35, grounded: true, kind: 'projectile',
      chains: { side: 'LightSide2', neutral: 'LightSide2' },
      projectile: { speed: 44, lifetime: 34, size: [1.2, 1.2], spawnOffset: [2.4, 3.0], shape: 'orb' } },
    LightSide2: { label: 'Backlash', startup: 7, active: 3, recovery: 19, damage: 6, base: 18, growth: 2.1, angle: 40, grounded: true, extraHitstun: 6,
      chainsHeavy: 'SigSide',
      hitboxes: [{ frames: [8, 10], offset: [2.8, 2.7], size: [3.6, 2.6] }] },

    LightUp: { label: 'Updraft', startup: 8, active: 3, recovery: 15, damage: 5, base: 15, growth: 1.7, angle: 84, grounded: true, extraHitstun: 4,
      chainsHeavy: 'SigSide',
      hitboxes: [{ frames: [9, 11], offset: [1.2, 4.2], size: [3.2, 4.6] }] },
    LightDown: { label: 'Ward', startup: 9, active: 4, recovery: 17, damage: 5, base: 13, growth: 1.4, angle: 22, grounded: true, trip: 60, extraHitstun: 8,
      hitboxes: [{ frames: [10, 13], offset: [2.6, 0.9], size: [4.6, 1.6] }] },

    AirNeutral: { label: 'Aura', startup: 9, active: 14, recovery: 15, landingLag: 9, damage: 7, base: 16, growth: 2.0, angle: 50, grounded: false, applies: { slow: 40 },
      hitboxes: [{ frames: [10, 23], offset: [0, 2.6], size: [5.6, 5.4], rehitEvery: 7 }] },
    AirUp: { label: 'Levitate', startup: 10, active: 5, recovery: 16, landingLag: 10, damage: 7, base: 18, growth: 2.5, angle: 85, grounded: false, applies: { slow: 20 },
      hitboxes: [{ frames: [11, 15], offset: [0.2, 5.2], size: [4.0, 4.6] }] },
    AirForward: { label: 'Cast Forward', startup: 11, active: 4, recovery: 16, landingLag: 11, damage: 8, base: 20, growth: 2.4, angle: 35, grounded: false, kind: 'projectile',
      projectile: { speed: 52, lifetime: 26, size: [1.2, 1.2], spawnOffset: [2.2, 2.8], shape: 'orb' } },
    AirDown: { label: 'Gravity Well', startup: 14, active: 5, recovery: 20, landingLag: 14, damage: 10, base: 20, growth: 2.6, angle: 70, grounded: false, applies: { slow: 30 },
      hitboxes: [
        { frames: [15, 16], offset: [0.5, -0.7], size: [2.2, 2.6], angle: 275 },   // the well still spikes at its core
        { frames: [15, 19], offset: [0.5, 0.6], size: [4.2, 4.2] },                // and drags everything else down slowly
      ] },

    SigSide: { label: 'Runebrand', startup: 15, active: 4, recovery: 36, damage: 15, base: 32, growth: 4.4, angle: 40, grounded: true, heavy: true, kind: 'projectile',
      projectile: { speed: 72, lifetime: 34, size: [2.8, 3.6], spawnOffset: [2.4, 2.4], shape: 'orb' } },   // body-height bolt, so it catches a victim launched at any light's angle   // tall enough to catch a victim launched at any of the light angles
    SigDown: { label: 'Glyph Trap', startup: 20, active: 0, recovery: 30, damage: 6, base: 10, growth: 0, angle: 78, grounded: true, heavy: true, kind: 'summon',
      summon: { type: 'mine', offset: [3.2, 0], hp: 2, lifetime: 480, trigger: 3.0, radius: 4.5, max: 2,
        blast: { damage: 13, base: 33, growth: 5.3, angle: 72 } } },
    SigNeutral: { label: 'Starfall', startup: 26, active: 6, recovery: 34, damage: 13, base: 30, growth: 4.6, angle: 80, grounded: true, heavy: true, kind: 'beam',
      charge: { maxHold: 90, damage: 17, base: 31, growth: 4.8 },
      hitboxes: [{ frames: [27, 32], offset: [0, 7.0], size: [5.0, 14.0] }] },

    // ULTIMATE - Astral Rain. The book goes overhead and the sky answers: two energy orbs per living
    // opponent, spawned high above wherever each of them happens to be and steering down onto
    // them. It is the only move in the game that threatens the whole stage at once - in a
    // four-player match that is eight orbs and nowhere to stand. 1.25x knockback on impact.
    Ultimate: { label: 'Astral Rain', startup: 22, active: 56, recovery: 32, damage: 13, base: 31, growth: 4.2, angle: 76,
      heavy: true, kind: 'starfall', ultimate: true, knockbackMul: 1.25, shieldDamageMul: 3.0,
      hitboxes: [],
      // height 20 rather than 30: at 4-6 pixels per stud an orb spawned 30 studs up starts above
      // a 270-pixel backbuffer, so the first thing a player learned about their orb was the hit.
      // turn 1.4 rather than 3.2 so sprinting actually leaves the impact circle, and 26 frames
      // between waves so one air dodge can cover one wave. The second wave is unblockable - see
      // the starfall branch in combat.js: the first wave is the shield check, the second is the
      // punish for still being in it.
      starfall: { perTarget: 2, every: 26, height: 20, speed: 30, turn: 1.4, jitter: 3.0, size: 1.5,
        radius: 3.2, damage: 13, base: 31, growth: 4.2, angle: 76, knockbackMul: 1.25, shieldDamageMul: 3.0 },
    },
  },
};
