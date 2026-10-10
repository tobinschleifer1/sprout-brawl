// Canvas raster cache for the shared kit composer. The composer produces rectangles in a
// y-down cell grid; the fighter rig uses a y-up world transform. Each variant is painted once.
import { KIT_PARTS, decodeKit } from '../data/avatarKit.js';
import { kitSprites, shadeRects } from './avatarCompose.js';

export const KIT_LOD_PX = 1.3;
const MAX_CODES = 32;
const cache = new Map();

function entry(code) {
  let found = cache.get(code);
  if (found) { cache.delete(code); cache.set(code, found); return found; }
  found = { art: kitSprites(decodeKit(code)), images: new Map() };
  cache.set(code, found);
  if (cache.size > MAX_CODES) cache.delete(cache.keys().next().value);
  return found;
}

function raster(code, id, half, far) {
  const e = entry(code), key = `${id}:${half ? 'half' : 'full'}:${far ? 'far' : 'near'}`;
  if (e.images.has(key)) return e.images.get(key);
  const p = KIT_PARTS[id], step = half ? 2 : 1;
  const cv = document.createElement('canvas');
  cv.width = Math.ceil(p.w / step); cv.height = Math.ceil(p.h / step);
  const c = cv.getContext('2d');
  c.imageSmoothingEnabled = false;
  const list = e.art[id][half ? 'half' : 'full'];
  for (const [x, y, w, h, colour, alpha] of far ? shadeRects(list) : list) {
    c.globalAlpha = alpha; c.fillStyle = colour; c.fillRect(x, y, w, h);
  }
  c.globalAlpha = 1;
  e.images.set(key, cv);
  return cv;
}

export function drawKitPiece(ctx, code, id, pw, ph, { far = false, half = false } = {}) {
  const p = KIT_PARTS[id], step = half ? 2 : 1;
  const cv = raster(code, id, half, far);
  const x0 = -p.ox * pw, y1 = p.oy * ph;
  // The canvas image has rows downward. Flip it in the world transform, without changing
  // the fighter's facing transform or the joint location.
  ctx.save();
  ctx.imageSmoothingEnabled = false;
  ctx.scale(1, -1);
  ctx.drawImage(cv, x0, -y1, cv.width * pw * step, cv.height * ph * step);
  ctx.restore();
}

export function kitHalfDetail(ctx, pw) {
  const m = ctx.getTransform && ctx.getTransform();
  return !!m && pw * Math.sqrt(Math.abs(m.a * m.d - m.b * m.c)) < KIT_LOD_PX;
}

export function clearKitCache() { cache.clear(); }
