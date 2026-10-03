// Balance analysis: KO percents and combo slack, computed from the engine's own formulas.
// Used both as a report (node test/balance.mjs) and as the source of truth for combo.test.mjs.
import { launchSpeed, stunSpeed, hitstun, velocity } from '../src/engine/knockback.js';
import { FRAME, GRAVITY, LAUNCH_DRAG } from '../src/config.js';
import { WEAPONS } from '../src/data/weapons/index.js';
import { buildLoadout } from '../src/data/loadout.js';
import { STAGES } from '../src/data/stages/index.js';

export const STAGE = STAGES.find((s) => s.id === 'FoundryFloor');
// 118 is the Battle Axe. Every KO percent in this project was computed across 90-108 and the axe
// sits outside that range entirely — against an axe victim every published number moves 35 to 44
// points, so a table that stops at 108 describes a fight that cannot happen.
// The roster spread, not a guess: Daggers 72, Gauntlets 78, Longbow 82, Blasters 90, Pike 94,
// Scythe 96, Sword 100, Flail 101, Grimoire 108, Shield 110, Axe 118, Hammer 125.
export const WEIGHTS = [72, 82, 94, 100, 110, 125];

// Simulate a launched fighter to see whether it crosses a blast zone. This mirrors the real
// integration in fighter._physics: gravity, the hitstun horizontal drag, and the raised terminal
// velocity while tumbling.
export function killsAt(base, growth, damage, percentAfter, weight, opts = {}) {
  const angle = opts.angle ?? 45;
  // `launchMul` is the ultimates' knockbackMul: it scales the launch the victim would already
  // have taken, so a KO percent measured without it is meaningless for those moves.
  const launch = launchSpeed(base, growth, damage, percentAfter, weight) * (opts.launchMul ?? 1);
  const v = velocity(launch, angle, 1, null);
  let x = opts.x ?? 0, y = opts.y ?? 0, vx = v.vx, vy = v.vy;
  const b = STAGE.blast;
  // Hitstun is its own curve in the engine (KNOCKBACK.stunSlope), so the frame budget has to come
  // from that one and not from the launch, or this oracle measures a different fight.
  const stun = stunSpeed(base, growth, damage, percentAfter, weight) * (opts.launchMul ?? 1);
  const frames = hitstun(stun) + 40;                    // hitstun, then a little drift
  for (let i = 0; i < frames; i++) {
    vy -= GRAVITY * FRAME;
    if (vy < -80) vy = -80;                             // tumble terminal velocity
    vx *= LAUNCH_DRAG;
    x += vx * FRAME; y += vy * FRAME;
    if (x < b.left || x > b.right || y > b.top) return true;
  }
  return false;
}

export function koPercent(base, growth, damage, weight, opts = {}) {
  for (let p = 0; p <= 400; p++) if (killsAt(base, growth, damage, p + damage, weight, opts)) return p;
  return null;                                          // never kills
}

// Frames between move A connecting on its earliest active frame and move B's first active frame.
// _chainInto fires at mf >= startupA + activeA; hitlag freezes both fighters so it cancels out.
export const chainGap = (A, B) => A.active + B.startup;

export function slack(weapon, A, B, percent) {
  const dmg = A.damage;
  const stun = hitstun(stunSpeed(A.base, A.growth, dmg, percent + dmg, 100)) + (A.extraHitstun || 0);
  return stun - chainGap(A, B);
}

export function edges(w) {
  const out = [];
  for (const [id, m] of Object.entries(w.moves)) {
    for (const [dir, t] of Object.entries(m.chains || {})) out.push({ from: id, dir, to: t, kind: 'light' });
    const ch = m.chainsHeavy;
    if (ch) for (const [dir, t] of (typeof ch === 'string' ? [['*', ch]] : Object.entries(ch))) out.push({ from: id, dir, to: t, kind: 'heavy' });
  }
  return out;
}

