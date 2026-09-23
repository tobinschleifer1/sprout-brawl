import { SCENES } from '../data/art.js';

// Screen-space scenery: coarse authored pixels remain hard-edged at every viewport size.
export function drawArtSky(ctx, stageId, cam, width, height) {
  const art = SCENES[stageId];
  if (!art) return false;
  ctx.save();
  const g = ctx.createLinearGradient(0, 0, 0, height);
  art.sky.forEach((colour, i) => g.addColorStop(i / (art.sky.length - 1), colour));
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, width, height);
  const scale = height / 270;
  ctx.scale(scale, scale);
  const w = width / scale;
  const [sx, sy, radius] = art.sun;
  const sunX = sx / 480 * w - cam.x * 0.03;
  ctx.fillStyle = art.light;
  ctx.globalAlpha = 0.65;
  ctx.fillRect(sunX - radius, sy - radius * 0.6, radius * 2, radius * 1.2);
  ctx.fillRect(sunX - radius * 0.6, sy - radius, radius * 1.2, radius * 0.4);
  ctx.fillRect(sunX - radius * 0.6, sy + radius * 0.6, radius * 1.2, radius * 0.4);
  for (let i = 0; i < 18; i++) {
    ctx.globalAlpha = 0.12 + (i % 3) * 0.08;
    ctx.fillRect(((i * 97 + 31) % 480) / 480 * w, 12 + (i * 29) % 83, 1, 1);
  }
  for (const layer of art.layers) {
    const shift = -cam.x * layer.parallax;
    const start = Math.floor(-shift / 480) * 480 + shift;
    for (let tile = start; tile < w; tile += 480) {
      for (const [x, y, rw, rh, colour, alpha] of layer.rectangles) {
        if (tile + x + rw <= 0 || tile + x >= w) continue;
        ctx.fillStyle = colour; ctx.globalAlpha = alpha;
        ctx.fillRect(tile + x, y, rw, rh);
      }
    }
  }
  ctx.restore();
  return true;
}

