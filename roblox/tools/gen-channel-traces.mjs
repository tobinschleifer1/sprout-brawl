// Record the JavaScript animation channels, pose by pose, for the Luau port to reproduce.
//
//     node tools/gen-channel-traces.mjs
//
// The probes are DATA, not code: every field channelsFor reads is written into the trace, and both
// harnesses read the same list. A probe is one fighter-state + one `t`, and the recorded output is
// the whole channel bag flattened. There is no stepping here - channelsFor is a pure function of
// the fields below, which is exactly what makes it testable without a simulation on either side.
//
// The probe fields are deliberately EXACTLY the snapshot's fields plus moveId. If a pose needed
// something the snapshot does not carry, it could not be written here, so this file doubles as the
// proof that src/shared/Snapshot.luau carries enough to draw with.
//
// Every number is a string. See tools/gen-traces.mjs for why.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const { channelsFor } = await import('../../web/src/render2d/channels.js');
const { buildLoadout } = await import('../../web/src/data/loadout.js');

const n = (v) => (typeof v === 'number' ? String(v) : v);

// ---------------------------------------------------------------- the probe grid ----
// Every state channelsFor switches on. The attack states carry a moveId; the rest ignore it.
const STATES = [
  'idle', 'run', 'dash', 'jumpsquat', 'air', 'helpless', 'recovery', 'landing',
  'hitstun', 'knockdown', 'tech', 'shield', 'shielddrop', 'stunned', 'spotdodge', 'airdodge',
  'ledge', 'ledgeaction', 'grab', 'holding', 'grabbed', 'groundpound', 'tether', 'frozen',
  'taunt', 'respawn', 'ko', 'attack',
  // `roll` and `throw` have no case in channelsFor and fall through to the neutral bag. They are
  // here as controls: if either ever grows a pose, this notices instead of silently not testing it.
  'roll', 'throw',
];
// ALL TWELVE weapons, because ultChannels branches on the weapon id and each branch is a wholly
// separate 30-line performance. Sampling four archetypes left eight of the twelve ultimate bodies
// untested - which is exactly the kind of coverage gap this project keeps finding by accident.
// Pike is the only weapon that thrusts, so it is the only one that reaches THRUSTABLE at all.
const KITS = [
  ['Classic', 'Sword'], ['Noir', 'Scythe'], ['Ember', 'Blasters'], ['Moss', 'Grimoire'],
  ['Vapor', 'Axe'], ['Steel', 'Pike'], ['Classic', 'Gauntlets'], ['Noir', 'Hammer'],
  ['Ember', 'Longbow'], ['Moss', 'Flail'], ['Vapor', 'Shield'], ['Steel', 'Daggers'],
];
const TIMES = ['0', '0.37', '1.84', '7.25'];

const probes = [];
for (const [avatar, weapon] of KITS) {
  const char = buildLoadout(avatar, weapon);
  const moveIds = Object.keys(char.moves);
  for (const state of STATES) {
    // Attacks sweep every move of the kit and every frame of each; everything else sweeps its own
    // state frame. A move's pose is a function of mf against startupEff/active/recovery, so the
    // sweep has to cross all three boundaries or the wind/strike/settle branches go untested.
    const ids = state === 'attack' ? moveIds : [null];
    for (const moveId of ids) {
      const m = moveId ? char.moves[moveId] : null;
      const span = m ? (m.startup + m.active + m.recovery + 4) : 26;
      // `t` is wall clock, and almost nothing reads it: the ordinary attack bodies are driven
      // entirely by mf. Only the held stances (counter, spray) and three of the ultimates breathe
      // on it, so sweeping four times across every attack quadrupled the fixture for four
      // identical poses. The states that DO read t still sweep all four.
      const usesTime = state !== 'attack'
        || moveId === 'Ultimate' || moveId === 'ItemSpray' || (m && m.kind === 'counter');
      const TS = usesTime ? TIMES : ['1.84'];
      for (let fr = 0; fr <= span; fr += (state === 'attack' ? 1 : 3)) {
        for (const t of TS) {
          // vy picks the rising / apex / falling branch, and only the airborne states read it.
          // Sweeping it everywhere tripled the attack probes - which are the bulk - for three
          // identical poses each.
          const VYS = (state === 'air' || state === 'helpless' || state === 'recovery')
            ? [42, 0, -38] : [0];
          for (const vy of VYS) {
            probes.push({
              avatar, weapon, state, moveId, t,
              index: probes.length % 4,
              x: '0', y: '0', vx: state === 'hitstun' ? '-9.5' : '14.25', vy: String(vy),
              facing: (probes.length % 2) ? '1' : '-1',
              sf: String(fr), mf: String(fr),
              startupEff: m ? String(m.startup) : '0',
              frameCount: String(fr * 7 + 3),
              charge: m && m.charge ? String(fr % 30) : '0',
              hitlag: String(fr % 3),
              fastFalling: (fr % 2) === 0,
              ultCooldown: String(fr % 40),
              techRoll: String((fr % 3) - 1),
              chillStacks: String(fr % 4),
              ledgeAction: ['attack', 'roll', 'climb'][fr % 3],
              onGround: (fr % 2) === 0,
              tumbling: (fr % 3) === 0,
              invincible: String(fr % 5),
              shield: '33.25', percent: '61.5', stocks: '2', ultCharge: '80',
              alive: true,
            });
          }
        }
      }
    }
  }
}

