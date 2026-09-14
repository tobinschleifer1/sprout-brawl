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
const PI_ = Math.PI;

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

// ---- 7. every ultimate has a body, not just a weapon ----
// `attackChannels` mapped move ids to body categories with a `: 'jab'` fallback, and 'Ultimate'
// matched nothing above it. So all six ultimates - the longest, loudest moves in the game, 72 to
// 140 frames each - played the body animation of a jab underneath a bespoke weapon performance.
// It was completely silent: the weapon looked right, so nothing looked broken.
{
  const rows = [], flatJab = [];
  const bad = [];
  for (const w of WEAPONS) {
    const g = makeMatch({ loadouts: [['Classic', w.id], ['Noir', 'Sword']] });
    skipCountdown(g);
    const gf = g.fighters[0];
    const mv = w.moves.Ultimate;
    const st = startupOf(gf, 'Ultimate');
    const total = st + mv.active + mv.recovery;
    // the fully cocked frame, against the jab's fully cocked frame
    const ultCock = poseAt(gf, 'Ultimate', st);
    const jabCock = poseAt(gf, 'LightNeutral1', (st2) => st2);
    const d = dist(ultCock, jabCock);
    // and it has to keep performing all the way through, not just strike a pose
    let travel = 0, prev = null;
    for (let i = 0; i <= total; i++) { const c = poseAt(gf, 'Ultimate', i, i / 60); if (prev) travel += dist(c, prev); prev = c; }
    rows.push(`${w.id} cock ${d.toFixed(1)} travel ${travel.toFixed(0)}`);
    if (d < 1.0) bad.push(`${w.id}: ultimate wind-up pose is ${d.toFixed(2)} from the jab's - it IS the jab`);
    if (travel < 8) bad.push(`${w.id}: ${travel.toFixed(1)} of body travel across ${total} frames`);
  }
  check('every ultimate animates the fighter, not only the weapon', bad.length === 0,
    bad.length ? bad.join('; ') : `distance from the jab pose, and total body travel: ${rows.join(', ')}`);
}

// ---- 8. a weapon that says it thrusts actually thrusts ----
// A thrust is a line and a swing is an arc, and the measurable difference is how far the weapon
// ROTATES between its cocked frame and contact. The pike used to cover 22-26 degrees with the
// body doing nothing and the prop sliding off the end of a fixed-length arm to fake reach; the
// reach now comes from the fighter driving forward, which is what the rotation figure is there to
// keep honest - if the pike ever starts sweeping, it has stopped being a spear.
{
  const rot = (weapon, id) => {
    const g = makeMatch({ loadouts: [['Classic', weapon], ['Noir', 'Sword']] });
    skipCountdown(g);
    const gf = g.fighters[0];
    const a = angleAt(gf, id, (st) => st);
    const b = angleAt(gf, id, (st, m2) => st + Math.max(1, Math.ceil(m2.active * 0.6)));
    const ch1 = (gf.setState('idle'), gf.startMove(id), gf.mf = gf.startupEff, channelsFor(gf, 0));
    const e1 = ch1.armR.ext || 1;
    gf.setState('idle'); gf.startMove(id); gf.mf = gf.startupEff + Math.max(1, Math.ceil(gf.move.active * 0.6));
    const e2 = (channelsFor(gf, 0).armR.ext || 1);
    const L = gf.h * 0.30;
    return { deg: Math.abs(b - a) * 180 / PI_, hand: Math.cos(b) * L * e2 - Math.cos(a) * L * e1 };
  };
  const MOVES = ['LightNeutral1', 'LightSide1', 'SigSide'];
  const bad = [], rows = [];
  for (const id of MOVES) {
    const p = rot('Pike', id), sw = rot('Sword', id), ax = rot('Axe', id);
    rows.push(`${id}: Pike ${p.deg.toFixed(0)}° (hand +${p.hand.toFixed(1)}) vs Sword ${sw.deg.toFixed(0)}° Axe ${ax.deg.toFixed(0)}°`);
    if (p.deg > 45) bad.push(`${id}: the pike rotates ${p.deg.toFixed(0)}° - that is a swing`);
    if (p.hand < 1.2) bad.push(`${id}: the pike's hand travels only ${p.hand.toFixed(2)} studs forward - the reach is not coming from the fighter`);
    if (id !== 'LightNeutral1' && sw.deg < 60) bad.push(`${id}: the sword only rotates ${sw.deg.toFixed(0)}° - the comparison is meaningless`);
  }
  check('the pike thrusts on a line while the swinging weapons sweep', bad.length === 0,
    bad.length ? bad.join('; ') : rows.join('  |  '));
}

// ---- 9. nobody is drawn lying on their side ----
// `lean` rotates the WHOLE rig (renderer2d `b.rotate(-ch.lean)`), so it is the one channel where a
// plausible-looking number is a broken drawing. The ultimate poses written for this pass held
// leans of 0.85 rad - 49 degrees, for 58 consecutive frames - and on the animation sheet the
// fighter was simply tipped over, holding the lance like a fence post. An attack's contact frame
// can lean hard for a few frames; a pose cannot HOLD it.
{
  const bad = [], rows = [];
  for (const w of WEAPONS) {
    const g = makeMatch({ loadouts: [['Classic', w.id], ['Noir', 'Sword']] });
    skipCountdown(g);
    const gf = g.fighters[0];
    for (const id of Object.keys(w.moves)) {
      const st = startupOf(gf, id);
      const mv = w.moves[id];
      const total = st + mv.active + mv.recovery;
      let peak = 0;
      for (let i = 0; i <= total; i++) peak = Math.max(peak, Math.abs(poseAt(gf, id, i, i / 60)['lean'] || 0));
      // One bar, on the peak. A "do not HOLD a big lean" clause was tried first and had to go:
      // the roster's committed side signatures legitimately sit above 26 degrees for 17-26 frames
      // of their recovery and look right doing it, so any threshold that caught the 49-degree pose
      // also failed four moves that were fine. The peak is the thing that reads as tipped over.
      if (peak > 0.62) bad.push(`${w.id}/${id} peaks at ${(peak * 57).toFixed(0)}° - the fighter is on their side`);
      if (peak > 0.5) rows.push(`${w.id}/${id} ${(peak * 57).toFixed(0)}°`);
    }
  }
  check('no pose leans further than a body bends', bad.length === 0,
    bad.length ? bad.join('; ') : `worst leans: ${rows.length ? rows.join(', ') : 'every move under 29°'}`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
