// Record the JavaScript Fighter state machine, frame by frame, for the Luau port to reproduce.
//
//     node tools/gen-fighter-traces.mjs
//
// The scenarios are DATA, not code: a list of input segments and scheduled events. Both sides read
// the same script out of the trace file, so there is no chance of the two harnesses diverging and
// quietly testing different things.
//
// ctx.combat is a STUB on both sides, and it logs every call. Combat is Phase 3; what this checks
// is the state machine in isolation - including that it calls out at the right frame, which is why
// the log is compared rather than discarded.
//
// Every number is a string. See tools/gen-traces.mjs for why.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const { Fighter } = await import('../../web/src/engine/fighter.js');
const { StageRuntime } = await import('../../web/src/engine/stage.js');
const { STAGES } = await import('../../web/src/data/stages/index.js');
const { buildLoadout } = await import('../../web/src/data/loadout.js');
const { emptyFrame } = await import('../../web/src/engine/input.js');

const n = (v) => (typeof v === 'number' ? String(v) : v);

// ---------------------------------------------------------------- the stub ----
function stubCombat(fighters) {
  const log = [];
  const rec = (name, extra) => log.push(extra === undefined ? name : `${name}:${extra}`);
  return {
    fighters, log,
    useItem: (f, kind) => rec('useItem', kind),
    dropItem: (f, thrown) => rec('dropItem', String(thrown)),
    itemNear: () => { rec('itemNear'); return null; },
    pickupItem: () => rec('pickupItem'),
    hasFruit: () => { rec('hasFruit'); return false; },
    fruiting: () => rec('fruiting'),
    nearestNode: () => { rec('nearestNode'); return null; },
    removeSummon: () => rec('removeSummon'),
    onMoveActive: (f, m) => rec('onMoveActive', m.id),
    onMoveActiveFrame: (f, m) => rec('onMoveActiveFrame', `${m.id}@${f.mf}`),
    spawnBurst: (f, b) => rec('spawnBurst', b.id || 'shock'),
    checkGrab: () => rec('checkGrab'),
    resolveThrow: (a, v, td) => rec('resolveThrow', String(td.angle)),
  };
}

// ---------------------------------------------------------------- recording ----
// Every field of the fighter that the simulation reads back. Anything left out is a field a port
// could get wrong invisibly, so this is deliberately exhaustive rather than "the interesting ones".
const FIELDS = ['x', 'y', 'prevX', 'prevY', 'vx', 'vy', 'facing', 'state', 'sf', 'onGround',
  'jumpsLeft', 'airDodgeUsed', 'recoveryUsed', 'ledgeGrabs', 'fastFalling', 'dropTimer',
  'ledgeCooldown', 'shield', 'blockstun', 'hitstun', 'hitlag', 'tumbling', 'invincible',
  'moveId', 'mf', 'startupEff', 'startupShift', 'moveLanded', 'charge', 'percent', 'carryX',
  'snaredBy', 'reeling', 'techPress', 'techRoll', 'ultCharge', 'ultActive', 'frozenFrames',
  'lag', 'alive', 'stocks', 'spawnedActive', 'armorUsed', 'bonusDamage', 'launchMul', 'rangeMul',
  'noGravityFrame', 'frameCount'];
const BUFFERS = ['jump', 'light', 'heavy', 'dodge', 'guard', 'grab', 'taunt', 'ult', 'pickup'];

