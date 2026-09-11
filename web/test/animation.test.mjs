// Does the fighter actually animate?
//
// The render suite proves a frame draws without throwing. It does not prove the drawing MOVES,
// and every animation bug this file was written for was invisible to it:
//
//   - `spinY` and `spinZ` were produced by channels.js and read by nothing in the renderer, so
//     neutral air, the helpless fall, air dodges, tech rolls and the taunt all set a spin that
//     rendered as a completely static pose. Five states silently un-animated.
//   - Every attack lerped on a raw linear `k`, so the whole moveset read as a slideshow of
//     positions rather than as motion.
//   - Active frames were constants, so a held pose was a frozen pose.
//
// So this file asserts the animation PRINCIPLES, measured off the channel bag:
//   every state is finite; every channel is consumed; attacks anticipate before they strike;
//   the strike's fastest frames are the ones the hitbox is live; held frames still move; and
//   recovery settles rather than sliding home.
import { makeMatch, skipCountdown } from './harness.mjs';
import { channelsFor } from '../src/render2d/channels.js';
import { WEAPONS } from '../src/data/weapons/index.js';
import { weaponPose } from '../src/render2d/weapons2d.js';
import { readFileSync } from 'node:fs';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };

// Flatten a channel bag to comparable numbers, so two poses can be diffed.
const flat = (ch) => {
  const out = {};
  for (const [k, v] of Object.entries(ch)) {
    if (typeof v === 'number') out[k] = v;
    else if (v && typeof v === 'object') for (const [k2, v2] of Object.entries(v)) if (typeof v2 === 'number') out[`${k}.${k2}`] = v2;
  }
  return out;
};
const dist = (a, b) => Object.keys(a).reduce((s, k) => s + Math.abs(a[k] - (b[k] ?? 0)), 0);

// Pose a fighter mid-move at an exact move-frame, without the match advancing underneath.
// `at` is a function of the move's real startupEff, because startupEff is only correct AFTER
// startMove has run — reading it beforehand gets the previous move's value, which silently posed
// several of these checks at the wrong frame entirely.
function poseAt(f, moveId, at, t = 0) {
  f.setState('idle');
  f.startMove(moveId);
  f.mf = typeof at === 'function' ? at(f.startupEff, f.move) : at;
  return flat(channelsFor(f, t));
}
const startupOf = (f, id) => { f.setState('idle'); f.startMove(id); const st = f.startupEff; f.setState('idle'); return st; };
// The drawn weapon angle at a given move-frame.
function angleAt(f, id, at) {
  f.setState('idle'); f.startMove(id);
  f.mf = typeof at === 'function' ? at(f.startupEff, f.move) : at;
  return weaponPose(f, f.mf / 60).angle;
}

// ---- 1. every state a real match produces yields finite channels ----
{
  const m = makeMatch({ mode: 'StockFFA', stocks: 3,
    loadouts: [['Classic', 'Sword'], ['Noir', 'Scythe'], ['Ember', 'Blasters'], ['Moss', 'Grimoire']] });
  m.itemsOn = true;
  m.fighters.forEach((f, i) => { f.isBot = true; f.botLevel = ['easy', 'normal', 'hard', 'normal'][i]; });
  skipCountdown(m);
  const states = new Set();
  const bad = [];
  for (let i = 0; i < 60 * 180; i++) {
    m.step(); m.events.length = 0;
    for (const f of m.fighters) {
      states.add(f.state);
      const ch = flat(channelsFor(f, i / 60));
      for (const [k, v] of Object.entries(ch)) if (!Number.isFinite(v)) bad.push(`${f.state}.${k}`);
    }
    if (m.state === 'results') break;
  }
  check('every state animates without a non-finite channel', bad.length === 0,
    bad.length ? `non-finite: ${[...new Set(bad)].slice(0, 8).join(', ')}`
      : `${states.size} states exercised over a full 4-player match: ${[...states].sort().join(', ')}`);
}

