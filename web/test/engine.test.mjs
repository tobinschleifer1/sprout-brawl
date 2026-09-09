import { makeMatch, skipCountdown } from './harness.mjs';
import { INPUT_BUFFER, TECH, HITLAG_CAP } from '../src/config.js';
let pass=0, fail=0;
const check=(name,cond,detail)=>{ (cond?pass++:fail++); console.log(`${cond?'PASS':'FAIL'}  ${name}\n      ${detail}`); };

// 1 clock does not run during the countdown
{ const m=makeMatch({mode:'TimedFFA',timeLimit:180}); skipCountdown(m);
  check('clock starts at GO', Math.abs(m.time)<1e-9, `after ${m.frame}f of countdown, match.time=${m.time.toFixed(3)}s (was 3.500s)`); }

// 2 timed modes respawn forever
{ const m=makeMatch({mode:'TimedFFA',stocks:3,timeLimit:180}); skipCountdown(m);
  const f=m.fighters[0]; let kos=0;
  for(let i=0;i<60*90 && kos<6;i++){ if(f.alive&&f.state!=='respawn'&&f.state!=='ko'){f.onGround=false;f.platform=null;f.y=m.stage.blast.bottom-60;f.setState('air');}
    const b=f.alive; m.step(); if(b&&!f.alive)kos++; }
  for(let i=0;i<60*5;i++) m.step();
  check('timed mode has no stock cap', kos>=5 && f.alive, `${kos} KOs taken, still alive=${f.alive}, stocks=${f.stocks}, state=${m.state}`); }

// 3 stock modes still eliminate
{ const m=makeMatch({mode:'StockFFA',stocks:2}); skipCountdown(m);
  const f=m.fighters[0]; let kos=0;
  for(let i=0;i<60*90 && m.state!=='results';i++){ if(f.alive&&f.state!=='respawn'&&f.state!=='ko'){f.onGround=false;f.platform=null;f.y=m.stage.blast.bottom-60;f.setState('air');}
    const b=f.alive; m.step(); if(b&&!f.alive)kos++; }
  check('stock mode still ends the match', m.state==='results' && f.stocks===0, `KOs=${kos} stocks=${f.stocks} state=${m.state} winner=${m.results&&m.results.rows[0].name}`); }

// 4 buffers survive hitlag
{ const m=makeMatch(); skipCountdown(m); const [a,v]=m.fighters;
  for(let i=0;i<200;i++) m.step();
  a.x=-2.2; v.x=2.2; a.facing=1; v.facing=-1;
  for(const f of [a,v]){ f.onGround=true; f.platform=m.stage.main; f.y=0; f.vx=0; f.vy=0; }
  v.setState('idle'); a.startMove('SigSide');
  let hl=0, atPress=0, after=0, started=false;
  for(let i=0;i<200;i++){ if(!started && v.hitlag>0){ started=true; hl=v.hitlag;
      m._input.set('p1',{jump:true,jumpHeld:true,anyPress:true}); m.step(); atPress=v.buffer.jump; m._input.clear('p1');
      while(v.hitlag>0) m.step(); after=v.buffer.jump; break; } m.step(); }
  check('input buffer frozen during hitlag', after===atPress && atPress>0, `hitlag=${hl}f buffer ${atPress} -> ${after} (was ${atPress} -> 0)`); }

