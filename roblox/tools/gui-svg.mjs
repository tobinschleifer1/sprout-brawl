// Development tool: paints a GUI recording (tools/render-select.luau and friends) as an SVG - the
// canvas's shapes first, then every Frame / label / button with its corner radius, outline and
// text. Roblox's fonts are stood in for by close Google Fonts (Luckiest Guy is on both).
//   node tools/gui-svg.mjs in.json out.svg
import fs from 'node:fs';
const [,, input, output] = process.argv;
const d = JSON.parse(fs.readFileSync(input, 'utf8'));
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
const FONTS = { 'Font.LuckiestGuy': "'Luckiest Guy', Impact, sans-serif", 'Font.GothamBlack': "'Montserrat', Arial Black, sans-serif",
  'Font.GothamBold': "'Montserrat', Arial, sans-serif", 'Font.FredokaOne': "'Fredoka', Arial, sans-serif" };
let out = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${d.w} ${d.h}" width="${d.w}" height="${d.h}">`
  + `<style>@import url('https://fonts.googleapis.com/css2?family=Luckiest+Guy&amp;family=Montserrat:wght@700;900&amp;family=Fredoka:wght@600&amp;display=block');</style>`
  + `<rect width="${d.w}" height="${d.h}" fill="#000"/><g shape-rendering="crispEdges">`;
for (const s of d.shapes) {
  if (s[0] === 'p') out += `<polygon points="${s.slice(1, 5).map((p) => p.join(',')).join(' ')}" fill="${s[5]}" fill-opacity="${s[6]}"/>`;
  else out += `<ellipse cx="${s[1]}" cy="${s[2]}" rx="${s[3]}" ry="${s[4]}" fill="${s[5]}" fill-opacity="${s[6]}"/>`;
}
out += '</g>';
for (const n of d.nodes) {
  const r = n.radius ? Math.min(n.radius, n.w / 2, n.h / 2) : 0;
  if (n.bg || n.stroke) {
    out += `<rect x="${n.x}" y="${n.y}" width="${n.w}" height="${n.h}" rx="${r}" fill="${n.bg || 'none'}" fill-opacity="${n.bg ? n.bgAlpha : 0}"`
      + (n.stroke ? ` stroke="${n.stroke}" stroke-width="${n.strokeW}"` : '') + '/>';
  }
  if (n.text) {
    const tx = n.align === 'start' ? n.x : n.align === 'end' ? n.x + n.w : n.x + n.w / 2;
    const font = FONTS[n.font] || "'Montserrat', Arial, sans-serif";
    const weight = n.font === 'Font.GothamBlack' ? 900 : 700;
    const stroke = n.textStroke ? ` stroke="${n.textStroke}" stroke-width="${Math.max(2, n.size / 7)}" paint-order="stroke" stroke-linejoin="round"` : '';
    // TextWrapped labels wrap at their width, as Roblox does (by an average glyph width)
    let lines = [n.text];
    if (n.wrap) {
      const per = Math.max(1, Math.floor(n.w / (n.size * (n.font === 'Font.LuckiestGuy' ? 0.52 : 0.6))));
      lines = [];
      let cur = '';
      for (const word of String(n.text).split(' ')) {
        if ((cur + ' ' + word).trim().length > per && cur) { lines.push(cur); cur = word; } else cur = (cur + ' ' + word).trim();
      }
      if (cur) lines.push(cur);
    }
    lines.forEach((ln, i) => {
      const y = n.y + n.h / 2 + (i - (lines.length - 1) / 2) * n.size * 1.15 + n.size * 0.36;
      out += `<text x="${tx}" y="${y}" fill="${n.colour}" font-family="${font}" font-weight="${weight}" font-size="${n.size}" text-anchor="${n.align}"${stroke}>${esc(ln)}</text>`;
    });
  }
}
fs.writeFileSync(output, out + '</svg>');
console.log(`wrote ${output} (${d.shapes.length} shapes, ${d.nodes.length} nodes)`);
