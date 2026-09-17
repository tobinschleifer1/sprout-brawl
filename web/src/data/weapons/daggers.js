// DUAL DAGGERS - the fastest, frailest thing in the game.
//
// From the brief: Glass cannon, "combo monster". Weight 72, run 29.0, air 24.0, fall 30.0, three
// jumps, signature Bloodrush - "every consecutive hit increases the combo counter; missing an
// attack resets the counter".
//
// So the daggers take `Surge`, the same counter the Gauntlets use, tuned the other way: the
// Gauntlets' Overdrive makes their attacks FASTER, and the daggers' Bloodrush makes theirs HURT
// MORE. Same mechanic, opposite payout, which is the honest reading of two briefs that describe
// the same gimmick for two different fighters. The brief's "missing resets the counter" is the
// part that separates them from the Gauntlets: on this weapon a whiff throws the whole thing away.
//
// Weight 72 is the lowest in the game by six points. Every stat is the best in the game and it
// dies about thirty percent of a stock earlier than anyone else - which is the deal.
//
// Cash-outs are MEASURED in the engine (web/test/combo.test.mjs), not derived from frame data.

// Signature cash-outs. Both columns are MEASURED in the engine against a victim who spot-dodges on
// their first actionable frame (web/test/combo.test.mjs); neither is derived from frame data, and
// combo.test.mjs parses this table and fails if any band here stops reproducing.
//   CONFIRM = lands while they are still in hitstun, so there is no escape.
//   trap    = lands on the recovery of the dodge they escaped with. A real option, but a read.
//
//   Twin Strike +Heavy+side  -> Execution    CONFIRM 0-180%                      kills 138%
//   Rising Blades +Heavy     -> Blade Storm  CONFIRM 0-180%                      kills 247%
//   Rising Blades +Heavy+up  -> Blade Storm  CONFIRM 0-180%                      kills 247%
//   Sweep +Heavy+down        -> Bloodrush    trap only 0-40%                     kills 128%
//   Sweep +Heavy             -> Bloodrush    trap only 0-40%                     kills 128%

