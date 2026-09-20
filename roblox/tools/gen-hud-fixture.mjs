// Record percentColor for the Luau port to reproduce.
//
//     node tools/gen-hud-fixture.mjs
//
// It is a piecewise linear ramp over five stops, and it is the one piece of the HUD that is pure
// arithmetic rather than layout - so it is the one piece that can be held to the JavaScript
// exactly. Getting a stop or an interpolation wrong produces a HUD that still works and quietly
// tells the player the wrong thing about how close they are to dying.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const { percentColor, PLAYER_COLORS, PLAYER_MARKS, TEAM_COLORS } = await import('../../web/src/ui/hud.js');

const rows = [];
// Every stop, every midpoint, both sides of every boundary, and well past the clamp at 200.
for (let p = -20; p <= 320; p += 0.5) {
  rows.push({ p: String(p), c: percentColor(p) });
}
for (const p of [0, 49.999, 50, 50.001, 99.999, 100, 149.999, 150, 199.999, 200, 200.001, 1e6]) {
  rows.push({ p: String(p), c: percentColor(p) });
}

const out = { rows, playerColors: PLAYER_COLORS, playerMarks: PLAYER_MARKS, teamColors: TEAM_COLORS };
fs.writeFileSync(path.join(HERE, '../tests/hud-fixture.json'), JSON.stringify(out));
console.log(`hud fixture: ${rows.length} percent samples, ${PLAYER_COLORS.length} player colours`);