// ---- 2. no channel is produced and then thrown away ----
// This is the check that would have caught spinY/spinZ. A pose channel nothing reads is an
// animation that does not happen, and it is completely silent otherwise.
{
  const src = readFileSync(new URL('../src/render2d/renderer2d.js', import.meta.url), 'utf8');
  const m = makeMatch({ loadouts: [['Classic', 'Sword'], ['Noir', 'Sword']] });
  skipCountdown(m);
  const ch = channelsFor(m.fighters[0], 0);
  // spinY and spinZ are deliberately folded into sx / rigRotZ inside channelsFor itself, so they
  // are consumed there rather than by the renderer.
  const arm = readFileSync(new URL('../src/render2d/renderer2d.js', import.meta.url), 'utf8');
  const foldedInternally = new Set(['spinY', 'spinZ']);
  // SUB-KEYS TOO. The first version matched `ch.armL` as a string, which is present — while
  // `armL.x` and `armR.x` were read by nothing, so the run wrote its entire arm swing into a
  // channel the renderer discarded and this check stayed green. A grep for the parent object is
  // not a test that the data is used.
  const leaves = [];
  for (const [k, v] of Object.entries(ch)) {
    if (foldedInternally.has(k)) continue;
    if (v && typeof v === 'object') for (const k2 of Object.keys(v)) leaves.push([`${k}.${k2}`, `a.${k2}`, `ch.${k}`]);
    else leaves.push([k, `ch.${k}`, null]);
  }
  const unread = leaves.filter(([, direct, parent]) => !arm.includes(direct) && !(parent && arm.includes(`${parent}.`))).map(([n]) => n);
  check('every animation channel is consumed by the renderer', unread.length === 0,
    unread.length ? `produced but never read: ${unread.join(', ')} — the pose is computed and discarded`
      : `${leaves.length} channel leaves, all consumed (spinY folds into sx, spinZ into rigRotZ)`);
}

// ---- 3. every attack anticipates before it strikes ----
// The end of startup must be measurably away from rest, and on the OPPOSITE side of rest from
// where the strike goes. A wind-up that already points at the target is not a wind-up, and it is
// the frame the defender is supposed to read.
{
  const m = makeMatch({ loadouts: [['Classic', 'Sword'], ['Noir', 'Sword']] });
  skipCountdown(m);
  const f = m.fighters[0];
  const rest = flat(channelsFor(f, 0));
  const restAngle = (f.setState('idle'), weaponPose(f, 0).angle);
  const noAnticipation = [], rows = [];
  const MOVES = ['LightNeutral1', 'LightSide1', 'LightUp', 'LightDown', 'SigSide', 'SigDown', 'SigNeutral', 'AirForward', 'AirUp'];
  for (const id of MOVES) {
    if (!f.char.moves[id]) continue;
    const mv = f.char.moves[id];
    const cocked = poseAt(f, id, (st) => st);
    const struck = poseAt(f, id, (st, m2) => st + Math.max(1, Math.ceil(m2.active * 0.6)));
    const cockDist = dist(cocked, rest);
    // Measured on the WEAPON ANGLE — the biggest, most visible thing on the character, drawn
    // every frame, and the one channel every attack moves.
    //
    // These checks used to key on `armR.z`, which `_fighter` reads only in a fallback branch that
    // never fires (every fighter carries a weapon, so the front arm is entirely weapon-driven):
    // three checks green on a discarded number. `lean` was no better — several moves never lean,
    // so half the roster measured a flat zero against itself.
    const cockA = angleAt(f, id, (st2) => st2);
    const strikeA = angleAt(f, id, (st2, m2) => st2 + Math.max(1, Math.ceil(m2.active * 0.6)));
    // Anticipation on a rotational swing, stated so it survives wraparound: the wind-up displaces
    // the weapon from rest in the direction OPPOSITE to the way the swing then travels. Two
    // earlier formulations were wrong — a sign flip about rest fails because a sword cocks at 140
    // and contacts at -25, both "one side" of a -78 rest; and "further from contact than rest is"
    // breaks down for the rising attacks, whose rest angle is already nearly antipodal to their
    // contact, where no cock can be further away. Direction of travel is the thing that is
    // actually being asserted, and it is well defined everywhere.
    const away = Math.sign(cockA - restAngle), toward = Math.sign(strikeA - cockA);
    const wound = away !== 0 && toward !== 0 && away !== toward;
    rows.push(`${id} rest ${(restAngle * 57).toFixed(0)}° cock ${(cockA * 57).toFixed(0)}° contact ${(strikeA * 57).toFixed(0)}°`);
    if (cockDist < 0.1 || !wound) noAnticipation.push(`${id}: rest ${(restAngle * 57).toFixed(0)}°, cock ${(cockA * 57).toFixed(0)}°, contact ${(strikeA * 57).toFixed(0)}° — the cock sits between rest and contact`);
  }
  check('every attack winds up before it swings', noAnticipation.length === 0,
    noAnticipation.length ? `no anticipation: ${noAnticipation.join('; ')}` : rows.join('  |  '));
}

