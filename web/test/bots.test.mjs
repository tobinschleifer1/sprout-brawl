// Do the bots actually play the game?
//
// Nothing tested them before, and three things had been quietly broken for a long time:
//
//   - No bot had ever pressed the ultimate key. Every ultimate in the game was player-only, so a
//     bot match never once showed the moves several rounds of work went into.
//   - The menu offers "Bot · Impossible" and the level table spelled the key `imposible`, so that
//     option silently played at Normal.
//   - Four of the seven archetype branches tested strings no weapon has ('Charge', 'Trap',
//     'Summoner', 'Grappler'), which made two whole plans unreachable and dropped Grimoire — the
//     heaviest zoner in the game — into the melee branch.
//
// All three are the same failure: behaviour asserted in code and never observed. So these checks
// run real matches and watch what the bots do.
import { makeMatch, skipCountdown } from './harness.mjs';
import { WEAPONS } from '../src/data/weapons/index.js';
import { ULTIMATE } from '../src/config.js';
import { STAGES } from '../src/data/stages/index.js';
import { CHAINS, LEVELS } from '../src/engine/ai.js';
import { readFileSync } from 'node:fs';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };

const AV = ['Classic', 'Noir', 'Ember', 'Moss'];
function botMatch(opts = {}) {
  const m = makeMatch({ mode: 'StockFFA', stocks: opts.stocks ?? 3, stageId: opts.stageId,
    loadouts: (opts.weapons || ['Sword', 'Scythe']).map((w, i) => [AV[i % 4], w]) });
  m.itemsOn = !!opts.items;
  m.fighters.forEach((f, i) => { f.isBot = true; f.botLevel = opts.level || 'hard'; });
  skipCountdown(m);
  return m;
}

