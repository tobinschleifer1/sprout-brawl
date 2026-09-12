// BATTLE AXE - the weapon you feel the weight of.
//
// Everything about this one is built from a single idea: the axe is too heavy to carry properly.
// It is the slowest weapon in the game, it has the worst recovery, and its fighter DRAGS it along
// the floor whenever they are not swinging it — `drag: true` tells the renderer to rest the head
// on the ground and kick up dirt wherever it scrapes. That drag is not decoration; it is the
// readable tell that this fighter cannot reposition quickly, which is the price of the damage.
//
// The heavies do not swing so much as fall. Each one hauls the axe up to head height across a long,
// visibly effortful wind-up and then lets go — the strike frames are gravity, not muscle, which is
// why the contact is so much faster than the lift. The animation layer gets this for free: the
// shared swing curve already eases OUT of rest and IN to contact, and the axe's arcs simply take
// that further than any other weapon's.
//
// Momentum is the mechanic, and it is the tension the weapon is designed around: the bonus is
// bought with 50 frames of running, and running is exactly when the axe is scraping along the
// floor behind you, telegraphing to everyone that you are winding up for something. You cannot
// charge it quietly.
//
// Range is short for its size. The head is heavy and close; the reach is in the arc, not the haft.
//
// Signature cash-outs. Both columns are MEASURED in the engine against a victim who spot-dodges on
// their first actionable frame (web/test/combo.test.mjs); neither is derived from frame data.
//   CONFIRM = lands while they are still in hitstun, so there is no escape.
//   trap    = lands on the recovery of the dodge they escaped with. A real option, but a read.
//
//   Uppercut Swing +Heavy  -> Uproot          CONFIRM 60-180%    trap  0-40%     kills 117%
//   Chop           +Heavy  -> Executioner     trap only  0-180%                  kills 134%
//   Chop     +Heavy+Side   -> Wide Arc        trap only  0-120%                  kills  97%
//   Backhand       +Heavy  -> Executioner     trap only  0-160%                  kills 134%
//   Floor Sweep    +Heavy  -> Executioner     trap only 60-180%                  kills 134%
//   Follow Through +Heavy+Side -> Wide Arc    trap only 120-160%                 kills  97%
//
// The shape of that table IS the weapon. One guaranteed route, off the one fast move it owns, and
// everything else is a read you have to earn. Executioner kills at 134% and can never be
// confirmed into — if you want it, you have to make them respect something else first.

