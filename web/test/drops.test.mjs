// WEAPON DROPS (DROPS in config.js), measured in the engine.
//
//   * off unless a match asks: no kit, no drops, the one weapon all match - the game as it was;
//   * on: every fighter starts on fists, with no ultimate; the meter waits for a weapon;
//   * drops start at DROPS.firstAt, come every spawnEvery, cap at dropsOnStage, land on a
//     platform and fade after despawnAfter seconds on the ground;
//   * the pickup button over a drop arms you with your FIRST weapon - its size, weight, jumps and
//     mechanic, not the fists'; armed, it throws: the weapon leaves on the throw's first active
//     frame, you are on fists from that frame, it hits for damage and lands as a drop that looks
//     like it; the next drop arms you with your OTHER weapon;
//   * an item in reach is taken before a throw; pickup and throw work in the air, and an air throw
//     that lands before letting go still throws; a thrown weapon off the stage is gone; a lost
//     stock loses the weapon in hand;
//   * the fists never kill early (their growth is under half the weakest real heavy's);
//   * the same seed and inputs drop the same drops in the same places.
//
//     node test/drops.test.mjs
import { makeMatch, skipCountdown } from './harness.mjs';
import { DROPS, dropsOnStage, FRAME } from '../src/config.js';
import { WEAPONS, FISTS } from '../src/data/weapons/index.js';
import { ITEMS } from '../src/data/items.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };

const armedMatch = (o = {}) => skipCountdown(makeMatch({ armed: o.armed || [['Classic', ['Sword', 'Gauntlets']], ['Noir', ['Hammer', 'Daggers']]], seed: o.seed, stocks: o.stocks }));
// Both fighters stood on the main floor, still, facing each other; no drops yet, the clock reset.
function planted(o = {}) {
  const m = armedMatch(o);
  const [a, b] = m.fighters;
  const ax = o.ax ?? -4, bx = o.bx ?? 4;
  for (const [who, x] of [[a, ax], [b, bx]]) { who.x = x; who.y = 6; who.vx = 0; who.vy = 0; who.invincible = 0; }
  for (let i = 0; i < 240 && !(a.onGround && b.onGround && a.y < 1 && b.y < 1); i++) {
    m.step(); m.events.length = 0;
    a.x = ax; b.x = bx; a.vx = 0; b.vx = 0;
  }
  a.facing = 1; b.facing = -1; a.invincible = 0; b.invincible = 0;
  m.combat.drops.length = 0; m.combat.dropTimer = -9999;     // drops only where a check puts them
  return { m, a, b };
}
const press = (m, who, p) => { m._input.set(`p${who.index}`, p); m.step(); m._input.clear(`p${who.index}`); };
const run = (m, frames) => { for (let i = 0; i < frames; i++) m.step(); };
const events = (m, type) => m.events.filter((e) => e.type === type);

// ---- off unless asked ----
{
  const m = skipCountdown(makeMatch({}));
  run(m, 60 * 12);
  const f = m.fighters[0];
  check('without weapon drops, the game is as it was', !m.dropsOn && !f.kit && f.char.weapon.id === 'Sword' && m.combat.drops.length === 0,
    `dropsOn=${m.dropsOn}, kit=${!!f.kit}, holding ${f.char.weapon.id}, ${m.combat.drops.length} drops after 12 s`);
}

// ---- fists to start, no ultimate ----
{
  const { m, a } = planted();
  const fistsOk = a.char.weapon.id === 'Fists' && a.armed === -1 && a.weight === a.fists.weight && a.h === a.fists.height;
  check('every fighter starts on fists', fistsOk, `holding ${a.char.weapon.id}, armed ${a.armed}`);
  a.ultCharge = 999;
  press(m, a, { ult: true });
  const denied = events(m, 'ultdenied');
  check('fists have no ultimate, and the meter waits', !a.char.moves.Ultimate && denied.some((e) => e.reason === 'unarmed') && a.ultCharge === 999 && a.state !== 'attack',
    `denied ${JSON.stringify(denied.map((e) => e.reason))}, meter ${a.ultCharge}, state ${a.state}`);
}

