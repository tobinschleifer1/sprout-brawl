// The animation manifest: every animation the revamp's hand-drawn sprites have to cover, broken
// into the KEY POSES an artist draws, each with the exact game frames it is shown on.
//
// This is the single list the production doc (web/tools/build-animation-doc.mjs), the basic
// placeholder sprites (web/tools/basic-sprites.mjs) and, later, the sprite renderer all read.
// Nothing here is typed in by hand that the game already knows: move key poses are cut from each
// move's real startup / active / recovery frames, so a balance change that alters a move's frame
// data changes its key-pose spans with it, and the doc cannot drift from the game.
//
// RULE 2 of the revamp plan: a sprite frame is chosen from the fighter's STATE, never from a clock.
// That is why every shared key carries a `sample` - the fighter state it depicts - and every move
// key a frame range: those are the inputs the sprite selector will map from, and rollback replays
// them exactly.
//
// Pixel-art fighting games HOLD a drawing and snap to the next rather than tweening, so a key pose
// here is shown on every frame of its range. How the frames of a phase are divided is set by the
// templates below; the principles behind them are the five documented at the top of channels.js.

import { WEAPONS } from './weapons/index.js';

export const PX_PER_STUD = 8;          // the sprite scale; see the plan's art-direction table

// ----------------------------------------------------------------------- move key templates ----
// Each key: [name, phase, fraction of that phase where it ENDS, what to draw].
// Phases are 'startup' | 'active' | 'recovery'. Fractions within a phase must end at 1.
const T = (name, phase, end, brief) => ({ name, phase, end, brief });
export const TEMPLATES = {
  light: [
    T('anticipation', 'startup', 0.6, 'Pull back against the direction of the strike and slightly past it. This is the frame the defender reacts to: exaggerate it, never cut it.'),
    T('cocked', 'startup', 1, 'Fully wound; on moves faster than 8 frames draw this as a smear - the limb stretched along the path it is about to take.'),
    T('contact', 'active', 1, 'The hitting pose, fully extended. Brightest values in the whole move; the weapon at its contact angle.'),
    T('recover', 'recovery', 1, 'Overshoot past the strike and settle back toward idle. Light moves snap back fast.'),
  ],
  air: [
    T('anticipation', 'startup', 0.6, 'Tuck and pull back; the body stays compact in the air.'),
    T('cocked', 'startup', 1, 'Fully wound, limbs gathered - a smear frame if startup is under 8.'),
    T('contact', 'active', 1, 'Extended strike; held for every active frame, with a slight drift so it does not read as a dropped frame.'),
    T('follow-through', 'recovery', 0.4, 'Carry past the strike; the weapon keeps travelling.'),
    T('settle', 'recovery', 1, 'Gather back into the airborne idle.'),
  ],
  sig: [
    T('anticipation', 'startup', 0.3, 'The big tell: weight shifts well back. Signature moves are slow, so this pose is on screen long enough to be read - make it unmistakable.'),
    T('overshoot', 'startup', 0.55, 'Push slightly past the anticipation, a coiled spring.'),
    T('coil', 'startup', 0.85, 'Held tension; the weapon at its wind-up angle.'),
    T('launch', 'startup', 1, 'The first frames of motion, drawn as a smear.'),
    T('contact', 'active', 1, 'The hit - the ability VFX layer plays over this.'),
    T('follow-through', 'recovery', 0.35, 'A long carry past the strike. Heavy weapons overshoot furthest.'),
    T('settle', 'recovery', 1, 'Damped return to idle, with a wobble for heavy weapons.'),
  ],
  ult: [
    T('activation', 'startup', 0.35, 'The banner pose, shown during the 26-frame freeze: a hero stance facing the camera three-quarters on.'),
    T('wind-up', 'startup', 0.7, 'Gather power; the weapon at its ultimate scale.'),
    T('launch', 'startup', 1, 'Explosive first motion, smeared.'),
    T('strike I', 'active', 0.25, 'First beat of the ultimate.'),
    T('strike II', 'active', 0.5, 'Second beat.'),
    T('peak', 'active', 0.75, 'The apex - the biggest silhouette in the game.'),
    T('finisher', 'active', 1, 'The final hit; the impact flash is layered on top.'),
    T('follow-through', 'recovery', 0.3, 'Carry through.'),
    T('settle', 'recovery', 0.7, 'Come down from the ultimate.'),
    T('return', 'recovery', 1, 'Back to the idle stance.'),
  ],
};

