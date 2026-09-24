// Natural disasters: does each one keep the contract written at the top of engine/disasters.js?
// Everything is measured by running the engine with fighters placed where the disaster must hit -
// a fairness test that passes because the disaster missed everyone would be asserting nothing, so
// every section also asserts that the disaster DID land when it should.
import { makeMatch, skipCountdown } from './harness.mjs';
import { DISASTERS, FIRST_AT, GAP, MIN_WARN } from '../src/engine/disasters.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };

const HOME = { lavasurge: 'Smeltworks', lightning: 'Rooftops', tornado: 'Saltflat', tsunami: 'Undertow', earthquake: 'Saltflat', meteor: 'FoundryFloor' };

function setup(type, opts = {}) {
  const m = makeMatch({ stageId: opts.stageId || HOME[type], disasters: 'chaos', forceDisaster: type, seed: opts.seed ?? 7 });
  skipCountdown(m);
  const [a, b] = m.fighters;
  b.invincible = 1e9;                                   // the bystander never interferes
  plant(m, b, m.stage.solids[0].x1 + 2, m.stage.solids[0].top);
  m.stage.director.next = 0;                            // start the disaster now, not in 45 s
  return { m, a, b };
}
function plant(m, f, x, y = null) {
  const surf = y === null ? m.stage.surfaceUnder(x, 999) : m.stage.surfaceUnder(x, y + 0.01);
  f.x = x; f.y = surf ? surf.top : y ?? 0; f.vx = 0; f.vy = 0;
  f.onGround = !!surf; f.platform = surf || null;
  f.setState(surf ? 'idle' : 'air'); f.invincible = 0;
}
// Run one whole disaster. `place(ctx)` runs on the first frame the event exists (after its random
// choices are made), so a fighter can be put exactly where a strike will land. `each` runs every frame.
function runEvent(m, { place, each } = {}) {
  const hits = [], kos = [];
  let start = null, frame = 0, placed = false;
  const stocks = m.fighters.map((f) => f.stocks);
  for (let i = 0; i < 60 * 30; i++) {
    const had = !!m.stage.director.active;
    if (!had && start !== null) break;
    m.step();
    const act = m.stage.director.active;
    if (act && start === null) start = m.frame;
    if (act && !placed && place) { place(act); placed = true; }
    if (each) each(act);
    for (const e of m.events) {
      if (e.disaster && e.type === 'hit') hits.push({ at: m.frame - start, victim: e.victim, damage: e.damage });
      if (e.disaster && e.type === 'chip') hits.push({ at: m.frame - start, victim: e.victim, damage: e.damage, chip: true });
      if (e.disaster && e.type === 'block') hits.push({ at: m.frame - start, victim: e.victim, damage: 0, blocked: true });
      if (e.type === 'ko') kos.push(e.fighter ?? e.victim);
    }
    m.events.length = 0;
    frame++;
  }
  return { hits, kos, lostStock: m.fighters.map((f, i) => f.stocks < stocks[i]) };
}

// Where to put the victim so that each disaster is guaranteed to reach them.
// Floor-level victims are planted at y 0 explicitly: plant(x) alone picks the HIGHEST surface over
// x, which at -22 on Smeltworks is the west shelf and at 0 on Undertow is the gull - exactly the
// safe spots, where these disasters rightly never reach.
const IN_HARM = {
  lavasurge: (m, a) => plant(m, a, -22, 0),
  lightning: (m, a) => (act) => plant(m, a, act.strikes[0].x),
  tornado: (m, a) => plant(m, a, 0, 0),
  tsunami: (m, a) => plant(m, a, 0, 0),
  earthquake: (m, a) => (act) => plant(m, a, act.plates.length ? (act.plates[0].x1 + act.plates[0].x2) / 2 : 0),
  meteor: (m, a) => (act) => plant(m, a, act.rocks[0].x),
};
function inHarm(type, m, a) { const r = IN_HARM[type](m, a); return typeof r === 'function' ? r : null; }

