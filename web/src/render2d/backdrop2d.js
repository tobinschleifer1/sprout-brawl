// STAGE SCENERY - the sky and everything behind the fighting.
//
// This file exists because the stages had no middle distance at all. `_sky` painted a vertical
// gradient, `_backdrop` painted three sine waves at 20-60% alpha, and that was the entire world:
// at gameplay zoom the three waves overlap into one pale wedge along the bottom and the top
// two-thirds of the screen is a flat colour. Six stages, six themes, and none of them were
// visible - a foundry, a suspension bridge and a dry lake all rendered as the same grey wash.
//
// Every stage also authored a `palette.glows` entry - a sun, a furnace mouth, a moon - and NOTHING
// READ IT. Six deliberate light sources, written down and thrown away, which is most of why the
// skies looked unlit.
//
// What is here now:
//   - a sky with its declared glow, plus per-theme sky content (cloud banks, stars, a sun disc)
//   - three to four parallax scenery bands per theme, built from repeated procedural silhouettes
//     (chimneys, towers and cables, skyline blocks with lit windows, mesas, cranes) rather than
//     from sine noise
//   - ATMOSPHERIC PERSPECTIVE: every band is mixed toward the sky colour by its distance, so depth
//     comes from contrast falling off with range the way it actually does, instead of from alpha
//
// Everything is deterministic - seeded off the column index, never off time or the camera - so the
// scenery is identical every match and does not crawl when the camera moves.

const PI = Math.PI;
const TAU = PI * 2;

// Stable per-column noise. Seeded by integer index so a given chimney is always the same chimney.
const hash = (i) => { const x = Math.sin(i * 127.1 + 311.7) * 43758.5453; return x - Math.floor(x); };
const hash2 = (i, j) => hash(i * 57.3 + j * 13.7);

const hex = (c) => [parseInt(c.slice(1, 3), 16), parseInt(c.slice(3, 5), 16), parseInt(c.slice(5, 7), 16)];
const rgb = (a) => `#${a.map((v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('')}`;
// Mix toward the sky. `k` is how far away the band is: 0 is right here, 1 is the horizon.
const haze = (colour, sky, k) => { const a = hex(colour), s = hex(sky); return rgb(a.map((v, i) => v + (s[i] - v) * k)); };

// ------------------------------------------------------------------------------- the sky -----

