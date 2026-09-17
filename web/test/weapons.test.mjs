import { makeMatch, skipCountdown, EMPTY } from './harness.mjs';
import { WEAPONS } from '../src/data/weapons/index.js';
import { buildLoadout } from '../src/data/loadout.js';
import { koPercent } from './balance.mjs';
let pass=0, fail=0;
const check=(n,c,d)=>{ (c?pass++:fail++); console.log(`${c?'PASS':'FAIL'}  ${n}\n      ${d}`); };

// Put two fighters face to face on solid ground, mid-stage.
function duel(wA, wB='Sword'){
  const m = makeMatch({ loadouts: [['Classic',wA], ['Noir',wB]] });
  skipCountdown(m);
  for(let i=0;i<200;i++) m.step();
  const [a,v] = m.fighters;
  const place=()=>{ a.x=-1.2; v.x=1.2; a.facing=1; v.facing=-1;
    for(const f of [a,v]){ f.onGround=true; f.platform=m.stage.main; f.y=0; f.vx=0; f.vy=0; } v.setState('idle'); };
  place();
  return { m, a, v, place };
}
const press=(m,src,p)=>m._input.set(src,Object.assign({anyPress:true},p));

// ---- 1. every weapon: all 13 moves start, run to completion, and produce sane damage ----
for (const w of WEAPONS) {
  const { m, a, v, place } = duel(w.id);
  const results = [];
  for (const id of Object.keys(w.moves)) {
    place(); v.percent = 0; v.setState('idle'); a.setState('idle'); a.hitVictims = new Map();
    a.startMove(id);
    let ranFrames = 0;
    for (let i=0;i<200 && (a.state==='attack'||a.hitlag>0);i++){ m.step(); ranFrames++; }
    results.push({ id, dmg: v.percent, ranFrames, stuck: a.state==='attack' });
  }
  const stuck = results.filter(r=>r.stuck);
  const connected = results.filter(r=>r.dmg>0);
  check(`${w.id}: every move completes`, stuck.length===0,
    `${results.length} moves run; ${connected.length} connected point-blank; longest ${Math.max(...results.map(r=>r.ranFrames))}f` + (stuck.length?` STUCK: ${stuck.map(r=>r.id)}`:''));
}

// ---- 2. combo strings: Light -> Light+Up must reach the launcher ----
for (const w of WEAPONS) {
  const { m, a, v, place } = duel(w.id);
  place(); a.startMove('LightNeutral1');
  let reached=null;
  for (let i=0;i<90;i++){
    if (a.moveLanded && a.moveId==='LightNeutral1') press(m,'p0',{ light:true, y:1 }); else m._input.clear('p0');
    m.step();
    if (a.moveId && a.moveId!=='LightNeutral1'){ reached=a.moveId; break; }
  }
  const want = w.moves.LightNeutral1.chains.up;
  check(`${w.id}: Light -> Light+Up chains to the launcher`, reached===want, `got '${reached}', expected '${want}'`);
}

// ---- 3. combo strings: the neutral branch differs from the up branch ----
for (const w of WEAPONS) {
  const runBranch=(inp)=>{ const { m, a, place } = duel(w.id); place(); a.startMove('LightNeutral1');
    for (let i=0;i<90;i++){ if (a.moveLanded && a.moveId==='LightNeutral1') press(m,'p0',Object.assign({light:true},inp)); else m._input.clear('p0');
      m.step(); if (a.moveId && a.moveId!=='LightNeutral1') return a.moveId; } return null; };
  const n=runBranch({}), u=runBranch({y:1}), d=runBranch({y:-1});
  check(`${w.id}: light string branches by direction`, n!==u && n!==d && u!==d, `neutral='${n}' up='${u}' down='${d}'`);
}

