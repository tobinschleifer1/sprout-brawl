// BLASTERS - the ranged option, and the only weapon that spends a resource to press buttons.
// Every ranged light costs one round from a six-shot magazine that refills one round every 45
// frames; Full Auto costs one to start plus one per bullet. Run dry and you still have Point Blank
// and Ricochet, which are melee and free. Nimblest movement in the game and the lightest weight, so
// it wins neutral and loses the moment it gets hit at high percent.
//
// Latest kill power on the roster by design: Scattergun at 140% is the honest finisher, and a fully
// charged Overcharge at 129% costs 95 frames of standing still. Full Auto cannot KO - it is
// pressure and an edgeguard tool, not a finisher.
//
// Combo language:
//   Light,Light,Light          Pop Shot, Double Tap, Point Blank   chip from range into a melee end
//   Light,Light+Up / Up+Light  Flak                                anti-air launcher, and the best route
//   Light+Side,Light+Side      Strafe, Kickback                    retreating pressure
//   Down+Light                 Ricochet                            free when the magazine is dry
//
// Signature cash-outs, measured against a dodging victim (CONFIRM = unescapable, trap = a read):
//   Flak        +Heavy      -> Scattergun   CONFIRM  120-260%   trap  20-100%   kills  227%
//   Kickback    +Heavy      -> Scattergun   CONFIRM  140-160%   trap  40-120%   kills  227%
//   Point Blank +Heavy+Down -> Scattergun   CONFIRM  160-260%   trap  60-140%   kills  227%
//   Ricochet    +Heavy      -> Scattergun   trap only     0-40%                 kills  227%
//   Point Blank +Heavy+Side -> Full Auto    trap only   80-260%                 kills  n/a
//
// Overcharge is deliberately absent from the tree: a 24-frame charged beam stays a read.

