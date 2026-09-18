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
const { ITEM_BY_ID } = await import('../../web/src/data/items.js');

const n = (v) => (typeof v === 'number' ? String(v) : v);
const I = (o = {}) => Object.assign(emptyFrame(), o);

// Everything about a fighter that a hit changes, plus what drives the next one.
// jumpsLeft is in here because a spring plate hands a jump back to a fighter who has none, and
// without it that was unobservable: the plate fired, the victim's jump count changed, and the trace
// recorded neither. The four after it are the same kind of insurance.
const F = ['x', 'y', 'vx', 'vy', 'facing', 'state', 'sf', 'onGround', 'percent', 'hitstun', 'hitlag',
  'shield', 'blockstun', 'tumbling', 'moveId', 'mf', 'moveLanded', 'ultCharge', 'armorUsed',
  'invincible', 'alive', 'stocks', 'bonusDamage', 'launchMul',
  'jumpsLeft', 'carryX', 'ultActive', 'ultShots', 'recoveryUsed'];

// The numeric payload of every event kind Phase 3a can emit. Listing them rather than dumping the
// object keeps the comparison numeric instead of a string compare, which would skip the tolerance
// that Math.sin drift needs.
// x and y are in here deliberately. Without them the trace compared only event COUNTS, and a
// projectile spawned at the wrong height - the volley's whole spread pattern - passed unnoticed.
const EVENT_NUMS = ['damage', 'launch', 'angle', 'facing', 'attacker', 'victim', 'marks', 'stored',
  'back', 'x', 'y', 'radius'];

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
      // Items never appear on their own inside a trace: maybeSpawnItem is on a fourteen-second
      // timer and Match, which drives it, is Phase 4. `act` puts them where the scenario needs them.
      if (seg.act) for (const act of seg.act) {
        if (act.kind === 'give') combat.giveItem(fighters[act.f], ITEM_BY_ID[act.item]);
        else if (act.kind === 'spawn') combat.spawnItem(ITEM_BY_ID[act.item], act.x, act.y);
        else if (act.kind === 'maybeSpawn') { combat.itemTimer = act.timer; combat.maybeSpawnItem(act.n ?? fighters.length); }
      }
      fighters[0].applyInput(I(seg.a));
      for (let k = 1; k < fighters.length; k++) fighters[k].applyInput(I(seg.b || {}));
      stage.step(match);
      for (const f of fighters) f.step(ctx);
      combat.step();
      const row = [];
      for (const f of fighters) for (const k of F) row.push(n(f[k]));
      row.push(String(fighters.length));
      row.push(String(combat.bursts.length), String(combat.projectiles.length),
        String(combat.summons.length), String(combat.debugBoxes.length));
      // Every live projectile and summon, not just how many. Counts alone let a mine cap evict the
      // wrong one, a shot pass through cover it should stop at, and a volley spawn its spread at
      // the wrong offset - all three passed a trace that only counted them.
      row.push(combat.projectiles.map((p) => [n(p.x), n(p.y), n(p.vx), n(p.vy), n(p.life), p.shape]));
      row.push(combat.summons.map((q) => [q.type, n(q.x), n(q.y), n(q.life), n(q.armed ?? -1), n(q.hp ?? -1)]));
      row.push(combat.bursts.map((b) => [b.move.id, n(b.x), n(b.y), n(b.frames), n(b.move.damage)]));
      row.push(combat.items.map((it) => [it.def.id, n(it.x), n(it.y), n(it.vx), n(it.vy), n(it.uses),
        n(it.life), n(it.cd), n(it.hp), it.onGround, it.held ? String(it.held.index) : null]));
      row.push(combat.plates.map((pl) => [n(pl.x), n(pl.y), n(pl.life), n(pl.cd), n(pl.vy)]));
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

// ---------------------------------------------------------------- phase 3b ----
// Projectiles. Only `mine` summons are used by the roster, so wall, cloud and node - and with them
// the `pulse` kind, the `teleport` recovery and nearestNode - are refused by the port rather than
// carried, and nothing here can reach them.

