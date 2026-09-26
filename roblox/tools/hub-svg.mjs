// Turns tools/render-hub.luau's JSON into an SVG. Development tool.
import fs from 'node:fs';
const [,, input, output] = process.argv;
const d = JSON.parse(fs.readFileSync(input, 'utf8'));
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
let out = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${d.w} ${d.w}" width="${d.w}" height="${d.w}" shape-rendering="crispEdges"><rect width="${d.w}" height="${d.w}" fill="#000"/>`;
for (const s of d.shapes) {
  if (s[0] === 'p') out += `<polygon points="${s.slice(1, 5).map((p) => p.join(',')).join(' ')}" fill="${s[5]}" fill-opacity="${s[6]}"/>`;
  else out += `<ellipse cx="${s[1]}" cy="${s[2]}" rx="${s[3]}" ry="${s[4]}" fill="${s[5]}" fill-opacity="${s[6]}"/>`;
}
for (const [x, y, w, h, text, colour, size, bg] of d.texts) {
  if (bg) out += `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${bg}" fill-opacity="0.88"/>`;
  const lines = String(text).split('\n');
  lines.forEach((ln, i) => { out += `<text x="${x + w / 2}" y="${y + h / 2 + (i - (lines.length - 1) / 2) * size * 1.15 + size * 0.35}" fill="${colour}" font-family="Arial Black, Helvetica" font-weight="700" font-size="${size}" text-anchor="middle">${esc(ln)}</text>`; });
}
fs.writeFileSync(output, out + '</svg>');
console.log(`wrote ${output}`);
