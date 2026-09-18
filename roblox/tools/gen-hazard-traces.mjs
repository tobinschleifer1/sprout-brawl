// Record what the JavaScript hazards do to real fighters, frame by frame.
//
//     node tools/gen-hazard-traces.mjs
//
// Hazards are pure force: they write to each fighter's `env` bag and occasionally call hazardHit.
// So what gets recorded is every fighter's env every frame, their positions, and the whole visual
// bag flattened to numbers - plus the hazardHit log, because a hazard that damages the right
// person on the wrong frame is not a correct port.
//
// Two of the four fighters are PINNED probes, teleported along a path each frame so they sweep the
// hazard volume instead of standing wherever physics leaves them. The path is a function of the
// frame number, so both sides follow it identically without it having to be recorded.
//
// Numbers are strings. See tools/gen-traces.mjs.
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

// combat.hazardHit, copied from web/src/engine/combat.js. The real Combat is Phase 3, but this is
// four lines and stubbing it to a no-op would leave the three damaging hazards untested.
function stubCombat(log) {
  const sign = (v) => (v < 0 ? -1 : 1);
  return {
    hazardHit(f, p) {
      if (f.untouchable) return;
      const facing = sign(f.x - p.x || 1);
      f.applyHit({ damage: p.damage, launch: p.launch, angle: p.angle, facing, attacker: null, hitlag: 6 });
      log.push(`${f.index}:${n(p.damage)}:${n(p.launch)}:${n(p.angle)}`);
    },
  };
}

// The visual bag, flattened to a sorted list of [path, value] so every number is compared as a
// number. Joining it into a string would compare it as text and skip the tolerance that
// Math.sin drift needs - the mistake the fighter trace already made once with the hurtbox.
function flatten(v, p, out) {
  if (v === null || v === undefined) return out;
  if (Array.isArray(v)) { v.forEach((x, i) => flatten(x, `${p}[${i}]`, out)); return out; }
  if (typeof v === 'object') {
    for (const k of Object.keys(v).sort()) flatten(v[k], `${p}.${k}`, out);
    return out;
  }
  out.push([p, n(v)]);
  return out;
}

// Where the two sweeping probes are on a given frame - a pure function of the frame, so both sides
// reproduce it without it being recorded.
function sweepAt(stage, i, frame) {
  const m = stage.main;
  const span = m.x2 - m.x1;
  const t = ((frame * 0.013) + i * 0.37) % 1;
  return { x: m.x1 + span * t, y: m.top + (i === 0 ? 1.0 : 16.0) };
}

// Points worth standing on, derived from each hazard's OWN coordinates.
//
// Sweeping the stage found the hazards that cover ground and missed the ones that do not: across
// 7,700 frames the first version triggered two hazard hits in total, so slagfall, the antenna arc
// and the dust devil's throw were all untested. These park a probe where each hazard actually is.
// Recorded in the trace rather than recomputed, so the two sides cannot disagree about the order.
function probePoints(data, stage) {
  const m = stage.main;
  const pts = [];
  for (const h of data.hazards) {
    if (h.type === 'vents') for (const px of h.positions) pts.push([px, m.top + 1]);
    else if (h.type === 'slagfall') pts.push([h.x, m.top + 1], [h.x + h.spread / 3, m.top + 1]);
    else if (h.type === 'sprinkler') pts.push([m.cx, m.top + 1], [m.x1 + 6, m.top + 1]);
    else if (h.type === 'antennaarc') pts.push([(h.x1 + h.x2) / 2, h.y], [h.x1 + 2, h.y - h.thickness / 2]);
    else if (h.type === 'dustdevil') pts.push([m.cx, m.top + 1], [m.cx + 6, m.top + 4]);
    else if (h.type === 'sandfall') pts.push([h.x, (h.from + h.to) / 2], [h.x, h.to + 2]);
    else if (h.type === 'tide') pts.push([h.edge + 6, h.low + 1], [h.edge + 10, h.low - 3]);
    else if (h.type === 'roguewave') pts.push([m.cx, h.crest], [m.x1 - 5, h.crest - 2]);
    else if (h.type === 'crosswind') pts.push([m.cx, m.top + 12]);
    else if (h.type === 'emberdrift') for (const px of h.positions) pts.push([px, (h.from + h.to) / 2]);
  }
  return pts;
}