// ---- 1. off by default, and the six are all real ----
{
  const m = makeMatch({ stageId: 'Smeltworks' });
  skipCountdown(m);
  let events = 0;
  for (let i = 0; i < 60 * 120; i++) { m.step(); events += m.events.filter((e) => e.type === 'disaster' || e.disaster).length; m.events.length = 0; }
  check('disasters are OFF unless a match asks for them', m.stage.director === null && events === 0,
    `two minutes on Smeltworks with no disaster mode: director ${m.stage.director}, ${events} disaster events`);
  check('six disasters, each with a warning of at least 90 frames', Object.keys(DISASTERS).length === 6
    && Object.values(DISASTERS).every((d) => d.warn >= MIN_WARN),
    Object.entries(DISASTERS).map(([k, d]) => `${k} ${d.warn}f`).join(' · '));
}

// ---- 2. each disaster lands, and never inside its warning ----
for (const type of Object.keys(DISASTERS)) {
  const { m, a } = setup(type);
  const late = inHarm(type, m, a);
  const r = runEvent(m, { place: late });
  const onVictim = r.hits.filter((h) => h.victim === a.index);
  const first = Math.min(...r.hits.map((h) => h.at));
  check(`${type}: lands on a fighter in harm's way, and not before ${MIN_WARN} frames of warning`,
    onVictim.length > 0 && first >= MIN_WARN,
    `${onVictim.length} hits on the victim; first contact at frame ${first} of the event`);
}

// ---- 3. no KO below 140% ----
for (const type of Object.keys(DISASTERS)) {
  const deaths = [];
  for (const pct of [0, 40, 80, 110, 139]) {
    const { m, a } = setup(type, { seed: 11 });
    a.percent = pct;
    const late = inHarm(type, m, a);
    const r = runEvent(m, { place: late });
    if (r.lostStock[a.index]) deaths.push(pct);
  }
  check(`${type}: cannot take a stock from a fighter below 140%`, deaths.length === 0,
    deaths.length ? `KO'd a fighter who started at ${deaths.join(', ')}%` : 'survived from 0, 40, 80, 110 and 139% standing still in the danger zone');
}

// ---- 4. somewhere safe to stand ----
const SAFE = {
  lavasurge: ['the west shelf, one jump up', (m, a) => plant(m, a, -27, 13)],
  tornado: ['the mesa top, above the funnel', (m, a) => plant(m, a, 38, 17)],
  tsunami: ['the gull, above the crest', (m, a) => plant(m, a, 0, 27)],
  meteor: ['away from every shadow', null],
};
for (const [type, [where, put]] of Object.entries(SAFE)) {
  const { m, a } = setup(type);
  let place = null;
  if (put) put(m, a);
  else place = (act) => {
    // the point on the floor furthest from every rock
    let best = 0, bx = 0;
    for (let x = m.stage.main.x1 + 2; x <= m.stage.main.x2 - 2; x += 0.5) {
      const d = Math.min(...act.rocks.map((rk) => Math.abs(rk.x - x)));
      if (d > best) { best = d; bx = x; }
    }
    plant(m, a, bx);
  };
  // hold position: a safe spot only counts if you stay in it, so the victim is re-pinned if pushed
  const p0 = put ? { x: a.x, y: a.y } : null;
  const r = runEvent(m, { place, each: () => { if (p0 && a.onGround && Math.abs(a.x - p0.x) > 1) { a.x = p0.x; } } });
  const dmg = r.hits.filter((h) => h.victim === a.index).reduce((t, h) => t + h.damage, 0);
  check(`${type}: standing on ${where} takes nothing`, dmg === 0, `${dmg}% taken`);
}

