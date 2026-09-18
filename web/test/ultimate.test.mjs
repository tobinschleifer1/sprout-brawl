// Ultimates: the meter rules, and the per-weapon moves once they exist.
//
// The meter is the part that has to be exactly right, because it is shared by every weapon and it
// is the only resource in the game that survives across moves. The rules under test:
//   - one landed hit is one charge, regardless of damage, so pressure fills it and not just big hits
//   - chip and tick damage does not charge it
//   - losing a stock wipes it
//   - activation spends the whole bar and cannot happen below the threshold
import { makeMatch, skipCountdown } from './harness.mjs';
import { WEAPONS } from '../src/data/weapons/index.js';
import { ULTIMATE } from '../src/config.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };
const EMPTY_IN = { x: 0, y: 0, jump: false, light: false, heavy: false, dodge: false, guard: false,
  grab: false, taunt: false, pickup: false, ult: false, jumpHeld: false, guardHeld: false,
  heavyHeld: false, lightHeld: false, downTap: false, anyPress: false };

function duel(weaponId, foe = 'Sword') {
  const m = makeMatch({ loadouts: [['Classic', weaponId], ['Noir', foe]] });
  skipCountdown(m);
  for (let i = 0; i < 200; i++) m.step();
  const [a, v] = m.fighters;
  const place = () => {
    a.x = -1.2; v.x = 1.2; a.facing = 1; v.facing = -1;
    for (const f of [a, v]) { f.onGround = true; f.platform = m.stage.main; f.y = 0; f.vx = 0; f.vy = 0; }
    v.setState('idle');
  };
  place();
  return { m, a, v, place };
}

// Land `n` clean hits with the jab, resetting between each so they all connect.
function landHits(ctx, n) {
  const { m, a, v, place } = ctx;
  for (let i = 0; i < n; i++) {
    place(); v.percent = 0; v.invincible = 0; a.setState('idle'); a.hitVictims = new Map();
    a.startMove('LightNeutral1');
    for (let k = 0; k < 60 && (a.state === 'attack' || a.hitlag > 0); k++) m.step();
  }
}

// ---- 1. landed hits charge the meter, one per hit ----
{
  const ctx = duel('Sword');
  landHits(ctx, 5);
  check('a landed hit charges the meter', ctx.a.ultCharge === 5,
    `5 jabs -> ${ctx.a.ultCharge} charge (want 5 of ${ULTIMATE.hitsRequired})`);
}

// ---- 2. the meter caps at the requirement and reports ready ----
{
  const ctx = duel('Sword');
  landHits(ctx, ULTIMATE.hitsRequired + 4);
  check('the meter caps and reports ready', ctx.a.ultCharge === ULTIMATE.hitsRequired,
    `${ULTIMATE.hitsRequired + 4} hits -> ${ctx.a.ultCharge} charge, ultMeter ${ctx.a.ultMeter.toFixed(2)}, ready ${ctx.a.ultReady}`);
}

// ---- 3. taking a hit does not charge YOUR meter ----
{
  const ctx = duel('Sword');
  const { m, a, v, place } = ctx;
  for (let i = 0; i < 4; i++) {
    place(); a.percent = 0; a.invincible = 0; v.setState('idle'); v.hitVictims = new Map();
    v.startMove('LightNeutral1');
    for (let k = 0; k < 60 && (v.state === 'attack' || v.hitlag > 0); k++) m.step();
  }
  check('being hit does not charge your own meter', a.ultCharge === 0 && v.ultCharge > 0,
    `attacker ${v.ultCharge}, victim ${a.ultCharge} — the meter belongs to whoever landed the hit`);
}

// ---- 4. losing a stock wipes the meter ----
{
  const ctx = duel('Sword');
  landHits(ctx, 8);
  const before = ctx.a.ultCharge;
  const { m, a } = ctx;
  a.onGround = false; a.platform = null; a.y = m.stage.blast.bottom - 60; a.setState('air');
  for (let i = 0; i < 200 && a.alive; i++) m.step();
  for (let i = 0; i < 200 && !a.alive; i++) m.step();
  check('losing a stock wipes the meter', before === 8 && a.ultCharge === 0,
    `${before} charge before the KO, ${a.ultCharge} after respawn — dying costs your progress`);
}

