// WARPIKE - the weapon that wins by never letting you close.
//
// Chosen as the counterweight to the axe. Where the axe is short, heavy and committed, the pike is
// the longest reach in the game on the thinnest hitboxes: a wall of point rather than a wall of
// edge. It THRUSTS instead of swinging, which is a different animation problem and a different
// gameplay one — its hitboxes are narrow and deep, so it beats an approach cleanly and loses
// completely to anyone who gets inside it.
//
// Nothing it owns is fast. What it owns is that its light pokes out-range every other weapon's
// signature, so the whole matchup is the other player trying to pay the toll to get in.
//
// BRACE is the mechanic, and it is deliberately the opposite of the axe's Momentum. Momentum is
// bought by running — by moving. Brace is bought by holding your ground: 45 frames of shield banks
// it, and the next signature spends it for a heavier, further thrust. One weapon is rewarded for
// committing forward, the other for refusing to move, and the two of them make each other legible.
//
// Reach on the pike is in the haft, so unlike the axe its hitboxes sit far from the body and its
// tip is what kills. Getting spaced correctly is the skill.
//
// Signature cash-outs. Both columns are MEASURED in the engine against a victim who spot-dodges on
// their first actionable frame (web/test/combo.test.mjs); neither is derived from frame data.
//   CONFIRM = lands while they are still in hitstun, so there is no escape.
//   trap    = lands on the recovery of the dodge they escaped with. A real option, but a read.
//
//   Lunge Point +Heavy+Down -> Pin        CONFIRM 160-180%   trap 120-140%   kills 135%
//   Poke        +Heavy      -> Pike Wall  trap only   0-180%                 kills 137%
//   Raise Point +Heavy      -> Pike Wall  trap only 100-180%                 kills 137%
//   Butt Spike  +Heavy      -> Pin        trap only   0-40%                  kills 135%
//   Lunge Point +Heavy      -> Pike Wall  trap only 160-180%                 kills 137%
//
// Full Extension appears nowhere in that table on purpose. It is the longest single hitbox in the
// game and it is thrown from outside everyone else's range, so it is a spacing tool rather than a
// combo ender — the pike's kill routes all go through Pin and Pike Wall instead.

