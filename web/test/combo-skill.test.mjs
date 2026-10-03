// Combos that take skill (COMBO in src/config.js, docs/briefs/combo-system-plan.md), asserted
// against the engine: real fighters in a real match, real presses on real frames.
//
//   * a press during the strike is a timed ("perfect") link: faster, harder, worth more meter;
//     the same press one frame earlier, a late press, or mashing is an ordinary link; a timed
//     press after a whiff does nothing, because nothing chains off a whiff;
//   * a finisher opens only at the end of a string linked perfectly all the way;
//   * cancels happen only off a landed hit, only on moves that declare them, and spend what a
//     jump or a dodge normally spends; a whiff keeps its full recovery;
//   * damage scales down from the third hit of a combo and floors; knockback does not scale; a
//     multi-hit swing counts once; the count clears the moment the victim can act;
//   * the break works from the fourth hit, only during that hit's freeze, never inside its
//     cooldown, and an early Dodge locks it out.
import { makeMatch, skipCountdown, EMPTY } from './harness.mjs';
import { COMBO, comboScale } from '../src/config.js';
import { launchSpeed } from '../src/engine/knockback.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };

// Two fighters toe to toe on Foundry Floor, attacker on the left facing right. `edit` changes the
// attacker's moves before anything runs (each match builds its own character, so this is local).
function duel({ weapon = 'Sword', gap = 2.4, percent = 0, edit } = {}) {
  const m = makeMatch({ loadouts: [['Classic', weapon], ['Noir', 'Sword']] });
  skipCountdown(m);
  for (let i = 0; i < 200; i++) m.step();
  const [a, v] = m.fighters;
  if (edit) {
    a.char = { ...a.char, moves: { ...a.char.moves } };
    edit(a.char.moves);
  }
  a.x = -gap / 2; v.x = gap / 2; a.facing = 1; v.facing = -1;
  for (const f of [a, v]) { f.onGround = true; f.platform = m.stage.main; f.y = 0; f.vx = 0; f.vy = 0; f.invincible = 0; f.setState('idle'); }
  v.percent = percent;
  m.events.length = 0;
  return { m, a, v };
}
const press = (m, src, p) => m._input.set(src, Object.assign(EMPTY(), p, { anyPress: true }));

// Starts `opener` and steps, calling `input(a, i)` before each frame for the attacker's input
// (an object to press, or null). Returns every event and the moves the attacker went through.
function play(d, opener, input, frames = 90) {
  const { m, a } = d;
  a.startMove(opener);
  const events = [], moves = [opener];
  for (let i = 0; i < frames; i++) {
    const p = input(a, i);
    if (p) press(m, 'p0', p); else m._input.clear('p0');
    m.step();
    for (const e of m.events) events.push(e);
    m.events.length = 0;
    if (a.moveId && a.moveId !== moves[moves.length - 1]) moves.push(a.moveId);
  }
  return { events, moves };
}
const perfects = (r) => r.events.filter((e) => e.type === 'perfectlink');
// The first frame the attacker's current move is in its strike (state before the step).
const inStrike = (a) => a.state === 'attack' && a.mf === a.startupEff && a.hitlag === 0;