// ---- 5. a weapon with no Ultimate never charges and never fires ----
{
  const missing = WEAPONS.filter((w) => !w.moves.Ultimate).map((w) => w.id);
  if (missing.length === WEAPONS.length) {
    console.log(`SKIP  per-weapon ultimates\n      no weapon defines an Ultimate move yet — meter rules tested above still apply`);
  } else if (missing.length) {
    check('every weapon has an Ultimate', false, `missing on: ${missing.join(', ')}`);
  } else {
    check('every weapon has an Ultimate', true, WEAPONS.map((w) => `${w.id}:${w.moves.Ultimate.label}`).join('  '));
  }
}

// ---- 6. activation: below the threshold nothing happens, at it the bar empties ----
if (WEAPONS.some((w) => w.moves.Ultimate)) {
  const wid = WEAPONS.find((w) => w.moves.Ultimate).id;
  {
    const ctx = duel(wid);
    landHits(ctx, 5);
    ctx.place(); ctx.a.setState('idle');
    ctx.m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: true, anyPress: true }));
    ctx.m.step();
    check(`${wid}: cannot fire below ${ULTIMATE.hitsRequired} hits`, ctx.a.moveId !== 'Ultimate',
      `5 charge, pressed ult -> moveId '${ctx.a.moveId}' (want anything but Ultimate)`);
  }
  {
    const ctx = duel(wid);
    landHits(ctx, ULTIMATE.hitsRequired);
    ctx.place(); ctx.a.setState('idle');
    ctx.m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: true, anyPress: true }));
    ctx.m.step();
    check(`${wid}: fires at full meter and spends it`, ctx.a.moveId === 'Ultimate' && ctx.a.ultCharge === 0,
      `moveId '${ctx.a.moveId}', charge left ${ctx.a.ultCharge}, invincible ${ctx.a.invincible}f`);
  }
  // ---- 7. every weapon's ultimate runs to completion and deals damage ----
  // Distance matters: a gun's muzzle sits 2.7 studs out, so point-blank is exactly where its
  // bullets spawn PAST you. Each ultimate is tested at the range it is meant to be used at.
  const RANGE = { Sword: 3.0, Scythe: 4.0, Blasters: 12, Grimoire: 9, Axe: 4.0, Pike: 10,
    Gauntlets: 4.0, Hammer: 4.0, Longbow: 10, Flail: 5.0, Shield: 3.0, Daggers: 3.5 };
  for (const w of WEAPONS) {
    if (!w.moves.Ultimate) continue;
    const ctx = duel(w.id);
    const { m, a, v } = ctx;
    const d = RANGE[w.id] ?? 4;
    a.x = -d / 2; v.x = d / 2; a.facing = 1; v.facing = -1;
    for (const f of [a, v]) { f.onGround = true; f.platform = m.stage.main; f.y = 0; f.vx = 0; f.vy = 0; f.invincible = 0; }
    v.setState('idle'); v.percent = 0;
    a.setState('idle'); a.ultCharge = ULTIMATE.hitsRequired;
    m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: true, anyPress: true }));
    m.step(); m._input.clear('p0');
    let frames = 0;
    for (let i = 0; i < 400 && (a.state === 'attack' || a.hitlag > 0); i++) {
      // Deadeye is a stance, not a swing: it holds three rounds and fires one per press of the
      // ultimate key. Every other ultimate ignores the button once it has started, so pressing
      // it on a timer here tests the one that reads it without changing the other three.
      if (i % 20 === 0) m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: true, anyPress: true }));
      else m._input.clear('p0');
      // A REFLECT ultimate deals nothing to somebody who never attacks - that IS the move. Against
      // a motionless victim this probe would measure 0% and call Aegis broken, when what it had
      // actually measured is the absence of an opponent. So the victim throws lights at it.
      if (w.moves.Ultimate.kind === 'reflect') m._input.set('p1', Object.assign({}, EMPTY_IN, { light: i % 10 === 0, anyPress: i % 10 === 0 }));
      m.step(); frames++;
      // keep the victim on stage, so the number read is damage and not how far they flew
      if (v.y < -4) { v.y = 0; v.vy = 0; v.onGround = true; v.platform = m.stage.main; }
    }
    // The floor is one connected component of the move, not all of it. Astral Rain spreads its
    // orbs with `jitter` and its blast radius is deliberately small enough that a sprinting
    // fighter can leave it, so "both orbs always land" is not a property the game has — asserting
    // it made this test fail roughly one run in six. What this check is for is that the ultimate
    // runs to completion and reaches the victim at all; the full-damage numbers are pinned by the
    // kill-percent bands in check 13 and the per-opponent orb count in check 12.
    const floor = w.id === 'Grimoire' ? 13 : 18;
    // For a reflect, the damage still lands on the fighter the probe calls the victim - because
    // the victim is the one swinging, and a reflect hurts whoever swung. Reading the Shield
    // player's own percent instead measured a fighter nothing had touched.
    const dealt = v.percent;
    check(`${w.id}: the ultimate resolves and connects`, frames > 0 && a.state !== 'attack' && dealt >= floor,
      `${w.moves.Ultimate.label}: ran ${frames}f from ${d} studs, dealt ${v.percent}% (want ${floor}+), ended '${a.state}'`);
  }
}


