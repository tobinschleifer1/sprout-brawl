// Team play (combat phase 3) through the real Combat and Match, for tests/team-parity.luau: scripted
// hits among four fighters, with clock gaps, KOs and combos ending - and the team flag on every hit,
// every KO's credit and assists, and everyone's assists and meter after each step. The combat and
// match traces have two fighters, so they hold no team combo and one assist.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const { makeMatch, skipCountdown } = await import('../../web/test/harness.mjs');
const S = (v) => (typeof v === 'number' ? String(v) : v);
// steps: ['hit', a, v] | ['wait', v, frames] | ['ko', v] | ['respawn', v] | ['free', v] (the combo ends)
//      | ['launch', v, dx, dy] (v tumbling at dx, dy from fighter 0) | ['catch', c] (c presses grab)
//      | ['place', [x0, x1, x2, x3]] (everyone standing, idle) | ['hold', f, input] | ['release', f]
//      | ['press', f, input] (one frame) | ['run', frames] - the real match loop, for team throws
const SCRIPTS = [
  { teams: [0, 1, 0, 1], steps: [['hit', 0, 1], ['hit', 2, 1], ['hit', 0, 1], ['hit', 2, 1], ['ko', 1], ['hit', 2, 3], ['free', 3], ['hit', 0, 3]] },
  { teams: null, steps: [['hit', 1, 3], ['wait', 3, 100], ['hit', 2, 3], ['wait', 3, 379], ['hit', 0, 3], ['ko', 3], ['hit', 0, 2], ['wait', 2, 480], ['hit', 1, 2], ['ko', 2]] },
  { teams: null, steps: [['hit', 1, 2], ['hit', 0, 2], ['ko', 2], ['respawn', 2], ['hit', 3, 2], ['ko', 2]] },
  { teams: [0, 1, 0, 1], steps: [['launch', 2, 1.5, 0], ['catch', 0], ['launch', 2, 1.5, 0], ['catch', 0], ['wait', 2, 5], ['hit', 1, 2], ['launch', 2, 2.9, 2.9], ['catch', 0],
    ['launch', 3, 1, 0], ['catch', 0], ['wait', 2, 5], ['hit', 1, 2], ['launch', 2, 3.1, 0], ['catch', 0], ['air', 0], ['launch', 2, -2, 2], ['catch', 0]] },
  // team throws through the match loop: a fling into a foe, a boost, a teammate jumping free, a
  // back throw and a down throw
  { teams: [0, 1, 0, 1], steps: [['place', [0, 14, 2.4, -30]], ['press', 0, { grab: true }], ['run', 10], ['hold', 0, { x: 1 }], ['run', 20], ['release', 0], ['run', 40]] },
  { teams: [0, 1, 0, 1], steps: [['place', [0, 30, 2.4, -30]], ['spent', 2], ['press', 0, { grab: true }], ['run', 10], ['hold', 0, { y: 1 }], ['run', 20], ['release', 0], ['run', 30]] },
  { teams: [0, 1, 0, 1], steps: [['place', [0, 30, 2.4, -30]], ['press', 0, { grab: true }], ['run', 10], ['press', 2, { jump: true }], ['run', 12]] },
  { teams: [0, 1, 0, 1], steps: [['place', [0, -13, 2.4, 30]], ['press', 0, { grab: true }], ['run', 10], ['hold', 0, { x: -1 }], ['run', 20], ['release', 0], ['run', 40]] },
  { teams: [0, 1, 0, 1], steps: [['place', [0, 15, 2.4, -30]], ['press', 0, { grab: true }], ['run', 10], ['hold', 0, { y: -1 }], ['run', 20], ['release', 0], ['run', 40]] },
  { teams: [0, 0, 1, 1], steps: [['hit', 2, 0], ['hit', 3, 0], ['hit', 2, 0], ['free', 0], ['hit', 3, 0], ['hit', 0, 2], ['hit', 1, 2], ['ko', 2], ['ko', 0]] },
];
const out = [];
for (const sc of SCRIPTS) {
  const m = skipCountdown(makeMatch({ mode: sc.teams ? 'StockTeams' : 'StockFFA', stocks: 3,
    loadouts: [0, 1, 2, 3].map((i) => [['Classic', 'Noir', 'Ember', 'Moss'][i], 'Sword']) }));
  m.fighters.forEach((f, i) => { if (sc.teams) f.team = sc.teams[i]; });
  const rows = [];
  for (const [kind, x, y, z] of sc.steps) {
    const place = () => m.fighters.forEach((f, i) => { f.x = -6 + i * 3; f.y = 0; f.vx = 0; f.vy = 0; f.onGround = true; f.platform = m.stage.main; f.invincible = 0; });
    m.combat.events.length = 0; m.events.length = 0;
    let row;
    if (kind === 'hit') {
      place();
      const a = m.fighters[x], v = m.fighters[y];
      a.moveSerial++; v.hitlag = 0;
      if (v.state !== 'hitstun') v.setState('idle');
      m.combat.resolveHit(a, v, a.char.moves.LightNeutral1, null, null, {});
      const e = m.combat.events.find((ev) => ev.type === 'hit');
      row = [kind, e ? e.team : null, e ? S(e.combo) : null];
    } else if (kind === 'wait') { for (let i = 0; i < y; i++) m.fighters[x].frameCount++; row = [kind]; }
    else if (kind === 'launch') {
      const c = m.fighters[0], v = m.fighters[x];
      v.x = c.x + y; v.y = c.y + z; v.onGround = false; v.platform = null;
      v.setState('hitstun'); v.hitstun = 30; v.tumbling = true; v.vx = 60; v.vy = 30; v.jumpsLeft = 0;
      row = [kind];
    } else if (kind === 'air') { const c = m.fighters[x]; c.y = 6; c.onGround = false; c.platform = null; c.setState('air'); c.vy = 0; row = [kind]; }
    else if (kind === 'catch') {
      const c = m.fighters[x];
      // through the catcher's own step, so the ground and the air paths are the ones exercised
      c.buffer.grab = 8;
      c.step({ stage: m.stage, combat: m.combat, fighters: m.fighters });
      const e = m.combat.events.find((ev) => ev.type === 'catch');
      const caught = !!e;
      row = [kind, caught ? 1 : 0, e ? S(e.ally) : null, m.fighters.map((f) => [f.state, f.vx.toFixed(6), f.vy.toFixed(6), S(f.invincible), S(f.jumpsLeft), f.tumbling, S(f.lag)].join(':')).join(' ')];
      c.setState('idle'); c.lag = 0; c.y = 0; c.onGround = true; c.platform = m.stage.main;
    }
    else if (kind === 'place') {
      m.fighters.forEach((f, i) => { f.x = x[i]; f.y = 0; f.vx = 0; f.vy = 0; f.onGround = true; f.platform = m.stage.main; f.setState('idle'); f.invincible = 0; f.facing = i === 0 ? 1 : -1; });
      row = [kind];
    } else if (kind === 'spent') { const f = m.fighters[x]; f.jumpsLeft = 0; f.airDodgeUsed = true; f.recoveryUsed = true; row = [kind]; }
    else if (kind === 'hold') { m._input.set(`p${x}`, { anyPress: false, ...y }); row = [kind]; }
    else if (kind === 'release') { m._input.clear(`p${x}`); row = [kind]; }
    else if (kind === 'press' || kind === 'run') {
      if (kind === 'press') m._input.set(`p${x}`, { ...y, anyPress: true });
      const n = kind === 'press' ? 1 : x;
      const seen = [];
      for (let i = 0; i < n; i++) { m.step(); for (const e of m.events) if (['hit', 'teamboost', 'teamfling', 'grabhit', 'block', 'armor'].includes(e.type)) seen.push(e.type); m.events.length = 0; }
      if (kind === 'press') m._input.clear(`p${x}`);
      row = [kind, seen.join(','), m.fighters.map((f) => [f.state, f.x.toFixed(6), f.y.toFixed(6), f.vx.toFixed(6), f.vy.toFixed(6), S(f.percent), S(f.jumpsLeft), String(f.recoveryUsed)].join(':')).join(' ')];
    }
    else if (kind === 'respawn') { m.respawn(m.fighters[x]); m.fighters[x].setState('idle'); m.fighters[x].invincible = 0; row = [kind, S(m.fighters[x].alive ? 1 : 0), null]; }
    else if (kind === 'free') { const v = m.fighters[x]; v.setState('idle'); v.step({ stage: m.stage, combat: m.combat, fighters: m.fighters }); row = [kind, S(v.comboHits), S(v.comboBy)]; }
    else { m.knockOut(m.fighters[x]); const e = m.events.find((ev) => ev.type === 'ko'); row = [kind, S(e.by), e.assists.join(',')]; }
    row.push(m.fighters.map((f) => `${f.stats.kos}/${f.stats.assists}/${f.ultCharge}`).join(' '));
    rows.push(row);
  }
  out.push({ ...sc, rows });
}
fs.writeFileSync(path.join(HERE, '../tests/team-fixture.json'), JSON.stringify({ scripts: out }));
console.log(`team fixture: ${out.length} scripts, ${out.reduce((n, s) => n + s.rows.length, 0)} steps`);
