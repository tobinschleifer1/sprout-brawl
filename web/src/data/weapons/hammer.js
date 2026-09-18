// WAR HAMMER - the heaviest thing anyone has swung in this game.
//
// From the brief: Superheavy, "armour breaker". Weight 125, run 17.2, air 14.0, fall 47.0, two
// jumps, Momentum, signature Earthshatter - "a slow attack that creates a ground shockwave".
//
// Momentum is the right mechanic for this one and the brief asks for it, so it keeps the axe's:
// running banks it, a signature spends it. The hammer's version pays more than the axe's, because
// 17.2 run speed is fifteen seconds of jogging to bank it.
//
// "Armour breaker" is the thing that makes it not-just-a-bigger-axe: every heavy on this weapon
// carries a shield multiplier between 2.2 and 3.4, so a shield is not an answer to it the way a
// shield answers everything else. Against a fighter who blocks on reaction, the hammer is the
// weapon that punishes the habit rather than the timing.
//
// Signature cash-outs are MEASURED in the engine (web/test/combo.test.mjs), not derived from the
// frame data.

// Signature cash-outs. Both columns are MEASURED in the engine against a victim who spot-dodges on
// their first actionable frame (web/test/combo.test.mjs); neither is derived from frame data, and
// combo.test.mjs parses this table and fails if any band here stops reproducing.
//   CONFIRM = lands while they are still in hitstun, so there is no escape.
//   trap    = lands on the recovery of the dodge they escaped with. A real option, but a read.
//
//   Wide Swing    +Heavy+Side -> Breach          CONFIRM  120-220%   trap        -   kills  200%
//   Overhead      +Heavy+Side -> Breach          CONFIRM    40-80%   trap    0-20%   kills  200%
//   Rising Hammer +Heavy      -> Crushing Blow   CONFIRM   60-260%   trap   20-40%   kills  189%
//   Back Swing    +Heavy+Side -> Breach          trap only  120-260%                 kills  200%
//   Ground Slam   +Heavy+Side -> Breach          trap only   80-120%                 kills  200%