export default {
  id: 'Pike', name: 'Warpike', archetype: 'Spacer',
  tagline: 'The toll for getting close',
  blurb: 'The longest reach in the game on the thinnest hitboxes. It thrusts rather than swings, beats every approach, and folds the moment someone is inside it.',
  difficulty: 3,
  stats: { set: { weight: 94 }, mul: { runSpeed: 0.97, airSpeed: 1.04, fallSpeed: 0.96 } },
  palette: { primary: '#C9B489', secondary: '#6E7C8A', tertiary: '#2B3038', accent: '#F0E6CC', glow: '#7FE0C8' },
  trail: '#BFF5E6',
  // 70 frames, not 45. Brace banks while holding shield; the axe's Momentum banks over 50 frames
  // of the slowest run in the game — 15.75 studs of uninterrupted travel while dragging a visible
  // telegraph — for +3 damage. Charging by standing still is the cheaper, safer and more repeatable
  // action, so it cannot also be the better-paying one.
  mechanic: { id: 'Brace', guardFrames: 70, bonusDamage: 3, launchMul: 1.04 },
  recovery: { kind: 'hop', vy: 60, vx: 22 },
  signature: 'SigSide',

  moves: {
    // ---- light string ----
    // The jab is the whole weapon in miniature: slow to come out, enormous reach, nothing behind it.
    LightNeutral1: { label: 'Poke', startup: 7, active: 2, recovery: 11, damage: 3, base: 9, growth: 0.7, angle: 40, grounded: true,
      chains: { neutral: 'LightNeutral2', side: 'LightSide1', up: 'LightUp', down: 'LightDown' },
      chainsHeavy: { neutral: 'SigNeutral' },
      hitboxes: [{ frames: [8, 9], offset: [4.4, 3.2], size: [5.2, 1.4] }] },
    LightNeutral2: { label: 'Second Point', startup: 6, active: 2, recovery: 12, damage: 4, base: 11, growth: 0.9, angle: 40, grounded: true,
      chains: { neutral: 'LightNeutral3', up: 'LightUp', down: 'LightDown' },
      chainsHeavy: { neutral: 'SigNeutral' },
      hitboxes: [{ frames: [7, 8], offset: [4.8, 3.2], size: [5.6, 1.4] }] },
    LightNeutral3: { label: 'Lunge Point', startup: 9, active: 3, recovery: 20, damage: 6, base: 17, growth: 1.9, angle: 44, grounded: true, lunge: 3,
      chainsHeavy: { neutral: 'SigNeutral', down: 'SigDown' },
      hitboxes: [{ frames: [10, 12], offset: [5.6, 3.2], size: [6.6, 1.6] }] },

    LightSide1: { label: 'Advance', startup: 9, active: 2, recovery: 13, damage: 4, base: 11, growth: 1.0, angle: 34, grounded: true, lunge: 3,
      chains: { side: 'LightSide2', neutral: 'LightNeutral2', up: 'LightUp' },
      // Full Extension never connects off anything — at 21 frames of startup on a move whose whole
      // job is to be thrown from outside everyone's range, that is correct, not a gap.
      hitboxes: [{ frames: [10, 11], offset: [5.0, 3.0], size: [6.0, 1.5] }] },
    LightSide2: { label: 'Drive', startup: 8, active: 3, recovery: 19, damage: 6, base: 16, growth: 1.8, angle: 36, grounded: true, lunge: 4,
      hitboxes: [{ frames: [9, 11], offset: [5.8, 3.0], size: [7.0, 1.6] }] },

    LightUp: { label: 'Raise Point', startup: 8, active: 3, recovery: 15, damage: 5, base: 15, growth: 1.7, angle: 84, grounded: true, extraHitstun: 5,
      chainsHeavy: { up: 'SigNeutral', neutral: 'SigNeutral' },
      hitboxes: [{ frames: [9, 11], offset: [1.4, 5.6], size: [1.8, 6.0] }] },
    LightDown: { label: 'Butt Spike', startup: 10, active: 3, recovery: 16, damage: 5, base: 12, growth: 1.3, angle: 16, grounded: true, trip: 60,
      chainsHeavy: { down: 'SigDown', neutral: 'SigDown' },
      hitboxes: [{ frames: [11, 13], offset: [3.6, 0.9], size: [5.0, 1.6] }] },

    // ---- aerials ----
    AirNeutral: { label: 'Spin Guard', startup: 8, active: 8, recovery: 14, landingLag: 9, damage: 6, base: 14, growth: 1.6, angle: 50, grounded: false,
      hitboxes: [{ frames: [9, 16], offset: [0, 3.2], size: [7.4, 5.0] }] },
    // The reason to be in the air at all: a horizontal spear the length of half a platform.
    AirForward: { label: 'Skewer', startup: 11, active: 3, recovery: 16, landingLag: 11, damage: 8, base: 19, growth: 2.3, angle: 34, grounded: false,
      hitboxes: [{ frames: [12, 14], offset: [6.0, 3.0], size: [7.6, 1.6] }] },
    AirUp: { label: 'Sky Point', startup: 9, active: 3, recovery: 15, landingLag: 9, damage: 7, base: 17, growth: 2.2, angle: 86, grounded: false,
      hitboxes: [{ frames: [10, 12], offset: [0.8, 6.0], size: [1.8, 6.4] }] },
    AirDown: { label: 'Stake', startup: 12, active: 4, recovery: 18, landingLag: 13, damage: 9, base: 20, growth: 2.6, angle: 270, grounded: false,
      fastFallActive: true,
      hitboxes: [{ frames: [13, 16], offset: [1.0, -1.4], size: [1.8, 5.4] }] },

    // ---- signatures ----
    SigSide: { label: 'Full Extension', startup: 21, active: 4, recovery: 33, damage: 14, base: 31, growth: 4.3, angle: 36, grounded: true, heavy: true, lunge: 6,
      hitboxes: [{ frames: [22, 25], offset: [7.4, 3.0], size: [10.0, 2.0] }] },
    SigDown: { label: 'Pin', startup: 19, active: 4, recovery: 30, damage: 13, base: 28, growth: 4.0, angle: 24, grounded: true, heavy: true, trip: 90,
      hitboxes: [{ frames: [20, 23], offset: [5.4, 1.2], size: [8.0, 2.2] }] },
    SigNeutral: { label: 'Pike Wall', startup: 23, active: 5, recovery: 31, damage: 13, base: 33, growth: 5.2, angle: 88, grounded: true, heavy: true,
      hitboxes: [{ frames: [24, 28], offset: [2.2, 5.4], size: [3.0, 9.0] }] },

    // ULTIMATE - Lance Charge. The pike, for four seconds, as the weapon it is trying to be.
    //
    // The haft telescopes into a full cavalry lance and the fighter delivers nine thrusts down a
    // single line, each one landing further out than the last, until the final thrust covers most
    // of a platform. It is the most linear ultimate in the game on purpose: Reave is a circle that
    // holds you, this is a line that you were either standing in or you were not.
    //
    // The reach ramp is the whole move. Early thrusts are a poke; by the seventh nobody on that
    // lane is safe, which gives the opponent a real and legible decision — leave the lane, or
    // commit to closing before it gets long.
    Ultimate: { label: 'Lance Charge', startup: 20, active: 58, recovery: 34, damage: 6, base: 12, growth: 0.5, angle: 38,
      heavy: true, kind: 'melee', ultimate: true, knockbackMul: 1.3, shieldDamageMul: 3.0, weaponScale: 1.9,
      // Five thrusts, and the drawing reaches every one of them.
      //
      // The first version's hitboxes ran out to 42 studs while the drawn lance reached 13.4 — a
      // 3.1x overhang, 28.6 studs of hitbox nobody could see. It also ran three unsynchronised
      // cadences (nine drawn thrusts, five reach steps, a rehit every five frames), so damage
      // landed up to four frames away from any visible thrust. Now there are five of everything:
      // five boxes, five drawn thrusts, and each box rehits once per its own step so a tick always
      // lands on a punch.
      hitboxes: [
        { frames: [21, 27], offset: [5.0, 3.1], size: [7.0, 1.8], shieldDamageMul: 1.5, rehitEvery: 6, damage: 4, base: 10, growth: 0.4 },
        { frames: [28, 35], offset: [6.6, 3.1], size: [9.0, 1.9], shieldDamageMul: 1.5, rehitEvery: 8, damage: 4, base: 11, growth: 0.5 },
        { frames: [36, 45], offset: [8.4, 3.1], size: [11.0, 2.0], shieldDamageMul: 1.5, rehitEvery: 10, damage: 5, base: 12, growth: 0.6 },
        { frames: [46, 57], offset: [10.2, 3.1], size: [13.0, 2.2], shieldDamageMul: 1.5, rehitEvery: 12, damage: 5, base: 13, growth: 0.7 },
        // the last thrust: the full length of the lance, and the one that actually sends
        { frames: [58, 78], offset: [12.0, 3.1], size: [16.0, 2.6], rehitEvery: 20,
          // Same reasoning as Reave: the ramp has already banked the damage, so the last thrust
          // has to kill late. At base 32 it KO'd from 45%.
          damage: 13, base: 26, growth: 3.5, angle: 30 },
      ] },
  },
};
