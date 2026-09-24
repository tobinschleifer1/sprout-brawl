// Record what the JavaScript disasters do inside real matches, frame by frame, for
// tests/disaster-parity.luau to replay through Disasters.luau.
//
//     node tools/gen-disaster-traces.mjs
//
// Each forced scenario runs one disaster from 0.5 s into the fight with three fighters: two PINNED
// probes whose positions are a pure function of the frame (so both sides reproduce them without
// recording them) and one free fighter physics moves - the one whose launches exercise the
// knockback curves. The lightning scenario has the free fighter shield, for the block path. A long
// chaos run with the real 45 s scheduler covers scheduling and the random pick.
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
const { DISASTERS } = await import('../../web/src/engine/disasters.js');

const n = (v) => (typeof v === 'number' ? String(v) : v);
const nn = (v) => (v === null || v === undefined ? null : typeof v === 'number' ? String(v) : v);

function flatten(v, p, out) {
  if (v === null || v === undefined) return out;
  if (Array.isArray(v)) { v.forEach((x, i) => flatten(x, `${p}[${i}]`, out)); return out; }
  if (typeof v === 'object') { for (const k of Object.keys(v).sort()) flatten(v[k], `${p}.${k}`, out); return out; }
  out.push([p, n(v)]);
  return out;
}

// The two probes, as functions of the frame. Probe 0 sweeps the floor just above it; probe 1 holds
// a point a third of the way along. Both sides compute these identically.
export function probeAt(stage, i, frame) {
  const m = stage.main, span = m.x2 - m.x1;
  if (i === 0) return { x: m.x1 + 2 + (span - 4) * (((frame * 0.009) % 1)), y: m.top + 0.6 };
  return { x: m.x1 + span / 3, y: m.top + 0.3 };
}

const WHO = [['Classic', 'Sword'], ['Noir', 'Axe'], ['Ember', 'Blasters']];

function run(spec) {
  const data = STAGES.find((s) => s.id === spec.stage);
  const script = {};
  const input = { kb2Active: false, poll() {}, get: (s) => script[s] || emptyFrame() };
  const m = new Match({
    mode: 'StockFFA', stage: data, input, seed: spec.seed, stocks: 3, timeLimit: 600, items: false,
    disasters: spec.mode, forceDisaster: spec.force || undefined, disasterFirstAt: spec.firstAt ?? undefined,
    fighters: WHO.map(([a, w], i) => ({ char: buildLoadout(a, w), skin: 0, team: i, source: `p${i}`, isBot: false, name: `P${i}` })),
  });
  const rows = [];
  for (let frame = 0; frame < spec.frames; frame++) {
    for (let k = 0; k < 3; k++) {
      const inp = emptyFrame();
      if (frame < 4) inp.anyPress = true;                               // drop in
      if (k === 2 && spec.shield && frame > 230) { inp.guardHeld = true; if (frame % 90 === 0) inp.guard = true; }
      if (k === 2 && spec.guardAt !== undefined && frame >= spec.guardAt) { inp.guardHeld = true; if (frame === spec.guardAt) inp.guard = true; }
      script[`p${k}`] = inp;
    }
    // `place` drops the free fighter somewhere on the first frame of the fight, to land by physics.
    if (spec.place && m.state === 'fight' && !spec._placed) {
      const f = m.fighters[2];
      f.x = spec.place[0]; f.y = spec.place[1]; f.vx = 0; f.vy = 0;
      spec._placed = true;
    }
    if (m.state === 'fight') {
      for (const i of [0, 1]) {
        const f = m.fighters[i];
        if (!f.alive) continue;
        const at = probeAt(m.stage, i, frame);
        f.x = at.x; f.y = at.y; f.vx = 0; f.vy = 0;
      }
    }
    m.events.length = 0;
    m.step();
    const row = [m.state, n(m.frame), String(!!m.stage.ledgesLocked)];
    for (const f of m.fighters) {
      row.push(n(f.x), n(f.y), n(f.vx), n(f.vy), n(f.percent), f.state, n(f.stocks), String(f.alive), n(f.env.windX), String(f.onGround));
    }
    row.push(flatten(m.stage.visual.disaster, 'd', []));
    row.push(m.events.filter((e) => e.disaster || e.type === 'disaster').map((e) =>
      [e.type, nn(e.victim), nn(e.damage), nn(e.disaster), nn(e.launch), nn(e.angle), nn(e.facing), e.perfect === undefined ? null : String(e.perfect)]));
    rows.push(row);
    if (m.state === 'results') break;
  }
  return rows;
}

