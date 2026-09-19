// Record whole BOT matches, frame by frame.
//
//     node tools/gen-ai-traces.mjs
//
// There is no scripting here and no `set`: the bots play, and the only reason that is reproducible
// at all is that every decision now draws from the match's seeded generator. A single wrong
// comparison anywhere in ai.js sends the whole match somewhere else within a few frames, which
// makes this the bluntest test in the suite and also the most sensitive.
//
// Each bot's internal scratch (`f.ai`) is recorded alongside its position, because a bot can be in
// the right place with the wrong plan, and the plan is what decides the next second of play.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const { Match } = await import('../../web/src/engine/match.js');
const { STAGES } = await import('../../web/src/data/stages/index.js');
const { buildLoadout } = await import('../../web/src/data/loadout.js');
const { emptyFrame } = await import('../../web/src/engine/input.js');
const { ITEM_BY_ID } = await import('../../web/src/data/items.js');

const n = (v) => (typeof v === 'number' ? String(v) : v);
const nn = (v) => (v === null || v === undefined ? null : String(v));

const F = ['x', 'y', 'vx', 'vy', 'facing', 'state', 'percent', 'onGround', 'jumpsLeft', 'alive',
  'stocks', 'moveId', 'ultCharge', 'ultShots', 'hitstun'];
const AI = ['timer', 'plan', 'hold', 'jumpCd', 'ultCd', 'defCd', 'punish', 'fetch', 'fetchCd', 'noFumble'];

const idle = { poll() {}, get() { return emptyFrame(); }, kb2Active: false };

function run(spec) {
  const data = STAGES.find((s) => s.id === spec.stage);
  const m = new Match({
    mode: spec.mode || 'StockFFA', stage: data, input: idle, seed: spec.seed,
    stocks: spec.stocks ?? 3, timeLimit: spec.timeLimit ?? 180, items: !!spec.items,
    fighters: spec.who.map(([a, w, level], i) => ({
      char: buildLoadout(a, w), skin: 0, team: spec.teamOf ? spec.teamOf[i] : i,
      source: `p${i}`, isBot: true, botLevel: level, name: `P${i}`,
    })),
  });

  const rows = [];
  for (let i = 0; i < spec.frames && m.state !== 'results'; i++) {
    // Items on the fourteen-second spawn timer almost never reach a bot: they land somewhere far
    // off, and a bot within five studs of an opponent will not go for one at all. Placing them
    // directly is the only way itemAction's fetch path runs.
    if (spec.drop) for (const d of spec.drop) {
      if (d.at === i) m.combat.spawnItem(ITEM_BY_ID[d.item], d.x, d.y);
    }
    m.events.length = 0;
    m.step();
    const row = [m.state, n(m.frame)];
    for (const f of m.fighters) {
      for (const k of F) row.push(n(f[k]));
      const ai = f.ai;
      for (const k of AI) row.push(ai ? n(ai[k]) : null);
      row.push(ai && ai.chain ? `${ai.chain.name}:${ai.chain.i}:${ai.chain.t}` : null);
    }
    row.push(m.events.map((e) => [e.type, nn(e.fighter), nn(e.by)]));
    rows.push(row);
  }
  return rows;
}

const S = [];
// Every rung of the ladder, so every `sight`, `slip` and `chains` value is exercised. The levels
// differ only in numbers, but those numbers gate whole branches - `chains: 0` never starts one.
for (const level of ['easy', 'normal', 'hard', 'elite', 'impossible', 'just_dont']) {
  S.push({ name: `ladder ${level}`, stage: 'FoundryFloor', seed: 4242,
    who: [['Classic', 'Sword', level], ['Noir', 'Pike', level]], stocks: 3, frames: 1800 });
}
// `dummy` returns an empty frame and never enters decide() at all.
S.push({ name: 'dummy', stage: 'FoundryFloor', seed: 7, frames: 400,
  who: [['Classic', 'Sword', 'dummy'], ['Noir', 'Sword', 'hard']], stocks: 3 });
// The misspelled alias in LEVELS, which is a real key somebody could pass.
S.push({ name: 'misspelled level', stage: 'FoundryFloor', seed: 11, frames: 600,
  who: [['Classic', 'Sword', 'imposible'], ['Noir', 'Sword', 'imposible']], stocks: 3 });
