// The pixel-art weapons: that each one exists, reaches as far as it hits, compiles to exactly the
// picture its grid describes, and stays inside the Frame budget Roblox draws it with.
import assert from 'node:assert/strict';
import { GRIDS, WEAPON_SPRITES, AWAKENED_SPRITES, AURA_ALPHA, OUTLINE, PX, paint, paintAwakened, compile, forwardExtent } from '../src/data/weaponArt.js';
import { WEAPONS } from '../src/data/weapons/index.js';
import { drawSprite, drawWeapon } from '../src/render2d/weapons2d.js';

// How far forward of the grip each weapon's previous polygon shape reached, in studs - measured
// from the shapes this art replaced (render2d/weapons2d.js before the pixel-art revision). Players
// judge reach by eye, so the new art has to land within one pixel of the old.
const OLD_REACH = { Sword: 2.35, Scythe: 3.84, Blasters: 0.92, Grimoire: 0.78, Axe: 3.4, Pike: 5.95,
  Gauntlets: 0.94, Hammer: 3.72, Longbow: 1.02, Flail: 4.56, Shield: 0.72, Daggers: 1.5 };
// Rectangles are Frames in Roblox. The ceiling was 80 while Roblox re-placed every rectangle of
// every weapon every frame. Since the lobby lag work, a weapon is ONE sprite there - a container
// Frame moved per frame, its rectangles built once - so detail now costs memory and a one-off build,
// not per-frame work, and the shaded redraw (bevels, wraps, gems) is allowed half as much again.
// The web draws each rectangle with fillRect, and 120 a weapon is nothing to a canvas.
const FRAME_BUDGET = 120;
// The awakened form adds a glowing ring and an aura round the same weapon.
const AWAKENED_BUDGET = 140;

assert.deepEqual(Object.keys(WEAPON_SPRITES).sort(), WEAPONS.map((w) => w.id).sort(), 'every weapon in the game has art');