// 5 DI now bends the launch during hitlag
{ const run=(di)=>{ const m=makeMatch(); skipCountdown(m); const [a,v]=m.fighters;
    for(let i=0;i<200;i++) m.step();
    a.x=-2.2; v.x=2.2; a.facing=1; v.facing=-1;
    for(const f of [a,v]){ f.onGround=true; f.platform=m.stage.main; f.y=0; f.vx=0; f.vy=0; }
    v.setState('idle'); a.startMove('SigSide');
    for(let i=0;i<200;i++){ if(v.hitlag>0){ if(di) m._input.set('p1',di); while(v.hitlag>0) m.step(); return {vx:v.vx,vy:v.vy}; } m.step(); }
    return null; };
  const n=run(null), up=run({x:0,y:1}), dn=run({x:0,y:-1});
  const ang=(v)=>Math.atan2(v.vy,v.vx)*180/Math.PI;
  const spread=Math.abs(ang(up)-ang(dn));
  check('DI held through hitlag bends the angle', spread>1e-6,
    `no DI ${ang(n).toFixed(2)}deg | up ${ang(up).toFixed(2)}deg | down ${ang(dn).toFixed(2)}deg | spread ${spread.toFixed(2)}deg (cap 2x12=24, was 0.00)`);
  check('launch speed unchanged by DI', Math.abs(Math.hypot(n.vx,n.vy)-Math.hypot(up.vx,up.vy))<1e-9,
    `|v| ${Math.hypot(n.vx,n.vy).toFixed(3)} vs ${Math.hypot(up.vx,up.vy).toFixed(3)} - DI bends the angle only, as specified`); }

// 6 tech window really is TECH.window frames wide
{ const setup=()=>{ const m=makeMatch(); skipCountdown(m); const f=m.fighters[0];
    for(let i=0;i<200;i++) m.step();
    // x=-33 is over bare main stage on Potting Bench: no soft platform to land on early.
    f.x=-33; f.onGround=false; f.platform=null; f.y=30; f.vy=-60; f.vx=0; f.tumbling=true; f.hitstun=40; f.setState('hitstun');
    return {m,f}; };
  let LAND=-1;
  { const {m,f}=setup(); for(let i=0;i<300;i++){ m.step(); if(f.onGround||['knockdown','tech'].includes(f.state)){ LAND=i; break; } } }
  const at=(ago)=>{ const {m,f}=setup();
    for(let i=0;i<300;i++){ if(i===LAND-ago) m._input.set('p0',{guard:true,guardHeld:true,anyPress:true}); else m._input.clear('p0');
      m.step(); if(f.onGround||['knockdown','tech'].includes(f.state)) return f.state; } return 'timeout'; };
  const inside=[0,1,3,5,7].map(at), outside=[8,9,14,25].map(at);
  check('tech succeeds across the whole window', inside.every(s=>s==='tech'),
    `guard 0/1/3/5/7f before landing -> ${inside.join(', ')}`);
  check('tech fails past the window', outside.every(s=>s!=='tech'),
    `guard 8/9/14/25f before landing -> ${outside.join(', ')} (TECH.window=${TECH.window} => press frames 0-${TECH.window-1})`); }

// 7 jump press is no longer swallowed with no jumps left
{ const m=makeMatch(); skipCountdown(m); const f=m.fighters[0];
  for(let i=0;i<200;i++) m.step();
  f.onGround=false; f.platform=null; f.setState('air'); f.jumpsLeft=0; f.y=8; f.vy=0;
  m._input.set('p0',{jump:true,jumpHeld:true,anyPress:true}); m.step(); const b=f.buffer.jump; m._input.clear('p0');
  check('jump press survives an empty jump count', b>0, `buffer.jump=${b} after pressing with jumpsLeft=0 (was 0)`); }

// 8 blockstun matches knockback.js
{ const m=makeMatch(); skipCountdown(m); const v=m.fighters[1];
  const { blockstun } = await import('../src/engine/knockback.js');
  v.setState('shield'); v.applyBlock({damage:10,facing:1,perfect:false});
  check('blockstun uses knockback.js', v.blockstun===blockstun(10), `applyBlock(10) -> ${v.blockstun}, knockback.blockstun(10) -> ${blockstun(10)}`); }

// 9 a full match between two bots still runs start to finish
{ const m=makeMatch({mode:'StockFFA',stocks:2}); m.fighters.forEach(f=>{f.isBot=true;f.botLevel='normal';});
  let f0=0; while(m.state!=='results' && f0<60*300){ m.step(); f0++; }
  check('bot vs bot match completes', m.state==='results', `${f0} frames (${(f0/60).toFixed(1)}s), winner=${m.results&&m.results.rows[0].name}, rows=${m.results&&m.results.rows.length}`); }

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail?1:0);
