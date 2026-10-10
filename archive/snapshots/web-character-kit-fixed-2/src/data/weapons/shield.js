// SHIELD - the weapon that wins by being hit.
//
// From the brief: Defensive, "counter attacker". Weight 110, run 19.5, air 15.5, fall 42.0, two
// jumps, Brace, signature Counterguard - "creates a short defensive window; if the opponent
// attacks during it, the Shield player blocks the hit and performs a powerful counterattack. If no
// attack connects, the player is vulnerable after the guard ends."
//
// Brace is the right mechanic and the brief asks for it, so this shares the pike's: frames spent
// holding shield bank a bonus that the next signature spends. On this weapon that reads as one
// idea rather than two - the whole fighter is about the value of standing still.
//
// Counterguard is `kind: 'counter'`, the engine's existing counter path: it has an active window,
// and a hit that lands inside it is converted into a burst scaled off the damage that was coming.
// The brief's "vulnerable after the guard ends" is the 34-frame recovery - whiff it and it is the
// worst punish window on any move in the game.
//
// Cash-outs are MEASURED in the engine (web/test/combo.test.mjs), not derived from frame data.

// Signature cash-outs. Both columns are MEASURED in the engine against a victim who spot-dodges on
// their first actionable frame (web/test/combo.test.mjs); neither is derived from frame data, and
// combo.test.mjs parses this table and fails if any band here stops reproducing.
//   CONFIRM = lands while they are still in hitstun, so there is no escape.
//   trap    = lands on the recovery of the dodge they escaped with. A real option, but a read.
//
//   Rising Bash +Heavy+Down -> Aegis Slam       CONFIRM  100-200%   trap   20-80%   kills  240%
//   Wall Break  +Heavy+Side -> Bulwark Charge   CONFIRM  160-220%   trap      80%   kills  229%
//   Low Bash    +Heavy      -> Aegis Slam       trap only     0-40%                 kills  240%
//   Boss Strike +Heavy+Down -> Aegis Slam       trap only        0%                 kills  240%
//   Boss Strike +Heavy+Side -> Bulwark Charge   trap only   20-120%                 kills  229%

