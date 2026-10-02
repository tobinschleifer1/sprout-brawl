// Development tool: paints tools/render-fight.luau's JSON as a PNG, its frames tiled in a grid.
//   node tools/fight-png.mjs in.json out.png [columns] [scale]
import fs from 'node:fs';
import zlib from 'node:zlib';
const [,, input, output, colsArg = '2', scaleArg = '0.5'] = process.argv;
const d = JSON.parse(fs.readFileSync(input, 'utf8'));
const cols = Number(colsArg), K = Number(scaleArg);
const fw = Math.round(d.w * K), fh = Math.round(d.h * K);
const rows = Math.ceil(d.frames.length / cols);
const W = cols * fw + (cols - 1) * 4, H = rows * fh + (rows - 1) * 4;
const img = new Float32Array(W * H * 3).fill(0.06);
const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);
d.frames.forEach((fr, n) => {
  const ox = (n % cols) * (fw + 4), oy = Math.floor(n / cols) * (fh + 4);
  const blend = (x, y, rgb, a) => {
    if (x < 0 || y < 0 || x >= fw || y >= fh) return;
    const i = ((oy + y) * W + ox + x) * 3;
    for (let k = 0; k < 3; k++) img[i + k] = img[i + k] * (1 - a) + rgb[k] * a;
  };
  for (const s of fr.shapes) {
    if (s[0] === 'p') {
      const pts = s.slice(1, 5).map(([x, y]) => [x * K, y * K]);
      const rgb = hex(s[5]), a = Math.max(0, Math.min(1, s[6]));
      if (a <= 0) continue;
      const xs = pts.map((p) => p[0]), ys = pts.map((p) => p[1]);
      const x0 = Math.max(0, Math.floor(Math.min(...xs))), x1 = Math.min(fw - 1, Math.ceil(Math.max(...xs)));
      const y0 = Math.max(0, Math.floor(Math.min(...ys))), y1 = Math.min(fh - 1, Math.ceil(Math.max(...ys)));
      for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
        const px = x + 0.5, py = y + 0.5;
        let pos = 0, neg = 0;
        for (let i = 0; i < 4; i++) {
          const [ax, ay] = pts[i], [bx, by] = pts[(i + 1) % 4];
          const c = (bx - ax) * (py - ay) - (by - ay) * (px - ax);
          if (c > 0) pos++; else if (c < 0) neg++;
        }
        if (!(pos && neg)) blend(x, y, rgb, a);
      }
    } else {
      const [, cx0, cy0, rx0, ry0, col, a0] = s;
      const cx = cx0 * K, cy = cy0 * K, rx = rx0 * K, ry = ry0 * K, rgb = hex(col), a = Math.max(0, Math.min(1, a0));
      for (let y = Math.max(0, Math.floor(cy - ry)); y <= Math.min(fh - 1, Math.ceil(cy + ry)); y++)
        for (let x = Math.max(0, Math.floor(cx - rx)); x <= Math.min(fw - 1, Math.ceil(cx + rx)); x++) {
          const u = (x + 0.5 - cx) / rx, v = (y + 0.5 - cy) / ry;
          if (u * u + v * v <= 1) blend(x, y, rgb, a);
        }
    }
  }
});
const crcT = new Int32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c; });
const crc = (b) => { let c = -1; for (const x of b) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ -1) >>> 0; };
const chunk = (t, dd) => { const l = Buffer.alloc(4); l.writeUInt32BE(dd.length); const td = Buffer.concat([Buffer.from(t), dd]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
const raw = Buffer.alloc((W * 3 + 1) * H);
for (let y = 0; y < H; y++) for (let x = 0; x < W * 3; x++) raw[y * (W * 3 + 1) + 1 + x] = Math.round(Math.max(0, Math.min(1, img[y * W * 3 + x])) * 255);
const ih = Buffer.alloc(13); ih.writeUInt32BE(W, 0); ih.writeUInt32BE(H, 4); ih[8] = 8; ih[9] = 2;
fs.writeFileSync(output, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
console.log(`wrote ${output} ${W}x${H}`);
