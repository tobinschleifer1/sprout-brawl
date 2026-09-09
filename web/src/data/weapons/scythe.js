// SCYTHE - reach and drag. The longest normals in the game and the only weapon whose lights pull
// the victim toward you (`pullVictim`), which turns its reach into real combos instead of poking.
// It pays in mobility: 10% slower on the ground, 8% slower in the air than everything else.
//
// Reaper's Arc is spaced: at weight 100 the tip KOs at 113%, the handle half at 122%. Because Hook
// drags the victim
// inward, cashing out of a combo lands the WEAK half - the tip is only available as a spacing read.
//
// Combo language:
//   Light,Light,Light          Reap, Backreap, Hook            the Hook drags them back into range
//   Light,Light+Up / Up+Light  Uproot                          launcher
//   Light+Side,Light+Side      Wide Swing, Crossreap           max-range poke into a real hit
//   Light+Down                 Ankle Hook                      trips under 70%, drags in
//
// Signature cash-outs, measured against a dodging victim (CONFIRM = unescapable, trap = a read):
//   Uproot     +Heavy      -> Soul Tether     CONFIRM 120-180%   trap  40-100%   kills 145%
//   Crossreap  +Heavy      -> Reaper's Arc    CONFIRM 120-140%   trap  60-100%   kills 113%
//   Hook       +Heavy+Side -> Reaper's Arc    CONFIRM     180%   trap  80-160%   kills 113%
//   Hook       +Heavy+Down -> Harvest         CONFIRM     180%   trap  80-160%   kills 142%
//   Hook       +Heavy      -> Soul Tether     trap only  60-80%                  kills 145%
//   Ankle Hook +Heavy      -> Harvest         trap only   0-60%                  kills 142%
//
// Recovery is a tether, not a jump: it grabs a ledge from 22 studs out, or fails outright.

