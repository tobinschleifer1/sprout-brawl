// The bullwhip (src/data/weapons/whip.js): a tip sweet spot, the Crack mark, and Storm Lash.
//
//   * the same swing at the tip's distance lands the tip, and point-blank only the lash - for a
//     fraction of the damage and launch;
//   * a tip hit marks its victim; the next tip hit on them cracks - its bonus damage, a harder
//     launch - and spends the mark; a lash hit neither marks nor cracks, a blocked tip does not
//     mark, a tip on someone else moves the mark, it fades after markFrames, and being hit wipes it;
//   * Storm Lash's cracks are a dome: a foe on its edge is hit, one standing next to the whip user,
//     inside it, is not.
//
//     node test/whip.test.mjs
import { makeMatch, skipCountdown } from './harness.mjs';
import { WEAPON_BY_ID } from '../src/data/weapons/index.js';
import { ULTIMATE } from '../src/config.js';
import { launchSpeed } from '../src/engine/knockback.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };
const W = WEAPON_BY_ID.Whip;
const M = W.mechanic;

function duel(n = 2) {
  const m = skipCountdown(makeMatch({ loadouts: [['Classic', 'Whip'], ['Noir', 'Sword'], ['Ember', 'Sword']].slice(0, n) }));
  for (const f of m.fighters) { f.y = 0; f.vx = 0; f.vy = 0; f.onGround = true; f.platform = m.stage.main; f.setState('idle'); f.invincible = 0; }
  const [a] = m.fighters;
  a.x = 0; a.facing = 1;
  return m;
}
// One Flick from `a` at `v` standing `gap` studs away: the hit event, the damage dealt, any crack event.
function flick(m, v, gap, opts = {}) {
  const a = m.fighters[0];
  v.x = a.x + gap; v.y = 0; v.vx = 0; v.vy = 0; v.facing = -1; v.hitlag = 0; v.invincible = 0;
  if (opts.shield) { v.setState('shield'); v.shield = 50; v.sf = 30; m._input.set(`p${v.index}`, { guardHeld: true }); }
  else { if (v.state !== 'idle') v.setState('idle'); m._input.clear(`p${v.index}`); }
  a.setState('idle'); a.hitlag = 0;
  const before = v.percent;
  a.startMove('LightNeutral1');
  const seen = [];
  for (let i = 0; i < 24; i++) {
    v.x = a.x + gap; v.vx = 0;
    m.step();
    for (const e of m.events) if (e.victim === v.index) seen.push(e);
    m.events.length = 0;
    if (seen.some((e) => e.type === 'hit' || e.type === 'block')) break;
  }
  m._input.clear(`p${v.index}`);
  const hit = seen.find((e) => e.type === 'hit');
  return { hit, dealt: v.percent - before, types: seen.map((e) => e.type) };
}

// ---- the tip, and the lash ----
{
  const m = duel();
  const v = m.fighters[1];
  const tip = flick(m, v, 6.2);
  const m2 = duel(); const lash2 = flick(m2, m2.fighters[1], 2.2);
  check('at the tip it cracks; point-blank only the lash stings', tip.hit && lash2.hit && tip.dealt === W.moves.LightNeutral1.damage && lash2.dealt < tip.dealt / 1.5
      && tip.hit.launch > lash2.hit.launch * 1.5,
    `tip ${tip.dealt}% launch ${tip.hit && tip.hit.launch.toFixed(1)}; lash ${lash2.dealt}% launch ${lash2.hit && lash2.hit.launch.toFixed(1)}`);
}