export default {
  id: 'Daggers', name: 'Dual Daggers', archetype: 'Combo monster', tagline: 'Glass cannon',
  blurb: 'The fastest hands and the lightest body in the game. Nine hits in a row is where the damage lives, and a single whiff throws all of it away.',
  difficulty: 3,
  stats: { set: { weight: 72, jumps: 3 }, mul: { runSpeed: 1.261, airSpeed: 1.333, fallSpeed: 0.789, jumpVelocity: 1.04 } },
  palette: { primary: '#C8CED8', secondary: '#2E3A4A', tertiary: '#1A2230', accent: '#FFFFFF', glow: '#FF4A6A' },
  trail: '#FF8AA0',
  // BLOODRUSH. Five hits inside a second banks it, and unlike the Gauntlets' Overdrive a WHIFF
  // resets it - `resetOnWhiff` is the difference between the two weapons that share this mechanic.
  mechanic: { id: 'Surge', label: 'Bloodrush', hitsRequired: 5, windowFrames: 60, durationFrames: 210, startupCut: 0, bonusDamage: 5, launchMul: 1.07, resetOnWhiff: true },
  recovery: { kind: 'hop', vy: 68, vx: 28 },
  signature: 'SigSide',

  moves: {
    // ---- light string ----
    // The longest light string in the game: four links rather than three, because the weapon is
    // paid in hit count rather than in damage per hit.
    LightNeutral1: { label: 'Slash', startup: 3, active: 2, recovery: 6, damage: 2, base: 7, growth: 0.45, angle: 44, grounded: true,
      chains: { neutral: 'LightNeutral2', side: 'LightSide1', up: 'LightUp', down: 'LightDown' },
      hitboxes: [{ frames: [4, 5], offset: [1.9, 2.8], size: [2.4, 1.8] }] },
    LightNeutral2: { label: 'Cross Slash', startup: 3, active: 2, recovery: 7, damage: 2, base: 8, growth: 0.5, angle: 44, grounded: true,
      chains: { neutral: 'LightNeutral3', side: 'LightSide1', up: 'LightUp', down: 'LightDown' },
      hitboxes: [{ frames: [4, 5], offset: [2.0, 2.8], size: [2.4, 1.8] }] },
    LightNeutral3: { label: 'Twin Strike', startup: 4, active: 3, recovery: 11, damage: 4, base: 13, growth: 1.2, angle: 50, grounded: true, extraHitstun: 11,
      chainsHeavy: { side: 'SigSide' },
      hitboxes: [{ frames: [5, 7], offset: [2.1, 2.8], size: [2.8, 2.4] }] },

    LightSide1: { label: 'Dash Cut', startup: 4, active: 2, recovery: 9, damage: 3, base: 9, growth: 0.7, angle: 36, grounded: true, lunge: 2.5,
      chains: { side: 'LightSide2', neutral: 'LightNeutral3', up: 'LightUp' },
      hitboxes: [{ frames: [5, 6], offset: [2.3, 2.8], size: [2.8, 1.8] }] },
    // Backstab: the damage is on the other side of them, so the move rewards crossing up.
    LightSide2: { label: 'Backstab', startup: 5, active: 3, recovery: 12, damage: 5, base: 15, growth: 1.5, angle: 38, grounded: true, lunge: 4, extraHitstun: 10,
      hitboxes: [{ frames: [6, 8], offset: [2.6, 2.8], size: [3.2, 2.0] }] },

    LightUp: { label: 'Rising Blades', startup: 4, active: 3, recovery: 12, damage: 3, base: 12, growth: 1.4, angle: 86, grounded: true, extraHitstun: 7,
      chainsHeavy: { neutral: 'SigNeutral', up: 'SigNeutral' },
      hitboxes: [{ frames: [5, 7], offset: [1.4, 3.6], size: [2.4, 3.8] }] },
    LightDown: { label: 'Sweep', startup: 5, active: 3, recovery: 13, damage: 3, base: 10, growth: 0.9, angle: 16, grounded: true, trip: 52,
      chainsHeavy: { down: 'SigDown', neutral: 'SigDown' },
      hitboxes: [{ frames: [6, 8], offset: [2.2, 0.8], size: [3.4, 1.4] }] },

    // ---- aerials ----
    AirNeutral: { label: 'Blade Spin', startup: 4, active: 6, recovery: 10, landingLag: 5, damage: 3, base: 11, growth: 1.1, angle: 46, grounded: false,
      hitboxes: [{ frames: [5, 10], offset: [0, 2.8], size: [4.0, 3.4] }] },
    AirForward: { label: 'Leaping Cut', startup: 5, active: 3, recovery: 11, landingLag: 6, damage: 4, base: 14, growth: 1.6, angle: 40, grounded: false,
      hitboxes: [{ frames: [6, 8], offset: [2.2, 2.8], size: [2.8, 2.2] }] },
    AirUp: { label: 'Skyward Blades', startup: 4, active: 3, recovery: 10, landingLag: 5, damage: 4, base: 12, growth: 1.4, angle: 88, grounded: false,
      hitboxes: [{ frames: [5, 7], offset: [0.6, 4.2], size: [2.4, 3.4] }] },
    AirDown: { label: 'Falling Fang', startup: 7, active: 4, recovery: 12, landingLag: 8, damage: 5, base: 14, growth: 1.8, angle: 272, grounded: false,
      fastFallActive: true,
      hitboxes: [{ frames: [8, 11], offset: [0.7, -0.8], size: [2.0, 3.0] }] },

    // ---- signatures ----
    // Every signature here is small: the weapon's kill power is the counter, not the numbers.
    SigSide: { label: 'Execution', startup: 12, active: 4, recovery: 27, damage: 10, base: 34, growth: 5.6, angle: 36, grounded: true, heavy: true, lunge: 5,
      hitboxes: [{ frames: [13, 16], offset: [2.6, 2.8], size: [3.6, 2.6] }] },
    SigDown: { label: 'Bloodrush', startup: 14, active: 4, recovery: 29, damage: 11, base: 27, growth: 5.0, angle: 24, grounded: true, heavy: true, trip: 80,
      hitboxes: [{ frames: [15, 18], offset: [2.6, 1.2], size: [4.4, 2.0] }] },
    SigNeutral: { label: 'Blade Storm', startup: 11, active: 7, recovery: 30, damage: 3, base: 9, growth: 0.4, angle: 80, grounded: true, heavy: true,
      hitboxes: [
        { frames: [12, 16], offset: [1.8, 3.2], size: [3.4, 4.6], rehitEvery: 2, damage: 3, base: 8, growth: 0.3, angle: 84 },
        { frames: [17, 18], offset: [1.8, 3.6], size: [3.6, 5.0], damage: 8, base: 34, growth: 5.6, angle: 76 },
      ] },

    // ULTIMATE - Thousand Cuts. The fighter disappears and the opponent is simply somewhere the
    // daggers already are: a run of teleporting slashes that ends behind them. Nine strikes, and
    // the last one is the only one with any knockback at all - everything before it is the setup
    // for it, which is the weapon in one move.
    Ultimate: { label: 'Thousand Cuts', startup: 14, active: 44, recovery: 32, damage: 3, base: 6, growth: 0.15, angle: 50,
      grounded: true, heavy: true, kind: 'melee', ultimate: true, knockbackMul: 1.3, shieldDamageMul: 3.0,
      // lunge 6, not 16: at sixteen the fighter outran its own flurry and the whole ultimate landed
      // 12% instead of the twenty it is authored for. A teleporting-slash ultimate has to stay on
      // the victim.
      lunge: 6,
      hitboxes: [
        { frames: [15, 46], offset: [1.8, 2.8], size: [6.4, 4.4], shieldDamageMul: 1.4, rehitEvery: 3, damage: 2, base: 5, growth: 0.1, angle: 55 },
        { frames: [47, 58], offset: [2.4, 2.8], size: [5.6, 4.2], rehitEvery: 12, damage: 12, base: 26, growth: 3.6, angle: 38 },
      ] },
  },
};
