import fs from 'node:fs';
import { Lobby } from '../../web/src/engine/lobby.js';
import { WEAPONS } from '../../web/src/data/weapons/index.js';
import { buildLoadout } from '../../web/src/data/loadout.js';
import { emptyFrame } from '../../web/src/engine/input.js';
import { HUB } from '../../web/src/data/hub.js';
const fields = ['x','y','vx','vy','facing','state','sf','onGround'];
const cases = [HUB, ...Object.values(HUB.rooms)].flatMap(scene => WEAPONS.map(w => {
  const hub = new Lobby(buildLoadout('Classic', w.id), scene);
  const frames = [];
  for (let i = 0; i < 1600; i++) {
    if (i === 800) hub.setScene(scene);
    const input = { ...emptyFrame(), x: i < 800 ? 1 : -1, jump: i % 170 === 0,
      jumpHeld: i % 170 < 25, light: true, heavy: true, ult: true, guard: true };
    hub.step(input);
    frames.push({ input, values: fields.map(k => hub.fighter[k]), near: hub.nearest()?.id ?? '' });
  }
  return { weapon: w.id, scene: scene.id, frames };
}));
fs.writeFileSync(new URL('../tests/hub-fixture.json', import.meta.url), JSON.stringify({ fields, cases }));
console.log('hub trace: twelve weapons × four scenes, 76,800 movement/transition frames');
