// Development tool: paints a GUI recording (tools/render-select.luau and friends) as an SVG - the
// canvas's shapes first, then every Frame / label / button with its corner radius, outline and
// text. Roblox's fonts are stood in for by close Google Fonts (Luckiest Guy is on both).
//   node tools/gui-svg.mjs in.json out.svg
import fs from 'node:fs';
const [,, input, output] = process.argv;
const d = JSON.parse(fs.readFileSync(input, 'utf8'));
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/\n/g, ' ');
const FONTS = { 'Font.LuckiestGuy': "'Luckiest Guy', Impact, sans-serif", 'Font.GothamBlack': "'Montserrat', Arial Black, sans-serif",
  'Font.GothamBold': "'Montserrat', Arial, sans-serif", 'Font.FredokaOne': "'Fredoka', Arial, sans-serif",
  'Font.Arcade': "'Press Start 2P', monospace",
  'Font.BuilderSansBold': "'Nunito Sans', Arial, sans-serif", 'Font.BuilderSansExtraBold': "'Nunito Sans', Arial Black, sans-serif" };
const WEIGHTS = { 'Font.GothamBlack': 900, 'Font.BuilderSansExtraBold': 900, 'Font.BuilderSansBold': 800, 'Font.FredokaOne': 600 };
// Roblox draws Font.Arcade (Press Start 2P) at 0.5625 px per letter per TextSize, where a browser
// draws it a full em per letter: scale its size to match (measured with TextService in Studio)
const ARCADE = 0.5625;
let out = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${d.w} ${d.h}" width="${d.w}" height="${d.h}">`
  + `<style>@import url('https://fonts.googleapis.com/css2?family=Luckiest+Guy&amp;family=Montserrat:wght@700;900&amp;family=Fredoka:wght@600&amp;family=Press+Start+2P&amp;display=block');</style>`
  // a renderer that cannot fetch Google Fonts (Quick Look's) can be handed the font file:
  // PS2P_TTF=path/to/PressStart2P-Regular.ttf (github.com/google/fonts, ofl/pressstart2p)
  + (process.env.PS2P_TTF ? `<style>@font-face { font-family: 'Press Start 2P'; src: url(data:font/ttf;base64,${fs.readFileSync(process.env.PS2P_TTF).toString('base64')}); }</style>` : '')
  // or a folder of them (GUI_FONT_DIR): PressStart2P, LuckiestGuy, Fredoka, Montserrat, NunitoSans .ttf
  + (process.env.GUI_FONT_DIR ? '<style>' + Object.entries({ PressStart2P: 'Press Start 2P', LuckiestGuy: 'Luckiest Guy', Fredoka: 'Fredoka',
    Montserrat: 'Montserrat', NunitoSans: 'Nunito Sans' }).filter(([f]) => fs.existsSync(`${process.env.GUI_FONT_DIR}/${f}.ttf`))
    .map(([f, fam]) => `@font-face { font-family: '${fam}'; font-weight: 100 900; src: url(data:font/ttf;base64,${fs.readFileSync(`${process.env.GUI_FONT_DIR}/${f}.ttf`).toString('base64')}); }`).join('') + '</style>' : '')
  + `<rect width="${d.w}" height="${d.h}" fill="#000"/><g shape-rendering="crispEdges">`;
for (const s of d.shapes) {
  if (s[0] === 'p') out += `<polygon points="${s.slice(1, 5).map((p) => p.join(',')).join(' ')}" fill="${s[5]}" fill-opacity="${s[6]}"/>`;
  else out += `<ellipse cx="${s[1]}" cy="${s[2]}" rx="${s[3]}" ry="${s[4]}" fill="${s[5]}" fill-opacity="${s[6]}"/>`;
}
out += '</g>';
const clips = new Map();
for (const n of d.nodes) {
  // a node inside a ScrollingFrame (or a ClipsDescendants box) is cut off at its edges
  let open = '';
  if (n.clip) {
    const key = n.clip.map((v) => Math.round(v * 10) / 10).join(',');
    if (!clips.has(key)) {
      clips.set(key, `c${clips.size}`);
      out += `<clipPath id="c${clips.size - 1}"><rect x="${n.clip[0]}" y="${n.clip[1]}" width="${n.clip[2]}" height="${n.clip[3]}"/></clipPath>`;
    }
    open = `<g clip-path="url(#${clips.get(key)})">`;
    out += open;
  }
  const r = n.radius ? Math.min(n.radius, n.w / 2, n.h / 2) : 0;
  if (n.bg || n.stroke) {
    out += `<rect x="${n.x}" y="${n.y}" width="${n.w}" height="${n.h}" rx="${r}" fill="${n.bg || 'none'}" fill-opacity="${n.bg ? n.bgAlpha : 0}"/>`;
    // a Roblox UIStroke border is drawn outside the box, where an SVG stroke straddles its edge
    if (n.stroke) {
      const h = n.strokeW / 2;
      out += `<rect x="${n.x - h}" y="${n.y - h}" width="${n.w + n.strokeW}" height="${n.h + n.strokeW}" rx="${r ? r + h : 0}" fill="none" stroke="${n.stroke}" stroke-width="${n.strokeW}"/>`;
    }
  }
  if (n.text) {
    // a UIPadding insets the text, not the box
    const left = n.x + (n.padL || 0), right = n.x + n.w - (n.padR || 0);
    const tx = n.align === 'start' ? left : n.align === 'end' ? right : (left + right) / 2;
    const font = FONTS[n.font] || FONTS['Font.' + n.font] || "'Montserrat', Arial, sans-serif";
    const arcade = n.font.endsWith('Arcade');
    const weight = arcade ? 400 : WEIGHTS[n.font] || WEIGHTS['Font.' + n.font] || 700;
    const fsz = arcade ? n.size * ARCADE : n.size;
    const sw = n.textStrokeW ? n.textStrokeW * 2 : Math.max(2, n.size / 7);   // SVG strokes straddle the edge
    const stroke = n.textStroke ? ` stroke="${n.textStroke}" stroke-width="${sw}" paint-order="stroke" stroke-linejoin="${arcade ? 'miter' : 'round'}"` : '';
    // TextWrapped labels wrap at their width, as Roblox does (by an average glyph width)
    // (and at every newline)
    let lines = [];
    const per = Math.max(1, Math.floor((right - left) / (n.size * (arcade ? ARCADE : n.font.endsWith('LuckiestGuy') ? 0.52 : /BuilderSans|FredokaOne/.test(n.font) ? 0.5 : 0.6))));
    for (const para of String(n.text).split('\n')) {
      if (!n.wrap) { lines.push(para); continue; }
      let cur = '';
      for (const word of para.split(' ')) {
        if ((cur + ' ' + word).trim().length > per && cur) { lines.push(cur); cur = word; } else cur = (cur + ' ' + word).trim();
      }
      if (cur) lines.push(cur);
    }
    lines.forEach((ln, i) => {
      const y = n.y + n.h / 2 + (i - (lines.length - 1) / 2) * n.size * (arcade ? 1.0 : 1.15) + (arcade ? fsz * 0.45 : n.size * 0.36);
      out += `<text x="${tx}" y="${y}" fill="${n.colour}" font-family="${font}" font-weight="${weight}" font-size="${fsz}" text-anchor="${n.align}"${stroke}>${esc(ln)}</text>`;
    });
  }
  if (open) out += '</g>';
}
fs.writeFileSync(output, out + '</svg>');
console.log(`wrote ${output} (${d.shapes.length} shapes, ${d.nodes.length} nodes)`);