// ---------------------------------------------------------------- timing ----
{
  // One press, on the first frame of the opener's strike.
  const d = duel();
  let pressed = false, startup = null, bonus = null, charge0 = d.a.ultCharge;
  const r = play(d, 'LightNeutral1', (a) => {
    if (!pressed && inStrike(a)) { pressed = true; return { light: true }; }
    if (a.moveId === 'LightNeutral2' && startup === null) { startup = a.startupEff; bonus = a.bonusDamage; }
    return null;
  });
  const p = perfects(r);
  const base = d.a.char.moves.LightNeutral2.startup;
  check('a press on the strike is a timed link', r.moves.includes('LightNeutral2') && p.length === 1 && p[0].streak === 1,
    `moves ${r.moves.join(' > ')}, perfect links ${p.length}`);
  check('a timed link starts faster and hits harder', startup === base - COMBO.perfectStartupCut && bonus === COMBO.perfectDamage,
    `LightNeutral2 startup ${startup} (data ${base}), bonus damage ${bonus}`);
  const hits = r.events.filter((e) => e.type === 'hit' && e.attacker === 0);
  check('a timed link that lands is worth more meter', hits.length === 2 && d.a.ultCharge - charge0 === 1 + COMBO.perfectCharge,
    `${hits.length} hits, meter +${d.a.ultCharge - charge0} (1 for the opener, ${COMBO.perfectCharge} for the timed link)`);
}
{
  // The same single press one frame earlier, in the wind-up: still chains, not timed.
  const d = duel();
  let pressed = false;
  const r = play(d, 'LightNeutral1', (a) => {
    if (!pressed && a.state === 'attack' && a.mf === a.startupEff - 1) { pressed = true; return { light: true }; }
    return null;
  });
  check('a press one frame before the strike is an ordinary link', r.moves.includes('LightNeutral2') && perfects(r).length === 0,
    `moves ${r.moves.join(' > ')}, perfect links ${perfects(r).length}`);
}
{
  // Mashing: a press every other frame (a key cannot go down two frames running) from the start.
  const d = duel();
  const r = play(d, 'LightNeutral1', (a, i) => (i % 2 === 0 ? { light: true } : null));
  check('mashing chains the whole string and never times a link', r.moves.length >= 3 && perfects(r).length === 0,
    `moves ${r.moves.join(' > ')}, perfect links ${perfects(r).length}`);
}
{
  // Late: first press after the window, during the recovery.
  const d = duel();
  let pressed = false;
  const r = play(d, 'LightNeutral1', (a) => {
    const m = a.move;
    if (!pressed && m && a.moveId === 'LightNeutral1' && a.mf === a.startupEff + m.active + COMBO.perfectLate) { pressed = true; return { light: true }; }
    return null;
  });
  check('a press after the window is an ordinary link', r.moves.includes('LightNeutral2') && perfects(r).length === 0,
    `moves ${r.moves.join(' > ')}, perfect links ${perfects(r).length}`);
}
{
  // The last frame inside the window is still timed.
  const d = duel();
  let pressed = false;
  const r = play(d, 'LightNeutral1', (a) => {
    const m = a.move;
    if (!pressed && m && a.moveId === 'LightNeutral1' && a.mf === a.startupEff + m.active + COMBO.perfectLate - 1) { pressed = true; return { light: true }; }
    return null;
  });
  check('the last frame of the window is still timed', perfects(r).length === 1, `perfect links ${perfects(r).length}`);
}
{
  // A timed press on a whiff: nothing to chain off.
  const d = duel({ gap: 12 });
  let pressed = false;
  const r = play(d, 'LightNeutral1', (a) => {
    if (!pressed && inStrike(a)) { pressed = true; return { light: true }; }
    return null;
  });
  check('a timed press after a whiff does nothing', !r.moves.includes('LightNeutral2') && perfects(r).length === 0,
    `moves ${r.moves.join(' > ')}`);
}

// ---------------------------------------------------------------- finishers ----
const withFinisher = (moves) => {
  moves.Finisher = { ...moves.LightNeutral3, id: 'Finisher', label: 'Test Finisher', finisher: true };
  moves.LightNeutral2 = { ...moves.LightNeutral2, finishers: { neutral: 'Finisher' } };
};
function string(timedLinks, edit = withFinisher) {
  // A string from LightNeutral1, each link pressed on the strike (timed) or on the last wind-up
  // frame (ordinary): link k is the press made during the k-th move of the string.
  const d = duel({ edit });
  let serial = -1, k = -1, pressedOn = -1;
  return play(d, 'LightNeutral1', (a) => {
    if (a.state !== 'attack' || !a.move) return null;
    if (a.moveSerial !== serial) { serial = a.moveSerial; k++; }
    if (k >= timedLinks.length || pressedOn === serial) return null;
    if (timedLinks[k] ? (a.mf === a.startupEff && a.hitlag === 0) : a.mf === a.startupEff - 1) { pressedOn = serial; return { light: true }; }
    return null;
  }, 160);
}
{
  const r = string([true, true]);
  const fin = perfects(r).find((e) => e.move === 'Finisher');
  check('a string linked perfectly all the way opens the finisher', r.moves.includes('Finisher') && fin && fin.finisher && fin.streak === 2,
    `moves ${r.moves.join(' > ')}`);
  const early = string([false, true]);
  check('one ordinary link closes the finisher', !early.moves.includes('Finisher') && early.moves.includes('LightNeutral3'),
    `ordinary then timed: ${early.moves.join(' > ')}`);
  const late = string([true, false]);
  check('an untimed last press does not reach the finisher', !late.moves.includes('Finisher') && late.moves.includes('LightNeutral3'),
    `timed then ordinary: ${late.moves.join(' > ')}`);
  // A timed link after an ordinary one is timed, and its streak starts again at 1: the ordinary
  // link neither poisons the next press nor counts toward the streak.
  const looping = (moves) => { moves.LightNeutral3 = { ...moves.LightNeutral3, chains: { neutral: 'LightNeutral1' } }; };
  const mixed = string([true, false, true], looping);
  const ps = perfects(mixed);
  check('a timed link after an ordinary one is timed, its streak restarted', mixed.moves.length >= 4 && ps.length === 2 && ps[0].streak === 1 && ps[1].streak === 1,
    `timed, ordinary, timed: ${mixed.moves.join(' > ')}; streaks ${ps.map((e) => e.streak).join(', ')}`);
  const d = duel({ edit: withFinisher });
  const mash = play(d, 'LightNeutral1', (a, i) => (i % 2 === 0 ? { light: true } : null), 120);
  check('mashing the same string never reaches the finisher', !mash.moves.includes('Finisher'), `mashed: ${mash.moves.join(' > ')}`);
}