// bolts flying, connecting, and being blocked
S.push({ name: 'blaster bolts', stage: 'FoundryFloor', pin: true,
  who: [['Classic', 'Blasters'], ['Noir', 'Sword']], at: [-9, 9],
  segments: Array.from({ length: 10 }, (_, i) => hold(24,
    { light: true, anyPress: true }, i % 3 === 2 ? { guard: true, guardHeld: true, anyPress: true } : {})) });

// the longbow's arrows, at a range where travel time matters
S.push({ name: 'longbow arrows', stage: 'FoundryFloor', pin: true,
  who: [['Classic', 'Longbow'], ['Noir', 'Sword']], at: [-18, 18],
  segments: Array.from({ length: 8 }, (_, i) => hold(30,
    i % 2 === 0 ? { light: true, anyPress: true } : { light: true, x: 1, anyPress: true }, {})) });

// a shot into a SOLID: Smeltworks has real cover, which is the branch that makes a tower scenery
// or a wall
S.push({ name: 'shot into cover', stage: 'Smeltworks', pin: true,
  who: [['Classic', 'Blasters'], ['Noir', 'Sword']], at: [-24, 24],
  segments: Array.from({ length: 8 }, () => hold(24, { light: true, anyPress: true }, {})) });

// Barbed Volley: the only `volley` move, and the only thing that spends Spines ammo
S.push({ name: 'volley', stage: 'FoundryFloor', pin: true,
  who: [['Classic', 'Blasters'], ['Noir', 'Sword']], at: [-12, 12],
  segments: [hold(10, {}), hold(1, { heavy: true, x: 1, anyPress: true }), hold(120, {}),
    hold(1, { heavy: true, x: 1, anyPress: true }), hold(120, {})] });

// a mine placed, armed, and walked into
S.push({ name: 'mine triggered', stage: 'FoundryFloor',
  who: [['Classic', 'Grimoire'], ['Noir', 'Sword']], at: [-6, 6],
  segments: [hold(4, {}), hold(1, { heavy: true, y: -1, anyPress: true }), hold(40, {}),
    hold(90, {}, { x: -1 }), hold(40, {})] });

// a mine shot off the stage - `destructible`, which is the only reason summons appear in step()
S.push({ name: 'mine destroyed', stage: 'FoundryFloor', pin: true,
  who: [['Classic', 'Grimoire'], ['Noir', 'Hammer']], at: [-1.6, 1.6],
  segments: [hold(4, {}), hold(1, { heavy: true, y: -1, anyPress: true }), hold(30, {}),
    hold(1, {}, { heavy: true, anyPress: true }), hold(60, {})] });

// mine cap: the roster's mine has a `max`, and placing past it removes the oldest
S.push({ name: 'mine cap', stage: 'FoundryFloor',
  who: [['Classic', 'Grimoire'], ['Noir', 'Sword']], at: [-10, 14],
  segments: Array.from({ length: 6 }, () => hold(50, { heavy: true, y: -1, anyPress: true }, {})) });

// A shot UNDER the mesa. `p.y > sp.bottom` is what lets a bolt pass beneath an elevated solid;
// every other cover scenario fires at chest height where the bound cannot matter, so dropping it
// passed the whole trace.
S.push({ name: 'shot under the mesa', stage: 'Saltflat', pin: true,
  who: [['Classic', 'Blasters'], ['Noir', 'Sword']], at: [20, 44],
  segments: Array.from({ length: 8 }, () => hold(24, { light: true, anyPress: true }, {})) });

// rangeMul scales a projectile's lifetime, and the rounding only shows when it is not 1. Bloom
// sets it, and banking Bloom through inputs takes a sustained combo, so it is set directly.
// 1.25, not 1.5: every Longbow lifetime is even, so x1.5 is a whole number and floor and round
// agree. 26 x 1.25 is 32.5, which is the only place the rounding is visible.
S.push({ name: 'bloomed projectile', stage: 'FoundryFloor', pin: true,
  who: [['Classic', 'Longbow'], ['Noir', 'Sword']], at: [-20, 20],
  segments: [{ frames: 2, a: {}, b: {}, set: { 0: { rangeMul: 1.25 } } },
    { frames: 1, a: { light: true, anyPress: true }, b: {}, set: { 0: { rangeMul: 1.25 } } },
    { frames: 90, a: {}, b: {}, set: { 0: { rangeMul: 1.25 } } }] });

