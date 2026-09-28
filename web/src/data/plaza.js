// The lobby: a rooftop night market you walk around beat-'em-up style - left and right along the
// street, up and down into the depth of each roof - instead of a side-scrolling corridor.
//
// WHY DEPTH AND NOT TOP-DOWN. Every character in the game is drawn side-on (avatarParts.js), and a
// top-down lobby would need front and back views of every part. A floor seen at an angle, walked in
// x and z with the character facing left or right, is how beat-'em-ups solved the same problem, and
// it lets a player's custom character walk the lobby exactly as it fights.
//
// COORDINATES, in studs. x runs along the street (the camera scrolls with it). z is depth: 0 is the
// front railing, larger is further back. y is height above the floor (a hop). The renderer draws a
// point at screen height y + z * DEPTH, so the floor tilts up away from the viewer.
//
// A scene's `floor` is a union of rectangles you can stand in; `blocks` are footprints you cannot
// (a cabinet, a kiosk). Walking is tested per axis against both, which is what lets a player slide
// along a wall instead of sticking to it. Stations are things you use, each with a reach box; warps
// are named places the warp menu can take you.

export const DEPTH = 0.5;

export const WALK = {
  speedX: 15,       // studs / second along the street
  speedZ: 9,        // into the depth: slower, as in every beat-'em-up, or the floor feels shallow
  accel: 0.3,       // share of the gap to the target speed closed each frame
  stop: 0.02,       // below this a speed is zero, so a released stick settles instead of creeping
  jump: 24,         // hop speed; the lobby hop is cosmetic and crosses nothing
  gravity: 80,
  hz: 60,           // frames a second; dt is 1 / hz, computed in the engine (1/60 needs 17 digits)
};

const R = (x1, x2, z1, z2) => ({ x1, x2, z1, z2 });
// A plank bridge over a gap between roofs: walked like any floor, drawn as planks over the drop.
const BRIDGE = (x1, x2, z1, z2) => ({ x1, x2, z1, z2, bridge: true });

// ------------------------------------------------------------------------ the market ----
// West to east: the tailor's roof (the wardrobe), Neon Square (spawn, notice board, roof map), the
// arcade (numbered cabinets), the crew gates (team fights) and the foot of the Skyline Climb (the
// parkour course, data/parkour.js). Plank bridges cross the gaps.
const CABINET_XS = [108, 128, 148, 168];
const CABINET_ROWS = [6.5, 15.5];
export const CABINETS = [];
CABINET_ROWS.forEach((z, row) => CABINET_XS.forEach((x, col) => CABINETS.push({ number: row * 4 + col + 1, x, z })));

const seats = [];
for (const c of CABINETS) {
  for (const side of [-1, 1]) {
    seats.push({ id: `Cab${c.number}${side < 0 ? 'A' : 'B'}`, name: `CABINET ${String(c.number).padStart(2, '0')}`,
      kind: 'Cabinet', cabinet: c.number, side, x: c.x + side * 5, z: c.z, rx: 2.4, rz: 2.2, facing: -side });
  }
}