export default {
  id: 'Blasters', name: 'Blasters', archetype: 'Zoner', tagline: 'Win neutral, pray at 120%',
  blurb: 'Fast, light, ranged. Chips from a distance on a six-round magazine and dies earlier than anything else on the roster.',
  difficulty: 2,
  stats: { set: { weight: 90 }, mul: { runSpeed: 1.06, airSpeed: 1.08, fallSpeed: 0.92 } },
  palette: { primary: '#2F3A4A', secondary: '#C9CFD8', tertiary: '#1A2230', accent: '#FFE9A8', glow: '#FFC44D' },
  trail: '#FFD37A',
  mechanic: { id: 'Spines', max: 6, regenFrames: 45, recoil: 1 },   // a magazine, plus a small thorn on melee contact
  recovery: { kind: 'puff', vy: 46, vx: 32 },        // shortest vertical, longest horizontal: it recovers sideways
  signature: 'SigDown',       // the showcase move has to be one that can actually end a stock

  moves: {
    LightNeutral1: { label: 'Pop Shot', startup: 6, active: 2, recovery: 12, damage: 2, base: 8, growth: 0.5, angle: 40, grounded: true, kind: 'projectile', ammo: 1,
      chains: { neutral: 'LightNeutral2', side: 'LightSide1', up: 'LightUp', down: 'LightDown' },
      projectile: { speed: 70, lifetime: 16, size: [0.8, 0.5], spawnOffset: [2.2, 2.8], shape: 'slug' } },
    LightNeutral2: { label: 'Double Tap', startup: 4, active: 2, recovery: 11, damage: 3, base: 10, growth: 0.7, angle: 40, grounded: true, kind: 'projectile', ammo: 1,
      chains: { neutral: 'LightNeutral3', up: 'LightUp' },
      projectile: { speed: 72, lifetime: 16, size: [0.8, 0.5], spawnOffset: [2.2, 2.8], shape: 'slug' } },
    LightNeutral3: { label: 'Point Blank', startup: 6, active: 3, recovery: 17, damage: 5, base: 16, growth: 1.6, angle: 45, grounded: true, extraHitstun: 5,
      chainsHeavy: { side: 'SigSide', down: 'SigDown' },
      hitboxes: [{ frames: [7, 9], offset: [2.4, 2.7], size: [3.0, 2.4] }] },

    LightSide1: { label: 'Strafe', startup: 7, active: 2, recovery: 10, damage: 3, base: 10, growth: 0.8, angle: 30, grounded: true, kind: 'projectile', ammo: 1,
      chains: { side: 'LightSide2', neutral: 'LightSide2' },
      projectile: { speed: 66, lifetime: 15, size: [0.9, 0.5], spawnOffset: [2.4, 2.8], shape: 'slug' } },
    LightSide2: { label: 'Kickback', startup: 6, active: 3, recovery: 18, damage: 5, base: 18, growth: 2.0, angle: 38, grounded: true, extraHitstun: 5,
      chainsHeavy: 'SigDown',
      hitboxes: [{ frames: [7, 9], offset: [2.8, 2.6], size: [3.4, 2.4] }] },

    LightUp: { label: 'Flak', startup: 7, active: 3, recovery: 14, damage: 4, base: 14, growth: 1.6, angle: 85, grounded: true, extraHitstun: 7,
      chainsHeavy: 'SigDown',
      hitboxes: [{ frames: [8, 10], offset: [1.2, 4.0], size: [3.0, 4.2] }] },
    LightDown: { label: 'Ricochet', startup: 7, active: 4, recovery: 16, damage: 4, base: 12, growth: 1.3, angle: 25, grounded: true, trip: 50, extraHitstun: 9,
      chainsHeavy: 'SigDown',
      hitboxes: [{ frames: [8, 11], offset: [2.6, 0.8], size: [4.0, 1.4] }] },

    AirNeutral: { label: 'Kick Off', startup: 5, active: 3, recovery: 11, landingLag: 6, damage: 5, base: 13, growth: 1.6, angle: 40, grounded: false, fastFallActive: true,
      hitboxes: [{ frames: [6, 8], offset: [0, 2.4], size: [3.8, 3.6] }] },
    AirUp: { label: 'Flak Burst', startup: 8, active: 3, recovery: 13, landingLag: 8, damage: 6, base: 16, growth: 2.2, angle: 86, grounded: false, ammo: 1,
      hitboxes: [{ frames: [9, 11], offset: [0.2, 5.0], size: [3.4, 3.8] }] },
    AirForward: { label: 'Dive Shot', startup: 9, active: 4, recovery: 14, landingLag: 9, damage: 7, base: 18, growth: 2.2, angle: 35, grounded: false,
      hitboxes: [{ frames: [10, 13], offset: [3.0, 2.5], size: [4.0, 2.8] }] },
    AirDown: { label: 'Downdraft', startup: 9, active: 4, recovery: 15, landingLag: 9, damage: 7, base: 18, growth: 2.3, angle: 60, grounded: false, fastFallActive: true,
      hitboxes: [
        { frames: [10, 11], offset: [0.4, -0.6], size: [1.6, 2.0], angle: 275 },
        { frames: [10, 13], offset: [0.4, 1.0], size: [2.0, 2.8] },
      ] },

    SigSide: { label: 'Full Auto', startup: 17, active: 12, recovery: 26, damage: 4, base: 14, growth: 1.4, angle: 32, grounded: true, heavy: true, kind: 'volley', ammo: 1,
      projectile: { speed: 78, lifetime: 18, size: [0.9, 0.5], spawnOffset: [2.6, 2.9], shape: 'slug', count: 4, every: 2 } },
    SigDown: { label: 'Scattergun', startup: 18, active: 4, recovery: 30, damage: 13, base: 32.5, growth: 5.7, angle: 50, grounded: true, heavy: true, lunge: 6,
      hitboxes: [{ frames: [19, 22], offset: [3.6, 1.6], size: [7.2, 3.4] }] },
    SigNeutral: { label: 'Overcharge', startup: 24, active: 5, recovery: 28, damage: 12, base: 26, growth: 4.0, angle: 45, grounded: true, heavy: true, kind: 'beam',
      charge: { maxHold: 75, damage: 16, base: 29, growth: 4.4 },
      hitboxes: [{ frames: [25, 29], offset: [14, 3.0], size: [24, 2.2] }] },

    // ULTIMATE - Deadeye. The blasters fold into a single long-barrelled rifle and paint the
    // nearest fighter red; from that moment you can see them through anything on the stage. Three
    // rounds in the magazine, one per press of the ultimate key, and each one steers itself into
    // the mark - cover does not save them, distance does not save them, only killing the stance
    // (or dying) does. 1.25x knockback each, so three connected rounds is a stock at mid percent.
    // The stance is on a clock: 96 frames, and unspent rounds are simply lost. You keep 40% of
    // your ground speed while it is up - rooting the lightest fighter on the roster in place for
    // two seconds to threaten ONE opponent is a price nobody pays in a four-player match.
    Ultimate: { label: 'Deadeye', startup: 18, active: 96, recovery: 26, damage: 13, base: 30, growth: 3.6, angle: 40,
      heavy: true, kind: 'sniper', ultimate: true, knockbackMul: 1.25, shieldDamageMul: 3.0, walkSpeed: 0.4,
      hitboxes: [],
      // turn 9 is the point where a round reliably runs down a fighter who is already flying from
      // the previous one. At 5.5 the third shot chased a launched victim and expired behind them.
      // `expireAfter` is what keeps that from being a guaranteed edgeguard: the round steers for
      // 40 frames and then flies straight, so DI away from a landed shot can leave the cone.
      sniper: { shots: 3, range: 220, reload: 16, holdAfterLast: 14, setupMul: 0.45,
        projectile: { speed: 78, turn: 9, expireAfter: 75, lifetime: 110, size: [2.2, 0.45], spawnOffset: [2.9, 3.5] } },
    },
  },
};