// ---- 8. the knockback multiplier is real, and it multiplies rather than replaces ----
// Each ultimate is specified as "the knockback they already have, times N". That is a different
// promise from "a big fixed launch": it has to scale with the victim's percent, so the same move
// is a knock-back at 0% and a kill at 90%. Measured, not read off the data.
{
  const { Combat } = await import('../src/engine/combat.js');
  // Capture the launch speed the engine actually hands the victim, at two very different percents.
  function launchOf(weaponId, percent) {
    const ctx = duel(weaponId);
    const { m, a, v } = ctx;
    const d = RANGE_FOR[weaponId];
    a.x = -d / 2; v.x = d / 2; a.facing = 1; v.facing = -1;
    for (const f of [a, v]) { f.onGround = true; f.platform = m.stage.main; f.y = 0; f.vx = 0; f.vy = 0; f.invincible = 0; }
    v.setState('idle'); v.percent = percent;
    a.setState('idle'); a.ultCharge = ULTIMATE.hitsRequired;
    let biggest = 0;
    const seen = [];
    m.subscribe ? null : null;
    m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: true, anyPress: true }));
    m.step();
    const kind = WEAPONS.find((w) => w.id === weaponId).moves.Ultimate.kind;
    // The sniper's setup rounds are deliberately damped (sniper.setupMul) so that only the last
    // round in the magazine launches. This probe takes the BIGGEST launch it sees, and at 90% the
    // finisher sent the victim clear of the next round - so the biggest launch on record was a
    // setup round and the move measured as scaling DOWNWARD. Cutting the magazine to one leaves
    // only the finisher, which is the hit whose scaling this assertion is about. It is clamped
    // inside the loop, not before it: the stance loads the magazine on its first ACTIVE frame,
    // eighteen frames after activation, so a write before the loop is overwritten.
    const oneShot = () => { if (kind === 'sniper' && a.ultShots > 1) a.ultShots = 1; };
    const reflects = kind === 'reflect';
    for (let i = 0; i < 400 && (a.state === 'attack' || a.hitlag > 0); i++) {
      oneShot();
      if (i % 20 === 0) m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: true, anyPress: true }));
      else m._input.clear('p0');
      // Same reason as the connect probe: a reflect launches nobody unless somebody swings at it.
      if (reflects) m._input.set('p1', Object.assign({}, EMPTY_IN, { light: i % 10 === 0, anyPress: i % 10 === 0 }));
      m.step();
      for (const e of m.events) if (e.type === 'hit' && e.victim === v.index) { biggest = Math.max(biggest, e.launch); seen.push(e.launch); }
      m.events.length = 0;
      if (v.y < -4) { v.y = 0; v.vy = 0; v.onGround = true; v.platform = m.stage.main; }
    }
    return biggest;
  }
  // Each ultimate is measured at the range it is meant to be used at; a weapon missing from
  // this map positioned its victim at NaN and silently measured a launch of zero.
  const RANGE_FOR = { Sword: 3.0, Scythe: 4.0, Blasters: 12, Grimoire: 9, Axe: 4.0, Pike: 10,
    Gauntlets: 3.0, Hammer: 4.0, Longbow: 9, Flail: 5.0, Shield: 3.0, Daggers: 3.0 };
  // And the warning above is not decoration: six weapons were added at once and every one of them
  // reported a launch of zero until it appeared here. The check below now fails loudly on a weapon
  // this map does not know about, rather than quietly measuring NaN.
  const unranged = WEAPONS.filter((w) => RANGE_FOR[w.id] == null).map((w) => w.id);
  if (unranged.length) check('every weapon has an ultimate test range', false,
    `${unranged.join(', ')} missing from RANGE_FOR — their ultimates are being measured at NaN studs`);
  const rows = [];
  let ok = true;
  for (const w of WEAPONS) {
    const lo = launchOf(w.id, 0), hi = launchOf(w.id, 90);
    const ratio = hi / Math.max(0.01, lo);
    // 1.4x is the floor. A fixed launch would sit at 1.00 no matter the percent; the four
    // land between 1.45 and 1.89, which is the whole difference between a finisher and a shove.
    if (!(lo > 0 && hi > lo * 1.4)) ok = false;
    rows.push(`${w.id} ${lo.toFixed(0)}->${hi.toFixed(0)} (x${ratio.toFixed(2)})`);
  }
  check('ultimate knockback scales with the victim percent', ok,
    `launch at 0% vs 90%: ${rows.join(', ')} — a multiplier, not a fixed launch`);
}