export const MARKET = {
  id: 'NeonRow', name: 'Neon Row', kind: 'plaza',
  spawn: { x: 0, z: 6 },
  bounds: { x1: -152, x2: 287 },
  floor: [
    R(-150, -95, 2, 16),       // tailor's roof
    BRIDGE(-96, -84, 7, 11),        // plank bridge
    R(-85, 85, 1, 18),         // Neon Square
    BRIDGE(84, 96, 7, 11),          // plank bridge
    R(95, 185, 2, 20),         // the arcade
    BRIDGE(184, 196, 7, 11),        // plank bridge
    R(195, 240, 2, 17),        // crew gates
    BRIDGE(239, 251, 7, 11),        // plank bridge
    R(250, 285, 2, 16),        // the foot of the climb
  ],
  blocks: [
    R(-4, 4, 12, 16),          // the hologram kiosk in the middle of the square
    ...CABINETS.map((c) => R(c.x - 3, c.x + 3, c.z - 1.2, c.z + 1.2)),
  ],
  districts: [
    { id: 'tailor', name: "TAILOR'S ROOF", x1: -150, x2: -95 },
    { id: 'square', name: 'NEON SQUARE', x1: -85, x2: 85 },
    { id: 'arcade', name: 'THE ARCADE', x1: 95, x2: 185 },
    { id: 'gates', name: 'CREW GATES', x1: 195, x2: 240 },
    { id: 'climb', name: 'SKYLINE CLIMB', x1: 250, x2: 285 },
  ],
  stations: [
    { id: 'Wardrobe', name: 'WARDROBE', landmark: 'CHARACTER STUDIO', kind: 'Wardrobe', x: -122, z: 14, rx: 7, rz: 3.5 },
    { id: 'Board', name: 'NOTICE BOARD', landmark: 'WHO IS HERE', kind: 'Members', x: -40, z: 16.5, rx: 5, rz: 3 },
    { id: 'Map', name: 'ROOF MAP', landmark: 'WARP', kind: 'Warp', x: 40, z: 16.5, rx: 5, rz: 3 },
    ...seats,
    { id: 'Duel', name: '1v1', landmark: 'OPEN ROOM', kind: 'Format', teamSize: 1, x: 202, z: 15.5, rx: 5, rz: 3 },
    { id: 'Doubles', name: '2v2', landmark: 'CREW LIFT', kind: 'Format', teamSize: 2, x: 217, z: 15.5, rx: 5, rz: 3 },
    { id: 'Triples', name: '3v3', landmark: 'FREIGHT LIFT', kind: 'Format', teamSize: 3, x: 232, z: 15.5, rx: 5, rz: 3 },
    { id: 'Climb', name: 'SKYLINE CLIMB', landmark: 'PARKOUR', kind: 'Parkour', x: 268, z: 14.5, rx: 6, rz: 3 },
    { id: 'Records', name: 'CLIMB RECORDS', landmark: 'LEADERBOARDS', kind: 'Records', x: 280.5, z: 14.5, rx: 3.5, rz: 3 },
  ],
  warps: [
    { id: 'tailor', name: "Tailor's Roof", x: -122, z: 8 },
    { id: 'square', name: 'Neon Square', x: 0, z: 6 },
    { id: 'arcade', name: 'The Arcade', x: 138, z: 11 },
    { id: 'gates', name: 'Crew Gates', x: 217, z: 8 },
    { id: 'climb', name: 'Skyline Climb', x: 262, z: 8 },
  ],
};

// ----------------------------------------------------------------------- the rooms ----
// A fight's preparation room: a private rooftop lounge, one per room, with the same stations the old
// bays had. Separate scenes rather than corners of the market, so a room's chatter and its ready
// rail stay with the people in it.
export const FORMAT_STATIONS = MARKET.stations.filter((s) => s.kind === 'Format');
export const ROOMS = {};
for (const gate of FORMAT_STATIONS) {
  ROOMS[gate.id] = {
    id: `Lounge${gate.id}`, name: `${gate.name} · ${gate.landmark}`, kind: 'room', teamSize: gate.teamSize,
    spawn: { x: -30, z: 7 },
    bounds: { x1: -44, x2: 44 },
    floor: [R(-42, 42, 1, 17)],
    blocks: [],
    districts: [{ id: 'lounge', name: 'ROOFTOP LOUNGE', x1: -42, x2: 42 }],
    stations: [
      { id: 'Exit', name: 'NEON ROW', landmark: 'STAIRS DOWN', kind: 'Exit', x: -38, z: 9, rx: 4, rz: 8 },
      { id: 'Maps', name: 'MAP BOARD', kind: 'Maps', x: -20, z: 16, rx: 5, rz: 3 },
      { id: 'Weapons', name: 'WEAPON RACK', kind: 'Weapons', x: -2, z: 16, rx: 5, rz: 3 },
      { id: 'Rules', name: 'RULES + BOTS', kind: 'Rules', x: 16, z: 16, rx: 5, rz: 3 },
      { id: 'Players', name: 'READY RAIL', kind: 'Players', x: 34, z: 16, rx: 5, rz: 3 },
    ],
    warps: [],
  };
}