// An unknown level falls back to `normal`.
S.push({ name: 'unknown level', stage: 'FoundryFloor', seed: 12, frames: 600,
  who: [['Classic', 'Sword', 'nonsense'], ['Noir', 'Sword', 'nonsense']], stocks: 3 });

// All four archetypes, because the tactic block branches on them and three of the four plans
// (`zone`, `lasso`, the Heavy-zoner attack) are unreachable without the right weapon.
S.push({ name: 'archetypes', stage: 'FoundryFloor', seed: 909, stocks: 3, frames: 2200,
  who: [['Classic', 'Sword', 'hard'], ['Noir', 'Blasters', 'hard'],
    ['Ember', 'Grimoire', 'hard'], ['Moss', 'Scythe', 'hard']] });

// Items on, which is the only way itemAction runs at all.
S.push({ name: 'bots with items', stage: 'FoundryFloor', seed: 5150, stocks: 3, items: true,
  frames: 2600, who: [['Classic', 'Sword', 'hard'], ['Noir', 'Hammer', 'hard']] });

// Items placed right under the bots, so they are picked up, carried and used - and one dropped
// across Smeltworks' pit, which is the shape that made `st.fetch` necessary: a bot walks at an item
// it cannot actually reach, and without the timeout it walks at it until the clock runs out.
S.push({ name: 'bots fetching items', stage: 'FoundryFloor', seed: 2468, stocks: 3, items: true,
  frames: 2400, who: [['Classic', 'Sword', 'hard'], ['Noir', 'Sword', 'hard']],
  drop: [{ at: 300, item: 'RivetGun', x: -14, y: 3 }, { at: 700, item: 'BlastKeg', x: 16, y: 3 },
    { at: 1100, item: 'Bulwark', x: -20, y: 3 }, { at: 1500, item: 'SpringPlate', x: 22, y: 3 },
    { at: 1900, item: 'Lodestone', x: -8, y: 3 }] });
S.push({ name: 'bots reaching across a pit', stage: 'Smeltworks', seed: 1357, stocks: 3,
  items: true, frames: 2400, who: [['Classic', 'Sword', 'hard'], ['Noir', 'Sword', 'hard']],
  drop: [{ at: 260, item: 'RivetGun', x: 2, y: 2 }, { at: 900, item: 'BlastKeg', x: -2, y: 2 },
    { at: 1500, item: 'Bulwark', x: 1, y: 2 }] });

// Ultimates: bots that charge and spend them, including the sniper stance which needs three
// separate presses and is fed from its own branch.
S.push({ name: 'bots with ultimates', stage: 'FoundryFloor', seed: 31337, stocks: 5, frames: 3000,
  who: [['Classic', 'Blasters', 'elite'], ['Noir', 'Sword', 'elite']] });

// A stage with hazards and moving ground, and one with real cover.
S.push({ name: 'bots on undertow', stage: 'Undertow', seed: 606, stocks: 3, frames: 2000,
  who: [['Classic', 'Sword', 'hard'], ['Noir', 'Longbow', 'hard']] });
S.push({ name: 'bots on smeltworks', stage: 'Smeltworks', seed: 707, stocks: 3, frames: 2000,
  who: [['Classic', 'Daggers', 'elite'], ['Noir', 'Gauntlets', 'elite']] });

// Teams, so the enemy filter has to exclude a team-mate.
S.push({ name: 'bot teams', stage: 'FoundryFloor', mode: 'StockTeams', seed: 808, stocks: 2,
  teamOf: [0, 0, 1, 1], frames: 2400,
  who: [['Classic', 'Sword', 'hard'], ['Noir', 'Pike', 'hard'],
    ['Ember', 'Axe', 'hard'], ['Moss', 'Flail', 'hard']] });

// A timed match that runs into sudden death with bots still playing.
S.push({ name: 'bot timed', stage: 'FoundryFloor', mode: 'TimedFFA', seed: 909, stocks: 3,
  timeLimit: 20, frames: 2600, who: [['Classic', 'Sword', 'hard'], ['Noir', 'Sword', 'hard']] });

const scenarios = S.map((spec) => ({ ...spec, rows: run(spec) }));
fs.writeFileSync(path.join(HERE, '../tests/trace-ai.json'), JSON.stringify({ fields: F, ai: AI, scenarios }));
const frames = scenarios.reduce((s, x) => s + x.rows.length, 0);
console.log(`ai traces: ${scenarios.length} scenarios, ${frames} frames`);
