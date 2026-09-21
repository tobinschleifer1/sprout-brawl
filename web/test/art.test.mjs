import assert from 'node:assert/strict';
import { SCENES, WEAPON_DETAILS } from '../src/data/art.js';
import { STAGES } from '../src/data/stages/index.js';
import { WEAPONS } from '../src/data/weapons/index.js';
import { drawArtSky, drawWeaponDetails } from '../src/render2d/art2d.js';

function canvas() {
  return {
    count: 0, stack: 0, globalAlpha: 1,
    save() { this.stack++; }, restore() { this.stack--; }, scale() {},
    createLinearGradient() { return { addColorStop() {} }; },
    fillRect(...values) {
      assert(values.every(Number.isFinite), 'art must not put NaN on the canvas');
      assert(values[2] > 0 && values[3] > 0, 'art rectangles have positive dimensions');
      assert(this.globalAlpha >= 0 && this.globalAlpha <= 1);
      this.count++;
    },
  };
}
assert.deepEqual(Object.keys(SCENES).sort(), STAGES.map(s => s.id).sort());
assert.deepEqual(Object.keys(WEAPON_DETAILS).sort(), WEAPONS.map(w => w.id).sort());
const identities = new Set();
for (const stage of STAGES) {
  const art = SCENES[stage.id];
  assert.equal(art.layers.length, 2, 'every stage has a middle and far distance');
  assert(art.layers[0].parallax < art.layers[1].parallax, 'far scenery moves less than near scenery');
  identities.add(JSON.stringify(art));
  for (const x of [-1000, 0, 1000]) for (const width of [320, 480, 900]) {
    const ctx = canvas();
    assert.equal(drawArtSky(ctx, stage.id, { x }, width, 270), true);
    assert(ctx.count > 60, 'each stage must actually paint its scenery');
    assert(ctx.count < 420, 'wide views retain a bounded scenery draw');
    assert.equal(ctx.stack, 0);
  }
}
assert.equal(identities.size, 6, 'six stages keep six distinct identities');
for (const weapon of WEAPONS) {
  const ctx = canvas();
  drawWeaponDetails(ctx, weapon.id, weapon.palette);
  assert(ctx.count >= 4 && ctx.count <= 8, `${weapon.id} gets meaningful detail without duplicating its entire shape`);
  assert.equal(ctx.stack, 0);
}
console.log('PASS art: six distinct backgrounds at three viewport widths and camera extremes; all twelve weapon details draw');
