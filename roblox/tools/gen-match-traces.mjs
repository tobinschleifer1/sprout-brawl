// Record whole matches: countdown, KOs, respawns, stocks, the timer, sudden death and results.
//
//     node tools/gen-match-traces.mjs
//
// Match is where the parts meet, so these are full matches rather than probes - but scripted, not
// fought, because bots are the next phase and a match with no inputs never ends. `set` writes
// straight onto a fighter, which is how a KO happens on a frame the scenario chooses rather than
// whenever two scripted fighters happen to connect.
//
// Numbers are strings. See tools/gen-traces.mjs.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const { Match } = await import('../../web/src/engine/match.js');
const { STAGES } = await import('../../web/src/data/stages/index.js');
const { buildLoadout } = await import('../../web/src/data/loadout.js');
const { emptyFrame } = await import('../../web/src/engine/input.js');

const n = (v) => (typeof v === 'number' ? String(v) : v);
const nn = (v) => (v === null || v === undefined ? null : String(v));

// Per-fighter state that a match decides, as opposed to what a fighter decides for itself.
const F = ['x', 'y', 'percent', 'stocks', 'alive', 'state', 'koTimer', 'invincible', 'facing'];

function fakeInput(script) {
  return {
    kb2Active: false,
    poll() {},
    get(source) { return script[source] || emptyFrame(); },
  };
}

function run(spec) {
  const data = STAGES.find((s) => s.id === spec.stage);
  const script = {};
  const input = fakeInput(script);
  const m = new Match({
    mode: spec.mode, stage: data, input, seed: spec.seed ?? 7,
    stocks: spec.stocks ?? 3, timeLimit: spec.timeLimit ?? 180, items: !!spec.items,
    fighters: spec.who.map(([a, w], i) => ({
      char: buildLoadout(a, w), skin: 0, team: spec.teamOf ? spec.teamOf[i] : i,
      source: `p${i}`, isBot: false, name: `P${i}`,
    })),
  });

  const rows = [];
  let frame = 0;
  for (const seg of spec.segments) {
    for (let i = 0; i < seg.frames; i++, frame++) {
      if (seg.set) for (const [k, kv] of Object.entries(seg.set)) {
        for (const [field, value] of Object.entries(kv)) m.fighters[Number(k)][field] = value;
        // `lastHitBy` has to be a fighter, which a JSON scenario cannot carry, so `selfHit` asks
        // for the fighter to be their own last attacker.
        if (kv.selfHit) m.fighters[Number(k)].lastHitBy = m.fighters[Number(k)];
      }
      for (let k = 0; k < m.fighters.length; k++) {
        script[`p${k}`] = Object.assign(emptyFrame(), (seg.in && seg.in[k]) || {});
      }
      m.events.length = 0;
      m.step();
      const row = [m.state, n(m.frame), n(m.time), n(m.countdown), n(m.sdTimer),
        String(m.timed), String(m.training)];
      for (const f of m.fighters) {
        for (const k of F) row.push(n(f[k]));
        row.push(n(f.stocksLeft()));
        row.push(nn(f.eliminatedAt));
      }
      row.push(Object.keys(m.teamPool).sort().map((t) => `${t}=${m.teamPool[t]}`).join(','));
      row.push(m.events.map((e) => [e.type, nn(e.n), nn(e.fighter), nn(e.by), nn(e.side),
        e.last === undefined ? null : e.last, nn(e.winner), nn(e.x), nn(e.y)]));
      row.push(m.results ? m.results.rows.map((r) => [String(r.index), n(r.kos), n(r.falls),
        n(r.sds), n(r.damage), n(r.percent), n(r.stocks), n(r.score),
        r.eliminatedAt === Infinity ? 'inf' : n(r.eliminatedAt)]) : null);
      row.push(m.results ? String(m.results.winnerTeam) : null);
      rows.push(row);
      if (m.state === 'results') break;
    }
    if (m.state === 'results') break;
  }
  return rows;
}

const hold = (frames, inp, set) => ({ frames, in: inp || {}, set });

// Fighters spawn in the `respawn` state and stay there for 180 frames unless somebody presses
// something, so a scenario that opens with silence has two inert bodies for three seconds. Every
// scenario that needs an actual hit drops in first. (Found the hard way: three credit scenarios all
// recorded `by: -1` because the attacker was still falling in when it swung.)
const DROP_IN = { 0: { anyPress: true }, 1: { anyPress: true } };
const S = [];
const TWO = [['Classic', 'Sword'], ['Noir', 'Sword']];

// The countdown itself: 3.5 seconds, three count events, then GO, and the clock starts on GO.
S.push({ name: 'countdown', mode: 'StockFFA', stage: 'FoundryFloor', who: TWO, stocks: 3,
  segments: [hold(260, {})] });

// One stock each, one fighter thrown past the side blast zone: KO, credit, elimination, results.
S.push({ name: 'stock KO ends the match', mode: 'StockFFA', stage: 'FoundryFloor', who: TWO, stocks: 1,
  segments: [hold(230, {}), { frames: 1, in: {}, set: { 1: { x: 400 } } }, hold(200, {})] });

// Three stocks: repeated KOs and respawns, ending when one side runs out.
S.push({ name: 'three stocks', mode: 'StockFFA', stage: 'FoundryFloor', who: TWO, stocks: 3,
  segments: [hold(230, {}),
    ...Array.from({ length: 4 }, () => [{ frames: 1, in: {}, set: { 1: { x: 400 } } }, hold(190, {})]).flat()] });

// A self-destruct: nobody to credit, so it counts against the fighter who did it.
S.push({ name: 'self destruct', mode: 'StockFFA', stage: 'FoundryFloor', who: TWO, stocks: 2,
  segments: [hold(230, {}), { frames: 1, in: {}, set: { 0: { y: -400 } } }, hold(260, {}),
    { frames: 1, in: {}, set: { 0: { y: -400 } } }, hold(200, {})] });