// ---- 4. a light string can finish into a signature (chainsHeavy) ----
for (const w of WEAPONS) {
  const { m, a, place } = duel(w.id);
  place(); a.startMove('LightNeutral2');
  let got=null;
  for (let i=0;i<90;i++){
    if (a.moveLanded && a.moveId==='LightNeutral2') press(m,'p0',{ heavy:true, heavyHeld:true }); else m._input.clear('p0');
    m.step(); if (a.moveId && a.moveId!=='LightNeutral2'){ got=a.moveId; break; }
  }
  check(`${w.id}: light string cashes out into a signature`, got && got.startsWith('Sig'), `LightNeutral2 + Heavy -> '${got}'`);
}

// ---- 5. mechanics actually move ----
{ // Sword Momentum: running fills, then the next move spends it
  const { m, a } = duel('Sword');
  a.setState('run');
  for(let i=0;i<200;i++){ press(m,'p0',{x:1}); m.step(); if(a.mech.ready) break; }
  check('Sword: Momentum charges from running', a.mech.ready===true, `runFrames=${a.mech.runFrames}, ready=${a.mech.ready} (needs ${a.char.mechanic.runFrames})`);
}
{ // Blasters ammo: Full Auto spends rounds
  const { m, a, place } = duel('Blasters');
  place(); const start=a.mech.spines;
  a.startMove('SigSide');
  for(let i=0;i<120 && a.state==='attack';i++) m.step();
  check('Blasters: Full Auto spends magazine rounds', a.mech.spines < start, `magazine ${start} -> ${a.mech.spines} (max ${a.char.mechanic.max})`);
}
{ // Blasters ammo regen
  const { m, a } = duel('Blasters');
  a.mech.spines = 0;
  for(let i=0;i<200;i++) m.step();
  check('Blasters: magazine refills over time', a.mech.spines > 0, `after 200f idle: ${a.mech.spines}/${a.char.mechanic.max} rounds`);
}
{ // Grimoire Light: standing still fills segments and shortens the beam's startup
  const { m, a } = duel('Grimoire');
  a.setState('idle');
  for(let i=0;i<400 && a.mech.segments<1;i++){ m._input.clear('p0'); m.step(); }
  const seg=a.mech.segments;
  a.startMove('SigNeutral');
  const shortened = a.startupEff < a.char.moves.SigNeutral.startup;
  check('Grimoire: standing still charges the beam', seg>0 && shortened,
    `${seg} segment(s) charged; Starfall startup ${a.char.moves.SigNeutral.startup} -> ${a.startupEff}`);
}
{ // Scythe Bloom: landing hits in the window empowers the next heavy
  const { m, a, v, place } = duel('Scythe');
  for(let round=0; round<8 && !a.mech.bloomed; round++){
    place(); v.percent=0; v.setState('idle'); a.setState('idle'); a.hitVictims=new Map();
    a.startMove('LightNeutral1');
    for(let i=0;i<60 && (a.state==='attack'||a.hitlag>0);i++) m.step();
  }
  check('Scythe: Bloom builds from landed hits', a.mech.bloomed===true || a.mech.hits.length>0,
    `hits banked=${a.mech.hits.length}/${a.char.mechanic.hitsRequired}, bloomed=${a.mech.bloomed}`);
}

// ---- 6. pullVictim really drags (scythe identity) ----
{ const { m, a, v, place } = duel('Scythe');
  place(); v.x = 3.4;                       // inside Hook range, outside jab range
  const before = v.x;
  a.startMove('LightNeutral3');             // Hook, pullVictim 2.5
  let atHit = null;
  for(let i=0;i<60;i++){ m.step(); if(v.hitlag>0){ atHit = v.x; break; } }
  check('Scythe: Hook drags the victim inward', atHit !== null && atHit < before - 1,
    `victim x ${before.toFixed(2)} -> ${atHit===null?'never hit':atHit.toFixed(2)} at the moment of the hit (pullVictim 2.5)`); }