function snap(f) {
  const row = FIELDS.map((k) => n(f[k]));
  row.push(f.platform ? f.platform.id : null);
  row.push(BUFFERS.map((b) => n(f.buffer[b])).join(','));
  // mechanic state varies by weapon, so it is flattened to sorted key=value pairs
  row.push(Object.keys(f.mech).sort().filter((k) => typeof f.mech[k] !== 'object')
    .map((k) => `${k}=${n(f.mech[k])}`).join(','));
  row.push(`${n(f.effects.chill.stacks)},${n(f.effects.chill.timer)},${n(f.effects.tangle.stacks)},`
    + `${n(f.effects.tangle.timer)},${n(f.effects.grit.hide)},${n(f.effects.grit.slow)},`
    + `${n(f.effects.slow)},${String(f.effects.frozenBonus)},${n(f.effects.lodestone)},${n(f.effects.bleed)}`);
  row.push(f.ledge ? `${n(f.ledge.x)}:${n(f.ledge.side)}` : null);
  row.push(f.la ? f.la.kind : null);
  row.push(f.tether ? `${n(f.tether.tx)}:${n(f.tether.ty)}` : null);
  row.push(f.events.map((e) => e.type).join(','));
  // The computed properties. Combat reads all of these in Phase 3, and none of them is implied by
  // the raw fields: isDodgeInvincible was completely untested until it was added here, and
  // replacing every SPOT_DODGE.inv[1] with a nil index still passed the whole trace.
  row.push(n(f.cy));
  row.push(f.untouchable);
  row.push(f.isDodgeInvincible());
  row.push(f.moveActive);
  row.push(f.grabActive);
  row.push(f.busy);
  row.push(f.ultReady);
  row.push(n(f.ultMeter));
  row.push(n(f.moveFrameAbs));
  row.push(f.isInvincible);
  row.push(f.inHitstun);
  // As four NUMBERS, not one joined string. Joined, it was compared as text, which skipped the
  // relative tolerance entirely and failed on the last bit of a position that had been through
  // Math.sin - the one difference no port can remove.
  const hb = f.hurtbox;
  row.push(n(hb.x1), n(hb.x2), n(hb.y1), n(hb.y2));
  return row;
}

const I = (o = {}) => Object.assign(emptyFrame(), o);

function run(spec) {
  const data = STAGES.find((s) => s.id === spec.stage);
  const stage = new StageRuntime({ ...data, hazards: [] });
  const char = buildLoadout(spec.avatar, spec.weapon);
  const f = new Fighter({ index: 0, char, x: spec.x, y: spec.y, stocks: 3, name: 'P' });
  // Start from a settled state rather than mid-respawn, unless the scenario is about respawning.
  if (!spec.keepRespawn) { f.setState('air'); f.invincible = 0; }
  const combat = stubCombat([f]);
  const ctx = { stage, combat, fighters: [f] };
  const events = new Map();
  for (const e of spec.events || []) events.set(e.frame, e);

  const rows = [];
  let frame = 0;
  for (const seg of spec.segments) {
    for (let i = 0; i < seg.frames; i++, frame++) {
      const ev = events.get(frame);
      if (ev) {
        if (ev.kind === 'hit') f.applyHit({ damage: ev.damage, launch: ev.launch, stun: ev.stun,
          angle: ev.angle, facing: ev.facing, attacker: null, hitlag: ev.hitlag,
          extraHitstun: ev.extraHitstun || 0 });
        else if (ev.kind === 'freeze') f.freeze(ev.frames);
        else if (ev.kind === 'launchNoStun') f.launchNoStun(ev.vx, ev.vy);
        else if (ev.kind === 'knockOut') f.knockOut();
        else if (ev.kind === 'respawn') f.respawn(ev.x, {});
        else if (ev.kind === 'block') f.applyBlock({ damage: ev.damage, facing: ev.facing, perfect: !!ev.perfect });
        else if (ev.kind === 'charge') f.chargeUltimate(ev.n);
        else if (ev.kind === 'landed') f.moveLanded = true;
        else if (ev.kind === 'carry') { f.carryX = ev.carryX; f.snaredBy = ev.snaredBy || 0; }
      }
      f.events.length = 0;
      f.applyInput(I(seg.input));
      stage.step({ fighters: [f] });
      f.step(ctx);
      rows.push(snap(f));
    }
  }
  return { rows, log: combat.log };
}

// ---------------------------------------------------------------- scenarios ----
const hold = (frames, input) => ({ frames, input });
const S = [];

// movement, turning, running, stopping
S.push({ name: 'walk and run', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(20, {}), hold(40, { x: 0.3 }), hold(40, { x: 1 }), hold(20, { x: -1 }),
    hold(30, {}), hold(20, { x: -0.1 })] });

// jumps: full hop, short hop, double jump, fastfall
S.push({ name: 'jumps', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(10, {}), hold(1, { jump: true, jumpHeld: true, anyPress: true }),
    hold(40, { jumpHeld: true }), hold(1, { jump: true, anyPress: true }), hold(30, {}),
    hold(1, { downTap: true, y: -1, anyPress: true }), hold(40, { y: -1 }),
    hold(10, {}), hold(1, { jump: true, anyPress: true }), hold(40, {})] });