// ---- drop timing, cap, landing, despawn ----
{
  const m = armedMatch();
  let first = -1, frames = 0;
  const spawnedAt = [];
  for (; frames < 60 * 40; frames++) {
    m.step();
    for (const e of events(m, 'dropspawn')) { spawnedAt.push(frames + 1); if (first < 0) first = frames + 1; }
    m.events.length = 0;
  }
  const want = Math.round(DROPS.firstAt / FRAME);
  check('the first drop falls DROPS.firstAt seconds into the fight', Math.abs(first - want) <= 1, `first at frame ${first}, want ${want}`);
  const gap = spawnedAt.length > 1 ? spawnedAt[1] - spawnedAt[0] : -1;
  check('then one every DROPS.spawnEvery seconds while there is room', Math.abs(gap - Math.round(DROPS.spawnEvery / FRAME)) <= 1, `second drop ${gap} frames after the first`);
  const cap = dropsOnStage(2);
  let most = 0;
  const m2 = armedMatch({ seed: 4 });
  for (let i = 0; i < 60 * 60; i++) { m2.step(); most = Math.max(most, m2.combat.drops.length); }
  check(`at most dropsOnStage (${cap}) drops lie about at once`, most === cap, `peak ${most} drops with nobody taking them`);
}
{
  const { m } = planted();
  const d = m.combat.spawnDrop(0, 14);
  let fell = 0;
  while (!d.onGround && fell < 240) { m.step(); fell++; }
  const top = Math.max(...m.stage.platforms.filter((p) => p.x1 < 0 && p.x2 > 0 && p.top <= 14).map((p) => p.top));
  check('a drop falls and lands on the platform under it', d.onGround && Math.abs(d.y - top) < 1e-9, `onGround=${d.onGround} after ${fell} frames at y=${d.y.toFixed(2)}, platform top ${top}`);
  const life = DROPS.despawnAfter * 60;
  m.events.length = 0;
  run(m, life - 2);
  const still = m.combat.drops.includes(d);
  run(m, 2);
  check('and fades after DROPS.despawnAfter seconds on the ground, not before', still && !m.combat.drops.includes(d) && events(m, 'dropgone').length === 1,
    `there ${life - 1} frames after landing: ${still}; gone ${life + 1} frames after: ${!m.combat.drops.includes(d)}`);
}

// ---- arming, throwing, alternation ----
{
  const { m, a, b } = planted();
  m.combat.spawnDrop(a.x, a.y + 0.5);
  run(m, 10);
  press(m, a, { pickup: true });
  const k = a.kit[0];
  check('pickup over a drop arms you with your first weapon', a.armed === 0 && a.char === k && m.combat.drops.length === 0,
    `armed ${a.armed}, holding ${a.char.weapon.id}, ${m.combat.drops.length} drops left`);
  check('...and you are that weapon: size, weight, jumps and mechanic', a.weight === k.weight && a.h === k.height && a.r === k.radius && a.mech.id === k.mechanic.id,
    `weight ${a.weight}/${k.weight}, height ${a.h}/${k.height}, mechanic ${a.mech.id}/${k.mechanic.id}`);
  run(m, 20);
  b.percent = 40;
  const before = b.percent;
  press(m, a, { pickup: true });
  check('armed, pickup throws: a throw move, still holding until it lets go', a.state === 'attack' && a.moveId === 'WeaponThrow' && a.armed === 0,
    `state ${a.state} ${a.moveId}, armed ${a.armed}`);
  // the press frame starts the move at frame 0; frame startup + 1 is the first active one
  run(m, DROPS.throwMove.startup);
  const early = m.combat.projectiles.some((p) => p.weaponDrop) || a.armed !== 0;
  run(m, 1);
  const pr = m.combat.projectiles.find((p) => p.weaponDrop);
  check("the weapon leaves on the throw's first active frame, not before, and you are on fists from it", !early && !!pr && pr.weaponDrop === 'Sword' && a.armed === -1 && a.char.weapon.id === 'Fists',
    `gone a frame early: ${early}; then projectile ${pr ? pr.weaponDrop : 'none'}, armed ${a.armed}, holding ${a.char.weapon.id}`);
  let hit = false, landed = null;
  for (let i = 0; i < 120 && !landed; i++) {
    m.step();
    if (b.percent > before) hit = true;
    landed = m.combat.drops.find((d) => d.look === 'Sword') || null;
  }
  check('the thrown weapon hits for damage', hit && b.percent - before === DROPS.thrown.damage, `victim ${before}% -> ${b.percent}%`);
  check('...and lands as a drop that looks like it', !!landed, landed ? `drop at ${landed.x.toFixed(1)},${landed.y.toFixed(1)} looking like ${landed.look}` : 'no drop');
  // walk to it and take it: the OTHER weapon
  a.x = landed.x; a.y = landed.y; a.vx = 0;
  run(m, 30);
  press(m, a, { pickup: true });
  check('the next drop arms you with your other weapon, and its weight', a.armed === 1 && a.char === a.kit[1] && a.char.weapon.id === 'Gauntlets'
    && a.weight === a.kit[1].weight && a.weight !== a.fists.weight,
    `armed ${a.armed}, holding ${a.char.weapon.id}, weight ${a.weight} (gauntlets ${a.kit[1].weight}, fists ${a.fists.weight})`);
}
{
  // an item in reach is taken first; a held item does not stop the throw
  const { m, a } = planted();
  m.combat.spawnDrop(a.x, a.y + 0.5); run(m, 10); press(m, a, { pickup: true });
  run(m, 20);
  m.combat.spawnItem(ITEMS.RivetGun, a.x, a.y + 0.5); run(m, 10);
  press(m, a, { pickup: true });
  check('armed with an item in reach, pickup takes the item, not a throw', a.item && a.item.def.id === 'RivetGun' && a.armed === 0 && a.moveId !== 'WeaponThrow',
    `item ${a.item ? a.item.def.id : 'none'}, armed ${a.armed}, move ${a.moveId}`);
  run(m, 20);
  press(m, a, { pickup: true });
  check('holding the item, pickup throws the weapon', a.moveId === 'WeaponThrow', `move ${a.moveId}`);
}
{
  // in the air
  const { m, a } = planted();
  a.vy = 30; a.onGround = false; a.setState('air');
  m.combat.spawnDrop(a.x, a.y + 2); m.combat.drops[0].vy = 30;
  run(m, 3);
  m.combat.drops[0].x = a.x; m.combat.drops[0].y = a.y + 0.5;
  press(m, a, { pickup: true });
  const took = a.armed === 0;
  press(m, a, { pickup: true });
  check('pickup and throw work in the air', took && !a.onGround && a.moveId === 'WeaponThrow' && a.move.grounded === false,
    `armed in the air: ${took}; then ${a.moveId} (grounded ${a.move && a.move.grounded}), onGround ${a.onGround}`);
}
{
  // an air throw started just above the floor lands mid-throw, and still throws
  const { m, a } = planted();
  m.combat.spawnDrop(a.x, a.y + 0.5); run(m, 10); press(m, a, { pickup: true });
  run(m, 20);
  a.y = 0.4; a.vy = -20; a.onGround = false; a.platform = null; a.setState('air');
  press(m, a, { pickup: true });
  const inAir = a.moveId === 'WeaponThrow' && a.move.grounded === false;
  run(m, DROPS.throwMove.startup + 2);
  check('an air throw that lands before letting go still throws', inAir && a.onGround && a.armed === -1 && m.combat.projectiles.some((p) => p.weaponDrop),
    `started in the air: ${inAir}; landed: ${a.onGround}; armed ${a.armed}, weapon in flight: ${m.combat.projectiles.some((p) => p.weaponDrop)}`);
}
{
  // off the stage: gone
  const { m, a } = planted({ ax: 30 });
  a.x = m.stage.blast.right - 15;
  m.combat.spawnDrop(a.x, a.y + 0.5); run(m, 2); m.combat.drops[0].x = a.x; m.combat.drops[0].y = a.y;
  press(m, a, { pickup: true }); run(m, 10);
  a.facing = 1;
  press(m, a, { pickup: true });
  // Its flight ends over the void, where it becomes a drop like any other and falls out of the
  // stage - so it is gone, by falling, not lying anywhere to be taken.
  let made = 0, gone = 0;
  for (let i = 0; i < 200; i++) { m.events.length = 0; m.step(); made += events(m, 'dropspawn').filter((e) => e.weapon).length; gone += events(m, 'dropgone').length; }
  check('a weapon thrown off the stage is gone: it falls out, and lies nowhere', a.armed === -1 && !m.combat.drops.some((d) => d.look)
    && !m.combat.projectiles.some((p) => p.weaponDrop) && made === gone,
    `${made} drops made of it, ${gone} fell out, ${m.combat.drops.filter((d) => d.look).length} left lying`);
}
{
  // a lost stock loses the weapon
  const { m, a } = planted();
  m.combat.spawnDrop(a.x, a.y + 0.5); run(m, 10); press(m, a, { pickup: true });
  const armed = a.armed === 0;
  a.x = m.stage.blast.right + 5;
  for (let i = 0; i < 60 * 6 && a.state !== 'respawn'; i++) m.step();
  check('a lost stock loses the weapon in hand', armed && a.armed === -1 && a.char.weapon.id === 'Fists',
    `armed before: ${armed}; after the KO, holding ${a.char.weapon.id}`);
}

