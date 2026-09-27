import assert from 'node:assert/strict';
import { HUB } from '../src/data/hub.js';
import { Lobby } from '../src/engine/lobby.js';
import { buildLoadout } from '../src/data/loadout.js';
import { emptyFrame } from '../src/engine/input.js';

assert.deepEqual(HUB.stations.map(s => [s.name, s.kind, s.teamSize]), [['1v1','Format',1],['2v2','Format',2],['3v3','Format',3],['WARDROBE','Wardrobe',undefined]]);
assert.deepEqual(Object.keys(HUB.rooms), ['Duel', 'Doubles', 'Triples'], 'only fight formats open a preparation room');
for (const target of HUB.stations) {
  const hub = new Lobby(buildLoadout('Classic', 'Sword'));
  for (let n = 0; n < 1000 && Math.abs(hub.fighter.x - target.x) > 1; n++) {
    hub.step({ ...emptyFrame(), x: Math.sign(target.x - hub.fighter.x) });
  }
  assert.equal(hub.nearest()?.id, target.id, `${target.name} must be reachable just by running`);
}
const hub = new Lobby(buildLoadout('Classic', 'Sword'));
let peak = 0;
for (let i = 0; i < 180; i++) {
  hub.step({ ...emptyFrame(), jump: i === 0, jumpHeld: i < 20, light: true, heavy: true, ult: true, guard: true });
  peak = Math.max(peak, hub.fighter.y);
  assert.ok(!['attack', 'ultimate', 'guard'].includes(hub.fighter.state), 'hub movement cannot attack or shield');
}
assert.ok(peak > 6, 'the lobby must actually support jumping');
assert.equal(hub.fighter.y, 0, 'jump lands back on the floor');
for (const direction of [-1, 1]) {
  for (let n = 0; n < 1500; n++) hub.step({ ...emptyFrame(), x: direction });
  assert.ok(hub.fighter.x >= HUB.main.x1 + 3 && hub.fighter.x <= HUB.main.x2 - 3, 'cannot leave lobby bounds');
}
const oldX = hub.fighter.x;
hub.setLoadout(buildLoadout('Noir', 'Hammer'));
assert.equal(hub.fighter.x, oldX, 'changing outfit does not teleport away from the station');
hub.fighter.x = HUB.stations[0].x;
hub.fighter.y = 15;
assert.equal(hub.nearest(), null, 'cannot use a station from the catwalk above it');
console.log('PASS walkable hub: three reachable mode portals, jumping, harmless movement, bounds, loadout continuity');

for (const [format, scene] of Object.entries(HUB.rooms)) {
  assert.equal(scene.teamSize, HUB.stations.find(g => g.id === format).teamSize);
  // No lockers: characters are made at the concourse's wardrobe, once, not per fight.
  assert.deepEqual(scene.stations.map(s => s.id), ['Exit', 'Maps', 'Weapons', 'Rules', 'Players']);
  for (const target of scene.stations) {
    const room = new Lobby(buildLoadout('Classic', 'Sword'), scene);
    assert.equal(room.nearest(), null, 'arrival must not immediately activate a station');
    for (let n = 0; n < 600 && Math.abs(room.fighter.x - target.x) > 1; n++)
      room.step({ ...emptyFrame(), x: Math.sign(target.x - room.fighter.x) });
    assert.equal(room.nearest()?.id, target.id, `${format}/${target.id} reachable without jumping`);
    room.setScene(HUB);
    assert.equal(room.fighter.x, HUB.spawn.x);
    assert.equal(room.fighter.vx, 0, 'scene transfer clears velocity');
    assert.equal(room.data.id, HUB.id);
    room.setScene(scene);
    assert.equal(room.fighter.x, scene.spawn.x);
    for (const direction of [-1, 1]) {
      for (let n = 0; n < 500; n++) room.step({ ...emptyFrame(), x: direction, ult: true, light: true });
      assert.ok(room.fighter.x >= scene.main.x1 + 3 && room.fighter.x <= scene.main.x2 - 3);
      assert.notEqual(room.fighter.state, 'ultimate');
    }
  }
}
console.log('PASS preparation rooms: 18 reachable stations, harmless movement, distinct bounds and scene resets');
