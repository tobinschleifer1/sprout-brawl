// Record the JavaScript Combat resolving real hits between two real fighters.
//
//     node tools/gen-combat-traces.mjs
//
// Phase 3a covers everything that needs no projectile, summon or item, so these scenarios use melee
// swings, grabs, throws, shields, counters, ground pounds and ledge attacks - and never fire an
// ultimate, because those are Phase 3c and Combat.luau refuses them by name.
//
// The EVENT STREAM is the sharpest instrument here: every resolveHit emits a `hit` carrying damage,
// launch, angle and facing, so comparing the stream frame by frame catches a wrong branch in
// resolveHit far more directly than watching positions drift afterwards.
//
// Numbers are strings. See tools/gen-traces.mjs.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const { Fighter } = await import('../../web/src/engine/fighter.js');
const { StageRuntime } = await import('../../web/src/engine/stage.js');
const { Combat } = await import('../../web/src/engine/combat.js');
const { STAGES } = await import('../../web/src/data/stages/index.js');
const { buildLoadout } = await import('../../web/src/data/loadout.js');
const { emptyFrame } = await import('../../web/src/engine/input.js');

const n = (v) => (typeof v === 'number' ? String(v) : v);
const I = (o = {}) => Object.assign(emptyFrame(), o);

// Everything about a fighter that a hit changes, plus what drives the next one.
const F = ['x', 'y', 'vx', 'vy', 'facing', 'state', 'sf', 'onGround', 'percent', 'hitstun', 'hitlag',
  'shield', 'blockstun', 'tumbling', 'moveId', 'mf', 'moveLanded', 'ultCharge', 'armorUsed',
  'invincible', 'alive', 'stocks', 'bonusDamage', 'launchMul'];

// The numeric payload of every event kind Phase 3a can emit. Listing them rather than dumping the
// object keeps the comparison numeric instead of a string compare, which would skip the tolerance
// that Math.sin drift needs.
const EVENT_NUMS = ['damage', 'launch', 'angle', 'facing', 'attacker', 'victim', 'marks', 'stored', 'back'];

function snapEvents(evts) {
  return evts.map((e) => {
    const row = [e.type];
    for (const k of EVENT_NUMS) row.push(e[k] === undefined ? null : n(e[k]));
    row.push(e.perfect === undefined ? null : e.perfect);
    row.push(e.heavy === undefined ? null : e.heavy);
    return row;
  });
}

function run(spec) {
  const data = STAGES.find((s) => s.id === spec.stage);
  const stage = new StageRuntime({ ...data, hazards: [] }, 4242);
  const fighters = spec.who.map(([a, w], i) => {
    const f = new Fighter({ index: i, char: buildLoadout(a, w), x: spec.at[i], y: 0.5, stocks: 3, name: `P${i}` });
    f.setState('idle'); f.invincible = 0; f.onGround = true; f.platform = stage.main;
    f.facing = i === 0 ? 1 : -1;
    return f;
  });
  const match = { fighters, frame: 0, stage };
  const combat = new Combat(match);
  match.combat = combat;
  const ctx = { stage, combat, fighters };

  const rows = [];
  let frame = 0;
  for (const seg of spec.segments) {
    for (let i = 0; i < seg.frames; i++, frame++) {
      match.frame = frame;
      // A pinned scenario holds both fighters at a fixed gap so every swing connects. Left to
      // physics they push each other apart and whiff: the first 'brawl' ran 336 frames and landed
      // one block, which is not a test of hit resolution.
      if (spec.pin) {
        fighters.forEach((f, k) => {
          f.x = spec.at[k]; f.y = 0; f.vx = 0;
          if (f.state !== 'hitstun' && f.hitlag === 0) { f.onGround = true; f.platform = stage.main; f.vy = 0; }
          f.facing = k === 0 ? 1 : -1;
        });
      }
      combat.events.length = 0;
      for (const f of fighters) f.events.length = 0;
      // `set` writes a field straight onto a fighter. Some branches cannot be reached by input
      // alone - `bonusDamage` only lands on a burst if a mechanic banked it first - and scripting
      // four seconds of shield-holding to test one boolean is worse than setting it.
      if (seg.set) for (const [k, kv] of Object.entries(seg.set)) {
        for (const [field, value] of Object.entries(kv)) fighters[Number(k)][field] = value;
      }
      fighters[0].applyInput(I(seg.a));
      fighters[1].applyInput(I(seg.b || {}));
      stage.step(match);
      for (const f of fighters) f.step(ctx);
      combat.step();
      const row = [];
      for (const f of fighters) for (const k of F) row.push(n(f[k]));
      row.push(String(combat.bursts.length), String(combat.projectiles.length),
        String(combat.summons.length), String(combat.debugBoxes.length));
      row.push(snapEvents(combat.events));
      // the fighters' own event stream too - jump, land, tech, shieldbreak, counter
      row.push(fighters.map((f) => f.events.map((e) => e.type).join(',')).join('|'));
      rows.push(row);
    }
  }
  return rows;
}

