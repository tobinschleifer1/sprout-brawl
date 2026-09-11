// Stage hazards: do they do what they claim, and do they obey the rules that keep them fair?
//
// The design rules being enforced here, all of them measured by running the engine rather than
// read off the data:
//
//   1. PRESSURE, NOT EXECUTION. No hazard may KO a fighter sitting on the stage at 0%.
//   2. NEVER A RESCUE. A hazard may not keep a launched fighter alive. This one has teeth: the
//      first build of the dust devil caught everyone blown off the left of Saltflat and matches
//      stopped resolving at all.
//   3. EVERY HAZARD TELEGRAPHS. There is a warning phase, it is visible to the renderer, and it
//      lasts long enough to react to.
//   4. RANKED STAGES ONLY PUSH. Checked in stages.test.mjs from the data; checked here from
//      behaviour, by running both ranked stages and asserting nobody ever takes damage.
//   5. FORCE IS BOUNDED. No stack of hazards can out-accelerate gravity.
import { makeMatch, skipCountdown } from './harness.mjs';
import { STAGES } from '../src/data/stages/index.js';
import { HAZARDS } from '../src/engine/hazards.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };

function stage(id, opts = {}) {
  const m = makeMatch({ stageId: id, loadouts: [['Classic', 'Sword'], ['Noir', 'Sword']], ...opts });
  skipCountdown(m);
  return m;
}
const plant = (m, f, x, y = 0) => {
  f.x = x; f.y = y; f.vx = 0; f.vy = 0;
  f.onGround = y === 0; f.platform = y === 0 ? m.stage.main : null;
  f.setState(y === 0 ? 'idle' : 'air'); f.invincible = 0;
};

// ---- 1. every declared hazard type is implemented, and every implementation is used ----
{
  const declared = new Set(STAGES.flatMap((d) => d.hazards.map((h) => h.type)));
  const built = new Set(Object.keys(HAZARDS));
  const missing = [...declared].filter((t) => !built.has(t));
  const unused = [...built].filter((t) => !declared.has(t));
  check('every hazard a stage declares is implemented, and none is dead code',
    missing.length === 0 && unused.length === 0,
    missing.length ? `no implementation for: ${missing.join(', ')}`
      : unused.length ? `implemented but on no stage: ${unused.join(', ')}`
      : `${built.size} types, all in use: ${[...built].sort().join(', ')}`);
}

// ---- 2. PRESSURE, NOT EXECUTION: standing still at 0% on any stage never kills you ----
// A fighter is planted in the worst place on each stage — right on a vent, under the sandfall,
// in the funnel's path — and left there with no inputs for two full hazard cycles.
{
  // Every spot here is on SOLID GROUND and directly under something: on a vent grate, beneath
  // the slag drip, in the funnel's path, under the sandfall's shadow. The first version of this
  // list had three coordinates that were over open air (x=41 on Foundry is outside a stage that
  // ends at 36), so it was measuring gravity and calling it a hazard.
  const SPOTS = {
    FoundryFloor: [0, -30, 30],          // the ember columns are off-stage; the floor is all there is
    TheSpan: [0, -40, 40],               // the whole span is solid
    Smeltworks: [-20, 20, -30],          // both vent grates, plus the west island under the gantry
    Rooftops: [0, -20, 20],              // the roof, under the sprinkler's full sweep
    Saltflat: [0, -40, 20],              // the flat, under the mesa's shadow at 20
    Undertow: [0, -14, 14],              // the raft deck at every tide level
  };
  const dead = [];
  for (const d of STAGES) {
    for (const x of SPOTS[d.id]) {
      const m = stage(d.id);
      const [f, other] = m.fighters;
      plant(m, other, d.main.x1 + 3);
      let survived = true;
      for (let i = 0; i < 60 * 45; i++) {
        if (f.onGround) plant(m, f, x);            // keep re-planting: we are testing the hazard, not movement
        m.step(); m.events.length = 0;
        if (!f.alive || f.stocks < 3) { survived = false; break; }
      }
      if (!survived) dead.push(`${d.name} @ x=${x}`);
    }
  }
  check('no hazard kills a fighter standing at 0%', dead.length === 0,
    dead.length ? `KOd by the stage alone: ${dead.join(', ')}`
      : `18 spots across 6 stages, 45 seconds each, nobody died to the weather`);
}