export default {
  id: 'Hammer', name: 'War Hammer', archetype: 'Superheavy', tagline: 'Armour breaker',
  blurb: 'The heaviest, slowest weapon in the game. Every heavy chews through a shield, so blocking it is not the answer it is against everything else.',
  difficulty: 2,
  stats: { set: { weight: 125 }, mul: { runSpeed: 0.748, airSpeed: 0.778, fallSpeed: 1.237, jumpVelocity: 0.9 } },
  palette: { primary: '#8A94A6', secondary: '#4A4038', tertiary: '#2A2420', accent: '#D8DCE2', glow: '#FFB05A', hilt: '#7A5A3A' },
  trail: '#E0D2B4',
  mechanic: { id: 'Momentum', runFrames: 55, bonusDamage: 4, launchMul: 1.08 },
  recovery: { kind: 'hop', vy: 46, vx: 12 },       // the worst recovery in the game, by design
  signature: 'SigDown',

  moves: {
    // ---- light string ----
    LightNeutral1: { label: 'Hammer', startup: 9, active: 3, recovery: 14, damage: 6, base: 14, growth: 1.2, angle: 45, grounded: true, shieldDamageMul: 1.6,
      chains: { neutral: 'LightNeutral2', side: 'LightSide1', up: 'LightUp', down: 'LightDown' },
      hitboxes: [{ frames: [10, 12], offset: [2.6, 3.0], size: [4.0, 3.4] }] },
    LightNeutral2: { label: 'Back Swing', startup: 10, active: 3, recovery: 14, damage: 7, base: 16, growth: 1.4, angle: 45, grounded: true, shieldDamageMul: 1.6, extraHitstun: 14,
      chains: { neutral: 'LightNeutral3', up: 'LightUp', down: 'LightDown' },
      chainsHeavy: { side: 'SigSide' },
      hitboxes: [{ frames: [11, 13], offset: [2.8, 3.2], size: [4.2, 3.6] }] },
    LightNeutral3: { label: 'Overhead', startup: 13, active: 4, recovery: 20, damage: 10, base: 22, growth: 2.4, angle: 58, grounded: true, shieldDamageMul: 1.8, extraHitstun: 14,
      chainsHeavy: { side: 'SigSide' },
      hitboxes: [{ frames: [14, 17], offset: [2.6, 2.6], size: [4.8, 4.6] }] },

    LightSide1: { label: 'Shoulder Bash', startup: 11, active: 3, recovery: 15, damage: 7, base: 16, growth: 1.5, angle: 34, grounded: true, lunge: 3, shieldDamageMul: 2.0, extraHitstun: 14,
      chains: { side: 'LightSide2', neutral: 'LightNeutral2', up: 'LightUp' },
      hitboxes: [{ frames: [12, 14], offset: [2.8, 2.9], size: [3.8, 3.2] }] },
    LightSide2: { label: 'Wide Swing', startup: 10, active: 4, recovery: 24, damage: 10, base: 23, growth: 2.7, angle: 42, grounded: true, lunge: 3.5, shieldDamageMul: 1.8,
      chainsHeavy: { side: 'SigSide' },
      hitboxes: [{ frames: [11, 14], offset: [3.2, 2.9], size: [5.2, 3.8] }] },

    LightUp: { label: 'Rising Hammer', startup: 11, active: 3, recovery: 18, damage: 8, base: 19, growth: 2.0, angle: 86, grounded: true, extraHitstun: 6, shieldDamageMul: 1.6,
      chainsHeavy: { neutral: 'SigNeutral', up: 'SigNeutral' },
      hitboxes: [{ frames: [12, 14], offset: [1.7, 4.6], size: [3.4, 5.0] }] },
    LightDown: { label: 'Ground Slam', startup: 12, active: 4, recovery: 20, damage: 7, base: 15, growth: 1.6, angle: 14, grounded: true, trip: 70, shieldDamageMul: 2.0,
      // No cash-out. The brief routes this into Earthshatter, and Earthshatter is 30 frames of
      // startup: measured, nothing on this weapon reaches it, so advertising the route would be
      // advertising a lie. Earthshatter is a standalone read.
      chainsHeavy: { side: 'SigSide' },
      hitboxes: [{ frames: [13, 16], offset: [3.0, 0.9], size: [5.2, 2.0] }] },

    // ---- aerials ----
    AirNeutral: { label: 'Turn Smash', startup: 11, active: 5, recovery: 17, landingLag: 13, damage: 9, base: 18, growth: 2.1, angle: 48, grounded: false,
      hitboxes: [{ frames: [12, 16], offset: [0, 3.0], size: [6.2, 5.2] }] },
    AirForward: { label: 'Falling Head', startup: 14, active: 4, recovery: 19, landingLag: 15, damage: 12, base: 23, growth: 2.9, angle: 38, grounded: false,
      hitboxes: [{ frames: [15, 18], offset: [3.0, 2.8], size: [4.4, 4.4] }] },
    AirUp: { label: 'Skyward Head', startup: 12, active: 4, recovery: 18, landingLag: 13, damage: 10, base: 20, growth: 2.6, angle: 88, grounded: false,
      hitboxes: [{ frames: [13, 16], offset: [0.8, 5.0], size: [3.8, 4.6] }] },
    AirDown: { label: 'Pile Driver', startup: 16, active: 6, recovery: 25, landingLag: 19, damage: 14, base: 25, growth: 3.3, angle: 268, grounded: false,
      fastFallActive: true,
      hitboxes: [{ frames: [17, 22], offset: [1.2, -0.9], size: [3.6, 4.6] }] },

    // ---- signatures ----
    SigSide: { label: 'Breach', startup: 22, active: 5, recovery: 34, damage: 17, base: 30, growth: 3.9, angle: 40, grounded: true, heavy: true, lunge: 4,
      shieldDamageMul: 3.4,                        // the armour breaker: this move eats a full shield
      hitboxes: [{ frames: [23, 27], offset: [3.4, 2.8], size: [6.4, 4.6] }] },
    // EARTHSHATTER. The brief's signature: slow, and what lands is not the head but the floor.
    // `kind: 'slam'` is the engine's crater path, the same one the sword's ultimate uses - the
    // shockwave walks outward along the ground in both directions from the impact.
    SigDown: { label: 'Earthshatter', startup: 30, active: 5, recovery: 40, damage: 18, base: 28, growth: 3.6, angle: 68, grounded: true, heavy: true, kind: 'slam',
      shieldDamageMul: 2.6,
      crater: { frame: 0, every: 5, count: 4, step: 4.6, radius: 2.6, damage: 11, minDamage: 8, base: 22, growth: 2.6, angle: 76, centreAngle: 70, knockbackMul: 1.0, shieldDamageMul: 2.6 },
      hitboxes: [{ frames: [31, 35], offset: [2.4, 2.2], size: [5.2, 5.8] }] },
    SigNeutral: { label: 'Crushing Blow', startup: 19, active: 4, recovery: 33, damage: 15, base: 32, growth: 4.6, angle: 86, grounded: true, heavy: true,
      shieldDamageMul: 2.2,
      hitboxes: [{ frames: [20, 23], offset: [1.8, 4.8], size: [4.2, 6.6] }] },

    // ULTIMATE - UPHEAVAL. The floor attacks, and it attacks where THEY are standing.
    //
    // Colossus cracks the ground outward from the sword. This raises a column under each opponent
    // in turn, five times, cycling through everyone who is on the ground. The difference is the
    // whole point: a crater is something you walk out of, a column is somewhere you already are.
    // Being airborne is the answer to it, which gives the heaviest weapon in the game a move that
    // makes light fighters jump - and jumping is where the hammer's aerials live.
    Ultimate: { label: 'Upheaval', startup: 30, active: 64, recovery: 40, damage: 14, base: 26, growth: 2.6, angle: 88,
      grounded: true, heavy: true, kind: 'upheaval', ultimate: true, knockbackMul: 1.3, shieldDamageMul: 4.0,
      hitboxes: [],
      // Each column pops rather than launches, so the next one can still reach them; the move's
      // kill comes from the sum, not from one hit.
      // `finalMul` is the fifth column, and it is what makes the move a kill at all: with five
      // equal columns Upheaval was the only ultimate that could not KO at any percent up to 400%.
      // 3.4 puts it at 145%, and it is a vertical kill - the hammer sends them through the roof.
      upheaval: { every: 13, count: 5, width: 5.0, height: 11.0,
        damage: 12, base: 14, growth: 1.6, angle: 82, knockbackMul: 1.0, finalMul: 3.4,
        shieldDamageMul: 4.0 },
    },
  },
};