const hold = (frames, a, b) => ({ frames, a, b: b || {} });
const S = [];
const SWORDS = [['Classic', 'Sword'], ['Noir', 'Sword']];

// a plain light connecting, at point-blank
S.push({ name: 'light connects', stage: 'FoundryFloor', who: SWORDS, at: [-1.2, 1.2],
  segments: [hold(6, {}), hold(1, { light: true, anyPress: true }), hold(60, {})] });

// a light string into a heavy cash-out, which is the whole combo system
S.push({ name: 'light string into signature', stage: 'FoundryFloor', who: SWORDS, at: [-1.2, 1.2],
  segments: [hold(4, {}), hold(1, { light: true, anyPress: true }), hold(9, {}),
    hold(1, { light: true, anyPress: true }), hold(9, {}),
    hold(1, { heavy: true, x: 1, anyPress: true }), hold(70, {})] });

// blocked, perfect-blocked, and shield broken by repeated heavies
S.push({ name: 'blocking', stage: 'FoundryFloor', who: SWORDS, at: [-1.2, 1.2],
  segments: [hold(4, {}, { guard: true, guardHeld: true, anyPress: true }),
    hold(1, { light: true, anyPress: true }, { guardHeld: true }), hold(30, {}, { guardHeld: true }),
    hold(1, { heavy: true, anyPress: true }, { guardHeld: true }), hold(60, {}, { guardHeld: true }),
    hold(1, { heavy: true, anyPress: true }, { guardHeld: true }), hold(60, {}, { guardHeld: true }),
    hold(1, { heavy: true, anyPress: true }, { guardHeld: true }), hold(90, {}, { guardHeld: true })] });

// a perfect block: guard pressed on the frame the hit lands
S.push({ name: 'perfect block', stage: 'FoundryFloor', who: SWORDS, at: [-1.2, 1.2],
  segments: [hold(4, {}), hold(1, { light: true, anyPress: true }), hold(4, {}),
    hold(1, {}, { guard: true, guardHeld: true, anyPress: true }), hold(40, {}, { guardHeld: true })] });

// grab, hold, and each of the four throws
for (const [name, stick] of [['forward', { x: 1 }], ['back', { x: -1 }], ['up', { y: 1 }], ['down', { y: -1 }]]) {
  S.push({ name: `throw ${name}`, stage: 'FoundryFloor', who: SWORDS, at: [-1.2, 1.2],
    segments: [hold(4, {}), hold(1, { grab: true, anyPress: true }), hold(12, {}),
      hold(30, stick), hold(60, {})] });
}

// ground pound onto someone standing underneath: DIVE_MOVE plus the landing shockwave burst
S.push({ name: 'ground pound onto a victim', stage: 'FoundryFloor', who: SWORDS, at: [0, 1.6],
  segments: [hold(1, { jump: true, jumpHeld: true, anyPress: true }), hold(22, { jumpHeld: true }),
    hold(1, { heavy: true, y: -1, anyPress: true }), hold(80, {})] });