let total = 0;
for (const w of WEAPONS) {
  const rects = WEAPON_SPRITES[w.id];
  const reach = forwardExtent(GRIDS[w.id]);
  assert(Math.abs(reach - OLD_REACH[w.id]) <= PX + 1e-9, `${w.id} reaches ${reach} studs, its hitboxes were drawn to ${OLD_REACH[w.id]}`);
  assert(rects.length <= FRAME_BUDGET, `${w.id} compiles to ${rects.length} rectangles, over the ${FRAME_BUDGET} budget`);
  total += rects.length;

  // The outline halo is drawn first, so the weapon always paints over it.
  const firstBody = rects.findIndex((r) => r[4] !== OUTLINE);
  assert(rects.slice(firstBody).every((r) => r[4] !== OUTLINE), `${w.id}: outline rectangles must all come first`);

  for (const [x, y, rw, rh, colour, a] of rects) {
    for (const v of [x, y, rw, rh]) assert(Number.isFinite(v), `${w.id}: non-finite geometry`);
    assert(rw > 0 && rh > 0, `${w.id}: empty rectangle`);
    for (const v of [x, y, rw, rh]) assert(Math.abs(v / PX - Math.round(v / PX)) < 1e-6, `${w.id}: off the pixel grid`);
    assert(/^#[0-9A-F]{6}$/i.test(colour), `${w.id}: colour ${colour} is not a hex colour`);
    assert(colour.toUpperCase() !== '#FF00FF', `${w.id}: an ink resolved to the missing-colour magenta`);
    assert(a > 0 && a <= 1);
  }

  // No two rectangles in the same layer overlap. Overlap is invisible in the colour check below,
  // but the outline is drawn at 0.9 alpha and two overlapping outline rectangles come out darker.
  const layers = [rects.filter((r) => r[4] === OUTLINE), rects.filter((r) => r[4] !== OUTLINE)];
  for (const layer of layers) {
    const seen = new Set();
    let painted = 0;
    for (const [x, y, rw, rh, colour] of layer) {
      const c0 = Math.round(x / PX), r0 = Math.round(y / PX);
      for (let r = r0; r < r0 + Math.round(rh / PX); r++) for (let c = c0; c < c0 + Math.round(rw / PX); c++) {
        const k = colour + '@' + c + ',' + r;
        assert(!seen.has(k), `${w.id}: two ${colour} rectangles overlap at (${c},${r})`);
        seen.add(k); painted++;
      }
    }
  }

  // Replaying the rectangles in order must reproduce the painted grid cell for cell. This is the
  // test that catches a merge that overlaps, drops or recolours a pixel.
  const p = paint(GRIDS[w.id], w.palette);
  const got = Array.from({ length: p.h }, () => Array(p.w).fill(null));
  for (const [x, y, rw, rh, colour] of rects) {
    const c0 = Math.round(x / PX) + p.ox, r0 = Math.round(y / PX) + p.oy;
    for (let r = r0; r < r0 + Math.round(rh / PX); r++) for (let c = c0; c < c0 + Math.round(rw / PX); c++) got[r][c] = colour;
  }
  for (let r = 0; r < p.h; r++) for (let c = 0; c < p.w; c++) {
    assert.equal(got[r][c], p.cell[r][c] || p.halo[r][c], `${w.id}: pixel (${c},${r}) reproduced wrongly`);
  }
}

// THE AWAKENED FORMS. Light is only ever added round the outside: the weapon's own pixels are
// untouched (save glow inlays, which run white-hot), so reach and grip are the everyday weapon's.
for (const w of WEAPONS) {
  const rects = AWAKENED_SPRITES[w.id];
  assert(rects && rects.length <= AWAKENED_BUDGET, `${w.id}: awakened art missing or ${rects?.length} rectangles, over ${AWAKENED_BUDGET}`);
  const a = paintAwakened(GRIDS[w.id], w.palette);
  const p = paint(GRIDS[w.id], w.palette);
  const glow = (w.palette.glow || w.palette.accent).toUpperCase();
  for (let r = 0; r < p.h; r++) for (let c = 0; c < p.w; c++) {
    const was = p.cell[r][c], now = a.cell[r + 1][c + 1];
    assert.equal(now, was && was.toUpperCase() === glow ? '#FFFFFF' : was, `${w.id}: awakened body pixel (${c},${r}) moved or changed`);
  }
  assert.equal(a.ox, p.ox + 1); assert.equal(a.oy, p.oy + 1);
  // The ring hugs the silhouette and the aura hugs the ring: every ring pixel touches the body,
  // every aura pixel touches the ring and not the body.
  const touches = (g, r, c) => [[-1, 0], [1, 0], [0, -1], [0, 1]].some(([dr, dc]) => g[r + dr]?.[c + dc]);
  let rings = 0;
  for (let r = 0; r < a.h; r++) for (let c = 0; c < a.w; c++) {
    if (a.ring[r][c]) { rings++; assert(!a.cell[r][c] && touches(a.cell, r, c), `${w.id}: ring pixel off the silhouette`); }
    if (a.aura[r][c]) assert(!a.cell[r][c] && !a.ring[r][c] && touches(a.ring, r, c) && !touches(a.cell, r, c), `${w.id}: aura pixel misplaced`);
    if (!a.cell[r][c] && touches(a.cell, r, c)) assert(a.ring[r][c], `${w.id}: a gap in the glowing outline at (${c},${r})`);
  }
  assert(rings > 0);
  // Replayed in order, the rectangles reproduce aura, ring and body exactly, at their own alphas.
  const got = Array.from({ length: a.h }, () => Array(a.w).fill(null));
  for (const [x, y, rw, rh, colour, alpha] of rects) {
    const c0 = Math.round(x / PX) + a.ox, r0 = Math.round(y / PX) + a.oy;
    for (let r = r0; r < r0 + Math.round(rh / PX); r++) for (let c = c0; c < c0 + Math.round(rw / PX); c++) got[r][c] = colour + '@' + alpha;
  }
  for (let r = 0; r < a.h; r++) for (let c = 0; c < a.w; c++) {
    const want = a.cell[r][c] ? a.cell[r][c] + '@1' : a.ring[r][c] ? a.ring[r][c] + '@1' : a.aura[r][c] ? a.aura[r][c] + '@' + AURA_ALPHA : null;
    assert.equal(got[r][c], want, `${w.id}: awakened pixel (${c},${r}) reproduced wrongly`);
  }
}

// The draw path: exactly one fillRect per rectangle, and the caller's alpha restored afterwards.
const ctx = { calls: 0, globalAlpha: 0.5, fillStyle: null, stack: 0, fillRect() { this.calls++; },
  save() { this.stack++; }, restore() { this.stack--; }, rotate() {}, translate() {}, scale() {} };
// Drawn at a fractional alpha, because at alpha 1 the last rectangle happens to set globalAlpha
// back to the caller's value by itself and a leak would go unseen.
assert.equal(drawSprite(ctx, 'Sword', 0.3), true);
assert.equal(ctx.calls, WEAPON_SPRITES.Sword.length);
assert.equal(ctx.globalAlpha, 0.5, 'drawSprite must leave globalAlpha as it found it');
assert.equal(drawSprite(ctx, 'Nothing'), false);
ctx.calls = 0;
drawWeapon(ctx, 'Axe', {}, { angle: 0, ox: 0, oy: 0, scale: 1, charge: 0, hide: true });
assert.equal(ctx.calls, 0, 'a hidden weapon draws nothing');
drawWeapon(ctx, 'Axe', {}, { angle: 0, ox: 0, oy: 0, scale: 1, charge: 0, hide: false });
assert.equal(ctx.calls, WEAPON_SPRITES.Axe.length);
assert.equal(ctx.stack, 0);

// Deterministic: compiling twice gives identical rectangles, so the generated Luau is stable.
assert.deepEqual(compile(GRIDS.Flail, WEAPONS.find((w) => w.id === 'Flail').palette), WEAPON_SPRITES.Flail);

console.log(`PASS weapon art: 12 weapons within one pixel of their reach, pixel-exact merges, ${total} rectangles (${(total / 12).toFixed(1)} a weapon, budget ${FRAME_BUDGET}); awakened forms add light only, pixel-exact`);
