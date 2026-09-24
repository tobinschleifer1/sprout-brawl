// A walkable concourse, not an arena and not a screen of menu tabs. Every destination is
// reachable on the main floor; the catwalks are optional movement/play space.
export const HUB = {
  id: 'IronConcourse', name: 'The Iron Concourse', spawn: { x: 0, y: 0 },
  main: { x1: -64, x2: 94, y: 0, thickness: 9 },
  platforms: [
    { id: 'west-crates', x: -8, y: 6, w: 10, soft: true },
    { id: 'west-walk', x: -46, y: 13, w: 20, soft: true },
    { id: 'east-crates', x: 59, y: 6, w: 10, soft: true },
    { id: 'east-walk', x: 80, y: 13, w: 20, soft: true },
  ],
  blast: { left: -84, right: 114, bottom: -40, top: 110 },
  spawns: [0], hazards: [],
  palette: { ground: '#232C35', groundTop: '#89959C', platform: '#4E626A', accent: '#EFB05A' },
  stations: [
    { id: 'Duel', name: '1v1', landmark: 'DUEL FOUNDRY', kind: 'Format', teamSize: 1, x: -28, y: 0, color: '#E5AB65' },
    { id: 'Doubles', name: '2v2', landmark: 'TWIN GANTRY', kind: 'Format', teamSize: 2, x: 14, y: 0, color: '#E5AB65' },
    { id: 'Triples', name: '3v3', landmark: 'FREIGHT HALL', kind: 'Format', teamSize: 3, x: 56, y: 0, color: '#E5AB65' },
  ],
};

// Separate harmless preparation scenes, never arena maps. Generated into Data/Hub with the
// concourse so movement, station reach and collision use one source in both builds.
HUB.rooms = {};
for (const gate of HUB.stations) {
  HUB.rooms[gate.id] = {
    id: `Prep${gate.id}`, name: `${gate.name} · ${gate.landmark}`, teamSize: gate.teamSize,
    spawn: { x: -53, y: 0 }, main: { x1: -74, x2: 72, y: 0, thickness: 9 },
    platforms: [{ id: 'observation', x: 7, y: 12, w: 16, soft: true }],
    blast: { left: -94, right: 92, bottom: -40, top: 110 }, spawns: [-53], hazards: [],
    palette: { ground: '#18212D', groundTop: '#89959C', platform: '#33404F', accent: '#E5AB65' },
    stations: [
      { id: 'Exit', name: 'CONCOURSE', kind: 'Exit', x: -65, y: 0, color: '#E5AB65' },
      { id: 'Maps', name: 'MAP BOARD', kind: 'Maps', x: -40, y: 0, color: '#E5AB65' },
      { id: 'Weapons', name: 'WEAPON RACK', kind: 'Weapons', x: -17, y: 0, color: '#E5AB65' },
      { id: 'Looks', name: 'LOCKERS', kind: 'Looks', x: 6, y: 0, color: '#E5AB65' },
      { id: 'Rules', name: 'RULES + BOTS', kind: 'Rules', x: 29, y: 0, color: '#E5AB65' },
      { id: 'Players', name: 'READY RAIL', kind: 'Players', x: 54, y: 0, color: '#E5AB65' },
    ],
  };
}