// ---- 7. full bot matches on every weapon pairing ----
{ let played=0, bad=[];
  for (let i=0;i<WEAPONS.length;i++) for (let j=0;j<WEAPONS.length;j++){
    const m = makeMatch({ mode:'StockFFA', stocks:1, loadouts:[['Classic',WEAPONS[i].id],['Noir',WEAPONS[j].id]] });
    m.fighters.forEach(f=>{f.isBot=true; f.botLevel='hard';});
    skipCountdown(m);
    let n=0; while(m.state!=='results' && n<60*400){ m.step(); n++;
      for(const f of m.fighters) if(![f.x,f.y,f.vx,f.vy,f.percent].every(Number.isFinite)) { bad.push(`${WEAPONS[i].id} vs ${WEAPONS[j].id}: non-finite`); n=1e9; break; } }
    if (m.state!=='results') bad.push(`${WEAPONS[i].id} vs ${WEAPONS[j].id}: unfinished`);
    played++;
  }
  check('every weapon pairing plays a full bot match', bad.length===0, `${played} matchups, all 4x4 pairings${bad.length?': '+bad.slice(0,4).join('; '):', no crashes or NaN'}`); }


// ---- 8. the up-air exists on every weapon and is reachable from an air Light + Up ----
for (const w of WEAPONS) {
  const { m, a } = duel(w.id);
  a.onGround=false; a.platform=null; a.setState('air'); a.y=10; a.vy=0; a.jumpsLeft=1;
  press(m,'p0',{ light:true, y:1 });
  m.step(); m._input.clear('p0');
  check(`${w.id}: Light+Up in the air gives an up-air`, a.moveId==='AirUp', `moveId='${a.moveId}' (expected AirUp)`);
}

// ---- 9. ammo: a dry magazine blocks the ranged lights but never the melee fallback ----
{
  const { m, a, place } = duel('Blasters');
  place(); a.mech.spines = 0; a.setState('idle');
  a.startMove('LightNeutral1');
  const blocked = a.moveId !== 'LightNeutral1';
  a.setState('idle'); a.startMove('LightNeutral3');      // Point Blank is melee, costs nothing
  check('Blasters: an empty magazine blocks the ranged light', blocked && a.moveId==='LightNeutral3',
    `dry Pop Shot -> ${blocked ? 'refused' : 'FIRED ANYWAY'}; melee Point Blank still available (moveId='${a.moveId}')`);
}
{
  const { m, a, place } = duel('Blasters');
  place(); const start = a.mech.spines; a.setState('idle');
  a.startMove('LightNeutral1');
  check('Blasters: a ranged light spends a round', a.mech.spines === start - 1,
    `magazine ${start} -> ${a.mech.spines} after one Pop Shot (this was free before)`);
}

// ---- 10. recoveries are actually different per weapon ----
{
  const kinds = WEAPONS.map(w => `${w.id}:${w.recovery.kind}`);
  const distinct = new Set(WEAPONS.map(w => `${w.recovery.kind}|${w.recovery.vy ?? w.recovery.hopVy}|${w.recovery.vx ?? '-'}`));
  check('every weapon recovers differently', distinct.size === WEAPONS.length, kinds.join('  '));
}
{ // the scythe's tether must actually reach a ledge
  const { m, a } = duel('Scythe');
  const L = m.stage.ledges[1];
  a.onGround=false; a.platform=null; a.setState('air'); a.x = L.x + 8; a.y = L.y - 4; a.vy=-10; a.recoveryUsed=false; a.ledgeGrabs=0;
  a.facing=-1;
  press(m,'p0',{ heavy:true, heavyHeld:true, y:1 });
  for (let i=0;i<90 && a.state!=='ledge';i++){ m.step(); m._input.clear('p0'); }
  check('Scythe: the tether recovery grabs the ledge', a.state==='ledge' || a.state==='tether',
    `state='${a.state}' after firing the tether from 8 studs out`);
}

