// Player-made characters.
//
// Two things have to be true and neither is visible by looking at the screen:
//
//   1. A CUSTOM AVATAR CANNOT CHANGE HOW YOU PLAY. Avatars are cosmetic by design - the weapon
//      carries the entire stat spread - and a character creator is exactly the feature that would
//      break that quietly. One stray field copied out of a saved JSON blob into the loadout and a
//      player could save themselves a lighter body.
//   2. NOTHING A PLAYER CAN AUTHOR CAN BREAK A MATCH. The save lives in localStorage, which anyone
//      can hand-edit, and it feeds straight into the renderer's paint path.
//
// So these run the real sanitiser against deliberately hostile input, and measure the stats that
// come out of the real loadout builder.
import { buildLoadout } from '../src/data/loadout.js';
import { AVATARS, FEATURES, FEATURE_KEYS, PALETTE_KEYS, avatarById, allAvatars, registerAvatar } from '../src/data/avatars.js';
import { sanitize, blankAvatar, readCustom, writeCustom, saveAvatar, deleteAvatar, importAvatars,
  exportAvatars, initCustomAvatars, readabilityWarning, MAX_CUSTOM, MAX_NAME, STORE_KEY } from '../src/data/customAvatars.js';
import { sanitizeArt, sanitizePart, PART_GRIDS, PART_IDS, INKS, inkColour, blankPart, setCell, cellAt } from '../src/data/pixelArt.js';
import { readFileSync } from 'node:fs';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };

// A store the tests own, so this exercises the real read/write path with no browser.
const fakeStore = () => { const m = new Map(); return { get: (k) => (m.has(k) ? m.get(k) : null), set: (k, v) => { m.set(k, v); return true; }, _m: m }; };

// ---- 1. a custom character cannot change a single stat ----
{
  const STAT = ['weight', 'runSpeed', 'walkSpeed', 'airSpeed', 'jumps', 'jumpVelocity', 'fallSpeed', 'height', 'radius'];
  const store = fakeStore();
  // The nastiest save a player could hand-write: stats, moves and a mechanic smuggled in.
  const cheat = saveAvatar({ name: 'Cheater', weight: 400, runSpeed: 99, height: 12, radius: 4,
    stats: { set: { weight: 400 } }, mul: { runSpeed: 3 }, moves: {}, mechanic: { id: 'Momentum' },
    palette: { primary: '#ff0000', secondary: '#00ff00', tertiary: '#0000ff', accent: '#ffffff', glow: '#ffff00' },
    features: { head: 'tall', face: 'visor', hat: 'crown', torso: 'sash' },
    art: { head: '1'.repeat(144), torso: '2'.repeat(156), arm: 'k'.repeat(70), leg: '3'.repeat(70) } }, store);
  const bad = [];
  for (const w of ['Sword', 'Axe', 'Pike', 'Grimoire']) {
    const preset = buildLoadout('Classic', w), custom = buildLoadout(cheat.avatar.id, w);
    for (const k of STAT) if (preset[k] !== custom[k]) bad.push(`${w}.${k}: preset ${preset[k]} vs custom ${custom[k]}`);
    if (custom.moves !== preset.moves) bad.push(`${w}: the custom avatar changed the moveset`);
    if (custom.mechanic.id !== preset.mechanic.id) bad.push(`${w}: the custom avatar changed the mechanic`);
  }
  check('a custom character changes nothing but how it looks', bad.length === 0,
    bad.length ? bad.join('; ')
      : `a save carrying weight 400, runSpeed 99, height 12, its own moves and a stolen mechanic produced identical stats on four weapons (weight ${buildLoadout(cheat.avatar.id, 'Sword').weight}, run ${buildLoadout(cheat.avatar.id, 'Sword').runSpeed})`);
  deleteAvatar(cheat.avatar.id, store);
}

