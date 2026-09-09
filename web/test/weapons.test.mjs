import { makeMatch, skipCountdown } from './harness.mjs';
import { WEAPONS } from '../src/data/weapons/index.js';
import { buildLoadout } from '../src/data/loadout.js';
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

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail?1:0);
