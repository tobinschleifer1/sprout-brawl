// BULLWHIP - the weapon that is only dangerous at one distance.
//
// Agreed with the user (2026-10-10): a tip sweet spot. Every light has two boxes live on the same
// frames - the TIP, far out, which cracks, and the lash nearer in, which barely stings - so the
// whip is all about standing exactly one whip-length away. Its longest light reaches 10 studs, past
// the pike's 9.3, and up close it is the weakest weapon in the game. The tip box is listed first:
// a victim inside both is hit by the tip, because the hitbox scan takes the first that overlaps.
//
// CRACK (the mechanic): a tip hit marks its victim for four seconds; the next tip hit on them
// cracks for more damage and a harder launch, and spends the mark. Mixing ranges cannot cash it -
// only the tip both marks and cracks - and only a tip that LANDS: a shielded one does neither. Being
// hit wipes the whip user's mark; a hit they armour through does not, like every other mechanic.
//
// Signature cash-outs. Both columns are MEASURED in the engine against a victim who spot-dodges on
// their first actionable frame (web/test/combo.test.mjs); neither is derived from frame data.
//   CONFIRM = lands while they are still in hitstun, so there is no escape.
//   trap    = lands on the recovery of the dodge they escaped with. A real option, but a read.
//
//   Bullwhip       +Heavy -> Bullwhip Snap   CONFIRM   20-260%   trap       0%   kills  177%
//   Overhead Crack +Heavy -> Skyfall Crack   CONFIRM    0-260%   trap        -   kills  192%
//   Snapline       +Heavy -> Bullwhip Snap   CONFIRM    0-100%   trap        -   kills  177%
//   Ankle Wrap     +Heavy -> Coil Snap       trap only     0-40%                 kills  224%
//
// Measured from the tip's distance (`spacing`, 6.2 studs) - the whip's strings step in (`lunge`)
// and the backlash hooks them back, so each crack is still at the tip when it lands. Up close the
// same strings open on the lash's sting and fall apart, which is the weapon.