// dash, dash-cancel into a light, and shield out of dash
S.push({ name: 'dash and cancels', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: -10, y: 0.5,
  segments: [hold(10, {}), hold(1, { dodge: true, x: 1, anyPress: true }), hold(8, { x: 1 }),
    hold(1, { light: true, x: 1, anyPress: true }), hold(40, {}),
    hold(1, { dodge: true, x: -1, anyPress: true }), hold(14, { x: -1 }),
    hold(1, { guard: true, guardHeld: true, anyPress: true }), hold(30, { guardHeld: true })] });

// shield: hold to drain, block a hit, break it
S.push({ name: 'shield and break', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(6, {}), hold(1, { guard: true, guardHeld: true, anyPress: true }),
    hold(80, { guardHeld: true }), hold(60, {}), hold(1, { guard: true, guardHeld: true, anyPress: true }),
    hold(140, { guardHeld: true })],
  events: [{ frame: 40, kind: 'block', damage: 18, facing: 1 },
    { frame: 60, kind: 'block', damage: 30, facing: 1 }] });

// spot dodge and air dodge
S.push({ name: 'dodges', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(6, {}), hold(1, { dodge: true, anyPress: true }), hold(30, {}),
    hold(1, { jump: true, jumpHeld: true, anyPress: true }), hold(12, { jumpHeld: true }),
    hold(1, { dodge: true, x: 0.7, y: 0.7, anyPress: true }), hold(60, {})] });

// ground attacks and a light chain
S.push({ name: 'light chain', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(6, {}), hold(1, { light: true, anyPress: true }), hold(8, {}),
    hold(1, { light: true, anyPress: true }), hold(12, {}),
    hold(1, { light: true, anyPress: true }), hold(60, {})],
  events: [{ frame: 8, kind: 'landed' }, { frame: 18, kind: 'landed' }] });

// a heavy signature with a lunge, thrown near the ledge
S.push({ name: 'lunge at the ledge', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 33, y: 0.5,
  segments: [hold(6, {}), hold(1, { heavy: true, x: 1, anyPress: true }), hold(80, { x: 1 })] });

// aerials
S.push({ name: 'aerials', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(1, { jump: true, jumpHeld: true, anyPress: true }), hold(10, { jumpHeld: true }),
    hold(1, { light: true, anyPress: true }), hold(20, {}),
    hold(1, { light: true, y: -1, anyPress: true }), hold(60, {})] });

// ground pound onto the floor
S.push({ name: 'ground pound', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(1, { jump: true, jumpHeld: true, anyPress: true }), hold(20, { jumpHeld: true }),
    hold(1, { heavy: true, y: -1, anyPress: true }), hold(80, {})] });

// taken hits: hitstun, tumble, landing, knockdown and a tech
S.push({ name: 'hit into knockdown', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(10, {}), hold(120, {})],
  events: [{ frame: 10, kind: 'hit', damage: 14, launch: 62, stun: 62, angle: 55, facing: 1, hitlag: 6 }] });
S.push({ name: 'hit into tech', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(10, {}), hold(26, {}), hold(1, { guard: true, anyPress: true }), hold(100, {})],
  events: [{ frame: 10, kind: 'hit', damage: 14, launch: 62, stun: 62, angle: 80, facing: 1, hitlag: 6 }] });
S.push({ name: 'light hit, no tumble', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(10, {}), hold(60, { x: 1 })],
  events: [{ frame: 10, kind: 'hit', damage: 5, launch: 14, stun: 14, angle: 45, facing: 1, hitlag: 3 }] });

// DI: the stick held through hitlag bends the launch
S.push({ name: 'DI through hitlag', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(10, {}), hold(8, { x: -1, y: 1 }), hold(90, { x: -1, y: 1 })],
  events: [{ frame: 10, kind: 'hit', damage: 12, launch: 55, stun: 55, angle: 45, facing: 1, hitlag: 8 }] });

// off the ledge, recovery, ledge grab and every ledge option
for (const [name, act] of [['getup', { x: -1 }], ['roll', { dodge: true, anyPress: true }],
  ['attack', { light: true, anyPress: true }], ['jump', { jump: true, anyPress: true }],
  ['drop', { y: -1 }]]) {
  S.push({ name: `ledge ${name}`, stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 40, y: 6,
    segments: [hold(40, { x: -1 }), hold(1, { heavy: true, x: -1, anyPress: true }), hold(60, { x: -1 }),
      hold(10, {}), hold(1, act), hold(70, {})] });
}