export function templateFor(moveId) {
  if (moveId === 'Ultimate') return 'ult';
  if (moveId.startsWith('Sig')) return 'sig';
  if (moveId.startsWith('Air')) return 'air';
  return 'light';
}

// Split `frames` among keys ending at the given fractions: every key at least one frame, the
// whole range covered exactly once. A key a phase is too short to hold (a 2-frame startup cut
// into three) is dropped rather than given zero frames - the test asserts nothing overlaps.
export function allocate(frames, ends) {
  const out = [];
  let prev = 0;
  for (let i = 0; i < ends.length; i++) {
    const last = i === ends.length - 1;
    const room = frames - (ends.length - 1 - i);          // frames left once each later key gets one
    let b = last ? frames : Math.min(room, Math.max(prev + 1, Math.round(ends[i] * frames)));
    if (b <= prev) { out.push(null); continue; }
    out.push([prev, b]);
    prev = b;
  }
  return out;
}

const PHASES = ['startup', 'active', 'recovery'];

// The key poses of one move, as [from, to) in move frames (frame 0 = the first startup frame).
export function moveKeys(move, moveId) {
  const tpl = TEMPLATES[templateFor(moveId)];
  const len = { startup: move.startup, active: move.active, recovery: move.recovery };
  let base = 0;
  const keys = [];
  for (const phase of PHASES) {
    const inPhase = tpl.filter((k) => k.phase === phase);
    const spans = allocate(len[phase], inPhase.map((k) => k.end));
    inPhase.forEach((k, i) => {
      if (spans[i]) keys.push({ name: k.name, phase, from: base + spans[i][0], to: base + spans[i][1], brief: k.brief });
    });
    base += len[phase];
  }
  return keys;
}

export const MOVE_ORDER = ['LightNeutral1', 'LightNeutral2', 'LightNeutral3', 'LightSide1', 'LightSide2', 'LightUp',
  'LightDown', 'AirNeutral', 'AirForward', 'AirUp', 'AirDown', 'Finisher', 'AirFinisher', 'SigSide', 'SigDown', 'SigNeutral', 'Ultimate'];

// ------------------------------------------------------------------------ shared animations ----
// Drawn once, shared by every weapon, tinted per avatar. `sample` is the fighter state each key
// depicts - the fields a sprite selector reads. `basic: false` marks keys the game has no
// procedural version of yet.
const K = (name, sample, brief) => ({ name, sample, brief });
const loop = (n, step, extra, label) => Array.from({ length: n }, (_, i) => K(`${label} ${i + 1}`, { ...extra, frameCount: i * step }));

