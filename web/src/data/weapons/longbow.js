// LONGBOW - the weapon that wants the whole stage between you.
//
// From the brief: Precision zoner, "charge your shots". Weight 82, run 23.0, air 18.5, fall 34.0,
// two jumps, signature Deadeye - "allows the player to charge a precision shot; longer charge
// means higher damage and knockback".
//
// That is the mechanic, so the bow takes `Draw` rather than the brief's Momentum line: holding the
// heavy button draws the string, and the engine's existing `charge` path on a move already turns
// hold frames into damage, base and growth. Drawing also SLOWS YOU DOWN, which is the cost - the
// bow cannot kite and charge at the same time.
//
// Against the Blasters, which are the game's other ranged weapon: the Blasters fire fast, cheap
// shots from a magazine and want you at mid range. The bow has one arrow at a time, it is slower
// than anything else at close quarters, and a fully drawn Power Shot is the second biggest single
// hit in the game. One is pressure, the other is a threat.
//
// Cash-outs are MEASURED in the engine (web/test/combo.test.mjs), not derived from frame data.

// Signature cash-outs. Both columns are MEASURED in the engine against a victim who spot-dodges on
// their first actionable frame (web/test/combo.test.mjs); neither is derived from frame data, and
// combo.test.mjs parses this table and fails if any band here stops reproducing.
//   CONFIRM = lands while they are still in hitstun, so there is no escape.
//   trap    = lands on the recovery of the dodge they escaped with. A real option, but a read.
//
//   Quick Shot +Heavy+side  -> Rainfall    trap only 0-160%                    kills 244%
//   Bowstave +Heavy+down    -> Tripwire    CONFIRM 20-40%      trap 0%         kills 150%
//   Pierce +Heavy+side      -> Rainfall    trap only 0-100%                    kills 244%
//   Sky Arrow +Heavy+up     -> Power Shot  CONFIRM 100-180%    trap 20-80%     kills 149%
//   Sky Arrow +Heavy        -> Power Shot  CONFIRM 100-180%    trap 20-80%     kills 149%
//   Low Arrow +Heavy+down   -> Tripwire    trap only 0-60%                     kills 150%
//   Low Arrow +Heavy        -> Tripwire    trap only 0-60%                     kills 150%