export function drawSky(b, stage, t, BW, BH, cam) {
  const p = stage.data.palette;
  const g = b.createLinearGradient(0, 0, 0, BH);
  const stops = p.skyStops || [[0, p.sky || '#BFE3E8'], [1, p.backdrop || '#EAF7F2']];
  for (const [o, col] of stops) g.addColorStop(Math.max(0, Math.min(1, o)), col);
  b.fillStyle = g;
  b.fillRect(0, 0, BW, BH);

  // Stars, before anything else, only where the sky is dark enough for them to be believable.
  const topStop = (stops[0] && stops[0][1]) || '#000000';
  const lum = hex(topStop).reduce((s, v) => s + v, 0) / 3;
  if (lum < 90) {
    b.fillStyle = 'rgba(255,255,255,0.55)';
    for (let i = 0; i < 40; i++) {
      const sx = (hash(i) * BW * 1.4 - cam.x * 0.02) % (BW * 1.4);
      const sy = hash(i + 91) * BH * 0.38;
      const tw = 0.5 + 0.5 * Math.sin(t * 1.3 + i);
      b.globalAlpha = 0.25 + 0.4 * tw * (1 - sy / (BH * 0.38));
      b.fillRect((sx + BW * 1.4) % (BW * 1.4) - BW * 0.2, sy, 1, 1);
    }
    b.globalAlpha = 1;
  }

  // THE DECLARED LIGHT SOURCE. Every stage has had one of these in its palette since the stages
  // were written and it has never been drawn.
  for (const gl of p.glows || []) {
    const gx = BW * (gl.x ?? 0.5) - cam.x * 0.03;
    const gy = BH - (gl.y ?? 120) * (BH / 270);
    const rr = (gl.r ?? 150) * (BH / 270);
    const rg = b.createRadialGradient(gx, gy, 0, gx, gy, rr);
    rg.addColorStop(0, gl.color || 'rgba(255,220,160,0.35)');
    rg.addColorStop(1, 'rgba(0,0,0,0)');
    b.fillStyle = rg;
    b.fillRect(gx - rr, gy - rr, rr * 2, rr * 2);
    // A hard disc for the ones that are a sun rather than a general wash.
    if (gl.disc) {
      b.beginPath(); b.arc(gx, gy, gl.disc * (BH / 270), 0, TAU);
      b.fillStyle = gl.discColor || 'rgba(255,246,224,0.9)'; b.fill();
    }
  }

  // Cloud banks: long flat lozenges at two speeds. Drawn in the backdrop colour so they sit in the
  // same family as the scenery rather than reading as white blobs pasted on.
  const clouds = SKY_CLOUDS[stage.data.theme];
  if (clouds) {
    for (let layer = 0; layer < 2; layer++) {
      const par = 0.02 + layer * 0.03, sc = 1 - layer * 0.35;
      b.fillStyle = haze(clouds.colour, (stops[0] && stops[0][1]) || '#888888', layer ? 0.45 : 0.2);
      b.globalAlpha = clouds.alpha * (layer ? 0.7 : 1);
      const span = BW * 2;
      for (let i = 0; i < 7; i++) {
        const seed = i + layer * 31;
        let cx = (hash(seed) * span - cam.x * par * 8 + t * (0.6 + hash(seed + 5)) * (layer ? 0.4 : 0.8)) % span;
        if (cx < 0) cx += span;
        cx -= BW * 0.5;
        const cy = BH * (0.06 + hash(seed + 17) * 0.30) * (1 + layer * 0.2);
        const w = (26 + hash(seed + 3) * 44) * sc, h = (4 + hash(seed + 9) * 4) * sc;
        b.beginPath();
        b.ellipse(cx, cy, w / 2, h / 2, 0, 0, TAU);
        b.ellipse(cx - w * 0.22, cy + h * 0.16, w / 3.4, h / 2.4, 0, 0, TAU);
        b.ellipse(cx + w * 0.26, cy + h * 0.12, w / 3.8, h / 2.6, 0, 0, TAU);
        b.fill();
      }
    }
    b.globalAlpha = 1;
  }
}

const SKY_CLOUDS = {
  'Iron works': { colour: '#8E9BB0', alpha: 0.5 },
  'Suspension bridge': { colour: '#FFFFFF', alpha: 0.55 },
  'Smelting floor': { colour: '#8A5A48', alpha: 0.55 },
  'City rooftops': { colour: '#5E6E86', alpha: 0.4 },
  'Dry lake': { colour: '#FFF4DC', alpha: 0.45 },
  'Flooded dock': { colour: '#FFFFFF', alpha: 0.5 },
};

// --------------------------------------------------------------------------- the scenery -----
// A band is: how much it moves with the camera, how far away it reads, what colour it starts as,
// how often its motif repeats, and how to draw one instance. Everything in world studs, +Y up.

function chimneyStack(b, x, base, s, seed, col, lit) {
  const w = 2.2 + hash(seed) * 1.8, h = 10 + hash(seed + 1) * 15;
  b.fillStyle = col;
  b.fillRect(x, base, w * s, h * s);                                   // the stack
  b.fillRect(x - 0.5 * s, base + h * s - 1.2 * s, (w + 1) * s, 1.2 * s); // the cap
  const bw = 5 + hash(seed + 2) * 7, bh = 4 + hash(seed + 3) * 5;
  b.fillRect(x - bw * 0.35 * s, base, bw * s, bh * s);                  // the shed it comes out of
  if (lit && hash(seed + 4) > 0.55) {                                   // furnace mouth
    b.fillStyle = lit;
    b.fillRect(x - bw * 0.2 * s, base + 0.8 * s, 2.2 * s, 2.4 * s);
  }
}