// ---- 1. every bot level the menu offers is a level the AI actually has ----
{
  const menu = readFileSync(new URL('../src/ui/menus.js', import.meta.url), 'utf8');
  const ai = readFileSync(new URL('../src/engine/ai.js', import.meta.url), 'utf8');
  const offered = [...menu.matchAll(/\['bot-([a-z_]+)'/g)].map((mm) => mm[1]);
  const missing = offered.filter((lvl) => !new RegExp(`(^|[^a-z])${lvl}\\s*:`, 'm').test(ai));
  check('every bot difficulty in the menu exists in the AI', missing.length === 0,
    missing.length ? `the menu offers ${missing.join(', ')} but the level table has no such key — it silently plays at Normal`
      : `${offered.length} levels offered and defined: ${offered.join(', ')}`);
}

// ---- 2. no archetype branch tests a string no weapon has ----
{
  const ai = readFileSync(new URL('../src/engine/ai.js', import.meta.url), 'utf8');
  const real = new Set(WEAPONS.map((w) => w.archetype));
  const tested = [...ai.matchAll(/arche(?:type)? === '([^']+)'/g)].map((mm) => mm[1]);
  const dead = [...new Set(tested)].filter((a) => !real.has(a));
  check('every archetype the AI branches on is one a weapon has', dead.length === 0,
    dead.length ? `dead branches on: ${dead.join(', ')} — real archetypes are ${[...real].join(', ')}`
      : `${[...new Set(tested)].length} archetypes tested, all real: ${[...new Set(tested)].join(', ')}`);
}

// ---- 3. a bot with a full meter actually spends it, on every weapon ----
{
  const never = [], rows = [];
  for (const w of WEAPONS) {
    const m = botMatch({ weapons: [w.id, 'Sword'], level: 'hard' });
    const [a] = m.fighters;
    let fired = 0;
    for (let i = 0; i < 60 * 60; i++) {
      // keep the bar full so this measures the DECISION, not how fast it can charge one
      if (!a.ultActive) a.ultCharge = ULTIMATE.hitsRequired;
      m.step();
      for (const e of m.events) if (e.type === 'ultimate' && e.fighter === a.index) fired++;
      m.events.length = 0;
      if (m.state === 'results') break;
    }
    rows.push(`${w.id} ${fired}`);
    if (!fired) never.push(w.id);
  }
  check('a bot spends its ultimate, on every weapon', never.length === 0,
    never.length ? `never fired with: ${never.join(', ')}` : `activations in 60s with a full bar: ${rows.join(', ')}`);
}

// ---- 4. Deadeye is a stance: the bot must spend all three rounds, not one ----
{
  const m = botMatch({ weapons: ['Blasters', 'Sword'], level: 'hard' });
  const [a] = m.fighters;
  let shots = 0, activations = 0;
  for (let i = 0; i < 60 * 90; i++) {
    if (!a.ultActive) a.ultCharge = ULTIMATE.hitsRequired;
    m.step();
    for (const e of m.events) { if (e.type === 'snipe') shots++; if (e.type === 'ultimate' && e.fighter === a.index) activations++; }
    m.events.length = 0;
    if (m.state === 'results') break;
  }
  const per = activations ? shots / activations : 0;
  check('a bot empties the Deadeye magazine', activations > 0 && per >= 2.4,
    `${activations} activations, ${shots} rounds fired — ${per.toFixed(1)} of 3 per stance`);
}

// ---- 5. bots do not kill themselves ----
// The cheapest measure of whether the movement logic is coherent: how often a bot dies when nobody
// ever touched it.
//
// The first version of this check asked whether anyone had hit the victim in the last 90 frames
// and reported 73% — which was the measurement, not the bots. Measured properly, the median gap
// between a fighter's last hit and its death is 305 frames: being knocked off and failing to
// recover is most of a platform fighter's KOs and takes seconds to resolve. A true self-destruct
// is one where the victim was never hit at all, and that is 10%.
{
  let selfKO = 0, total = 0;
  for (const d of STAGES) {
    const m = botMatch({ stageId: d.id, weapons: ['Sword', 'Scythe', 'Blasters', 'Grimoire'], level: 'hard', stocks: 2 });
    for (let i = 0; i < 60 * 240 && m.state !== 'results'; i++) {
      m.step();
      for (const e of m.events) {
        if (e.type !== 'ko') continue;
        total++;
        const v = m.fighters[e.fighter];
        if (!v.lastHitBy) selfKO++;               // never hit by anyone, the whole stock
      }
      m.events.length = 0;
    }
  }
  const rate = total ? selfKO / total : 0;
  check('bots rarely kill themselves', total > 0 && rate < 0.2,
    `${selfKO} of ${total} KOs across six stages were fighters nobody had ever hit (${(rate * 100).toFixed(0)}%)`);
}

// ---- 6. difficulty is a LADDER: each level beats the one below it ----
//
// This check used to be pinned near the floor with a comment calling difficulty a known defect,
// because it was: over eighty games the hardest bot beat the easiest 83 stocks to 76, a ratio of
// 1.09, and two of the six levels were indistinguishable. Three rounds of work went into the AI
// looking for the cause.
//
// The cause was not in the AI at all. A grounded lunge left its drive speed in `vx` when the
// active frames ended and the airborne branch of _stepAttack was skipped for any move with a
// lunge, so a signature thrown near an edge carried its own user off the stage - and the levels
// most likely to throw one are the aggressive ones. Aggression, the only dial difficulty was
// turning, was literally a suicide rate. Fixing the lunge (see engine.test.mjs checks 10 and 11)
// moved this from 1.09 to 4.75 on its own.
//
// The second half is perception. Difficulty now handicaps what a bot can SEE - `sight` frames of
// staleness in its view of the opponent, 26 at easy and 0 at the top - which is how the fighting
// game AI literature does it and is the reason the rungs below are separated rather than merely
// ordered.
{
  // SEEDED, one distinct seed per game. The bots used to draw from Math.random, so this test was
  // a different experiment every run and failed roughly one run in twenty with nothing behind it.
  // Sixteen fixed seeds is still a real sample - it is a fixed one, so a failure is reproducible
  // and a pass means the same thing tomorrow.
  const ladder = (lo, hi, n, rung) => {
    let hiS = 0, loS = 0, games = 0;
    for (let g = 0; g < n; g++) {
      const m = makeMatch({ mode: 'StockFFA', stocks: 3, seed: g * 7919 + rung * 104729,
        loadouts: [['Classic', 'Sword'], ['Noir', 'Sword']] });
      skipCountdown(m);
      m.fighters[0].isBot = true; m.fighters[0].botLevel = lo;
      m.fighters[1].isBot = true; m.fighters[1].botLevel = hi;
      for (let i = 0; i < 60 * 400 && m.state !== 'results'; i++) { m.step(); m.events.length = 0; }
      if (m.state === 'results') { games++; hiS += m.fighters[1].stocksLeft(); loS += m.fighters[0].stocksLeft(); }
    }
    return { r: hiS / Math.max(1, loS), hiS, loS, games };
  };
  const RUNGS = [['easy', 'normal'], ['normal', 'hard'], ['hard', 'just_dont']];
  const rows = [], weak = [];
  for (const [lo, hi] of RUNGS) {
    const d = ladder(lo, hi, 16, RUNGS.findIndex((r) => r[1] === hi));
    rows.push(`${hi} beat ${lo} ${d.hiS}-${d.loS} (${d.r.toFixed(1)}x over ${d.games})`);
    // The bar is deliberately far below what these actually measure (4x to 75x on longer runs).
    // Sixteen games is a small sample, so this exists to catch the LADDER BREAKING, not to
    // certify a number.
    if (d.r < 1.2) weak.push(`${hi} vs ${lo} only ${d.r.toFixed(2)}x`);
  }
  check('every difficulty beats the one below it', weak.length === 0,
    weak.length ? `${weak.join('; ')} — the ladder has a flat or inverted rung` : rows.join(' | '));
}

// ---- 7. every chain the AI defines can actually be started ----
//
// Chains are the committed input sequences borrowed from SmashBot's Strategy / Tactic / Chain
// split. The first version of `shieldGrab` was unreachable: it was selected in the tactic block,
// but a shield plan is set by the threat-reaction branch above it, which returns first. It was
// written, gated by level, and never once run.
//
// That is the fourth time this project has shipped authored-but-unreachable behaviour (spinY and
// spinZ, env.grip, five ultimate VFX channels, palette.glows), so it gets a check rather than
// another fix. Real matches, and watch what the bots actually start.
{
  const started = new Set();
  const byLevel = {};
  for (const lvl of ['easy', 'normal', 'hard', 'just_dont']) {
    const m = botMatch({ weapons: ['Sword', 'Axe'], level: lvl });
    const here = new Set();
    for (let i = 0; i < 60 * 100 && m.state !== 'results'; i++) {
      m.step(); m.events.length = 0;
      for (const f of m.fighters) if (f.ai && f.ai.chain) { started.add(f.ai.chain.name); here.add(f.ai.chain.name); }
    }
    byLevel[lvl] = [...here];
  }
  const never = Object.keys(CHAINS).filter((k) => !started.has(k));
  // and the gate has to bite: a level that knows no chains must start none
  const leak = byLevel.easy.length ? `easy knows ${LEVELS.easy.chains} chains but started ${byLevel.easy.join(', ')}` : null;
  check('every chain the AI defines is reachable, and the level gate holds', never.length === 0 && !leak,
    never.length ? `defined but never started: ${never.join(', ')}` : leak
      || Object.entries(byLevel).map(([k, v]) => `${k}: ${v.length ? v.join('+') : 'none'}`).join(' | '));
}

// ---- 8. a bot's view of its opponent is as stale as its level says ----
//
// Perception delay is the difficulty lever now, so it has to be real: an `easy` bot must actually
// be reading a stale world, and the top level must be reading the current one. Measured by moving
// a fighter and asking what each level would have seen.
{
  const m = makeMatch({ mode: 'StockFFA', stocks: 3, loadouts: [['Classic', 'Sword'], ['Noir', 'Sword']] });
  skipCountdown(m);
  m.fighters.forEach((f) => { f.isBot = true; f.botLevel = 'hard'; });
  const [a, b] = m.fighters;
  // drive B across the stage for a while so there is a history with real spread in it
  for (let i = 0; i < 90; i++) { b.x = i * 0.4; m.step(); m.events.length = 0; }
  const buf = m._aiHist.ring.get(b);
  // The newest entry is what a bot with sight 0 reads. It is NOT the same as b.x after the step:
  // the ring is written while the bot is deciding, and the world keeps moving after that. The
  // invariant is staleness relative to that newest entry, which is what "sight" actually means.
  const newest = buf[buf.length - 1].x;
  const rows = [], bad = [];
  let prevLag = -1, prevName = '';
  // `imposible` is a deliberate alias for the same object (the menu shipped that spelling), so
  // dedupe by identity or the ladder below compares a level against itself.
  const uniq = [], seenL = new Set();
  for (const [lvl, L] of Object.entries(LEVELS)) { if (!L || seenL.has(L)) continue; seenL.add(L); uniq.push([lvl, L]); }
  for (const [lvl, L] of uniq.sort((p, q) => q[1].sight - p[1].sight)) {
    const lag = Math.abs(newest - buf[Math.max(0, buf.length - 1 - L.sight)].x);
    rows.push(`${lvl} sight ${L.sight} = ${lag.toFixed(1)} studs behind`);
    if (L.sight === 0 && lag > 1e-9) bad.push(`${lvl} has sight 0 but reads a stale snapshot`);
    if (L.sight > 0 && lag <= 0) bad.push(`${lvl} has sight ${L.sight} but reads the newest snapshot`);
    if (prevLag >= 0 && lag >= prevLag) bad.push(`${lvl} is not sharper than ${prevName} (${lag.toFixed(1)} vs ${prevLag.toFixed(1)})`);
    prevLag = lag; prevName = lvl;
  }
  check('a bot sees the world as late as its difficulty says', bad.length === 0,
    bad.length ? bad.join('; ') : `against an opponent crossing the stage: ${rows.join(', ')}`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
