// The character kit: parts, codes and the composer.
//
// What has to hold, and cannot be seen by looking at one character:
//   - every option in the catalogue draws something no other option in its category draws, or the
//     creator offers a choice that does nothing;
//   - a code survives the trip through a DataStore, a room and a roster, and garbage in a code
//     degrades into a valid character instead of an error on every client in the match;
//   - a kit character is cosmetic: the loadout's stats are the weapon's, byte for byte;
//   - the rectangles the renderer draws ARE the composed picture (the cut loses nothing), and there
//     are few enough of them to draw six fighters;
//   - a face survives being drawn at half resolution, which is how the game draws it zoomed out.
import { KIT_PARTS, KIT_ROLES, KIT_CATEGORIES, KIT_COLOURS, KIT_PRESETS, DEFAULT_KIT, CODE_LENGTH, OUTLINE,
  encodeKit, decodeKit, canonicalKit, sanitizeKit, isKitCode, kitAvatar, presetKit, partCombinations, colourCombinations } from '../src/data/avatarKit.js';
import { compose, halve, piece, kitSprites, layersOf, resolveRoles, PIECES } from '../src/render2d/avatarCompose.js';
import { buildLoadout } from '../src/data/loadout.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };

// A small deterministic generator, so a failure names a spec that can be rebuilt.
let seed = 12345;
const rnd = (n) => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; };
const randomSpec = () => ({
  parts: Object.fromEntries(KIT_CATEGORIES.map((c) => [c.id, c.options[rnd(c.options.length)].id])),
  colours: Object.fromEntries(KIT_COLOURS.map((c) => [c.id, rnd(c.list.length)])),
});
const withPart = (cat, id) => ({ parts: { ...DEFAULT_KIT.parts, [cat]: id }, colours: { ...DEFAULT_KIT.colours } });
const fingerprint = (g) => PIECES.map((id) => g[id].cells.map((c) => (c ? c.hex : '.')).join(',')).join('|');

// ---- 1. the catalogue is well formed ----
{
  const bad = [];
  const HEX = /^#[0-9A-F]{6}$/;
  for (const cat of KIT_CATEGORIES) {
    if (cat.options.length > 36) bad.push(`${cat.id}: ${cat.options.length} options (a code digit holds 36)`);
    const ids = new Set();
    for (const o of cat.options) {
      if (ids.has(o.id)) bad.push(`${cat.id}.${o.id} twice`);
      ids.add(o.id);
      for (const L of o.layers) {
        const P = KIT_PARTS[L.part];
        if (!P) { bad.push(`${cat.id}.${o.id}: unknown piece ${L.part}`); continue; }
        const w = Math.max(...L.rows.map((r) => r.length));
        if (L.x < 0 || L.y < 0 || L.x + w > P.w || L.y + L.rows.length > P.h) bad.push(`${cat.id}.${o.id}: ${L.part} layer at ${L.x},${L.y} size ${w}x${L.rows.length} leaves the ${P.w}x${P.h} canvas`);
        for (const row of L.rows) for (const ch of row) if (ch !== '.' && !KIT_ROLES[ch]) bad.push(`${cat.id}.${o.id}: unknown colour role '${ch}'`);
      }
    }
  }
  for (const c of KIT_COLOURS) {
    if (c.list.length > 36) bad.push(`${c.id}: ${c.list.length} swatches`);
    for (const h of c.list) if (!HEX.test(h)) bad.push(`${c.id}: ${h}`);
  }
  for (const p of KIT_PRESETS) {
    for (const [k, v] of Object.entries(p.parts)) {
      const cat = KIT_CATEGORIES.find((c) => c.id === k);
      if (!cat || !cat.options.some((o) => o.id === v)) bad.push(`preset ${p.id}: ${k} = ${v} does not exist`);
    }
    for (const [k, v] of Object.entries(p.colours)) {
      const c = KIT_COLOURS.find((x) => x.id === k);
      if (!c || !(v >= 0 && v < c.list.length)) bad.push(`preset ${p.id}: colour ${k} = ${v} does not exist`);
    }
  }
  check('every part, colour and preset in the catalogue is well formed', bad.length === 0,
    bad.length ? bad.slice(0, 8).join('; ') : `${KIT_CATEGORIES.length} categories, ${KIT_CATEGORIES.reduce((n, c) => n + c.options.length, 0)} options, ${KIT_COLOURS.length} colour slots, ${KIT_PRESETS.length} presets: every layer inside its canvas, every letter a known colour`);
}

