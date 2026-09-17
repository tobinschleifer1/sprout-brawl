// CHAIN FLAIL - the weapon you cannot read.
//
// From the brief: Unpredictable, "space control". Weight 101, run 20.5, air 17.0, fall 38.0, two
// jumps, signature Chain Reaper, and: "Snare can attach the chain to an opponent. The player can
// then pull the opponent toward them or pull themselves toward the opponent."
//
// So the mechanic is `Snare`, not Momentum. The pull is implemented on the engine's vortex path -
// the same code the Scythe's ultimate uses to drag fighters in - because a grapple that yanks
// somebody across the stage is exactly that, at a smaller scale.
//
// The identity: the longest ARC in the game as opposed to the pike's longest line. Its hitboxes
// are wide, curved and slow, they hit on the way out AND the way back, and the head keeps moving
// through its own recovery - which is what "unpredictable" means here in a way a random number
// never could.
//
// Cash-outs are MEASURED in the engine (web/test/combo.test.mjs), not derived from frame data.

// Signature cash-outs. Both columns are MEASURED in the engine against a victim who spot-dodges on
// their first actionable frame (web/test/combo.test.mjs); neither is derived from frame data, and
// combo.test.mjs parses this table and fails if any band here stops reproducing.
//   CONFIRM = lands while they are still in hitstun, so there is no escape.
//   trap    = lands on the recovery of the dodge they escaped with. A real option, but a read.
//
//   Return +Heavy+side         -> Reaper        trap only 0-60%                     kills 120%
//   Full Circle +Heavy+side    -> Reaper        CONFIRM 80-100%     trap 20-60%     kills 120%
//   Chain Breaker +Heavy+side  -> Reaper        CONFIRM 60%         trap 20-40%     kills 120%
//   Rising Chain +Heavy+up     -> Chain Reaper  trap only 120-180%                  kills 139%
//   Rising Chain +Heavy        -> Chain Reaper  trap only 120-180%                  kills 139%

