// Lag compensation (docs/briefs/combat-plan.md, phase 4): a swing or a grab judged against where
// its attacker saw the victim.
//
//   * a swing at a foe who has since stepped away lands when the attacker saw them in reach, and
//     misses when the attacker is looking at now;
//   * the look back is capped at LAG_COMP.maxFrames - asked for more, it looks that far and no
//     further; a foe in reach only before that is missed;
//   * only the position is rewound: a foe invincible now is not hit, a foe shielding now blocks;
//   * a grab is rewound the same way; a foe who was KO'd at the frame looked at is judged as now;
//   * it is per attacker, and nothing changes when nobody looks back: a match with every rewind 0
//     plays out frame for frame as one without lag compensation at all.
//
//     node test/lagcomp.test.mjs
import { makeMatch, skipCountdown } from './harness.mjs';
import { LAG_COMP, FRAME } from '../src/config.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };

const REACH = 2, GONE = 9;
// The victim stands in reach of a's jab for `near` frames, then out of it for `far` frames; then a
// jabs. `rewind` is how far back a is looking (null: no lag compensation at all). What a's swing did.
function swing({ rewind = null, near = 12, far = 1, now = null, grab = false, koNear = false }) {
  const m = skipCountdown(makeMatch({ loadouts: [['Classic', 'Sword'], ['Noir', 'Sword']] }));
  const [a, v] = m.fighters;
  for (const f of [a, v]) { f.y = 0; f.vx = 0; f.vy = 0; f.onGround = true; f.platform = m.stage.main; f.setState('idle'); f.invincible = 0; }
  a.x = 0; a.facing = 1; v.facing = -1;
  if (rewind !== null) m.combat.rewindOf = (f) => (f === a ? rewind : 0);
  const hold = (x) => { v.x = x; v.y = 0; v.vx = 0; v.vy = 0; v.invincible = 0; };
  if (koNear) m.knockOut(v);
  for (let i = 0; i < near; i++) { hold(REACH); m.step(); }
  if (koNear) { m.respawn(v); v.setState('idle'); v.onGround = true; v.platform = m.stage.main; }
  for (let i = 0; i < far; i++) { hold(GONE); m.step(); }
  hold(GONE);
  if (now) now(v, m);
  m.events.length = 0;
  const seen = [];
  if (grab) {
    m.combat.checkGrab(a);
    return { grabbed: v.state === 'grabbed', v };
  }
  a.startMove(a.char.moves.LightNeutral1);
  for (let i = 0; i < 12; i++) {
    if (!now) hold(GONE);
    m.step();
    for (const e of m.events) if ((e.type === 'hit' || e.type === 'block') && e.victim === v.index) seen.push(e.type);
    m.events.length = 0;
  }
  return { seen, v };
}
// The jab's hitbox comes out on its sixth frame, so a foe gone `far` frames before the swing has
// been gone far + 6 frames by the time it is judged.
const ACTIVE = 6;

// ---- it lands where they were seen ----
{
  const live = swing({ far: 1 }), looked = swing({ far: 1, rewind: ACTIVE + 2 }), short = swing({ far: 1, rewind: 2 });
  check('a jab at a foe who has stepped away lands when the attacker saw them in reach', looked.seen.includes('hit') && !live.seen.length,
    `looking ${ACTIVE + 2} frames back: ${looked.seen.join(',') || 'miss'}; with no lag compensation: ${live.seen.join(',') || 'miss'}`);
  check('and misses when what they saw was already after the step', !short.seen.length, `looking 2 frames back: ${short.seen.join(',') || 'miss'}`);
}

// ---- capped ----
{
  // in reach until exactly LAG_COMP.maxFrames before the hitbox comes out, then gone
  const far = LAG_COMP.maxFrames - ACTIVE;
  const asked = swing({ far, rewind: 30 }), edge = swing({ far, rewind: LAG_COMP.maxFrames });
  const older = swing({ far: far + 1, rewind: 30 });
  // 150ms, as agreed: a full rewind for a ping of about 200ms
  check(`asked for more than ${LAG_COMP.maxFrames} frames (150ms), it looks ${LAG_COMP.maxFrames} back`, Math.abs(LAG_COMP.maxFrames * FRAME - 0.15) < 1e-9 && asked.seen.includes('hit') && edge.seen.includes('hit'),
    `foe last in reach ${LAG_COMP.maxFrames} frames before: asked for 30, ${asked.seen.join(',') || 'miss'}; asked for ${LAG_COMP.maxFrames}, ${edge.seen.join(',') || 'miss'}`);
  check('and no further: a foe in reach only before that is missed', !older.seen.length,
    `foe last in reach ${LAG_COMP.maxFrames + 1} frames before, asked for 30: ${older.seen.join(',') || 'miss'}`);
}

