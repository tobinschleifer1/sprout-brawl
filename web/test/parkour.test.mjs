// The Skyline Climb: can every step be made, and is the last stretch really the hardest?
//
// Every step of the route is JUMPED with the real engine: from the foothold you are on to the next,
// trying run-ups, take-off points, double-jump timings and - where either foothold moves - how
// long you wait first. A step passes if any attempt lands you on the next foothold. The share of
// attempts that land is the step's difficulty, and the final stretch has to be far below the rest.
import { COURSE, COURSE_WEAPON, CHECKPOINTS } from '../src/data/parkour.js';
import { Parkour } from '../src/engine/parkour.js';
import { buildLoadout } from '../src/data/loadout.js';
import { emptyFrame } from '../src/engine/input.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };
const CHAR = buildLoadout('Classic', COURSE_WEAPON);
const frame = (x, jump = false, jumpHeld = false) => ({ ...emptyFrame(), x, jump, jumpHeld });
const byId = (pk, id) => pk.stage.platforms.find((p) => p.id === id);
const dataOf = (id) => (id === 'main' ? null : COURSE.platforms.find((p) => p.id === id));
const moves = (id) => { const d = dataOf(id); return !!(d && (d.moving || d.sinking)); };
const periodOf = (id) => { const d = dataOf(id); return d && d.moving ? (d.moving.x || d.moving.y).period : 0; };

// One attempt from A to B. Returns true if it lands on B.
function attempt(aId, bId, { start, edge, j2, wait, release, hop }) {
  const pk = new Parkour(COURSE, CHAR);
  const A = byId(pk, aId), B = byId(pk, bId);
  const f = pk.fighter;
  const dir = Math.sign((B.x1 + B.x2) / 2 - (A.x1 + A.x2) / 2) || 1;
  f.x = start === 'far' ? (dir > 0 ? A.x1 + 0.6 : A.x2 - 0.6) : start === 'mid' ? (A.x1 + A.x2) / 2 : (dir > 0 ? A.x2 - 1.2 : A.x1 + 1.2);
  f.y = A.top; f.platform = A; f.onGround = true;
  for (let i = 0; i < wait; i++) pk.step(frame(0));
  let jumped = -1;
  for (let t = 0; t < 420; t++) {
    const onA = f.onGround && f.platform === A;
    const atEdge = dir > 0 ? f.x >= A.x2 - edge : f.x <= A.x1 + edge;
    // Easing off: let go of the direction some frames after take-off (and the jump button early,
    // for a short hop) - how a player lands on something small or close.
    const held = jumped >= 0 && (hop === 'full' || t - jumped < 4);
    const steer = jumped >= 0 && release !== null && t - jumped >= release ? 0 : dir;
    let inp = frame(steer, false, held);
    if (jumped < 0 && onA && atEdge) { inp = frame(dir, true, true); jumped = t; }
    else if (jumped >= 0 && j2 !== null && t - jumped === j2) inp = frame(steer, true, true);
    const before = pk.deaths;
    pk.step(inp);
    if (pk.deaths > before) return false;
    if (jumped >= 0 && f.onGround && f.platform === B) return true;
    if (jumped >= 0 && t - jumped > 6 && f.onGround && f.platform !== B) return false;
    if (jumped < 0 && t > 300) return false;
  }
  return false;
}

// Every strategy for one step: the landing rate is its difficulty.
function step(aId, bId) {
  const moving = moves(aId) || moves(bId);
  const starts = moving ? ['far'] : ['far', 'mid', 'near'];
  const edges = moving ? [0.3, 1.5] : [0.3, 1.0, 2.0];
  const j2s = [null];
  for (let j = 4; j <= 56; j += moving ? 8 : 4) j2s.push(j);
  const span = Math.max(periodOf(aId), periodOf(bId)) * 60;
  const waits = [0];
  // A moving foothold is a timing puzzle: try take-offs every tenth of a second across its cycle.
  if (moving) for (let w = 6; w <= Math.max(span, 60); w += 6) waits.push(w);
  const releases = [null, 10, 20, 40];
  const hops = ['full', 'short'];
  let tries = 0, lands = 0;
  for (const start of starts) for (const edge of edges) for (const j2 of j2s) for (const wait of waits)
    for (const release of releases) for (const hop of hops) {
      tries++;
      if (attempt(aId, bId, { start, edge, j2, wait, release, hop })) lands++;
    }
  return { tries, lands, rate: lands / tries };
}

// ---- 1. every step of the route can be made ----
const route = COURSE.route;
const needleAt = route.indexOf('needle');
const results = [];
{
  const bad = [];
  for (let i = 0; i < route.length - 1; i++) {
    const r = step(route[i], route[i + 1]);
    results.push({ from: route[i], to: route[i + 1], ...r, final: i >= needleAt });
    if (r.lands === 0) bad.push(`${route[i]} -> ${route[i + 1]} (0 of ${r.tries})`);
  }
  check('every step of the Skyline Climb can be made with the real engine', bad.length === 0,
    bad.length ? `impossible: ${bad.join('; ')}` : `${results.length} steps, each landed by at least one of its attempts`);
}

