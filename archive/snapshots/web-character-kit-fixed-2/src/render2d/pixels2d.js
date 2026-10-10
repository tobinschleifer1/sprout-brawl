// Drawing a player's pixel art into the world.
//
// The naive version - a fillRect per cell, every part, every fighter, every frame - is about 1500
// rectangles a frame at four players, all of them recomputing the same picture. So each part is
// rasterised ONCE into a tiny offscreen canvas and then blitted. The cache key is the grid plus the
// colours it resolves to, which means moving a swatch in the editor invalidates exactly the parts
// that changed and nothing else.
//
// `shade` is the second reason this is cached rather than tinted at draw time: the back arm and the
// back leg have to read as further away, and the built-in shapes get that for free by using a
// different palette entry. A drawn limb has no such luxury - the player drew one arm - so the back
// copy is a separately cached raster with every colour darkened.

import { PART_GRIDS, inkColour } from '../data/pixelArt.js';

const CACHE = new Map();
const MAX_CACHE = 96;                   // six parts x two shades x a few characters, comfortably

const darken = (hex, k) => {
  const n = parseInt(hex.slice(1), 16);
  const r = Math.round(((n >> 16) & 255) * k), g = Math.round(((n >> 8) & 255) * k), b = Math.round((n & 255) * k);
  return 'rgb(' + r + ',' + g + ',' + b + ')';
};

function raster(part, px, palette, shade) {
  const g = PART_GRIDS[part];
  const key = part + '|' + px + '|' + shade + '|' + [palette.primary, palette.secondary, palette.tertiary, palette.accent, palette.glow].join(',');
  const hit = CACHE.get(key);
  if (hit) return hit;
  const cv = document.createElement('canvas');
  cv.width = g.w; cv.height = g.h;
  const c = cv.getContext('2d');
  for (let y = 0; y < g.h; y++) for (let x = 0; x < g.w; x++) {
    const col = inkColour(px[y * g.w + x], palette);
    if (!col) continue;
    c.fillStyle = shade < 1 ? darken(col, shade) : col;
    c.fillRect(x, y, 1, 1);
  }
  if (CACHE.size > MAX_CACHE) CACHE.clear();      // whole-cache eviction: this is a warm-up cost, not a hot path
  CACHE.set(key, cv);
  return cv;
}

// Place a drawn part into a box in the fighter's own space, where +Y is UP. Image row 0 is the top
// of the box, which is why the vertical scale is negative: the world transform has already flipped
// Y once, and a raster that ignored that would be drawn upside down - the same mistake that had
// every weapon in this game mirrored for months.
export function drawPixelPart(ctx, part, px, palette, x, y, w, h, shade = 1) {
  const img = raster(part, px, palette, shade);
  ctx.save();
  ctx.imageSmoothingEnabled = false;
  ctx.translate(x, y + h);
  ctx.scale(w / img.width, -h / img.height);
  ctx.drawImage(img, 0, 0);
  ctx.restore();
}

// For the editor and the HUD portrait: the same raster, straight into a 2D context in screen space.
export function blitPixelPart(ctx, part, px, palette, x, y, w, h, shade = 1) {
  const img = raster(part, px, palette, shade);
  ctx.save();
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(img, x, y, w, h);
  ctx.restore();
}

export const clearPixelCache = () => CACHE.clear();


// ------------------------------------------------------------------------------ tracing -----
// Start a drawing from the character you already have, instead of from an empty grid.
//
// A blank 12x12 is an intimidating thing to hand someone, and most players want to tweak a face
// rather than invent a body. This renders the BUILT-IN part - the same drawHead, the same torso
// mark - into a grid-sized canvas and snaps every pixel to the nearest available ink. What comes
// back is the character they were already looking at, now made of cells they can edit.

import { drawHead, drawTorsoMark } from './avatar2d.js';
import { INKS, PART_GRIDS as GRIDS } from '../data/pixelArt.js';

const hexToRgb = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];

export function traceProcedural(part, palette, feat) {
  const g = GRIDS[part];
  const cv = document.createElement('canvas');
  cv.width = g.w; cv.height = g.h;
  const c = cv.getContext('2d');
  c.imageSmoothingEnabled = false;
  const S = 0.78;                                   // headroom, so a crown or horns are not clipped

  if (part === 'head') {
    c.setTransform(g.w * S, 0, 0, -g.h * S, g.w / 2, g.h * 0.90);
    drawHead(c, palette, 1, feat);
  } else if (part === 'torso') {
    c.setTransform(g.w * 0.94, 0, 0, -g.h * 0.94, g.w / 2, g.h * 0.97);
    c.fillStyle = palette.secondary;
    c.fillRect(-0.5, 0, 1, 1);
    drawTorsoMark(c, palette, 0.625, 1, feat);      // r*0.8 = 0.5 half-width, so r = 0.625 at unit torso
  } else {
    // Arms and legs are a plain bar in the built-in rig; trace gives the player the bar to carve.
    c.fillStyle = part === 'arm' ? palette.primary : palette.tertiary;
    const inset = part === 'arm' ? 1 : 1;
    c.fillRect(inset, 0, g.w - inset * 2, g.h - (part === 'arm' ? 0 : 0));
  }

  c.setTransform(1, 0, 0, 1, 0, 0);
  const data = c.getImageData(0, 0, g.w, g.h).data;
  // Candidate inks, resolved for this character.
  const cands = INKS.filter((i) => i.id !== '.').map((i) => ({ id: i.id, rgb: hexToRgb(i.fixed || palette[i.slot] || '#ff00ff') }));
  let out = '';
  for (let i = 0; i < g.w * g.h; i++) {
    const a = data[i * 4 + 3];
    if (a < 110) { out += '.'; continue; }
    const px = [data[i * 4], data[i * 4 + 1], data[i * 4 + 2]];
    let best = cands[0], bd = Infinity;
    for (const cd of cands) {
      const d = (px[0] - cd.rgb[0]) ** 2 + (px[1] - cd.rgb[1]) ** 2 + (px[2] - cd.rgb[2]) ** 2;
      if (d < bd) { bd = d; best = cd; }
    }
    out += best.id;
  }
  return out;
}
