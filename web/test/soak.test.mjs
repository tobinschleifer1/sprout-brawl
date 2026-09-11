import { makeMatch, skipCountdown } from './harness.mjs';
import { WEAPONS } from '../src/data/weapons/index.js';
import { STAGES } from '../src/data/stages/index.js';
const ids=WEAPONS.map(w=>w.id);
const AV=['Classic','Noir','Ember','Moss'];
let runs=0, bad=[], totalFrames=0;
const finite=(f)=>[f.x,f.y,f.vx,f.vy,f.percent,f.hitstun,f.shield].every(Number.isFinite);
for (const st of STAGES) {
  for (let k=0;k<ids.length;k++) {
    const four=[ids[k], ids[(k+1)%ids.length], ids[(k+3)%ids.length], ids[(k+5)%ids.length]];
    for (const mode of ['StockFFA','TimedFFA']) {
      const m=makeMatch({mode, stageId:st.id, loadouts:four.map((w,i)=>[AV[i%AV.length],w]), stocks:2, timeLimit:20});
      m.itemsOn=true;
      m.fighters.forEach((f,i)=>{ f.isBot=true; f.botLevel=['easy','normal','hard','normal'][i]; });
      skipCountdown(m);
      let n=0;
      try {
        // 8 minutes, not 4m20s. Measured across 18 four-player 3-stock bot matches on all six
        // stages: median length 9,632 frames with hazards and 9,737 without — hazards do not
        // lengthen a match — but the TAIL runs ~7% longer with them (p90 12,295 vs 11,438, max
        // 12,981 vs 11,873). The old 15,600 cap sat only 1.2x above that maximum, so a slow seed
        // tripped it roughly one run in five and reported a hazard bug that was not one.
        while (m.state!=='results' && n<60*480) {
          m.step(); n++;
          for (const f of m.fighters) if (!finite(f)) { bad.push(`${st.id}/${mode}/${f.name}: non-finite at frame ${n} x=${f.x} y=${f.y} vx=${f.vx} vy=${f.vy} pct=${f.percent}`); throw new Error('nonfinite'); }
        }
      } catch(e) { if (e.message!=='nonfinite') bad.push(`${st.id}/${mode}/${four.join('+')}: THREW at frame ${n}: ${e.message}`); }
      if (m.state!=='results') bad.push(`${st.id}/${mode}/${four.join('+')}: never reached results in ${n} frames (state=${m.state})`);
      totalFrames+=n; runs++;
    }
  }
}
console.log(`${runs} matches, ${totalFrames} simulated frames (${(totalFrames/60/60).toFixed(1)} minutes of gameplay)`);
console.log(`stages: ${STAGES.length}, weapons: ${ids.length}, items on, bots at 3 difficulties`);
if (bad.length){ console.log(`\n${bad.length} PROBLEMS:`); bad.slice(0,25).forEach(b=>console.log('  '+b)); process.exit(1); }
console.log('\nno crashes, no NaN/Infinity, every match reached a result.');
