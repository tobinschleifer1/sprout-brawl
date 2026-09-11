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

// ---- 6. difficulty scaling — A KNOWN OPEN DEFECT, pinned so it cannot get worse ----
//
// Difficulty barely does anything, and it took three sample sizes to establish that honestly.
// At 14 games the same duel returned 3/14 then 7/14; at 20 games the stock ratio read 0.84 and
// then 1.91. Both of those were noise, and either could have been written up as a finding. At 80
// games it settles: just_dont beats easy 83 stocks to 76 — a ratio of 1.09 — and hard vs easy is
// exactly 73 to 73. The scale is not inverted. It is FLAT: the hardest bot in the game is about
// nine percent better than the easiest, and two of the six levels are indistinguishable.
//
// Diagnosed so far, and partly fixed: the top levels re-rolled their plan every frame because plan
// churn was tied to `reaction` (now `commit`); and at defence 1.0 / dodge 1.0 they spent 11% of the
// match spot-dodging and attacked less than Normal, because taking every defensive option available
// is not skill (now rate-limited and converted into a punish). Those moved the ratio from 0.74 to
// 0.84. Something else is still upside down — most likely that aggression and air time rise with
// level while conversion does not, so the better bots simply expose themselves more.
//
// The bar below is deliberately near the floor, because this metric is too noisy at any sample
// size a test suite can afford: at forty games it flaked below 0.7 on the first run after being
// set there. It exists to catch the scale going CATASTROPHICALLY backwards — the hardest bot
// losing two stocks to one — and to print the number every run so the trend is visible. It does
// not certify anything. The target is a ratio above 1.5 and getting there is open work.
{
  const ratio = (lo, hi, n) => {
    let hiS = 0, loS = 0, games = 0;
    for (let g = 0; g < n; g++) {
      const m = makeMatch({ mode: 'StockFFA', stocks: 3, loadouts: [['Classic', 'Sword'], ['Noir', 'Sword']] });
      skipCountdown(m);
      m.fighters[0].isBot = true; m.fighters[0].botLevel = lo;
      m.fighters[1].isBot = true; m.fighters[1].botLevel = hi;
      for (let i = 0; i < 60 * 400 && m.state !== 'results'; i++) { m.step(); m.events.length = 0; }
      if (m.state === 'results') { games++; hiS += m.fighters[1].stocksLeft(); loS += m.fighters[0].stocksLeft(); }
    }
    return { r: hiS / Math.max(1, loS), hiS, loS, games };
  };
  const top = ratio('easy', 'just_dont', 40);
  check('difficulty scaling has not collapsed (KNOWN DEFECT: it is flat, target >1.5)', top.r >= 0.45,
    `just_dont vs easy over ${top.games} games: ${top.hiS} stocks to ${top.loS}, ratio ${top.r.toFixed(2)} — ` +
    `1.09 over 80 games, target >1.5. This number swings 0.74-1.91 between runs; only a collapse below 0.45 fails.`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
