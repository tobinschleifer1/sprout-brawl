// The animation manifest: every move's key poses tile its real frames exactly, every move in the
// game is listed, and the list is the size the production doc says it is.
import assert from 'node:assert/strict';
import { manifest, allocate, moveKeys, TEMPLATES, templateFor, MOVE_ORDER } from '../src/data/animations.js';
import { WEAPONS } from '../src/data/weapons/index.js';

const m = manifest();

// Every weapon, every move it has, in the manifest - a move missing here is a move nobody draws.
for (const w of WEAPONS) {
  const listed = m.weapons.find((x) => x.id === w.id);
  assert(listed, `${w.id} missing from the manifest`);
  const inGame = Object.keys(w.moves).filter((id) => MOVE_ORDER.includes(id));
  assert.deepEqual(listed.moves.map((x) => x.id).sort(), inGame.sort(), `${w.id}: manifest moves differ from the game's`);
  assert.equal(inGame.length, Object.keys(w.moves).length, `${w.id} has a move MOVE_ORDER does not know about`);
}

let keys = 0;
for (const w of m.weapons) for (const mv of w.moves) {
  const move = WEAPONS.find((x) => x.id === w.id).moves[mv.id];
  assert.equal(mv.total, move.startup + move.active + move.recovery, `${w.id} ${mv.id}: total frames`);
  // The keys tile [0, total) exactly: contiguous, non-empty, no gaps, no overlap.
  let at = 0;
  for (const k of mv.keys) {
    assert.equal(k.from, at, `${w.id} ${mv.id} ${k.name}: starts at ${k.from}, expected ${at}`);
    assert(k.to > k.from, `${w.id} ${mv.id} ${k.name}: empty key`);
    at = k.to;
  }
  assert.equal(at, mv.total, `${w.id} ${mv.id}: keys end at ${at}, move is ${mv.total} frames`);
  // Keys never straddle a phase boundary: the active frames are exactly the contact keys, so the
  // brightest drawing is on screen precisely when the move can hit.
  for (const k of mv.keys) {
    const phaseStart = { startup: 0, active: move.startup, recovery: move.startup + move.active }[k.phase];
    const phaseEnd = phaseStart + { startup: move.startup, active: move.active, recovery: move.recovery }[k.phase];
    assert(k.from >= phaseStart && k.to <= phaseEnd, `${w.id} ${mv.id} ${k.name} spills out of its ${k.phase} phase`);
  }
  assert(mv.keys.length <= TEMPLATES[templateFor(mv.id)].length);
  keys += mv.keys.length;
}
assert.equal(keys, m.totals.moveKeys);

// allocate: each key gets at least a frame, the range is covered once, a too-short phase drops keys.
assert.deepEqual(allocate(10, [0.6, 1]), [[0, 6], [6, 10]]);
assert.deepEqual(allocate(1, [0.5, 1]), [null, [0, 1]]);
assert.deepEqual(allocate(3, [0.3, 0.55, 0.85, 1]), [null, [0, 1], [1, 2], [2, 3]]);
for (let n = 1; n <= 40; n++) for (const t of Object.values(TEMPLATES)) {
  for (const phase of ['startup', 'active', 'recovery']) {
    const ends = t.filter((k) => k.phase === phase).map((k) => k.end);
    if (!ends.length) continue;
    const spans = allocate(n, ends).filter(Boolean);
    assert.equal(spans[0][0], 0); assert.equal(spans[spans.length - 1][1], n);
    for (let i = 1; i < spans.length; i++) assert.equal(spans[i][0], spans[i - 1][1]);
  }
}

// Shared animations: unique ids, every key named, and a key with a basic version names the state.
const ids = new Set();
for (const a of m.shared) {
  assert(!ids.has(a.id), `duplicate animation ${a.id}`); ids.add(a.id);
  for (const k of a.keys) {
    assert(k.name, `${a.id}: unnamed key`);
    if (k.basic !== false) assert(k.sample && k.sample.state, `${a.id} ${k.name}: no fighter state to depict`);
  }
}
assert.equal(m.totals.all, m.totals.sharedKeys + m.totals.moveKeys + m.totals.vfxFrames);

// A known move, spelled out: the Sword's Crescent Rush (21/4/30) is the plan's worked example.
const crescent = moveKeys(WEAPONS.find((w) => w.id === 'Sword').moves.SigSide, 'SigSide');
assert.deepEqual(crescent.filter((k) => k.phase === 'active').map((k) => [k.from, k.to]), [[21, 25]]);

console.log(`PASS animations: ${m.totals.moveKeys} move key poses tile their frames exactly across ${m.weapons.length} weapons; ${m.totals.sharedKeys} shared poses; ${m.totals.vfxFrames} effect frames; ${m.totals.all} in all`);