// A mine hit by something too weak to break it: `destructible` only yields to 4 damage or more.
//
// The swing has to land while the mine is still ARMING. Its trigger is 3 studs and no light in the
// game reaches that far, so any fighter close enough to hit a live mine has already set it off -
// which is why the first version of this tested nothing at all. The twenty arming frames are the
// only window in which a mine can be struck.
// A mine SHOT by something too weak to break it: `destructible` only yields to 4 damage or more.
//
// It has to be a projectile. A mine's trigger is 3 studs and no light in the game reaches that far,
// so any fighter close enough to swing at a live mine has already set it off - two earlier versions
// of this scenario tested nothing, one because the placer was knocked out of its own signature at
// point-blank and never made a mine at all. A blaster bolt is 2 damage and arrives from twenty
// studs away, which is outside the trigger and under the threshold.
// A mine SHOT OUT by a projectile.
//
// Getting here at all took three tries. A mine's trigger is 3 studs and no light in the game
// reaches that far, so any fighter close enough to swing at a live mine has already set it off; and
// every bolt and arrow in the roster spawns at chest height (y 2.55 to 3.75) while a mine's box is
// y 0.0 to 1.6, so they all fly straight over it. Grimoire's Runebrand is the one projectile tall
// enough to touch a mine - 3.6 studs of it, y 0.60 to 4.20.
//
// Which also means the `>= 4` damage threshold on this branch is unreachable: the only projectile
// that can reach a mine deals 15. The branch is covered; the threshold is not.
S.push({ name: 'mine shot out', stage: 'FoundryFloor', pin: true,
  who: [['Classic', 'Grimoire'], ['Noir', 'Grimoire']], at: [-1.6, 22],
  segments: [hold(4, {}), hold(1, { heavy: true, y: -1, anyPress: true }), hold(40, {}),
    ...Array.from({ length: 6 }, () => hold(40, {}, { heavy: true, x: -1, anyPress: true }))] });

// The mirror: fighter ONE shoots, so the shot travels left. Every other projectile scenario has
// fighter zero firing, who always faces right, so dropping `f.facing` from the spawn velocity
// passed the whole trace.
S.push({ name: 'shooting leftwards', stage: 'FoundryFloor', pin: true,
  who: [['Classic', 'Sword'], ['Noir', 'Blasters']], at: [-14, 14],
  segments: Array.from({ length: 8 }, () => hold(24, {}, { light: true, anyPress: true })) });

// A mine dropped off the lip of a platform. Standing on the main floor the fighter's own y IS the
// surface, so `surfaceUnder` and `f.y` agree and skipping the lookup changes nothing; from the left
// shelf the mine lands fourteen studs below the hand that placed it.
S.push({ name: 'mine off a platform edge', stage: 'FoundryFloor',
  who: [['Classic', 'Grimoire'], ['Noir', 'Sword']], at: [-14.5, 20],
  segments: [{ frames: 2, a: {}, b: {}, set: { 0: { y: 14 } } },
    hold(1, { heavy: true, y: -1, anyPress: true }), hold(60, {})] });

// ---------------------------------------------------------------- phase 3c ----
// The twelve ultimates. NOT pinned: Rundown teleports the attacker to its target and Soul Harvest
// drags victims to the caster, so holding anybody in place would be testing the harness instead of
// the move. They are placed at the range each one is meant to be used at and left to run.
//
// The meter is set directly rather than earned - twenty landed hits is a minute of scripted combo
// per scenario - and `ult` is re-pressed periodically because Deadeye reads the buffer for each of
// its three rounds.
const ULT_RANGE = { Sword: 3.0, Scythe: 4.0, Blasters: 12, Grimoire: 9, Axe: 4.0, Pike: 10,
  Gauntlets: 3.0, Hammer: 4.0, Longbow: 9, Flail: 5.0, Shield: 3.0, Daggers: 3.0 };