if (import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  const PCT = [0, 50, 100, 150];
  console.log('=== COMBO SLACK (hitstun - gap; >=0 is a true combo) ===\n');
  for (const w of WEAPONS) {
    console.log(w.id);
    for (const e of edges(w)) {
      const A = w.moves[e.from], B = w.moves[e.to];
      const s = PCT.map((p) => slack(w, A, B, p));
      const tag = e.kind === 'heavy' ? 'HEAVY' : 'light';
      const worst = Math.max(...s);
      const mark = worst < 0 ? '  <-- never connects' : '';
      console.log(`  ${tag} ${e.from.padEnd(14)} -${e.dir.padEnd(7)}-> ${e.to.padEnd(12)} gap ${String(chainGap(A,B)).padStart(2)}  slack@0/50/100/150: ${s.map(v=>String(v).padStart(3)).join(' ')}${mark}`);
    }
    console.log();
  }

  console.log('=== SIGNATURE KO PERCENT (centre stage, weight 100 unless shown) ===\n');
  console.log('weapon    move            dmg base growth angle   w90  w96 w100 w108');
  const row = (wid, label, d, b, g, angle) => {
    const ks = WEIGHTS.map((wt) => { const k = koPercent(b, g, d, wt, { angle }); return k === null ? ' -- ' : String(k).padStart(4); });
    console.log(`${wid.padEnd(9)} ${label.padEnd(15)} ${String(d).padStart(3)} ${String(b).padStart(4)} ${String(g).padStart(6)} ${String(angle).padStart(5)}  ${ks.join(' ')}`);
  };
  for (const w of WEAPONS) {
    for (const id of ['SigSide', 'SigDown', 'SigNeutral']) {
      const m = w.moves[id]; if (!m) continue;
      // Per-hitbox overrides are what actually resolve in combat.resolveHit, so report them, not
      // just the move-level numbers. A sweetspot is a different move as far as balance goes.
      const boxes = (m.hitboxes || []).filter((h) => h.base != null || h.damage != null || h.growth != null);
      if (boxes.length) {
        boxes.forEach((h, i) => row(w.id, `${id} box${i}`, h.damage ?? m.damage, h.base ?? m.base, h.growth ?? m.growth, h.angle ?? m.angle));
        row(w.id, `${id} (rest)`, m.damage, m.base, m.growth, m.angle);
      } else if (m.kind === 'summon' && m.summon && m.summon.blast) {
        const bl = m.summon.blast;                      // the mine's explosion, not the move itself
        row(w.id, `${id} blast`, bl.damage, bl.base, bl.growth, bl.angle);
      } else {
        row(w.id, id, m.damage, m.base, m.growth, m.angle);
      }
      if (m.charge && m.charge.base) row(w.id, id + '+chg', m.charge.damage, m.charge.base, m.charge.growth, m.angle);
    }
  }
  console.log('\n(-- = cannot KO from centre stage at any percent up to 400)');

  console.log('\n=== STAT SPREAD ===\n');
  console.log('weapon    weight  run    air    fall   recovery');
  for (const w of WEAPONS) {
    const L = buildLoadout('Classic', w.id);
    const r = L.recovery;
    console.log(`${w.id.padEnd(9)} ${String(L.weight).padEnd(7)} ${L.runSpeed.toFixed(2).padEnd(6)} ${L.airSpeed.toFixed(2).padEnd(6)} ${L.fallSpeed.toFixed(2).padEnd(6)} ${r.kind} vy${r.vy ?? r.hopVy ?? '-'} vx${r.vx ?? '-'}`);
  }
}

// ---------------------------------------------------------------------------------------------
// SIMULATION-BACKED CONFIRM ORACLE
//
// slack() above is an estimate: it models hitstun and startup and nothing else. The engine also
// ends hitstun on landing, requires the follow-up to physically REACH, and gives the victim dodge
// invincibility. Asserting against slack() therefore certifies the model against itself.
//
// confirmsAt() runs the actual match: it lands the opener, chains into the follow-up, and lets the
// victim buffer a dodge on their first actionable frame. It returns true only if the follow-up
// connects anyway. That is what "guaranteed" has to mean.
// ---------------------------------------------------------------------------------------------
import { makeMatch, skipCountdown } from './harness.mjs';
import { Combat } from '../src/engine/combat.js';

