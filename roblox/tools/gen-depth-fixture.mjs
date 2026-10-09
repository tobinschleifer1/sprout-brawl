// Depth (combat phase 2) through the real Combat, for tests/depth-parity.luau.
//
// Staling (STALE in config.js): sequences of probe moves landed on a victim
// held fresh to combos, and the damage and launch each hit dealt. The
// combat traces cannot reach this - no weapon's multi-hit move deals enough per hit for one step of
// staling to survive rounding, so a per-swing slip never shows there.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const { makeMatch, skipCountdown } = await import('../../web/test/harness.mjs');
const S = (v) => (typeof v === 'number' ? String(v) : v);
// [id, damage, sameSwing, shield]; ids repeat, swings repeat, some are blocked or the ultimate
const SEQS = [
  Array.from({ length: 11 }, () => ['Probe', 20, false, false]),
  Array.from({ length: 16 }, (_, n) => [['A', 'B', 'C', 'D'][n % 4], 20, false, false]),
  [['Old', 20], ...Array.from({ length: 8 }, (_, n) => [`O${n}`, 20]), ['Old', 20]].map(([id, d]) => [id, d, false, false]),
  [...Array.from({ length: 5 }, () => ['Multi', 20, false, false]), ['Multi', 20, true, false], ['Multi', 20, true, false], ['Multi', 20, false, false], ['Multi', 20, true, false]],
  [...Array.from({ length: 4 }, () => ['Wall', 20, false, true]), ['Wall', 20, false, false], ['Wall', 20, false, false]],
  Array.from({ length: 7 }, () => ['Ultimate', 20, false, false]),
  Array.from({ length: 12 }, (_, n) => ['Small', 3 + (n % 3), false, false]),
];
const out = [];
for (const seq of SEQS) {
  const m = skipCountdown(makeMatch({ loadouts: [['Classic', 'Sword'], ['Noir', 'Sword']] }));
  const [a, v] = m.fighters;
  const rows = [];
  for (const [id, damage, same, shield] of seq) {
    a.x = 0; v.x = 2; a.facing = 1; v.facing = -1;
    for (const f of [a, v]) { f.y = 0; f.vx = 0; f.vy = 0; f.onGround = true; f.platform = m.stage.main; f.invincible = 0; }
    if (!same) a.moveSerial++;
    v.percent = 50; v.comboHits = 0; v.comboKey = -1; v.hitlag = 0;
    if (shield) { v.setState('shield'); v.sf = 30; v.shield = 50; } else v.setState('idle');
    m.combat.events.length = 0;
    m.combat.resolveHit(a, v, { id, damage, base: 12, growth: 1.0, angle: 45, startup: 3, active: 3, recovery: 10, kind: 'melee' }, null, null, {});
    const hit = m.combat.events.find((e) => e.type === 'hit');
    rows.push([S(v.percent - 50), hit ? S(hit.launch) : null, a.staleMoves.join(',')]);
  }
  out.push({ seq, rows });
}
// Armour: a light (and a heavy) landed on every frame of each weapon's heavies' startups and just
// past them - absorbed or not, exactly where the startup ends.
const armour = [];
const { WEAPONS } = await import('../../web/src/data/weapons/index.js');
for (const w of WEAPONS) {
  for (const id of ['SigSide', 'SigNeutral', 'SigDown']) {
    for (const by of ['LightNeutral1', 'SigSide']) {
      const probeM = skipCountdown(makeMatch({ loadouts: [['Classic', 'Sword'], ['Noir', w.id]] }));
      const v0 = probeM.fighters[1];
      v0.startMove(v0.char.moves[id]);
      const last = v0.startupEff + 2;
      for (let mf = 0; mf <= last; mf++) {
        const m = skipCountdown(makeMatch({ loadouts: [['Classic', 'Sword'], ['Noir', w.id]] }));
        const [a, v] = m.fighters;
        a.x = 0; v.x = 2; a.facing = 1; v.facing = -1;
        for (const f of [a, v]) { f.y = 0; f.vx = 0; f.vy = 0; f.onGround = true; f.platform = m.stage.main; f.invincible = 0; f.setState('idle'); }
        v.startMove(v.char.moves[id]);
        v.mf = mf;
        m.combat.events.length = 0;
        m.combat.resolveHit(a, v, a.char.moves[by], null, null, {});
        armour.push([w.id, id, by, mf, m.combat.events.some((e) => e.type === 'armor') ? 1 : 0, v.state, S(v.percent)]);
      }
    }
  }
}
fs.writeFileSync(path.join(HERE, '../tests/depth-fixture.json'), JSON.stringify({ cases: out, armour }));
console.log(`depth fixture: ${out.length} staling sequences, ${out.reduce((n, c) => n + c.rows.length, 0)} hits; ${armour.length} armour probes`);
