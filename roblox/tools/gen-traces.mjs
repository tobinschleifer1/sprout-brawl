// Record what the JavaScript engine actually does, frame by frame, for the Luau port to reproduce.
//
//     node tools/gen-traces.mjs
//
// A port of a state machine cannot be checked by reading it. This drives the REAL JS classes
// through scripted scenarios and writes every value that matters per frame; tests/trace-parity.luau
// replays the same scenarios through the Luau and compares. Any divergence - a wrong comparison, a
// 0-vs-1 indexing slip, a branch in the wrong order - shows up as the first frame that differs.
//
// EVERY NUMBER IS A STRING. Lune's JSON decoder keeps about 16 significant digits and simulated
// positions routinely need 17, so a decoded fixture would disagree with a port that is exactly
// right. Luau's tonumber parses the decimal back to the same double. (Learned the hard way in
// tools/gen-data.mjs.)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const { StageRuntime } = await import('../../web/src/engine/stage.js');
const { STAGES } = await import('../../web/src/data/stages/index.js');

const n = (v) => String(v);
const nn = (v) => (v == null ? null : String(v));

// Hazards are Phase 2b, so every trace runs on a stage with them stripped - on BOTH sides. Stage
// .luau throws rather than silently skipping a hazard it cannot step, so this is the only way to
// get a trace at all, which is the point.
const stripped = (data) => ({ ...data, hazards: [] });

// A stand-in for Fighter, carrying only the fields StageRuntime.step and collide actually read.
// Phase 2's stage trace must not depend on Fighter, which does not exist in Luau yet.
function probeBody(o = {}) {
  return {
    alive: true, onGround: false, platform: null, dropTimer: 0,
    r: 1.1, h: 5.2, x: 0, y: 0, vy: 0, facing: 1, ledgeCooldown: 0, ledgeGrabs: 0,
    env: { updraft: 0, windX: 0, traction: 1, grip: 1, damp: 1 },
    dropped: 0,
    dropThrough() { this.dropped++; this.onGround = false; this.platform = null; },
    ...o,
  };
}

const platformRow = (p) => [p.id, n(p.x1), n(p.x2), n(p.top), n(p.bottom), n(p.cx), n(p.dx), n(p.dy),
  nn(p.sink), nn(p.occupiedFrames)];

// ---------------------------------------------------------------- geometry ----
// Frame-0 construction for all six stages: platforms, solids, ledges, blast box. This is what the
// constructor produced, and it is where an ordering or ledge-side mistake surfaces.
const geometry = [];
for (const data of STAGES) {
  const st = new StageRuntime(stripped(data));
  geometry.push({
    id: data.id,
    blast: { left: n(st.blast.left), right: n(st.blast.right), top: n(st.blast.top), bottom: n(st.blast.bottom) },
    main: platformRow(st.main),
    platforms: st.platforms.map(platformRow),
    solids: st.solids.map((p) => p.id),
    ledges: st.ledges.map((L) => [n(L.x), n(L.y), n(L.side), L.platform.id]),
  });
}

// ---------------------------------------------------------------- motion ----
// Moving and sinking platforms, stepped for real. Undertow has a sliding raft and two bobbing
// buoys; Smeltworks has the gantry that sinks under anyone who loiters on it - including the
// 120-frame timer that drops them through, which is why the trace runs past 120.
const motion = [];
for (const [stageId, standOn, frames] of [['Undertow', null, 420], ['Smeltworks', 'gantry', 400]]) {
  const data = STAGES.find((s) => s.id === stageId);
  const st = new StageRuntime(stripped(data));
  const body = probeBody();
  if (standOn) {
    const p = st.platforms.find((q) => q.id === standOn);
    body.onGround = true; body.platform = p; body.x = p.cx; body.y = p.top;
  }
  const match = { fighters: [body] };
  const dynamic = st.platforms.filter((p) => p.moving || p.sinking).map((p) => p.id);
  const rows = [];
  const scoop = [];
  for (let i = 0; i < frames; i++) {
    st.step(match);
    rows.push(st.platforms.filter((p) => dynamic.includes(p.id)).map(platformRow));
    // A STATIONARY fighter (vy === 0) sitting just under a platform that is rising into them.
    //
    // This is the case that separates `f.vy <= 0` from `f.vy < 0`, and the only case that reads
    // `prevTop = p.top - p.dy` - a rising platform has to catch a fighter who did not move, using
    // where its surface was last frame. Without these probes, both of those could be broken in the
    // port and the whole trace still passed: every other probe either has a non-zero vy or is
    // falling, and both mutations are invisible in that half of the space.
    for (const p of st.platforms) {
      if (!dynamic.includes(p.id)) continue;
      for (const off of [-0.2, -0.04, 0, 0.3]) {
        const px = p.cx, py = p.top + off;
        const f = probeBody({ x: px, y: py, vy: 0 });
        const r = st.collide(f, px, py, px, py);
        scoop.push([n(i), p.id, n(off), n(r.x), n(r.y), r.landed ? r.landed.id : null, r.wall, r.bumped]);
      }
    }
  }
  motion.push({ id: stageId, standOn, dynamic, frames, time: n(st.time), dropped: body.dropped, rows, scoop });
}