// ---- 2. the sanitiser survives whatever is in storage ----
{
  const nasty = [
    null, undefined, 42, 'a string', [], { }, { palette: null, features: null },
    { name: '<img src=x onerror=alert(1)>', palette: { primary: 'javascript:void' }, features: { hat: '__proto__' } },
    { id: 'Classic' },                                  // trying to overwrite a preset
    { id: 'custom:../../etc', name: 'x' },
    { name: 'x'.repeat(5000) },
    { palette: { primary: '#GGGGGG', secondary: 3, tertiary: {}, accent: [], glow: '#fff' } },
    { features: { head: 'constructor', face: 1, hat: [], torso: 'toString' } },
  ];
  const problems = [];
  nasty.forEach((raw, i) => {
    let a;
    try { a = sanitize(raw, i); } catch (e) { problems.push(`entry ${i} threw: ${e.message}`); return; }
    if (!a || typeof a.name !== 'string' || !a.name.length) problems.push(`entry ${i}: bad name ${JSON.stringify(a && a.name)}`);
    if (a.name.length > MAX_NAME) problems.push(`entry ${i}: name ${a.name.length} chars`);
    if (/[<>&"']/.test(a.name)) problems.push(`entry ${i}: name kept markup: ${a.name}`);
    if (AVATARS.some((p) => p.id === a.id)) problems.push(`entry ${i}: took a preset id (${a.id})`);
    if (!/^custom:[a-z0-9]+$/i.test(a.id)) problems.push(`entry ${i}: bad id ${a.id}`);
    for (const k of PALETTE_KEYS) if (!/^#[0-9a-f]{6}$/i.test(a.palette[k])) problems.push(`entry ${i}: ${k} = ${a.palette[k]}`);
    for (const k of FEATURE_KEYS) if (!FEATURES[k].some((o) => o.id === a.features[k])) problems.push(`entry ${i}: ${k} = ${a.features[k]}`);
  });
  check('nothing a player can put in storage produces a broken character', problems.length === 0,
    problems.length ? problems.slice(0, 6).join('; ') : `${nasty.length} hostile saves - markup, prototype keys, preset ids, a 5000-character name, wrong types - all became valid plain characters`);
}

// ---- 3. save, reload, and it is still there ----
{
  const store = fakeStore();
  const a = blankAvatar(0);
  a.name = 'Round Two'; a.features.head = 'round'; a.features.hat = 'antenna'; a.palette.primary = '#12ab34';
  const r = saveAvatar(a, store);
  const back = readCustom(store);
  const same = back.length === 1 && back[0].id === r.avatar.id && back[0].name === 'Round Two'
    && back[0].features.head === 'round' && back[0].features.hat === 'antenna' && back[0].palette.primary === '#12ab34';
  // and a second save of the same id updates rather than duplicating
  a.name = 'Round Three';
  saveAvatar({ ...a, id: r.avatar.id }, store);
  const after = readCustom(store);
  check('a character survives a save and a reload', same && after.length === 1 && after[0].name === 'Round Three',
    `saved ${back.length}, reloaded name "${back[0] && back[0].name}" head "${back[0] && back[0].features.head}"; re-saving the same id left ${after.length} character named "${after[0] && after[0].name}"`);
  deleteAvatar(r.avatar.id, store);
}

// ---- 4. the registry resolves a saved character exactly like a preset ----
{
  const store = fakeStore();
  const a = blankAvatar(0); a.name = 'Registry';
  const saved = saveAvatar(a, store).avatar;
  const found = avatarById(saved.id);
  const listed = allAvatars().some((x) => x.id === saved.id);
  deleteAvatar(saved.id, store);
  const gone = avatarById(saved.id).id;
  check('a saved character resolves by id, and a deleted one stops resolving', found.id === saved.id && listed && gone === AVATARS[0].id,
    `avatarById returned "${found.name}" while saved and fell back to "${gone}" after delete; listed in allAvatars: ${listed}`);
}

// ---- 5. storage limits hold ----
{
  const store = fakeStore();
  const made = [];
  for (let i = 0; i < MAX_CUSTOM + 6; i++) { const r = saveAvatar(blankAvatar(i), store); if (r.ok) made.push(r.avatar.id); }
  const held = readCustom(store).length;
  // and an import cannot go over the top either
  const before = readCustom(store).length;
  const imp = importAvatars(exportAvatars([blankAvatar(0), blankAvatar(1)]), store);
  const after = readCustom(store).length;
  for (const id of made) deleteAvatar(id, store);
  check('the store refuses to grow past its limit', held === MAX_CUSTOM && after === before && !imp.ok,
    `${MAX_CUSTOM + 6} saves attempted, ${made.length} accepted, ${held} held; an import on a full store added ${after - before} and reported "${imp.reason}"`);
}

// ---- 6. import always makes copies, never overwrites ----
{
  const store = fakeStore();
  const mine = saveAvatar({ ...blankAvatar(0), name: 'Original' }, store).avatar;
  const r = importAvatars(exportAvatars([mine]), store);
  const list = readCustom(store);
  const ids = new Set(list.map((a) => a.id));
  for (const a of list) deleteAvatar(a.id, store);
  check('importing your own export gives you copies, not an overwrite', r.ok && list.length === 2 && ids.size === 2,
    `re-importing one character left ${list.length} characters with ${ids.size} distinct ids`);
}

// ---- 7. corrupt storage never throws, and never loses what it can still read ----
{
  const JUNK = ['', 'not json', '{}', '[1,2,3]', 'null', 'true', '[{"name":"ok"},null,7]'];
  const threw = [];
  let mixed = null;
  for (const junk of JUNK) {
    const store = fakeStore(); store.set(STORE_KEY, junk);
    try { const list = readCustom(store); if (junk.startsWith('[{')) mixed = list; }
    catch (e) { threw.push(`${JSON.stringify(junk)} threw ${e.message}`); }
  }
  const kept = mixed && mixed.length === 3 && mixed.every((a) => a.name);
  check('corrupt storage degrades instead of throwing', threw.length === 0 && kept,
    threw.length ? threw.join('; ')
      : `${JUNK.length} kinds of junk parsed without throwing; an array of one real character, a null and a number came back as ${mixed.length} valid characters (${mixed.map((a) => a.name).join(', ')})`);
}

// ---- 8. every feature the creator offers is actually drawn ----
// The same dead-data check the stage palettes carry, for the same reason: an option that is
// offered, chosen and then not painted is a player wondering why their hat did nothing.
{
  const art = readFileSync(new URL('../src/render2d/avatar2d.js', import.meta.url), 'utf8');
  const undrawn = [];
  for (const k of FEATURE_KEYS) for (const o of FEATURES[k]) {
    if (!new RegExp(`(^|[^A-Za-z])${o.id}\\s*[(:]`, 'm').test(art)) undrawn.push(`${k}/${o.id}`);
  }
  const counts = FEATURE_KEYS.map((k) => `${k} ${FEATURES[k].length}`).join(', ');
  const combos = FEATURE_KEYS.reduce((n, k) => n * FEATURES[k].length, 1);
  check('every feature the creator offers has drawing code', undrawn.length === 0,
    undrawn.length ? `offered but never painted: ${undrawn.join(', ')}` : `${counts} - ${combos} combinations, all drawn`);
}

// ---- 9. every combination renders without throwing ----
{
  const { Renderer2D } = await import('../src/render2d/renderer2d.js');
  const noop = () => {};
  const stub = () => new Proxy({}, { get(t, p) {
    if (p === 'canvas') return { width: 480, height: 270 };
    if (p === 'createLinearGradient' || p === 'createRadialGradient') return () => ({ addColorStop: noop });
    if (p === 'measureText') return () => ({ width: 10 });
    if (p in t) return t[p];
    return noop;
  }, set(t, p, v) { t[p] = v; return true; } });
  globalThis.document = { createElement: () => ({ getContext: () => stub(), width: 480, height: 270, getBoundingClientRect: () => ({ width: 480, height: 270 }), style: {} }) };
  globalThis.window = { devicePixelRatio: 1 };
  const { posedFighter } = await import('../src/render2d/preview.js');
  const view = new Renderer2D(globalThis.document.createElement('canvas'));
  const ctx = stub();
  let drawn = 0, threw = null;
  outer:
  for (const head of FEATURES.head) for (const face of FEATURES.face) for (const hat of FEATURES.hat) for (const torso of FEATURES.torso) {
    const av = sanitize({ name: 'T', features: { head: head.id, face: face.id, hat: hat.id, torso: torso.id } });
    const L = { ...buildLoadout('Classic', 'Sword'), avatar: av, palette: av.palette };
    for (const [state, moveId] of [['idle', null], ['attack', 'SigSide'], ['attack', 'Ultimate']]) {
      try { view.drawFighterInto(ctx, posedFighter(L, moveId, 12, { state, onGround: true }), 0.4, { ppu: 15, x: 50, y: 90 }); drawn++; }
      catch (e) { threw = `${head.id}/${face.id}/${hat.id}/${torso.id} ${state}: ${e.message}`; break outer; }
    }
  }
  check('every character the creator can build renders', threw === null,
    threw || `${drawn} draws: all ${FEATURES.head.length * FEATURES.face.length * FEATURES.hat.length * FEATURES.torso.length} combinations, idle, mid-signature and mid-ultimate`);
}

// ---- 10. the readability hint fires on the characters it should ----
{
  const invisible = sanitize({ palette: { primary: '#7a7a7a', secondary: '#7b7b7b', tertiary: '#000000', accent: '#ffffff', glow: '#ffffff' } });
  const fine = sanitize({ palette: { primary: '#f2c94c', secondary: '#23232b', tertiary: '#111111', accent: '#ffffff', glow: '#8ed8ff' } });
  check('the readability hint warns about a flat character and stays quiet about a clear one',
    readabilityWarning(invisible) !== null && readabilityWarning(fine) === null,
    `mid-grey on mid-grey: "${readabilityWarning(invisible)}" | yellow on near-black: ${readabilityWarning(fine) === null ? 'no warning' : readabilityWarning(fine)}`);
}


// ---- 11. a hand-drawn grid is rebuilt from known inks, whatever arrives ----
{
  const bad = [];
  const HOSTILE = [null, undefined, 42, [], {}, 'short', 'x'.repeat(9999), '<script>', '1234567890'];
  for (const part of PART_IDS) {
    const want = PART_GRIDS[part].w * PART_GRIDS[part].h;
    for (const raw of HOSTILE) {
      let px;
      try { px = sanitizePart(part, raw); } catch (e) { bad.push(`${part} threw on ${JSON.stringify(raw)}: ${e.message}`); continue; }
      if (px.length !== want) bad.push(`${part}: ${px.length} cells, wanted ${want}`);
      for (const ch of px) if (!INKS.some((i) => i.id === ch)) bad.push(`${part}: unknown ink ${JSON.stringify(ch)}`);
    }
  }
  // a part that is all transparent is the same as not having drawn it
  const dropped = sanitizeArt({ head: blankPart('head'), torso: '2'.repeat(200), nonsense: '111' });
  if (dropped.head) bad.push('an all-transparent part survived as art');
  if (!dropped.torso) bad.push('a drawn torso was dropped');
  if (dropped.nonsense) bad.push('an unknown part name survived');
  if (sanitizeArt('not an object') !== null) bad.push('a non-object art bag survived');
  check('every hand-drawn grid comes back the right size, in real inks', bad.length === 0,
    bad.length ? bad.slice(0, 5).join('; ')
      : `${HOSTILE.length} hostile grids x ${PART_IDS.length} parts - wrong types, a 9999-character string, markup - all rebuilt to exact size; blank parts and unknown part names dropped`);
}

// ---- 12. every ink the editor offers resolves to a colour ----
{
  const pal = AVATARS[0].palette;
  const dead = INKS.filter((i) => i.id !== '.').filter((i) => !/^#[0-9a-f]{6}$/i.test(String(inkColour(i.id, pal))));
  const transparent = inkColour('.', pal);
  check('every drawing ink resolves to a real colour', dead.length === 0 && transparent === null,
    dead.length ? `no colour for: ${dead.map((i) => i.id).join(', ')}`
      : `${INKS.length - 1} inks resolve (${INKS.filter((i) => i.id !== '.').map((i) => i.id + '=' + inkColour(i.id, pal)).join(' ')}), and '.' is transparent`);
}

// ---- 13. a drawing survives the round trip, and recolours with the swatches ----
{
  const store = fakeStore();
  let px = blankPart('head');
  px = setCell(px, 'head', 3, 4, 'k');
  px = setCell(px, 'head', 11, 11, '5');
  px = setCell(px, 'head', 99, 99, 'w');          // out of bounds: must be a no-op, not a crash
  const saved = saveAvatar({ ...blankAvatar(0), name: 'Drawn', art: { head: px } }, store).avatar;
  const back = readCustom(store)[0];
  const ok = back.art && back.art.head === px && cellAt(back.art.head, 'head', 3, 4) === 'k' && cellAt(back.art.head, 'head', 11, 11) === '5';
  // the cell holds an index, not a colour, so moving a swatch repaints the drawing
  const before = inkColour('5', back.palette);
  const recoloured = saveAvatar({ ...back, palette: { ...back.palette, glow: '#00ff88' } }, store).avatar;
  const after = inkColour('5', recoloured.palette);
  deleteAvatar(saved.id, store);
  check('a drawing round-trips, and follows the swatches', ok && before !== after && after === '#00ff88' && recoloured.art.head === px,
    `${px.replace(/\./g, '').length} painted cells survived a save and reload; moving the highlight swatch took ink 5 from ${before} to ${after} without touching the grid`);
}

// ---- 14. the rig still animates a hand-drawn character ----
//
// This is the claim the whole design rests on. A drawn character is NOT a sprite pasted over the
// fighter - it is drawn part by part through the same rig, so every wind-up, lean, squash and
// follow-through still applies to it. Measured by recording the transform each part is blitted
// under and checking it MOVES across a move's frames.
{
  const { Renderer2D } = await import('../src/render2d/renderer2d.js');
  const { posedFighter } = await import('../src/render2d/preview.js');
  // A context that tracks only the current transform, and records where images land.
  function tracer(shots) {
    let m = [1, 0, 0, 1, 0, 0]; const stack = [];
    const mul = (a, b) => [a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1], a[0] * b[2] + a[2] * b[3],
      a[1] * b[2] + a[3] * b[3], a[0] * b[4] + a[2] * b[5] + a[4], a[1] * b[4] + a[3] * b[5] + a[5]];
    const noop = () => {};
    return new Proxy({}, { get(t, p) {
      if (p === 'canvas') return { width: 480, height: 270 };
      if (p === 'save') return () => stack.push(m.slice());
      if (p === 'restore') return () => { m = stack.pop() || m; };
      if (p === 'setTransform') return (...a) => { m = a.slice(0, 6); };
      if (p === 'translate') return (x, y) => { m = mul(m, [1, 0, 0, 1, x, y]); };
      if (p === 'scale') return (x, y) => { m = mul(m, [x, 0, 0, y, 0, 0]); };
      if (p === 'rotate') return (r) => { m = mul(m, [Math.cos(r), Math.sin(r), -Math.sin(r), Math.cos(r), 0, 0]); };
      if (p === 'drawImage') return () => shots.push(m.slice());
      if (p === 'createLinearGradient' || p === 'createRadialGradient') return () => ({ addColorStop: noop });
      if (p === 'measureText') return () => ({ width: 10 });
      if (p in t) return t[p];
      return noop;
    }, set(t, p, v) { t[p] = v; return true; } });
  }
  const art = {};
  for (const part of PART_IDS) art[part] = '1'.repeat(PART_GRIDS[part].w * PART_GRIDS[part].h);
  const av = sanitize({ name: 'Rigged', art });
  const L = { ...buildLoadout('Classic', 'Sword'), avatar: av, palette: av.palette };
  const view = new Renderer2D(globalThis.document.createElement('canvas'));
  const frames = [];
  for (const mf of [1, 12, 22, 30]) {
    const shots = [];
    view.drawFighterInto(tracer(shots), posedFighter(L, 'SigSide', mf, { state: 'attack', onGround: true }), mf / 60, { ppu: 15, x: 100, y: 200 });
    frames.push(shots);
  }
  const drewAll = frames.every((f) => f.length >= 5);       // head, torso, two arms, two legs
  // how far the drawn parts travel between the cocked frame and the contact frame
  const spread = frames[0].length === frames[2].length
    ? frames[0].reduce((s, m, i) => s + Math.abs(m[4] - frames[2][i][4]) + Math.abs(m[5] - frames[2][i][5]), 0) : -1;
  check('the rig animates a hand-drawn character exactly like a built-in one', drewAll && spread > 5,
    !drewAll ? `only ${frames.map((f) => f.length).join('/')} parts blitted per frame - some drawn part is not being drawn`
      : `${frames[0].length} drawn parts per frame; between the cocked frame and contact they move a combined ${spread.toFixed(1)} pixels of transform`);
}

// ---- 15. a hand-drawn character is still cosmetic ----
{
  const store = fakeStore();
  const art = {};
  for (const part of PART_IDS) art[part] = 'k'.repeat(PART_GRIDS[part].w * PART_GRIDS[part].h);
  const drawn = saveAvatar({ name: 'Solid', art, height: 20, weight: 500 }, store).avatar;
  const STAT = ['weight', 'runSpeed', 'airSpeed', 'jumps', 'height', 'radius'];
  const a = buildLoadout('Classic', 'Axe'), b = buildLoadout(drawn.id, 'Axe');
  const diff = STAT.filter((k) => a[k] !== b[k]);
  deleteAvatar(drawn.id, store);
  check('drawing your own character changes no stat either', diff.length === 0,
    diff.length ? `differs on ${diff.join(', ')}` : `a fully hand-drawn character on the Battle Axe: weight ${b.weight}, height ${b.height}, radius ${b.radius} - identical to the preset`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