function gantry(b, x, base, s, seed, col) {
  const h = 7 + hash(seed) * 6, w = 11 + hash(seed + 1) * 7;
  b.fillStyle = col;
  b.fillRect(x, base, 1.3 * s, h * s);                                  // legs
  b.fillRect(x + (w - 1.3) * s, base, 1.3 * s, h * s);
  b.fillRect(x, base + h * s, w * s, 1.6 * s);                          // the deck
  b.lineWidth = 0.5 * s; b.strokeStyle = col;                           // the truss under it
  b.beginPath();
  for (let i = 0; i < 5; i++) {
    b.moveTo(x + (i / 5) * w * s, base + h * s);
    b.lineTo(x + ((i + 1) / 5) * w * s, base + (h - 2.4) * s);
    b.lineTo(x + ((i + 2) / 5) * w * s, base + h * s);
  }
  b.stroke();
}

function skyline(b, x, base, s, seed, col, lit) {
  const w = 5 + hash(seed) * 6, h = 8 + hash(seed + 1) * 22;
  b.fillStyle = col;
  b.fillRect(x, base, w * s, h * s);
  if (hash(seed + 2) > 0.6) b.fillRect(x + w * 0.3 * s, base + h * s, 1.1 * s, (3 + hash(seed + 3) * 5) * s); // aerial
  if (!lit) return;
  b.fillStyle = lit;                                                    // lit windows, stable per building
  const cols = Math.max(1, Math.floor(w / 2.4)), rows = Math.max(1, Math.floor(h / 3.2));
  for (let cx = 0; cx < cols; cx++) for (let ry = 0; ry < rows; ry++) {
    if (hash2(seed * 7 + cx, ry) < 0.62) continue;
    b.fillRect(x + (0.9 + cx * 2.4) * s, base + (1.6 + ry * 3.2) * s, 1.0 * s, 1.3 * s);
  }
}

function mesa(b, x, base, s, seed, col) {
  const w = 16 + hash(seed) * 20, h = 5 + hash(seed + 1) * 11, slope = 2 + hash(seed + 2) * 3;
  b.fillStyle = col;
  b.beginPath();
  b.moveTo(x, base);
  b.lineTo(x + slope * s, base + h * s);
  b.lineTo(x + (w - slope * 0.7) * s, base + h * s * (0.82 + hash(seed + 3) * 0.2));
  b.lineTo(x + w * s, base);
  b.closePath(); b.fill();
}

function tower(b, x, base, s, seed, col) {
  // A suspension tower plus the catenary running off both sides of it.
  const h = 17 + hash(seed) * 6, w = 3;
  b.fillStyle = col;
  b.fillRect(x, base, 1.6 * s, h * s);
  b.fillRect(x + (w - 1.6) * s, base, 1.6 * s, h * s);
  for (let i = 1; i < 4; i++) b.fillRect(x, base + (h * i / 4) * s, w * s, 1.0 * s);   // cross braces
  b.strokeStyle = col; b.lineWidth = 0.55 * s;
  const span = 30 * s, sag = 11 * s;
  for (const dir of [-1, 1]) {
    b.beginPath();
    b.moveTo(x + (dir < 0 ? 0 : w * s), base + h * s);
    b.quadraticCurveTo(x + dir * span * 0.5, base + (h * s - sag), x + dir * span, base + h * s * 0.62);
    b.stroke();
  }
}

function crane(b, x, base, s, seed, col) {
  const h = 12 + hash(seed) * 9, arm = 10 + hash(seed + 1) * 6;
  b.fillStyle = col;
  b.fillRect(x, base, 1.5 * s, h * s);
  b.fillRect(x - arm * 0.25 * s, base + h * s, arm * s, 1.4 * s);
  b.fillRect(x + arm * 0.6 * s, base + (h - 5) * s, 0.9 * s, 5 * s);     // the hoist line
  b.fillRect(x + (arm * 0.6 - 1) * s, base + (h - 6.4) * s, 2.6 * s, 1.5 * s);
}