export default {
  id: 'Longbow', name: 'Longbow', archetype: 'Precision zoner', tagline: 'Charge your shots',
  blurb: 'One arrow at a time, drawn as long as you dare. Helpless up close, and the longest single threat in the game from across the stage.',
  difficulty: 3,
  stats: { set: { weight: 82 }, mul: { runSpeed: 1.0, airSpeed: 1.028, fallSpeed: 0.895 } },
  palette: { primary: '#C9A96A', secondary: '#5A4028', tertiary: '#2E2418', accent: '#F0E2C0', glow: '#8EE86A' },
  trail: '#D8F0B4',
  // DRAW. Every frame with the heavy button held banks draw; a drawn shot spends it. Unlike
  // Momentum this is not a bonus you carry into a different move - it is the move.
  mechanic: { id: 'Draw', label: 'Draw', drawFrames: 60, bonusDamage: 2, launchMul: 1.05, slowMul: 0.55 },
  recovery: { kind: 'hop', vy: 60, vx: 18 },
  signature: 'SigNeutral',

  moves: {
    // ---- light string ----
    // Quick Shot is the only fast thing the bow owns and it is 3%: the string exists to buy space,
    // not damage.
    LightNeutral1: { label: 'Draw', startup: 7, active: 2, recovery: 13, damage: 3, base: 9, growth: 0.6, angle: 22, grounded: true, kind: 'projectile',
      chains: { neutral: 'LightNeutral2', side: 'LightSide1', up: 'LightUp', down: 'LightDown' },
      projectile: { speed: 62, lifetime: 26, size: [1.4, 0.3], spawnOffset: [2.2, 3.0], shape: 'arrow' } },
    LightNeutral2: { label: 'Quick Shot', startup: 6, active: 2, recovery: 14, damage: 4, base: 11, growth: 0.8, angle: 24, grounded: true, kind: 'projectile',
      chains: { neutral: 'LightNeutral3', up: 'LightUp' },
      chainsHeavy: { side: 'SigSide' },
      projectile: { speed: 66, lifetime: 26, size: [1.4, 0.3], spawnOffset: [2.2, 3.0], shape: 'arrow' } },
    // The only move on the weapon that wants them close, and the only one that sets anything up.
    LightNeutral3: { label: 'Bowstave', startup: 8, active: 3, recovery: 15, damage: 6, base: 17, growth: 1.8, angle: 50, grounded: true, extraHitstun: 14,
      chainsHeavy: { down: 'SigDown' },
      hitboxes: [{ frames: [9, 11], offset: [2.4, 2.8], size: [3.6, 3.0] }] },

    LightSide1: { label: 'Pierce', startup: 9, active: 2, recovery: 16, damage: 5, base: 12, growth: 1.0, angle: 18, grounded: true, kind: 'projectile',
      chains: { side: 'LightSide2', neutral: 'LightNeutral2' },
      chainsHeavy: { side: 'SigSide' },
      projectile: { speed: 78, lifetime: 30, size: [1.8, 0.3], spawnOffset: [2.4, 3.0], shape: 'arrow' } },
    LightSide2: { label: 'Impaler', startup: 11, active: 3, recovery: 22, damage: 8, base: 20, growth: 2.2, angle: 26, grounded: true, kind: 'projectile', extraHitstun: 5,
      // No cash-out: this is an arrow fired from outside everyone else's range with 22 frames of
      // recovery. Nothing reaches out of it and the weapon does not need it to.
      projectile: { speed: 84, lifetime: 32, size: [2.2, 0.4], spawnOffset: [2.6, 3.0], shape: 'arrow' } },

    // Sky Arrow holds them long enough to reach Power Shot, which is the bow's one guaranteed
    // cash-out and the only route on the weapon that closes a stock. Everything else is spacing.
    LightUp: { label: 'Sky Arrow', startup: 8, active: 3, recovery: 13, damage: 5, base: 15, growth: 1.7, angle: 84, grounded: true, extraHitstun: 16,
      chainsHeavy: { up: 'SigNeutral', neutral: 'SigNeutral' },
      hitboxes: [{ frames: [9, 11], offset: [1.4, 4.4], size: [2.2, 5.0] }] },
    // Tripwire: the arrow goes into the floor and whoever walks over it goes down.
    LightDown: { label: 'Low Arrow', startup: 10, active: 3, recovery: 17, damage: 4, base: 11, growth: 1.1, angle: 14, grounded: true, trip: 75,
      chainsHeavy: { down: 'SigDown', neutral: 'SigDown' },
      hitboxes: [{ frames: [11, 13], offset: [3.2, 0.8], size: [5.0, 1.4] }] },

    // ---- aerials ----
    AirNeutral: { label: 'Snap Shot', startup: 7, active: 3, recovery: 15, landingLag: 9, damage: 4, base: 12, growth: 1.2, angle: 30, grounded: false, kind: 'projectile',
      projectile: { speed: 64, lifetime: 24, size: [1.4, 0.3], spawnOffset: [1.8, 2.8], shape: 'arrow' } },
    AirForward: { label: 'Loosed', startup: 9, active: 3, recovery: 16, landingLag: 10, damage: 7, base: 18, growth: 2.1, angle: 28, grounded: false, kind: 'projectile',
      projectile: { speed: 76, lifetime: 30, size: [1.8, 0.3], spawnOffset: [2.2, 2.8], shape: 'arrow' } },
    AirUp: { label: 'Overhead Loose', startup: 8, active: 3, recovery: 15, landingLag: 9, damage: 6, base: 16, growth: 2.0, angle: 86, grounded: false,
      hitboxes: [{ frames: [9, 11], offset: [0.8, 4.6], size: [2.2, 4.4] }] },
    AirDown: { label: 'Plunging Shot', startup: 11, active: 4, recovery: 18, landingLag: 12, damage: 8, base: 19, growth: 2.4, angle: 272, grounded: false,
      fastFallActive: true,
      hitboxes: [{ frames: [12, 15], offset: [0.9, -1.0], size: [2.0, 4.0] }] },

    // ---- signatures ----
    SigSide: { label: 'Rainfall', startup: 24, active: 5, recovery: 32, damage: 12, base: 30, growth: 4.4, angle: 60, grounded: true, heavy: true, kind: 'projectile',
      // four arrows on a lob, so it covers ground rather than a line
      projectile: { speed: 52, lifetime: 40, size: [1.4, 0.3], spawnOffset: [2.0, 3.6], shape: 'arrow', count: 4, every: 3, spread: 0.9 } },
    SigDown: { label: 'Tripwire', startup: 20, active: 4, recovery: 30, damage: 11, base: 30, growth: 4.1, angle: 16, grounded: true, heavy: true, trip: 110,
      hitboxes: [{ frames: [21, 24], offset: [4.0, 0.9], size: [7.4, 1.8] }] },
    // DEADEYE. The brief's signature: hold heavy to draw, and the longer it is held the harder it
    // lands. Fully drawn it is the second largest single hit in the game - and the wind-up is 26
    // frames before the hold even starts, from a fighter who cannot move while drawing.
    SigNeutral: { label: 'Power Shot', startup: 26, active: 4, recovery: 34, damage: 14, base: 28, growth: 3.8, angle: 34, grounded: true, heavy: true, kind: 'projectile',
      // A FULLY DRAWN POWER SHOT KILLED FROM 37%, and from 21% with Draw banked on top - a
      // projectile taking a stock at a fifth of the percent anything else needs. Nothing caught it
      // because every combo measurement reads the UNCHARGED move (149%), and a `charge` block
      // silently replaces damage, base and growth.
      //
      // The trap is that raising damage lowers the kill percent all by itself: the victim's own
      // percent goes up before the knockback is computed. 22 damage on the uncharged 28/3.8 alone
      // already kills from 67%. So the charged knockback goes DOWN, not up, and the extra damage
      // is what makes it the biggest threat on the weapon. Charged now kills from 99%, in line
      // with Overcharge (129%) and Starfall (106%), the game's other two charge moves.
      charge: { maxHold: 60, damage: 22, base: 30, growth: 3.0 },
      projectile: { speed: 96, lifetime: 40, size: [3.0, 0.5], spawnOffset: [2.6, 3.0], shape: 'arrow' } },

    // ULTIMATE - HEARTSEEKER. One arrow.
    //
    // It crosses the entire stage, it goes THROUGH everything it hits rather than stopping at the
    // first, and it cannot be blocked. Every other ultimate in the game is a duration you survive;
    // this is a single frame of commitment behind a second and a half of drawing, which is the
    // most a precision weapon can honestly say. Miss and you have spent the whole meter on nothing.
    Ultimate: { label: 'Heartseeker', startup: 44, active: 8, recovery: 40, damage: 21, base: 34, growth: 3.4, angle: 30,
      grounded: true, heavy: true, kind: 'pierce', ultimate: true, knockbackMul: 1.4, shieldDamageMul: 3.0,
      hitboxes: [],
      pierce: { speed: 150, lifetime: 70, height: 3.0, size: [4.0, 0.7] },
    },
  },
};
