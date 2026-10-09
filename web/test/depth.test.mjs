// Depth (docs/briefs/combat-plan.md, phase 2): the rules that make a fight more than mashing.
//
//   * staling (STALE): a move landed again and again does less, down to a floor; mixing moves keeps
//     them fresh; the memory forgets; both hits of one swing land alike; a blocked hit and the
//     ultimate never stale; the launch falls with the damage.
//
//   * armour: a heavy's startup shrugs off the first light hit - the damage is taken and counted,
//     the swing goes on; once per swing; a heavy, a grab, or a light after the startup still land;
//     the existing per-move armour still works.
//
//     node test/depth.test.mjs
import { makeMatch, skipCountdown } from './harness.mjs';
import { STALE, staleMul } from '../src/config.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };

function duel() {
  const m = skipCountdown(makeMatch({ loadouts: [['Classic', 'Sword'], ['Noir', 'Sword']] }));
  const [a, v] = m.fighters;
  a.x = 0; v.x = 2; a.facing = 1; v.facing = -1;
  for (const f of [a, v]) { f.y = 0; f.vx = 0; f.vy = 0; f.onGround = true; f.platform = m.stage.main; f.setState('idle'); f.invincible = 0; }
  return { m, a, v };
}
const probe = (id, damage = 20) => ({ id, damage, base: 12, growth: 1.0, angle: 45, startup: 3, active: 3, recovery: 10, kind: 'melee' });
// One swing of `move` landing on v at 50%, fresh to combos: what it dealt and how hard it launched.
function land(d, move, opts = {}) {
  const { m, a, v } = d;
  if (!opts.sameSwing) a.moveSerial++;
  v.percent = 50; v.comboHits = 0; v.comboKey = -1; v.hitlag = 0;
  if (opts.shield) { v.setState('shield'); v.sf = 30; v.shield = 50; } else if (v.state === 'shield') v.setState('idle');
  m.combat.events.length = 0;
  m.combat.resolveHit(a, v, move, null, null, {});
  const hit = m.combat.events.find((e) => e.type === 'hit');
  return { dealt: v.percent - 50, launch: hit ? hit.launch : null };
}

// ---- repeats fall, to a floor ----
{
  const d = duel();
  const P = probe('Probe');
  const dealt = [], launches = [];
  for (let n = 0; n < 11; n++) { const r = land(d, P); dealt.push(r.dealt); launches.push(r.launch); }
  const want = dealt.map((_, n) => Math.max(1, Math.floor(20 * Math.max(STALE.floor, 1 - STALE.step * Math.min(n, STALE.memory)) + 0.5)));
  check('a move landed again and again does less, down to the floor', JSON.stringify(dealt) === JSON.stringify(want) && dealt[0] === 20 && dealt[10] === 20 * STALE.floor,
    `dealt ${dealt.join(', ')}`);
  check('its launch falls with it', launches.every((l, i) => i === 0 || l < launches[i - 1] || dealt[i] === dealt[i - 1]) && launches[10] < launches[0],
    `launch ${launches[0].toFixed(1)} fresh, ${launches[10].toFixed(1)} stale`);
}

// ---- variety keeps moves fresh, and the memory forgets ----
{
  const d = duel();
  const four = ['A', 'B', 'C', 'D'].map((id) => probe(id));
  let mixed = 0;
  for (let n = 0; n < 16; n++) { const r = land(d, four[n % 4]); if (n >= 8) mixed += r.dealt; }
  const spam = duel();
  let one = 0;
  for (let n = 0; n < 16; n++) { const r = land(spam, probe('A')); if (n >= 8) one += r.dealt; }
  check('mixing four moves lands harder than spamming one', mixed > one && mixed === 8 * Math.floor(20 * (1 - STALE.step * 2) + 0.5),
    `last eight hits: ${mixed} mixed against ${one} spammed`);
  const f = duel();
  land(f, probe('Old'));
  for (let n = 0; n < STALE.memory; n++) land(f, probe(`Other${n}`));
  check('after eight other moves it is fresh again', land(f, probe('Old')).dealt === 20 && f.a.staleMoves.length === STALE.memory,
    `remembered: ${f.a.staleMoves.join(' ')}`);
}

