// Emit the Luau data layer from the JavaScript, and a JSON fixture to check the emitter against.
//
//     node tools/gen-data.mjs
//
// web/src/data/**.js is the SOURCE OF TRUTH for weapons, avatars, stages and items. Those files
// are pure data with no functions, no nulls and no shared references (the generator asserts all
// three), so they translate mechanically - and generating them means the Roblox build cannot drift
// from the web build the way the knockback port silently did. Nothing under src/shared/Data is
// hand-editable: change the JavaScript and re-run.
//
// check.sh runs this first, every time.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// fileURLToPath, not URL.pathname: this repo's directory has a space in it, and pathname hands
// back "roblox%202d%20fighting%20game".
const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(HERE, '../src/shared/Data');
const WEB = '../../web/src/data';  // relative to THIS file, not to the cwd

const { WEAPONS, DEFAULT_WEAPON } = await import(`${WEB}/weapons/index.js`);
const { AVATARS, BASE, DEFAULT_AVATAR } = await import(`${WEB}/avatars.js`);
const { STAGES } = await import(`${WEB}/stages/index.js`);
const { ITEM_LIST } = await import(`${WEB}/items.js`);
const { buildLoadout } = await import(`${WEB}/loadout.js`);

// ---------------------------------------------------------------- emitter ----
const RESERVED = new Set(['and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function',
  'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while']);
const IDENT = /^[A-Za-z_][A-Za-z0-9_]*$/;

function luaKey(k) {
  return IDENT.test(k) && !RESERVED.has(k) ? k : `[${luaString(k)}]`;
}

function luaString(s) {
  // UTF-8 passes through a Luau source file unharmed; only quotes, backslashes and control
  // characters have to be escaped.
  let out = '"';
  for (const ch of String(s)) {
    const c = ch.codePointAt(0);
    if (ch === '"') out += '\\"';
    else if (ch === '\\') out += '\\\\';
    else if (ch === '\n') out += '\\n';
    else if (ch === '\r') out += '\\r';
    else if (ch === '\t') out += '\\t';
    else if (c < 0x20 || c === 0x7f) out += `\\${String(c).padStart(3, '0')}`;
    else out += ch;
  }
  return out + '"';
}

function luaNumber(n, where) {
  if (!Number.isFinite(n)) throw new Error(`${where}: ${n} is not finite`);
  // String(n) is the shortest representation that round-trips through an IEEE-754 double, and
  // Luau parses decimal literals into the same doubles, so this is exact rather than approximate.
  return Object.is(n, -0) ? '-0' : String(n);
}

function emit(v, indent, where) {
  if (v === null || v === undefined) throw new Error(`${where}: ${v} has no Luau equivalent (nil in a table is absence)`);
  const t = typeof v;
  if (t === 'function') throw new Error(`${where}: functions cannot be generated - this is data only`);
  if (t === 'number') return luaNumber(v, where);
  if (t === 'boolean') return v ? 'true' : 'false';
  if (t === 'string') return luaString(v);
  if (t !== 'object') throw new Error(`${where}: unsupported type ${t}`);

  const pad = '\t'.repeat(indent + 1), close = '\t'.repeat(indent);
  if (Array.isArray(v)) {
    if (v.length === 0) return '{}';
    // Luau arrays are 1-INDEXED. Anything porting engine code that indexes hitboxes[0] has to
    // shift; the data-parity test compares JS index i against Luau index i + 1 for exactly this.
    const scalarsOnly = v.every((x) => x === null || typeof x !== 'object');
    if (scalarsOnly && v.length <= 8) return `{ ${v.map((x, i) => emit(x, 0, `${where}[${i}]`)).join(', ')} }`;
    return `{\n${v.map((x, i) => pad + emit(x, indent + 1, `${where}[${i}]`)).join(',\n')},\n${close}}`;
  }
  const keys = Object.keys(v);           // insertion order, so the output is stable across runs
  if (keys.length === 0) return '{}';
  return `{\n${keys.map((k) => `${pad}${luaKey(k)} = ${emit(v[k], indent + 1, `${where}.${k}`)}`).join(',\n')},\n${close}}`;
}

// Lune's JSON decoder keeps about 16 significant digits, so a value that needs 17 to round-trip
// comes back one ulp out and the parity test compares the wrong number. Every literal in the
// JavaScript data is hand-written and short, so this holds today - it is asserted so that it
// cannot stop holding silently.
const survivesJson = (n) => Number(n.toPrecision(16)) === n;

// The three properties that make this translation mechanical, asserted rather than assumed.
function assertPlain(root, where) {
  const seen = new Set();
  const walk = (v, p) => {
    if (v === null) throw new Error(`${p} is null`);
    const t = typeof v;
    if (t === 'function') throw new Error(`${p} is a function`);
    if (t === 'undefined') throw new Error(`${p} is undefined`);
    if (t === 'number' && !survivesJson(v)) {
      throw new Error(`${p} = ${v} needs 17 significant digits, which the JSON fixture cannot carry `
        + `(Lune's decoder rounds it). Emit it as a string the way the loadout stats are.`);
    }
    if (t !== 'object') return;
    if (seen.has(v)) throw new Error(`${p} is a shared or cyclic reference`);
    seen.add(v);
    if (Array.isArray(v)) v.forEach((x, i) => walk(x, `${p}[${i}]`));
    else for (const [k, x] of Object.entries(v)) walk(x, `${p}.${k}`);
  };
  walk(root, where);
}