// a counter weapon eating a hit - resolveHit's counter branch
S.push({ name: 'counter', stage: 'FoundryFloor', who: [['Classic', 'Sword'], ['Noir', 'Shield']], at: [-1.2, 1.2],
  segments: [hold(4, {}, { heavy: true, anyPress: true }), hold(6, {}),
    hold(1, { light: true, anyPress: true }), hold(80, {})] });

// two heavies trading on the same frame
S.push({ name: 'trade', stage: 'FoundryFloor', who: SWORDS, at: [-1.4, 1.4],
  segments: [hold(4, {}), hold(1, { heavy: true, anyPress: true }, { heavy: true, anyPress: true }),
    hold(80, {})] });

// weight matters: a heavy body and a light one taking the same hit
S.push({ name: 'heavy victim', stage: 'FoundryFloor', who: [['Classic', 'Sword'], ['Steel', 'Hammer']], at: [-1.2, 1.2],
  segments: [hold(4, {}), hold(1, { heavy: true, anyPress: true }), hold(80, {})] });
S.push({ name: 'light victim', stage: 'FoundryFloor', who: [['Classic', 'Sword'], ['Vapor', 'Daggers']], at: [-1.2, 1.2],
  segments: [hold(4, {}), hold(1, { heavy: true, anyPress: true }), hold(80, {})] });

// a rehitting multi-hit move, which is the only thing that exercises hb.rehitEvery
S.push({ name: 'multi-hit', stage: 'FoundryFloor', who: [['Classic', 'Daggers'], ['Noir', 'Sword']], at: [-1.2, 1.2],
  segments: [hold(4, {}), hold(1, { heavy: true, anyPress: true }), hold(90, {})] });

// a long free-for-all: both of them swinging at each other with no script beyond alternating
S.push({ name: 'brawl', stage: 'FoundryFloor', who: [['Classic', 'Pike'], ['Noir', 'Gauntlets']], at: [-3, 3],
  segments: Array.from({ length: 14 }, (_, i) => hold(24,
    i % 3 === 0 ? { light: true, x: 1, anyPress: true } : i % 3 === 1 ? { x: 1 } : { heavy: true, x: 1, anyPress: true },
    i % 4 === 0 ? { guard: true, guardHeld: true, anyPress: true } : i % 4 === 2 ? { light: true, x: -1, anyPress: true } : { x: -1 })) });

// A pinned slugfest: both held at a fixed gap, swinging continuously for ten seconds. This is
// where rehitEvery, hitVictims, hitlag-gating and repeated resolveHit actually get exercised -
// everything above lands one hit and stops.
S.push({ name: 'pinned slugfest', stage: 'FoundryFloor', pin: true,
  who: [['Classic', 'Sword'], ['Noir', 'Pike']], at: [-1.3, 1.3],
  segments: Array.from({ length: 30 }, (_, i) => hold(20,
    i % 2 === 0 ? { light: true, anyPress: true } : {},
    i % 3 === 0 ? { light: true, anyPress: true } : i % 3 === 1 ? { guard: true, guardHeld: true, anyPress: true } : {})) });

// A rehitting multi-hit, pinned so every tick of it connects.
S.push({ name: 'rehit pinned', stage: 'FoundryFloor', pin: true,
  who: [['Classic', 'Grimoire'], ['Noir', 'Sword']], at: [-1.0, 1.0],
  segments: [hold(4, {}), hold(1, { jump: true, jumpHeld: true, anyPress: true }),
    hold(6, { jumpHeld: true }), hold(1, { light: true, anyPress: true }), hold(120, {})] });