// ---- 3. NEVER A RESCUE: a launched fighter is not caught by the weather ----
// Launch someone hard off the side on every stage and confirm they still cross the blast zone.
// This is the regression test for the bug that made Saltflat matches unfinishable.
{
  const saved = [];
  for (const d of STAGES) {
    const m = stage(d.id);
    const [f] = m.fighters;
    f.x = d.main.x1 + 2; f.y = 6; f.onGround = false; f.platform = null;
    f.percent = 140; f.invincible = 0;
    // angle is measured from horizontal IN THE FACING DIRECTION, so 168 with facing -1 launches
    // to the RIGHT — which on Saltflat threw the fighter into the mesa wall, bounced them back
    // onto the floor, and looked exactly like a hazard rescue. 15 with facing -1 goes left and
    // shallow, which is the off-the-side kill this test is actually about.
    f.applyHit({ damage: 12, launch: 210, angle: 15, facing: -1, attacker: m.fighters[1], hitlag: 0 });
    let died = false;
    for (let i = 0; i < 60 * 12; i++) { m.step(); m.events.length = 0; if (f.stocks < 3 || !f.alive) { died = true; break; } }
    if (!died) saved.push(`${d.name} (ended x=${f.x.toFixed(0)} y=${f.y.toFixed(0)})`);
  }
  check('the weather never saves a fighter from a kill', saved.length === 0,
    saved.length ? `survived a 210-launch at 140%: ${saved.join(', ')}`
      : 'a hard launch crosses the blast zone on all six stages — hazards cannot cancel a KO');
}

// ---- 4. EVERY HAZARD TELEGRAPHS, and the warning is long enough to act on ----
// A warning that lasts three frames is decoration. The floor is 24 frames: enough to see it,
// decide, and move. Measured by watching the visual the engine hands the renderer.
{
  const MIN_WARN = 24;
  const rows = [], bad = [];
  for (const d of STAGES) {
    if (!d.hazards.length) continue;
    const m = stage(d.id);
    m.fighters.forEach((f) => plant(m, f, 0));
    const warnFrames = new Map();
    const runs = new Map();
    for (let i = 0; i < 60 * 80; i++) {
      m.step(); m.events.length = 0;
      const v = m.stage.visual || {};
      for (const key of Object.keys(HAZARDS)) if (!v[key]) runs.set(key, 0);
      for (const key of Object.keys(HAZARDS)) {
        const hv = v[key];
        if (!hv) continue;
        const warning = hv.phase === 'warn' || hv.warn === true || hv.phase === 'rising';
        // The LONGEST UNBROKEN run, not the total. Summing across eighty seconds measured the
        // wrong thing entirely: a hazard warning for three frames on a one-second period would
        // total 240 and sail past a 24-frame bar. What a player gets is one warning, once, and
        // its length is the only number that matters.
        if (warning) {
          const run = (runs.get(key) || 0) + 1;
          runs.set(key, run);
          warnFrames.set(key, Math.max(warnFrames.get(key) || 0, run));
        } else runs.set(key, 0);
      }
    }
    for (const h of d.hazards) {
      // Three are not events with a wind-up, and a phase-based warning would be meaningless:
      //   emberdrift  never changes at all — it is a fixed piece of the layout
      //   tide        its warning IS watching the water climb, checked separately below
      //   slagfall    each drop telegraphs itself by falling; measured as fall time below
      if (h.type === 'emberdrift' || h.type === 'slagfall') continue;
      const got = warnFrames.get(h.type) || 0;
      rows.push(`${h.type} ${got}f`);
      if (got < MIN_WARN) bad.push(`${d.name}/${h.type} warned for only ${got} frames`);
    }
  }
  check('every hazard telegraphs for at least 24 consecutive frames', bad.length === 0,
    bad.length ? bad.join('; ') : `longest unbroken warning: ${rows.join(', ')}`);
}