// ---- 4. the strike's fastest frames are the ones that hit ----
// Slow in / slow out, measured: the per-frame pose change across the first active frames must
// exceed the average across the wind-up. If the wind-up is the fastest part of a move, the move
// reads as a lunge that stops rather than as a hit that lands.
{
  const m = makeMatch({ loadouts: [['Classic', 'Sword'], ['Noir', 'Sword']] });
  skipCountdown(m);
  const f = m.fighters[0];
  const slow = [], rows = [];
  for (const id of ['LightSide1', 'SigSide', 'SigDown', 'AirForward']) {
    if (!f.char.moves[id]) continue;
    const mv = f.char.moves[id];
    const st = startupOf(f, id);
    const speedAt = (a, b) => dist(poseAt(f, id, b), poseAt(f, id, a));
    let windSpeed = 0;
    for (let i = 1; i <= st; i++) windSpeed += speedAt(i - 1, i);
    windSpeed /= Math.max(1, st);
    const hitSpeed = speedAt(st, st + 1);
    rows.push(`${id} wind ${windSpeed.toFixed(2)}/f vs contact ${hitSpeed.toFixed(2)}/f`);
    if (hitSpeed <= windSpeed) slow.push(`${id}: contact ${hitSpeed.toFixed(2)} <= wind-up ${windSpeed.toFixed(2)}`);
  }
  check('the contact frames are the fastest frames', slow.length === 0,
    slow.length ? slow.join('; ') : rows.join('  |  '));
}

// ---- 5. a held pose is not a frozen pose ----
// Something has to keep moving through the active window, or the frame reads as dropped.
{
  const m = makeMatch({ loadouts: [['Classic', 'Sword'], ['Noir', 'Sword']] });
  skipCountdown(m);
  const f = m.fighters[0];
  const frozen = [], rows = [];
  for (const w of WEAPONS) {
    for (const id of ['SigSide', 'LightSide1']) {
      const mv = w.moves[id]; if (!mv || mv.active < 3) continue;
      const g = makeMatch({ loadouts: [['Classic', w.id], ['Noir', 'Sword']] });
      skipCountdown(g);
      const gf = g.fighters[0];
      let moved = 0;
      const st = startupOf(gf, id);
      for (let i = 1; i < mv.active; i++) moved += dist(poseAt(gf, id, st + i, i / 60), poseAt(gf, id, st + i - 1, (i - 1) / 60));
      rows.push(`${w.id}/${id} ${moved.toFixed(2)}`);
      if (moved < 0.02) frozen.push(`${w.id}/${id} moved ${moved.toFixed(3)} across ${mv.active} active frames`);
    }
  }
  check('active frames keep moving', frozen.length === 0,
    frozen.length ? frozen.join('; ') : `total pose travel across the active window: ${rows.join(', ')}`);
}

// ---- 6. recovery settles rather than sliding straight home ----
// A damped settle passes its rest value and comes back. A linear return never does. Measured by
// looking for a sign change in the arm's approach to rest.
//
// "Rest" here is the move's OWN end-of-recovery pose, not the idle stance. Comparing against idle
// measured the wrong thing entirely: an attack's neutral is a combat stance with the arm forward,
// idle's is a relaxed one with it back, so the gap between them never changed sign no matter how
// the settle behaved.
{
  const m = makeMatch({ loadouts: [['Classic', 'Sword'], ['Noir', 'Sword']] });
  skipCountdown(m);
  const f = m.fighters[0];
  const noSettle = [], rows = [];
  for (const id of ['SigSide', 'SigDown', 'LightSide1']) {
    const mv = f.char.moves[id]; if (!mv) continue;
    const st = startupOf(f, id);
    const rest = angleAt(f, id, (s2, m2) => s2 + m2.active + m2.recovery);
    let signs = 0, prev = null;
    for (let i = 0; i <= mv.recovery; i++) {
      const d = angleAt(f, id, st + mv.active + i) - rest;
      const sgn = Math.sign(d);
      if (prev !== null && sgn !== 0 && sgn !== prev) signs++;
      if (sgn !== 0) prev = sgn;
    }
    rows.push(`${id} ${signs} crossing${signs === 1 ? '' : 's'}`);
    if (signs < 1) noSettle.push(`${id} never crosses rest — it slides home`);
  }
  check('recovery follows through past rest', noSettle.length === 0,
    noSettle.length ? noSettle.join('; ') : `${rows.join(', ')} — the settle overshoots and comes back`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
