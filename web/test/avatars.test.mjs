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
    features: { head: 'tall', face: 'visor', hat: 'crown', torso: 'sash' } }, store);
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

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