const EMPTY_IN = { x: 0, y: 0, jump: false, light: false, heavy: false, dodge: false, guard: false,
  grab: false, taunt: false, pickup: false, jumpHeld: false, guardHeld: false, heavyHeld: false,
  lightHeld: false, downTap: false, anyPress: false };

function withImpactStates(fn) {
  const original = Combat.prototype.resolveHit;
  const seen = [];
  Combat.prototype.resolveHit = function (attacker, victim, move, hb, rect, o) {
    const before = victim.state;
    const hit = original.call(this, attacker, victim, move, hb, rect, o);
    if (hit) seen.push({ victim, state: before, move });
    return hit;
  };
  try { return fn(seen); } finally { Combat.prototype.resolveHit = original; }
}

// Returns { confirmed, punish }. `confirmed` means the follow-up landed while the victim was still
// in hitstun and had no choice. `punish` means it landed on the recovery of the dodge they used to
// escape - a legitimate frame trap, but a read, not a guarantee.
export function confirmsAt(weaponId, fromId, dir, toId, percent, opts = {}) {
  return withImpactStates((impacts) => confirmsAtInner(weaponId, fromId, dir, toId, percent, opts, impacts));
}

function confirmsAtInner(weaponId, fromId, dir, toId, percent, opts, impacts) {
  const foe = opts.foeWeapon || weaponId;
  const m = makeMatch({ loadouts: [['Classic', weaponId], ['Noir', foe]] });
  skipCountdown(m);
  for (let i = 0; i < 200; i++) m.step();
  const [a, v] = m.fighters;
  const gap = opts.gap ?? 2.4;
  a.x = -gap / 2; v.x = gap / 2; a.facing = 1; v.facing = -1;
  for (const f of [a, v]) { f.onGround = true; f.platform = m.stage.main; f.y = 0; f.vx = 0; f.vy = 0; f.invincible = 0; }
  v.setState('idle'); v.percent = percent;
  a.setState('idle'); a.hitVictims = new Map();

  const heavy = !!m.fighters[0].char.moves[toId].heavy;
  const stick = dir === 'up' ? { y: 1 } : dir === 'down' ? { y: -1 } : dir === 'side' ? { x: 1 } : {};
  const press = (p) => m._input.set('p0', Object.assign({}, EMPTY_IN, p, { anyPress: true }));

  a.startMove(fromId);
  const to = m.fighters[0].char.moves[toId];
  // A combo has to land promptly. A projectile still in flight or an armed mine that catches the
  // victim two seconds later is not a confirm, so the follow-up gets its active window plus a
  // short grace and no more.
  const budget = to.active + 24;
  let opened = false, chained = false, chainedAt = -1, startPct = percent, dodged = false;
  for (let i = 0; i < 200; i++) {
    if (!opened && v.percent > startPct) opened = true;          // the opener connected
    // The follow-up input, held until the chain fires. `timing` is how it is pressed (COMBO in
    // config.js): 'mash' presses every frame from the opener's first frame, which is an ordinary
    // link - exactly what every chain was before timed links existed, so the weapons' header
    // tables measure the same; 'perfect' starts pressing the frame the opener lands, a timed link.
    const timing = opts.timing || 'mash';
    if ((opened || timing === 'mash') && !chained && a.moveId === fromId) {
      press(Object.assign({}, stick, heavy ? { heavy: true, heavyHeld: true } : { light: true }));
    } else m._input.clear('p0');
    // Once hit, the victim escapes the instant they are actionable again. Spot dodge is invincible
    // on frames 3-14, so this is the strictest realistic test of "guaranteed".
    if (opened && !dodged && v.state !== 'hitstun' && v.hitlag === 0 && !v.holder && ['idle', 'run', 'air'].includes(v.state)) {
      m._input.set('p1', Object.assign({}, EMPTY_IN, { dodge: true, anyPress: true }));
      dodged = true;
    } else if (dodged) m._input.clear('p1');
    const pctBefore = v.percent;
    const nImpacts = impacts.length;
    m.step();
    if (a.moveId === toId && !chained) { chained = true; chainedAt = i; }
    if (chained && v.percent > pctBefore) {
      const inWindow = i - chainedAt <= budget;
      const impact = impacts.slice(nImpacts).find((x) => x.victim === v);
      const state = impact ? impact.state : v.state;
      return { confirmed: inWindow && state === 'hitstun', punish: inWindow && state !== 'hitstun',
        stateAtImpact: state, dodged, opened, chained };
    }
    if (chained && i - chainedAt > budget) break;                   // ran out of window
  }
  return { confirmed: false, punish: false, dodged, opened, chained };
}

