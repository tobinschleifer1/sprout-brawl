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
const SCRIPTS = [
  { teams: [0, 1, 0, 1], steps: [['hit', 0, 1], ['hit', 2, 1], ['hit', 0, 1], ['hit', 2, 1], ['ko', 1], ['hit', 2, 3], ['free', 3], ['hit', 0, 3]] },
  { teams: null, steps: [['hit', 1, 3], ['wait', 3, 100], ['hit', 2, 3], ['wait', 3, 379], ['hit', 0, 3], ['ko', 3], ['hit', 0, 2], ['wait', 2, 480], ['hit', 1, 2], ['ko', 2]] },
  { teams: null, steps: [['hit', 1, 2], ['hit', 0, 2], ['ko', 2], ['respawn', 2], ['hit', 3, 2], ['ko', 2]] },
  { teams: [0, 0, 1, 1], steps: [['hit', 2, 0], ['hit', 3, 0], ['hit', 2, 0], ['free', 0], ['hit', 3, 0], ['hit', 0, 2], ['hit', 1, 2], ['ko', 2], ['ko', 0]] },
];
const out = [];
for (const sc of SCRIPTS) {
  const m = skipCountdown(makeMatch({ mode: sc.teams ? 'StockTeams' : 'StockFFA', stocks: 3,
    loadouts: [0, 1, 2, 3].map((i) => [['Classic', 'Noir', 'Ember', 'Moss'][i], 'Sword']) }));
  m.fighters.forEach((f, i) => { if (sc.teams) f.team = sc.teams[i]; });
  const rows = [];
  for (const [kind, x, y] of sc.steps) {
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
