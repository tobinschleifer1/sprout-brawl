// Readability: what the engine tells the screen so a fight can be read (docs/briefs/combat-plan.md,
// phase 1).
//
//   * the kill hit (KILL_HIT): a hit whose launch, left alone, carries its victim past a side or the
//     top blast line says `kill` on its event - and only then: the same hit at low percent does not;
//   * it predicts and changes nothing: a match with the prediction answering "no" every time plays
//     out frame for frame the same as one without;
//   * it is right when it says so: across real bot matches most marked hits KO, and a good share of
//     the side and top KOs were marked (the numbers are in config.js beside KILL_HIT).
//
//     node test/readability.test.mjs
import { makeMatch, skipCountdown } from './harness.mjs';
import { WEAPON_BY_ID } from '../src/data/weapons/index.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };

// Two fighters planted on the main floor, the attacker at x facing the victim.
function planted(x = 0) {
  const m = skipCountdown(makeMatch({ loadouts: [['Classic', 'Hammer'], ['Noir', 'Sword']] }));
  const [a, b] = m.fighters;
  a.x = x; b.x = x + 2.5; a.facing = 1; b.facing = -1;
  for (const f of [a, b]) { f.y = 0; f.vx = 0; f.vy = 0; f.onGround = true; f.platform = m.stage.main; f.setState('idle'); f.invincible = 0; }
  return { m, a, b };
}
// The hammer's heaviest ground move, landed on b at `percent`: the hit event, and whether b is KO'd.
function heavyAt(percent) {
  const { m, a, b } = planted();
  const move = WEAPON_BY_ID.Hammer.moves.SigSide || Object.values(WEAPON_BY_ID.Hammer.moves).find((mv) => mv.heavy);
  b.percent = percent;
  m.events.length = 0;
  m.combat.resolveHit(a, b, move, null, null, {});
  m.step();
  const hit = m.events.find((e) => e.type === 'hit');
  let ko = false;
  for (let i = 0; i < 400 && !ko; i++) { m.step(); ko = m.events.some((e) => e.type === 'ko' && e.fighter === b.index); m.events.length = 0; }
  return { hit, ko };
}

// ---- the kill hit is marked, and only the kill hit ----
{
  const high = heavyAt(300), low = heavyAt(10);
  check('a hit that carries its victim out says `kill`', high.hit && high.hit.kill === true && high.ko,
    `at 300%: kill=${high.hit && high.hit.kill}, KO'd ${high.ko}`);
  check('the same hit at low percent does not', low.hit && low.hit.kill === false && !low.ko,
    `at 10%: kill=${low.hit && low.hit.kill}, KO'd ${low.ko}`);
}

// ---- it changes nothing ----
{
  // Several seeds, so the check never rests on one match happening to land a kill hit.
  const run = (seed, silence) => {
    const m = skipCountdown(makeMatch({ mode: 'StockFFA', stocks: 3, seed,
      armed: [['Classic', ['Sword', 'Hammer']], ['Noir', ['Daggers', 'Axe']], ['Ember', ['Pike', 'Shield']], ['Moss', ['Scythe', 'Flail']]] }));
    m.fighters.forEach((f) => { f.isBot = true; f.botLevel = 'elite'; });
    if (silence) m.combat.killHit = () => false;
    let kills = 0;
    for (let i = 0; i < 60 * 240 && m.state !== 'results'; i++) {
      m.step();
      for (const e of m.events) if (e.type === 'hit' && e.kill) kills++;
      m.events.length = 0;
    }
    return { kills, state: m.fighters.map((f) => [f.x.toFixed(6), f.y.toFixed(6), f.percent, f.stocksLeft(), f.state].join(',')).join(' | '), frame: m.frame };
  };
  let kills = 0, same = true, detail = '';
  for (const seed of [902, 903, 904]) {
    const real = run(seed, false), silent = run(seed, true);
    kills += real.kills;
    if (real.state !== silent.state || real.frame !== silent.frame) { same = false; detail += `\n        seed ${seed}: ${real.state}\n        silenced: ${silent.state}`; }
  }
  check('the prediction is read-only: a match plays out the same without it', same && kills > 0,
    `${kills} kill hits marked across three matches; the runs ${same ? 'match' : `differ:${detail}`}`);
}

// ---- it is usually right ----
{
  const KITS = [['Sword', 'Hammer'], ['Daggers', 'Axe'], ['Pike', 'Shield'], ['Scythe', 'Flail']];
  let marked = 0, markedKO = 0, sideKOs = 0, sideMarked = 0;
  for (let g = 0; g < 24; g++) {
    const n = 2 + (g % 3);
    const m = skipCountdown(makeMatch({ mode: 'StockFFA', stocks: 3, seed: 900 + g, armed: KITS.slice(0, n).map((k, i) => [['Classic', 'Noir', 'Ember', 'Moss'][i], k]) }));
    m.fighters.forEach((f) => { f.isBot = true; f.botLevel = ['normal', 'hard', 'elite'][g % 3]; });
    const last = {};
    for (let i = 0; i < 60 * 300 && m.state !== 'results'; i++) {
      m.step();
      for (const e of m.events) {
        if (e.type === 'hit') { last[e.victim] = { frame: m.frame, kill: !!e.kill }; if (e.kill) marked++; }
        if (e.type === 'ko') {
          const prev = last[e.fighter];
          if (prev && m.frame - prev.frame < 300) {
            if (prev.kill) markedKO++;
            if (e.side !== 'bottom') { sideKOs++; if (prev.kill) sideMarked++; }
          }
          delete last[e.fighter];
        }
      }
      m.events.length = 0;
    }
  }
  const precision = markedKO / marked, recall = sideMarked / sideKOs;
  check('most marked hits KO, and a good share of side and top KOs are marked', precision >= 0.75 && recall >= 0.4,
    `${markedKO} of ${marked} marked hits KO'd (${(100 * precision).toFixed(0)}%); ${sideMarked} of ${sideKOs} side/top KOs after a hit were marked (${(100 * recall).toFixed(0)}%)`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
