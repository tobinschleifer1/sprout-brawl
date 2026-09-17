// GAUNTLETS - the weapon with no weapon.
//
// From the brief: Rushdown, "never let them breathe". Weight 78, run 27.5, air 22.5, fall 32,
// three jumps, signature Overdrive - "activates after landing enough consecutive hits, attacks
// become faster for a short time".
//
// That last line is the mechanic, not a move, so Overdrive IS the mechanic here (`Surge`, shown in
// the HUD as OVERDRIVE) and the heavy the brief hangs off Body Blow is the move that SPENDS it.
// The brief lists "Momentum" on the stat line of five of the six new weapons, which cannot be
// right - Momentum is bought by running and these signatures describe four different things - so
// each weapon takes the mechanic its own signature describes. See docs at the end of this file.
//
// The shape of the weapon: the lightest, fastest thing in the game with the shortest reach in the
// game. Every hit is 2-4%, the whole moveset is inside two studs, and it dies at 78 weight - which
// is to say it has to be on top of you constantly or it is doing nothing at all.
//
// Signature cash-outs. Both columns are MEASURED in the engine against a victim who spot-dodges on
// their first actionable frame (web/test/combo.test.mjs); neither is derived from frame data, and
// combo.test.mjs parses this table and fails if any band here stops reproducing.
//   CONFIRM = lands while they are still in hitstun, so there is no escape.
//   trap    = lands on the recovery of the dodge they escaped with. A real option, but a read.
//
//   Body Blow +Heavy+side    -> Rush Elbow      CONFIRM 60-180%     trap 0-40%      kills 126%
//   Rising Fist +Heavy       -> Overdrive Blow  CONFIRM 80-180%     trap 0-60%      kills 125%
//   Rising Fist +Heavy+down  -> Meteor Fist     CONFIRM 180%        trap 40-160%    kills 233%
//   Low Kick +Heavy+down     -> Meteor Fist     trap only 0-40%                     kills 233%
//   Low Kick +Heavy          -> Meteor Fist     trap only 0-40%                     kills 233%