// ---- 5. the timing answers ----
{ // shield the bolt - on Foundry Floor, which has no rods to stack strikes on one spot
  const { m, a } = setup('lightning', { stageId: 'FoundryFloor' });
  // A bolt that lands on its own. Strikes near a lightning rod snap onto it, so standing on a rod
  // means blocking several bolts in a row until the shield breaks - by design, near a rod is the
  // DANGEROUS place - and that is not what this checks. One bolt, one shield: the timing answer.
  // The strike furthest from every other one.
  const lone = (act) => act.strikes.reduce((best, s) => {
    const gap = Math.min(...act.strikes.filter((o) => o !== s).map((o) => Math.abs(o.x - s.x)));
    return !best || gap > best.gap ? { x: s.x, gap } : best;
  }, null);
  let target = null;
  const r = runEvent(m, { place: (act) => { target = lone(act); plant(m, a, target.x); a.setState('shield'); a.sf = 30; },
    each: () => m._input.set('p0', { guard: false, guardHeld: true }) });
  const blocked = r.hits.filter((h) => h.victim === a.index && h.blocked).length;
  const took = r.hits.filter((h) => h.victim === a.index && !h.blocked).length;
  // It must actually have blocked something: 0% because the bolt landed elsewhere proves nothing.
  check('lightning: a held shield takes the bolt instead of you', blocked > 0 && took === 0 && a.percent === 0,
    `${blocked} bolts blocked, ${took} landed, ${a.percent}% taken, shielding at x=${target && target.x.toFixed(1)}`);
}
{ // be airborne on the drop frame
  const { m, a } = setup('earthquake', { stageId: 'FoundryFloor' });   // one solid: a tremor
  let jumped = false;
  const r = runEvent(m, { place: () => plant(m, a, 0), each: (act) => {
    if (act && act.frame === act.warn - 6 && !jumped) { jumped = true; a.onGround = false; a.vy = 40; a.y += 0.5; a.setState('air'); }
  } });
  check('earthquake: airborne on the drop frame is untouched', r.hits.filter((h) => h.victim === a.index).length === 0 && jumped,
    `jumped 6 frames before the drop: ${r.hits.filter((h) => h.victim === a.index).length} hits`);
}
{ // jump the wave: a real jump (jumpsquat and all), pressed as the crest is 14-16 studs away -
  // the middle of the 12-18 stud window worked out in engine/disasters.js
  const { m, a } = setup('tsunami');
  plant(m, a, 0, 0);
  let jumpedAt = null;
  const r = runEvent(m, { each: (act) => {
    m._input.clear('p0');
    if (!act) return;
    const d = (a.x - act.x) * act.dir;
    if (act.frame >= act.warn && d < 16 && d > 14 && a.onGround && jumpedAt === null) { jumpedAt = d; m._input.set('p0', { jump: true, jumpHeld: true }); }
    // Held from the press on - including jumpsquat, when the fighter still counts as grounded.
    // Letting go inside the short-hop window makes it a short hop at 0.6x height, which the crest
    // rightly catches.
    else if (jumpedAt !== null) m._input.set('p0', { jumpHeld: true });
  } });
  const crest = r.hits.filter((h) => h.victim === a.index && !h.blocked).length;
  check('tsunami: a jump timed to the crest clears it', jumpedAt !== null && crest === 0,
    `full jump pressed ${jumpedAt && jumpedAt.toFixed(1)} studs ahead of the crest: ${crest} crest hits`);
}
{ // and the wave really does hit a fighter who does not jump - so the check above means something
  const { m, a } = setup('tsunami');
  plant(m, a, 0, 0);
  const r = runEvent(m);
  check('tsunami: standing still, the crest does hit', r.hits.some((h) => h.victim === a.index && !h.blocked), 'the control for the jump test');
}

// ---- 6. never the untouchable ----
for (const type of Object.keys(DISASTERS)) {
  const { m, a } = setup(type);
  const late = inHarm(type, m, a);
  const r = runEvent(m, { place: (act) => { if (late) late(act); a.invincible = 1e9; }, each: () => { a.invincible = 1e9; } });
  if (!late) a.invincible = 1e9;
  check(`${type}: never touches an invincible fighter`, r.hits.filter((h) => h.victim === a.index).length === 0 && a.percent === 0,
    `${a.percent}% on a fighter kept invincible in harm's way`);
}