function warehouse(b, x, base, s, seed, col, lit) {
  const w = 12 + hash(seed) * 11, h = 5 + hash(seed + 1) * 5;
  b.fillStyle = col;
  b.fillRect(x, base, w * s, h * s);
  b.beginPath();                                                        // a sawtooth roof
  b.moveTo(x, base + h * s);
  for (let i = 0; i < 4; i++) {
    b.lineTo(x + (i + 0.5) * (w / 4) * s, base + (h + 2.6) * s);
    b.lineTo(x + (i + 1) * (w / 4) * s, base + h * s);
  }
  b.closePath(); b.fill();
  if (lit && hash(seed + 5) > 0.4) { b.fillStyle = lit; b.fillRect(x + w * 0.2 * s, base + 1.2 * s, 2.0 * s, 2.2 * s); }
}

function pipeRun(b, x, base, s, seed, col) {
  const h = 3 + hash(seed) * 3, len = 13 + hash(seed + 1) * 9;
  b.fillStyle = col;
  b.fillRect(x, base + h * s, len * s, 1.5 * s);
  for (let i = 0; i < 3; i++) b.fillRect(x + (2 + i * len / 3) * s, base, 1.1 * s, h * s);
  b.fillRect(x + len * 0.4 * s, base + (h + 1.5) * s, 1.3 * s, 4 * s);   // a riser
}

function ridge(b, x, base, s, seed, col) {
  const w = 30 + hash(seed) * 26, h = 4 + hash(seed + 1) * 7;
  b.fillStyle = col;
  b.beginPath();
  b.moveTo(x, base);
  b.quadraticCurveTo(x + w * 0.5 * s, base + h * s, x + w * s, base);
  b.closePath(); b.fill();
}

