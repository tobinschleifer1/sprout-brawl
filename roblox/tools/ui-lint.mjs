// Development tool: checks a GUI recording (tools/render-ui.luau, tools/render-select.luau) for
// neighbouring buttons whose outlines come closer than Ui.GAP leaves them: 8 px between outer
// strokes. Every pair of outlined buttons on the screen is measured, not a list of named rows; a
// named list is how round 7's Climb, Studio header and odds tabs were missed.
//   node tools/ui-lint.mjs a.json [b.json ...]      exit 1 when any screen has a pair too close
import fs from 'node:fs';
const MIN = 8;
let bad = 0;
for (const file of process.argv.slice(2)) {
  const d = JSON.parse(fs.readFileSync(file, 'utf8'));
  // outer boxes: a Roblox UIStroke in Border mode draws outside the box, its full width
  const boxes = [];
  for (const n of d.nodes) {
    // a chosen box's stepped brackets (Ui.brackets) are part of its outline too: their holder, plus
    // the ink drawn BRACKET_INK (2 px) round each bar
    const marks = n.name === 'Brackets';
    // and item cards (Shop, Locker, Workshop, crates): their outlines ran 2-4 px apart in a grid
    const card = /^(Card\d|Crate_|Hero$)/.test(n.name || '');
    if (!marks && ((!n.button && !card) || !n.stroke || !(n.strokeW > 0))) continue;
    const e = marks ? 2 : n.strokeW;
    let x0 = n.x - e, y0 = n.y - e, x1 = n.x + n.w + e, y1 = n.y + n.h + e;
    // what a scrolling area cuts off is not on screen
    if (n.clip) {
      const [cx, cy, cw, ch] = n.clip;
      if (n.x >= cx + cw || n.y >= cy + ch || n.x + n.w <= cx || n.y + n.h <= cy) continue;
      // (and the part of it, stroke included, that the area shows)
      x0 = Math.max(x0, cx); y0 = Math.max(y0, cy); x1 = Math.min(x1, cx + cw); y1 = Math.min(y1, cy + ch);
    }
    if (n.w <= 0 || n.h <= 0) continue;
    boxes.push({ layer: n.layer || 0, name: n.name || '?', text: n.text || '', x0, y0, x1, y1, inner: [n.x, n.y, n.x + n.w, n.y + n.h] });
  }
  // (brackets are measured against other boxes' outlines, not against the box they mark)
  const contains = (a, b) => a.inner[0] <= b.inner[0] && a.inner[1] <= b.inner[1] && a.inner[2] >= b.inner[2] && a.inner[3] >= b.inner[3];
  const found = [];
  for (let i = 0; i < boxes.length; i++) {
    for (let j = i + 1; j < boxes.length; j++) {
      const a = boxes[i], b = boxes[j];
      if (a.layer !== b.layer || contains(a, b) || contains(b, a)) continue;      // (a window over the screen is not its neighbour)
      const overlapX = Math.min(a.x1, b.x1) - Math.max(a.x0, b.x0);
      const overlapY = Math.min(a.y1, b.y1) - Math.max(a.y0, b.y0);
      // side by side (sharing some height) or stacked (sharing some width)
      let gap = null;
      if (overlapY > 0) gap = Math.max(a.x0, b.x0) - Math.min(a.x1, b.x1);
      if (overlapX > 0) gap = gap === null ? Math.max(a.y0, b.y0) - Math.min(a.y1, b.y1) : Math.max(gap, Math.max(a.y0, b.y0) - Math.min(a.y1, b.y1));
      // (overlapping by more than a stroke's width is one window layered over another - an odds
      // window over the tabs - not two neighbours crowding)
      if (gap !== null && gap < -12) continue;
      if (gap !== null && gap < MIN - 0.01) found.push(`${a.name}${a.text ? ` "${a.text}"` : ''} / ${b.name}${b.text ? ` "${b.text}"` : ''}: ${gap.toFixed(1)} px`);
    }
  }
  const screen = file.replace(/^.*\//, '').replace(/\.json$/, '');
  if (found.length) { bad++; console.log(`${screen}: ${found.length} pair(s) under ${MIN} px between outer strokes`); for (const f of found) console.log(`  ${f}`); }
}
process.exit(bad ? 1 : 0);
