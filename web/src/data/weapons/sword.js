// SWORD - the honest weapon. Every other weapon is described relative to this one.
// No stat modifiers, no gimmick, mid range on everything. Its edge is the combo tree: the light
// string branches four ways and every branch cashes out into a signature.
//
// Combo language (direction is read on the FOLLOW-UP press, not the first one):
//   Light,Light,Light          Slash, Backslash, Cross Cut     safe damage, opens every heavy branch
//   Light,Light+Up / Up+Light  Rising Cut                      launcher, into an up-air
//   Light,Light+Down           Low Sweep                       trips under 60%
//   Light+Side,Light+Side      Dash Slash, Riposte             the approach string
//
// Signature cash-outs. Both columns are MEASURED in the engine against a victim who spot-dodges on
// their first actionable frame (web/test/combo.test.mjs); neither is derived from frame data.
//   CONFIRM = lands while they are still in hitstun, so there is no escape.
//   trap    = lands on the recovery of the dodge they escaped with. A real option, but a read.
//
//   Rising Cut +Heavy      -> Skyward         CONFIRM 120-160%   trap  20-100%   kills 129%
//   Riposte    +Heavy      -> Crescent Rush   CONFIRM 140-180%   trap  80-120%   kills 111%
//   Cross Cut  +Heavy      -> Skyward         CONFIRM     160%   trap  60-140%   kills 129%
//   Cross Cut  +Heavy+Down -> Earthsplitter   CONFIRM     180%   trap  80-160%   kills 120%
//   Cross Cut  +Heavy+Side -> Crescent Rush   trap only 140-180%                 kills 111%
//   Low Sweep  +Heavy      -> Earthsplitter   trap only   0-40%                  kills 120%
//
// Momentum: 60 frames of running buys +1 damage and x1.01 launch on the next SIGNATURE, worth about
// 16 points of kill percent. A light does not burn it, so it can ride a cash-out.