const S = [];
const dur = (t) => Math.ceil(0.5 * 60) + 240 + Math.max(90, DISASTERS[t].warn) + DISASTERS[t].strike + DISASTERS[t].after + 60;
// the countdown is 210 frames; the fight clock starts on GO
S.push({ name: 'lava surge', stage: 'Smeltworks', mode: 'stage', force: 'lavasurge', firstAt: 0.5, seed: 7, frames: dur('lavasurge') });
S.push({ name: 'lightning with rods, shielding', stage: 'Rooftops', mode: 'stage', force: 'lightning', firstAt: 0.5, seed: 7, frames: dur('lightning'), shield: true });
S.push({ name: 'lightning, open floor', stage: 'FoundryFloor', mode: 'chaos', force: 'lightning', firstAt: 0.5, seed: 21, frames: dur('lightning') });
S.push({ name: 'tornado', stage: 'Saltflat', mode: 'stage', force: 'tornado', firstAt: 0.5, seed: 7, frames: dur('tornado') });
S.push({ name: 'tsunami', stage: 'Undertow', mode: 'stage', force: 'tsunami', firstAt: 0.5, seed: 9, frames: dur('tsunami') });
// Saltflat's plate is the bunker (-20..-12, top 4): the free fighter is dropped onto it.
S.push({ name: 'earthquake, plates', stage: 'Saltflat', mode: 'chaos', force: 'earthquake', firstAt: 0.5, seed: 7, frames: dur('earthquake'), place: [-16, 9] });
S.push({ name: 'earthquake as a tremor', stage: 'FoundryFloor', mode: 'chaos', force: 'earthquake', firstAt: 0.5, seed: 7, frames: dur('earthquake') });
S.push({ name: 'meteor shower', stage: 'FoundryFloor', mode: 'chaos', force: 'meteor', firstAt: 0.5, seed: 7, frames: dur('meteor') });
S.push({ name: 'chaos, real schedule', stage: 'Rooftops', mode: 'chaos', seed: 5, frames: 60 * 150 });

// A PERFECT shield: dry-run to find the first bolt and where it lands, then put the free fighter
// under it and raise the shield 3 frames before - inside SHIELD.perfectFrames. Asserted below, so
// if a data change moves the bolt this scenario fails loudly instead of quietly covering nothing.
{
  const probe = { name: 'probe', stage: 'FoundryFloor', mode: 'chaos', force: 'lightning', firstAt: 0.5, seed: 33, frames: dur('lightning') };
  const rows = run(probe);
  let bolt = null;
  rows.forEach((r, frame) => {
    if (bolt) return;
    const view = r[r.length - 2];
    const live = view.findIndex(([p, v]) => /strikes\[\d+\]\.live$/.test(p) && v === true);
    if (live >= 0) { const idx = view[live][0].match(/strikes\[(\d+)\]/)[1]; bolt = { frame, x: Number(view.find(([p]) => p === `d.strikes[${idx}].x`)[1]) }; }
  });
  // Both sides of the perfect-shield edge. Raising the shield some frames before the bolt, find
  // the latest lead that still blocks perfectly, then record it AND one frame later - so a window
  // that is a frame too long or too short changes one of the two and fails the replay.
  const withLead = (lead) => ({ name: `lightning, shield raised ${lead} frames early`, stage: 'FoundryFloor', mode: 'chaos',
    force: 'lightning', firstAt: 0.5, seed: 33, frames: dur('lightning'),
    place: [Math.round((bolt.x + 0.4) * 1000) / 1000, 1], guardAt: bolt.frame - lead });
  const perfectAt = (lead) => run({ ...withLead(lead) }).flatMap((r) => r[r.length - 1]).find((e) => e[0] === 'block' && e[1] === '2');
  let edge = null;
  for (let lead = 1; lead <= 12; lead++) { const b = perfectAt(lead); if (b && b[7] === 'true') edge = lead; }
  if (edge === null) throw new Error('no lead produced a perfect block');
  const inside = perfectAt(edge), outside = perfectAt(edge + 1);
  if (!inside || inside[7] !== 'true' || !outside || outside[7] !== 'false') throw new Error('the perfect-shield edge did not bracket');
  S.push({ ...withLead(edge), name: 'lightning, perfect shield at the edge of the window' });
  S.push({ ...withLead(edge + 1), name: 'lightning, one frame too early: not perfect' });
}
// Many random picks from the chaos pool, so its ORDER is exercised rather than one or two draws.
S.push({ name: 'chaos, many picks', stage: 'FoundryFloor', mode: 'chaos', firstAt: 0.5, seed: 17, frames: 60 * 480 });