// ---- every weapon's recovery declares the fields its own kind reads ----
//
// Recovery kinds read different fields, and nothing checked that a weapon supplied the right ones.
// The Chain Flail shipped `{ kind: 'tether', vy, vx }` while the tether branch of fighter.js reads
// `range`, `speed` and `hopVy` - so a failed tether set `vy = undefined`, and a non-finite fighter
// made two of the 144 weapon pairings unfinishable. The symptom was a whole match hanging; the
// cause was two field names.
{
  const NEEDS = {
    hop: ['vy', 'vx'],
    puff: ['vy', 'vx'],
    tether: ['range', 'speed', 'hopVy'],
    teleport: ['range'],
  };
  const bad = [], rows = [];
  for (const w of WEAPONS) {
    const r = w.recovery;
    if (!r || !r.kind) { bad.push(`${w.id} has no recovery`); continue; }
    const need = NEEDS[r.kind];
    if (!need) { bad.push(`${w.id}: recovery kind "${r.kind}" is not one fighter.js handles (${Object.keys(NEEDS).join(', ')})`); continue; }
    const missing = need.filter((k) => typeof r[k] !== 'number' || !Number.isFinite(r[k]));
    if (missing.length) bad.push(`${w.id}: ${r.kind} recovery is missing ${missing.join(', ')}`);
    rows.push(`${w.id} ${r.kind}`);
  }
  check('every recovery declares the fields its kind reads', bad.length === 0,
    bad.length ? bad.join('; ') : `${WEAPONS.length} weapons: ${rows.join(', ')}`);
}

// ---- every sub-object a move declares carries the fields the engine reads off it ----
//
// Two of these in one afternoon. The Chain Flail declared a tether recovery with the wrong field
// names and produced a non-finite fighter; the War Hammer declared a crater without the optional
// `minDamage` and `Math.max(undefined, n)` wrote NaN into a victim's percent, which corrupts a
// match in a way nothing else notices. Both were valid-looking data.
{
  const NEEDS = {
    crater: ['frame', 'every', 'count', 'step', 'radius', 'damage', 'minDamage', 'base', 'growth', 'angle'],
    starfall: ['perTarget', 'every', 'height', 'speed', 'turn', 'size', 'radius', 'damage', 'base', 'growth', 'angle'],
    vortex: ['targets', 'range', 'holdFrames', 'pullSpeed', 'orbOffset'],
    projectile: ['speed', 'lifetime', 'size', 'spawnOffset'],
    charge: ['maxHold', 'damage', 'base', 'growth'],
    counter: ['multiplier', 'minDamage', 'burstFrames', 'burstRecovery', 'hitbox'],
  };
  const bad = [], seen = [];
  for (const w of WEAPONS) for (const [id, mv] of Object.entries(w.moves)) {
    for (const [key, need] of Object.entries(NEEDS)) {
      const sub = mv[key];
      if (!sub) continue;
      seen.push(`${w.id}/${id}.${key}`);
      for (const f of need) {
        const v = sub[f];
        const ok = Array.isArray(v) ? v.every(Number.isFinite) : (typeof v === 'object' && v !== null) || Number.isFinite(v);
        if (!ok) bad.push(`${w.id} ${id}: ${key} is missing ${f}`);
      }
    }
  }
  check('every move sub-object declares the fields the engine reads', bad.length === 0,
    bad.length ? bad.join('; ') : `${seen.length} sub-objects across ${WEAPONS.length} weapons, all complete`);
}

