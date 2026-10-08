// FISTS - what a fighter has when they hold neither of their two weapons (DROPS in config.js).
//
// Not a weapon anyone picks: it is not in WEAPONS, so no roster, menu or bot ever offers it. It is
// the state between weapons, and it is shaped to make you want to leave it:
//   - quick, so you are never helpless while you go for a drop;
//   - weak, every hit 2-7%, and no move here kills early - the knockback growth of even the heaviest
//     is under half that of any weapon's kill move (test/drops.test.mjs), so a fight is decided by
//     who armed first, not by punching;
//   - no ultimate, no finishers, no weapon mechanic. The meter still fills on fists and waits for
//     a weapon to spend it.
// Its frames lean on the gauntlets', the one weapon that is fists, cut down: shorter strings,
// smaller boxes, a third of the kill power.
export default {
  id: 'Fists', name: 'Fists', archetype: 'Unarmed', tagline: 'Find a weapon',
  blurb: 'Quick and weak. Grab a weapon.',
  difficulty: 1,
  stats: { mul: { runSpeed: 1.06 } },
  palette: { primary: '#E8D2B0', secondary: '#9C7A5A', tertiary: '#5A4636', accent: '#FFF1DC', glow: '#FFE2B8' },
  trail: '#FFE9CC',
  recovery: { kind: 'hop', vy: 62, vx: 22 },
  signature: 'SigNeutral',

  moves: {
    // ---- light string: one two, and that is all ----
    LightNeutral1: { label: 'Jab', startup: 3, active: 2, recovery: 7, damage: 2, base: 6, growth: 0.4, angle: 45, grounded: true,
      cancels: { dodge: true },
      chains: { neutral: 'LightNeutral2' },
      hitboxes: [{ frames: [4, 5], offset: [1.6, 2.9], size: [1.8, 1.5] }] },
    LightNeutral2: { label: 'Cross', startup: 3, active: 2, recovery: 9, damage: 3, base: 9, growth: 0.8, angle: 45, grounded: true,
      cancels: { dodge: true },
      hitboxes: [{ frames: [4, 5], offset: [1.8, 2.9], size: [2.0, 1.5] }] },
    LightSide1: { label: 'Shove', startup: 5, active: 3, recovery: 11, damage: 3, base: 10, growth: 1.0, angle: 35, grounded: true, lunge: 1.2,
      cancels: { dodge: true },
      hitboxes: [{ frames: [6, 8], offset: [1.9, 2.8], size: [2.2, 1.8] }] },
    LightUp: { label: 'Uppercut', startup: 5, active: 3, recovery: 12, damage: 3, base: 11, growth: 1.0, angle: 85, grounded: true,
      cancels: { dodge: true },
      hitboxes: [{ frames: [6, 8], offset: [1.2, 3.4], size: [2.0, 3.0] }] },
    LightDown: { label: 'Sweep', startup: 6, active: 3, recovery: 12, damage: 2, base: 9, growth: 0.8, angle: 20, grounded: true,
      cancels: { dodge: true },
      hitboxes: [{ frames: [7, 9], offset: [1.8, 0.8], size: [2.6, 1.4] }] },

    // ---- aerials ----
    AirNeutral: { label: 'Kick', startup: 5, active: 4, recovery: 10, landingLag: 6, damage: 3, base: 10, growth: 0.9, angle: 48, grounded: false,
      cancels: { dodge: true },
      hitboxes: [{ frames: [6, 9], offset: [0, 2.8], size: [3.4, 3.0] }] },
    AirForward: { label: 'Flying Kick', startup: 6, active: 3, recovery: 11, landingLag: 7, damage: 4, base: 12, growth: 1.1, angle: 40, grounded: false,
      cancels: { dodge: true },
      hitboxes: [{ frames: [7, 9], offset: [1.8, 2.7], size: [2.4, 2.2] }] },
    AirUp: { label: 'Headbutt', startup: 5, active: 3, recovery: 10, landingLag: 6, damage: 3, base: 11, growth: 1.1, angle: 88, grounded: false,
      cancels: { dodge: true },
      hitboxes: [{ frames: [6, 8], offset: [0.4, 4.0], size: [2.2, 3.0] }] },
    AirDown: { label: 'Stomp', startup: 7, active: 4, recovery: 13, landingLag: 9, damage: 4, base: 12, growth: 1.2, angle: 270, grounded: false,
      fastFallActive: true,
      hitboxes: [{ frames: [8, 11], offset: [0.5, -0.6], size: [2.0, 2.6] }] },

    // ---- the heavies: real commitments for unreal rewards ----
    SigSide: { label: 'Shoulder Charge', startup: 12, active: 4, recovery: 24, damage: 6, base: 18, growth: 1.9, angle: 38, grounded: true, heavy: true, lunge: 4,
      hitboxes: [{ frames: [13, 16], offset: [2.2, 2.7], size: [3.0, 2.4] }] },
    SigDown: { label: 'Ground Slam', startup: 14, active: 4, recovery: 26, damage: 6, base: 18, growth: 1.8, angle: 60, grounded: true, heavy: true,
      hitboxes: [{ frames: [15, 18], offset: [1.6, 0.9], size: [4.0, 1.8] }] },
    SigNeutral: { label: 'Haymaker', startup: 13, active: 3, recovery: 26, damage: 7, base: 20, growth: 2.0, angle: 80, grounded: true, heavy: true,
      hitboxes: [{ frames: [14, 16], offset: [1.5, 3.4], size: [2.6, 3.8] }] },
  },
};