// ---- what does not stale ----
{
  const d = duel();
  const P = probe('Twice');
  for (let n = 0; n < 4; n++) land(d, P);
  const first = land(d, P), second = land(d, P, { sameSwing: true });
  check('both hits of one swing land alike', first.dealt === second.dealt && first.dealt < 20,
    `first hit ${first.dealt}, second hit of the same swing ${second.dealt}`);
  const b = duel();
  for (let n = 0; n < 5; n++) land(b, probe('Blocked'), { shield: true });
  check('a blocked hit is not a landed one', land(b, probe('Blocked')).dealt === 20 && b.a.staleMoves.length === 1,
    `after five blocked: ${land(duel(), probe('Blocked')).dealt} dealt, ${b.a.staleMoves.length} remembered`);
  const u = duel();
  const U = { ...probe('Ultimate'), id: 'Ultimate' };
  for (let n = 0; n < 6; n++) land(u, U);
  check('the ultimate never stales', land(u, U).dealt === 20 && u.a.staleMoves.length === 0, `seventh ultimate dealt ${land(u, U).dealt}`);
  check('staleMul counts the memory', staleMul(['A', 'B', 'A'], 'A') === 1 - 2 * STALE.step && staleMul(new Array(20).fill('A'), 'A') === STALE.floor,
    `two of A: ${staleMul(['A', 'B', 'A'], 'A')}, twenty: ${staleMul(new Array(20).fill('A'), 'A')}`);
}

// ---- armour: heavies shrug off a light through their startup ----
{
  const setup = () => {
    const d = duel();
    const { a, v } = d;
    v.startMove(v.char.moves.SigSide);           // the victim winding up a heavy
    return { ...d, heavy: v.move };
  };
  const light = (d) => { d.a.moveSerial++; d.m.combat.events.length = 0; return d.m.combat.resolveHit(d.a, d.v, d.a.char.moves.LightNeutral1, null, null, {}); };
  const s1 = setup();
  const before = s1.v.percent;
  light(s1);
  const ev = s1.m.combat.events;
  check('a light into a heavy\'s startup is shrugged off', s1.v.state === 'attack' && s1.v.move === s1.heavy && s1.v.percent > before
      && ev.some((e) => e.type === 'armor') && !ev.some((e) => e.type === 'hit') && s1.v.stats.damageTaken === s1.v.percent - before,
    `victim ${s1.v.state} (${s1.v.move && s1.v.move.id}), took ${s1.v.percent - before}, events ${ev.map((e) => e.type).join(',')}`);
  light(s1);
  check('but only once per swing', s1.v.state === 'hitstun', `the second light: victim ${s1.v.state}`);
  const s2 = setup();
  s2.a.moveSerial++; s2.m.combat.resolveHit(s2.a, s2.v, s2.a.char.moves.SigSide, null, null, {});
  check('a heavy goes through it', s2.v.state === 'hitstun', `victim ${s2.v.state}`);
  const s3 = setup();
  s3.v.mf = s3.v.startupEff + 1;
  light(s3);
  check('a light after the startup lands', s3.v.state === 'hitstun', `victim ${s3.v.state} at frame ${s3.v.startupEff + 1}`);
  const s4 = setup();
  s4.a.x = s4.v.x - 1.4;
  s4.m.combat.checkGrab(s4.a);
  check('a grab still takes them', s4.v.state === 'grabbed', `victim ${s4.v.state}`);
  const s5 = duel();
  s5.v.startMove(s5.v.char.moves.LightNeutral1);
  light(s5);
  check('a light does not armour a light', s5.v.state === 'hitstun', `victim ${s5.v.state}`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