// ---- 9. Colossus: the crater reaches well past the blade ----
{
  const ctx = duel('Sword');
  const { m, a, v } = ctx;
  const U = a.char.moves.Ultimate;
  const reach = U.crater.step * (U.crater.count - 1);
  // stand a victim out past the sword's own arc but inside the shockwave
  a.x = -reach + 2; v.x = 2; a.facing = 1; v.facing = -1;
  for (const f of [a, v]) { f.onGround = true; f.platform = m.stage.main; f.y = 0; f.vx = 0; f.vy = 0; f.invincible = 0; }
  v.setState('idle'); v.percent = 0;
  a.setState('idle'); a.ultCharge = ULTIMATE.hitsRequired;
  m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: true, anyPress: true }));
  m.step(); m._input.clear('p0');
  for (let i = 0; i < 200 && (a.state === 'attack' || a.hitlag > 0); i++) m.step();
  const gap = Math.abs(v.x - a.x);
  check('Colossus: the crater reaches past the blade', v.percent > 0 && U.weaponScale === 2,
    `victim ${gap.toFixed(0)} studs away (blade reaches ~5) took ${v.percent}%, blade drawn at ${U.weaponScale}x`);
}

// ---- 10. Soul Harvest: exactly the two nearest, dragged to one point ----
{
  const m = makeMatch({ loadouts: [['Classic', 'Scythe'], ['Noir', 'Sword'], ['Ember', 'Sword'], ['Moss', 'Sword']] });
  skipCountdown(m);
  for (let i = 0; i < 200; i++) m.step();
  const [a, n1, n2, far] = m.fighters;
  const put = (f, x) => { f.x = x; f.y = 0; f.vx = 0; f.vy = 0; f.onGround = true; f.platform = m.stage.main; f.setState('idle'); f.invincible = 0; f.percent = 0; };
  put(a, 0); put(n1, 6); put(n2, -7); put(far, 27);
  a.facing = 1; a.ultCharge = ULTIMATE.hitsRequired;
  m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: true, anyPress: true }));
  m.step(); m._input.clear('p0');
  let minSpread = 999;
  for (let i = 0; i < 200 && (a.state === 'attack' || a.hitlag > 0); i++) {
    m.step();
    if (a.ultHeld && a.ultHeld.length === 2) minSpread = Math.min(minSpread, Math.hypot(n1.x - n2.x, n1.cy - n2.cy));
  }
  check('Soul Harvest: takes the two nearest and crushes them together', minSpread < 3 && far.percent === 0 && n1.percent > 15 && n2.percent > 15,
    `the two nearest closed to ${minSpread.toFixed(1)} studs apart and took ${n1.percent}% / ${n2.percent}%; the fighter 27 studs away took ${far.percent}%`);
}

// ---- 11. Deadeye: three rounds, one per press, and they track through cover ----
{
  const m = makeMatch({ stageId: 'Saltflat', loadouts: [['Classic', 'Blasters'], ['Noir', 'Sword']] });
  skipCountdown(m);
  for (let i = 0; i < 200; i++) m.step();
  const [a, v] = m.fighters;
  // the bunker on Saltflat sits at x=-16: put the shooter on one side of it and the mark on the other
  a.x = -34; v.x = 2; a.facing = 1; v.facing = -1;
  for (const f of [a, v]) { f.onGround = true; f.platform = m.stage.main; f.y = 0; f.vx = 0; f.vy = 0; f.invincible = 0; }
  v.setState('idle'); v.percent = 0;
  a.setState('idle'); a.ultCharge = ULTIMATE.hitsRequired;
  m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: true, anyPress: true }));
  m.step(); m._input.clear('p0');
  let shots = 0, marked = false;
  for (let i = 0; i < 300 && (a.state === 'attack' || a.hitlag > 0 || m.combat.projectiles.length); i++) {
    if (i % 20 === 0) m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: true, anyPress: true }));
    else m._input.clear('p0');
    m.step();
    if (a.ultTarget === v) marked = true;
    for (const e of m.events) if (e.type === 'snipe') shots++;
    m.events.length = 0;
    if (v.y < -4) { v.y = 0; v.vy = 0; v.onGround = true; v.platform = m.stage.main; }
  }
  check('Deadeye: three tracked rounds, and cover does not stop them', shots === 3 && marked && v.percent >= 39,
    `painted the nearest fighter, fired ${shots} rounds (want 3) across the Saltflat bunker for ${v.percent}%`);
}

