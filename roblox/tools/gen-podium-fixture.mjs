// The podium layout, places and stat values for tests/podium-parity.luau.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const { podiumLayout, places, statValue, ordinal, podiumTitle, STATS } = await import('../../web/src/render2d/podium.js');
const S = String;
const layouts = [];
for (const n of [1, 2, 3, 4, 6, 8]) {
  for (const [W, H] of [[480, 270], [1280, 720], [812, 375], [400, 420]]) {
    layouts.push({ n, W, H, slots: podiumLayout(n, W, H).map((s) => [s.cx, s.top, s.colW, s.figureH,
      s.pillar.x, s.pillar.y, s.pillar.w, s.pillar.h, s.cap.x, s.cap.y, s.cap.w, s.cap.h,
      s.card.x, s.card.y, s.card.w, s.card.h, s.rowH].map(S)) });
  }
}
const teamRows = [{ team: 1 }, { team: 1 }, { team: 0 }, { team: 0 }];
const ffaRows = [{ team: 0 }, { team: 1 }, { team: 2 }, { team: 3 }];
const row = { score: 3, kos: 4, falls: 1, sds: 0, damage: 184.5, taken: 91.49 };
fs.writeFileSync(path.join(HERE, '../tests/podium-fixture.json'), JSON.stringify({
  layouts,
  places: { teams: places(teamRows, true), ffa: places(ffaRows, false), ffaTeamsFlag: places(ffaRows, true) },
  stats: STATS.map(([l, f]) => [l, f, S(statValue(row, f))]),
  titles: [
    ['duel as teams', [{ name: 'Ana', team: 1 }, { name: 'Bo', team: 0 }], true],
    ['2v2', [{ name: 'Ana', team: 0 }, { name: 'Cy', team: 0 }, { name: 'Bo', team: 1 }, { name: 'Di', team: 1 }], true],
    ['ffa', [{ name: 'Ana', team: 0 }, { name: 'Bo', team: 1 }, { name: 'Cy', team: 2 }], false],
    ['empty', [], true],
  ].map(([k, rows, teams]) => ({ k, rows, teams, want: podiumTitle(rows, teams) })),
  ordinals: [1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111].map((n) => [n, ordinal(n)]),
}));
console.log(`podium fixture: ${layouts.length} layouts`);