export const SHARED = [
  { id: 'idle', label: 'Idle', frames: '60 (loop)', driver: 'fighter frame count', note: 'Breathing, weapon at rest.',
    keys: loop(6, 10, { state: 'idle' }, 'breath') },
  { id: 'walk', label: 'Walk', frames: '32 (loop)', driver: 'distance travelled', note: 'Drawn to 12 studs/s so the feet do not slide.',
    keys: ['contact R', 'down R', 'passing R', 'up R', 'contact L', 'down L', 'passing L', 'up L'].map((n, i) => K(n, { state: 'run', vx: 8, frameCount: i * 4 })) },
  { id: 'run', label: 'Run', frames: '24 (loop)', driver: 'distance travelled', note: 'Drawn to 23 studs/s, leaning into it.',
    keys: ['contact R', 'down R', 'passing R', 'up R', 'contact L', 'down L', 'passing L', 'up L'].map((n, i) => K(n, { state: 'run', vx: 22, frameCount: i * 3 })) },
  { id: 'dash', label: 'Dash', frames: '18', driver: 'state frame', note: 'DASH.frames = 18.',
    keys: ['push-off', 'stretch', 'glide', 'brake', 'settle'].map((n, i) => K(n, { state: 'dash', sf: i * 4, vx: 30 })) },
  { id: 'jumpsquat', label: 'Jumpsquat', frames: '3', driver: 'state frame', note: 'MOVE.jumpsquat = 3.',
    keys: [K('crouch', { state: 'jumpsquat', sf: 0 }), K('spring', { state: 'jumpsquat', sf: 2 })] },
  { id: 'air', label: 'Rise / apex / fall', frames: 'n/a', driver: 'vertical speed', note: 'Chosen by velocity band, not by a timer.',
    keys: [['rise fast', 40], ['rise slow', 15], ['apex', 0], ['fall slow', -12], ['fall fast', -35]].map(([n, vy]) => K(n, { state: 'air', onGround: false, vy }))
      .concat([K('fast-fall', { state: 'air', onGround: false, vy: -60, fastFalling: true })]) },
  { id: 'landing', label: 'Landing', frames: '4-12', driver: 'state frame', note: 'Matches landing lag.',
    keys: ['impact', 'absorb', 'stand'].map((n, i) => K(n, { state: 'landing', sf: i * 2 })) },
  { id: 'shield', label: 'Shield', frames: 'hold', driver: 'shield HP', note: 'The bubble shrinks with SHIELD.max = 50.',
    keys: [K('raise', { state: 'shield', sf: 0 }), K('hold', { state: 'shield', sf: 8 }), K('hold, cracking', { state: 'shield', sf: 8, shield: 12 })] },
  { id: 'spotdodge', label: 'Spot dodge', frames: '24', driver: 'state frame', note: 'Frames 3-14 are invincible: outline them.',
    keys: ['duck', 'vanish', 'hold', 'return', 'recover'].map((n, i) => K(n, { state: 'spotdodge', sf: i * 5 })) },
  { id: 'airdodge', label: 'Air dodge', frames: '28', driver: 'state frame', note: 'Frames 3-13 are invincible: outline them.',
    keys: ['tuck', 'dart', 'hold', 'unfurl', 'recover'].map((n, i) => K(n, { state: 'airdodge', sf: i * 6, onGround: false })) },
  { id: 'tech', label: 'Tech in place / roll', frames: '30', driver: 'state frame', note: 'TECH window = 8 frames.',
    keys: [K('slap ground', { state: 'tech', sf: 0 }), K('pop up', { state: 'tech', sf: 10 }), K('ready', { state: 'tech', sf: 22 }),
      K('roll: tuck', { state: 'tech', sf: 2, techRoll: 1 }), K('roll: over', { state: 'tech', sf: 12, techRoll: 1 }), K('roll: rise', { state: 'tech', sf: 24, techRoll: 1 })] },
  { id: 'knockdown', label: 'Knockdown + getup', frames: '26 + 10', driver: 'state frame', note: 'KNOCKDOWN.frames = 26.',
    keys: ['bounce', 'flat', 'stir', 'push up', 'kneel', 'stand'].map((n, i) => K(n, { state: 'knockdown', sf: i * 6 })) },
  { id: 'ledge', label: 'Ledge hang, climb, roll, jump, attack', frames: 'loop + 4 x ~20', driver: 'state frame', note: 'One set shared by every weapon.',
    keys: [K('hang', { state: 'ledge', sf: 0, onGround: false }), K('hang, swaying', { state: 'ledge', sf: 20, onGround: false })]
      .concat(['climb', 'roll', 'jump', 'attack'].flatMap((kind) => ['start', 'mid', 'end'].map((p, i) => K(`${kind}: ${p}`, { state: 'ledgeaction', sf: i * 8, la: { kind }, onGround: false })))) },
  { id: 'hitstun', label: 'Hitstun light / heavy', frames: 'varies', driver: 'hitstun remaining', note: '',
    keys: [K('light: flinch', { state: 'hitstun', sf: 0 }), K('light: recoil', { state: 'hitstun', sf: 6 }),
      K('heavy: buckle', { state: 'hitstun', sf: 0, hitstun: 40 }), K('heavy: thrown back', { state: 'hitstun', sf: 8, hitstun: 40 })] },
  { id: 'tumble', label: 'Tumble', frames: 'loop', driver: 'spin angle', note: 'Frame = spin angle / 45 degrees, never a timer.',
    keys: Array.from({ length: 8 }, (_, i) => K(`${i * 45} degrees`, { state: 'hitstun', tumbling: true, sf: i * 3, onGround: false })) },
  { id: 'grabbed', label: 'Grabbed / thrown', frames: 'varies', driver: 'state frame', note: '',
    keys: ['caught', 'struggle', 'lifted', 'released'].map((n, i) => K(n, { state: 'grabbed', sf: i * 8 })) },
  { id: 'taunt', label: 'Taunt', frames: '90', driver: 'state frame', note: 'TAUNT_FRAMES = 90.',
    keys: Array.from({ length: 10 }, (_, i) => K(`beat ${i + 1}`, { state: 'taunt', sf: i * 9 })) },
  { id: 'ko', label: 'KO, respawn, victory, defeat', frames: 'n/a', driver: 'match event', note: 'Victory and defeat have no in-game state yet; they come with the results screen.',
    keys: [K('KO: struck', { state: 'ko', sf: 0 }), K('KO: flung', { state: 'ko', sf: 6 }), K('KO: gone', { state: 'ko', sf: 12 }),
      K('respawn: descend', { state: 'respawn', sf: 0, onGround: false }), K('respawn: land', { state: 'respawn', sf: 30, onGround: false }), K('respawn: ready', { state: 'respawn', sf: 60, onGround: false })]
      .concat(Array.from({ length: 6 }, (_, i) => ({ ...K(`victory ${i + 1}`, null), basic: false })))
      .concat(Array.from({ length: 4 }, (_, i) => ({ ...K(`defeat ${i + 1}`, null), basic: false }))) },
  // Disaster reactions. Planned with the disaster system; no basic version until it exists.
  { id: 'disaster', label: 'Disaster reactions', frames: 'varies', driver: 'disaster hit type', note: 'Arrive with the disaster engine (roadmap R5).',
    keys: [['lava: scorched launch', 3], ['lightning: electrified freeze', 3], ['tornado: caught spinning', 4], ['tsunami: swept', 3], ['earthquake: popped up', 2], ['meteor: blasted', 2]]
      .flatMap(([n, c]) => Array.from({ length: c }, (_, i) => ({ ...K(`${n} ${i + 1}`, null), basic: false }))) },
];