// ---- Crack: mark, then crack ----
{
  const m = duel();
  const a = m.fighters[0], v = m.fighters[1];
  const first = flick(m, v, 6.2);
  // marked until markFrames after the hit (a few frames have passed since, in its hitlag)
  const left = a.mech.expires - a.frameCount;
  const marked = a.mech.mark === v.index && left <= M.markFrames && left > M.markFrames - 20;
  const second = flick(m, v, 6.2);
  check('a tip hit marks; the next tip hit on them cracks for more and spends the mark',
    first.types.includes('crackmark') && marked && second.types.includes('crack') && second.dealt === first.dealt + M.bonusDamage && a.mech.mark === -1,
    `first: ${first.types.join(',')} (${first.dealt}%), second: ${second.types.join(',')} (${second.dealt}%), mark now ${a.mech.mark}`);
  // the crack's launch, against the same hit without the mark (at the same percent)
  const m2 = duel(); const v2 = m2.fighters[1];
  v2.percent = v.percent - second.dealt;
  const plain = flick(m2, v2, 6.2);
  const m3 = duel(); const a3 = m3.fighters[0], v3 = m3.fighters[1];
  v3.percent = v2.percent;
  a3.mech.mark = v3.index; a3.mech.expires = a3.frameCount + 100;
  const cracked = flick(m3, v3, 6.2);
  // exactly the tip's launch at the cracked damage, times launchMul - not merely the extra damage
  const J = W.moves.LightNeutral1, dmg = J.damage + M.bonusDamage;
  const want = launchSpeed(J.base, J.growth, dmg, v3.percent, v3.weight) * M.launchMul;
  check('a crack launches harder than the same tip unmarked, by launchMul on top of its damage',
    cracked.hit.launch > plain.hit.launch * 1.1 && Math.abs(cracked.hit.launch - want) < 1e-9 && cracked.types.includes('crack'),
    `unmarked launch ${plain.hit.launch.toFixed(2)}, cracked ${cracked.hit.launch.toFixed(2)} (want ${want.toFixed(2)})`);
}
{
  const m = duel(3);
  const a = m.fighters[0], v = m.fighters[1], u = m.fighters[2];
  const lash = flick(m, v, 2.2);
  check('the lash neither marks nor cracks', lash.hit && a.mech.mark === -1 && !lash.types.includes('crackmark'), `lash hit: ${lash.types.join(',')}, mark ${a.mech.mark}`);
  a.mech.mark = v.index; a.mech.expires = a.frameCount + 100;
  const lash2 = flick(m, v, 2.2);
  check('...even on a marked foe', a.mech.mark === v.index && !lash2.types.includes('crack'), `mark ${a.mech.mark} after a lash hit on the marked foe`);
  const blocked = flick(m, u, 6.2, { shield: true });
  check('a blocked tip does not mark', blocked.types.includes('block') && a.mech.mark === v.index, `blocked: ${blocked.types.join(',')}, mark still on ${a.mech.mark}`);
  u.setState('idle');
  const other = flick(m, u, 6.2);
  check('a tip on someone else moves the mark to them, and does not crack', other.types.includes('crackmark') && a.mech.mark === u.index,
    `${other.types.join(',')}, mark now on ${a.mech.mark}`);
}
{
  const m = duel();
  const a = m.fighters[0], v = m.fighters[1];
  flick(m, v, 6.2);
  for (let i = 0; i < M.markFrames + 2; i++) { v.x = 30; m.step(); m.events.length = 0; }
  const after = flick(m, v, 6.2);
  check('the mark fades after markFrames', after.types.includes('crackmark') && !after.types.includes('crack'), `${M.markFrames} frames later: ${after.types.join(',')}`);
  m.combat.resolveHit(v, a, v.char.moves.LightNeutral1, null, null, {});
  check('being hit wipes it', a.mech.mark === -1, `after a hit on the whip user: mark ${a.mech.mark}`);
}

// ---- only a landed tip cracks ----
{
  // A marked foe shielding a tip: the block is the same as on an unmarked foe - no bonus shield
  // damage - and the mark is still there for a tip that lands. (Codex's review found a blocked tip
  // taking the bonus and keeping the mark, so a shield could be cracked over and over.)
  const shieldAfter = (marked) => {
    const m = duel(); const a = m.fighters[0], v = m.fighters[1];
    if (marked) { a.mech.mark = v.index; a.mech.expires = a.frameCount + 200; }
    const r = flick(m, v, 6.2, { shield: true });
    return { shield: v.shield, types: r.types, mark: a.mech.mark, v };
  };
  const plain = shieldAfter(false), marked = shieldAfter(true);
  check('a blocked tip on a marked foe neither cracks nor spends the mark', plain.types.includes('block') && marked.types.includes('block')
      && Math.abs(plain.shield - marked.shield) < 1e-9 && marked.mark === marked.v.index && !marked.types.includes('crack'),
    `shield left: ${plain.shield.toFixed(2)} unmarked, ${marked.shield.toFixed(2)} marked; mark ${marked.mark === marked.v.index ? 'kept' : 'lost'}`);
  // A light the whip user armours through (a heavy's startup) is not a hit on them: the mark stays,
  // as every other mechanic's state does (Momentum, Surge, Draw are wiped by applyHit alone).
  const m = duel(); const a = m.fighters[0], v = m.fighters[1];
  v.x = a.x + 2; a.mech.mark = v.index; a.mech.expires = a.frameCount + 200;
  a.startMove('SigSide');
  m.combat.events.length = 0;
  v.moveSerial++; m.combat.resolveHit(v, a, v.char.moves.LightNeutral1, null, null, {});
  check('a hit the whip user armours through keeps their mark', m.combat.events.some((e) => e.type === 'armor') && a.mech.mark === v.index,
    `events ${m.combat.events.map((e) => e.type).join(',')}, mark ${a.mech.mark}`);
}