// A credited KO: hit first, then across the line 200 frames later - inside the 480-frame window but
// well outside a short one. The first version left only 41 frames between the two, so shortening
// the window to 60 changed nothing.
S.push({ name: 'credited KO', mode: 'StockFFA', stage: 'FoundryFloor', who: TWO, stocks: 1,
  segments: [hold(212, {}), hold(4, DROP_IN), hold(30, {}),
    { frames: 1, in: { 0: { light: true, anyPress: true } }, set: { 0: { x: -1.2 }, 1: { x: 1.2 } } },
    hold(200, {}), { frames: 1, in: {}, set: { 1: { x: 400 } } }, hold(200, {})] });

// And one just OUTSIDE the window: hit, then 500 frames of nothing, then a fall. Nobody gets the
// credit, so it counts as a self-destruct.
S.push({ name: 'credit expired', mode: 'StockFFA', stage: 'FoundryFloor', who: TWO, stocks: 1,
  segments: [hold(212, {}), hold(4, DROP_IN), hold(30, {}),
    { frames: 1, in: { 0: { light: true, anyPress: true } }, set: { 0: { x: -1.2 }, 1: { x: 1.2 } } },
    hold(500, {}), { frames: 1, in: {}, set: { 1: { x: 400 } } }, hold(200, {})] });

// A gap of about 1,200 frames: outside the 480-frame window, inside any careless widening of it.
// Reaching it by waiting would mean twenty seconds of trace for one boolean, so `lastHitFrame` is
// wound back instead - the real hit above still supplies `lastHitBy`.
S.push({ name: 'credit far outside the window', mode: 'StockFFA', stage: 'FoundryFloor', who: TWO,
  stocks: 1,
  segments: [hold(212, {}), hold(4, DROP_IN), hold(30, {}),
    { frames: 1, in: { 0: { light: true, anyPress: true } }, set: { 0: { x: -1.2 }, 1: { x: 1.2 } } },
    hold(20, {}), { frames: 1, in: {}, set: { 1: { lastHitFrame: -960 } } },
    hold(2, {}), { frames: 1, in: {}, set: { 1: { x: 400 } } }, hold(200, {})] });

// `credit !== f` guards against crediting a fighter for their own death, which needs lastHitBy to
// point at the victim themselves. Nothing in a normal match does that - self-damage goes through
// percent, not applyHit - so it is set directly.
S.push({ name: 'self-credited KO', mode: 'StockFFA', stage: 'FoundryFloor', who: TWO, stocks: 1,
  segments: [hold(230, {}),
    { frames: 1, in: {}, set: { 1: { selfHit: true, lastHitFrame: 0 } } },
    hold(2, {}), { frames: 1, in: {}, set: { 1: { x: 400 } } }, hold(200, {})] });

// Timed mode: the clock decides it, and a KO costs nothing but the respawn wait.
S.push({ name: 'timed, decided on score', mode: 'TimedFFA', stage: 'FoundryFloor', who: TWO,
  stocks: 3, timeLimit: 6,
  segments: [hold(230, {}), { frames: 1, in: {}, set: { 1: { x: 400 } } }, hold(500, {})] });

// Timed mode ending level: sudden death, the stage closing in, and a winner.
S.push({ name: 'timed into sudden death', mode: 'TimedFFA', stage: 'FoundryFloor', who: TWO,
  stocks: 3, timeLimit: 4,
  segments: [hold(230, {}), hold(300, {}),
    ...Array.from({ length: 8 }, () => hold(120, {})),
    { frames: 1, in: {}, set: { 1: { x: 400 } } }, hold(200, {})] });

// Teams: the pool is shared, so one fighter's KO spends the team's stock.
S.push({ name: 'teams share a stock pool', mode: 'StockTeams', stage: 'FoundryFloor',
  who: [['Classic', 'Sword'], ['Noir', 'Sword'], ['Ember', 'Sword'], ['Moss', 'Sword']],
  teamOf: [0, 0, 1, 1], stocks: 2,
  segments: [hold(230, {}),
    ...Array.from({ length: 5 }, (_, i) => [{ frames: 1, in: {}, set: { [2 + (i % 2)]: { x: 400 } } },
      hold(190, {})]).flat()] });

// Training never ends and never spends a stock.
S.push({ name: 'training', mode: 'Training', stage: 'FoundryFloor', who: TWO, stocks: 3,
  segments: [hold(230, {}), { frames: 1, in: {}, set: { 1: { x: 400 } } }, hold(300, {})] });

// Items on, so maybeSpawnItem runs off the match's own seed for a full spawn interval.
S.push({ name: 'items spawning in a match', mode: 'StockFFA', stage: 'FoundryFloor', who: TWO,
  stocks: 3, items: true, seed: 99,
  segments: [hold(1100, {})] });

// A different stage, so the spawn list and the blast box are not Foundry Floor's.
S.push({ name: 'undertow match', mode: 'StockFFA', stage: 'Undertow', who: TWO, stocks: 2,
  segments: [hold(230, {}), { frames: 1, in: {}, set: { 0: { x: -400 } } }, hold(260, {}),
    { frames: 1, in: {}, set: { 0: { x: -400 } } }, hold(200, {})] });

const scenarios = S.map((spec) => ({ ...spec, rows: run(spec) }));
fs.writeFileSync(path.join(HERE, '../tests/trace-match.json'), JSON.stringify({ fields: F, scenarios }));
const frames = scenarios.reduce((s, x) => s + x.rows.length, 0);
console.log(`match traces: ${scenarios.length} scenarios, ${frames} frames`);