// ---- 2. the last stretch is the hardest, by a long way ----
{
  const early = results.filter((r) => !r.final), last = results.filter((r) => r.final);
  const mean = (list) => list.reduce((s, r) => s + r.rate, 0) / list.length;
  const hardestEarly = Math.min(...early.map((r) => r.rate));
  const easiestLast = Math.max(...last.map((r) => r.rate));
  const sectionRates = [];
  for (let c = 1; c < CHECKPOINTS.length; c++) {
    const from = route.indexOf(CHECKPOINTS[c - 1].pad), to = route.indexOf(CHECKPOINTS[c].pad);
    const rs = results.slice(from, to);
    sectionRates.push(`${CHECKPOINTS[c].name} ${(100 * mean(rs)).toFixed(0)}%`);
  }
  console.log('      landing rate by section: ' + sectionRates.join(', '));
  console.log('      final stretch: ' + last.map((r) => `${r.to} ${(100 * r.rate).toFixed(1)}%`).join(', '));
  console.log('      hardest before it: ' + [...early].sort((a, b) => a.rate - b.rate).slice(0, 5).map((r) => `${r.from}->${r.to} ${(100 * r.rate).toFixed(1)}%`).join(', '));
  check('the stretch to the Summit is far harder than anything before it', mean(last) < mean(early) * 0.25 && easiestLast <= 0.12,
    `final stretch lands ${(100 * mean(last)).toFixed(1)}% of attempts (easiest step ${(100 * easiestLast).toFixed(1)}%), the rest ${(100 * mean(early)).toFixed(1)}% (hardest ${(100 * hardestEarly).toFixed(1)}%)`);
}

// ---- 3. checkpoints, falls and the clock ----
{
  const bad = [];
  const pk = new Parkour(COURSE, CHAR);
  if (pk.reached !== 0 || pk.fighter.platform.id !== 'main') bad.push('does not start on Rooftop Access');
  // Stand on the chimney pad: that is checkpoint 1.
  const chimney = byId(pk, 'chimney');
  pk.fighter.x = chimney.cx; pk.fighter.y = chimney.top + 3; pk.fighter.onGround = false; pk.fighter.platform = null;
  for (let i = 0; i < 60; i++) pk.step(frame(0));
  if (pk.reached !== 1) bad.push(`landing on the chimney reached checkpoint ${pk.reached}`);
  const ev = pk.drain();
  if (!ev.some((e) => e.type === 'checkpoint' && e.checkpoint === 1)) bad.push('no checkpoint event');
  // Fall: back on the chimney, one death.
  pk.fighter.x = 150; pk.fighter.y = -10; pk.fighter.onGround = false; pk.fighter.platform = null;
  for (let i = 0; i < 120; i++) pk.step(frame(0));
  if (pk.deaths !== 1 || pk.fighter.platform !== chimney) bad.push(`after a fall: ${pk.deaths} deaths, on ${pk.fighter.platform && pk.fighter.platform.id}`);
  if (!pk.drain().some((e) => e.type === 'fall')) bad.push('no fall event');
  // Skipping a pad counts it; the Summit finishes and stops the clock.
  const summit = byId(pk, 'summit');
  pk.fighter.x = summit.cx; pk.fighter.y = summit.top + 3; pk.fighter.onGround = false; pk.fighter.platform = null;
  for (let i = 0; i < 60; i++) pk.step(frame(0));
  const clock = pk.frames;
  for (let i = 0; i < 60; i++) pk.step(frame(0));
  if (!pk.done || pk.reached !== CHECKPOINTS.length - 1) bad.push('the Summit did not finish the climb');
  if (pk.frames !== clock) bad.push('the clock kept running after the Summit');
  if (!pk.drain().some((e) => e.type === 'summit')) bad.push('no summit event');
  // A returning climber starts on their checkpoint.
  const back = new Parkour(COURSE, CHAR, 5);
  if (back.fighter.platform.id !== CHECKPOINTS[5].pad) bad.push('did not start on checkpoint 5');
  check('checkpoints count on landing, a fall returns you to the last one, the Summit stops the clock', bad.length === 0,
    bad.length ? bad.join('; ') : 'landing, falling, skipping ahead, finishing and resuming all behave');
}

// ---- 4. harmless ----
{
  const a = new Parkour(COURSE, CHAR), b = new Parkour(COURSE, CHAR);
  for (let i = 0; i < 400; i++) {
    const base = frame(i < 200 ? 1 : -1, i % 50 === 0, i % 50 < 12);
    a.step(base);
    b.step({ ...base, light: true, heavy: true, ult: true, guard: true, grab: true, dodge: true, pickup: true });
  }
  check('attack buttons do nothing on the course', a.fighter.x === b.fighter.x && a.fighter.y === b.fighter.y && a.fighter.state === b.fighter.state,
    `after 400 frames both at (${a.fighter.x.toFixed(2)}, ${a.fighter.y.toFixed(2)})`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