const HEADER = (source) => `--!nocheck
-- GENERATED FILE - DO NOT EDIT.
--
-- Emitted from ${source} by roblox/tools/gen-data.mjs, which check.sh runs on every invocation.
-- Edit the JavaScript and re-run; anything typed in here is overwritten without warning.
--
-- \`--!nocheck\` because this is a literal data table with no logic in it: strict mode would
-- produce thousands of inferred-shape errors and check nothing that tests/data-parity.luau does
-- not already check field by field against the JavaScript.
`;

function write(file, source, body) {
  const p = path.join(OUT, file);
  fs.writeFileSync(p, `${HEADER(source)}\n${body}\n`);
  return `${file} (${(fs.statSync(p).size / 1024).toFixed(1)} KB)`;
}

// ---------------------------------------------------------------- modules ----
const written = [];

assertPlain(WEAPONS, 'WEAPONS');
written.push(write('Weapons.luau', 'web/src/data/weapons/*.js', `local WEAPONS = ${emit(WEAPONS, 0, 'WEAPONS')}

-- Built here rather than emitted so the lookup holds the SAME tables as the list, which is what
-- WEAPON_BY_ID does in the JavaScript.
local BY_ID = {}
for _, w in WEAPONS do
	BY_ID[w.id] = w
end

return { LIST = WEAPONS, BY_ID = BY_ID, DEFAULT_ID = ${luaString(DEFAULT_WEAPON.id)} }`));

assertPlain(AVATARS, 'AVATARS');
assertPlain(BASE, 'BASE');
written.push(write('Avatars.luau', 'web/src/data/avatars.js', `local AVATARS = ${emit(AVATARS, 0, 'AVATARS')}

-- The stat line every fighter starts from, before the weapon's set/mul overrides. See Loadout.
local BASE = ${emit(BASE, 0, 'BASE')}

local BY_ID = {}
for _, a in AVATARS do
	BY_ID[a.id] = a
end

return { LIST = AVATARS, BY_ID = BY_ID, BASE = BASE, DEFAULT_ID = ${luaString(DEFAULT_AVATAR.id)} }`));

assertPlain(STAGES, 'STAGES');
written.push(write('Stages.luau', 'web/src/data/stages/index.js', `local STAGES = ${emit(STAGES, 0, 'STAGES')}

local BY_ID = {}
for _, s in STAGES do
	BY_ID[s.id] = s
end

return { LIST = STAGES, BY_ID = BY_ID }`));

assertPlain(ITEM_LIST, 'ITEM_LIST');
written.push(write('Items.luau', 'web/src/data/items.js', `local ITEMS = ${emit(ITEM_LIST, 0, 'ITEM_LIST')}

local BY_ID = {}
for _, i in ITEMS do
	BY_ID[i.id] = i
end

return { LIST = ITEMS, BY_ID = BY_ID }`));

// ---------------------------------------------------------------- fixture ----
// What the emitter was given. tests/data-parity.luau walks this against the Luau it produced, so
// a dropped field, a mangled number or an array emitted as a dictionary fails the build.
// Every composed loadout, stat line only. Loadout.luau is hand-written rather than generated -
// it is logic, not data - so the 72 avatar x weapon combinations are the check that applyStats
// multiplies, overrides and rounds exactly the way the JavaScript does.
const STAT_KEYS = ['weight', 'runSpeed', 'walkSpeed', 'airSpeed', 'jumps', 'jumpVelocity', 'fallSpeed', 'height', 'radius'];
const loadouts = [];
for (const a of AVATARS) for (const w of WEAPONS) {
  const L = buildLoadout(a.id, w.id);
  const row = { avatar: a.id, weapon: w.id, id: L.id, name: L.name, archetype: L.archetype, stats: {} };
  // As STRINGS. These are computed - 18 * 0.778 is 14.004000000000001336, which needs 17
  // significant digits - and Lune's JSON decoder would hand the test 14.004 instead, failing a
  // port that is exactly right. Luau's own tonumber parses the decimal back to the same double.
  for (const k of STAT_KEYS) row.stats[k] = String(L[k]);
  loadouts.push(row);
}

fs.writeFileSync(path.join(HERE, '../tests/data-fixture.json'),
  JSON.stringify({ weapons: WEAPONS, avatars: AVATARS, base: BASE, stages: STAGES, items: ITEM_LIST, loadouts }));

const count = (o) => JSON.stringify(o).length;
console.log(`data generated: ${written.join(', ')}`);
console.log(`  ${WEAPONS.length} weapons, ${AVATARS.length} avatars, ${STAGES.length} stages, ${ITEM_LIST.length} items, ${loadouts.length} loadouts`
  + ` (${(count({ WEAPONS, AVATARS, STAGES, ITEM_LIST }) / 1024).toFixed(0)} KB of source data)`);
