// What a disaster looks like, as a list of shapes computed from its view (stage.visual.disaster).
//
// Pure: no canvas, no clock. Both builds paint exactly this list - the web through fillRect and
// ellipse, Roblox through Canvas2D - and roblox/tests/disaster-shapes.luau replays it, so the two
// cannot drift into different pictures of the same event. Animation comes from the event's own
// frame counter, never a local clock, so every client sees the same pulse at the same moment.
//
// The signal rule from the revamp plan: WARNINGS are cool cyan, DAMAGE is hot orange. A player
// who has learned one disaster has learned how all six announce themselves.
//
// Shapes: ['r', x, y, w, h, colour, alpha]  - a rectangle, (x, y) its bottom-left, world y up
//         ['e', cx, cy, rx, ry, colour, alpha] - a filled ellipse
export const COOL = '#7FD4FF';
export const HOT = '#F08B60';
const WHITE = '#FFFFFF';
const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
// A pulse from the frame count: 0..1..0 every `period` frames.
const pulse = (frame, period) => 0.5 - 0.5 * Math.cos((frame % period) / period * Math.PI * 2);

function span(stage) {
  let lo = Infinity, hi = -Infinity;
  for (const s of stage.solids) { lo = Math.min(lo, s.x1); hi = Math.max(hi, s.x2); }
  return [lo, hi];
}

// A dashed horizontal line: where something WILL be.
function dashes(out, x1, x2, y, colour, alpha) {
  for (let x = x1; x < x2; x += 2) out.push(['r', x, y - 0.12, Math.min(1, x2 - x), 0.24, colour, alpha]);
}