// ---- the fists never kill early ----
{
  // Every weapon kills with its strongest signature; the weakest of those is the bar.
  const heaviestFist = Math.max(...Object.values(FISTS.moves).map((mv) => mv.growth));
  const weakestKiller = Math.min(...WEAPONS.map((w) => Math.max(...Object.values(w.moves).filter((mv) => mv.heavy && !mv.ultimate).map((mv) => mv.growth))));
  check("the fists hit at under half the kill power of any weapon's kill move", heaviestFist * 2 < weakestKiller,
    `strongest fist ${heaviestFist} growth, weakest weapon kill move ${weakestKiller}`);
  check('the fists are no weapon anyone can pick', !WEAPONS.includes(FISTS), 'not in WEAPONS');
  const bad = Object.entries(FISTS.moves).filter(([id, mv]) => mv.id !== id || mv.total !== mv.startup + mv.active + mv.recovery || !mv.kind || !mv.hitboxes);
  check("the fists' moves carry the fields every weapon's do", bad.length === 0, bad.length ? `missing on ${bad.map(([id]) => id).join(', ')}` : `${Object.keys(FISTS.moves).length} moves, each with id, total, kind and hitboxes`);
}

// ---- seeded ----
{
  const trace = (seed) => {
    const m = armedMatch({ seed });
    const out = [];
    for (let i = 0; i < 60 * 20; i++) { m.step(); for (const e of events(m, 'dropspawn')) out.push(`${e.x.toFixed(6)},${e.y.toFixed(6)}`); m.events.length = 0; }
    return out.join(' ');
  };
  const a = trace(7), b = trace(7), c = trace(8);
  check('the same seed drops the same drops in the same places', a === b && a.length > 0 && a !== c, `seed 7: ${a.split(' ').length} drops, twice the same; seed 8 differs: ${a !== c}`);
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
