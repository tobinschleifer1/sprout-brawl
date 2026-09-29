// Export the web game as a standalone folder, ready to upload to a web portal (CrazyGames et al.).
//
//   node tools/export.mjs <out-dir>
//
// Copies exactly what the game loads: index.html, style.css, and every module src/main.js reaches
// through static or dynamic imports - walked, not globbed, so the tests, the tools, the dev pages
// (anim.html, maps.html...) and the modules only the Roblox build uses (the lobby, the climb) stay
// behind. Stage backgrounds a player has dropped into assets/backgrounds/ come along too. The copy is
// then checked: every import in it resolves to a file in it, so a missing module fails here rather
// than as a black screen on the portal.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const WEB = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const out = process.argv[2];
if (!out) { console.error('usage: node tools/export.mjs <out-dir>'); process.exit(1); }
const OUT = path.resolve(out);
if (OUT === WEB || OUT.startsWith(WEB + path.sep)) { console.error('export somewhere outside web/'); process.exit(1); }

// import x from './a.js'; import './a.js'; export { x } from './a.js'; import('./a.js')
const IMPORT = /(?:\bimport\s*(?:[\w*{}\s,]+\sfrom\s*)?|\bexport\s*[\w*{}\s,]+\sfrom\s*|\bimport\s*\(\s*)['"](\.{1,2}\/[^'"]+)['"]/g;

function walk(entry) {
  const seen = new Set();
  const stack = [entry];
  while (stack.length) {
    const file = stack.pop();
    if (seen.has(file)) continue;
    if (!fs.existsSync(file)) throw new Error(`missing module: ${path.relative(WEB, file)}`);
    seen.add(file);
    const src = fs.readFileSync(file, 'utf8');
    for (const m of src.matchAll(IMPORT)) stack.push(path.resolve(path.dirname(file), m[1]));
  }
  return [...seen];
}

const files = [path.join(WEB, 'index.html'), path.join(WEB, 'style.css'), ...walk(path.join(WEB, 'src/main.js'))];
const bgDir = path.join(WEB, 'assets/backgrounds');
if (fs.existsSync(bgDir)) {
  for (const f of fs.readdirSync(bgDir)) if (/\.(png|jpe?g|webp|gif)$/i.test(f)) files.push(path.join(bgDir, f));
}

const shipped = files.filter((f) => path.dirname(f) === bgDir).map((f) => path.basename(f));

fs.rmSync(OUT, { recursive: true, force: true });
let bytes = 0;
for (const f of files) {
  const dest = path.join(OUT, path.relative(WEB, f));
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(f, dest);
  bytes += fs.statSync(f).size;
}

// The build says which backgrounds it ships, so the game asks for those and nothing else
// (data/backgrounds.js backgroundCandidates) - no failed requests on the portal.
const indexPath = path.join(OUT, 'index.html');
const html = fs.readFileSync(indexPath, 'utf8');
const tag = `<script>window.BLOCKFALL_BACKGROUNDS = ${JSON.stringify(shipped)};</script>\n`;
if (!html.includes('<script type="module"')) throw new Error('index.html has no module script to put the background list before');
fs.writeFileSync(indexPath, html.replace('<script type="module"', tag + '<script type="module"'));

// The copy stands on its own: every relative import in it resolves inside it.
const copied = walk(path.join(OUT, 'src/main.js'));
console.log(`exported ${files.length} files, ${(bytes / 1024).toFixed(0)} KB -> ${OUT}`);
console.log(`checked: ${copied.length} modules resolve inside the export`);