// Lowest percent (stepping by `step`) at which a route is genuinely guaranteed, or null.
export function confirmWindow(weaponId, fromId, dir, toId, { max = 200, step = 5 } = {}) {
  for (let p = 0; p <= max; p += step) {
    const r = confirmsAt(weaponId, fromId, dir, toId, p);
    if (!r.opened) return { from: p, note: 'opener never connected' };
    if (r.confirmed) {
      for (let q = Math.max(0, p - step + 1); q <= p; q++) if (confirmsAt(weaponId, fromId, dir, toId, q).confirmed) return { from: q };
      return { from: p };
    }
  }
  return null;
}

// ---------------------------------------------------------------------------------------------
// routeAt(): a whole combo ROUTE played through the engine, the way a player would press it.
//
// `route` is a list of steps. The first is { start: moveId }; after it, each step is either
//   { to: moveId, press: {...} }   the next attack: Light/Heavy with a direction, or
//   { cancel: 'jump' | 'dodge', x }  cut the current move's recovery short.
// `timing` is how the attacks are pressed (COMBO in config.js): 'perfect' presses each follow-up
// the moment the previous move lands - during the hit's freeze, a timed link - and 'mash' presses
// every frame from the start of each move. After a cancel the next attack is pressed every frame
// until it comes out, which is what a player does.
//
// The victim escapes exactly as in confirmsAt: a dodge on their first actionable frame (an air
// dodge in the air). `confirmed` means every attack in the route connected, each one after the
// first while the victim was still in hitstun - the whole route was unescapable.
export function routeAt(weaponId, route, percent, opts = {}) {
  return withImpactStates((impacts) => routeAtInner(weaponId, route, percent, opts, impacts));
}