export default {
  id: 'Scythe', name: 'Scythe', archetype: 'Reach / combo', tagline: 'Nothing is out of range',
  blurb: 'Enormous horizontal reach and hits that drag opponents back to you. Slow enough that a whiff is a free punish for them.',
  difficulty: 3,
  stats: { set: { weight: 96 }, mul: { runSpeed: 0.90, airSpeed: 0.92, fallSpeed: 1.05 } },
  palette: { primary: '#4A3B5C', secondary: '#8E7BA8', tertiary: '#241C30', accent: '#E4DCF0', glow: '#B77DFF' },
  trail: '#C79BFF',
  mechanic: { id: 'Bloom', hitsRequired: 5, windowFrames: 240, durationFrames: 420, cooldownFrames: 540, rangeMul: 1.3, bonusDamage: 3 },
  recovery: { kind: 'tether', range: 22, speed: 70, hopVy: 42 },
  signature: 'SigSide',

  moves: {
    LightNeutral1: { label: 'Reap', startup: 6, active: 2, recovery: 9, damage: 3, base: 10, growth: 0.8, angle: 45, grounded: true,
      chains: { neutral: 'LightNeutral2', side: 'LightSide1', up: 'LightUp', down: 'LightDown' },
      hitboxes: [{ frames: [7, 8], offset: [2.8, 2.6], size: [3.6, 2.2] }] },
    LightNeutral2: { label: 'Backreap', startup: 5, active: 2, recovery: 10, damage: 4, base: 11, growth: 0.9, angle: 45, grounded: true,
      chains: { neutral: 'LightNeutral3', up: 'LightUp', down: 'LightDown' },
      hitboxes: [{ frames: [6, 7], offset: [3.0, 2.6], size: [3.8, 2.2] }] },
    LightNeutral3: { label: 'Hook', startup: 7, active: 3, recovery: 17, damage: 5, base: 15, growth: 1.5, angle: 50, grounded: true, pullVictim: 2.5, extraHitstun: 9,
      chainsHeavy: { neutral: 'SigNeutral', side: 'SigSide', down: 'SigDown' },
      hitboxes: [{ frames: [8, 10], offset: [3.6, 2.5], size: [4.4, 2.6] }] },

    LightSide1: { label: 'Wide Swing', startup: 9, active: 3, recovery: 13, damage: 4, base: 12, growth: 1.1, angle: 35, grounded: true,
      chains: { side: 'LightSide2', neutral: 'LightSide2', up: 'LightUp' },
      hitboxes: [{ frames: [10, 12], offset: [5.0, 2.6], size: [5.6, 2.2] }] },
    LightSide2: { label: 'Crossreap', startup: 7, active: 3, recovery: 19, damage: 6, base: 18, growth: 2.2, angle: 40, grounded: true, pullVictim: 1.5, extraHitstun: 5,
      chainsHeavy: 'SigSide',
      hitboxes: [{ frames: [8, 10], offset: [5.2, 2.6], size: [5.8, 2.4] }] },

    LightUp: { label: 'Uproot', startup: 8, active: 3, recovery: 15, damage: 5, base: 15, growth: 1.7, angle: 82, grounded: true, extraHitstun: 5,
      chainsHeavy: 'SigNeutral',
      hitboxes: [{ frames: [9, 11], offset: [1.8, 4.0], size: [3.4, 4.4] }] },
    LightDown: { label: 'Ankle Hook', startup: 9, active: 4, recovery: 18, damage: 5, base: 12, growth: 1.4, angle: 15, grounded: true, trip: 70, pullVictim: 2, extraHitstun: 9,
      chainsHeavy: 'SigDown',
      hitboxes: [{ frames: [10, 13], offset: [3.4, 0.8], size: [5.4, 1.4] }] },

    AirNeutral: { label: 'Whirl', startup: 9, active: 12, recovery: 15, landingLag: 9, damage: 7, base: 16, growth: 2.0, angle: 50, grounded: false,
      hitboxes: [{ frames: [10, 21], offset: [0, 2.6], size: [5.6, 5.2] }] },
    AirForward: { label: 'Long Reap', startup: 11, active: 4, recovery: 16, landingLag: 11, damage: 8, base: 20, growth: 2.4, angle: 32, grounded: false, pullVictim: 1.5,
      hitboxes: [{ frames: [12, 15], offset: [5.0, 2.6], size: [7.2, 2.8] }] },
    AirUp: { label: 'Skyhook', startup: 10, active: 4, recovery: 16, landingLag: 10, damage: 7, base: 17, growth: 2.4, angle: 86, grounded: false, pullVictim: 1.2,
      hitboxes: [{ frames: [11, 14], offset: [0.6, 5.4], size: [4.2, 5.2] }] },
    AirDown: { label: 'Grave Drop', startup: 14, active: 5, recovery: 20, landingLag: 14, damage: 10, base: 22, growth: 3.0, angle: 60, grounded: false, pullVictim: 2,
      hitboxes: [
        { frames: [15, 16], offset: [0.6, -0.8], size: [2.2, 2.6], angle: 275 },
        { frames: [15, 19], offset: [0.6, 1.0], size: [3.4, 3.6] },
      ] },

    SigSide: { label: "Reaper's Arc", startup: 20, active: 5, recovery: 34, damage: 15, base: 32, growth: 4.5, angle: 42, grounded: true, heavy: true, lunge: 5,
      hitboxes: [
        { frames: [21, 25], offset: [7.6, 2.8], size: [4.2, 4.4], damage: 16, base: 30, growth: 4.5 },  // sweetspot: the tip, KO 100%
        { frames: [21, 25], offset: [4.2, 2.8], size: [7.0, 4.4] },                                     // the handle half
      ] },
    SigDown: { label: 'Harvest', startup: 20, active: 4, recovery: 30, damage: 14, base: 32, growth: 5.1, angle: 70, grounded: true, heavy: true, pullVictim: 3,
      hitboxes: [{ frames: [21, 24], offset: [3.0, 1.2], size: [7.0, 2.8] }] },
    SigNeutral: { label: 'Soul Tether', startup: 19, active: 3, recovery: 29, damage: 12, base: 34, growth: 5.4, angle: 88, grounded: true, heavy: true, pullVictim: 4,
      hitboxes: [{ frames: [20, 22], offset: [1.4, 4.0], size: [4.0, 6.2] }] },

    // ULTIMATE - Soul Harvest. The scythe reaches out and takes hold of the two nearest fighters,
    // drags them off their feet into one point in front of you, and crushes them together into a
    // ball of purple-black energy before it goes off. The detonation carries 1.5x knockback, and
    // because both victims are in the same place they both eat all of it.
    //
    // The hold is escapable, and it has to be. At base 38 this killed two people at 17% through
    // shield, dodge, DI and mash alike - the earliest kill in the game, on a move that hits two
    // targets. Now: mashing pushes you back out of the ball, the stick bends where in it you end
    // up, and clearing 1.6x the burst radius frees you outright. It KOs at 112% at mid weight
    // (90/103/112/129 across the weight classes) - LATER than Reaper's Arc at 122% is not quite
    // true, but close, and that is the right shape for a move that kills two people at once.
    //
    // `range` is 17, not 30, because pullSpeed x holdFrames only covers about 17 studs - a
    // 30-stud reach grabbed distant fighters, gave them a free approach and dropped them next to
    // you having taken nothing.
    Ultimate: { label: 'Soul Harvest', startup: 20, active: 30, recovery: 34, damage: 4, base: 8, growth: 0.2, angle: 60,
      grounded: true, heavy: true, kind: 'vortex', ultimate: true, knockbackMul: 1.5, shieldDamageMul: 3.0,
      hitboxes: [],
      vortex: { targets: 2, range: 17, holdFrames: 26, pullSpeed: 46, orbOffset: [3.4, 3.6],
        escapePerPress: 1.2, escapeCap: 14, diPerFrame: 0.17,
        burst: { damage: 18, base: 26, growth: 3.3, angle: 58, radius: 5.6, knockbackMul: 1.5, shieldDamageMul: 3.0 } },
    },
  },
};