// ---- 5. RANKED STAGES ONLY PUSH ----
{
  const hurt = [];
  for (const d of STAGES.filter((x) => x.ranked)) {
    const m = stage(d.id);
    const [f, other] = m.fighters;
    plant(m, other, d.main.x2 - 3);
    let worst = 0;
    for (let i = 0; i < 60 * 60; i++) {
      // ride the air just off the ledge, where a ranked stage's weather actually lives
      f.x = d.main.x1 - 4; f.y = 4; f.onGround = false; f.platform = null; f.setState('air'); f.invincible = 0;
      m.step(); m.events.length = 0;
      worst = Math.max(worst, f.percent);
    }
    if (worst > 0) hurt.push(`${d.name} dealt ${worst}%`);
  }
  check('a ranked stage never deals damage', hurt.length === 0,
    hurt.length ? hurt.join(', ') : 'Foundry Floor and The Span pushed for 60 seconds and dealt 0%');
}

// ---- 6. FORCE IS BOUNDED: no hazard out-accelerates gravity ----
// Measured as terminal behaviour: park a fighter in the strongest lift in the game (a vent at
// full strength) and check they rise but do not accelerate away.
{
  const m = stage('Smeltworks');
  const [f] = m.fighters;
  let peakVy = 0, peakY = 0;
  for (let i = 0; i < 60 * 30; i++) {
    if (f.y < -20) plant(m, f, -20);
    f.x = -20;
    m.step(); m.events.length = 0;
    peakVy = Math.max(peakVy, f.vy);
    peakY = Math.max(peakY, f.y);
  }
  // The vent's reach is 26 studs; a fighter should be lifted well up it and no further.
  check('the strongest updraft lifts but does not fling', peakVy < 90 && peakY < 60,
    `30s parked on a vent: peak rise ${peakVy.toFixed(0)} studs/s, peak height ${peakY.toFixed(0)} studs (blast top is ${m.stage.blast.top})`);
}

// ---- 7. the slick outlives the jet that made it ----
// The sprinkler's whole point is that it changes the roof for ten seconds after the water stops.
{
  const m = stage('Rooftops');
  m.fighters.forEach((f) => plant(m, f, 0));
  let sawJet = false, wetAfterJet = 0, maxWet = 0;
  for (let i = 0; i < 60 * 40; i++) {
    m.step(); m.events.length = 0;
    const sp = (m.stage.visual || {}).sprinkler;
    if (!sp) continue;
    maxWet = Math.max(maxWet, sp.wet.length);
    if (sp.phase === 'active') sawJet = true;
    else if (sawJet && sp.wet.length) wetAfterJet++;
  }
  check('the sprinkler leaves the roof wet long after it stops', sawJet && wetAfterJet > 120 && maxWet > 4,
    `jet ran, then ${maxWet} slick patches persisted for ${wetAfterJet} frames (${(wetAfterJet / 60).toFixed(1)}s) with no water in the air`);
}

// ---- 8. the dust devil carries rather than bumps ----
// The old one hit you once for 7% and moved on. The new one should hold a fighter for a while
// and move them a meaningful distance before throwing them out.
{
  const m = stage('Saltflat');
  const [f] = m.fighters;
  plant(m, m.fighters[1], -40);
  let held = 0, lifted = 0, startX = null, travelled = 0;
  for (let i = 0; i < 60 * 25; i++) {
    m.step(); m.events.length = 0;
    const dd = (m.stage.visual || {}).dustdevil;
    if (!dd || !dd.active) continue;
    if (startX === null) { plant(m, f, dd.x); startX = f.x; }
    if (Math.abs(f.x - dd.x) < 7) { held++; lifted = Math.max(lifted, f.y); travelled = Math.abs(f.x - startX); }
  }
  check('the dust devil carries a fighter instead of bumping them', held > 40 && lifted > 6,
    `held for ${held} frames, lifted to ${lifted.toFixed(1)} studs, dragged ${travelled.toFixed(0)} studs along the flat`);
}