// ---- Storm Lash: a dome ----
{
  const S = W.moves.Ultimate.stormlash;
  const run = (gap) => {
    const m = duel();
    const a = m.fighters[0], v = m.fighters[1];
    v.x = gap; v.facing = -1;
    a.ultCharge = ULTIMATE.hitsRequired;
    m._input.set('p0', { ult: true, anyPress: true }); m.step(); m._input.clear('p0');
    let cracks = 0;
    for (let i = 0; i < 160 && (a.state === 'attack' || a.hitlag > 0); i++) {
      m.step();
      for (const e of m.events) if (e.type === 'lash') cracks++;
      m.events.length = 0;
      if (v.y < -4 || v.state === 'ko') break;
    }
    return { pct: v.percent, cracks };
  };
  const edge = run(S.radius), inside = run(1.6);
  check('Storm Lash hits a foe on its edge, and not one inside it', edge.pct > 15 && inside.pct === 0 && edge.cracks === S.sweeps * S.perSweep + 1,
    `on the edge (${S.radius} studs): ${edge.pct}%; next to the whip user: ${inside.pct}%; ${edge.cracks} cracks`);
}

// ---- the lash is drawn where the crack is ----
// On every live frame of every move with a tip, the end of the drawn lash - the renderer's own
// geometry: the arm from the shoulder, the handle, the lash beyond it - is inside the tip's box;
// and through Storm Lash it is on the dome where each crack lands.
{
  const { posedFighter } = await import('../src/render2d/preview.js');
  const { buildLoadout } = await import('../src/data/loadout.js');
  const { weaponPose, REACH } = await import('../src/render2d/weapons2d.js');
  const { channelsFor } = await import('../src/render2d/channels.js');
  const { lashPoint } = await import('../src/engine/combat.js');
  const char = buildLoadout('Classic', 'Whip');
  const h = char.height, r = char.radius;
  const tipOf = (f, wp) => {
    const AL = h * 0.30 * (channelsFor(f, 0.3).armR.ext || 1);
    const L = AL + REACH.Whip + wp.lash.len;
    return { x: r * 0.55 + Math.cos(wp.angle) * L, y: h * 0.70 + Math.sin(wp.angle) * L, straight: wp.lash.curl === 0 };
  };
  const off = [];
  let frames = 0;
  for (const [id, m] of Object.entries(char.moves)) {
    const tip = (m.hitboxes || []).find((hb) => hb.tip);
    if (!tip) continue;
    for (let mf = tip.frames[0]; mf <= tip.frames[1]; mf++) {
      const f = posedFighter(char, id, mf, { frameCount: mf });
      const p = tipOf(f, weaponPose(f, 0.3));
      // on the box's centre, not merely inside it: the lash is sized to reach exactly there
      const d = Math.hypot(p.x - tip.offset[0], p.y - tip.offset[1]);
      frames++;
      if (!p.straight || d > 0.05) off.push(`${m.label} f${mf}: ${d.toFixed(2)} studs off the box's centre${p.straight ? '' : ', curled'}`);
    }
  }
  const U = char.moves.Ultimate, S = U.stormlash;
  let worst = 0, cracks = 0;
  for (let i = 0; i <= S.sweeps * S.perSweep; i++) {
    const mf = U.startup + 1 + i * S.every;
    const f = posedFighter(char, 'Ultimate', mf, { frameCount: mf });
    const p = tipOf(f, weaponPose(f, 0.3)), q = lashPoint(S, i);
    worst = Math.max(worst, Math.hypot(p.x - q.dx, p.y - q.dy)); cracks++;
  }
  check('the drawn lash ends on the tip box on every live frame, and on every crack of Storm Lash', off.length === 0 && worst < 0.05,
    off.length ? off.slice(0, 6).join('; ') : `${frames} live tip frames on their box's centre; ${cracks} cracks, the drawn tip at most ${worst.toFixed(3)} studs from each`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
