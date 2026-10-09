// Lag compensation (LAG_COMP, combat phase 4) through the real Combat and Match, for
// tests/lagcomp-parity.luau: probes of one jab or one grab at a victim who moves along a path, with
// the attacker looking 0..13 frames back - past the cap - and the victim sometimes KO'd and
// respawned inside the window, invincible or shielding at the moment of the swing. The bot trace
// (gen-ai-traces 'bots looking back') holds rewinds in real fights; it rarely reaches a grab, a
// respawn or the cap's edge, and these do on purpose.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const { makeMatch, skipCountdown } = await import('../../web/test/harness.mjs');
const S = (v) => (typeof v === 'number' ? String(v) : v);

let seed = 2024;
const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
const SPOTS = [1.2, 2, 2.6, 3.4, 4.4, 9];
const HISTORY = 16, AFTER = 12;
const probes = [];
for (let n = 0; n < 360; n++) {
  const kind = n % 3 === 2 ? 'grab' : 'jab';
  const pathX = [];
  let x = SPOTS[Math.floor(rnd() * SPOTS.length)];
  for (let t = 0; t < HISTORY + AFTER; t++) { if (rnd() < 0.3) x = SPOTS[Math.floor(rnd() * SPOTS.length)]; pathX.push(x); }
  const dead = rnd() < 0.15 ? [Math.floor(rnd() * 8), 8 + Math.floor(rnd() * 6)] : null;
  const now = kind === 'jab' && rnd() < 0.2 ? (rnd() < 0.5 ? 'invincible' : 'shield') : null;
  probes.push({ kind, rewind: Math.floor(rnd() * 14), path: pathX, dead, now });
}

const rows = [];
for (const p of probes) {
  const m = skipCountdown(makeMatch({ loadouts: [['Classic', 'Sword'], ['Noir', 'Sword']] }));
  const [a, v] = m.fighters;
  for (const f of [a, v]) { f.y = 0; f.vx = 0; f.vy = 0; f.onGround = true; f.platform = m.stage.main; f.setState('idle'); f.invincible = 0; }
  a.x = 0; a.facing = 1; v.facing = -1;
  m.combat.rewindOf = (f) => (f === a ? p.rewind : 0);
  const hold = (t) => { v.x = p.path[t]; v.y = 0; v.vx = 0; v.vy = 0; if (p.now !== 'invincible') v.invincible = 0; };
  for (let t = 0; t < HISTORY; t++) {
    if (p.dead && t === p.dead[0]) m.knockOut(v);
    if (p.dead && t === p.dead[1]) { m.respawn(v); v.setState('idle'); v.onGround = true; v.platform = m.stage.main; }
    hold(t); m.step();
  }
  if (p.now === 'invincible') v.invincible = 40;
  if (p.now === 'shield') { m._input.set('p1', { guardHeld: true }); v.setState('shield'); v.shield = 50; v.sf = 30; }
  hold(HISTORY);
  m.events.length = 0;
  const seen = [];
  if (p.kind === 'grab') {
    m.combat.checkGrab(a);
    seen.push(v.state);
  } else {
    a.startMove(a.char.moves.LightNeutral1);
    for (let t = HISTORY; t < HISTORY + AFTER; t++) {
      if (v.state !== 'hitstun') hold(t);
      m.step();
      for (const e of m.events) if (e.victim === v.index) seen.push(e.type);
      m.events.length = 0;
    }
  }
  rows.push([seen.join(','), S(v.percent), v.state]);
}
const landed = rows.filter((r) => r[0].includes('hit') || r[0].includes('grabbed')).length;
fs.writeFileSync(path.join(HERE, '../tests/lagcomp-fixture.json'), JSON.stringify({ history: HISTORY, after: AFTER, probes, rows }));
console.log(`lag compensation fixture: ${probes.length} probes, ${landed} landed`);