const scenarios = S.map((spec) => { const rows = run(spec); delete spec._placed; return { ...spec, rows }; });
fs.writeFileSync(path.join(HERE, '../tests/trace-disaster.json'), JSON.stringify({ scenarios }));
const perfect = scenarios.find((x) => x.name === 'lightning, perfect shield at the edge of the window').rows.flatMap((r) => r[r.length - 1]).filter((e) => e[0] === 'block' && e[7] === 'true');
if (!perfect.length) throw new Error('the perfect-shield scenario no longer produces a perfect block - re-time it');
const picks = scenarios.find((x) => x.name === 'chaos, many picks').rows.flatMap((r) => r[r.length - 1]).filter((e) => e[0] === 'disaster').map((e) => e[3]);
if (new Set(picks).size < 3) throw new Error(`the long chaos run drew too few kinds of disaster: ${picks.join(', ')}`);
const frames = scenarios.reduce((s, x) => s + x.rows.length, 0);
const events = scenarios.reduce((s, x) => s + x.rows.reduce((t, r) => t + r[r.length - 1].length, 0), 0);
console.log(`disaster traces: ${scenarios.length} scenarios, ${frames} frames, ${events} disaster events; chaos drew ${picks.join(', ')}`);

// ---- the picture: view -> shapes, for tests/disaster-shapes.luau ----
// Every 5th frame's disaster view from the scenarios above, with the shape list and banner the
// JavaScript draws for it. Numbers travel as strings: Lune's JSON decoder keeps ~16 digits.
{
  const { disasterShapes, disasterBanner } = await import('../../web/src/render2d/disasterShapes.js');
  const { StageRuntime } = await import('../../web/src/engine/stage.js');
  const str = (v) => (typeof v === 'number' ? String(v) : Array.isArray(v) ? v.map(str)
    : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, str(x)])) : v);
  const samples = [];
  for (const spec of S) {
    if (spec.name.startsWith('chaos')) continue;
    const data = STAGES.find((s) => s.id === spec.stage);
    const script = {};
    const m = new Match({ mode: 'StockFFA', stage: data, input: { kb2Active: false, poll() {}, get: (s) => script[s] || emptyFrame() },
      seed: spec.seed, stocks: 3, timeLimit: 600, items: false, disasters: spec.mode, forceDisaster: spec.force, disasterFirstAt: spec.firstAt,
      fighters: WHO.map(([a, w], i) => ({ char: buildLoadout(a, w), skin: 0, team: i, source: `p${i}`, isBot: false, name: `P${i}` })) });
    const flat = new StageRuntime(data, spec.seed);      // shapes read only static geometry
    for (let f = 0; f < spec.frames; f++) {
      for (let k = 0; k < 3; k++) script[`p${k}`] = Object.assign(emptyFrame(), f < 4 ? { anyPress: true } : {});
      m.step(); m.events.length = 0;
      const v = m.stage.visual.disaster;
      if (v && f % 5 === 0) samples.push({ stage: spec.stage, seed: spec.seed, view: str(v), shapes: str(disasterShapes(v, flat)), banner: str(disasterBanner(v)) });
    }
  }
  fs.writeFileSync(path.join(HERE, '../tests/trace-disaster-shapes.json'), JSON.stringify({ samples }));
  console.log(`disaster shapes: ${samples.length} sampled views, ${samples.reduce((t, s) => t + s.shapes.length, 0)} shapes`);
}
