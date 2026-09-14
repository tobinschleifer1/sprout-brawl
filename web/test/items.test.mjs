// ITEMS, measured in the engine.
//
// The old set were Sprout Brawl leftovers and, more importantly, they did not work: over eight
// four-player bot matches THIRTY-EIGHT items spawned, ZERO were picked up and thirty-four
// despawned untouched. Nothing in ai.js ever reached for one, `pickup` was declared in the input
// frame but bound to no key and read by nothing, and it was not in the input buffer either - so
// even the button that did exist could not have worked. Three separate layers of the same feature
// were dead at once and the only symptom was that items seemed pointless.
//
// So the first thing this file checks is that items are REACHED, in real matches, by real bots.
// Everything after that measures what each one actually does.
import { makeMatch, skipCountdown } from './harness.mjs';
import { ITEMS, ITEM_LIST } from '../src/data/items.js';
import { ITEM_ART_IDS } from '../src/render2d/items2d.js';
import { ITEMS as ITEM_CFG } from '../src/config.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };

const AV = ['Classic', 'Noir', 'Ember', 'Moss'];
function itemMatch(opts = {}) {
  const m = makeMatch({ mode: 'StockFFA', stocks: opts.stocks ?? 3, stageId: opts.stageId,
    loadouts: (opts.weapons || ['Sword', 'Scythe']).map((w, i) => [AV[i % 4], w]) });
  m.itemsOn = true;
  if (opts.bots !== false) m.fighters.forEach((f) => { f.isBot = true; f.botLevel = opts.level || 'hard'; });
  skipCountdown(m);
  return m;
}

// Put a specific item straight into a fighter's hands and give them a live opponent.
//
// Both fighters are planted on the MAIN FLOOR first. Fighters spawn on the soft platforms high
// above it, and moving one in x drops it off - the first version of this helper threw a Lodestone
// eighteen studs over the head of an opponent who was still falling, and every projectile check
// failed for that reason rather than for anything to do with the items.
function withItem(id, setup = {}) {
  const m = itemMatch({ bots: false, weapons: setup.weapons || ['Sword', 'Scythe'] });
  const [a, b] = m.fighters;
  const ax = setup.ax ?? -4, bx = setup.bx ?? 4;
  for (const [who, x] of [[a, ax], [b, bx]]) { who.x = x; who.y = 6; who.vx = 0; who.vy = 0; }
  for (let i = 0; i < 240 && !(a.onGround && b.onGround && a.y < 1 && b.y < 1); i++) {
    m.step(); m.events.length = 0;
    a.x = ax; b.x = bx; a.vx = 0; b.vx = 0;
  }
  a.facing = 1; b.facing = -1;
  if (setup.percent != null) b.percent = setup.percent;
  m.combat.giveItem(a, ITEMS[id]);
  return { m, a, b };
}

// Freeze a projectile in place, so an interaction can be tested without racing it across the
// stage. Used for the keg, whose whole point is what happens while it is in the air.
function park(p, x, y) { p.x = x; p.y = y; p.vx = 0; p.vy = 0; p.gravity = 0; p.rect = { x1: x - p.w / 2, x2: x + p.w / 2, y1: y - p.h / 2, y2: y + p.h / 2 }; }

// ---- 1. bots pick items up and use them ----
{
  const t = { itemspawn: 0, pickup: 0, throwitem: 0, rivet: 0, placeitem: 0, spring: 0, lodestone: 0, bulwark: 0 };
  for (let g = 0; g < 6; g++) {
    const m = itemMatch({ weapons: ['Sword', 'Scythe', 'Axe', 'Pike'], level: 'hard' });
    for (let i = 0; i < 60 * 200 && m.state !== 'results'; i++) {
      m.step();
      for (const e of m.events) if (t[e.type] !== undefined) t[e.type]++;
      m.events.length = 0;
    }
  }
  const used = t.throwitem + t.rivet + t.placeitem;
  check('bots pick items up and use them', t.itemspawn > 0 && t.pickup > 0 && used > 0,
    t.pickup === 0 ? `${t.itemspawn} items spawned and not one was picked up — the item system is scenery again`
      : `over six four-player matches: ${t.itemspawn} spawned, ${t.pickup} picked up, ${used} used ` +
        `(${t.throwitem} thrown, ${t.rivet} rivets, ${t.placeitem} plates), ${t.spring} spring launches, ` +
        `${t.lodestone} lodestones stuck, ${t.bulwark} hits eaten by a Bulwark`);
}