// ---- 2. over a million characters from the parts alone ----
{
  const n = partCombinations(), cn = colourCombinations();
  check('the parts alone make over a million different characters', n > 1e6,
    `${n.toExponential(2)} part combinations before any colour changes; x ${cn.toExponential(2)} colourings`);
}

// ---- 3. no option is dead ----
{
  const dead = [];
  for (const cat of KIT_CATEGORIES) {
    const seen = new Map();
    for (const o of cat.options) {
      const f = fingerprint(compose(withPart(cat.id, o.id)));
      if (seen.has(f)) dead.push(`${cat.id}: '${o.id}' draws exactly what '${seen.get(f)}' draws`);
      else seen.set(f, o.id);
    }
  }
  check('every option draws something no other option in its category draws', dead.length === 0,
    dead.length ? dead.join('; ') : `${KIT_CATEGORIES.reduce((n, c) => n + c.options.length, 0)} options compared pairwise within their categories on the default character`);
}

// ---- 4. codes ----
{
  const bad = [];
  const specs = [DEFAULT_KIT, ...KIT_PRESETS.map(presetKit)];
  for (let i = 0; i < 400; i++) specs.push(randomSpec());
  for (const s of specs) {
    const code = encodeKit(s);
    if (code.length !== CODE_LENGTH) bad.push(`length ${code.length}`);
    if (!/^k1[0-9a-z]+$/.test(code)) bad.push(`not base 36: ${code}`);
    if (JSON.stringify(decodeKit(code)) !== JSON.stringify(sanitizeKit(s))) bad.push(`${code} does not decode to what encoded it`);
    if (canonicalKit(code.toUpperCase().replace('K1', 'k1')) !== code) bad.push(`${code} is case-sensitive`);
  }
  // Garbage never throws and always lands on a valid character.
  const junk = ['k1', 'k1!!!!!!!!!!!!!!!!!!!!!!!!!!!', 'k1zzzzzzzzzzzzzzzzzzzzzzzzz', 'k1' + '0'.repeat(80), 'k10', 'k1\u0000\u0001', 'k1<script>'];
  for (const j of junk) {
    let out;
    try { out = canonicalKit(j); } catch (e) { bad.push(`${JSON.stringify(j)} threw ${e.message}`); continue; }
    if (j.length <= 64 && (!out || out.length !== CODE_LENGTH)) bad.push(`${JSON.stringify(j)} -> ${out}`);
  }
  for (const not of ['Classic', '', null, 42, {}, 'K2abc', 'k1'.padEnd(65, '0')]) if (isKitCode(not)) bad.push(`${JSON.stringify(not)} taken for a kit code`);
  // A short code keeps what it has and defaults the rest - never "option 0".
  const short = decodeKit(encodeKit(KIT_PRESETS.find((p) => p.id === 'knight') && presetKit(KIT_PRESETS.find((p) => p.id === 'knight'))).slice(0, 6));
  if (short.parts.facialHair !== DEFAULT_KIT.parts.facialHair || short.colours.skin !== DEFAULT_KIT.colours.skin) bad.push('a short code did not default its missing digits');
  if (short.parts.head !== 'square') bad.push('a short code lost a digit it had');
  check('a code round-trips, ignores case, and any garbage decodes to a valid character', bad.length === 0,
    bad.length ? bad.slice(0, 6).join('; ') : `${specs.length} specs round-trip through ${CODE_LENGTH}-character codes; ${junk.length} malformed codes degrade to valid ones; short codes default only what they lack`);
}