// par   how much of the camera's movement this band takes (0 = painted on the sky)
// dist  how far away it reads, 0-1, which is how far its colour is mixed into the sky
// y     world height of the band's base
// step  studs between motifs
const THEMES = {
  'Iron works': [
    { par: 0.06, dist: 0.58, y: -4, step: 22, s: 1.0, key: 'backdrop', draw: (b, x, y, s, sd, c) => chimneyStack(b, x, y, s, sd, c, null) },
    { par: 0.14, dist: 0.40, y: -6, step: 18, s: 0.95, key: 'backdrop', draw: (b, x, y, s, sd, c) => chimneyStack(b, x, y, s, sd, c, 'rgba(255,150,60,0.75)') },
    { par: 0.26, dist: 0.34, y: -9, step: 21, s: 1.0, key: 'ground', draw: gantry },
    { par: 0.40, dist: 0.24, y: -13, step: 17, s: 1.0, key: 'ground', draw: pipeRun },
  ],
  'Suspension bridge': [
    { par: 0.05, dist: 0.62, y: -4, step: 40, s: 1.0, key: 'backdrop', draw: ridge },
    { par: 0.12, dist: 0.38, y: -6, step: 62, s: 1.0, key: 'ground', draw: tower },
    { par: 0.28, dist: 0.30, y: -10, step: 20, s: 0.9, key: 'ground', draw: gantry },
  ],
  'Smelting floor': [
    { par: 0.07, dist: 0.52, y: -4, step: 20, s: 1.0, key: 'backdrop', draw: (b, x, y, s, sd, c) => chimneyStack(b, x, y, s, sd, c, 'rgba(255,120,40,0.6)') },
    { par: 0.18, dist: 0.32, y: -6, step: 19, s: 1.0, key: 'ground', draw: (b, x, y, s, sd, c) => warehouse(b, x, y, s, sd, c, 'rgba(255,160,60,0.85)') },
    { par: 0.34, dist: 0.26, y: -11, step: 15, s: 1.0, key: 'ground', draw: pipeRun },
  ],
  'City rooftops': [
    { par: 0.05, dist: 0.60, y: -4, step: 13, s: 1.0, key: 'backdrop', draw: (b, x, y, s, sd, c) => skyline(b, x, y, s, sd, c, null) },
    { par: 0.13, dist: 0.42, y: -6, step: 12, s: 1.0, key: 'backdrop', draw: (b, x, y, s, sd, c) => skyline(b, x, y, s, sd, c, 'rgba(255,214,140,0.8)') },
    { par: 0.27, dist: 0.36, y: -9, step: 16, s: 1.0, key: 'ground', draw: (b, x, y, s, sd, c) => skyline(b, x, y, s, sd, c, 'rgba(255,226,170,0.55)') },
    { par: 0.42, dist: 0.22, y: -14, step: 26, s: 0.8, key: 'ground', draw: crane },
  ],
  'Dry lake': [
    { par: 0.04, dist: 0.52, y: -3, step: 44, s: 1.0, key: 'ground', draw: mesa },
    { par: 0.11, dist: 0.34, y: -5, step: 36, s: 1.1, key: 'ground', draw: mesa },
    { par: 0.24, dist: 0.20, y: -7, step: 30, s: 0.8, key: 'ground', draw: mesa },
  ],
  'Flooded dock': [
    { par: 0.05, dist: 0.50, y: -3, step: 34, s: 0.9, key: 'ground', draw: ridge },
    { par: 0.14, dist: 0.38, y: -5, step: 24, s: 1.0, key: 'backdrop', draw: (b, x, y, s, sd, c) => warehouse(b, x, y, s, sd, c, 'rgba(255,232,180,0.7)') },
    { par: 0.30, dist: 0.28, y: -10, step: 26, s: 1.0, key: 'ground', draw: crane },
  ],
};
export function drawScenery(b, stage, cam, t, BW) {
  const p = stage.data.palette;
  const bands = THEMES[stage.data.theme];
  const skyCol = (p.skyStops && p.skyStops[p.skyStops.length - 1][1]) || p.sky || '#BFE3E8';
  if (!bands) return;
  const halfW = BW / (2 * cam.ppu);
  const floor = (stage.main && stage.main.top) || 0;

  for (const L of bands) {
    // The band slides against the camera, so what is on screen is a window into an infinite strip.
    const shift = cam.x * L.par;
    const left = cam.x - halfW - L.step, right = cam.x + halfW + L.step;
    const colour = haze(p[L.key] || p.backdrop || '#8E9BB0', skyCol, L.dist);
    const i0 = Math.floor((left - shift) / L.step), i1 = Math.ceil((right - shift) / L.step);
    for (let i = i0; i <= i1; i++) {
      const x = i * L.step + shift + (hash(i * 3 + 11) - 0.5) * L.step * 0.45;
      // Anchored to the stage floor, not to world zero. The camera shows about 50x37 studs, so a
      // band based at a fixed world Y is either buried under the ground or off the top of the
      // screen depending on the stage - the first version put every silhouette below the visible
      // bottom edge and the scenery simply did not appear.
      L.draw(b, x, floor + L.y, L.s, i * 13 + 7, colour);
    }
  }

  // Ground haze: the band where the scenery meets the stage, which is what stops the silhouettes
  // from looking like stickers standing on nothing.
  const g = b.createLinearGradient(0, floor - 4, 0, floor + 2);
  g.addColorStop(0, skyCol);
  g.addColorStop(1, 'rgba(0,0,0,0)');
  b.globalAlpha = 0.22;
  b.fillStyle = g;
  b.fillRect(cam.x - halfW - 4, floor - 4, halfW * 2 + 8, 6);
  b.globalAlpha = 1;
}


