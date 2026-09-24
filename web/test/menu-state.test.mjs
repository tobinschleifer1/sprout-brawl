import assert from 'node:assert/strict';
import { Menus } from '../src/ui/menus.js';
globalThis.document = { createElement: () => ({ addEventListener() {} }) };
let saved;
globalThis.localStorage = { getItem: (key) => JSON.stringify(key.endsWith('-settings') ? { music: 'bad', sfx: 99, shake: 'yes' } : saved) };
const build = () => new Menus({ appendChild() {} }, {});
for (const bad of [null, [], { slots: [] }, { slots: [null] }, { mode: {}, slots: [{ weaponId: 'Sword', type: null }] }]) {
  saved = bad;
  const menu = build();
  assert.equal(menu.config.slots.length, 4, 'saved state always has four usable slots');
  assert.equal(menu.config.mode, 'StockFFA');
  assert.equal(menu.config.slots[0].type, 'kb1');
  assert.equal(menu.config.slots[1].type, 'off', 'bots must be explicitly enabled');
  assert.equal(menu.settings.music, 0.6, 'corrupt audio setting falls back');
  assert.equal(menu.settings.sfx, 1, 'volume stays in range');
  assert.equal(menu.settings.shake, true, 'boolean settings remain boolean');
}
saved = { mode: 'TimedTeams', stocks: 4, time: 240, stageId: 'Rooftops', slots: [{ type: 'kb2', weaponId: 'Hammer', avatarId: 'Noir', team: 1 }] };
const menu = build();
assert.equal(menu.config.mode, 'TimedTeams');
assert.equal(menu.config.slots[0].weaponId, 'Hammer');
assert.equal(menu.config.slots[0].type, 'kb2');
assert.equal(menu.config.slots[0].avatarId, 'Noir');
console.log('PASS saved menus: malformed slots and settings recover; valid selections survive');