const scenarios = [];
for (const data of STAGES) {
  if (!data.hazards || data.hazards.length === 0) continue;
  // Long enough to cover the slowest cycle in the roster: Undertow's tide runs 34 seconds.
  const frames = data.id === 'Undertow' ? 2200 : 1100;
  const stage = new StageRuntime(data, 12345);
  const hitLog = [];
  const combat = stubCombat(hitLog);
  const chars = [['Classic', 'Sword'], ['Noir', 'Pike'], ['Ember', 'Hammer'], ['Moss', 'Daggers'],
    ['Vapor', 'Longbow']];
  const fighters = chars.map(([a, w], i) => {
    const f = new Fighter({ index: i, char: buildLoadout(a, w), x: data.spawns[i % data.spawns.length], y: 2, stocks: 99, name: `P${i}` });
    f.setState('idle'); f.invincible = 0;
    return f;
  });
  const match = { fighters, frame: 0, combat };
  const ctx = { stage, combat, fighters };
  const points = probePoints(data, stage);
  // A fifth probe that does NOT move: it sits in the damaging hazard for the whole run, so a
  // fighter is hit repeatedly and the per-fighter cooldown is actually exercised. With everything
  // cycling every 45 frames, nobody was ever hit twice inside the antenna arc's 30-frame cooldown
  // and shortening it to 20 passed the entire trace.
  const DAMAGING = ['antennaarc', 'slagfall', 'dustdevil'];
  const damaging = data.hazards.find((h) => DAMAGING.includes(h.type));
  const hold = damaging
    ? (damaging.type === 'antennaarc' ? [(damaging.x1 + damaging.x2) / 2, damaging.y]
      : damaging.type === 'slagfall' ? [damaging.x, stage.main.top + 1]
      : [stage.main.cx, stage.main.top + 1])
    : (points[0] || [stage.main.cx, stage.main.top + 1]);
  const rows = [];
  for (let frame = 0; frame < frames; frame++) {
    match.frame = frame;
    // Pin all four probes before hazards run, so they sample the field where they are put.
    // 0 and 1 sweep the stage; 2 and 3 sit on the hazards' own coordinates, changing every 45
    // frames so a full cycle of each hazard is seen from the place it acts.
    for (let i = 0; i < 5; i++) {
      const f = fighters[i];
      let at;
      if (i === 4) at = { x: hold[0], y: hold[1] };
      else if (i < 2) at = sweepAt(stage, i, frame);
      else if (points.length) {
        const p = points[(Math.floor(frame / 45) + (i - 2) * 3) % points.length];
        at = { x: p[0], y: p[1] + (i === 3 ? 3 : 0) };
      } else at = sweepAt(stage, i - 2, frame);
      f.x = at.x; f.y = at.y; f.vx = 0; f.vy = 0;
      f.onGround = i % 2 === 0; f.platform = i % 2 === 0 ? stage.main : null;
      f.percent = 0; f.hitstun = 0; f.hitlag = 0; f.tumbling = false;
      f.setState(i % 2 === 0 ? 'idle' : 'air');
    }
    stage.step(match);
    for (const f of fighters) { f.events.length = 0; f.applyInput(emptyFrame()); f.step(ctx); }
    const row = [];
    for (const f of fighters) {
      row.push(n(f.env.updraft), n(f.env.windX), n(f.env.traction), n(f.env.grip), n(f.env.damp),
        f.inWater, n(f.x), n(f.y), n(f.vx), n(f.vy), n(f.percent), f.state, f.onGround);
    }
    row.push(stage.waterLevel === null || stage.waterLevel === undefined ? null : n(stage.waterLevel));
    rows.push(row);
    // the whole visual bag, every 10th frame: it is large, and a hazard that is wrong is wrong for
    // far longer than ten frames
    if (frame % 10 === 0) rows[rows.length - 1].push(flatten(stage.visual, '', []));
    else rows[rows.length - 1].push(null);
  }
  scenarios.push({ id: data.id, frames, seed: 12345, points: points.map((p) => [n(p[0]), n(p[1])]),
    hold: [n(hold[0]), n(hold[1])],
    hazards: data.hazards.map((h) => h.type), rows, hitLog });
}

fs.writeFileSync(path.join(HERE, '../tests/trace-hazard.json'), JSON.stringify({ scenarios }));
const total = scenarios.reduce((s, x) => s + x.frames, 0);
console.log(`hazard traces: ${scenarios.length} stages, ${total} frames, `
  + `${scenarios.reduce((s, x) => s + x.hitLog.length, 0)} hazard hits`);
