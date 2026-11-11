// Development tool: prints tools/bot-stats.luau's JSON (one or more files of the same mode) as
// markdown tables.   node tools/bot-stats.mjs a.json [b.json ...]
import fs from 'node:fs';
const docs = process.argv.slice(2).map((f) => JSON.parse(fs.readFileSync(f, 'utf8')));
const pct = (a, b) => (b ? `${Math.round((100 * a) / b)}%` : '-');
const per = (a, frames) => (frames ? (a / (frames / 3600)).toFixed(1) : '-'); // a minute
let out = '';
for (const d of docs) {
  if (d.mode === 'ladder') {
    out += `### Difficulty ladder (${d.weapon} mirror, ${d.matchesPerPair} matches a pair)\n\n| | wins | vs | wins | timeouts |\n|---|---|---|---|---|\n`;
    for (const p of d.pairs) out += `| ${p.a} | ${p.aWins} | ${p.b} | ${p.bWins} | ${p.timeouts} |\n`;
    out += '\n| Level | Win % | Self-destructs (of deaths) | Damage dealt a minute | Shielding | Dodging | Moves started a minute |\n|---|---|---|---|---|---|---|\n';
    for (const [lvl, s] of Object.entries(d.levels)) {
      const moves = Object.values(s.moves).reduce((a, b) => a + b, 0);
      out += `| ${lvl} | ${pct(s.wins, s.matches)} | ${pct(s.sds, s.kos + s.sds)} | ${per(s.damage, s.frames)} | ${pct(s.shield, s.frames)} | ${pct(s.dodge, s.frames)} | ${per(moves, s.frames)} |\n`;
    }
    out += '\n';
  } else {
    out += `### Each weapon against itself (${d.level} bots, ${d.matchesPerPair} matches a weapon)\n\n`;
    out += '| Weapon | Self-destructs (of deaths) | Avg match (s) | Timeouts | Moves used | Signatures a minute | Ultimates a match | Shielding | Dodging | Grabbing | Never used |\n|---|---|---|---|---|---|---|---|---|---|---|\n';
    for (const s of d.rows) {
      const ids = Object.keys(s.moves);
      const sig = ids.filter((id) => id.startsWith('Sig')).reduce((a, id) => a + s.moves[id], 0);
      const ult = s.moves.Ultimate || 0;
      const fighterMatches = s.matches; // two fighters a match, both counted
      const never = []; // filled below from the move list printed by the luau side
      out += `| ${s.weapon} | ${pct(s.sds, s.kos + s.sds)} (${s.sds}/${s.kos + s.sds}) | ${Math.round(s.frames / s.matches / 60)} | ${s.timeouts} | ${ids.length}/${s.moveCount} | ${per(sig, s.frames)} | ${(ult / fighterMatches).toFixed(2)} | ${pct(s.shield, s.frames)} | ${pct(s.dodge, s.frames)} | ${pct(s.grab, s.frames)} | ${(s.never || []).join(' ') || '-'} |\n`;
    }
    out += '\n';
  }
}
process.stdout.write(out);