// ---- only the position ----
{
  const dodging = swing({ far: 1, rewind: ACTIVE + 2, now: (v) => { v.invincible = 30; } });
  const shielding = swing({ far: 1, rewind: ACTIVE + 2, now: (v, m) => { m._input.set('p1', { guardHeld: true }); v.setState('shield'); v.shield = 50; v.sf = 30; } });
  check('a foe invincible now is not hit, wherever they were seen', !dodging.seen.length, `invincible now: ${dodging.seen.join(',') || 'miss'}`);
  check('a foe shielding now blocks it', shielding.seen[0] === 'block' && !shielding.seen.includes('hit'), `shielding now: ${shielding.seen.join(',') || 'miss'}`);
}

// ---- grabs, and a KO'd past ----
{
  const live = swing({ far: 3, grab: true }), looked = swing({ far: 3, rewind: 5, grab: true });
  check('a grab is judged where the foe was seen too', looked.grabbed && !live.grabbed,
    `looking 5 frames back: ${looked.grabbed ? 'grabbed' : 'missed'}; with no lag compensation: ${live.grabbed ? 'grabbed' : 'missed'}`);
  const ko = swing({ far: 1, rewind: ACTIVE + 2, koNear: true });
  check('a foe KO\'d at the frame looked at is judged as now', !ko.seen.length, `KO'd in reach, respawned out of it: ${ko.seen.join(',') || 'miss'}`);
}

// ---- per attacker, and read-only at zero ----
{
  // v swings back at a with a's rewind set: v looks at now.
  const m = skipCountdown(makeMatch({ loadouts: [['Classic', 'Sword'], ['Noir', 'Sword']] }));
  const [a, v] = m.fighters;
  for (const f of [a, v]) { f.y = 0; f.vx = 0; f.vy = 0; f.onGround = true; f.platform = m.stage.main; f.setState('idle'); f.invincible = 0; }
  v.x = 0; v.facing = 1; a.facing = -1;
  m.combat.rewindOf = (f) => (f === a ? ACTIVE + 2 : 0);
  for (let i = 0; i < 12; i++) { a.x = REACH; m.step(); }
  a.x = GONE;
  v.startMove(v.char.moves.LightNeutral1);
  let hit = false;
  for (let i = 0; i < 12; i++) { a.x = GONE; m.step(); hit = hit || m.events.some((e) => e.type === 'hit'); m.events.length = 0; }
  check('only the attacker asked about looks back', !hit, `the other fighter's jab at the same old spot: ${hit ? 'hit' : 'miss'}`);

  const run = (seed, rewindOf) => {
    const g = skipCountdown(makeMatch({ mode: 'StockFFA', stocks: 2, seed,
      armed: [['Classic', ['Sword', 'Hammer']], ['Noir', ['Daggers', 'Axe']], ['Ember', ['Pike', 'Shield']]] }));
    g.fighters.forEach((f) => { f.isBot = true; f.botLevel = 'elite'; });
    g.combat.rewindOf = rewindOf;
    let hits = 0;
    for (let i = 0; i < 60 * 90 && g.state !== 'results'; i++) { g.step(); hits += g.events.filter((e) => e.type === 'hit').length; g.events.length = 0; }
    return { hits, state: g.fighters.map((f) => [f.x.toFixed(9), f.y.toFixed(9), f.percent, f.stocksLeft(), f.state].join(',')).join(' | ') + ` @${g.frame}` };
  };
  let same = true, differs = 0, hits = 0;
  for (const seed of [41, 42, 43]) {
    const none = run(seed, null), zero = run(seed, () => 0), back = run(seed, (f) => (f.index === 0 ? 6 : 0));
    hits += none.hits;
    if (none.state !== zero.state) same = false;
    if (none.state !== back.state) differs++;
  }
  check('with every rewind 0 a match plays out exactly as without lag compensation', same && hits > 50, `${hits} hits over three bot matches; the runs ${same ? 'match' : 'differ'}`);
  check('and a rewind does change a real fight', differs === 3, `${differs} of 3 matches went differently with one bot looking 6 frames back`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