// Heavies packed close enough to actually break a shield, which the spaced version never did:
// the shield regenerates 8 a second, and sixty frames between swings gave it back most of the bite.
S.push({ name: 'shield break', stage: 'FoundryFloor', pin: true, who: SWORDS, at: [-1.3, 1.3],
  segments: Array.from({ length: 10 }, () => hold(26,
    { heavy: true, anyPress: true }, { guard: true, guardHeld: true, anyPress: true })) });

// Two counters facing each other, so the counter branch fires against a counter.
S.push({ name: 'counter into counter', stage: 'FoundryFloor', pin: true,
  who: [['Classic', 'Shield'], ['Noir', 'Shield']], at: [-1.3, 1.3],
  segments: [hold(4, {}, { heavy: true, anyPress: true }), hold(8, { heavy: true, anyPress: true }),
    hold(90, {})] });

// A hit landing just OUTSIDE the perfect-block window (sf 5-7 against a window of 4). Widening the
// window passed the whole trace without this, because the only block in it was already perfect.
S.push({ name: 'late block', stage: 'FoundryFloor', pin: true, who: SWORDS, at: [-1.3, 1.3],
  segments: [hold(3, {}), hold(1, { light: true, anyPress: true }),
    hold(1, {}, { guard: true, guardHeld: true, anyPress: true }), hold(40, {}, { guardHeld: true })] });

// shieldDamageMul: every move used above leaves it undefined, so dropping the multiplier entirely
// changed nothing. The war hammer's lights carry 1.6 to 2.0 and its signatures up to 3.4.
S.push({ name: 'shield vs the hammer', stage: 'FoundryFloor', pin: true,
  who: [['Steel', 'Hammer'], ['Noir', 'Sword']], at: [-1.4, 1.4],
  segments: Array.from({ length: 8 }, (_, i) => hold(30,
    i % 2 === 0 ? { light: true, anyPress: true } : { heavy: true, x: 1, anyPress: true },
    { guard: true, guardHeld: true, anyPress: true })) });

// bonusDamage must apply to a DIRECT hit and not to a burst. The ground pound gives both on the
// same fighter: the dive is direct, the landing shockwave is not.
S.push({ name: 'bonus damage direct vs burst', stage: 'FoundryFloor', who: SWORDS, at: [0, 1.6],
  segments: [{ frames: 1, a: { jump: true, jumpHeld: true, anyPress: true }, b: {}, set: { 0: { bonusDamage: 5 } } },
    hold(22, { jumpHeld: true }), hold(1, { heavy: true, y: -1, anyPress: true }),
    { frames: 80, a: {}, b: {}, set: { 0: { bonusDamage: 5 } } }] });

// Hits landing OUTSIDE the counter's active window - Counterguard is startup 6, active 14,
// recovery 34, so a hit at move-frame 30 is deep in recovery and must NOT be countered. Without
// this, letting the counter fire on every frame of the move passed the whole trace.
S.push({ name: 'hit outside the counter window', stage: 'FoundryFloor', pin: true,
  who: [['Classic', 'Sword'], ['Noir', 'Shield']], at: [-1.3, 1.3],
  // The counter is thrown and deliberately NOT hit while it is live, so the only connection lands
  // in its recovery. Hitting it early countered, which replaced the move and left nothing for the
  // late hit to test.
  segments: [hold(1, {}, { heavy: true, anyPress: true }), hold(23, {}),
    hold(1, { light: true, anyPress: true }), hold(70, {})] });

const scenarios = S.map((spec) => ({ ...spec, rows: run(spec) }));
fs.writeFileSync(path.join(HERE, '../tests/trace-combat.json'), JSON.stringify({ fields: F, eventNums: EVENT_NUMS, scenarios }));
const frames = scenarios.reduce((s, x) => s + x.rows.length, 0);
const hits = scenarios.reduce((s, x) => s + x.rows.reduce((t, r) => t + r[r.length - 2].length, 0), 0);
console.log(`combat traces: ${scenarios.length} scenarios, ${frames} frames, ${hits} combat events`);