// ------------------------------------------------------------------------- talking ----
// Quick messages are a fixed list rather than free text, so nothing a player can say through them
// needs filtering, and anyone can use them from a gamepad.
export const MESSAGES = [
  'Hello!', 'GG!', 'One more?', 'Nice!', 'Good luck!', 'Well played!', 'Thanks!', 'Rematch?',
  'Wow!', 'Oops!', 'Let\'s fight!', 'Be right back', 'Want to team up?', 'Close one!',
];

// Stamps: pixel icons that pop over your head. Grids in the weapon-art convention (row 0 on top);
// letters are colours from `ink`.
const S = (id, name, rows, ink) => ({ id, name, rows, ink });
export const STAMPS = [
  S('gg', 'GG', [
    '..kkkkkkkkkk..', '.kyyyyyyyyyyk.', 'kyyyyyyyyyyyyk', 'kyykkkyykkkyyk', 'kykyyyykyyyyyk', 'kykykkykykkkyk',
    'kykyykykyyykyk', 'kyykkkyykkkyyk', 'kyyyyyyyyyyyyk', '.kyyyyyyyyyyk.', '..kkkkkkkkkk..',
  ], { k: '#1B1526', y: '#FFD23A' }),
  S('heart', 'Heart', [
    '.kkk...kkk.', 'krrrk.krrrk', 'krwrrkrrrrk', 'krrrrrrrrrk', '.krrrrrrrk.', '..krrrrrk..', '...krrrk...', '....krk....', '.....k.....',
  ], { k: '#1B1526', r: '#FF4E7A', w: '#FFD0DD' }),
  S('fire', 'Fire', [
    '....k.....', '...kok.k..', '..koyokok.', '.koyyoook.', 'koyyyyyok.', 'koywwyyok.', 'koywwwyok.', '.koywwyok.', '..kooook..', '...kkkk...',
  ], { k: '#1B1526', o: '#FF6A2A', y: '#FFC23A', w: '#FFF3C8' }),
  S('laugh', 'Ha!', [
    '..kkkkkkk..', '.kyyyyyyyk.', 'kyykyyykyyk', 'kyk.kyk.kyk', 'kyyyyyyyyyk', 'kykkkkkkkyk', 'kykwwwwwkyk', 'kyykrrrkyyk', '.kyykkkyyk.', '..kkkkkkk..',
  ], { k: '#1B1526', y: '#FFD23A', w: '#FFFFFF', r: '#E0506A' }),
  S('skull', 'Skull', [
    '..kkkkkk..', '.kwwwwwwk.', 'kwwwwwwwwk', 'kwkkwwkkwk', 'kwkkwwkkwk', 'kwwwkkwwwk', '.kwwwwwwk.', '.kwkwkwkk.', '..kkkkkk..',
  ], { k: '#1B1526', w: '#EDE6D6' }),
  S('what', '?', [
    '..kkkkk..', '.kcccccck', 'kcckkkcck', 'kkk..kcck', '....kcck.', '...kcck..', '...kcck..', '....kk...', '...kcck..', '...kkkk..',
  ], { k: '#1B1526', c: '#5FE0FF' }),
  S('wow', '!', [
    '..kkk..', '.kyyyk.', '.kyyyk.', '.kyyyk.', '.kyyyk.', '..kyk..', '..kyk..', '...k...', '..kkk..', '.kyyyk.', '..kkk..',
  ], { k: '#1B1526', y: '#FF8A3A' }),
  S('thumbs', 'Thumbs up', [
    '....kk.....', '...kssk....', '...kssk....', '..kssskkkk.', 'kkksssssssk', 'kbksssskkk.', 'kbksssssssk', 'kbkssskkkk.', 'kbksssssk..', 'kkkkkkkk...',
  ], { k: '#1B1526', s: '#F2C08E', b: '#4FA0FF' }),
];
