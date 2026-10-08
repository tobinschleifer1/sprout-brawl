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
//   * the fists never kill early (their growth is under half the weakest real heavy's; their heavies
//     do not kill at 300%);
//   * every weapon throws its own way, and kills in its band (heavy, medium, light); the pike goes
//     through everyone on the line; the shield skips off the floor;
//   * bots arm themselves (climbing and dropping through platforms for drops), throw, spend most
//     of a fight armed and still finish matches; without drops they never touch any of it;
//   * the same seed and inputs drop the same drops in the same places.
//
//     node test/drops.test.mjs
import { makeMatch, skipCountdown } from './harness.mjs';
import { DROPS, dropsOnStage, FRAME } from '../src/config.js';
import { WEAPONS, WEAPON_BY_ID, FISTS } from '../src/data/weapons/index.js';
import { buildArmed } from '../src/data/loadout.js';
import { koPercent } from './balance.mjs';
import { LEVELS, weaponAction } from '../src/engine/ai.js';
import { emptyFrame } from '../src/engine/input.js';
import { Fighter } from '../src/engine/fighter.js';
const buildArmedFor = (w) => buildArmed('Classic', [w, w]);
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

// ---- an unnamed fighter (a bot) is named for its first weapon, not the fists it holds ----
{
  const A = buildArmed('Classic', ['Hammer', 'Sword']);
  const f = new Fighter({ index: 0, ...A, x: 0, y: 0 });
  check('a bot is named for its first weapon, not "Fists"', f.name === 'War Hammer' && f.char.weapon.id === 'Fists',
    `named "${f.name}" holding ${f.char.weapon.id}`);
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
  check("the thrown weapon hits for its own throw's damage", hit && b.percent - before === a.kit[0].weapon.thrown.damage, `victim ${before}% -> ${b.percent}% (the sword's throw does ${a.kit[0].weapon.thrown.damage})`);
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

// ---- every weapon throws its own way (phase 2) ----
// Kill power by the same oracle every signature's "kills N%" in the weapon files comes from
// (balance.mjs koPercent: a 100-weight victim launched from the stage's centre, crossing a side or
// the top blast line), so a throw's number means what a signature's does. Simulating a standing
// victim instead measured whether they happened to fall off the stage - non-monotonic in percent,
// since a launch that lands on a ledge is no KO. Bands by what each weapon is for:
//   heavy  (Hammer, Axe)                       kill like a heavy signature: by 200%
//   medium (Flail, Sword, Scythe, Shield, Pike) kill 200-260%
//   light  (Daggers, Blasters, Gauntlets, Longbow, Grimoire)  pressure: never kill
// At the time of writing: Hammer 174, Axe 185, Flail 217, Sword 226, Scythe 236, Shield 247,
// Pike 253 (the Sword's signatures kill 172-185); the five light throws never kill.
// And every throw has to connect, which only a simulation shows: thrown from 5 studs.
function throwAt(weapon, pc = 0, d = 5) {
  const m = skipCountdown(makeMatch({ armed: [['Classic', [weapon, weapon]], ['Noir', ['Sword', 'Sword']]] }));
  const [a, b] = m.fighters;
  const ax = -d / 2, bx = d / 2;
  for (const [who, x] of [[a, ax], [b, bx]]) { who.x = x; who.y = 6; who.vx = 0; who.vy = 0; }
  for (let i = 0; i < 240 && !(a.onGround && b.onGround && a.y < 1 && b.y < 1); i++) { m.step(); a.x = ax; b.x = bx; a.vx = 0; b.vx = 0; }
  a.facing = 1; b.facing = -1; a.invincible = 0; b.invincible = 0;
  m.combat.drops.length = 0; m.combat.dropTimer = -9999;
  m.combat.spawnDrop(a.x, a.y + 0.5); run(m, 4); press(m, a, { pickup: true }); run(m, 4);
  b.percent = pc;
  press(m, a, { pickup: true });
  let hit = false, ko = false;
  for (let i = 0; i < 60 * 8 && !ko; i++) { m.step(); if (b.percent > pc) hit = true; ko = m.events.some((e) => e.type === 'ko' && e.fighter === b.index); m.events.length = 0; }
  return { hit, ko };
}
{
  const BANDS = { Hammer: [140, 200], Axe: [140, 200], Flail: [200, 260], Sword: [200, 260], Scythe: [200, 260], Shield: [200, 260], Pike: [200, 260] };
  const LIGHT = ['Daggers', 'Blasters', 'Gauntlets', 'Longbow', 'Grimoire'];
  const ko = (w) => { const T = WEAPON_BY_ID[w].thrown; return koPercent(T.base, T.growth, T.damage, 100, { angle: T.angle }); };
  const bad = [], got = [];
  for (const [id, [lo, hi]] of Object.entries(BANDS)) {
    const k = ko(id);
    got.push(`${id} ${k}`);
    if (k === null || k < lo || k > hi) bad.push(`${id} kills at ${k}%, band ${lo}-${hi}`);
  }
  for (const id of LIGHT) if (ko(id) !== null) bad.push(`${id} kills at ${ko(id)}%`);
  const heavy = Math.max(ko('Hammer'), ko('Axe')), medium = Math.min(...['Flail', 'Sword', 'Scythe', 'Shield', 'Pike'].map(ko));
  check('every throw kills in its band: heavies by 200%, mediums 200-260%, lights never', bad.length === 0 && heavy < medium,
    bad.length ? bad.join('; ') : `${got.join(', ')}; ${LIGHT.length} light throws never kill`);
  const misses = WEAPONS.map((w) => w.id).filter((id) => !throwAt(id).hit);
  check('every throw connects from 5 studs', misses.length === 0, misses.length ? `misses: ${misses.join(', ')}` : `all ${WEAPONS.length} hit a standing fighter 5 studs away`);
  const profiles = WEAPONS.map((w) => JSON.stringify(w.thrown));
  check('every weapon has a throw of its own', WEAPONS.every((w) => w.thrown) && new Set(profiles).size === WEAPONS.length,
    `${new Set(profiles).size} different throws across ${WEAPONS.length} weapons`);
}
{
  // the pike goes through everyone on the line
  const m = skipCountdown(makeMatch({ armed: [['Classic', ['Pike', 'Pike']], ['Noir', ['Sword', 'Sword']], ['Ember', ['Sword', 'Sword']]] }));
  const [a, b, c] = m.fighters;
  const xs = [[a, -6], [b, -1], [c, 4]];
  for (const [who, x] of xs) { who.x = x; who.y = 6; who.vx = 0; who.vy = 0; }
  for (let i = 0; i < 240 && !xs.every(([w]) => w.onGround && w.y < 1); i++) { m.step(); for (const [w, x] of xs) { w.x = x; w.vx = 0; } }
  for (const [w] of xs) w.invincible = 0;
  a.facing = 1; m.combat.drops.length = 0; m.combat.dropTimer = -9999;
  m.combat.spawnDrop(a.x, a.y + 0.5); run(m, 4); press(m, a, { pickup: true }); run(m, 4);
  press(m, a, { pickup: true });
  run(m, 60);
  check('a thrown pike goes through everyone on the line', b.percent > 0 && c.percent > 0, `first in line ${b.percent}%, second ${c.percent}%`);
}
{
  // the shield skips off the floor and keeps going
  const { m, a } = planted({ ax: -20, bx: 30 });
  const shield = buildArmedFor('Shield');
  a.kit = shield.kit; a.nextArm = 0;
  m.combat.spawnDrop(a.x, a.y + 0.5); run(m, 4); press(m, a, { pickup: true }); run(m, 4);
  m.events.length = 0;
  press(m, a, { pickup: true });
  run(m, DROPS.throwMove.startup + 1);
  // held still over the middle of the floor, so only the skips decide what happens
  const pr = m.combat.projectiles.find((p) => p.weaponDrop === 'Shield');
  pr.x = 0; pr.y = 6; pr.vx = 0; pr.vy = -10; pr.life = 9999;
  let bounces = 0, flewOn = false, landed = null;
  for (let i = 0; i < 240 && !landed; i++) {
    m.events.length = 0;
    m.step();
    bounces += events(m, 'bounce').length;
    if (bounces > 0 && m.combat.projectiles.includes(pr)) flewOn = true;
    landed = m.combat.drops.find((d) => d.look === 'Shield') || null;
  }
  const want = WEAPON_BY_ID.Shield.thrown.bounces;
  check('a thrown shield skips off the floor its number of times, then lands', bounces === want && flewOn && !!landed,
    `${bounces} skips (it has ${want}), still flying after the first: ${flewOn}, then a drop: ${!!landed}`);
  // ...and the same coming down fast enough to be inside the floor a frame later: the solid's own
  // skip, which the gentle fall above never reaches (it meets the platform a frame early)
  m.combat.drops.length = 0;
  m.combat.spawnDrop(a.x, a.y + 0.5); run(m, 4); press(m, a, { pickup: true }); run(m, 4);
  press(m, a, { pickup: true }); run(m, DROPS.throwMove.startup + 1);
  const fast = m.combat.projectiles.find((p) => p.weaponDrop === 'Shield');
  fast.x = 0; fast.y = 0.5; fast.vx = 0; fast.vy = -60; fast.life = 9999;
  let hard = 0, down = null;
  for (let i = 0; i < 240 && !down; i++) { m.events.length = 0; m.step(); hard += events(m, 'bounce').length; down = m.combat.drops.find((d) => d.look === 'Shield') || null; }
  check('a shield driven into the floor skips its number of times too', hard === want && !!down, `${hard} skips, then a drop: ${!!down}`);
}
{
  // the fists' heavies chip at 300% and do not kill
  const kills = [];
  for (const mv of ['SigNeutral', 'SigSide', 'SigDown']) {
    const { m, a, b } = planted({ ax: -1.2, bx: 1.2 });
    b.percent = 300;
    a.startMove(mv);
    let hit = false, ko = false;
    for (let i = 0; i < 60 * 8 && !ko; i++) { m.step(); if (b.percent > 300) hit = true; ko = m.events.some((e) => e.type === 'ko' && e.fighter === b.index); m.events.length = 0; }
    kills.push(`${mv} ${hit ? (ko ? 'KILLED' : 'chipped') : 'missed'}`);
  }
  check("the fists' heavies land and do not kill even at 300%", kills.every((k) => k.endsWith('chipped')), kills.join(', '));
}

// ---- bots (phase 3) ----
// Four bots with drops on: they go for drops (up and through platforms), throw what they hold, and
// spend most of the fight armed; matches still end. Measured when this was written (six normal
// four-bot matches): armed about two thirds of the time, a median of four seconds on fists before
// a pickup. Before bots climbed and dropped through platforms for drops it was under half, and
// one stretch in ten ran past forty seconds.
{
  const KITS = [['Sword', 'Hammer'], ['Daggers', 'Axe'], ['Pike', 'Shield'], ['Scythe', 'Flail']];
  let arms = 0, throws = 0, armed = 0, alive = 0, ended = 0;
  const waits = [];
  const games = 3;
  for (let g = 0; g < games; g++) {
    const m = skipCountdown(makeMatch({ armed: KITS.map((k, i) => [['Classic', 'Noir', 'Ember', 'Moss'][i], k]), seed: 100 + g, stocks: 2 }));
    m.fighters.forEach((f) => { f.isBot = true; f.botLevel = 'normal'; });
    const since = m.fighters.map(() => 0);
    for (let i = 0; i < 60 * 240 && m.state !== 'results'; i++) {
      m.step();
      m.fighters.forEach((f, k) => { if (!f.alive) return; alive++; if (f.armed >= 0) armed++; else if (f.state !== 'respawn') since[k]++; });
      for (const e of m.events) { if (e.type === 'arm') arms++; if (e.type === 'throwweapon') throws++; if (e.type === 'droptake') { waits.push(since[e.fighter]); since[e.fighter] = 0; } }
      m.events.length = 0;
    }
    if (m.state === 'results') ended++;
  }
  waits.sort((a, b) => a - b);
  const share = armed / alive, median = waits[Math.floor(waits.length / 2)] / 60;
  check('bots arm themselves from drops and throw what they hold', arms >= games * 6 && throws >= games,
    `${arms} pickups and ${throws} throws over ${games} four-bot matches`);
  check('bots spend most of a fight armed, and are not left on fists for long', share > 0.55 && median < 6,
    `armed ${(share * 100).toFixed(0)}% of the time; median ${median.toFixed(1)}s on fists before a pickup`);
  check('bot matches with drops still end', ended === games, `${ended}/${games} finished inside four minutes`);
}
{
  // Reaching a drop: on the first platform up (a jump and a double jump), and on the top one (too
  // high to jump to - the bot steps up via a platform in between). One bot, no opponent near.
  const reach = (x, y) => {
    const { m, a, b } = planted({ ax: 0, bx: 34 });
    a.isBot = true; a.botLevel = 'just_dont'; b.x = 34;
    const d = m.combat.spawnDrop(x, y);
    for (let i = 0; i < 60 * 10; i++) { m.step(); b.x = 34; b.vx = 0; if (a.armed >= 0) return i; if (!m.combat.drops.includes(d)) return null; }
    return null;
  };
  const side = reach(-21, 15), top = reach(0, 28);
  check('a bot climbs to a drop: a platform up, and the top one by way of another', side !== null && top !== null,
    `side platform: ${side === null ? 'never' : (side / 60).toFixed(1) + 's'}; top platform: ${top === null ? 'never' : (top / 60).toFixed(1) + 's'}`);
}
{
  // A bot match WITHOUT drops must draw nothing from the match's generator in the drop logic, or
  // every bot match in the game replays differently from before drops existed. Called directly,
  // in every state a bot can be in, with a generator that counts.
  const m = skipCountdown(makeMatch({ seed: 9 }));
  const [a, b] = m.fighters;
  let draws = 0;
  const counting = () => { draws++; return 0.5; };
  const st = { dropCd: 0, dropFetch: 0, wantArm: false, throwCd: 0, jumpCd: 0 };
  const tv = { x: b.x, y: b.y, percent: 200, state: 'idle' };
  let acted = false;
  for (const L of Object.values(LEVELS).filter(Boolean)) {
    for (const adx of [2, 10, 30]) acted = weaponAction(a, m, L, st, tv, adx, 0, emptyFrame(), counting) || acted;
  }
  check('without drops, the bots\' drop logic draws nothing and does nothing', draws === 0 && !acted, `${draws} draws, acted: ${acted}`);
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