// ---- 9. water damps knockback, so the tide is a refuge as well as a trap ----
{
  const run = (inWater) => {
    const m = stage('Undertow');
    const [f, a] = m.fighters;
    // wait for high tide so there is water to be in
    for (let i = 0; i < 60 * 40; i++) {
      m.step(); m.events.length = 0;
      const tv = (m.stage.visual || {}).tide;
      if (tv && tv.phase === 'high') break;
    }
    const lvl = m.stage.waterLevel;
    f.x = inWater ? 34 : 0; f.y = inWater ? lvl - 3 : 0;
    f.onGround = !inWater; f.platform = inWater ? null : m.stage.main;
    f.setState(inWater ? 'air' : 'idle'); f.percent = 90; f.invincible = 0;
    plant(m, a, inWater ? 30 : -4);
    m.step();                                        // let the tide flag f.inWater
    f.applyHit({ damage: 12, launch: 150, angle: 45, facing: 1, attacker: a, hitlag: 0 });
    return Math.hypot(f.vx, f.vy);
  };
  const dry = run(false), wet = run(true);
  check('water damps knockback', wet < dry * 0.8,
    `the same hit launches at ${dry.toFixed(0)} on land and ${wet.toFixed(0)} in the sea (${((1 - wet / dry) * 100).toFixed(0)}% softer)`);
}


// ---- 10. the waterline is actually visible against its own sky ----
// The first tide painted #3D7A95 at 0.42 alpha over a sky that bottoms out at #33566E. The water
// as drawn came out four, fifteen and sixteen units from the sky per channel — and LIGHTER than
// it, which reads as haze rather than sea. The most important thing to read on Undertow was
// invisible. Contrast on this one element is a correctness property, so it is pinned.
{
  const { TIDE_RAMP } = await import('../src/render2d/hazards2d.js');
  const hex = (c) => [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16));
  const lum = (c) => { const [r, g, b] = hex(c); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
  const bad = [];
  const rows = [];
  for (const d of STAGES) {
    if (!d.hazards.some((h) => h.type === 'tide')) continue;
    // the darkest sky stop is the one sitting behind the water at the horizon
    const darkestSky = d.palette.skyStops.reduce((a, s) => (lum(s[1]) < lum(a) ? s[1] : a), d.palette.skyStops[0][1]);
    const skyL = lum(darkestSky);
    const deepL = lum(TIDE_RAMP.deep), crestL = lum(TIDE_RAMP.underCrest), foamL = lum(TIDE_RAMP.foam);
    rows.push(`${d.name}: sky ${skyL.toFixed(0)} / deep ${deepL.toFixed(0)} / under-crest ${crestL.toFixed(0)} / foam ${foamL.toFixed(0)}`);
    // water must be clearly DARKER than the sky, and the foam clearly brighter than both
    if (deepL > skyL - 25) bad.push(`${d.name}: deep water (${deepL.toFixed(0)}) is not 25 darker than its sky (${skyL.toFixed(0)})`);
    if (crestL > deepL) bad.push(`${d.name}: the under-crest band is not the darkest part of the water`);
    if (foamL - skyL < 90) bad.push(`${d.name}: foam (${foamL.toFixed(0)}) does not read against the sky (${skyL.toFixed(0)})`);
  }
  check('the waterline reads against its own sky', bad.length === 0,
    bad.length ? bad.join('; ') : `${rows.join(' | ')} — water darker than sky, foam far brighter`);
}


