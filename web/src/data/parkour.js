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
// Twenty levels, each ending on a checkpoint. Levels 19 and 20 - The Razor and The Summit - are
// the hard ones: gaps near the very edge of a double jump onto footholds a stud or so wide, fast
// movers and crumbling pillars. A reward waits at the end of each (REWARDS), for whoever climbed
// there themselves.
//
// Difficulty is measured, not guessed. test/parkour.test.mjs jumps every step of the route with the
// real engine, trying run-ups, take-off points, double-jump timings and (for moving footholds)
// waits, and requires every step to be possible and fair - and levels 19 and 20 to be far harder
// than anything before them.

export const COURSE_WEAPON = 'Sword';

// Centre and width rounded to a thousandth: 650.6 - 649.2 is 1.3999999999999773 in floating point,
// which the generated Luau and its JSON check cannot carry exactly.
const r3 = (v) => Math.round(v * 1000) / 1000;
const block = (id, x1, x2, top, extra = {}) => ({ id, x: r3((x1 + x2) / 2), y: top, w: r3(x2 - x1), solid: true, thickness: 4, ...extra });
const ledge = (id, x1, x2, top, extra = {}) => ({ id, x: r3((x1 + x2) / 2), y: top, w: r3(x2 - x1), ...extra });
const sinking = (id, x1, x2, top) => ({ id, x: r3((x1 + x2) / 2), y: top, w: r3(x2 - x1), sinking: true });
const slide = (id, w, top, from, to, period, phase = 0) => ({ id, x: (from + to) / 2, y: top, w, solid: true, thickness: 2, ledges: false, moving: { x: { from, to, period, phase } } });
const lift = (id, x, w, from, to, period, phase = 0) => ({ id, x, y: (from + to) / 2, w, solid: true, thickness: 2, ledges: false, moving: { y: { from, to, period, phase } } });
// A cable car: along x and y at once, on the same clock.
const car = (id, w, x1, x2, y1, y2, period, phase = 0) => ({ id, x: (x1 + x2) / 2, y: (y1 + y2) / 2, w, solid: true, thickness: 2, ledges: false,
  moving: { x: { from: x1, to: x2, period, phase }, y: { from: y1, to: y2, period, phase } } });