const DRAW = {
  lavasurge(out, v, stage) {
    const [lo, hi] = span(stage);
    const warn = v.phase === 'warn';
    // the telegraph: where the lava will stop, shown for the whole event
    dashes(out, lo - 8, hi + 8, v.line, COOL, warn ? 0.5 + 0.5 * pulse(v.frame, 30) : 0.35);
    if (v.level > stage.blast.bottom) {
      const bottom = stage.blast.bottom - 5;
      out.push(['r', lo - 40, bottom, hi - lo + 80, v.level - bottom, '#8A2A12', 0.92]);
      out.push(['r', lo - 40, v.level - 1.2, hi - lo + 80, 1.2, '#C0461E', 1]);
      out.push(['r', lo - 40, v.level - 0.4, hi - lo + 80, 0.4, '#FF9A3C', 1]);
      for (let i = 0; i < 9; i++) {                           // bubbles walk along the surface
        const x = lo + ((i * 11.3 + v.frame * 0.15) % (hi - lo));
        out.push(['e', x, v.level - 0.2, 0.45, 0.3, '#FFE0A0', 0.5 + 0.5 * pulse(v.frame + i * 7, 40)]);
      }
    }
  },
  lightning(out, v) {
    for (const s of v.strikes || []) {
      if (s.live) {
        out.push(['r', s.x - 0.8, s.y, 1.6, 60, COOL, 0.45]);
        out.push(['r', s.x - 0.3, s.y, 0.6, 60, WHITE, 1]);
        out.push(['e', s.x, s.y + 0.2, 3.2, 0.8, HOT, 0.9]);
      } else {
        // the marker: a flat ring on the ground that tightens as the bolt gets closer
        out.push(['e', s.x, s.y + 0.1, 2.5, 0.5, COOL, 0.25 + 0.35 * pulse(v.frame, 20)]);
        out.push(['e', s.x, s.y + 0.1, 0.6, 0.18, COOL, 0.9]);
      }
    }
  },
  tornado(out, v) {
    const k = v.phase === 'warn' ? v.k : v.phase === 'after' ? 1 - v.k : 1;
    for (let i = 0; i < 8; i++) {
      const u = i / 7, r = v.radiusFloor + (v.radiusTop - v.radiusFloor) * u;
      const sway = Math.sin((v.frame * 0.2) + i * 0.9) * 0.6 * u;
      out.push(['e', v.x + sway, v.floor + u * v.height, r, 0.9, '#C9A87A', 0.18 + 0.22 * k]);
    }
    if (v.phase === 'warn') out.push(['r', v.x - 0.2, v.floor, 0.4, v.height, COOL, 0.5 * v.k]);
  },
  tsunami(out, v, stage) {
    const [lo, hi] = span(stage);
    if (v.phase === 'warn') {
      // the horizon rises, and an arrow at the side it comes from
      out.push(['r', lo - 40, v.base, hi - lo + 80, v.k * 2, COOL, 0.35]);
      const edge = v.dir > 0 ? lo - 6 : hi + 6;
      for (let i = 0; i < 3; i++) out.push(['r', edge + v.dir * i * 1.2, v.crest * 0.5 - i, 1, 2 * i + 1, COOL, 0.5 + 0.5 * pulse(v.frame, 24)]);
      return;
    }
    const fade = v.phase === 'after' ? 1 - v.k : 1;
    const back = v.dir > 0 ? stage.blast.left : v.x;
    const front = v.dir > 0 ? v.x : stage.blast.right;
    out.push(['r', back, v.base, Math.max(0, front - back), v.crest * 0.5, '#2F7A8A', 0.55 * fade]);   // the backwash
    if (v.phase === 'strike') {
      out.push(['r', v.x - v.width / 2, v.base, v.width, v.crest - v.base, '#59D9F2', 0.95]);
      out.push(['r', v.x - v.width / 2, v.crest - 0.6, v.width, 0.6, WHITE, 0.9]);                      // foam
    }
  },
  earthquake(out, v) {
    const seam = v.phase === 'warn' ? 0.4 + 0.6 * pulse(v.frame, 16) : 0.8;
    for (const p of v.plates || []) {
      out.push(['r', p.x1 - 0.2, p.top - 3, 0.4, 3, HOT, seam]);
      out.push(['r', p.x2 - 0.2, p.top - 3, 0.4, 3, HOT, seam]);
      if (v.phase !== 'warn') out.push(['r', p.x1, p.top - 0.3, p.x2 - p.x1, 0.3, HOT, 0.35]);
    }
    if (!(v.plates || []).length && v.phase === 'warn') {        // a tremor: the whole floor hums
      out.push(['r', -200, -0.4, 400, 0.4, COOL, 0.3 + 0.4 * pulse(v.frame, 10)]);
    }
  },
  meteor(out, v) {
    for (const r of v.rocks || []) {
      if (r.shadow > 0) {
        out.push(['e', r.x, r.y + 0.1, 0.6 + 4.4 * r.shadow, 0.4 + 0.5 * r.shadow, '#000000', 0.45]);
        out.push(['e', r.x, r.y + 0.1, 5, 0.9, COOL, 0.3 * r.shadow]);
        const h = 40 * (1 - r.shadow);                                                            // falling in
        out.push(['e', r.x - h * 0.3, r.y + h, 1.1, 1.1, '#FFE0A0', clamp(r.shadow * 1.5, 0, 1)]);
        out.push(['r', r.x - h * 0.3 - 0.3, r.y + h, 0.6, 6, HOT, 0.6 * r.shadow]);
      }
      if (r.live) out.push(['e', r.x, r.y + 1, 5, 4, HOT, 0.85]);
      if (r.burning) {
        out.push(['e', r.x, r.y + 0.1, 3, 0.5, '#1A0E08', 0.9]);
        out.push(['e', r.x, r.y + 0.3, 1.2, 0.3, HOT, 0.6 + 0.4 * pulse(v.frame, 12)]);
      }
    }
  },
};

export function disasterShapes(view, stage) {
  const out = [];
  if (!view || !DRAW[view.type]) return out;
  DRAW[view.type](out, view, stage);
  return out;
}

// The words for the HUD banner: what is coming and when, in the plan's cool/hot signal colours.
const NAMES = { lavasurge: 'LAVA SURGE', lightning: 'LIGHTNING STORM', tornado: 'TORNADO', tsunami: 'TSUNAMI',
  earthquake: 'EARTHQUAKE', meteor: 'METEOR SHOWER' };
export function disasterBanner(view) {
  if (!view || !NAMES[view.type] || view.phase === 'after') return null;
  const name = view.type === 'earthquake' && !(view.plates || []).length ? 'TREMOR' : NAMES[view.type];
  if (view.phase === 'warn') {
    return { text: `${name} INCOMING`, colour: COOL, seconds: Math.ceil(Math.max(0, view.warn - view.frame) / 60) };
  }
  return { text: name, colour: HOT, seconds: null };
}
