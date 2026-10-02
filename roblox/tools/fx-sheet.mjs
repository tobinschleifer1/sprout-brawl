// Development tool: paints tools/fx-sheet.luau's JSON as a PNG contact sheet, one drawing per
// row, its flipbook frames left to right.
//   node tools/fx-sheet.mjs in.json out.png [pixel]
import fs from 'node:fs';
import zlib from 'node:zlib';
const [,, input, output, px = '4'] = process.argv;
const P = Number(px);
const rows = JSON.parse(fs.readFileSync(input, 'utf8'));
const cellW = Math.max(...rows.flatMap((r) => r.frames.map((f) => f.cols))) * P + 12;
const cellH = (r) => Math.max(...r.frames.map((f) => f.rows)) * P + 12;
const W = cellW * Math.max(...rows.map((r) => r.frames.length));
const H = rows.reduce((s, r) => s + cellH(r), 0);
const img = Buffer.alloc(W * H * 3);
for (let i = 0; i < W * H; i++) img.set([24, 20, 36], i * 3);
const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
let y0 = 0;
for (const r of rows) {
  r.frames.forEach((f, n) => {
    const ox = n * cellW + 6, oy = y0 + 6;
    for (const [c, rr, w, h, col, a] of f.rects) {
      const rgb = hex(col);
      for (let y = (oy + rr * P); y < oy + (rr + h) * P; y++) for (let x = ox + c * P; x < ox + (c + w) * P; x++) {
        const i = (y * W + x) * 3; for (let k = 0; k < 3; k++) img[i + k] = Math.round(img[i + k] * (1 - a) + rgb[k] * a);
      }
    }
  });
  y0 += cellH(r);
}
const crcT = new Int32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c; });
const crc = (b) => { let c = -1; for (const x of b) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ -1) >>> 0; };
const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
const raw = Buffer.alloc((W * 3 + 1) * H);
for (let y = 0; y < H; y++) img.copy(raw, y * (W * 3 + 1) + 1, y * W * 3, (y + 1) * W * 3);
const ih = Buffer.alloc(13); ih.writeUInt32BE(W, 0); ih.writeUInt32BE(H, 4); ih[8] = 8; ih[9] = 2;
fs.writeFileSync(output, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
console.log(`wrote ${output} ${W}x${H}; ${rows.map((r) => r.kind + ':' + r.frames.map((f) => f.rects.length).join('/')).join(' ')}`);
