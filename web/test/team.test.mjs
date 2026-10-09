// Team play (docs/briefs/combat-plan.md, phase 3).
//
//   * assists (TEAM): whoever else hit the victim within the window gets an assist and meter when
//     they are KO'd - in every mode - and the KO event names them; an older hit does not count, nor
//     does the KO'er;
//   * team combos: hits by two teammates on one held foe are a team combo on the hit event; one
//     attacker alone is not, nor are two attackers on different sides.
//
//     node test/team.test.mjs
import { makeMatch, skipCountdown } from './harness.mjs';
import { TEAM } from '../src/config.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };

// Three or four fighters on the main floor; `teams` gives each one's team.
function arena(teams) {
  const m = skipCountdown(makeMatch({ mode: teams ? 'StockTeams' : 'StockFFA', stocks: 3,
    loadouts: (teams || [0, 1, 2]).map((_, i) => [['Classic', 'Noir', 'Ember', 'Moss'][i], 'Sword']) }));
  m.fighters.forEach((f, i) => {
    if (teams) f.team = teams[i];
    f.x = -6 + i * 3; f.y = 0; f.vx = 0; f.vy = 0; f.onGround = true; f.platform = m.stage.main; f.setState('idle'); f.invincible = 0;
  });
  return m;
}
const hit = (m, a, v) => { a.moveSerial++; v.hitlag = 0; m.combat.events.length = 0; m.combat.resolveHit(a, v, a.char.moves.LightNeutral1, null, null, {}); return m.combat.events.find((e) => e.type === 'hit'); };

// ---- assists ----
{
  const m = arena();
  const [a, b, v] = m.fighters;
  hit(m, b, v);
  for (let i = 0; i < 60; i++) v.frameCount++;
  hit(m, a, v);
  const charge = b.ultCharge;
  m.events.length = 0;
  m.knockOut(v);
  const ko = m.events.find((e) => e.type === 'ko');
  check('whoever else hit them lately gets an assist, and meter', a.stats.kos === 1 && b.stats.assists === 1 && a.stats.assists === 0
      && b.ultCharge === charge + TEAM.assistMeter && JSON.stringify(ko.assists) === JSON.stringify([b.index]) && ko.by === a.index,
    `KO by ${ko.by}, assists ${JSON.stringify(ko.assists)}; b's meter ${charge} -> ${b.ultCharge}`);
  const n = arena();
  const [na, nb, nv] = n.fighters;
  hit(n, nb, nv);
  for (let i = 0; i < TEAM.assistWindow; i++) nv.frameCount++;
  hit(n, na, nv);
  n.events.length = 0;
  n.knockOut(nv);
  const late = n.events.find((e) => e.type === 'ko');
  check('a hit older than the window is not an assist', nb.stats.assists === 0 && late.assists.length === 0,
    `b hit ${TEAM.assistWindow} frames before the KO: assists ${JSON.stringify(late.assists)}`);
  const twice = arena();
  const [ta, tb, tv] = twice.fighters;
  hit(twice, tb, tv); hit(twice, ta, tv);
  twice.knockOut(tv);
  twice.respawn(tv); tv.setState('idle'); tv.invincible = 0;
  twice.events.length = 0;
  const landed = hit(twice, ta, tv);
  twice.knockOut(tv);
  const second = twice.events.find((e) => e.type === 'ko');
  check('a KO clears who hit them: the next life starts with no one owed an assist', landed && second.assists.length === 0 && tb.stats.assists === 1,
    `second KO's assists ${JSON.stringify(second.assists)}; b has ${tb.stats.assists} (from the first)`);
  const r = arena();
  r.knockOut(r.fighters[2]);
  check('the results carry assists', (() => { r.finish(); return r.results.rows.every((row) => row.assists === 0); })(),
    `rows: ${r.results.rows.map((row) => row.assists).join(',')}`);
}

// ---- team combos ----
{
  const m = arena([0, 1, 0, 1]);
  const [a, v, c] = m.fighters;
  const first = hit(m, a, v), second = hit(m, c, v);
  check('two teammates on one held foe make a team combo', first.team === false && second.team === true && second.combo === 2,
    `first hit team=${first.team}, second (the ally's) team=${second.team}, combo ${second.combo}`);
  const solo = arena([0, 1, 0, 1]);
  hit(solo, solo.fighters[0], solo.fighters[1]);
  const again = hit(solo, solo.fighters[0], solo.fighters[1]);
  check('one attacker alone is not', again.team === false && again.combo === 2, `combo ${again.combo}, team=${again.team}`);
  const ffa = arena();
  hit(ffa, ffa.fighters[0], ffa.fighters[2]);
  const rival = hit(ffa, ffa.fighters[1], ffa.fighters[2]);
  check('two attackers on different sides are not', rival.team === false && rival.combo === 2, `combo ${rival.combo}, team=${rival.team}`);
  // the combo ends, and with it who was in it
  v.setState('idle'); m.step(); m.events.length = 0;
  const fresh = hit(m, c, v);
  check('a new combo starts with nobody in it', fresh.team === false && fresh.combo === 1, `combo ${fresh.combo}, team=${fresh.team}`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
