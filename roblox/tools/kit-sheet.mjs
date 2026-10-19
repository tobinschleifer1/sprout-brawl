// The shipping Luau portrait renderer, presented as an SVG contact sheet.
// node tools/kit-sheet.mjs out.svg [presets|category[:head]|random|clothing] [--half|--match]
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const [out = 'kit.svg', mode = 'presets', flag = ''] = process.argv.slice(2);
const cwd = fileURLToPath(new URL('../', import.meta.url));
const d = JSON.parse(execFileSync('lune', ['run', 'tools/render-portraits', '-', mode, flag], { cwd, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 }));
const cols = Math.max(3, Math.ceil(Math.sqrt(d.frames.length * (d.h + 32) / d.w)));
const rows = Math.ceil(d.frames.length / cols), cellH = d.h + 32;
const escape = (s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const svg = [`<svg xmlns="http://www.w3.org/2000/svg" width="${cols * d.w}" height="${rows * cellH}" shape-rendering="crispEdges">`, '<rect width="100%" height="100%" fill="#2a3340"/>'];
d.frames.forEach((frame, i) => {
  svg.push(`<g transform="translate(${i % cols * d.w},${Math.floor(i / cols) * cellH})">`);
  for (const s of frame.shapes) {
    if (s[0] === 'p') svg.push(`<polygon points="${s.slice(1, 5).map(([x, y]) => `${x},${y}`).join(' ')}" fill="${s[5]}" fill-opacity="${s[6]}"/>`);
    else svg.push(`<ellipse cx="${s[1]}" cy="${s[2]}" rx="${s[3]}" ry="${s[4]}" fill="${s[5]}" fill-opacity="${s[6]}"/>`);
  }
  svg.push(`<text x="${d.w / 2}" y="${d.h + 20}" font-size="13" text-anchor="middle" fill="#ddd" font-family="Helvetica">${escape(frame.label)}</text></g>`);
});
svg.push('</svg>');
fs.writeFileSync(out, svg.join('\n'));
console.log(`${d.frames.length} portraits -> ${out}`);