function routeAtInner(weaponId, route, percent, opts, impacts) {
  const m = makeMatch({ loadouts: [['Classic', weaponId], ['Noir', opts.foeWeapon || weaponId]] });
  skipCountdown(m);
  for (let i = 0; i < 200; i++) m.step();
  const [a, v] = m.fighters;
  const gap = opts.gap ?? 2.4;
  a.x = -gap / 2; v.x = gap / 2; a.facing = 1; v.facing = -1;
  for (const f of [a, v]) {
    f.vx = 0; f.vy = 0; f.invincible = 0;
    if (opts.air) { f.onGround = false; f.platform = null; f.y = opts.air; f.setState('air'); }
    else { f.onGround = true; f.platform = m.stage.main; f.y = 0; f.setState('idle'); }
  }
  if (opts.air) a.y -= 0.5;                  // a touch below: aerials are aimed up and out
  v.percent = percent; a.hitVictims = new Map();
  const timing = opts.timing || 'perfect';
  const press = (src, p) => m._input.set(src, Object.assign({}, EMPTY_IN, p, { anyPress: true }));

  a.startMove(route[0].start);
  let k = 1, dodged = false, cancelled = false, perfects = 0, serialAtStep = a.moveSerial;
  const attacks = route.filter((s) => !s.cancel).map((s) => s.start || s.to);
  const landedMoves = [];                    // [moveId, victim state at impact], first impact of each swing
  const seenSerial = new Set();
  for (let i = 0; i < 400 && k <= route.length; i++) {
    const step = route[k];
    let input = null;
    if (step && step.cancel) {
      if (a.moveLanded && a.state === 'attack') input = { [step.cancel]: true, x: step.x || 0, y: step.y || 0 };
    } else if (step) {
      const p = Object.assign({}, step.press);
      if (cancelled) input = p;                                            // after a cancel: press until it comes out
      else if (timing === 'mash') input = a.state === 'attack' ? p : null;
      else if (a.moveLanded && a.state === 'attack') input = p;            // timed: from the moment it lands
    }
    if (input) press('p0', input); else m._input.clear('p0');
    if (!dodged && landedMoves.length && v.state !== 'hitstun' && v.hitlag === 0 && !v.holder && ['idle', 'run', 'air'].includes(v.state)) {
      press('p1', { dodge: true }); dodged = true;
    } else if (dodged) m._input.clear('p1');
    const n0 = impacts.length;
    m.step();
    for (const e of m.events) if (e.type === 'perfectlink' && e.fighter === 0) perfects++;
    m.events.length = 0;
    for (const hit of impacts.slice(n0)) {
      if (hit.victim !== v || seenSerial.has(a.moveSerial)) continue;
      seenSerial.add(a.moveSerial);
      landedMoves.push([hit.move.id, hit.state]);
    }
    // advance the route
    if (step && step.cancel && a.state !== 'attack') { k++; cancelled = true; continue; }
    if (step && !step.cancel && a.moveId === step.to && a.moveSerial !== serialAtStep) { k++; cancelled = false; serialAtStep = a.moveSerial; }
    if (k >= route.length && landedMoves.length >= attacks.length) break;
    if (!a.move && a.state !== 'jumpsquat' && a.state !== 'air' && a.state !== 'dash' && a.state !== 'airdodge' && !cancelled && k < route.length) break;
  }
  const completed = k >= route.length;
  const allLanded = completed && landedMoves.length >= attacks.length && attacks.every((id, j) => landedMoves[j] && landedMoves[j][0] === id);
  const confirmed = allLanded && landedMoves.slice(1, attacks.length).every(([, s]) => s === 'hitstun');
  return { completed, allLanded, confirmed, perfects, landed: landedMoves, dodged, reached: a.moveId };
}