export default {
  id: 'Axe', name: 'Battle Axe', archetype: 'Heavy bruiser',
  tagline: 'Gravity does the work',
  blurb: 'The slowest, heaviest weapon in the game. It drags on the floor between swings, and every heavy is a lift and a drop rather than a swing.',
  difficulty: 2,
  // Heaviest body in the roster, slowest on the ground, and it falls like the axe is pulling it
  // down — which buys it the best survivability against horizontal launches and the worst against
  // being knocked off the bottom.
  stats: { set: { weight: 118 }, mul: { runSpeed: 0.82, airSpeed: 0.86, fallSpeed: 1.18, jumpVelocity: 0.94 } },
  // `hilt` is a separate, lighter value for the haft: the old #2E2A26 measured 1.02:1 against
  // the backgrounds this weapon is drawn on, so most of its length was invisible.
  palette: { primary: '#8A8F98', secondary: '#5A4632', tertiary: '#2E2A26', hilt: '#8A6E4A', accent: '#D8DCE2', glow: '#FFB05A' },
  trail: '#E8C89A',
  drag: true,                                    // rests on the floor when not attacking
  mechanic: { id: 'Momentum', runFrames: 50, bonusDamage: 3, launchMul: 1.06 },
  recovery: { kind: 'hop', vy: 50, vx: 14 },     // poor: heavy weapons should fear the ledge
  signature: 'SigDown',

  moves: {
    // ---- light string ----
    // Even the lights are hauled rather than flicked. The first one is the only fast option the
    // axe owns, and it exists so the weapon has any answer at all to being rushed.
    LightNeutral1: { label: 'Chop', startup: 7, active: 3, recovery: 11, damage: 5, base: 12, growth: 1.0, angle: 45, grounded: true,
      chains: { neutral: 'LightNeutral2', side: 'LightSide1', up: 'LightUp', down: 'LightDown' },
      // no `up` cash-out: only the launcher generates enough hitstun to reach Uproot
      chainsHeavy: { neutral: 'SigDown', side: 'SigSide', down: 'SigDown' },
      hitboxes: [{ frames: [8, 10], offset: [2.2, 3.0], size: [3.6, 3.2] }] },
    LightNeutral2: { label: 'Backhand', startup: 8, active: 3, recovery: 13, damage: 6, base: 14, growth: 1.2, angle: 45, grounded: true,
      chains: { neutral: 'LightNeutral3', up: 'LightUp', down: 'LightDown' },
      chainsHeavy: { neutral: 'SigDown', side: 'SigSide', down: 'SigDown' },
      hitboxes: [{ frames: [9, 11], offset: [2.4, 3.2], size: [3.8, 3.4] }] },
    LightNeutral3: { label: 'Cleave', startup: 11, active: 4, recovery: 20, damage: 9, base: 20, growth: 2.2, angle: 52, grounded: true,
      // Cleave's own recovery is too long to reach anything but the fastest heavy, so it only
      // advertises the two that actually connect.
      chainsHeavy: { neutral: 'SigDown', down: 'SigDown' },
      hitboxes: [{ frames: [12, 15], offset: [2.8, 2.8], size: [4.6, 4.4] }] },

    LightSide1: { label: 'Haul', startup: 10, active: 3, recovery: 15, damage: 6, base: 14, growth: 1.3, angle: 38, grounded: true, lunge: 2.5,
      chains: { side: 'LightSide2', neutral: 'LightNeutral2', up: 'LightUp', down: 'LightDown' },
      // no heavy cash-out: Haul exists to close distance into Follow Through, not to end a string
      hitboxes: [{ frames: [11, 13], offset: [3.0, 3.0], size: [4.4, 3.4] }] },
    LightSide2: { label: 'Follow Through', startup: 9, active: 4, recovery: 22, damage: 9, base: 22, growth: 2.6, angle: 42, grounded: true, lunge: 3,
      chainsHeavy: { side: 'SigSide', neutral: 'SigDown', down: 'SigDown' },
      hitboxes: [{ frames: [10, 13], offset: [3.2, 2.8], size: [5.0, 3.8] }] },

    // The launcher, and the axe's ONE guaranteed route. It pops them high enough and holds them
    // long enough that Uproot cannot be dodged out of — which is the whole reason the weapon has a
    // fast light at all.
    LightUp: { label: 'Uppercut Swing', startup: 10, active: 3, recovery: 17, damage: 7, base: 17, growth: 1.9, angle: 84, grounded: true, extraHitstun: 6,
      chainsHeavy: { neutral: 'SigNeutral', up: 'SigNeutral' },
      hitboxes: [{ frames: [11, 13], offset: [1.6, 4.6], size: [3.4, 5.0] }] },
    // The haft sweeps low along the floor — the one move that uses the drag rather than fighting it.
    LightDown: { label: 'Floor Sweep', startup: 11, active: 4, recovery: 19, damage: 6, base: 13, growth: 1.4, angle: 14, grounded: true, trip: 65,
      chainsHeavy: { neutral: 'SigDown', down: 'SigDown' },
      hitboxes: [{ frames: [12, 15], offset: [3.0, 0.9], size: [5.4, 2.0] }] },

    // ---- aerials ----
    // The axe in the air is a liability everywhere except straight down, which is the point.
    AirNeutral: { label: 'Turn Cut', startup: 10, active: 6, recovery: 16, landingLag: 12, damage: 8, base: 17, growth: 2.0, angle: 48, grounded: false,
      hitboxes: [{ frames: [11, 16], offset: [0, 3.0], size: [6.0, 5.4] }] },
    AirForward: { label: 'Overhand', startup: 13, active: 4, recovery: 18, landingLag: 14, damage: 11, base: 22, growth: 2.8, angle: 38, grounded: false,
      hitboxes: [{ frames: [14, 17], offset: [3.0, 2.8], size: [4.6, 4.6] }] },
    AirUp: { label: 'Heave', startup: 12, active: 4, recovery: 17, landingLag: 12, damage: 9, base: 19, growth: 2.5, angle: 88, grounded: false,
      hitboxes: [{ frames: [13, 16], offset: [0.8, 5.2], size: [4.0, 4.8] }] },
    // The signature aerial: the axe's own weight turned into a spike. Slow, obvious, and lethal.
    AirDown: { label: 'Deadweight', startup: 15, active: 6, recovery: 24, landingLag: 18, damage: 13, base: 24, growth: 3.2, angle: 268, grounded: false,
      fastFallActive: true,
      hitboxes: [{ frames: [16, 21], offset: [1.2, -0.8], size: [3.8, 4.4] }] },

    // ---- signatures ----
    // All three are the same sentence said three ways: HAUL IT UP, then let it fall. The wind-ups
    // are the longest in the game and they are supposed to be — the lift is the telegraph, and the
    // fighter is visibly straining through every frame of it.
    SigSide: { label: 'Wide Arc', startup: 24, active: 5, recovery: 36, damage: 17, base: 32, growth: 4.4, angle: 40, grounded: true, heavy: true, lunge: 5,
      hitboxes: [{ frames: [25, 29], offset: [3.6, 2.6], size: [7.0, 5.2] }] },
    // The one the weapon is named for: overhead, held a beat, then dropped. It splits the floor.
    SigDown: { label: 'Executioner', startup: 28, active: 5, recovery: 38, damage: 19, base: 30, growth: 4.0, angle: 66, grounded: true, heavy: true,
      shieldDamageMul: 2.0,
      hitboxes: [{ frames: [29, 33], offset: [2.4, 2.2], size: [5.6, 6.4] }] },
    // Fast for a signature, because it is the cash-out for the launcher and nothing else.
    SigNeutral: { label: 'Uproot', startup: 17, active: 4, recovery: 32, damage: 15, base: 33, growth: 5.0, angle: 86, grounded: true, heavy: true,
      hitboxes: [{ frames: [18, 21], offset: [1.8, 5.0], size: [4.4, 7.0] }] },

    // ULTIMATE - Reave. The short burst the weapon has been fighting against all match.
    //
    // Every other move on this axe is the fighter losing an argument with its weight. Reave is the
    // fighter stopping: they plant, let the head swing, and go with it — three full revolutions
    // that get faster and wider as the momentum builds, dragging them forward the whole way,
    // hitting everything in the circle on every pass. The last revolution is the one that sends.
    //
    // `rehitEvery` is what makes it a grinder rather than a launcher: a victim caught early is
    // struck on each pass at low knockback, held in the circle, and only released by the finisher.
    Ultimate: { label: 'Reave', startup: 22, active: 54, recovery: 40, damage: 4, base: 8, growth: 0.2, angle: 70,
      grounded: true, heavy: true, kind: 'melee', ultimate: true, knockbackMul: 1.4, shieldDamageMul: 3.0,
      lunge: 14, weaponScale: 1.35,
      hitboxes: [
        // three accelerating revolutions, centred on the fighter so the spin holds them in
        { frames: [23, 42], offset: [0, 3.0], size: [10.0, 7.0], shieldDamageMul: 1.5, rehitEvery: 7, damage: 3, base: 8, growth: 0.2, angle: 80 },
        { frames: [43, 62], offset: [0, 3.0], size: [11.5, 7.6], shieldDamageMul: 1.5, rehitEvery: 6, damage: 3, base: 9, growth: 0.25, angle: 80 },
        // the release: one wide, slow, enormous horizontal cut
        { frames: [63, 76], offset: [1.4, 2.8], size: [14.0, 8.2], rehitEvery: 3,
          // A grinder's finisher has to kill LATER than a single-hit ultimate's, because the grind
          // has already put fifty percent on them before it lands. At base 30 it KO'd from 52%,
          // which after the grind meant it killed from zero.
          damage: 14, base: 25, growth: 3.4, angle: 38 },
      ] },
  },
};