// ---- 12. Starfall: two orbs for every living opponent ----
{
  const m = makeMatch({ loadouts: [['Classic', 'Grimoire'], ['Noir', 'Sword'], ['Ember', 'Sword'], ['Moss', 'Sword']] });
  skipCountdown(m);
  for (let i = 0; i < 200; i++) m.step();
  const a = m.fighters[0];
  const foes = m.fighters.slice(1);
  a.x = 0; a.y = 0; a.onGround = true; a.platform = m.stage.main; a.setState('idle');
  foes.forEach((f, i) => { f.x = -18 + i * 16; f.y = 0; f.vx = 0; f.vy = 0; f.onGround = true; f.platform = m.stage.main; f.setState('idle'); f.percent = 0; f.invincible = 0; });
  a.ultCharge = ULTIMATE.hitsRequired;
  m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: true, anyPress: true }));
  m.step(); m._input.clear('p0');
  const perTarget = new Map();
  for (let i = 0; i < 300 && (a.state === 'attack' || a.hitlag > 0 || m.combat.projectiles.length); i++) {
    m.step();
    for (const e of m.events) if (e.type === 'starfall') perTarget.set(e.target, (perTarget.get(e.target) || 0) + 1);
    m.events.length = 0;
  }
  const counts = foes.map((f) => perTarget.get(f.index) || 0);
  const hurt = foes.filter((f) => f.percent > 0).length;
  check('Starfall: two orbs for every opponent, wherever they are standing', counts.every((c) => c === 2) && hurt === 3,
    `orbs per opponent: ${counts.join('/')} (want 2 each); ${hurt} of 3 were hit, spread across 34 studs`);
}