// ---- 5. cosmetic only ----
{
  const STAT = ['weight', 'runSpeed', 'walkSpeed', 'airSpeed', 'jumps', 'jumpVelocity', 'fallSpeed', 'height', 'radius'];
  const bad = [];
  for (const p of KIT_PRESETS) for (const w of ['Sword', 'Axe', 'Grimoire']) {
    const a = buildLoadout('Classic', w), b = buildLoadout(encodeKit(presetKit(p)), w);
    for (const k of STAT) if (a[k] !== b[k]) bad.push(`${p.id}/${w}.${k}`);
    if (b.moves !== a.moves) bad.push(`${p.id}/${w} moves`);
    if (!b.avatar.kit) bad.push(`${p.id}: the loadout lost the kit`);
  }
  check('a kit character changes nothing but how it looks', bad.length === 0,
    bad.length ? bad.slice(0, 6).join('; ') : `${KIT_PRESETS.length} presets x 3 weapons: identical stats and the same move tables as a preset avatar`);
}

// ---- 6. clothes stay on the body, hats flatten hair ----
{
  const bad = [];
  const top = KIT_CATEGORIES.find((c) => c.id === 'top'), build = KIT_CATEGORIES.find((c) => c.id === 'build');
  for (const b of build.options) {
    const bare = compose({ parts: { ...DEFAULT_KIT.parts, build: b.id, neck: 'none' }, colours: DEFAULT_KIT.colours });
    const body = bare.torso.cells.map((c) => !!c);
    for (const t of top.options) {
      const g = compose({ parts: { ...DEFAULT_KIT.parts, build: b.id, top: t.id, neck: 'none' }, colours: DEFAULT_KIT.colours });
      g.torso.cells.forEach((c, i) => { if (!!c !== body[i]) bad.push(`${t.id} on ${b.id}: torso cell ${i} ${c ? 'painted off' : 'left bare on'} the body`); });
    }
  }
  const { trim } = layersOf(withPart('headwear', 'cap').parts ? sanitizeKit({ parts: { ...DEFAULT_KIT.parts, headwear: 'cap', hair: 'spiky' } }) : DEFAULT_KIT);
  const hat = compose({ parts: { ...DEFAULT_KIT.parts, headwear: 'cap', hair: 'spiky' }, colours: DEFAULT_KIT.colours });
  const bare = compose({ parts: { ...DEFAULT_KIT.parts, headwear: 'none', hair: 'spiky' }, colours: DEFAULT_KIT.colours });
  const roles = resolveRoles(sanitizeKit(DEFAULT_KIT));
  const hairHex = new Set([roles.h.hex, roles.H.hex, roles.i.hex]);
  let above = 0, bareAbove = 0;
  for (let y = 0; y < trim; y++) for (let x = 0; x < KIT_PARTS.head.w; x++) {
    const i = y * KIT_PARTS.head.w + x;
    if (hat.head.cells[i] && hairHex.has(hat.head.cells[i].hex)) above++;
    if (bare.head.cells[i] && hairHex.has(bare.head.cells[i].hex)) bareAbove++;
  }
  if (!trim) bad.push('the cap trims nothing');
  if (above) bad.push(`${above} hair cells poke through the cap`);
  if (!bareAbove) bad.push('spiky hair has nothing above the cap line to trim, so this proves nothing');
  check('every top fits every build exactly, and a hat flattens the hair under it', bad.length === 0,
    bad.length ? bad.slice(0, 6).join('; ') : `${top.options.length} tops x ${build.options.length} builds paint exactly the body's cells; a cap removes ${bareAbove} cells of spiky hair above row ${trim}`);
}