export default {
  id: 'Flail', name: 'Chain Flail', archetype: 'Space control', tagline: 'Unpredictable',
  blurb: 'A weighted head on four studs of chain. Wide, slow arcs that hit going out and coming back, and a snare that decides who closes the distance.',
  difficulty: 3,
  stats: { set: { weight: 101 }, mul: { runSpeed: 0.891, airSpeed: 0.944, fallSpeed: 1.0 } },
  palette: { primary: '#6E7684', secondary: '#3A3038', tertiary: '#231C22', accent: '#C8CED8', glow: '#C86AE8', hilt: '#7A6248' },
  trail: '#D8B0F0',
  // SNARE. Land the down signature and the chain is attached: for its duration, holding toward
  // them reels them in and holding away reels YOU in. One tool, two completely different plans.
  mechanic: { id: 'Snare', label: 'Snare', holdFrames: 90, pullSpeed: 38, range: 16, bonusDamage: 2, launchMul: 1.03 },
  // A tether recovery, because it is a chain. The field names are the ones the `tether` branch of
  // fighter.js actually reads - range/speed/hopVy, NOT vy/vx. Declared with the wrong pair it
  // produced `vy = undefined` on every failed grab, which is a non-finite fighter and an
  // unfinishable match; see the recovery-shape check in weapons.test.mjs.
  recovery: { kind: 'tether', range: 15, speed: 62, hopVy: 48 },
  signature: 'SigDown',

  moves: {
    // ---- light string ----
    LightNeutral1: { label: 'Swing', startup: 8, active: 4, recovery: 13, damage: 4, base: 12, growth: 1.0, angle: 42, grounded: true,
      chains: { neutral: 'LightNeutral2', side: 'LightSide1', up: 'LightUp', down: 'LightDown' },
      hitboxes: [{ frames: [9, 12], offset: [3.2, 3.0], size: [4.6, 3.0] }] },
    // Return: the head comes back through the same space, which is the whole point of a flail.
    // Two hitboxes, one outbound and one inbound, and they read as one motion.
    LightNeutral2: { label: 'Return', startup: 7, active: 6, recovery: 15, damage: 4, base: 13, growth: 1.1, angle: 44, grounded: true,
      chains: { neutral: 'LightNeutral3', up: 'LightUp', down: 'LightDown' },
      chainsHeavy: { side: 'SigSide' },
      hitboxes: [
        { frames: [8, 10], offset: [3.4, 3.0], size: [4.4, 2.8] },
        { frames: [11, 13], offset: [-1.2, 3.0], size: [4.0, 2.8], damage: 3, base: 11, growth: 0.9, angle: 130 },
      ] },
    LightNeutral3: { label: 'Full Circle', startup: 10, active: 6, recovery: 19, damage: 7, base: 19, growth: 2.0, angle: 52, grounded: true, extraHitstun: 14,
      chainsHeavy: { side: 'SigSide' },
      hitboxes: [
        { frames: [11, 13], offset: [3.4, 3.2], size: [5.0, 3.4] },
        { frames: [14, 16], offset: [-1.6, 3.2], size: [4.4, 3.4], damage: 5, base: 15, growth: 1.4, angle: 128 },
      ] },

    LightSide1: { label: 'Long Swing', startup: 10, active: 4, recovery: 16, damage: 5, base: 14, growth: 1.3, angle: 36, grounded: true, lunge: 2,
      chains: { side: 'LightSide2', neutral: 'LightNeutral2', up: 'LightUp' },
      hitboxes: [{ frames: [11, 14], offset: [4.4, 2.9], size: [6.0, 2.8] }] },
    LightSide2: { label: 'Chain Breaker', startup: 9, active: 5, recovery: 21, damage: 8, base: 21, growth: 2.4, angle: 40, grounded: true, lunge: 2.5, extraHitstun: 12,
      chainsHeavy: { side: 'SigSide' },
      hitboxes: [{ frames: [10, 14], offset: [4.8, 2.9], size: [6.8, 3.2] }] },

    LightUp: { label: 'Rising Chain', startup: 9, active: 4, recovery: 17, damage: 5, base: 16, growth: 1.8, angle: 82, grounded: true, extraHitstun: 6,
      chainsHeavy: { up: 'SigNeutral', neutral: 'SigNeutral' },
      hitboxes: [{ frames: [10, 13], offset: [1.8, 4.4], size: [3.2, 5.2] }] },
    LightDown: { label: 'Ground Wrap', startup: 11, active: 5, recovery: 16, damage: 5, base: 13, growth: 1.4, angle: 12, grounded: true, trip: 68, extraHitstun: 12,
      hitboxes: [{ frames: [12, 16], offset: [3.6, 0.9], size: [6.2, 1.8] }] },

    // ---- aerials ----
    AirNeutral: { label: 'Whirl', startup: 8, active: 9, recovery: 15, landingLag: 10, damage: 5, base: 14, growth: 1.5, angle: 50, grounded: false,
      hitboxes: [{ frames: [9, 17], offset: [0, 3.0], size: [7.8, 5.4] }] },
    AirForward: { label: 'Flung Head', startup: 11, active: 4, recovery: 17, landingLag: 11, damage: 8, base: 19, growth: 2.3, angle: 36, grounded: false,
      hitboxes: [{ frames: [12, 15], offset: [4.2, 2.8], size: [5.4, 3.0] }] },
    AirUp: { label: 'Chain Launch', startup: 9, active: 4, recovery: 16, landingLag: 10, damage: 7, base: 17, growth: 2.2, angle: 86, grounded: false,
      hitboxes: [{ frames: [10, 13], offset: [1.0, 5.0], size: [3.0, 5.2] }] },
    AirDown: { label: 'Drop Weight', startup: 12, active: 5, recovery: 19, landingLag: 13, damage: 9, base: 20, growth: 2.6, angle: 270, grounded: false,
      fastFallActive: true,
      hitboxes: [{ frames: [13, 17], offset: [1.0, -1.2], size: [2.6, 4.6] }] },

    // ---- signatures ----
    SigSide: { label: 'Reaper', startup: 21, active: 8, recovery: 31, damage: 15, base: 31, growth: 4.6, angle: 42, grounded: true, heavy: true, lunge: 3,
      hitboxes: [
        { frames: [22, 25], offset: [5.0, 3.0], size: [8.0, 3.8] },
        { frames: [26, 28], offset: [-2.0, 3.0], size: [5.4, 3.8], damage: 9, base: 22, growth: 3.0, angle: 132 },
      ] },
    // SNARE. The brief's mechanic move: it attaches, and then the match is about who is dragged.
    SigDown: { label: 'Snare', startup: 18, active: 5, recovery: 30, damage: 9, base: 14, growth: 1.2, angle: 20, grounded: true, heavy: true, kind: 'vortex',
      vortex: { targets: 1, range: 16, holdFrames: 20, pullSpeed: 38, orbOffset: [2.6, 3.0],
        crush: { damage: 8, base: 20, growth: 2.4, angle: 46 } },
      hitboxes: [{ frames: [19, 23], offset: [4.4, 1.6], size: [7.0, 2.6] }] },
    SigNeutral: { label: 'Chain Reaper', startup: 23, active: 5, recovery: 32, damage: 14, base: 30, growth: 4.9, angle: 84, grounded: true, heavy: true,
      hitboxes: [{ frames: [24, 28], offset: [2.2, 4.8], size: [4.4, 7.4] }] },

    // ULTIMATE - ANCHOR. The head goes into the ground and stays there.
    //
    // For four seconds the chain between the fighter and that point is live along its whole length,
    // and the fighter can still walk - so the weapon stops being a swing and becomes a lethal line
    // you drag around the stage. Standing still is worthless; the move is entirely about where you
    // put yourself relative to a point you chose.
    //
    // It is the only ultimate in the game that leaves something ON the stage and then asks the
    // player to play around it. Pull too far and the chain snaps and the ultimate is over.
    Ultimate: { label: 'Anchor', startup: 20, active: 70, recovery: 34, damage: 4, base: 9, growth: 0.3, angle: 58,
      grounded: true, heavy: true, kind: 'anchor', ultimate: true, knockbackMul: 1.25, shieldDamageMul: 3.0,
      hitboxes: [],
      // 2 damage every 9 frames, not 4 every 6. Measured, the first version dealt 124% in a single
      // ultimate - three times what any other one in the game does - because a chain that is live
      // along its whole length hits far more often than a swing does. It also swamped the check
      // that ultimate knockback scales with percent: when the move itself adds a hundred percent,
      // what the victim started at stops mattering.
      anchor: { throwDistance: 9, maxLength: 26, every: 8, thickness: 1.6,
        damage: 3, base: 9, growth: 0.6, angle: 62, shieldDamageMul: 1.8,
        // and the snap-back, which is the move's finisher
        snapDamage: 13, snapBase: 15, snapGrowth: 5.2, snapAngle: 44 },
    },
  },
};