// A foothold with nothing to hang from: the hard levels give no second chance at the edge.
const post = (id, x1, x2, top) => block(id, x1, x2, top, { ledges: false });

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
  // 8. -> The Crest: the old summit run, eased - wider footholds, shorter gaps, slower movers.
  post('f1', 646, 648.6, 64),
  sinking('f2', 673, 676, 66),
  slide('f3', 3, 68, 700, 724, 2),
  post('f4', 750, 752.5, 70),
  lift('f5', 780, 2.4, 58, 80, 1.6),
  post('f6', 806, 808, 72),
  post('crest', 834, 846, 74),
  // 9. -> Signal Mast: a zigzag of drop-through ledges straight up.
  ledge('t1', 850, 857, 80), ledge('t2', 861, 867, 87), ledge('t3', 850, 857, 94), ledge('t4', 861, 867, 101),
  ledge('t5', 850, 857, 108),
  block('mast', 866, 878, 112),
  // 10. -> Freight Line: a chain of sliding girders, each on its own clock.
  slide('r1', 6, 112, 890, 906, 3.2), slide('r2', 5, 114, 920, 938, 2.8, 0.3), slide('r3', 5, 112, 952, 968, 3, 0.6),
  block('depot', 982, 994, 114),
  // 11. -> Cable Cars: cars that ride up and along at once.
  car('c1', 5, 1004, 1016, 110, 120, 3.6), car('c2', 5, 1030, 1044, 116, 128, 3.2, 0.25), car('c3', 5, 1056, 1068, 112, 122, 3, 0.5),
  block('gondola', 1084, 1096, 128),
  // 12. -> Crumbling Terrace: planks that give way, further apart than the first ones.
  sinking('k5', 1105, 1111, 126), sinking('k6', 1121, 1126, 129), sinking('k7', 1135, 1141, 126), sinking('k8', 1151, 1155, 130),
  sinking('k9', 1166, 1170, 127),
  block('terrace', 1180, 1192, 130),
  // 13. -> Lift Shaft: three lifts, each riding higher; leave each near its top.
  lift('l1', 1202, 5, 120, 140, 2.6), lift('l2', 1218, 5, 128, 152, 2.4, 0.3), lift('l3', 1234, 5, 138, 162, 2.2, 0.6),
  block('shaft', 1248, 1260, 158),
  // 14. -> Gantry: long double jumps onto narrow beams.
  post('g1', 1283, 1286, 156), post('g2', 1308, 1311, 160), post('g3', 1333, 1336, 157), post('g4', 1359, 1362, 161),
  block('gantry', 1386, 1396, 160),
  // 15. -> Pendulum Yard: fast sliders, out of step with each other.
  slide('p1', 4, 160, 1408, 1426, 2.2), slide('p2', 4, 163, 1440, 1458, 2, 0.5), slide('p3', 3.5, 160, 1472, 1490, 1.8),
  block('yard', 1504, 1516, 163),
  // 16. -> Stormline: a plank, a slider, a lift and a post in a row.
  sinking('w1', 1528, 1532, 165), slide('w2', 3.5, 167, 1545, 1562, 2), lift('w3', 1578, 3, 158, 176, 1.9), post('w4', 1600, 1603, 172),
  block('storm', 1626, 1638, 174),
  // 17. -> Spire Stairs: small steps, each far above the last.
  post('u1', 1649, 1652, 182), post('u2', 1661, 1664, 190), post('u3', 1673, 1676, 198), post('u4', 1685, 1688, 206),
  post('u5', 1697, 1700, 214),
  block('spire', 1709, 1721, 220),
  // 18. -> Beacon Walk: everything since the Crest, tighter.
  post('e1', 1745, 1747.5, 220), slide('e2', 3, 222, 1770, 1790, 1.7), sinking('e3', 1812, 1815, 224), lift('e4', 1838, 2.5, 214, 232, 1.6),
  block('beacon', 1860, 1870, 230),
  // 19. -> The Razor. Near the edge of a double jump at every step, footholds barely wider than a
  //    foot. The first reward is at the far end of Crown Perch.
  post('x1', 1899.3, 1900.3, 230),
  slide('x2', 2, 232, 1922, 1946, 1.3),
  sinking('x3', 1974, 1975.6, 234),
  lift('x4', 2006, 1, 218, 250, 0.8),
  post('x5', 2032.6, 2033.5, 238),
  post('perch', 2062.5, 2070.5, 241),
  // 20. -> The Summit. Worse. The second reward is on the Summit itself.
  car('y1', 1.2, 2095, 2111, 240, 246, 1),
  post('y2', 2135, 2136.2, 246),
  slide('y3', 1.8, 248, 2161, 2187, 1.2, 0.4),
  sinking('y4', 2215, 2216.4, 250),
  lift('y5', 2247, 1, 234, 264, 0.8),
  post('y6', 2274, 2275, 256),
  post('summit', 2304.8, 2316.8, 259),
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
  { id: 'crest', name: 'The Crest', pad: 'crest' },
  { id: 'mast', name: 'Signal Mast', pad: 'mast' },
  { id: 'depot', name: 'Freight Line', pad: 'depot' },
  { id: 'gondola', name: 'Cable Cars', pad: 'gondola' },
  { id: 'terrace', name: 'Crumbling Terrace', pad: 'terrace' },
  { id: 'shaft', name: 'Lift Shaft', pad: 'shaft' },
  { id: 'gantry', name: 'Gantry', pad: 'gantry' },
  { id: 'yard', name: 'Pendulum Yard', pad: 'yard' },
  { id: 'storm', name: 'Stormline', pad: 'storm' },
  { id: 'spire', name: 'Spire Stairs', pad: 'spire' },
  { id: 'beacon', name: 'Beacon Walk', pad: 'beacon' },
  { id: 'perch', name: 'Crown Perch', pad: 'perch' },
  { id: 'summit', name: 'The Summit', pad: 'summit' },
];

// What waits at the end of the two hard levels: a pickup on the checkpoint's pad, near the edge you
// arrive at and clear of its flag (x, y is where it floats), collected by touching it - by a climber who CLIMBED to that checkpoint, never skipped to
// it. `unlock` is the avatar part it unlocks (data/avatarParts.js).
export const REWARDS = [
  { id: 'skylineCrown', name: 'Skyline Crown', checkpoint: 19, x: 2064.5, y: 243.5, unlock: 'skylineCrown' },
  { id: 'summitMantle', name: 'Summit Mantle', checkpoint: 20, x: 2307, y: 261.5, unlock: 'summitMantle' },
];

export const COURSE = {
  id: 'SkylineClimb', name: 'Skyline Climb', theme: 'Rooftops at night',
  main: { x1: -20, x2: 20, y: 0, thickness: 6 },
  platforms: PLATFORMS,
  // Far outside everything: falling is decided by killY, not the blast box.
  blast: { left: -400, right: 2800, top: 900, bottom: -400 },
  killY: -30,
  // A fall ends this far below your checkpoint's pad, not at the street: from the Summit's height the
  // street is ten seconds of falling. Every foothold of a level sits above its fall line (test).
  fallDepth: 20,
  spawns: [0],
  hazards: [],
  // The route: every foothold in order. The test proves each step can be made.
  route: ['main', ...PLATFORMS.map((p) => p.id)],
  checkpoints: CHECKPOINTS,
  rewards: REWARDS,
  palette: {
    ground: '#262B35', groundTop: '#8A94A6', platform: '#6E7788', backdrop: '#3E4450', accent: '#E8A24A',
    sky: '#1A1E26', skyStops: [[0, '#0D1526'], [0.55, '#28364E'], [1, '#5C7084']], glows: [],
  },
};
