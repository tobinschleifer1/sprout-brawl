// Team play (docs/briefs/combat-plan.md, phase 3).
//
//   * assists (TEAM): whoever else hit the victim within the window gets an assist and meter when
//     they are KO'd - in every mode - and the KO event names them; an older hit does not count, nor
//     does the KO'er;
//   * team combos: hits by two teammates on one held foe are a team combo on the hit event; one
//     attacker alone is not, nor are two attackers on different sides.
//
//   * the save (TEAM.catch): grab pressed with a tumbling teammate in reach catches them - their
//     launch ends, they can act, they are briefly invincible, and the catcher pays a little on the
//     ground; from the air too; not an enemy, not out of reach (that is a grab), once per launch,
//     and again after a new hit.
//
//     node test/team.test.mjs
import { makeMatch, skipCountdown } from './harness.mjs';
import { TEAM } from '../src/config.js';
import { emptyFrame } from '../src/engine/input.js';

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

// ---- the save ----
{
  // a teammate (index 2) launched past the catcher (index 0), who presses grab
  const save = ({ dx = 1.5, dy = 0, team = 0, air = false, again = false } = {}) => {
    const m = arena([0, 1, team, 1]);
    const [c, , ally] = m.fighters;
    const launch = (f) => {
      f.x = c.x + dx; f.y = c.y + dy; f.onGround = false; f.platform = null;
      f.setState('hitstun'); f.hitstun = 30; f.tumbling = true; f.vx = 60; f.vy = 30; f.lastHitFrame = f.frameCount;
    };
    if (air) { c.y = 6; c.onGround = false; c.platform = null; c.setState('air'); c.vy = 0; }
    launch(ally);
    const before = { vx: ally.vx };
    m._input.set('p0', { ...emptyFrame(), grab: true, anyPress: true });
    m.step(); m._input.clear('p0');
    const ev = m.events.find((e) => e.type === 'catch');
    m.events.length = 0;
    let second = null;
    if (again) {
      for (let i = 0; i < 20; i++) m.step();
      m.events.length = 0;
      ally.x = c.x + dx; ally.y = c.y; ally.onGround = false; ally.setState('hitstun'); ally.hitstun = 30; ally.tumbling = true;
      c.setState('idle'); c.lag = 0;
      m._input.set('p0', { ...emptyFrame(), grab: true, anyPress: true }); m.step(); m._input.clear('p0');
      second = m.events.find((e) => e.type === 'catch') || null;
      m.events.length = 0;
      launch(ally); ally.lastHitFrame = ally.frameCount + 1;   // a new hit: a new launch
      ally.x = c.x + dx; ally.y = c.y;
      c.setState('idle'); c.lag = 0;
      m._input.set('p0', { ...emptyFrame(), grab: true, anyPress: true }); m.step(); m._input.clear('p0');
      second = { once: second, fresh: m.events.find((e) => e.type === 'catch') || null };
    }
    return { m, c, ally, ev, before, second };
  };
  const s = save();
  check('grab on a tumbling teammate in reach catches them', s.ev && s.ev.ally === s.ally.index && !s.ally.tumbling && s.ally.state === 'air'
      && s.ally.hitstun === 0 && s.ally.invincible > 0 && Math.abs(s.ally.vx) < s.before.vx * 0.3 && s.ally.jumpsLeft >= 1,
    `ally ${s.ally.state}, tumbling ${s.ally.tumbling}, vx ${s.before.vx} -> ${s.ally.vx.toFixed(1)}, invincible ${s.ally.invincible}, jumps ${s.ally.jumpsLeft}`);
  check('a catch on the ground costs the catcher a moment', s.c.state === 'landing' && s.c.lag > 0, `catcher ${s.c.state}, lag ${s.c.lag}`);
  const a = save({ air: true, dy: 0 });
  check('and it works from the air, for free', a.ev && a.c.state === 'air', `catch ${!!a.ev}, catcher ${a.c.state}`);
  const enemy = save({ team: 1 });
  check('an enemy is not caught', !enemy.ev && enemy.ally.tumbling, `catch ${!!enemy.ev}, their tumble ${enemy.ally.tumbling}`);
  const far = save({ dx: 7 });
  check('out of reach it is just a grab', !far.ev && far.c.state === 'grab' && far.ally.tumbling, `catch ${!!far.ev}, catcher ${far.c.state}`);
  // bots save each other too: four elite bots, two a side, catch a launched team-mate
  const bots = skipCountdown(makeMatch({ mode: 'StockTeams', stocks: 2, seed: 26,
    loadouts: [['Classic', 'Sword'], ['Noir', 'Pike'], ['Ember', 'Axe'], ['Moss', 'Flail']] }));
  bots.fighters.forEach((f, i) => { f.isBot = true; f.botLevel = 'elite'; f.team = [0, 0, 1, 1][i]; });
  let botCatches = 0;
  for (let i = 0; i < 60 * 60 && bots.state !== 'results'; i++) {
    bots.step();
    for (const e of bots.events) if (e.type === 'catch') { botCatches++; if (bots.fighters[e.fighter].team !== bots.fighters[e.ally].team) botCatches = -999; }
    bots.events.length = 0;
  }
  check('bots catch their team-mates, and only them', botCatches > 0, `${botCatches} catches by elite bots in a minute`);
  const twice = save({ again: true });
  check('once per launch, and again after a new hit', twice.ev && !twice.second.once && twice.second.fresh,
    `first ${!!twice.ev}, same launch again ${!!twice.second.once}, after a new hit ${!!twice.second.fresh}`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