// frozen, and mashing out of it
S.push({ name: 'frozen', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(6, {}), hold(20, {}), hold(30, { anyPress: true })],
  events: [{ frame: 6, kind: 'freeze', frames: 40 }] });

// vent-style launch with no stun
S.push({ name: 'launchNoStun', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(6, {}), hold(60, {})],
  events: [{ frame: 6, kind: 'launchNoStun', vx: 4, vy: 30 }] });

// KO and respawn
S.push({ name: 'ko and respawn', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  keepRespawn: true,
  segments: [hold(10, {}), hold(20, {}), hold(30, {}), hold(40, { anyPress: true }), hold(30, {})],
  events: [{ frame: 10, kind: 'knockOut' }, { frame: 30, kind: 'respawn', x: -20 }] });

// ultimate: denied without meter, then spent
S.push({ name: 'ultimate', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(4, {}), hold(1, { ult: true, anyPress: true }), hold(10, {}),
    hold(1, { ult: true, anyPress: true }), hold(140, {})],
  events: [{ frame: 8, kind: 'charge', n: 20 }] });

// mechanics: Momentum (Axe), Brace (Pike), Draw (Longbow), Surge (Gauntlets), Light/Spines
S.push({ name: 'momentum', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Axe', x: -30, y: 0.5,
  segments: [hold(10, {}), hold(70, { x: 1 }), hold(1, { heavy: true, x: 1, anyPress: true }), hold(70, {})] });
S.push({ name: 'brace', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Pike', x: 0, y: 0.5,
  segments: [hold(4, {}), hold(1, { guard: true, guardHeld: true, anyPress: true }),
    hold(100, { guardHeld: true }), hold(1, { heavy: true, heavyHeld: true, anyPress: true }), hold(70, {})] });
S.push({ name: 'draw', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Longbow', x: 0, y: 0.5,
  segments: [hold(4, {}), hold(90, { heavyHeld: true }), hold(30, {}), hold(60, { heavyHeld: true })] });
S.push({ name: 'surge', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Gauntlets', x: 0, y: 0.5,
  segments: [hold(4, {}), hold(1, { light: true, anyPress: true }), hold(60, {})],
  events: [{ frame: 10, kind: 'landed' }] });
S.push({ name: 'grimoire idle mechanic', stage: 'FoundryFloor', avatar: 'Noir', weapon: 'Grimoire', x: 0, y: 0.5,
  segments: [hold(200, {})] });

// a different stage: soft platforms, drop-through, and a moving raft
S.push({ name: 'soft platform drop', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: -21, y: 20,
  segments: [hold(60, {}), hold(1, { downTap: true, y: -1, anyPress: true }), hold(60, {})] });
S.push({ name: 'riding the raft', stage: 'Undertow', avatar: 'Classic', weapon: 'Sword', x: 0, y: 16,
  segments: [hold(240, {})] });

// heavier and lighter bodies, to catch anything that reads char stats wrongly
S.push({ name: 'hammer weight', stage: 'FoundryFloor', avatar: 'Steel', weapon: 'Hammer', x: 0, y: 0.5,
  segments: [hold(1, { jump: true, jumpHeld: true, anyPress: true }), hold(60, { jumpHeld: true, x: 1 })] });
S.push({ name: 'daggers weight', stage: 'FoundryFloor', avatar: 'Vapor', weapon: 'Daggers', x: 0, y: 0.5,
  segments: [hold(1, { jump: true, jumpHeld: true, anyPress: true }), hold(60, { jumpHeld: true, x: 1 })] });

// Buffers must NOT tick during hitlag. Hitlag runs to 12 frames and INPUT_BUFFER is 6, so a port
// that ticks them through the freeze silently eats every escape input - and nothing else in this
// file noticed: making the Luau tick them passed all thirty scenarios, because none of them
// pressed a button anywhere near a hit.
S.push({ name: 'buffer survives hitlag', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(10, {}), hold(2, {}), hold(1, { jump: true, anyPress: true }),
    hold(1, { dodge: true, anyPress: true }), hold(20, {}), hold(60, {})],
  events: [{ frame: 10, kind: 'hit', damage: 9, launch: 30, stun: 30, angle: 45, facing: 1, hitlag: 12 }] });

// grab whiff, which is the only path to ctx.combat.checkGrab
S.push({ name: 'grab whiff', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(6, {}), hold(1, { grab: true, anyPress: true }), hold(60, {})] });