// ---------------------------------------------------------------- cancels ----
const cancelling = (c) => (moves) => { moves.LightNeutral1 = { ...moves.LightNeutral1, cancels: c }; };
function cancelRun(edit, button, { gap = 2.4, air = false } = {}) {
  const d = duel({ edit, gap });
  if (air) { for (const f of [d.a, d.v]) { f.y = 6; f.onGround = false; f.platform = null; f.setState('air'); } d.a.jumpsLeft = 1; d.a.airDodgeUsed = false; }
  // Press the cancel button every frame from the end of the active window.
  let spent = null;
  const r = play(d, 'LightNeutral1', (a, i) => {
    const m = a.char.moves.LightNeutral1;
    // what the cancel spent, read the frame it happened - landing later restores both
    if (spent === null && (a.state === 'airdodge' || (a.state === 'air' && a.moveId === null && i > 0))) spent = { jumps: a.jumpsLeft, airDodge: a.airDodgeUsed };
    if (a.moveId === 'LightNeutral1' && a.mf >= a.startupEff + m.active) return { [button]: true, x: button === 'dodge' ? 1 : 0 };
    return null;
  }, 40);
  const ev = r.events.find((e) => e.type === 'cancel' && e.fighter === 0);
  return { d, r, ev, spent };
}
{
  const j = cancelRun(cancelling({ jump: true }), 'jump');
  check('Jump cancels a landed move that allows it', j.ev && j.ev.kind === 'jump', `cancel ${j.ev ? j.ev.kind : 'none'}, state ${j.d.a.state}`);
  const dg = cancelRun(cancelling({ dodge: true }), 'dodge');
  check('Dodge cancels a landed move that allows it, into a dash', dg.ev && dg.ev.kind === 'dodge' && dg.r.events.some((e) => e.type === 'dash' && e.fighter === 0),
    `cancel ${dg.ev ? dg.ev.kind : 'none'}`);
  const none = cancelRun(null, 'jump');
  check('a move that does not declare cancels cannot be cancelled', !none.ev, `cancel ${none.ev ? none.ev.kind : 'none'}`);
  const onlyDodge = cancelRun(cancelling({ dodge: true }), 'jump');
  check('a move cancels only with what it declares', !onlyDodge.ev, `jump on a dodge-cancel move: ${onlyDodge.ev ? onlyDodge.ev.kind : 'none'}`);
  const whiff = cancelRun(cancelling({ jump: true, dodge: true }), 'jump', { gap: 12 });
  check('a whiff cannot be cancelled', !whiff.ev, `cancel on a whiff: ${whiff.ev ? whiff.ev.kind : 'none'}`);
  // In the air: the cancel spends the double jump / the air dodge.
  const aj = cancelRun((moves) => { moves.LightNeutral1 = { ...moves.LightNeutral1, cancels: { jump: true }, grounded: false }; }, 'jump', { air: true });
  check('a jump cancel in the air spends the double jump', aj.ev && aj.spent && aj.spent.jumps === 0, `cancel ${aj.ev ? aj.ev.kind : 'none'}, jumps left after it ${aj.spent && aj.spent.jumps}`);
  const ad = cancelRun((moves) => { moves.LightNeutral1 = { ...moves.LightNeutral1, cancels: { dodge: true }, grounded: false }; }, 'dodge', { air: true });
  check('a dodge cancel in the air spends the air dodge', ad.ev && ad.spent && ad.spent.airDodge === true, `cancel ${ad.ev ? ad.ev.kind : 'none'}, air dodge used after it ${ad.spent && ad.spent.airDodge}`);
}

