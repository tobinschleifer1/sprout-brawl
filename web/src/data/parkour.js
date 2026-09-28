// The Skyline Climb: a side-on parkour course over the rooftops, reached from Neon Row.
//
// It is stage data - the same shape as data/stages/*, so StageRuntime runs it (solid blocks with
// grabbable ledges, drop-through ledges, moving and sinking platforms) and the real fighter
// movement climbs it (double jump, ledge grabs, fast fall). What makes it a course is the ROUTE:
// the order of footholds from start to summit, and the CHECKPOINTS on it. Fall below killY and
// you are back on the last checkpoint you reached.
//
// Everyone climbs in the same body: the Sword's stat line (COURSE_WEAPON). Weapons change jump
// height and count - Daggers clear 46 studs where an Axe clears 23 - and a course, and one day its
// rewards, have to be the same course for everybody.
//
// Difficulty is measured, not guessed. test/parkour.test.mjs jumps every step of the route with the
// real engine, trying run-ups, take-off points, double-jump timings and (for moving footholds)
// waits, and requires every step to be possible - and the last stretch, from The Needle to the
// Summit, to be much harder than anything before it: gaps near the very edge of a double jump,
// footholds a stud and a half wide, fast movers and crumbling pillars.

export const COURSE_WEAPON = 'Sword';

// Centre and width rounded to a thousandth: 650.6 - 649.2 is 1.3999999999999773 in floating point,
// which the generated Luau and its JSON check cannot carry exactly.
const r3 = (v) => Math.round(v * 1000) / 1000;
const block = (id, x1, x2, top, extra = {}) => ({ id, x: r3((x1 + x2) / 2), y: top, w: r3(x2 - x1), solid: true, thickness: 4, ...extra });
const ledge = (id, x1, x2, top, extra = {}) => ({ id, x: r3((x1 + x2) / 2), y: top, w: r3(x2 - x1), ...extra });
const sinking = (id, x1, x2, top) => ({ id, x: r3((x1 + x2) / 2), y: top, w: r3(x2 - x1), sinking: true });
const slide = (id, w, top, from, to, period, phase = 0) => ({ id, x: (from + to) / 2, y: top, w, solid: true, thickness: 2, ledges: false, moving: { x: { from, to, period, phase } } });
const lift = (id, x, w, from, to, period, phase = 0) => ({ id, x, y: (from + to) / 2, w, solid: true, thickness: 2, ledges: false, moving: { y: { from, to, period, phase } } });

const PLATFORMS = [
  // 1. Rooftop Access -> Chimney Stack: short hops and steps.
  block('b1', 26, 34, 0), block('b2', 40, 46, 3), block('b3', 52, 58, 6), block('b4', 64, 72, 6),
  block('b5', 80, 86, 2), block('b6', 92, 100, 5),
  block('chimney', 106, 118, 5),
  // 2. -> Crane Arm: sliding girders over a long drop.
  slide('m1', 8, 5, 126, 146, 4), slide('m2', 8, 8, 158, 178, 3.6, 0.5),
  block('crane', 190, 202, 8),
  // 3. -> Water Tower: a zigzag climb of drop-through ledges.
  ledge('s1', 206, 214, 14), ledge('s2', 196, 204, 22), ledge('s3', 206, 214, 30), ledge('s4', 196, 204, 38),
  block('tower', 214, 228, 44),
  // 4. -> Billboard Scaffold: planks that give way if you stand on them.
  sinking('k1', 236, 242, 44), sinking('k2', 250, 256, 46), sinking('k3', 264, 270, 44), sinking('k4', 278, 284, 47),
  block('scaffold', 292, 304, 46),
  // 5. -> Antenna Row: long double jumps between narrow roofs.
  block('a1', 324, 330, 44), block('a2', 350, 356, 48), block('a3', 376, 382, 44),
  block('antenna', 402, 412, 46),
  // 6. -> Skybridge: lifts going up and down; time the jump off each.
  lift('v1', 424, 6, 40, 56, 3), lift('v2', 442, 6, 44, 62, 2.6, 0.3), lift('v3', 460, 6, 50, 66, 2.2, 0.6),
  block('skybridge', 472, 486, 60),
  // 7. -> The Needle: everything so far, tighter.
  block('n1', 510, 514, 60), block('n2', 534, 541, 62), slide('n3', 6, 62, 556, 572, 5),
  block('n4', 588, 594, 64),
  block('needle', 612, 620, 64),
  // 8. -> The Summit. Near the edge of a double jump at every step, on footholds barely wider than
  //    a foot, over a drop that sends you back to The Needle.
  block('f1', 649.2, 650.6, 64, { ledges: false }),
  sinking('f2', 679.3, 681, 66),
  slide('f3', 2, 68, 702, 728, 1.4),
  block('f4', 757, 758.5, 70, { ledges: false }),
  lift('f5', 788, 1.6, 58, 80, 1.1),
  block('f6', 816, 817.2, 72, { ledges: false }),
  block('summit', 846.4, 858, 74, { ledges: false }),
];

export const CHECKPOINTS = [
  { id: 'start', name: 'Rooftop Access', pad: 'main' },
  { id: 'chimney', name: 'Chimney Stack', pad: 'chimney' },
  { id: 'crane', name: 'Crane Arm', pad: 'crane' },
  { id: 'tower', name: 'Water Tower', pad: 'tower' },
  { id: 'scaffold', name: 'Billboard Scaffold', pad: 'scaffold' },
  { id: 'antenna', name: 'Antenna Row', pad: 'antenna' },
  { id: 'skybridge', name: 'Skybridge', pad: 'skybridge' },
  { id: 'needle', name: 'The Needle', pad: 'needle' },
  { id: 'summit', name: 'The Summit', pad: 'summit' },
];

export const COURSE = {
  id: 'SkylineClimb', name: 'Skyline Climb', theme: 'Rooftops at night',
  main: { x1: -20, x2: 20, y: 0, thickness: 6 },
  platforms: PLATFORMS,
  // Far outside everything: falling is decided by killY, not the blast box.
  blast: { left: -400, right: 1300, top: 600, bottom: -400 },
  killY: -30,
  spawns: [0],
  hazards: [],
  // The route: every foothold in order. The test proves each step can be made.
  route: ['main', ...PLATFORMS.map((p) => p.id)],
  checkpoints: CHECKPOINTS,
  palette: {
    ground: '#262B35', groundTop: '#8A94A6', platform: '#6E7788', backdrop: '#3E4450', accent: '#E8A24A',
    sky: '#1A1E26', skyStops: [[0, '#0D1526'], [0.55, '#28364E'], [1, '#5C7084']], glows: [],
  },
};