for (const [w, gap] of Object.entries(ULT_RANGE)) {
  // Aegis does nothing at all unless the opponent swings at it, and Exsanguinate needs the victim
  // to still be standing there to collect the marks it puts on.
  const foeSwings = w === 'Shield';
  const charged = { 0: { ultCharge: 20 } };
  S.push({ name: `ultimate ${w}`, stage: 'FoundryFloor',
    who: [['Classic', w], ['Noir', 'Sword']], at: [-gap / 2, gap / 2],
    segments: [
      { frames: 4, a: {}, b: {}, set: charged },
      { frames: 1, a: { ult: true, anyPress: true }, b: {}, set: charged },
      ...Array.from({ length: 16 }, (_, i) => ({
        frames: 20,
        // re-press ult for the sniper's magazine; everything else ignores it mid-move
        a: i % 1 === 0 ? { ult: true, anyPress: true } : {},
        b: foeSwings ? { light: true, anyPress: true } : {},
      })),
    ] });
}

// Soul Harvest with somebody mashing out of it, and with a third and fourth body in range so the
// two-target pick has something to choose between.
S.push({ name: 'vortex with four bodies', stage: 'FoundryFloor',
  who: [['Classic', 'Scythe'], ['Noir', 'Sword'], ['Ember', 'Pike'], ['Moss', 'Hammer']],
  at: [-4, 2, 6, 11],
  segments: [{ frames: 4, a: {}, b: {}, set: { 0: { ultCharge: 20 } } },
    { frames: 1, a: { ult: true, anyPress: true }, b: {}, set: { 0: { ultCharge: 20 } } },
    ...Array.from({ length: 12 }, (_, i) => ({ frames: 16, a: {},
      b: i % 2 === 0 ? { jump: true, anyPress: true } : { dodge: true, anyPress: true } }))] });

// A vortex victim grabbed from far enough out to still be OUTSIDE the release radius after the
// first frame's drag. Soul Harvest reaches 17 studs but releases at burst.radius * 1.6 = 6.4, and
// the `ultEscape > 0` gate is what stops everyone beyond 6.4 being let go on frame one - before
// they have done anything to earn it. Every other vortex scenario grabs from inside 6.4, or close
// enough that one frame of pull brings them in, so dropping the gate changed nothing.
S.push({ name: 'vortex grab from long range', stage: 'FoundryFloor',
  who: [['Classic', 'Scythe'], ['Noir', 'Sword'], ['Ember', 'Sword']], at: [-6, -2, 9],
  segments: [{ frames: 4, a: {}, b: {}, set: { 0: { ultCharge: 20 } } },
    { frames: 1, a: { ult: true, anyPress: true }, b: {}, set: { 0: { ultCharge: 20 } } },
    ...Array.from({ length: 12 }, () => hold(16, {}, {}))] });

// Astral Rain into a held shield. The first wave is blockable and the second is not, and with the
// target simply standing there neither orb ever met a shield, so making both blockable passed.
S.push({ name: 'starfall into a shield', stage: 'FoundryFloor',
  who: [['Classic', 'Grimoire'], ['Noir', 'Sword']], at: [-4.5, 4.5],
  segments: [{ frames: 4, a: {}, b: { guard: true, guardHeld: true, anyPress: true }, set: { 0: { ultCharge: 20 } } },
    { frames: 1, a: { ult: true, anyPress: true }, b: { guardHeld: true }, set: { 0: { ultCharge: 20 } } },
    ...Array.from({ length: 14 }, () => hold(20, {}, { guard: true, guardHeld: true, anyPress: true }))] });