// ---------------------------------------------------------------- queries ----
// collide / supported / ledgeFor / surfaceUnder / nearestLedge over a grid that deliberately
// straddles every edge: ledge lips, platform undersides, soft platforms while dropping through,
// and the moving-solid ejection case.
const queries = [];
for (const data of STAGES) {
  const st = new StageRuntime(stripped(data));
  const collide = [], support = [], ledge = [], surface = [], nearest = [];
  const XS = [-60, -36.5, -36, -20.4, -12, -3, 0, 4.7, 12, 21, 29, 36, 46.2, 61];
  const YS = [-8, 0, 0.4, 4, 11, 13.9, 17, 21, 27, 33];
  for (const px of XS) {
    for (const py of YS) {
      // vy === 0 is in here on purpose. `collide` branches on `f.vy <= 0`, and with only
      // non-zero velocities in the grid, changing that to `<` passed the whole trace.
      for (const [dx, dy, vy, dropTimer] of [[3.1, 0, -4, 0], [-3.1, 0, -4, 0], [0, -6.2, -40, 0],
        [0, -6.2, -40, 6], [0, 5.5, 20, 0], [8.4, -2.2, -12, 0],
        [0, 0, 0, 0], [2.4, 0, 0, 0], [0, -1.2, 0, 0], [0, 1.2, 0, 0]]) {
        const f = probeBody({ x: px, y: py, vy, dropTimer });
        const res = st.collide(f, px, py, px + dx, py + dy);
        collide.push([n(px), n(py), n(dx), n(dy), n(vy), n(dropTimer),
          n(res.x), n(res.y), res.landed ? res.landed.id : null, res.wall, res.bumped]);
      }
      for (const p of st.platforms) {
        const f = probeBody({ x: px, y: py, platform: p });
        support.push([n(px), n(py), p.id, st.supported(f)]);
      }
      for (const facing of [1, -1]) {
        for (const guard of [false, true]) {
          const f = probeBody({ x: px, y: py, vy: -3, facing });
          const L = st.ledgeFor(f, guard);
          ledge.push([n(px), n(py), n(facing), guard, L ? [n(L.x), n(L.y), n(L.side), L.platform.id] : null]);
        }
      }
      const s = st.surfaceUnder(px, py);
      surface.push([n(px), n(py), s ? s.id : null]);
      const near = st.nearestLedge(px, py);
      nearest.push([n(px), n(py), near.ledge ? near.ledge.platform.id + ':' + n(near.ledge.side) : null, n(near.dist)]);
    }
  }
  queries.push({ id: data.id, collide, support, ledge, surface, nearest });
}

// ---------------------------------------------------------------- shrink ----
// Sudden death, run to the floor, so the clamps against the stage geometry are covered.
const shrink = [];
for (const data of STAGES) {
  const st = new StageRuntime(stripped(data));
  const steps = [];
  for (let i = 0; i < 8; i++) {
    st.shrink(0.8);
    steps.push([n(st.blast.left), n(st.blast.right), n(st.blast.top), n(st.blast.bottom)]);
  }
  // and outsideBlast either side of every wall
  const out = [];
  for (const [x, y] of [[0, 0], [-200, 0], [200, 0], [0, 400], [0, -400], [-60, 20], [60, 20]]) {
    out.push([n(x), n(y), st.outsideBlast({ x, y, h: 5.2 })]);
  }
  shrink.push({ id: data.id, steps, out });
}

// ---------------------------------------------------------------- moving solid ----
// No stage in the roster has a moving SOLID - every mover is a soft platform - so collide's
// "a solid drove into a fighter who never moved into it" ejection branch is unreachable from real
// data, and deleting it from the Luau passed the entire trace. It is legitimate defensive code for
// a stage type that could exist, so rather than drop it, it gets a synthetic stage.
//
// The stage definition travels IN the trace so both sides build from one description rather than
// from two literals that can drift apart.
const syntheticData = {
  id: 'SyntheticMover',
  main: { x1: -30, x2: 30, y: 0, thickness: 6 },
  platforms: [
    { id: 'slider', x: 0, y: 8, w: 12, solid: true, thickness: 4,
      moving: { x: { from: -14, to: 14, period: 2.5, phase: 0 } } },
  ],
  blast: { left: -80, right: 80, top: 60, bottom: -40 },
  hazards: [],
};
const mover = [];
{
  const st = new StageRuntime(syntheticData);
  const match = { fighters: [probeBody()] };
  for (let frame = 0; frame < 90; frame++) {
    st.step(match);
    const sl = st.platforms.find((p) => p.id === 'slider');
    const probes = [];
    // Positions spread across and just outside the slider, so the ejection picks both faces.
    for (const px of [-16, -8, -3, 0, 3, 8, 16]) {
      for (const py of [5, 8, 10]) {
        const f = probeBody({ x: px, y: py, vy: 0 });
        const r = st.collide(f, px, py, px, py);
        probes.push([n(px), n(py), n(r.x), n(r.y), r.landed ? r.landed.id : null, r.wall, r.bumped]);
      }
    }
    mover.push({ slider: platformRow(sl), probes });
  }
}

const out = { geometry, motion, queries, shrink, syntheticData, mover };
fs.writeFileSync(path.join(HERE, '../tests/trace-stage.json'), JSON.stringify(out));
const count = (a) => a.reduce((s, q) => s + q.collide.length + q.support.length + q.ledge.length + q.surface.length + q.nearest.length, 0);
console.log(`stage traces: ${geometry.length} stages of geometry, ${mover.length} moving-solid frames, `
  + `${motion.reduce((s, m) => s + m.rows.length, 0)} motion frames, `
  + `${count(queries)} query probes, ${shrink.length * 8} shrink steps`);