// ------------------------------------------------------------------- platform surfacing -----
// The stage itself was four fillRects: a slab, a shaded underside, a bright cap and a white line.
// At gameplay zoom that is a grey bar, and it looked like one on every stage in the game - the
// foundry's steel plate and the saltflat's baked crust were the same rectangle in two colours.
//
// Each theme gets a surface treatment drawn INTO the slab: rivet rows and plate seams on steel,
// courses on stone, strata on rock, planking on timber. All of it is positioned off world X, so
// it stays locked to the stage rather than swimming when the camera moves, and all of it is
// clipped to the slab it belongs to.

const SURFACE = {
  'Iron works': 'steel',
  'Smelting floor': 'steel',
  'Suspension bridge': 'steel',
  'City rooftops': 'stone',
  'Dry lake': 'strata',
  'Flooded dock': 'plank',
};

export function drawSurface(b, stage, sp, depth, top) {
  const p = stage.data.palette;
  const kind = SURFACE[stage.data.theme] || 'stone';
  const x1 = sp.x1, x2 = sp.x2, w = x2 - x1;
  const bottom = top - depth;
  b.save();
  b.beginPath(); b.rect(x1, bottom, w, depth); b.clip();

  if (kind === 'steel') {
    // Plate seams every eight studs, with a rivet row down each one and along the top edge.
    b.fillStyle = 'rgba(0,0,0,0.22)';
    for (let x = Math.ceil(x1 / 8) * 8; x < x2; x += 8) b.fillRect(x, bottom, 0.3, depth);
    b.fillStyle = 'rgba(255,255,255,0.10)';
    for (let x = Math.ceil(x1 / 8) * 8; x < x2; x += 8) b.fillRect(x + 0.3, bottom, 0.2, depth);
    b.fillStyle = 'rgba(255,255,255,0.18)';
    for (let x = x1 + 1.4; x < x2 - 0.6; x += 2.6) b.fillRect(x, top - 2.1, 0.45, 0.45);   // rivets
    b.fillStyle = 'rgba(0,0,0,0.20)';
    for (let x = x1 + 1.4; x < x2 - 0.6; x += 2.6) b.fillRect(x, top - 2.45, 0.45, 0.35);
  } else if (kind === 'stone') {
    // Courses, offset every other row, the way brick actually stacks.
    b.fillStyle = 'rgba(0,0,0,0.20)';
    let row = 0;
    for (let y = top - 1.6; y > bottom; y -= 2.4, row++) {
      b.fillRect(x1, y, w, 0.22);
      for (let x = x1 + (row % 2 ? 2.6 : 0.9); x < x2; x += 5.2) b.fillRect(x, y - 2.4, 0.22, 2.4);
    }
  } else if (kind === 'strata') {
    // Sedimentary banding: horizontal layers of slightly different value.
    for (let i = 0, y = top - 1.4; y > bottom; i++, y -= 1.1 + hash(i) * 1.9) {
      b.fillStyle = hash(i + 40) > 0.5 ? 'rgba(0,0,0,0.19)' : 'rgba(255,255,255,0.11)';
      b.fillRect(x1, y - 1.4, w, 1.4);
    }
  } else {
    // Planking: boards across the slab with a dark gap between each.
    b.fillStyle = 'rgba(0,0,0,0.22)';
    for (let x = Math.ceil(x1 / 3.4) * 3.4; x < x2; x += 3.4) b.fillRect(x, top - 2.2, 0.28, 2.2);
    b.fillStyle = 'rgba(0,0,0,0.16)';
    for (let y = top - 2.2; y > bottom; y -= 2.2) b.fillRect(x1, y, w, 0.25);
  }

  // Weathering down the face, so the slab is not one flat value from the cap to the bottom of the
  // screen. Deterministic per stage-x, so it never crawls.
  b.fillStyle = 'rgba(0,0,0,0.18)';
  for (let i = 0; i < Math.ceil(w / 4); i++) {
    const x = x1 + hash(i * 5 + 3) * w;
    b.fillRect(x, top - depth, 0.6 + hash(i * 5 + 4) * 1.6, depth * (0.25 + hash(i * 5 + 6) * 0.6));
  }
  b.restore();
}
