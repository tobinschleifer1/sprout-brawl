// Development tool: merges tools/weapon-matrix.luau's shards into a win-rate table (markdown).
//   node tools/weapon-matrix.mjs shard1.json shard2.json ... > matrix.md
import fs from 'node:fs';
const rows = process.argv.slice(2).flatMap((f) => JSON.parse(fs.readFileSync(f, 'utf8')).results);
const meta = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const ids = [...new Set(rows.flatMap((r) => [r.a, r.b]))];
const cell = {}, tot = Object.fromEntries(ids.map((id) => [id, { w: 0, n: 0, t: 0, f: 0 }]));
for (const r of rows) {
  cell[`${r.a}|${r.b}`] = [r.aWins, r.games];
  cell[`${r.b}|${r.a}`] = [r.games - r.aWins, r.games];
  tot[r.a].w += r.aWins; tot[r.a].n += r.games; tot[r.a].t += r.timeouts; tot[r.a].f += r.frames;
  tot[r.b].w += r.games - r.aWins; tot[r.b].n += r.games; tot[r.b].t += r.timeouts; tot[r.b].f += r.frames;
}
ids.sort((x, y) => tot[y].w / tot[y].n - tot[x].w / tot[x].n);
const pct = (w, n) => (n ? Math.round((100 * w) / n) : '-');
let out = `Bot level ${meta.botLevel}, ${meta.matchesPerPair} matches a pair, 3 stocks, no items.\n\n`;
out += '| Weapon | Win % | Games | Timeouts | Avg match (s) |\n|---|---|---|---|---|\n';
for (const id of ids) { const t = tot[id]; out += `| ${id} | ${pct(t.w, t.n)} | ${t.n} | ${t.t} | ${t.n ? Math.round(t.f / t.n / 60) : '-'} |\n`; }
out += `\nRow's win % against column:\n\n| | ${ids.map((id) => id.slice(0, 5)).join(' | ')} |\n|---|${ids.map(() => '---').join('|')}|\n`;
for (const a of ids) out += `| ${a} | ${ids.map((b) => (a === b ? '·' : pct(...(cell[`${a}|${b}`] || [0, 0])))).join(' | ')} |\n`;
process.stdout.write(out);