// Upheaval and Rundown both cycle through every enemy, which a two-player scenario cannot show.
for (const w of ['Hammer', 'Gauntlets']) {
  S.push({ name: `ultimate ${w} in a crowd`, stage: 'FoundryFloor',
    who: [['Classic', w], ['Noir', 'Sword'], ['Ember', 'Sword'], ['Moss', 'Sword']],
    at: [-8, -2, 5, 12],
    segments: [{ frames: 4, a: {}, b: {}, set: { 0: { ultCharge: 20 } } },
      { frames: 1, a: { ult: true, anyPress: true }, b: {}, set: { 0: { ultCharge: 20 } } },
      ...Array.from({ length: 14 }, () => hold(20, { ult: true, anyPress: true }, {}))] });
}

// Exsanguinate against a shield: marks land on a blocking victim, and the collection is what
// exercises hb.shieldDamageMul, which no non-ultimate hitbox in the game carries.
S.push({ name: 'bleed into a shield', stage: 'FoundryFloor',
  who: [['Classic', 'Daggers'], ['Noir', 'Sword']], at: [-1.5, 1.5],
  segments: [{ frames: 4, a: {}, b: {}, set: { 0: { ultCharge: 20 } } },
    { frames: 1, a: { ult: true, anyPress: true }, b: { guard: true, guardHeld: true, anyPress: true },
      set: { 0: { ultCharge: 20 } } },
    ...Array.from({ length: 14 }, () => hold(20, {}, { guardHeld: true }))] });

// ---------------------------------------------------------------- phase 3d ----
const give = (f, item) => ({ kind: 'give', f, item });

// Each item's own verb, light and heavy, at a range where the result lands on somebody.
S.push({ name: 'item: blast keg thrown', stage: 'FoundryFloor',
  who: [['Classic', 'Sword'], ['Noir', 'Sword']], at: [-8, 8],
  segments: [{ frames: 4, a: {}, b: {}, act: [give(0, 'BlastKeg')] },
    hold(1, { light: true, anyPress: true }), hold(200, {})] });

// The keg is VOLATILE: any melee hitbox sets it off, the thrower's included.
S.push({ name: 'item: keg shot out of the air', stage: 'FoundryFloor',
  who: [['Classic', 'Sword'], ['Noir', 'Sword']], at: [-10, 10],
  segments: [{ frames: 4, a: {}, b: {}, act: [give(0, 'BlastKeg')] },
    hold(1, { light: true, anyPress: true }),
    ...Array.from({ length: 10 }, () => hold(10, {}, { light: true, anyPress: true }))] });

// Catching one out of the air: a guard press on an incoming keg takes it and puts it in your hands.
S.push({ name: 'item: keg caught', stage: 'FoundryFloor',
  who: [['Classic', 'Sword'], ['Noir', 'Sword']], at: [-9, 9],
  segments: [{ frames: 4, a: {}, b: {}, act: [give(0, 'BlastKeg')] },
    hold(1, { light: true, anyPress: true }),
    ...Array.from({ length: 14 }, () => hold(8, {}, { guard: true, anyPress: true }))] });

S.push({ name: 'item: rivet gun until empty', stage: 'FoundryFloor', pin: true,
  who: [['Classic', 'Sword'], ['Noir', 'Sword']], at: [-11, 11],
  segments: [{ frames: 4, a: {}, b: {}, act: [give(0, 'RivetGun')] },
    ...Array.from({ length: 22 }, () => hold(12, { light: true, anyPress: true }, {}))] });

// The Bulwark: bashing with it, hiding behind it, and it breaking under damage from the front.
S.push({ name: 'item: bulwark bash and break', stage: 'FoundryFloor', pin: true,
  who: [['Classic', 'Sword'], ['Noir', 'Hammer']], at: [-1.6, 1.6],
  segments: [{ frames: 4, a: {}, b: {}, act: [give(0, 'Bulwark')] },
    ...Array.from({ length: 16 }, (_, i) => hold(22,
      i % 2 === 0 ? { light: true, anyPress: true } : {},
      { heavy: true, anyPress: true }))] });