// ---------------------------------------------------------------------------------------------
// The routes the combo system (COMBO in config.js) advertises for a weapon, read off its data.
//   finisherRoute: Light from LightNeutral1 along the neutral chain to the move that holds the
//     `Finisher` branch, then the finisher - the string a player links perfectly all the way.
//   airRoute: back from the aerial holding the `AirFinisher` branch through the aerials that
//     chain into it, then the air finisher.
//   cancelRoutes: every declared cancel off a landed move, into the obvious follow-up - Rising
//     into the up-aerial after a jump, the side light after a dodge's dash.
const DIR_PRESS = { neutral: {}, side: { x: 1 }, up: { y: 1 }, down: { y: -1 } };
export function finisherRoute(w) {
  const M = w.moves;
  const from = Object.keys(M).find((id) => M[id].finishers && Object.values(M[id].finishers).includes('Finisher'));
  if (!from) return null;
  const path = ['LightNeutral1'];
  while (path[path.length - 1] !== from) {
    const next = M[path[path.length - 1]].chains && M[path[path.length - 1]].chains.neutral;
    if (!next || path.includes(next)) return null;
    path.push(next);
  }
  return [{ start: path[0] }, ...path.slice(1).map((id) => ({ to: id, press: { light: true } })), { to: 'Finisher', press: { light: true } }];
}
export function airRoute(w) {
  const M = w.moves;
  let cur = Object.keys(M).find((id) => M[id].finishers && Object.values(M[id].finishers).includes('AirFinisher'));
  if (!cur) return null;
  // the longest chain of aerials leading into it: the whole air string, not a shortcut through it
  const into = (id) => Object.keys(M).filter((p) => p.startsWith('Air') && M[p].chains && Object.values(M[p].chains).includes(id));
  const longest = (id, seen) => {
    let best = [id];
    for (const p of into(id)) if (!seen.has(p)) { const l = [...longest(p, new Set([...seen, p])), id]; if (l.length > best.length) best = l; }
    return best;
  };
  const path = longest(cur, new Set([cur]));
  const steps = path.slice(1).map((id, i) => {
    const dir = Object.entries(M[path[i]].chains).find(([, t]) => t === id)[0];
    return { to: id, press: { light: true, ...DIR_PRESS[dir] } };
  });
  return [{ start: path[0] }, ...steps, { to: 'AirFinisher', press: { light: true } }];
}
export function cancelRoutes(w) {
  const out = [];
  for (const [id, m] of Object.entries(w.moves)) {
    for (const kind of Object.keys(m.cancels || {})) {
      const to = kind === 'jump' ? 'AirUp' : 'LightSide1';
      out.push({ from: id, kind, to, route: [{ start: id }, { cancel: kind, x: kind === 'dodge' ? 1 : 0 }, { to, press: { light: true, ...(kind === 'jump' ? { y: 1 } : { x: 1 }) } }] });
    }
  }
  return out;
}
export const routeLabel = (w, route) => route.map((s) => (s.cancel ? s.cancel : w.moves[s.start || s.to].label))
  .join(' > ').replace(/ > (jump|dodge) > /g, ', $1 > ');

// The longest combo a greedy attacker can hold a victim in (COMBO: the victim escapes the only way
// it can without breaking - a dodge the moment it can act). Two greedy styles, the worse taken:
// cancel every landed move that allows it, or run each string out first and cancel at its end.
// Either way every follow-up is timed and aimed at the victim. This is the infinite check.
export function longestCombo(weaponId, percent, frames = 600) {
  let best = 0;
  for (const style of ['cancel', 'string']) {
    const m = makeMatch({ loadouts: [['Classic', weaponId], ['Noir', 'Sword']] });
    skipCountdown(m); for (let i = 0; i < 200; i++) m.step();
    const [a, v] = m.fighters;
    a.x = -1.2; v.x = 1.2; a.facing = 1; v.facing = -1;
    for (const f of [a, v]) { f.onGround = true; f.platform = m.stage.main; f.y = 0; f.vx = 0; f.vy = 0; f.invincible = 0; f.setState('idle'); }
    v.percent = percent;
    const set = (src, p) => m._input.set(src, Object.assign({}, EMPTY_IN, p, { anyPress: true }));
    let dodged = false, hit = false;
    a.startMove('LightNeutral1');
    for (let i = 0; i < frames; i++) {
      const toward = v.x >= a.x ? 1 : -1;
      let p = null;
      if (a.state === 'attack' && a.moveLanded && a.move) {
        const mv = a.move, c = mv.cancels;
        const strings = style === 'string' && (mv.chains || mv.finishers || mv.chainsTo);
        if (c && !strings) p = c.dodge ? { dodge: true, x: toward } : { jump: true };
        else p = { light: true };
      } else if (['idle', 'run', 'air', 'dash'].includes(a.state)) p = { light: true, x: toward };
      if (p) set('p0', p); else m._input.clear('p0');
      if (v.comboHits > 0) hit = true;
      if (hit && !dodged && v.state !== 'hitstun' && v.hitlag === 0 && ['idle', 'run', 'air'].includes(v.state)) { set('p1', { dodge: true }); dodged = true; }
      else { m._input.clear('p1'); if (v.state === 'hitstun') dodged = false; }
      m.step(); m.events.length = 0;
      best = Math.max(best, v.comboHits);
    }
  }
  return best;
}