// ---- 13. KILL PERCENT, pinned ----
// Every other assertion in this file measures plumbing, and all sixteen of them passed while
// Colossus killed at 226% (a same-frame crater was overwriting its own blade's launch) and Soul
// Harvest killed two people at 17%. Damage thresholds cannot catch that. Kill percent can.
//
// This used to be pinned per HITBOX through balance.koPercent, and that could only ever describe
// the ultimates whose kill is one launch off one sub-object. It said nothing about the six whose
// kill comes out of a mechanic - a magazine, a stack of marks, a chain that drags. Measured for
// real, four of those killed between 4% and 85% while this test was green, and Upheaval could not
// kill at ANY percent up to 400.
//
// So it fires the actual move at a victim standing centre stage and asks whether the LAUNCH took
// them out - they have to leave the blast box within hitstun + 40 frames of the last hit, the same
// rule balance.killsAt uses. Anything looser just measures a do-nothing dummy drifting off the
// edge, which every horizontal launch does eventually.
{
  const RANGE_FOR = { Sword: 3.0, Scythe: 4.0, Blasters: 12, Grimoire: 9, Axe: 4.0, Pike: 10,
    Gauntlets: 3.0, Hammer: 4.0, Longbow: 9, Flail: 5.0, Shield: 3.0, Daggers: 3.0 };

  function ultKills(weaponId, percent) {
    const m = makeMatch({ loadouts: [['Classic', weaponId], ['Noir', 'Sword']], stocks: 3 });
    skipCountdown(m);
    for (let i = 0; i < 120; i++) m.step();
    const [a, v] = m.fighters;
    const d = RANGE_FOR[weaponId];
    a.x = -d / 2; v.x = d / 2; a.facing = 1; v.facing = -1;
    for (const f of [a, v]) { f.onGround = true; f.platform = m.stage.main; f.y = 0; f.vx = 0; f.vy = 0; f.invincible = 0; }
    v.setState('idle'); v.percent = percent;
    a.setState('idle'); a.ultCharge = ULTIMATE.hitsRequired;
    // A reflect launches nobody unless somebody swings at it.
    const reflects = WEAPONS.find((w) => w.id === weaponId).moves.Ultimate.kind === 'reflect';
    m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: true, anyPress: true }));
    m.step();
    let pct = v.percent, deadline = -1;
    for (let i = 0; i < 700; i++) {
      // The sniper needs a trigger pull per round, so the button is re-pressed periodically.
      if (i % 20 === 0) m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: true, anyPress: true }));
      else m._input.clear('p0');
      if (reflects && i < 120) m._input.set('p1', Object.assign({}, EMPTY_IN, { light: i % 10 === 0, anyPress: i % 10 === 0 }));
      m.step();
      if (v.percent > pct) { pct = v.percent; deadline = i + v.hitstun + 40; }
      if (m.stage.outsideBlast(v) || v.stocks < 3 || !v.alive) return deadline >= 0 && i <= deadline;
      if (deadline >= 0 && i > deadline && a.state !== 'attack' && v.onGround) return false;
    }
    return false;
  }
  const ultKo = (weaponId) => {
    for (let p = 0; p <= 400; p += 5) if (ultKills(weaponId, p)) {
      for (let q = Math.max(0, p - 4); q <= p; q++) if (ultKills(weaponId, q)) return q;
      return p;
    }
    return null;
  };

  // [expected kill %, tolerance] - measured, then pinned. The band is +/-18 because a few of these
  // resolve through positioning (whether the third round still reaches, which column catches them)
  // and land a few points either side of a rerun.
  const EXPECT = { Sword: 134, Scythe: 161, Blasters: 131, Grimoire: 191, Axe: 155, Pike: 136,
    Gauntlets: 213, Hammer: 146, Longbow: 133, Flail: 148, Shield: 193, Daggers: 142 };
  // An ultimate is the biggest commitment in the game and it is allowed to be the thing that
  // closes a stock. It is not allowed to be a contact kill: before this floor existed, Deadeye
  // killed from 4%, Heartseeker from 21% and Exsanguinate from 24%, which meant twenty landed
  // hits bought a stock outright rather than the chance at one.
  const FLOOR = 120, CEILING = 260;
  const rows = [], bad = [];
  for (const w of WEAPONS) {
    const k = ultKo(w.id);
    const want = EXPECT[w.id];
    rows.push(`${w.moves.Ultimate.label} ${k === null ? 'NEVER' : k + '%'}${want == null ? ' (unpinned)' : ''}`);
    if (k === null) bad.push(`${w.id} cannot KO at all`);
    else if (k < FLOOR || k > CEILING) bad.push(`${w.id} kills at ${k}%, outside ${FLOOR}-${CEILING}`);
    else if (want != null && Math.abs(k - want) > 18) bad.push(`${w.id} kills at ${k}%, pinned at ${want}%`);
    else if (want == null) bad.push(`${w.id} has no pinned kill percent`);
  }
  check('every ultimate kills late, and every one of them kills', bad.length === 0,
    bad.length ? bad.join('; ') : rows.join(', '));
}

// ---- 14. the vortex hold is escapable ----
// 26 frames of no agency ending in a kill is only acceptable if the victim can fight it. A player
// mashing must get out; a player doing nothing must not.
{
  const still = (mash) => {
    const m = makeMatch({ loadouts: [['Classic', 'Scythe'], ['Noir', 'Sword']] });
    skipCountdown(m);
    for (let i = 0; i < 200; i++) m.step();
    const [a, v] = m.fighters;
    a.x = -3; v.x = 3; a.facing = 1; v.facing = -1;
    for (const f of [a, v]) { f.onGround = true; f.platform = m.stage.main; f.y = 0; f.vx = 0; f.vy = 0; f.invincible = 0; }
    v.setState('idle'); v.percent = 0; a.setState('idle'); a.ultCharge = ULTIMATE.hitsRequired;
    m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: true, anyPress: true }));
    m.step(); m._input.clear('p0');
    for (let i = 0; i < 220 && (a.state === 'attack' || a.hitlag > 0); i++) {
      // ~8.5 presses a second, which is a fast human mash. The first version of this test
      // alternated every single frame - 30 Hz, four times what a person can do - and so it
      // certified an escape that did not exist at any rate anyone could actually produce.
      if (mash) m._input.set('p1', Object.assign({}, EMPTY_IN, { jump: i % 14 === 0, dodge: i % 14 === 7, anyPress: i % 7 === 0 }));
      m.step();
    }
    return v.percent;
  };
  const passive = still(false), mashing = still(true);
  check('Soul Harvest: mashing breaks the hold, standing still does not', passive >= 18 && mashing === 0,
    `a victim who does nothing takes ${passive}%; a victim mashing jump and dodge takes ${mashing}% — the hold is a grab, not a cutscene`);
}