// ---------------------------------------------------------------- run them ----
// The fighter handed to channelsFor is a plain bag, not a Fighter. That is the point: the client
// has a decoded snapshot and a char, never a Fighter, so this records what the client can actually
// reproduce. A field channelsFor reads that is not set here comes out undefined and the diff says so.
function fighterFor(p) {
  const char = buildLoadout(p.avatar, p.weapon);
  return {
    char, index: p.index,
    x: Number(p.x), y: Number(p.y), vx: Number(p.vx), vy: Number(p.vy),
    facing: Number(p.facing), state: p.state,
    sf: Number(p.sf), mf: Number(p.mf),
    moveId: p.moveId, move: p.moveId ? char.moves[p.moveId] : null,
    startupEff: Number(p.startupEff), frameCount: Number(p.frameCount),
    charge: Number(p.charge), hitlag: Number(p.hitlag),
    fastFalling: p.fastFalling, ultCooldown: Number(p.ultCooldown),
    techRoll: Number(p.techRoll), onGround: p.onGround, tumbling: p.tumbling,
    invincible: Number(p.invincible), shield: Number(p.shield),
    percent: Number(p.percent), stocks: Number(p.stocks), ultCharge: Number(p.ultCharge),
    alive: p.alive,
    // The two flattened ones, rebuilt into the shape channelsFor reads them through.
    effects: { chill: { stacks: Number(p.chillStacks) }, tangle: { stacks: 0 },
               grit: { hide: 0, slow: 0 }, slow: 0, frozenBonus: false },
    la: p.ledgeAction ? { kind: p.ledgeAction, L: {} } : null,
  };
}

// The channel bag, flattened. Written out longhand rather than walked, so a channel that stops
// being produced fails here instead of quietly vanishing from both sides at once.
const CHANNELS = [
  'lean', 'bob', 'sx', 'sy', 'spinY', 'spinZ', 'legL', 'legR', 'head',
  'opacity', 'rigRotZ', 'yOff', 'bubble', 'shakeX', 'smear',
  'armL.z', 'armL.x', 'armL.ext', 'armR.z', 'armR.x', 'armR.ext',
];
const outputs = [];
for (const p of probes) {
  const ch = channelsFor(fighterFor(p), Number(p.t));
  const row = {};
  for (const key of CHANNELS) {
    const [a, b] = key.split('.');
    const v = b === undefined ? ch[a] : ch[a][b];
    if (typeof v !== 'number' || !Number.isFinite(v)) {
      throw new Error(`channel ${key} is ${v} for state=${p.state} move=${p.moveId} weapon=${p.weapon}`);
    }
    row[key] = n(v);
  }
  // tint is a colour or null, and visible is a boolean. Both are compared, neither is a number.
  row.tint = ch.tint === null || ch.tint === undefined ? '' : String(ch.tint);
  row.visible = ch.visible === true;
  outputs.push(row);
}

const out = { channels: CHANNELS, probes, outputs };
fs.writeFileSync(path.join(HERE, '../tests/trace-channels.json'), JSON.stringify(out));
const tints = outputs.filter((r) => r.tint !== '').length;
console.log(`channel traces: ${probes.length} probes, ${CHANNELS.length} channels, ${tints} tinted frames`);
