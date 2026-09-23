// A dependency-free PNG encoder, for tools that turn pixel data into images (sprite atlases,
// weapon previews, the animation production sheet). Node has zlib; PNG needs nothing else.
import zlib from 'node:zlib';

const CRC = new Uint32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(buf) {
  let c = 0xFFFFFFFF;
  for (const b of buf) c = CRC[(c ^ b) & 255] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}
function chunk(type, data) {
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  out.write(type, 4, 'ascii');
  data.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
  return out;
}

// `rgba` is a Uint8Array of width*height*4.
export function encodePNG(width, height, rgba) {
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (width * 4 + 1)] = 0;                       // filter: none
    Buffer.from(rgba.buffer, rgba.byteOffset + y * width * 4, width * 4).copy(raw, y * (width * 4 + 1) + 1);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;   // 8-bit RGBA
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// A tiny raster to draw into before encoding.
export class Raster {
  constructor(w, h) { this.w = w; this.h = h; this.px = new Uint8Array(w * h * 4); }
  set(x, y, hex, a = 1) {
    x = Math.floor(x); y = Math.floor(y);
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return;
    const n = parseInt(hex.slice(1), 16), i = (y * this.w + x) * 4;
    const sa = a, da = this.px[i + 3] / 255, oa = sa + da * (1 - sa);
    const mix = (s, d) => (oa === 0 ? 0 : Math.round((s * sa + d * da * (1 - sa)) / oa));
    this.px[i] = mix((n >> 16) & 255, this.px[i]); this.px[i + 1] = mix((n >> 8) & 255, this.px[i + 1]);
    this.px[i + 2] = mix(n & 255, this.px[i + 2]); this.px[i + 3] = Math.round(oa * 255);
  }
  rect(x, y, w, h, hex, a = 1) { for (let j = y; j < y + h; j++) for (let i = x; i < x + w; i++) this.set(i, j, hex, a); }
  png() { return encodePNG(this.w, this.h, this.px); }
}