// ---- 15. an ultimate is not answered by holding one button, at ANY range ----
// The first version of this test asked "did the shield break OR did they take damage", once, at
// one distance. Colossus broke a shield at point blank and passed it — while at 9 to 17 studs its
// crater took 0% and left 34.9/50 shield, because the burst was never handed the move's
// shieldDamageMul. One distance is not a test; the outer half of a move is where the plumbing
// gets forgotten.
{
  // Three distances per weapon: point blank, mid, and the far edge of what the move reaches.
  // A weapon missing here used to throw rather than silently pass, which is the right failure.
  const RANGES = { Sword: [2.5, 9, 17], Scythe: [2.5, 8, 14], Blasters: [8, 20, 40], Grimoire: [0, 6, 14],
    // These must sit INSIDE the move's own reach. Reave's widest box reaches 8.4 studs and Lance
    // Charge's now reaches 20 — probing at 11 and 30 was asking whether a shield beats an attack
    // that cannot touch you, which it obviously does.
    Axe: [2.5, 5, 8], Pike: [6, 12, 18],
    Gauntlets: [2.5, 4, 6], Hammer: [3, 5, 8], Longbow: [6, 12, 20],
    // Exsanguinate marks at close range only - its window hitbox reaches 4.8 studs, so probing at
    // 6 measured a miss and called it a clean block.
    Flail: [3, 6, 10], Shield: [2.5, 4, 7], Daggers: [2.5, 3.5, 4.5] };
  // Second per-weapon map in this file that a new weapon has to be added to. Missing from the one
  // above, a weapon measured a launch of NaN; missing from this one it threw outright. Both now
  // say so by name instead.
  const unprobed = WEAPONS.filter((w) => !RANGES[w.id]).map((w) => w.id);
  if (unprobed.length) check('every weapon has shield-probe ranges', false,
    `${unprobed.join(', ')} missing from RANGES — the shield check cannot run for them`);
  const blocked = [];
  const rows = [];
  for (const w of WEAPONS) {
    for (const d of RANGES[w.id]) {
      const m = makeMatch({ loadouts: [['Classic', w.id], ['Noir', 'Sword']] });
      skipCountdown(m);
      for (let i = 0; i < 200; i++) m.step();
      const [a, v] = m.fighters;
      a.x = -d / 2; v.x = d / 2; a.facing = 1; v.facing = -1;
      for (const f of [a, v]) { f.onGround = true; f.platform = m.stage.main; f.y = 0; f.vx = 0; f.vy = 0; f.invincible = 0; }
      v.setState('idle'); v.percent = 0; a.setState('idle'); a.ultCharge = ULTIMATE.hitsRequired;
      m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: true, anyPress: true }));
      m.step();
      let broke = false, lowest = 50;
      for (let i = 0; i < 340 && (a.state === 'attack' || a.hitlag > 0 || m.combat.projectiles.length); i++) {
        m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: i % 20 === 0, anyPress: i % 20 === 0 }));
        // A REFLECT ultimate does nothing at all to somebody who never attacks - that is the move,
        // not a bug in it. Holding shield against Aegis and reporting "blocked clean" measures the
        // absence of an opponent. So the defender shields AND swings, which is what anyone
        // actually does, and the question becomes whether shielding saved them.
        // A REFLECT ultimate does nothing at all to somebody who never attacks - that is the move,
        // not a bug in it - so the defender here shields AND periodically swings, which is what a
        // real player does. It cannot do both on the same frame: light + guardHeld is a GRAB in
        // this engine, so holding both produced a defender who only ever grabbed and the probe
        // measured a fighter who never attacked at all.
        const reflects = w.moves.Ultimate && w.moves.Ultimate.kind === 'reflect';
        // The no-guard stretch has to outlast INPUT_BUFFER (6 frames), or the buffered light meets
        // the returning guard and becomes a GRAB - and a grab cancels the ultimate outright, so
        // the probe was measuring "can you grab someone out of their ultimate" (yes, at close
        // range) rather than "can you block it". That is a real property of every ultimate in the
        // game and worth knowing, but it is not what this check is for.
        const swinging = reflects && i % 30 < 10;
        m._input.set('p1', swinging
          ? Object.assign({}, EMPTY_IN, { light: i % 30 === 0, anyPress: i % 30 === 0 })
          : Object.assign({}, EMPTY_IN, { guard: true, guardHeld: true, anyPress: true }));
        m.step();
        // The engine's broken-shield state is 'stunned', and it emits a `shieldbreak` event. This
        // loop watched for 'shieldbreak' and 'stun', neither of which exists, so a shield that
        // broke in ONE hit was recorded as having held: the shield resets to half on break, so
        // `lowest` never dipped under 25 either. The six original ultimates hid it by chipping the
        // bar down over many blocks; the war hammer breaks it outright and the flaw surfaced.
        for (const e of m.events) if (e.type === 'shieldbreak') broke = true;
        m.events.length = 0;
        lowest = Math.min(lowest, v.shield);
        if (v.shield <= 0 || v.state === 'stunned') broke = true;
      }
      // "Not a clean answer" means one of: the shield broke, it got through anyway, or holding it
      // cost at least half the bar. The outer ring of a shockwave should not break a full shield
      // - but it should not be free either, and 34.9/50 (what the unplumbed crater used to leave)
      // is free. 25 is the line: blocking any part of an ultimate costs you half your shield.
      const ok = broke || v.percent > 0 || lowest < 25;
      rows.push(`${w.id}@${d}: ${v.percent}% shield ${lowest.toFixed(0)}${broke ? ' BROKE' : ''}`);
      if (!ok) blocked.push(`${w.id} at ${d} studs (0%, shield ${lowest.toFixed(0)}/50)`);
    }
  }
  check('holding shield is not a free answer to an ultimate, at any range', blocked.length === 0,
    blocked.length ? `blocked clean: ${blocked.join('; ')}` : rows.join('  '));
}