// ------------------------------------------------------------------------------ effects (VFX) ----
// Flipbooks rather than poses: drawn once, played over the fighters. `procedural` marks the ones
// the game already draws procedurally today (the basic version); the rest are new.
export const VFX = [
  { id: 'hitspark', label: 'Hit sparks (light / medium / heavy)', frames: 12, procedural: true },
  { id: 'shieldhit', label: 'Shield hit', frames: 4, procedural: true },
  { id: 'shieldbreak', label: 'Shield break', frames: 6, procedural: true },
  { id: 'parry', label: 'Perfect-shield / counter flash', frames: 4, procedural: false },
  { id: 'dust', label: 'Dust: run, dash, landing, ledge', frames: 17, procedural: true },
  { id: 'ko', label: 'KO blast line', frames: 8, procedural: true },
  { id: 'respawn', label: 'Respawn beam', frames: 6, procedural: false },
  { id: 'invincible', label: 'Invincibility outline shimmer', frames: 4, procedural: false },
  ...WEAPONS.map((w) => ({ id: `smear-${w.id}`, label: `${w.id}: swing smears`, frames: 3, procedural: true, weapon: w.id })),
  ...WEAPONS.map((w) => ({ id: `abilities-${w.id}`, label: `${w.id}: signature-move effects (3 moves x 5)`, frames: 15, procedural: false, weapon: w.id })),
  ...WEAPONS.map((w) => ({ id: `ult-${w.id}`, label: `${w.id}: ultimate effect`, frames: 8, procedural: true, weapon: w.id })),
  ...WEAPONS.map((w) => ({ id: `banner-${w.id}`, label: `${w.id}: ultimate banner portrait`, frames: 1, procedural: false, weapon: w.id })),
  ...['Lava Surge', 'Lightning Storm', 'Tornado', 'Tsunami', 'Earthquake', 'Meteor Shower'].map((d) => ({ id: `disaster-${d}`, label: `${d}: warning, strike, aftermath`, frames: 8, procedural: false })),
];

// ---------------------------------------------------------------------------------- manifest ----
export function manifest() {
  const weapons = WEAPONS.map((w) => ({
    id: w.id, archetype: w.archetype,
    moves: MOVE_ORDER.filter((id) => w.moves[id]).map((id) => {
      const m = w.moves[id];
      return { id, label: m.label || m.name || id, template: templateFor(id),
        startup: m.startup, active: m.active, recovery: m.recovery,
        total: m.startup + m.active + m.recovery, keys: moveKeys(m, id) };
    }),
  }));
  const sharedKeys = SHARED.reduce((t, a) => t + a.keys.length, 0);
  const moveKeysCount = weapons.reduce((t, w) => t + w.moves.reduce((u, m) => u + m.keys.length, 0), 0);
  const vfxFrames = VFX.reduce((t, v) => t + v.frames, 0);
  return { pxPerStud: PX_PER_STUD, shared: SHARED, weapons, vfx: VFX,
    totals: { sharedKeys, moveKeys: moveKeysCount, vfxFrames, all: sharedKeys + moveKeysCount + vfxFrames } };
}
