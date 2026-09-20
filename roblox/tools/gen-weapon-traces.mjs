// Record the JavaScript weapon poses for the Luau port to reproduce.
//
//     node tools/gen-weapon-traces.mjs
//
// Same shape as tools/gen-channel-traces.mjs: the probes are DATA, every field weaponPose reads is
// written into the trace, and both harnesses read the same list.
//
// The output is not a flat bag of numbers like the channels are. `out.ult` is a different set of
// keys per weapon and per phase, and `out.trail` is present only while a blade is live - so the
// comparison is over a FLATTENED key set, and the key set itself is compared as well as the
// values. A pose that stops emitting `ult.chop` is a renderer that silently stops drawing the
// chop, and that has to fail here rather than look slightly wrong in Studio.
//
// Every number is a string. See tools/gen-traces.mjs for why.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const { weaponPose } = await import('../../web/src/render2d/weapons2d.js');
const { buildLoadout } = await import('../../web/src/data/loadout.js');

const n = (v) => (typeof v === 'number' ? String(v) : v);

const STATES = [
  'idle', 'run', 'dash', 'shield', 'shielddrop', 'ledge', 'tether', 'knockdown', 'ko',
  'hitstun', 'tumble', 'air', 'helpless', 'recovery', 'groundpound', 'attack',
  // No branch of weaponPose matches these, so they must come out as the bare rest pose. Controls.
  'idle_unused', 'grabbed',
];
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
    const ids = state === 'attack' ? moveIds : [null];
    for (const moveId of ids) {
      const m = moveId ? char.moves[moveId] : null;
      const span = m ? (m.startup + m.active + m.recovery + 4) : 20;
      // The ultimates and the aimed weapons read `t`; the ordinary swings are driven by mf alone.
      const usesTime = state !== 'attack' || moveId === 'Ultimate'
        || ['Blasters', 'Grimoire', 'Longbow'].includes(weapon);
      const TS = usesTime ? TIMES : ['1.84'];
      for (let fr = 0; fr <= span; fr += (state === 'attack' ? 1 : 3)) {
        for (const t of TS) {
          probes.push({
            avatar, weapon, state, moveId, t,
            index: probes.length % 4,
            vx: String((fr % 5) * 4 - 6),          // crosses the 1.5 drag threshold both ways
            onGround: (fr % 2) === 0,
            sf: String(fr), mf: String(fr),
            startupEff: m ? String(m.startup) : '0',
            charge: m && m.charge ? String(fr % 30) : '0',
            ultCooldown: String(fr % 40),
            ultShots: String(fr % 7),
          });
        }
      }
    }
  }
}

function fighterFor(p) {
  const char = buildLoadout(p.avatar, p.weapon);
  return {
    char, index: p.index, state: p.state,
    vx: Number(p.vx), onGround: p.onGround,
    sf: Number(p.sf), mf: Number(p.mf),
    moveId: p.moveId, move: p.moveId ? char.moves[p.moveId] : null,
    startupEff: Number(p.startupEff), charge: Number(p.charge),
    ultCooldown: Number(p.ultCooldown), ultShots: Number(p.ultShots),
  };
}

// Flatten the pose to `key=value` pairs. Nested objects become dotted keys and arrays become
// 1-based indices, so the Luau side can rebuild exactly the same list from 1-indexed tables.
function flatten(out) {
  const rows = {};
  const walk = (prefix, v) => {
    if (v === null || v === undefined) return;
    if (Array.isArray(v)) { v.forEach((x, i) => walk(`${prefix}.${i + 1}`, x)); return; }
    if (typeof v === 'object') { for (const key of Object.keys(v)) walk(prefix ? `${prefix}.${key}` : key, v[key]); return; }
    if (typeof v === 'number') {
      if (!Number.isFinite(v)) throw new Error(`${prefix} is ${v}`);
      rows[prefix] = String(v);
    } else if (typeof v === 'boolean') {
      rows[prefix] = v ? 'true' : 'false';
    } else {
      rows[prefix] = String(v);
    }
  };
  walk('', out);
  return rows;
}

const outputs = [];
const seenKeys = new Set();
for (const p of probes) {
  const pose = weaponPose(fighterFor(p), Number(p.t));
  const flat = flatten(pose);
  for (const key of Object.keys(flat)) seenKeys.add(key);
  outputs.push(flat);
}

const out = { probes, outputs, keys: [...seenKeys].sort() };
fs.writeFileSync(path.join(HERE, '../tests/trace-weapons.json'), JSON.stringify(out));
const withTrail = outputs.filter((r) => r['trail.to'] !== undefined).length;
const withUlt = outputs.filter((r) => r['ult.phase'] !== undefined).length;
console.log(`weapon traces: ${probes.length} probes, ${seenKeys.size} distinct keys, `
  + `${withTrail} with a trail, ${withUlt} ultimate frames`);