export default {
  id: 'Gauntlets', name: 'Gauntlets', archetype: 'Rushdown', tagline: 'Never let them breathe',
  blurb: 'The lightest, fastest fighter in the game and the shortest reach in it. Land four hits in a row and Overdrive makes everything faster still.',
  difficulty: 2,
  stats: { set: { weight: 78, jumps: 3 }, mul: { runSpeed: 1.196, airSpeed: 1.25, fallSpeed: 0.842, jumpVelocity: 1.02 } },
  palette: { primary: '#E8C07A', secondary: '#B4462E', tertiary: '#5A2018', accent: '#FFE9C4', glow: '#FF9A4A' },
  trail: '#FFC98A',
  // OVERDRIVE. Four connected hits inside a second and a half bank it; the next heavy spends it for
  // damage, and while it is banked every startup is two frames shorter. Whiffing does not reset it,
  // but being hit does - the counter is a reward for pressure, not for swinging.
  mechanic: { id: 'Surge', label: 'Overdrive', hitsRequired: 4, windowFrames: 90, durationFrames: 240, startupCut: 2, bonusDamage: 3, launchMul: 1.04 },
  recovery: { kind: 'hop', vy: 66, vx: 26 },
  signature: 'SigNeutral',

  moves: {
    // ---- light string ----
    LightNeutral1: { label: 'Jab', startup: 3, active: 2, recovery: 6, damage: 2, base: 7, growth: 0.5, angle: 45, grounded: true,
      chains: { neutral: 'LightNeutral2', side: 'LightSide1', up: 'LightUp', down: 'LightDown' },
      hitboxes: [{ frames: [4, 5], offset: [1.7, 2.9], size: [2.0, 1.6] }] },
    LightNeutral2: { label: 'Cross', startup: 3, active: 2, recovery: 7, damage: 3, base: 8, growth: 0.6, angle: 45, grounded: true,
      chains: { neutral: 'LightNeutral3', side: 'LightSide1', up: 'LightUp', down: 'LightDown' },
      hitboxes: [{ frames: [4, 5], offset: [1.9, 2.9], size: [2.2, 1.6] }] },
    // The cash-out link. Everything the gauntlets do is aimed at reaching this move with the
    // Overdrive counter full.
    LightNeutral3: { label: 'Body Blow', startup: 5, active: 2, recovery: 12, damage: 4, base: 14, growth: 1.3, angle: 50, grounded: true, extraHitstun: 1,
      chainsHeavy: { side: 'SigSide' },
      hitboxes: [{ frames: [6, 7], offset: [2.0, 2.7], size: [2.6, 2.2] }] },

    LightSide1: { label: 'Hook', startup: 4, active: 2, recovery: 9, damage: 3, base: 9, growth: 0.7, angle: 38, grounded: true, lunge: 1.5,
      chains: { neutral: 'LightNeutral3', side: 'LightSide2', up: 'LightUp' },
      hitboxes: [{ frames: [5, 6], offset: [2.1, 2.8], size: [2.4, 1.8] }] },
    LightSide2: { label: 'Dash Punch', startup: 5, active: 3, recovery: 13, damage: 4, base: 15, growth: 1.5, angle: 36, grounded: true, lunge: 3.5, extraHitstun: 8,
      hitboxes: [{ frames: [6, 8], offset: [2.4, 2.7], size: [3.0, 1.9] }] },

    LightUp: { label: 'Rising Fist', startup: 5, active: 3, recovery: 13, damage: 4, base: 13, growth: 1.5, angle: 85, grounded: true,
      // the brief routes this into Meteor Fist, which is the spike
      chainsHeavy: { neutral: 'SigNeutral', down: 'SigDown' },
      hitboxes: [{ frames: [6, 8], offset: [1.3, 3.6], size: [2.4, 3.6] }] },
    LightDown: { label: 'Low Kick', startup: 6, active: 3, recovery: 13, damage: 3, base: 10, growth: 1.0, angle: 16, grounded: true, trip: 55,
      chainsHeavy: { down: 'SigDown', neutral: 'SigDown' },
      hitboxes: [{ frames: [7, 9], offset: [2.0, 0.8], size: [3.0, 1.5] }] },

    // ---- aerials ----
    AirNeutral: { label: 'Spin Kick', startup: 5, active: 5, recovery: 10, landingLag: 6, damage: 4, base: 12, growth: 1.2, angle: 48, grounded: false,
      hitboxes: [{ frames: [6, 10], offset: [0, 2.8], size: [4.0, 3.6] }] },
    AirForward: { label: 'Flying Knee', startup: 6, active: 3, recovery: 11, landingLag: 7, damage: 5, base: 15, growth: 1.7, angle: 42, grounded: false,
      hitboxes: [{ frames: [7, 9], offset: [2.0, 2.7], size: [2.6, 2.4] }] },
    AirUp: { label: 'Upper', startup: 5, active: 3, recovery: 10, landingLag: 6, damage: 4, base: 13, growth: 1.5, angle: 88, grounded: false,
      hitboxes: [{ frames: [6, 8], offset: [0.6, 4.2], size: [2.4, 3.4] }] },
    AirDown: { label: 'Stomp', startup: 7, active: 4, recovery: 13, landingLag: 9, damage: 6, base: 15, growth: 1.9, angle: 270, grounded: false,
      fastFallActive: true,
      hitboxes: [{ frames: [8, 11], offset: [0.6, -0.8], size: [2.2, 3.0] }] },

    // ---- signatures ----
    SigSide: { label: 'Rush Elbow', startup: 13, active: 4, recovery: 26, damage: 11, base: 34, growth: 5.6, angle: 38, grounded: true, heavy: true, lunge: 6,
      hitboxes: [{ frames: [14, 17], offset: [2.6, 2.7], size: [3.6, 2.6] }] },
    // Meteor Fist: the spike, and the reason the gauntlets want you in the air.
    SigDown: { label: 'Meteor Fist', startup: 15, active: 4, recovery: 30, damage: 12, base: 26, growth: 4.6, angle: 308, grounded: true, heavy: true,
      hitboxes: [{ frames: [16, 19], offset: [2.0, 1.4], size: [3.2, 3.4] }] },
    // The move Overdrive is for. Fast for a signature, because it has to be reachable off a
    // three-hit string that only holds them for eight frames.
    SigNeutral: { label: 'Overdrive Blow', startup: 12, active: 3, recovery: 28, damage: 12, base: 35, growth: 6.0, angle: 84, grounded: true, heavy: true,
      hitboxes: [{ frames: [13, 15], offset: [1.6, 3.6], size: [2.8, 4.6] }] },

    // ULTIMATE - Hundred Hands. Two seconds of a fighter who cannot be interrupted, throwing more
    // punches than the frame rate can honestly show, ending on the one that sends.
    Ultimate: { label: 'Hundred Hands', startup: 16, active: 46, recovery: 34, damage: 2, base: 5, growth: 0.15, angle: 60,
      grounded: true, heavy: true, kind: 'melee', ultimate: true, knockbackMul: 1.35, shieldDamageMul: 3.0, lunge: 4,
      hitboxes: [
        { frames: [17, 52], offset: [2.0, 2.8], size: [4.2, 3.4], shieldDamageMul: 1.4, rehitEvery: 3, damage: 2, base: 5, growth: 0.12, angle: 60 },
        // the last one: a single straight right through everything the flurry set up
        { frames: [53, 62], offset: [2.2, 2.8], size: [6.8, 4.4], rehitEvery: 10, damage: 11, base: 24, growth: 3.3, angle: 40 },
      ] },
  },
};