// ---- no ultimate deals wildly more than the rest ----
//
// The Chain Flail's Anchor dealt 124% in a single activation - three times what any other ultimate
// in the game does - because a chain that is live along its whole length connects far more often
// than a swing does, and nothing measured total output. It only surfaced as a side effect of the
// knockback-scaling check: when a move adds a hundred percent by itself, what the victim started
// at stops mattering, and the scaling ratio collapses.
{
  const RANGE = { Sword: 3.0, Scythe: 4.0, Blasters: 12, Grimoire: 9, Axe: 4.0, Pike: 10,
    Gauntlets: 4.0, Hammer: 4.0, Longbow: 10, Flail: 5.0, Shield: 3.0, Daggers: 3.5 };
  const rows = [], bad = [];
  for (const w of WEAPONS) {
    if (!w.moves.Ultimate) continue;
    const { m, a, v } = duel(w.id);
    const d = RANGE[w.id] ?? 4;
    a.x = -d / 2; v.x = d / 2; a.facing = 1; v.facing = -1;
    for (const f of [a, v]) { f.onGround = true; f.platform = m.stage.main; f.y = 0; f.vx = 0; f.vy = 0; f.invincible = 0; }
    v.setState('idle'); v.percent = 0;
    a.setState('idle'); a.ultCharge = ULTIMATE.hitsRequired;
    m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: true, anyPress: true }));
    m.step();
    const reflects = w.moves.Ultimate.kind === 'reflect';
    for (let i = 0; i < 400 && (a.state === 'attack' || a.hitlag > 0); i++) {
      if (i % 20 === 0) m._input.set('p0', Object.assign({}, EMPTY_IN, { ult: true, anyPress: true }));
      else m._input.clear('p0');
      if (reflects) m._input.set('p1', Object.assign({}, EMPTY_IN, { light: i % 10 === 0, anyPress: i % 10 === 0 }));
      m.step(); m.events.length = 0;
      if (v.y < -4) { v.y = 0; v.vy = 0; v.onGround = true; v.platform = m.stage.main; }
    }
    rows.push(`${w.moves.Ultimate.label} ${Math.round(v.percent)}%`);
    // Reave is the heaviest of the original six at 49%. Twice that is a different kind of move.
    if (v.percent > 70) bad.push(`${w.id}'s ${w.moves.Ultimate.label} deals ${Math.round(v.percent)}% in one activation`);
  }
  check('no ultimate deals wildly more than the rest', bad.length === 0,
    bad.length ? bad.join('; ') + ' — the rest sit between 18% and 55%' : rows.join(', '));
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
