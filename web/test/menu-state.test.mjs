import assert from 'node:assert/strict';
import { Menus, mapSet, MAP_SETS, applyPreset, presetOf, portraitPpu } from '../src/ui/menus.js';
import { RULES } from '../src/data/rules.js';
import { STAGES } from '../src/data/stages/index.js';
globalThis.document = { createElement: () => ({ addEventListener() {} }) };
let saved;
globalThis.localStorage = { getItem: (key) => JSON.stringify(key.endsWith('-settings') ? { music: 'bad', sfx: 99, shake: 'yes' } : saved) };
const build = () => new Menus({ appendChild() {} }, {});
for (const bad of [null, [], { slots: [] }, { slots: [null] }, { mode: {}, slots: [{ weaponId: 'Sword', type: null }] }]) {
  saved = bad;
  const menu = build();
  assert.equal(menu.config.slots.length, 8, 'saved state always has eight usable slots');
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
// Map sets and the Random pick: a saved Random and a saved set survive; junk falls back.
saved = { stageId: 'Random', mapSet: 'ranked', slots: [] };
const rnd = build();
assert.equal(rnd.config.stageId, 'Random', 'a saved Random pick survives');
assert.equal(rnd.config.mapSet, 'ranked', 'a saved map set survives');
saved = { stageId: 'Atlantis', mapSet: 'secret', slots: [] };
const junk = build();
assert.equal(junk.config.stageId, 'FoundryFloor', 'an unknown map falls back');
assert.equal(junk.config.mapSet, 'all', 'an unknown map set falls back');
saved = { stageId: 'Undertow', mapSet: 'all', slots: [] };
assert.equal(build().config.stageId, 'FoundryFloor', 'a previously saved unfinished map falls back');
assert.deepEqual(MAP_SETS.map(([id]) => id), ['all', 'ranked']);
assert.equal(mapSet('all').length, STAGES.length - 1, 'all web maps omit the unfinished stage');
assert.ok(mapSet('all').every((s) => s.id !== 'Undertow'), 'Random can never draw Undertow');
const ranked = mapSet('ranked');
assert.ok(ranked.length > 0 && ranked.length < STAGES.length, 'Ranked is a real subset');
assert.ok(ranked.every((s) => s.ranked), 'Ranked holds only ranked maps');
assert.equal(ranked.length, STAGES.filter((s) => s.ranked).length, 'and every ranked map');
// Rule presets: each sets its rules, keeps the free-for-all/teams choice, and is recognised after.
const base = build().config;
for (const p of RULES.presets) {
  for (const mode of ['StockFFA', 'TimedTeams']) {
    const c = applyPreset({ ...base, mode, stageId: 'Smeltworks' }, p.id);
    assert.equal(c.mode.includes('Teams'), mode.includes('Teams'), `${p.id} keeps free-for-all or teams`);
    assert.equal(c.mode.startsWith('Timed'), p.rules.mode === 'timed', `${p.id} sets the mode`);
    for (const k of ['stocks', 'time', 'items', 'disasters', 'mapSet']) assert.equal(c[k], p.rules[k], `${p.id} sets ${k}`);
    assert.equal(presetOf(c), p.id, `${p.id} is recognised once applied`);
    if (p.rules.mapChoice === 'random') assert.equal(c.stageId, 'Random', `${p.id} draws a random map`);
    if (p.rules.mapSet === 'ranked') assert.ok(c.stageId === 'Random' || mapSet('ranked').some((s) => s.id === c.stageId), `${p.id} leaves no map outside its set selected`);
  }
}
assert.equal(presetOf({ ...applyPreset(base, 'tournament'), stocks: 5 }), null, 'one changed rule and no preset applies');
for (const height of [56, 88, 98]) {
  const scale = portraitPpu(17, 180, height, 5.2);
  assert.ok(scale < 17, 'short slot portraits reduce the requested scale');
  assert.ok(height * 0.88 - scale * (5.2 + 1.8) > 0,
    'the whole fighter and raised-weapon allowance fit above the slot border');
}
assert.equal(portraitPpu(15, 300, 142, 5.2), 15, 'a tall portrait keeps its chosen scale');
for (const [k, v] of [['items', true], ['disasters', 'chaos'], ['time', 300], ['mapSet', 'all']]) {
  assert.equal(presetOf({ ...applyPreset(base, 'tournament'), [k]: v }), null, `changing ${k} leaves the preset`);
}
console.log('PASS saved menus: malformed slots and settings recover; valid selections survive; map sets and Random; rule presets');
