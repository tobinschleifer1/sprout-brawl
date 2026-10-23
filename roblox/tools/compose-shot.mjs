// Development tool: one fight frame (tools/render-fight.luau's JSON) under a recorded screen's GUI
// (tools/render-ui.luau's JSON, e.g. the HUD), scaled to the GUI's size, as one tools/gui-svg.mjs
// input - so a map is judged with the HUD that is drawn over it in play.
//   node tools/compose-shot.mjs fight.json gui.json out.json
import fs from 'node:fs';
const [,, fightPath, guiPath, out] = process.argv;
const fight = JSON.parse(fs.readFileSync(fightPath, 'utf8'));
const gui = JSON.parse(fs.readFileSync(guiPath, 'utf8'));
const k = gui.w / fight.w;
const shapes = fight.frames[0].shapes.map((s) => s[0] === 'p'
  ? ['p', ...s.slice(1, 5).map(([x, y]) => [x * k, y * k]), s[5], s[6]]
  : ['e', s[1] * k, s[2] * k, s[3] * k, s[4] * k, s[5], s[6]]);
// (the GUI recording's own canvas shapes are its stand-in backdrop: left out, the fight is the backdrop)
fs.writeFileSync(out, JSON.stringify({ w: gui.w, h: gui.h, shapes, nodes: gui.nodes }));