// ---- 11. two hazards on one stage must not occupy the same ground ----
// Depth is two hazards a player can tell apart. Two acting on the same patch of air is noise:
// caught there, you cannot tell which one is moving you or which warning to read.
//
// Each hazard is measured IN ISOLATION — the stage is rebuilt carrying only that one — because
// attributing an effect to whichever hazard happened to be active credits both with everything
// and measures nothing.
//
// The box covers FORCE and DAMAGE. An earlier version measured force alone, which meant the two
// damage-only hazards (slagfall, antennaarc) had no box at all and three of the four multi-hazard
// stages were compared against nothing. Worse, the comment here asserted that the sprinkler and
// the arc "sit ten studs apart vertically, and that is fine" — a number that was never computed.
// It happens to be true (11.8 studs) and it was still a claim the test did not make.
{
  const { Match } = await import('../src/engine/match.js');
  const { buildLoadout } = await import('../src/data/loadout.js');
  const soloStage = (d, type) => ({ ...d, hazards: d.hazards.filter((h) => h.type === type).map((h) => ({ ...h, state: undefined })) });

  function footprint(d, type) {
    const fighters = [['Classic', 'Sword'], ['Noir', 'Sword']].map(([a, w], i) => {
      const L = buildLoadout(a, w);
      return { char: L, skin: 0, team: i, source: 'p' + i, isBot: false, name: L.weapon.id };
    });
    const m = new Match({ mode: 'StockFFA', stocks: 9, timeLimit: 0, items: false,
      input: { kb2Active: false, poll() {}, get: () => ({ x: 0, y: 0 }) },
      stage: soloStage(d, type), fighters });
    while (m.state === 'countdown') m.step();
    const [f, other] = m.fighters;
    other.x = d.main.x1 + 2; other.y = 0; other.onGround = true; other.platform = m.stage.main;
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    const W = d.main.x2 - d.main.x1 + 30, H = 52;
    let lastPct = 0;
    for (let i = 0; i < 60 * 110; i++) {
      f.x = d.main.x1 - 15 + ((i * 1.7) % W);
      f.y = -6 + ((i * 0.37) % H);
      f.vx = 0; f.vy = 0; f.onGround = false; f.platform = null; f.setState('air');
      f.invincible = 0; f.percent = 0; lastPct = 0;
      m.step(); m.events.length = 0;
      const forced = Math.abs(f.env.updraft) > 1 || Math.abs(f.env.windX) > 1;
      const hurt = f.percent > lastPct;               // damage hazards get a box too
      if (!forced && !hurt) continue;
      x0 = Math.min(x0, f.x); x1 = Math.max(x1, f.x);
      y0 = Math.min(y0, f.y); y1 = Math.max(y1, f.y);
    }
    return x0 === Infinity ? null : { x0, x1, y0, y1 };
  }

  const bad = [], rows = [];
  for (const d of STAGES) {
    if (d.hazards.length < 2) continue;
    const boxes = d.hazards.map((h) => ({ type: h.type, box: footprint(d, h.type) })).filter((e) => e.box);
    rows.push(`${d.name}: ${boxes.map((e) => `${e.type} x${e.box.x0.toFixed(0)}..${e.box.x1.toFixed(0)} y${e.box.y0.toFixed(0)}..${e.box.y1.toFixed(0)}`).join(', ')}`);
    if (boxes.length < d.hazards.length) bad.push(`${d.name}: only ${boxes.length} of ${d.hazards.length} hazards produced a measurable footprint — a hazard that does nothing is not separated from anything`);
    for (let i = 0; i < boxes.length; i++) for (let j = i + 1; j < boxes.length; j++) {
      const A = boxes[i], B = boxes[j];
      // Tide and rogue wave are deliberately the same body of water; they may share.
      const paired = [A.type, B.type].sort().join('+') === 'roguewave+tide';
      const ox = Math.min(A.box.x1, B.box.x1) - Math.max(A.box.x0, B.box.x0);
      const oy = Math.min(A.box.y1, B.box.y1) - Math.max(A.box.y0, B.box.y0);
      if (ox > 5 && oy > 5 && !paired) bad.push(`${d.name}: ${A.type} and ${B.type} overlap by ${ox.toFixed(0)}x${oy.toFixed(0)} studs`);
    }
  }
  check('no two hazards fight over the same ground', bad.length === 0,
    bad.length ? bad.join('; ') : rows.join('  |  '));
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