// Heavy on a held Bulwark bashes rather than throws, while it still has hit points and you are
// grounded - and throws once either stops being true.
S.push({ name: 'item: bulwark heavy in the air', stage: 'FoundryFloor',
  who: [['Classic', 'Sword'], ['Noir', 'Sword']], at: [-6, 6],
  segments: [{ frames: 4, a: {}, b: {}, act: [give(0, 'Bulwark')] },
    hold(1, { heavy: true, anyPress: true }), hold(40, {}),
    hold(1, { jump: true, jumpHeld: true, anyPress: true }), hold(10, { jumpHeld: true }),
    hold(1, { heavy: true, anyPress: true }), hold(90, {})] });

// A spring plate placed, then jumped onto.
S.push({ name: 'item: spring plate', stage: 'FoundryFloor',
  who: [['Classic', 'Sword'], ['Noir', 'Sword']], at: [-3, 3],
  segments: [{ frames: 4, a: {}, b: {}, act: [give(0, 'SpringPlate')] },
    hold(1, { light: true, anyPress: true }), hold(30, {}),
    hold(1, {}, { jump: true, jumpHeld: true, anyPress: true }), hold(40, {}, { x: -1 }),
    hold(120, {}, { x: -1 })] });

// Two things the simple version cannot show, both about who the plate is allowed to launch:
//   * `v.vy <= 12` stops it re-launching somebody already rising, which only matters if a fighter
//     jumps from ON the plate;
//   * `jumpsLeft = max(jumpsLeft, 1)` only does anything to a fighter who has NO jumps left.
//
// The third thing - a plate placed in the AIR - is not here because it cannot happen: Fighter only
// calls useItem from _stepGround, so an airborne fighter cannot use an item at all. That makes the
// `if not f.onGround then return end` guard in the `place` branch unreachable, along with the
// `f.onGround` term in the Bulwark's throw exception.
S.push({ name: 'item: spring plate edge cases', stage: 'FoundryFloor',
  who: [['Classic', 'Sword'], ['Noir', 'Sword']], at: [-2, 6],
  segments: [{ frames: 2, a: {}, b: {}, act: [give(0, 'SpringPlate')] },
    hold(1, { light: true, anyPress: true }), hold(24, {}),
    // the victim burns both jumps getting there, arriving with none left
    hold(1, {}, { jump: true, jumpHeld: true, anyPress: true }), hold(10, {}, { jumpHeld: true, x: -1 }),
    hold(1, {}, { jump: true, anyPress: true, x: -1 }), hold(40, {}, { x: -1 }),
    // then it stands on the plate and jumps, which is a rise the plate must not re-launch
    ...Array.from({ length: 12 }, () => hold(16, {}, { jump: true, jumpHeld: true, anyPress: true }))] });

// The plate's two guards, set up directly.
//
// Neither is reachable by input with any reliability. A fighter jumping off a plate is sprung
// during jumpsquat, while vy is still 0, so it never crosses the plate RISING with the cooldown
// expired; and a fighter with no jumps left has to arrive airborne, which means landing on the
// plate from a double jump before touching the ground, which restores the jumps on the way. So the
// victim is placed on the plate with the velocity and jump count each branch needs.
S.push({ name: 'item: plate guards', stage: 'FoundryFloor',
  who: [['Classic', 'Sword'], ['Noir', 'Sword']], at: [-2, 6],
  segments: [{ frames: 2, a: {}, b: {}, act: [give(0, 'SpringPlate')] },
    hold(1, { light: true, anyPress: true }), hold(30, {}),
    // rising over the plate: vy above 12, so it must NOT fire
    ...Array.from({ length: 10 }, () => ({ frames: 4, a: {}, b: {},
      set: { 1: { x: -2, y: 0.4, vy: 30, onGround: false, platform: null } } })),
    hold(30, {}),
    // falling onto it with no jumps left: it must fire, and hand a jump back
    ...Array.from({ length: 10 }, () => ({ frames: 4, a: {}, b: {},
      set: { 1: { x: -2, y: 0.4, vy: -5, jumpsLeft: 0, onGround: false, platform: null } } })),
    hold(60, {})] });