export default {
  id: 'Sword', name: 'Sword', archetype: 'All-rounder', tagline: 'Clean combos, no excuses',
  blurb: 'Mid range, mid speed, mid weight. The sword rewards knowing your string better than the other player knows theirs.',
  difficulty: 1,
  stats: {},                                     // no modifiers: the sword IS the baseline
  palette: { primary: '#D9DEE6', secondary: '#7A8698', tertiary: '#3B4453', accent: '#FFFFFF', glow: '#9FE8FF' },
  trail: '#CFE9FF',
  mechanic: { id: 'Momentum', runFrames: 60, bonusDamage: 1, launchMul: 1.01 },
  recovery: { kind: 'hop', vy: 58, vx: 20 },
  signature: 'SigSide',

  moves: {
    // ---- light string ----
    LightNeutral1: { label: 'Slash', startup: 5, active: 2, recovery: 8, damage: 3, base: 10, growth: 0.8, angle: 45, grounded: true,
      chains: { neutral: 'LightNeutral2', side: 'LightSide1', up: 'LightUp', down: 'LightDown' },
      hitboxes: [{ frames: [6, 7], offset: [2.1, 2.6], size: [2.8, 2.2] }] },
    LightNeutral2: { label: 'Backslash', startup: 4, active: 2, recovery: 9, damage: 3, base: 11, growth: 0.9, angle: 45, grounded: true,
      chains: { neutral: 'LightNeutral3', up: 'LightUp', down: 'LightDown' },
      hitboxes: [{ frames: [5, 6], offset: [2.3, 2.6], size: [2.8, 2.2] }] },
    LightNeutral3: { label: 'Cross Cut', startup: 6, active: 3, recovery: 16, damage: 5, base: 16, growth: 1.6, angle: 45, grounded: true, lunge: 2, extraHitstun: 7,
      chainsHeavy: { neutral: 'SigNeutral', side: 'SigSide', down: 'SigDown' },
      hitboxes: [{ frames: [7, 9], offset: [2.8, 2.5], size: [3.4, 2.6] }] },

    LightSide1: { label: 'Dash Slash', startup: 8, active: 3, recovery: 12, damage: 4, base: 12, growth: 1.1, angle: 35, grounded: true, lunge: 3,
      chains: { side: 'LightSide2', neutral: 'LightSide2', up: 'LightUp' },
      hitboxes: [{ frames: [9, 11], offset: [3.4, 2.5], size: [4.0, 2.2] }] },
    LightSide2: { label: 'Riposte', startup: 6, active: 3, recovery: 18, damage: 6, base: 19, growth: 2.3, angle: 40, grounded: true, lunge: 2, extraHitstun: 4,
      chainsHeavy: 'SigSide',
      hitboxes: [{ frames: [7, 9], offset: [3.6, 2.5], size: [4.2, 2.4] }] },

    LightUp: { label: 'Rising Cut', startup: 7, active: 3, recovery: 14, damage: 5, base: 15, growth: 1.7, angle: 80, grounded: true, extraHitstun: 5,
      chainsHeavy: 'SigNeutral',
      hitboxes: [{ frames: [8, 10], offset: [1.6, 3.8], size: [3.0, 4.0] }] },
    LightDown: { label: 'Low Sweep', startup: 8, active: 4, recovery: 16, damage: 5, base: 13, growth: 1.5, angle: 20, grounded: true, trip: 60, extraHitstun: 7,
      chainsHeavy: 'SigDown',
      hitboxes: [{ frames: [9, 12], offset: [2.8, 0.8], size: [4.4, 1.4] }] },

    // ---- aerials ----
    AirNeutral: { label: 'Spin Cut', startup: 8, active: 10, recovery: 14, landingLag: 8, damage: 7, base: 16, growth: 2.0, angle: 50, grounded: false,
      hitboxes: [{ frames: [9, 18], offset: [0, 2.6], size: [4.8, 4.8] }] },
    AirForward: { label: 'Arc Slash', startup: 10, active: 4, recovery: 15, landingLag: 10, damage: 8, base: 20, growth: 2.4, angle: 35, grounded: false, onHit: { bounce: 10 },
      hitboxes: [{ frames: [11, 14], offset: [3.4, 2.6], size: [4.4, 3.0] }] },
    AirUp: { label: 'Overhead', startup: 9, active: 4, recovery: 14, landingLag: 8, damage: 7, base: 18, growth: 2.6, angle: 88, grounded: false, onHit: { regainJump: true },
      hitboxes: [{ frames: [10, 13], offset: [0.4, 5.0], size: [3.6, 4.0] }] },
    AirDown: { label: 'Skewer', startup: 13, active: 5, recovery: 19, landingLag: 13, damage: 10, base: 22, growth: 3.0, angle: 60, grounded: false,
      hitboxes: [
        { frames: [14, 15], offset: [0.5, -0.6], size: [1.8, 2.2], angle: 275 },   // sweetspot: spike
        { frames: [14, 18], offset: [0.5, 1.0], size: [2.2, 3.2] },                // late: sends up-forward
      ] },

    // ---- signatures ----
    SigSide: { label: 'Crescent Rush', startup: 21, active: 4, recovery: 30, damage: 14, base: 32, growth: 5.0, angle: 40, grounded: true, heavy: true, lunge: 8,
      hitboxes: [{ frames: [22, 25], offset: [4.2, 2.6], size: [6.4, 3.6] }] },
    SigDown: { label: 'Earthsplitter', startup: 19, active: 5, recovery: 32, damage: 15, base: 33, growth: 5.2, angle: 72, grounded: true, heavy: true, lunge: 4,
      hitboxes: [{ frames: [20, 24], offset: [3.0, 1.2], size: [7.0, 2.6] }] },
    SigNeutral: { label: 'Skyward', startup: 18, active: 4, recovery: 28, damage: 13, base: 34, growth: 5.4, angle: 85, grounded: true, heavy: true,
      hitboxes: [{ frames: [19, 22], offset: [1.2, 4.2], size: [3.6, 6.0] }] },

    // ULTIMATE - Colossus. The blade doubles in length and comes down from directly overhead in
    // one committed stroke. The swing itself is only half the move: where it lands, the floor
    // opens, and a crater of rock and energy walks outward from the impact in both directions.
    // Everything it touches takes 1.5x the knockback it would otherwise have taken, so this is a
    // finisher - at 0% it is a big hit, at 90% it is the end of a stock.
    Ultimate: { label: 'Colossus', startup: 24, active: 26, recovery: 32, damage: 16, base: 26, growth: 3.4, angle: 46,
      grounded: true, heavy: true, kind: 'slam', ultimate: true, knockbackMul: 1.5, weaponScale: 2, shieldDamageMul: 3.0,
      // the descending blade: a tall box in front, live for the four frames of the stroke
      hitboxes: [
        { frames: [25, 28], offset: [2.4, 4.2], size: [6.4, 10.0] },
      ],
      // And the impact. It fires on the SAME frame the blade lands, not after it: hitlag freezes
      // the attacker too, so a crater even three frames later arrives after the victim has already
      // launched. The chop animation is timed to finish on the last startup frame to match.
      //
      // Five steps of 4.2 studs, not seven of 3.6: the old shape advertised 21.6 studs of lethal
      // floor and delivered a 4-damage nudge past the third step. Shorter, and all of it kills.
      crater: { frame: 0, every: 3, count: 5, step: 4.2, radius: 3.4,
        damage: 12, base: 32, growth: 4.4, angle: 64, knockbackMul: 1.5, shieldDamageMul: 3.0 },
    },
  },
};