//
// Timed routes (COMBO in config.js), measured in combo.test.mjs the same way: every link pressed
// the moment the previous move lands, the victim dodging on their first actionable frame. The
// finisher only exists at the end of a string linked perfectly all the way - mashed, the string
// stops short of it - and timed air links chase the victim, so mashed air strings fall apart.
//   ROUTE  Flick > Backlash > Bullwhip > Thunderclap   CONFIRM 0-180%   kills 217%
//   ROUTE  Lariat > Air Crack > Falling Crack          CONFIRM 0-140%
//   ROUTE  Snapline, dodge > Long Lash                 CONFIRM 20-100%
//   ROUTE  Overhead Crack, jump > Sky Crack            CONFIRM 220-260%
export default {
  id: 'Whip', name: 'Bullwhip', archetype: 'Sweet-spot spacer', tagline: 'Crack it at the tip',
  blurb: 'Ten studs of braided leather. Only the tip does anything: stay exactly a whip-length away and every crack marks them for a harder one.',
  difficulty: 3,
  stats: { set: { weight: 86 }, mul: { runSpeed: 1.02, airSpeed: 1.0, fallSpeed: 0.97 } },
  palette: { primary: '#8A5A36', secondary: '#5C3A22', tertiary: '#2E1E14', accent: '#E8C58A', glow: '#FFD25A', hilt: '#3A2A1E' },
  trail: '#FFE6A8',
  mechanic: { id: 'Crack', label: 'Crack', markFrames: 240, bonusDamage: 3, launchMul: 1.08 },
  // A whip catches the ledge: a tether, shorter and faster than the chain's.
  recovery: { kind: 'tether', range: 13, speed: 66, hopVy: 50 },
  signature: 'SigSide',
  // Where it fights from: the jab's tip, 6.2 studs out. test/balance.mjs measures its combos from
  // here rather than point-blank, where only the weak lash reaches.
  spacing: 6.2,

  // Thrown (weapon drops): the coiled whip, end over end. Kill power measured in web/test/drops.test.mjs.
  thrown: { speed: 44, vy: 8, gravity: 40, lifetime: 50, damage: 8, base: 28, growth: 6.4, angle: 44, size: [2.4, 1.4] },

  moves: {
    // ---- light string ----
    LightNeutral1: { label: 'Flick', startup: 7, active: 2, recovery: 12, damage: 4, base: 11, growth: 1.0, angle: 30, grounded: true,
      chains: { neutral: 'LightNeutral2', side: 'LightSide1', up: 'LightUp', down: 'LightDown' },
      hitboxes: [
        { frames: [8, 9], offset: [6.2, 2.8], size: [2.4, 1.8], tip: true },
        { frames: [8, 9], offset: [3.2, 2.8], size: [3.6, 1.6], damage: 2, base: 6, growth: 0.4, angle: 50 },
      ] },
    // Backlash: the lash coming back hooks them a step back toward the tip's distance.
    LightNeutral2: { label: 'Backlash', startup: 6, active: 2, recovery: 13, damage: 4, base: 12, growth: 1.1, angle: 36, grounded: true, pullVictim: 1.5, lunge: 1,
      chains: { neutral: 'LightNeutral3', up: 'LightUp', down: 'LightDown' },
      hitboxes: [
        { frames: [7, 8], offset: [6.6, 3.0], size: [2.8, 2.0], tip: true },
        { frames: [7, 8], offset: [3.3, 3.0], size: [3.8, 1.6], damage: 2, base: 6, growth: 0.4, angle: 50 },
      ] },
    LightNeutral3: { label: 'Bullwhip', startup: 9, active: 3, recovery: 18, damage: 6, base: 15, growth: 1.5, angle: 40, grounded: true, lunge: 2, extraHitstun: 12,
      finishers: { neutral: 'Finisher' },
      chainsHeavy: 'SigSide',
      hitboxes: [
        { frames: [10, 12], offset: [7.4, 2.8], size: [3.0, 2.2], tip: true },
        { frames: [10, 12], offset: [3.6, 2.8], size: [4.2, 1.8], damage: 3, base: 8, growth: 0.6, angle: 50 },
      ] },

    LightSide1: { label: 'Long Lash', startup: 10, active: 2, recovery: 15, damage: 5, base: 14, growth: 1.3, angle: 36, grounded: true,
      chains: { side: 'LightSide2', neutral: 'LightNeutral2', up: 'LightUp' },
      hitboxes: [
        { frames: [11, 12], offset: [7.6, 2.6], size: [2.6, 1.8], tip: true },
        { frames: [11, 12], offset: [4.0, 2.6], size: [4.4, 1.6], damage: 2, base: 6, growth: 0.4, angle: 45 },
      ] },
    LightSide2: { label: 'Snapline', startup: 9, active: 3, recovery: 20, damage: 7, base: 18, growth: 2.0, angle: 32, grounded: true, extraHitstun: 10,
      cancels: { dodge: true },
      chainsHeavy: 'SigSide',
      hitboxes: [
        { frames: [10, 12], offset: [8.2, 2.6], size: [3.6, 2.0], tip: true },
        { frames: [10, 12], offset: [3.9, 2.6], size: [5.0, 1.6], damage: 3, base: 7, growth: 0.5, angle: 45 },
      ] },

    // Up, but out at the tip's distance: a crack rising forward, not straight overhead.
    LightUp: { label: 'Overhead Crack', startup: 8, active: 3, recovery: 15, damage: 5, base: 15, growth: 1.8, angle: 80, grounded: true, extraHitstun: 6,
      cancels: { jump: true },
      chainsHeavy: 'SigNeutral',
      hitboxes: [
        { frames: [9, 11], offset: [4.6, 5.8], size: [2.8, 2.8], tip: true },
        { frames: [9, 11], offset: [2.2, 4.0], size: [2.6, 2.4], damage: 2, base: 7, growth: 0.5, angle: 80 },
      ] },
    LightDown: { label: 'Ankle Wrap', startup: 9, active: 3, recovery: 16, damage: 5, base: 12, growth: 1.4, angle: 18, grounded: true, trip: 64, extraHitstun: 7,
      chainsHeavy: 'SigDown',
      hitboxes: [
        { frames: [10, 12], offset: [6.4, 0.7], size: [2.8, 1.4], tip: true },
        { frames: [10, 12], offset: [3.2, 0.7], size: [3.6, 1.2], damage: 2, base: 6, growth: 0.4, angle: 30 },
      ] },

    // ---- aerials ----
    // Lariat: the one move with no tip - the whip whirled round the body, a ring at full length.
    AirNeutral: { label: 'Lariat', startup: 8, active: 9, recovery: 14, landingLag: 9, damage: 4, base: 12, growth: 1.4, angle: 50, grounded: false, extraHitstun: 10,
      chains: { neutral: 'AirForward', side: 'AirForward' },
      hitboxes: [{ frames: [9, 17], offset: [0, 2.8], size: [13.2, 5.6] }] },
    AirForward: { label: 'Air Crack', startup: 8, active: 3, recovery: 16, landingLag: 10, damage: 7, base: 19, growth: 2.3, angle: 38, grounded: false, extraHitstun: 6,
      chains: { down: 'AirDown' }, finishers: { neutral: 'AirFinisher' },
      hitboxes: [
        { frames: [9, 11], offset: [6.4, 2.4], size: [3.0, 2.4], tip: true },
        { frames: [9, 11], offset: [3.4, 2.4], size: [3.6, 1.8], damage: 3, base: 8, growth: 0.6, angle: 45 },
      ] },
    AirUp: { label: 'Sky Crack', startup: 9, active: 3, recovery: 15, landingLag: 9, damage: 7, base: 18, growth: 2.5, angle: 88, grounded: false,
      hitboxes: [
        { frames: [10, 12], offset: [0.8, 7.2], size: [2.4, 2.4], tip: true },
        { frames: [10, 12], offset: [0.6, 4.4], size: [2.2, 2.6], damage: 3, base: 8, growth: 0.6, angle: 85 },
      ] },
    AirDown: { label: 'Downlash', startup: 12, active: 4, recovery: 18, landingLag: 12, damage: 9, base: 18, growth: 2.4, angle: 280, grounded: false,
      hitboxes: [
        { frames: [13, 16], offset: [1.0, -3.4], size: [2.4, 2.4], tip: true },                       // the tip: a spike
        { frames: [13, 16], offset: [0.8, -0.6], size: [2.2, 2.6], damage: 3, base: 9, growth: 0.6, angle: 60 },
      ] },

    // ---- finishers: the end of a string linked perfectly all the way (COMBO, config.js) ----
    Finisher: { label: 'Thunderclap', startup: 8, active: 3, recovery: 26, damage: 9, base: 27, growth: 8.5, angle: 48, grounded: true, finisher: true,
      hitboxes: [
        { frames: [9, 11], offset: [7.4, 3.0], size: [3.2, 2.4], tip: true },
        { frames: [9, 11], offset: [3.8, 3.0], size: [4.0, 2.0], damage: 4, base: 12, growth: 1.2, angle: 50 },
      ] },
    AirFinisher: { label: 'Falling Crack', startup: 12, active: 4, recovery: 22, landingLag: 14, damage: 10, base: 25, growth: 3.4, angle: 300, grounded: false, finisher: true,
      hitboxes: [
        { frames: [13, 16], offset: [5.6, 1.0], size: [3.0, 2.6], tip: true },
        { frames: [13, 16], offset: [2.8, 1.8], size: [3.2, 2.2], damage: 4, base: 10, growth: 0.8, angle: 60 },
      ] },

    // ---- signatures ----
    SigSide: { label: 'Bullwhip Snap', startup: 16, active: 3, recovery: 30, damage: 14, base: 32, growth: 5.0, angle: 38, grounded: true, heavy: true, lunge: 6,
      hitboxes: [
        { frames: [17, 19], offset: [9.6, 3.0], size: [3.6, 3.0], tip: true },
        { frames: [17, 19], offset: [4.8, 2.8], size: [5.4, 2.0], damage: 6, base: 14, growth: 1.4, angle: 45 },
      ] },
    SigDown: { label: 'Coil Snap', startup: 18, active: 4, recovery: 30, damage: 13, base: 31, growth: 5.0, angle: 72, grounded: true, heavy: true,
      hitboxes: [
        { frames: [19, 22], offset: [6.8, 0.8], size: [3.2, 1.8], tip: true },
        { frames: [19, 22], offset: [3.4, 0.8], size: [3.6, 1.6], damage: 5, base: 12, growth: 1.2, angle: 70 },
      ] },
    SigNeutral: { label: 'Skyfall Crack', startup: 15, active: 3, recovery: 28, damage: 13, base: 33, growth: 5.3, angle: 82, grounded: true, heavy: true,
      hitboxes: [
        { frames: [16, 18], offset: [6.4, 6.8], size: [3.6, 4.2], tip: true },
        { frames: [16, 18], offset: [3.0, 4.6], size: [3.0, 3.2], damage: 5, base: 12, growth: 1.2, angle: 84 },
      ] },

    // ULTIMATE - STORM LASH. The whip goes overhead and sweeps, behind to front and back again, at
    // full length: a dome of cracks around the fighter. Its edge is the only dangerous place on
    // the stage - right next to the fighter is safe, which is the whole whip in one move. Each crack
    // chips and pops; the last, out in front, is the one that kills. Built from bursts at the tip's
    // point on the arc (onMoveActiveFrame, `stormlash`).
    Ultimate: { label: 'Storm Lash', startup: 22, active: 66, recovery: 30, damage: 3, base: 6, growth: 0.2, angle: 90,
      grounded: true, heavy: true, kind: 'stormlash', ultimate: true, knockbackMul: 1.3, shieldDamageMul: 3.0,
      hitboxes: [],
      stormlash: { radius: 7.2, height: 2.8, every: 2, perSweep: 8, sweeps: 4, size: 3.6,
        damage: 3, base: 6, growth: 0.2, angle: 90, shieldDamageMul: 3.0,
        final: { damage: 13, base: 27, growth: 4.2, angle: 40, size: 4.4, knockbackMul: 1.25 } },
    },
  },
};