// ...and not even a push: the tornado's inflow must not move an invincible fighter in the air.
{
  const { m, a } = setup('tornado', { stageId: 'FoundryFloor' });
  let pushed = 0, samples = 0;
  runEvent(m, { each: (act) => {
    if (!act || act.frame < act.warn + 5) return;
    // hover the fighter just outside the funnel, in the inflow band, every frame
    a.x = act.x + 5.5; a.y = 6;   // at 6 studs up the funnel is 2.8 wide: 5.5 is in the inflow, clear of the hit a.vx = 0; a.vy = 0; a.onGround = false; a.platform = null;
    a.setState('air'); a.invincible = 1e9;
    if (a.env.windX !== 0) pushed++;
    samples++;
  } });
  check('tornado: its inflow never pushes an invincible fighter', samples > 100 && pushed === 0,
    `${pushed} of ${samples} frames pushed`);
  // the control: a touchable fighter in the same place IS pulled in
  const c = setup('tornado', { stageId: 'FoundryFloor' });
  let pulled = 0;
  runEvent(c.m, { each: (act) => {
    if (!act || act.frame < act.warn + 5 || pulled) return;
    const f = c.a;
    f.x = act.x + 5.5; f.y = 6; f.vx = 0; f.vy = 0; f.onGround = false; f.platform = null; f.setState('air'); f.invincible = 0;
    c.m.step(); c.m.events.length = 0;
    if (f.env.windX !== 0) pulled++;
  } });
  check('tornado: ...while a touchable fighter in the same spot is pulled in', pulled > 0, 'the control');
}

// ---- 7. scheduling: 45 s first, 40-55 s gaps, never in the countdown; deterministic ----
function schedule(seed) {
  const m = makeMatch({ stageId: 'FoundryFloor', disasters: 'chaos', seed, stocks: 99 });
  const starts = [];
  let countdownEvents = 0, trace = '';
  for (let i = 0; i < 60 * 60 * 6 && m.state !== 'results'; i++) {
    const inCountdown = m.state === 'countdown';
    m.step();
    for (const e of m.events) if (e.type === 'disaster') { if (inCountdown) countdownEvents++; starts.push({ t: m.time, type: e.disaster }); }
    if (m.stage.visual.disaster) trace += JSON.stringify(m.stage.visual.disaster);   // what it DID, not just what it was
    m.events.length = 0;
    for (const f of m.fighters) { f.invincible = 1e9; f.percent = 0; }
  }
  return { starts, countdownEvents, m, trace };
}
{
  const s = schedule(3);
  const ends = [];
  const gapsOk = s.starts.every((x, i) => i === 0 || x.t - s.starts[i - 1].t >= 40);   // the contract's numbers, not the constants
  check('the first disaster waits 45 s; later ones come at least 40 s apart; never during the countdown',
    s.starts.length >= 4 && s.starts[0].t >= 45 - 1e-9 && gapsOk && s.countdownEvents === 0,
    `${s.starts.length} disasters in 6 min at ${s.starts.map((x) => x.t.toFixed(0) + 's ' + x.type).join(', ')}`);
  const again = schedule(3);
  check('a seed replays the same disasters at the same moments, doing the same things',
    JSON.stringify(again.starts) === JSON.stringify(s.starts) && again.trace === s.trace && s.trace.length > 1000,
    `${again.starts.length} identical events; ${(s.trace.length / 1024).toFixed(0)} KB of disaster state identical frame for frame`);
  const other = schedule(4);
  check('a different seed gives a different storm', JSON.stringify(other.starts) !== JSON.stringify(s.starts),
    other.starts.map((x) => x.type).join(', '));
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