// ---- 2. every item is reachable, and every one has art ----
{
  const ids = ITEM_LIST.map((d) => d.id);
  const artless = ids.filter((id) => !ITEM_ART_IDS.includes(id));
  const seen = new Set();
  for (let g = 0; g < 8 && seen.size < ids.length; g++) {
    const m = itemMatch({ weapons: ['Sword', 'Scythe', 'Axe', 'Pike'], level: 'hard' });
    for (let i = 0; i < 60 * 200 && m.state !== 'results'; i++) {
      m.step();
      for (const e of m.events) if (e.type === 'itemspawn') seen.add(e.item);
      m.events.length = 0;
    }
  }
  const never = ids.filter((id) => !seen.has(id));
  check('every item can spawn, and every item has its own art', never.length === 0 && artless.length === 0,
    artless.length ? `no drawing for: ${artless.join(', ')} — it would fall back to a grey rectangle`
      : never.length ? `never spawned in eight matches: ${never.join(', ')}`
        : `${ids.length} items, all spawned in play and all drawn: ${ids.join(', ')}`);
}

// ---- 3. the Blast Keg goes off when ANYONE hits it ----
// The item's whole identity: you throw it, and then it belongs to the situation rather than to you.
{
  const { m, a, b } = withItem('BlastKeg');
  a.buffer.light = 6;
  for (let i = 0; i < 6; i++) { m.step(); m.events.length = 0; }
  const flying = m.combat.projectiles.find((p) => p.volatile);
  let boom = false, hitBy = null;
  if (flying) {
    // the OPPONENT swings at it. The keg is parked first: a keg travelling at 30 studs a second
    // is four studs away by the time a light attack's hitbox exists, which tests the chase rather
    // than the detonation.
    park(flying, b.x - 1.6, b.y + 2.6);
    b.facing = -1; b.setState('idle'); b.buffer.light = 6;
    for (let i = 0; i < 40 && !boom; i++) {
      m.step();
      for (const e of m.events) if (e.type === 'explosion') { boom = true; hitBy = 'the opponent'; }
      m.events.length = 0;
    }
  }
  check('a thrown Blast Keg can be set off by the other player', !!flying && boom,
    !flying ? 'the keg never left the hand' : boom ? `the keg was in the air and ${hitBy} detonated it early` : 'the opponent hit the keg and nothing happened');
}

// ---- 4. the Rivet Gun cannot kill, and the Blast Keg can ----
// Two items, opposite jobs, and the numbers have to say so rather than the comments.
{
  const koAt = (id, fire) => {
    for (let pc = 0; pc <= 300; pc += 20) {
      const { m, a, b } = withItem(id, { percent: pc, bx: 3 });
      fire(m, a, b);
      let ko = false;
      for (let i = 0; i < 60 * 8 && !ko; i++) {
        m.step();
        for (const e of m.events) if (e.type === 'ko' && e.fighter === b.index) ko = true;
        m.events.length = 0;
      }
      if (ko) return pc;
    }
    return null;
  };
  const rivetKO = koAt('RivetGun', (m, a) => { for (let i = 0; i < 8; i++) { a.buffer.light = 6; for (let k = 0; k < 8; k++) { m.step(); m.events.length = 0; } } });
  const kegKO = koAt('BlastKeg', (m, a, b) => {
    a.buffer.light = 6;
    for (let i = 0; i < 10; i++) {
      m.step(); m.events.length = 0;
      const p = m.combat.projectiles.find((q) => q.volatile);
      if (p) { park(p, b.x, b.y + 2); break; }          // measure the blast, not the throw arc
    }
  });
  check('the Rivet Gun chips and the Blast Keg kills', rivetKO === null && kegKO !== null && kegKO <= 140,
    `Rivet Gun: ${rivetKO === null ? 'never killed, even at 300% with the whole magazine' : 'killed at ' + rivetKO + '%'} | ` +
    `Blast Keg: ${kegKO === null ? 'never killed at all' : 'kills from ' + kegKO + '%'}`);
}

// ---- 5. the Bulwark only covers the front ----
{
  const hit = (fromBehind) => {
    const { m, a, b } = withItem('Bulwark');
    // b attacks a, from in front or from behind
    b.x = fromBehind ? a.x - 3 : a.x + 3;
    b.facing = fromBehind ? 1 : -1;
    a.facing = 1;
    const before = a.percent;
    b.setState('idle'); b.buffer.heavy = 6;
    for (let i = 0; i < 70; i++) { m.step(); m.events.length = 0; }
    return { taken: a.percent - before, hp: a.item ? a.item.hp : 0 };
  };
  const front = hit(false), back = hit(true);
  const worked = front.taken > 0 && back.taken > 0 && front.taken < back.taken * 0.6;
  check('a Bulwark covers the front and nothing else', worked,
    `hit from the front: ${front.taken.toFixed(1)}% taken, shield down to ${front.hp} hp | ` +
    `hit from behind: ${back.taken.toFixed(1)}% taken` +
    (worked ? '' : ' — the shield is not discriminating by side'));
}