export default {
  id: 'Shield', name: 'Shield', archetype: 'Counter attacker', tagline: 'Defensive',
  blurb: 'Slow, heavy, and short on reach. Counterguard turns the other player\'s best move into your best move, and whiffing it is the worst thing you can do.',
  difficulty: 3,
  stats: { set: { weight: 110 }, mul: { runSpeed: 0.848, airSpeed: 0.861, fallSpeed: 1.105, jumpVelocity: 0.95 } },
  palette: { primary: '#B0B8C6', secondary: '#4A5464', tertiary: '#2A303C', accent: '#F0F4FA', glow: '#7FD4FF' },
  trail: '#CFE4FF',
  mechanic: { id: 'Brace', guardFrames: 55, bonusDamage: 4, launchMul: 1.06 },
  recovery: { kind: 'hop', vy: 52, vx: 16 },
  signature: 'SigNeutral',

  moves: {
    // ---- light string ----
    LightNeutral1: { label: 'Bash', startup: 7, active: 3, recovery: 12, damage: 5, base: 13, growth: 1.1, angle: 40, grounded: true, shieldDamageMul: 1.8,
      chains: { neutral: 'LightNeutral2', side: 'LightSide1', up: 'LightUp', down: 'LightDown' },
      hitboxes: [{ frames: [8, 10], offset: [2.2, 2.8], size: [3.0, 3.0] }] },
    LightNeutral2: { label: 'Shield Jab', startup: 6, active: 3, recovery: 15, damage: 5, base: 15, growth: 1.4, angle: 42, grounded: true, extraHitstun: 8, shieldDamageMul: 1.8,
      chains: { neutral: 'LightNeutral3', up: 'LightUp', down: 'LightDown' },
      // The brief routes this into Counterguard. It cannot: a counter has NO HITBOX - it is a
      // window that converts an incoming hit - so there is nothing for a combo to connect with.
      // Counterguard is a standalone defensive option on this weapon, which is what a counter is.
      hitboxes: [{ frames: [7, 9], offset: [2.3, 2.8], size: [3.0, 3.0] }] },
    LightNeutral3: { label: 'Boss Strike', startup: 9, active: 3, recovery: 19, damage: 8, base: 20, growth: 2.1, angle: 48, grounded: true, extraHitstun: 6, shieldDamageMul: 2.0,
      chainsHeavy: { side: 'SigSide', down: 'SigDown' },
      hitboxes: [{ frames: [10, 12], offset: [2.5, 2.7], size: [3.4, 3.4] }] },

    LightSide1: { label: 'Shield Charge', startup: 9, active: 3, recovery: 14, damage: 6, base: 15, growth: 1.4, angle: 32, grounded: true, lunge: 3, shieldDamageMul: 2.2, extraHitstun: 10,
      chains: { side: 'LightSide2', neutral: 'LightNeutral2', up: 'LightUp' },
      hitboxes: [{ frames: [10, 12], offset: [2.6, 2.8], size: [3.4, 3.2] }] },
    LightSide2: { label: 'Wall Break', startup: 8, active: 4, recovery: 22, damage: 9, base: 21, growth: 2.4, angle: 36, grounded: true, lunge: 3.5, shieldDamageMul: 2.6,
      chainsHeavy: { side: 'SigSide' },
      hitboxes: [{ frames: [9, 12], offset: [2.9, 2.8], size: [4.0, 3.4] }] },

    LightUp: { label: 'Rising Bash', startup: 8, active: 3, recovery: 16, damage: 6, base: 17, growth: 1.9, angle: 84, grounded: true, extraHitstun: 6, shieldDamageMul: 1.8,
      chainsHeavy: { down: 'SigDown' },
      hitboxes: [{ frames: [9, 11], offset: [1.5, 4.0], size: [3.0, 4.2] }] },
    LightDown: { label: 'Low Bash', startup: 10, active: 4, recovery: 18, damage: 6, base: 14, growth: 1.5, angle: 14, grounded: true, trip: 65, shieldDamageMul: 2.0,
      chainsHeavy: { down: 'SigDown', neutral: 'SigDown' },
      hitboxes: [{ frames: [11, 14], offset: [2.8, 0.9], size: [4.4, 1.8] }] },

    // ---- aerials ----
    AirNeutral: { label: 'Shield Spin', startup: 8, active: 6, recovery: 14, landingLag: 11, damage: 6, base: 15, growth: 1.6, angle: 50, grounded: false,
      hitboxes: [{ frames: [9, 14], offset: [0, 2.9], size: [5.0, 4.4] }] },
    AirForward: { label: 'Flying Bash', startup: 10, active: 3, recovery: 16, landingLag: 12, damage: 9, base: 20, growth: 2.4, angle: 38, grounded: false,
      hitboxes: [{ frames: [11, 13], offset: [2.6, 2.8], size: [3.6, 3.6] }] },
    AirUp: { label: 'Shield Launch', startup: 9, active: 3, recovery: 15, landingLag: 11, damage: 8, base: 18, growth: 2.3, angle: 88, grounded: false,
      hitboxes: [{ frames: [10, 12], offset: [0.8, 4.6], size: [3.2, 4.0] }] },
    AirDown: { label: 'Ground Break', startup: 13, active: 5, recovery: 20, landingLag: 15, damage: 11, base: 21, growth: 2.7, angle: 268, grounded: false,
      fastFallActive: true, shieldDamageMul: 2.2,
      hitboxes: [{ frames: [14, 18], offset: [1.0, -0.9], size: [3.2, 4.0] }] },

    // ---- signatures ----
    SigSide: { label: 'Bulwark Charge', startup: 20, active: 5, recovery: 32, damage: 15, base: 29, growth: 3.9, angle: 38, grounded: true, heavy: true, lunge: 6,
      shieldDamageMul: 3.0,
      hitboxes: [{ frames: [21, 25], offset: [3.0, 2.8], size: [4.6, 4.0] }] },
    SigDown: { label: 'Aegis Slam', startup: 19, active: 4, recovery: 30, damage: 14, base: 26, growth: 3.4, angle: 22, grounded: true, heavy: true, trip: 95,
      shieldDamageMul: 2.4,
      hitboxes: [{ frames: [20, 23], offset: [3.0, 1.2], size: [5.6, 2.4] }] },
    // COUNTERGUARD. A 14-frame window that converts whatever was coming into a burst worth 1.9x
    // its damage, floored at 11% so countering a jab is still worth something. Whiff it and you
    // owe 34 frames, which is longer than any punish window the weapon can create itself.
    SigNeutral: { label: 'Counterguard', startup: 6, active: 14, recovery: 34, damage: 0, base: 30, growth: 4.2, angle: 56, grounded: true, heavy: true, kind: 'counter',
      counter: { multiplier: 1.9, minDamage: 11, burstFrames: 4, burstRecovery: 18, hitbox: { offset: [2.4, 2.8], size: [6.0, 5.0] } },
      hitboxes: [] },

    // ULTIMATE - AEGIS. Their damage becomes yours.
    //
    // For two seconds every hit that lands on this fighter is absorbed and thrown straight back at
    // whoever threw it at 2.2x, floored at 14% so even a jab hurts to have tried. Counterguard does
    // this for one hit on one frame; this holds the window open.
    //
    // It is the only ultimate in the game that does NOTHING unless the opponent acts, which is the
    // most complete statement of what this weapon is. Against someone who simply walks away it is
    // the whole meter spent on standing still - and that is the correct counterplay, not a flaw.
    // Startup 4, not 12. At twelve frames a swing already in the air beat the activation outright
    // at point-blank range - the probe failed at 2.5 and 4 studs and passed at 7, which is the
    // shape of an ultimate being interrupted rather than blocked. A counter that loses to being
    // attacked is not a counter.
    Ultimate: { label: 'Aegis', startup: 4, active: 120, recovery: 38, damage: 0, base: 0, growth: 0, angle: 50,
      grounded: true, heavy: true, kind: 'reflect', ultimate: true, shieldDamageMul: 3.0,
      hitboxes: [],
      reflect: { multiplier: 2.6, minDamage: 20, radius: 4.8, angle: 46, base: 30, growth: 3.6, shieldDamageMul: 3.0,
        // and the discharge: everything it absorbed, released on the last frame, with a floor so
        // an opponent who refuses to engage still has to respect the end of it
        dischargeMin: 20, dischargeShare: 1.1, dischargeRadius: 6.5 },
    },
  },
};