// ---------------------------------------------------------------- scaling ----
{
  // Land hit after hit through combat with the victim held in hitstun, each a new swing.
  const d = duel({ percent: 50 });
  const { m, a, v } = d;
  const move = { ...a.char.moves.LightNeutral1, id: 'Probe', damage: 10, base: 12, growth: 1.0 };
  const dealt = [], launches = [];
  for (let n = 1; n <= 12; n++) {
    a.moveSerial++;
    v.percent = 50;
    m.combat.resolveHit(a, v, move, null, null, {});
    dealt.push(v.percent - 50);
    const hit = m.combat.events.filter((e) => e.type === 'hit').pop();
    launches.push(hit.launch);
    v.hitlag = 0;
  }
  m.combat.events.length = 0;
  const want = dealt.map((_, i) => Math.max(1, Math.floor(10 * comboScale(i + 1) + 0.5)));
  check('damage scales from the third hit of a combo and floors', JSON.stringify(dealt) === JSON.stringify(want) && dealt[0] === 10 && dealt[1] === 10 && dealt[2] < 10 && dealt[11] === Math.floor(10 * COMBO.scaleFloor + 0.5),
    `dealt ${dealt.join(', ')}`);
  const full = launchSpeed(12, 1.0, 10, 60, v.weight);
  check('knockback does not scale', launches.every((l) => Math.abs(l - full) < 1e-9), `launch every hit ${launches[0].toFixed(3)}, unscaled ${full.toFixed(3)}`);
  // Two hits of one swing count once.
  const n0 = v.comboHits;
  a.moveSerial++;
  m.combat.resolveHit(a, v, move, null, null, {});
  m.combat.resolveHit(a, v, move, null, null, {});
  check('a multi-hit swing counts as one hit of the combo', v.comboHits === n0 + 1, `count ${n0} -> ${v.comboHits}`);
  // The moment the victim can act, the combo is over.
  v.hitlag = 0; v.hitstun = 0; v.setState('idle');
  m.step();
  check('the combo count clears when the victim can act', v.comboHits === 0, `count after an idle frame: ${v.comboHits}`);
}

// ---------------------------------------------------------------- the break ----
function breakAt(hitNumber, { pressInFreeze = true, cooldown = 0, earlyPress = false } = {}) {
  const d = duel({ percent: 40 });
  const { m, a, v } = d;
  v.breakCooldown = cooldown;
  const move = { ...a.char.moves.LightNeutral1, id: 'Probe', damage: 4, base: 10, growth: 0.5 };
  const events = [];
  for (let n = 1; n <= hitNumber; n++) {
    a.moveSerial++;
    m.combat.resolveHit(a, v, move, null, null, {});
    if (n < hitNumber) {
      if (earlyPress && n === COMBO.breakFrom - 1) { press(m, 'p1', { dodge: true }); m.step(); m._input.clear('p1'); m.events.length = 0; }
      v.hitlag = 0;
    }
  }
  if (pressInFreeze) press(m, 'p1', { dodge: true });
  else { v.hitlag = 0; press(m, 'p1', { dodge: true }); }
  m.step();
  m._input.clear('p1');
  for (const e of m.events) events.push(e);
  m.events.length = 0;
  const broke = events.find((e) => e.type === 'combobreak' && e.fighter === 1);
  return { d, broke };
}
{
  const ok = breakAt(COMBO.breakFrom);
  check('Dodge in the freeze of the fourth hit breaks the combo', ok.broke && ok.d.v.state === 'breakout' && ok.d.v.invincible >= COMBO.breakInv - 1
    && ok.d.v.breakCooldown > 0 && ok.d.v.pendingLaunch === null && Math.abs(ok.d.a.vx) > 0,
    `broke ${!!ok.broke}, state ${ok.d.v.state}, invincible ${ok.d.v.invincible}, cooldown ${ok.d.v.breakCooldown}, attacker pushed ${ok.d.a.vx.toFixed(1)}`);
  check('the break pushes the attacker away from the victim', ok.d.a.vx < 0, `attacker vx ${ok.d.a.vx.toFixed(1)} (attacker is on the left)`);
  const early = breakAt(COMBO.breakFrom - 1);
  check('the break is not there before the fourth hit', !early.broke && early.d.v.breakLocked, `third hit: broke ${!!early.broke}, locked ${early.d.v.breakLocked}`);
  const outside = breakAt(COMBO.breakFrom, { pressInFreeze: false });
  check('the break is only during the freeze', !outside.broke, `after the freeze: broke ${!!outside.broke}`);
  const cd = breakAt(COMBO.breakFrom + 2, { cooldown: 100 });
  check('no break inside the cooldown', !cd.broke, `with 100 frames of cooldown: broke ${!!cd.broke}`);
  const locked = breakAt(COMBO.breakFrom + 1, { earlyPress: true });
  check('an early Dodge locks the break for the rest of the combo', !locked.broke, `pressed during the previous hit, then in the freeze: broke ${!!locked.broke}`);
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