// The Lodestone sticks to whoever it hits and drags them down for five seconds.
S.push({ name: 'item: lodestone', stage: 'FoundryFloor',
  who: [['Classic', 'Sword'], ['Noir', 'Sword']], at: [-8, 8],
  segments: [{ frames: 4, a: {}, b: {}, act: [give(0, 'Lodestone')] },
    hold(1, { light: true, anyPress: true }), hold(60, {}),
    hold(1, {}, { jump: true, jumpHeld: true, anyPress: true }), hold(200, {})] });

// A loose item on the ground: picked up, dropped, and KNOCKED out of someone's hands.
//
// The knocked drop is the only thing that gives an item horizontal velocity, so without a hit big
// enough to cause one (knockOutDamage is 12) the item's vx stayed 0 all trace and both the drop
// velocities and the 0.95 air damping were untestable. The hammer is pinned at swinging range.
S.push({ name: 'item: pickup and drop', stage: 'FoundryFloor', pin: true,
  who: [['Classic', 'Sword'], ['Noir', 'Hammer']], at: [-1.5, 1.5],
  segments: [{ frames: 2, a: {}, b: {}, act: [{ kind: 'spawn', item: 'RivetGun', x: -1.5, y: 6 }] },
    hold(40, {}), hold(1, { pickup: true, anyPress: true }), hold(20, {}),
    hold(1, { pickup: true, y: -1, anyPress: true }), hold(30, {}),
    hold(1, { pickup: true, anyPress: true }), hold(20, {}),
    ...Array.from({ length: 8 }, () => hold(26, {}, { heavy: true, anyPress: true }))] });

// An item just out of reach. itemNear is 3 studs wide and 3.5 tall, and every other scenario drops
// the item on the fighter's own feet, so widening the radius to six changed nothing.
S.push({ name: 'item: just out of reach', stage: 'FoundryFloor', pin: true,
  who: [['Classic', 'Sword'], ['Noir', 'Sword']], at: [-1.5, 12],
  segments: [{ frames: 2, a: {}, b: {}, act: [{ kind: 'spawn', item: 'RivetGun', x: 2.9, y: 4 },
      { kind: 'spawn', item: 'Bulwark', x: -1.5, y: 9.2 }] },
    ...Array.from({ length: 20 }, () => hold(10, { pickup: true, anyPress: true }, {}))] });

// A loose item left alone until it despawns, and one dropped off the bottom of the world.
S.push({ name: 'item: despawn and fall', stage: 'FoundryFloor',
  who: [['Classic', 'Sword'], ['Noir', 'Sword']], at: [-20, 20],
  segments: [{ frames: 2, a: {}, b: {}, act: [{ kind: 'spawn', item: 'Bulwark', x: 0, y: 8 },
      { kind: 'spawn', item: 'BlastKeg', x: 60, y: 4 }] },
    hold(400, {})] });

// The spawner itself, driven straight off the seeded generator.
//
// `n: 5` raises the cap to two loose items, and one fighter is holding a third: the cap counts only
// LOOSE items, so a version where held items counted too would stop spawning a beat early. With
// n = 2 the cap is one item and the spawner fired exactly once in ten calls, which tested neither.
S.push({ name: 'item: seeded spawning', stage: 'FoundryFloor',
  who: [['Classic', 'Sword'], ['Noir', 'Sword']], at: [-20, 20],
  segments: [{ frames: 2, a: {}, b: {}, act: [give(0, 'Bulwark')] },
    ...Array.from({ length: 14 }, () => ({ frames: 30, a: {}, b: {},
      act: [{ kind: 'maybeSpawn', timer: 999, n: 5 }] }))] });

const scenarios = S.map((spec) => ({ ...spec, rows: run(spec) }));
fs.writeFileSync(path.join(HERE, '../tests/trace-combat.json'), JSON.stringify({ fields: F, eventNums: EVENT_NUMS, scenarios }));
const frames = scenarios.reduce((s, x) => s + x.rows.length, 0);
const hits = scenarios.reduce((s, x) => s + x.rows.reduce((t, r) => t + r[r.length - 2].length, 0), 0);
console.log(`combat traces: ${scenarios.length} scenarios, ${frames} frames, ${hits} combat events`);
