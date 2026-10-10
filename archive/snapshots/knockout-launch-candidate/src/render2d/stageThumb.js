// A stage as a map-select thumbnail, as a list of rectangles in the thumbnail's own pixels
// (y down): ['r', x, y, w, h, colour, alpha]. Both builds draw this one list - the web setup
// screen as SVG, the Roblox room's map board through Canvas2D - so a map looks the same in either
// (roblox/src/client/StageThumb.luau, held to this by tests/stage-thumb.luau).
//
// Framed on the stage itself, not its blast box: at tile size the blast box made every map a thin
// line in an empty sky. The sky is the stage's own gradient in flat bands, which is what pixel art
// does with a gradient anyway.

const px = (v) => Math.floor(v + 0.5);

// The playable area in studs: every surface, a moving one across its whole travel, plus a margin.
export function stageExtent(stage) {
  let x0 = stage.main.x1, x1 = stage.main.x2, y0 = stage.main.y - stage.main.thickness, y1 = stage.main.y;
  for (const p of stage.platforms) {
    const mx = p.moving && p.moving.x;
    const lo = mx ? Math.min(mx.from, mx.to) : p.x, hi = mx ? Math.max(mx.from, mx.to) : p.x;
    x0 = Math.min(x0, lo - p.w / 2); x1 = Math.max(x1, hi + p.w / 2);
    const my = p.moving && p.moving.y;
    y1 = Math.max(y1, my ? Math.max(my.from, my.to) : p.y);
    y0 = Math.min(y0, p.y - (p.thickness || (p.solid ? 5 : 1)));
  }
  return [x0 - 4, x1 + 4, y0 - 2, y1 + 6];
}

export function stageThumb(stage, w, h) {
  const out = [];
  const pal = stage.palette || {};
  const R = (x, y, rw, rh, colour, alpha = 1) => {
    const a = px(x), b = px(y);
    const c = px(x + rw), d = px(y + rh);
    if (c > a && d > b) out.push(['r', a, b, c - a, d - b, colour, alpha]);
  };
  // sky: one flat band per gradient stop
  const stops = pal.skyStops && pal.skyStops.length > 1 ? pal.skyStops : [[0, pal.sky || '#8295AD'], [1, pal.sky || '#8295AD']];
  for (let i = 0; i < stops.length - 1; i++) {
    R(0, stops[i][0] * h, w, (stops[i + 1][0] - stops[i][0]) * h, stops[i][1]);
  }
  const [x0, x1, y0, y1] = stageExtent(stage);
  const ppu = Math.min(w / (x1 - x0), h / (y1 - y0));
  const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
  const X = (x) => w / 2 + (x - cx) * ppu;
  const Y = (y) => h / 2 - (y - cy) * ppu;
  const ground = pal.ground || '#3E4450', top = pal.groundTop || '#8A94A6';
  const shelf = pal.platform || '#6E7788', accent = pal.accent || '#EBAD50';
  const solid = (a, b, topY, thick, ledges) => {
    R(X(a), Y(topY), (b - a) * ppu, thick * ppu, ground);
    R(X(a), Y(topY), (b - a) * ppu, Math.max(1, ppu * 0.8), top);
    if (ledges !== false) {
      R(X(a), Y(topY), Math.max(1, ppu * 0.9), Math.max(2, ppu * 2), accent);
      R(X(b) - Math.max(1, ppu * 0.9), Y(topY), Math.max(1, ppu * 0.9), Math.max(2, ppu * 2), accent);
    }
  };
  const m = stage.main;
  solid(m.x1, m.x2, m.y, m.thickness, m.ledges);
  for (const p of stage.platforms) {
    if (p.solid) { solid(p.x - p.w / 2, p.x + p.w / 2, p.y, p.thickness || 5, p.ledges); continue; }
    const mx = p.moving && p.moving.x;
    if (mx) {
      // the whole travel, faint, so the board says "this one moves"
      const lo = Math.min(mx.from, mx.to), hi = Math.max(mx.from, mx.to);
      R(X(lo - p.w / 2), Y(p.y), (hi - lo + p.w) * ppu, Math.max(1, ppu * 0.4), shelf, 0.35);
    }
    R(X(p.x - p.w / 2), Y(p.y), p.w * ppu, Math.max(1, (p.thickness || 1) * ppu), shelf);
  }
  return out;
}

// The Random tile: a die face, in the same shape language.
export function randomThumb(w, h) {
  const out = [['r', 0, 0, w, h, '#1B2531', 1]];
  const s = Math.floor(Math.min(w, h) * 0.56), x = Math.floor((w - s) / 2), y = Math.floor((h - s) / 2);
  out.push(['r', x, y, s, s, '#E9E5DB', 1]);
  const d = Math.max(2, Math.floor(s * 0.16));
  for (const [u, v] of [[0.25, 0.25], [0.75, 0.25], [0.5, 0.5], [0.25, 0.75], [0.75, 0.75]]) {
    out.push(['r', Math.floor(x + s * u - d / 2), Math.floor(y + s * v - d / 2), d, d, '#101721', 1]);
  }
  return out;
}