// the light+guard grab shortcut, and shield-grab
S.push({ name: 'shield grab', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(4, {}), hold(1, { guard: true, guardHeld: true, anyPress: true }),
    hold(10, { guardHeld: true }), hold(1, { light: true, guardHeld: true, anyPress: true }), hold(50, {})] });

// pickup and guard-to-pickup, the two paths into itemNear
S.push({ name: 'pickup presses', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(4, {}), hold(1, { pickup: true, anyPress: true }), hold(10, {}),
    hold(1, { guard: true, anyPress: true }), hold(10, {}),
    hold(1, { pickup: true, y: -1, anyPress: true }), hold(20, {})] });

// taunt, including the early-out on any press
S.push({ name: 'taunt', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(4, {}), hold(1, { taunt: true, anyPress: true }), hold(20, {}),
    hold(1, { anyPress: true }), hold(20, {})] });

// stun and launch are DIFFERENT curves (Config.KNOCKBACK), and every hit above passes them equal,
// which made `tumbling = stun >= TUMBLE_THRESHOLD` and `tumbling = launch >= ...` indistinguishable.
// These straddle the threshold in both directions: a big launch with small stun must not tumble,
// and a small launch with big stun must.
S.push({ name: 'stun over, launch under', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(10, {}), hold(110, {})],
  events: [{ frame: 10, kind: 'hit', damage: 11, launch: 30, stun: 58, angle: 70, facing: 1, hitlag: 5 }] });
S.push({ name: 'launch over, stun under', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(10, {}), hold(110, {})],
  events: [{ frame: 10, kind: 'hit', damage: 11, launch: 58, stun: 30, angle: 70, facing: 1, hitlag: 5 }] });

// carryX only becomes non-zero from wind (hazards, Phase 2b) or a snare (needs two fighters), so
// its decay - 0.80 a frame grounded, 0.97 airborne, 0.97 while roped - is set directly here. It is
// the one path in _physics that nothing else in this file reaches.
S.push({ name: 'carry decay grounded', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(6, {}), hold(50, {})],
  events: [{ frame: 6, kind: 'carry', carryX: 40 }] });
S.push({ name: 'carry decay airborne', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(1, { jump: true, jumpHeld: true, anyPress: true }), hold(6, { jumpHeld: true }), hold(60, {})],
  events: [{ frame: 5, kind: 'carry', carryX: 40 }] });
S.push({ name: 'carry decay roped', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(6, {}), hold(50, {})],
  events: [{ frame: 6, kind: 'carry', carryX: 40, snaredBy: 30 }] });

// A press inside the taunt's 10-frame lockout, which the 'taunt' scenario above steps straight
// over: it only presses long after the early-out is already allowed.
S.push({ name: 'taunt lockout', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(4, {}), hold(1, { taunt: true, anyPress: true }), hold(6, {}),
    hold(1, { anyPress: true }), hold(6, {}), hold(1, { anyPress: true }), hold(30, {})] });

// pickup AND guard buffered on the same frame, so which one `consume` takes first is observable.
S.push({ name: 'pickup and guard together', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(4, {}), hold(1, { pickup: true, guard: true, anyPress: true }), hold(20, {})] });

// a chain input held between 0.4 and 0.5, either side of the direction thresholds
S.push({ name: 'chain near the threshold', stage: 'FoundryFloor', avatar: 'Classic', weapon: 'Sword', x: 0, y: 0.5,
  segments: [hold(6, {}), hold(1, { light: true, anyPress: true }), hold(6, { y: 0.45 }),
    hold(1, { light: true, y: 0.45, anyPress: true }), hold(40, { y: 0.45 }),
    hold(1, { light: true, x: 0.45, anyPress: true }), hold(40, { x: 0.45 })],
  events: [{ frame: 8, kind: 'landed' }, { frame: 20, kind: 'landed' }] });

// ---------------------------------------------------------------- output ----
const scenarios = [];
for (const spec of S) {
  const { rows, log } = run(spec);
  scenarios.push({ ...spec, rows, log });
}
const out = { fields: FIELDS, buffers: BUFFERS, scenarios };
fs.writeFileSync(path.join(HERE, '../tests/trace-fighter.json'), JSON.stringify(out));
const frames = scenarios.reduce((s, x) => s + x.rows.length, 0);
console.log(`fighter traces: ${scenarios.length} scenarios, ${frames} frames, `
  + `${frames * (FIELDS.length + 20)} recorded values`);