// ---- 6. a Spring Plate launches whoever lands on it, including the player who placed it ----
{
  const { m, a, b } = withItem('SpringPlate');
  a.buffer.light = 6;
  for (let i = 0; i < 20; i++) { m.step(); m.events.length = 0; }
  const placed = m.combat.plates.length === 1;
  let ownerUp = 0, enemyUp = 0;
  if (placed) {
    const pl = m.combat.plates[0];
    for (const [who, tag] of [[a, 'owner'], [b, 'enemy']]) {
      who.x = pl.x; who.y = pl.y + 1; who.vy = -10; who.onGround = false; who.setState('air');
      let best = 0;
      for (let i = 0; i < 30; i++) { m.step(); m.events.length = 0; best = Math.max(best, who.vy); }
      if (tag === 'owner') ownerUp = best; else enemyUp = best;
    }
  }
  check('a Spring Plate launches anyone who lands on it', placed && ownerUp > 40 && enemyUp > 40,
    !placed ? 'the plate was never placed' : `owner launched at ${ownerUp.toFixed(0)} studs/s, opponent at ${enemyUp.toFixed(0)} — it does not care who put it there`);
}

// ---- 7. the Lodestone does almost no damage and ruins the recovery ----
// The point of the item, stated as the two measurements that make it true.
{
  const { m, a, b } = withItem('Lodestone', { bx: 6 });
  const before = b.percent;
  a.buffer.light = 6;
  let stuck = false;
  for (let i = 0; i < 90 && !stuck; i++) {
    m.step();
    for (const e of m.events) if (e.type === 'lodestone') stuck = true;
    m.events.length = 0;
  }
  const dealt = b.percent - before;
  // Terminal fall speed, with and without. Measured as a VELOCITY rather than as a distance: the
  // first version dropped a fighter from forty studs and measured how far it got in a second, and
  // both cases returned exactly 13.0 studs because the fighter landed on a platform on the way
  // down. It was measuring the stage, not the item.
  const terminal = (weighted) => {
    const g = itemMatch({ bots: false });
    const v = g.fighters[1];
    for (let i = 0; i < 30; i++) { g.step(); g.events.length = 0; }
    if (weighted) { v.effects.lodestone = 600; v.effects.lodestoneDef = ITEMS.Lodestone.stick; }
    let worst = 0;
    for (let i = 0; i < 90; i++) {
      v.y = 40; v.onGround = false; v.platform = null;      // keep it in free air the whole time
      if (v.state !== 'air') v.setState('air');
      g.step(); g.events.length = 0;
      worst = Math.min(worst, v.vy);
    }
    return -worst;
  };
  const plain = terminal(false), heavy = terminal(true);
  check('the Lodestone deals nothing and makes them fall like a stone', stuck && dealt <= 4 && heavy > plain * 1.3,
    !stuck ? 'the lodestone never stuck to anyone'
      : `${dealt.toFixed(0)}% dealt, and terminal fall speed goes from ${plain.toFixed(0)} to ${heavy.toFixed(0)} studs/s — ${(heavy / plain).toFixed(2)}x`);
}

// ---- 8. no item is a strictly better version of another ----
// The set is built one-verb-per-item; this is the check that keeps it that way, because the easy
// mistake is adding a sixth item that throws for damage like the first one.
{
  const verbs = {};
  for (const d of ITEM_LIST) (verbs[d.kind] = verbs[d.kind] || []).push(d.id);
  const dupes = Object.entries(verbs).filter(([, v]) => v.length > 1);
  // two throwers are allowed only if one does no damage at all
  const bad = dupes.filter(([kind, v]) => {
    if (kind !== 'throw') return true;
    const dmg = v.map((id) => (ITEMS[id].explode ? ITEMS[id].explode.damage : 0));
    return dmg.filter((x) => x > 6).length > 1;
  });
  check('every item owns a different verb', bad.length === 0,
    bad.length ? bad.map(([k, v]) => `${v.join(' and ')} both do "${k}" the same way`).join('; ')
      : Object.entries(verbs).map(([k, v]) => `${k}: ${v.join(', ')}`).join(' | '));
}

// ---- 9. items actually turn up during a match ----
{
  const m = itemMatch({ weapons: ['Sword', 'Scythe', 'Axe', 'Pike'], level: 'normal' });
  let spawns = 0, frames = 0;
  for (; frames < 60 * 180 && m.state !== 'results'; frames++) {
    m.step();
    for (const e of m.events) if (e.type === 'itemspawn') spawns++;
    m.events.length = 0;
  }
  const secs = frames / 60;
  const expected = Math.floor(secs / ITEM_CFG.spawnEvery);
  check('items appear often enough to matter', spawns >= Math.max(2, expected * 0.5),
    `${spawns} items in ${secs.toFixed(0)}s of play, one every ${ITEM_CFG.spawnEvery}s nominal (was 25s, and most of those timed out untouched)`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