// ---- 7. the rectangles are the picture ----
{
  const bad = [];
  const paint = (rects, w, h) => {
    const g = Array(w * h).fill(null);
    for (const [c, r, rw, rh, hex] of rects) for (let y = r; y < r + rh; y++) for (let x = c; x < c + rw; x++) {
      if (x < 0 || y < 0 || x >= w || y >= h) bad.push(`rect outside the canvas at ${x},${y}`);
      else g[y * w + x] = hex;
    }
    return g;
  };
  let pieces = 0;
  for (let n = 0; n < 60; n++) {
    const g = compose(n < KIT_PRESETS.length ? presetKit(KIT_PRESETS[n]) : randomSpec());
    for (const id of PIECES) for (const half of [false, true]) {
      const src = half ? halve(g[id]) : g[id];
      const drawn = paint(piece(src), src.w, src.h);
      const at = (x, y) => (x >= 0 && y >= 0 && x < src.w && y < src.h ? src.cells[y * src.w + x] : null);
      for (let y = 0; y < src.h; y++) for (let x = 0; x < src.w; x++) {
        const want = at(x, y) ? at(x, y).hex : (at(x - 1, y) || at(x + 1, y) || at(x, y - 1) || at(x, y + 1) ? OUTLINE : null);
        if (drawn[y * src.w + x] !== want) { bad.push(`${id}${half ? ' (half)' : ''} cell ${x},${y}: drew ${drawn[y * src.w + x]}, the picture is ${want}`); break; }
      }
      pieces++;
    }
  }
  check('the rectangles repaint the composed picture cell for cell, outline included', bad.length === 0,
    bad.length ? bad.slice(0, 5).join('; ') : `${pieces} pieces at full and half resolution repainted from their rectangles match the composed cells exactly`);
}

// ---- 8. a face survives half resolution ----
{
  const bad = [];
  for (const o of KIT_CATEGORIES.find((c) => c.id === 'eyes').options) {
    const spec = sanitizeKit(withPart('eyes', o.id));
    const roles = resolveRoles(spec);
    const face = new Set([roles.e.hex, roles.k.hex, roles.w.hex]);
    const half = halve(compose(spec).head);
    if (!half.cells.some((c) => c && face.has(c.hex))) bad.push(`${o.id} eyes vanish at half resolution`);
  }
  check('every pair of eyes is still there at half resolution', bad.length === 0,
    bad.length ? bad.join('; ') : 'eye, ink and white cells outweigh the skin around them when four cells become one');
}

// ---- 9. few enough rectangles for six fighters ----
{
  let worst = 0, worstHalf = 0, total = 0, totalHalf = 0, who = '';
  const N = 300;
  for (let n = 0; n < N; n++) {
    const spec = n < KIT_PRESETS.length ? presetKit(KIT_PRESETS[n]) : randomSpec();
    const s = kitSprites(spec);
    // The rig draws the arm and the leg twice.
    const count = (k) => PIECES.reduce((t, id) => t + s[id][k].length * (id === 'arm' || id === 'leg' ? 2 : 1), 0);
    const f = count('full'), h = count('half');
    total += f; totalHalf += h;
    if (f > worst) { worst = f; who = encodeKit(spec); }
    worstHalf = Math.max(worstHalf, h);
  }
  check('a character costs at most 260 rectangles, and at most 140 at half resolution', worst <= 260 && worstHalf <= 140,
    `mean ${(total / N).toFixed(0)} (half ${(totalHalf / N).toFixed(0)}), worst ${worst} (${who}) and ${worstHalf} at half, over ${N} characters`);
}

// ---- 10. a kit avatar carries the colours the rest of the game reads ----
{
  const a = kitAvatar(encodeKit(presetKit(KIT_PRESETS.find((p) => p.id === 'punk'))));
  const ok = a && a.kit && ['primary', 'secondary', 'tertiary', 'accent', 'glow'].every((k) => /^#[0-9A-F]{6}$/.test(a.palette[k]));
  check('a kit avatar resolves with a full five-colour palette', !!ok, ok ? `${a.id}: ${Object.values(a.palette).join(' ')}` : JSON.stringify(a));
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
