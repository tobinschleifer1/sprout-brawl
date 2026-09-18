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
    // hold the follow-up input from the moment the opener lands until the chain fires
    if (opened && !chained && a.moveId === fromId) {
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
