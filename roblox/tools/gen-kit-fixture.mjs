// Kit characters through the JavaScript, for tests/kit-parity.luau: codes (good, short and
// malformed), sanitised specs, resolved colours, layer order, and every piece's rectangles at full
// and half resolution, with the far-limb shading.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const K = await import('../../web/src/data/avatarKit.js');
const C = await import('../../web/src/render2d/avatarCompose.js');

let seed = 99;
const rnd = (n) => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; };
const randomSpec = () => ({
  parts: Object.fromEntries(K.KIT_CATEGORIES.map((c) => [c.id, c.options[rnd(c.options.length)].id])),
  colours: Object.fromEntries(K.KIT_COLOURS.map((c) => [c.id, rnd(c.list.length)])),
});

const specs = [K.DEFAULT_KIT, ...K.KIT_PRESETS.map(K.presetKit)];
for (let i = 0; i < 40; i++) specs.push(randomSpec());
// Every option of every category at least once, on the default character.
for (const cat of K.KIT_CATEGORIES) for (const o of cat.options) specs.push({ parts: { ...K.DEFAULT_KIT.parts, [cat.id]: o.id }, colours: K.DEFAULT_KIT.colours });

const junk = ['k1', 'k10', 'k1zzzzzzzzzzzzzzzzzzzzzzzzz', 'K1abc', 'k1ABCDEF', 'k1!!!!', 'k1' + '0'.repeat(62), 'k1' + '0'.repeat(63),
  'Classic', '', 'k1\u0001\u0002', 'k1-1-1-1'];
const codes = [...specs.map((s) => K.encodeKit(s)), ...junk].map((input) => ({
  input, isCode: K.isKitCode(input), canonical: K.canonicalKit(input) ?? false, spec: K.decodeKit(input) ?? false,
}));

// Sanitising what a client could send as a table.
const raws = [null, 42, 'x', [], {}, { parts: null, colours: 'no' }, { parts: { hair: 'nonsense', eyes: 'wink' }, colours: { skin: 99, hair: -1, eyes: 2.5, top: 3 } },
  { parts: { head: 'constructor', top: 'toString' } }, randomSpec()];
const sanitized = raws.map((raw) => ({ raw: raw ?? false, spec: K.sanitizeKit(raw) }));

const sprites = specs.map((s) => {
  const code = K.encodeKit(s);
  const sp = C.kitSprites(s);
  const { layers, trim } = C.layersOf(K.sanitizeKit(s));
  return { code, palette: K.kitPalette(K.sanitizeKit(s)), roles: Object.fromEntries(Object.entries(C.resolveRoles(K.sanitizeKit(s))).map(([k, v]) => [k, v.hex])),
    order: layers.map((L) => `${L.part}:${L.z}:${L.x}:${L.y}`), trim, pieces: sp, farArm: C.shadeRects(sp.arm.full), farLegHalf: C.shadeRects(sp.leg.half) };
});

fs.writeFileSync(path.join(HERE, '../tests/kit-fixture.json'), JSON.stringify({ codes, sanitized, sprites, combos: String(K.partCombinations()) }));
console.log(`kit fixture: ${codes.length} codes, ${sprites.length} characters`);