// ---- a charged move has to stay inside the roster's kill band ----
//
// A `charge` block silently replaces damage, base AND growth, and every other measurement in this
// project reads the UNCHARGED move. A fully drawn Power Shot killed from 37%, and from 21% with
// the Longbow's Draw banked on top - a projectile taking a stock at a fifth of the percent
// anything else needs - while combo.test.mjs happily reported the move at 149% and passed.
//
// The counter-intuitive part is why it happened: raising a move's damage LOWERS its kill percent
// all by itself, because the victim's own percent goes up before knockback is computed. Charge
// blocks that raise damage and base and growth together compound three ways at once.
{
  const bad = [], rows = [];
  for (const w of WEAPONS) for (const [id, m] of Object.entries(w.moves)) {
    if (!m.charge) continue;
    const c = m.charge;
    const ko = koPercent(c.base ?? m.base, c.growth ?? m.growth, c.damage ?? m.damage, 100, { angle: m.angle });
    rows.push(`${w.id} ${m.label} ${ko === null ? 'never' : Math.round(ko) + '%'}`);
    // The roster's signatures kill between 97% and 153%. A charge is worth paying for, so it may
    // kill earlier than its own uncharged form - but not before the earliest thing in the game.
    if (ko !== null && ko < 90) bad.push(`${w.id} ${m.label} fully charged kills from ${Math.round(ko)}%, earlier than any signature in the game`);
  }
  check('a fully charged move still kills inside the roster band', bad.length === 0,
    bad.length ? bad.join('; ') : `charged kill percents: ${rows.join(', ')}`);
}

// ---- a mechanic that moves somebody has to actually move them ----
//
// The Chain Flail's Snare added its pull to `vx`, which `_groundMove` and `_friction` rewrite from
// the stick every single frame. Measured over a full 90-frame hold, the victim moved 0.00 studs
// and the attacker moved 29.99 - which is just the flail's own run speed. The mechanic was a
// complete no-op in BOTH directions and every existing test passed.
//
// It is the same bug, with the same fix, as hazard wind: `_airDrift` erased every gust in the game
// until wind moved into its own carried velocity. This check drives the real mechanic through the
// real engine and measures displacement, because that is the only thing that would have caught it.
{
  const M = WEAPONS.find((w) => w.id === 'Flail').mechanic;
  const run = (attackerStick) => {
    const m = makeMatch({ loadouts: [['Classic', 'Flail'], ['Noir', 'Sword']] });
    skipCountdown(m);
    const [a, v] = m.fighters;
    for (const [f, x] of [[a, -6], [v, 6]]) { f.x = x; f.y = 6; f.vx = 0; f.vy = 0; }
    for (let i = 0; i < 240 && !(a.onGround && v.onGround && a.y < 1 && v.y < 1); i++) {
      m.step(); m.events.length = 0; a.x = -6; v.x = 6; a.vx = 0; v.vx = 0;
    }
    a.facing = 1; v.facing = -1;
    a.mech.snared = v; a.mech.timer = M.holdFrames;
    const gap0 = Math.abs(v.x - a.x);
    for (let i = 0; i < M.holdFrames; i++) {
      m._input.set('p0', Object.assign({}, EMPTY(), { x: attackerStick }));
      m.step(); m.events.length = 0;
    }
    return { gap0, gap: Math.abs(v.x - a.x) };
  };
  const toward = run(1), away = run(-1), idle = run(0);
  const bad = [];
  if (toward.gap > toward.gap0 * 0.5) bad.push(`reeling yourself in closed ${toward.gap0.toFixed(1)} studs to ${toward.gap.toFixed(1)} — the pull is not reaching the position step`);
  if (away.gap > away.gap0 * 0.5) bad.push(`reeling them in closed ${away.gap0.toFixed(1)} studs to ${away.gap.toFixed(1)} — the victim is not being dragged`);
  if (Math.abs(idle.gap - idle.gap0) > 0.5) bad.push(`a snare with no stick input moved somebody ${(idle.gap - idle.gap0).toFixed(1)} studs`);
  check('the Snare actually pulls, both ways, and only when asked', bad.length === 0,
    bad.length ? bad.join('; ')
      : `over ${M.holdFrames} frames from ${toward.gap0.toFixed(0)} studs apart: hold toward -> ${toward.gap.toFixed(2)}, hold away -> ${away.gap.toFixed(2)}, no input -> ${idle.gap.toFixed(2)}`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail?1:0);
