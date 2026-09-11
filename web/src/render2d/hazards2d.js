// Hazards, drawn.
//
// Every one of these used to be a single `fillRect` — the vents were an orange box, the dust devil
// a beige box, the sprinkler a blue box, the tide a flat blue slab. They read as debug overlays
// because that is what they were, and a player could not tell a wind-up from an eruption.
//
// The rules this file follows:
//
//   1. A hazard must look like the thing it is. Steam billows and expands; sand falls in grains;
//      water has a surface and foam; electricity is jagged. A translucent rectangle is none of
//      these, and at a 480x270 backbuffer the shape is all you have.
//   2. The WARNING has to be as legible as the event. Every hazard here draws its wind-up as a
//      different picture, not a dimmer version of the same one, because that is the frame the
//      player actually has to read.
//   3. Motion comes from the simulation where it can. Phase, sweep position, tide level, funnel
//      spin and drop positions are all state the engine already keeps, so the picture cannot
//      disagree with the hitbox.
//   4. Nothing here allocates. These run every frame for up to four hazards at once, so the
//      particle-ish detail is generated from a cheap deterministic hash of (index, time) rather
//      than from stored arrays — same look, no garbage, and it survives a pause.
//
// Everything is drawn in WORLD space (studs, +Y up); the renderer sets that transform.

const PI = Math.PI;
const TAU = PI * 2;
const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);

// Deterministic pseudo-random in [0,1) from an integer. Used so a "particle" with a given index
// always has the same size and offset, frame after frame, without keeping an array of them.
function hash(i) {
  let x = Math.sin(i * 127.1 + 311.7) * 43758.5453;
  return x - Math.floor(x);
}

// A soft blob. Canvas has no cheap blur at this resolution, so body is built from a few
// overlapping translucent circles instead — which is also what reads best as steam and dust.
function puff(b, x, y, r, alpha, colour) {
  b.globalAlpha = alpha;
  b.fillStyle = colour;
  b.beginPath(); b.arc(x, y, r, 0, TAU); b.fill();
}

// ---------------------------------------------------------------------------- STEAM VENTS ----
// Idle: a dark grate with heat bleeding through the slots.
// Warn: the slots go white-hot, the grate jitters, and small puffs escape early — the picture
//       changes completely rather than getting brighter, so the wind-up is unmistakable.
// Erupt: a column of overlapping billows, expanding and slowing as it rises, brightest at the
//        throat, with fast wisps shooting up the core ahead of the body of the steam.
function drawVents(b, v, t, pal, stage) {
  const m = stage.main;
  const top = m.top;
  const warn = v.phase === 'warn', erupt = v.phase === 'active';
  for (let pi = 0; pi < v.positions.length; pi++) {
    const px = v.positions[pi];
    const armed = v.armed.includes(px);
    const jitter = warn && armed ? Math.sin(t * 60 + pi) * 0.12 : 0;
    const w = v.width;

    // the grate itself
    b.globalAlpha = 1;
    b.fillStyle = '#2A2320';
    b.fillRect(px - w / 2, top - 0.1, w, 1.1);
    const slotGlow = erupt ? 1 : warn && armed ? 0.35 + 0.65 * Math.abs(Math.sin(t * 22)) : 0.16;
    for (let i = 0; i < 5; i++) {
      const sx = px - w / 2 + 0.55 + i * (w - 1.1) / 4;
      b.globalAlpha = slotGlow;
      b.fillStyle = erupt ? '#FFF3D0' : '#FF9A3C';
      b.fillRect(sx - 0.22 + jitter, top + 0.05, 0.44, 0.85);
    }

    if (!armed) { b.globalAlpha = 1; continue; }

    if (warn) {
      // heat haze and a few escaping puffs, low and small
      const k = v.k;
      for (let i = 0; i < 7; i++) {
        const h1 = hash(pi * 31 + i);
        const rise = ((t * 1.4 + h1) % 1);
        const y = top + 0.8 + rise * 4.2;
        const x = px + (h1 - 0.5) * w * 0.7 + Math.sin(t * 2 + i) * 0.3;
        puff(b, x, y, 0.4 + rise * 0.7, (1 - rise) * (0.45 + 0.3 * k), '#C9BBA8');
      }
      // a thin crack of light widening across the grate
      b.globalAlpha = 0.25 + 0.4 * k;
      b.fillStyle = '#FFD9A0';
      b.fillRect(px - (w / 2) * k, top + 0.9, w * k, 0.22);
      b.globalAlpha = 1;
      continue;
    }

    if (!erupt) { b.globalAlpha = 1; continue; }

    // ---- the column ----
    const s = v.strength;               // 0→1→0 across the eruption, from the engine
    const reach = 26 * s;
    // body: overlapping billows that widen and fade with height
    for (let i = 0; i < 26; i++) {
      const h1 = hash(pi * 71 + i), h2 = hash(pi * 71 + i + 500);
      // each billow runs its own loop up the column
      const rise = ((t * 1.15 + h1) % 1);
      const y = top + rise * reach;
      const spread = 0.35 + rise * 0.95;
      const x = px + (h2 - 0.5) * w * spread + Math.sin(rise * 5 + h1 * 6) * 0.8 * rise;
      const r = (0.5 + h2 * 0.7) * (0.6 + rise * 1.9);
      // hot at the throat, cooling to white-grey as it climbs
      const hot = clamp(1 - rise * 2.2, 0, 1);
      // #DCD6CE sat right on Smeltworks' warm backdrop; #B8ADA0 gives the column a value range
      // of its own rather than relying on the white core streaks to be seen at all.
      const col = hot > 0.5 ? '#FFD9A0' : '#B8ADA0';
      puff(b, x, y, r, (1 - rise) * 0.5 * s, col);
    }
    // core: a bright fast jet up the middle, well ahead of the billows
    b.globalAlpha = 0.55 * s;
    b.fillStyle = '#FFF3D0';
    b.fillRect(px - w * 0.16, top, w * 0.32, reach * 0.75);
    for (let i = 0; i < 6; i++) {
      const h1 = hash(pi * 17 + i);
      const rise = ((t * 2.6 + h1) % 1);
      b.globalAlpha = (1 - rise) * 0.85 * s;
      b.fillStyle = '#FFFFFF';
      b.fillRect(px + (h1 - 0.5) * w * 0.5, top + rise * reach, 0.2, 1.4);
    }
    // the throat: a bright flare sitting on the grate
    puff(b, px, top + 0.6, w * 0.42 * s, 0.5 * s, '#FFE9C0');
    b.globalAlpha = 1;
  }
}

// ---------------------------------------------------------------------------- SLAG DRIP ----
// Molten droplets off the gantry, each with a stretched trail, ending in a spark splash.
function drawSlag(b, v, t) {
  for (const d of v.drops) {
    if (d.splash > 0) {
      const k = d.splash;
      for (let i = 0; i < 7; i++) {
        const a = (i / 7) * PI + PI;                     // upward fan
        const sp = (1 - k) * 3.2;
        b.globalAlpha = k * 0.9;
        b.fillStyle = i % 2 ? '#FFD37A' : '#FF7A3C';
        b.fillRect(d.x + Math.cos(a) * sp - 0.13, d.y - Math.sin(a) * sp * 0.8 - 0.13, 0.26, 0.26);
      }
      b.globalAlpha = k * 0.5;
      b.fillStyle = '#FF7A3C';
      b.beginPath(); b.ellipse(d.x, d.y, 1.4 * (1 - k) + 0.5, 0.3, 0, 0, TAU); b.fill();
      b.globalAlpha = 1;
      continue;
    }
    b.globalAlpha = 0.4;
    b.fillStyle = '#FF9A3C';
    b.fillRect(d.x - 0.09, d.y, 0.18, 2.0);              // the trail it stretches into
    b.globalAlpha = 1;
    // A dark rim around the drop, so it does not depend on one sub-pixel white dot to be seen
    // against a stage that is already orange.
    b.fillStyle = '#5A2E18';
    b.beginPath(); b.ellipse(d.x, d.y, 0.40, 0.56, 0, 0, TAU); b.fill();
    b.fillStyle = '#FFD37A';
    b.beginPath(); b.ellipse(d.x, d.y, 0.28, 0.42, 0, 0, TAU); b.fill();
    b.fillStyle = '#FFFFFF';
    b.beginPath(); b.arc(d.x, d.y + 0.08, 0.18, 0, TAU); b.fill();
  }
}

// ---------------------------------------------------------------------------- SPRINKLER ----
// A burst pipe. The jet is an ARC, not a column: it leaves the pipe sideways, bends over under
// gravity and lands, with a spray fan where it hits. Behind it, the roof is visibly wet, and the
// wet patches dry out over ten seconds — the slick is the real hazard and it has to be readable.
function drawSprinkler(b, v, t, pal, stage) {
  const m = stage.main;
  // the slicks first, so the jet draws over them
  for (const w of v.wet) {
    // Cells overlap by half a stud and carry a fainter outer skirt, so a swept stretch of roof
    // reads as one continuous wet patch instead of a row of discrete tiles.
    // A hue Rooftops does not otherwise use. The slick was #5B7C8D on a #5A6478 deck — the deck's
    // own colour, measured at 1.13 when fresh and 1.04 at nine seconds. The slick IS this hazard;
    // it cannot be the one element you cannot see.
    b.globalAlpha = (0.18 + w.k * 0.37) * 0.45;
    b.fillStyle = '#2E5A66';
    b.fillRect(w.x - 2.6, w.y - 0.05, 5.2, 0.45);
    b.globalAlpha = 0.18 + w.k * 0.37;
    b.fillRect(w.x - 2.1, w.y - 0.05, 4.2, 0.5);
    // a highlight that shivers, so wet floor does not read as painted floor
    b.globalAlpha = w.k * (0.34 + 0.22 * Math.sin(t * 3 + w.x));
    b.fillStyle = '#CFE9F5';
    b.fillRect(w.x - 1.5, w.y + 0.18, 3.0, 0.35);
  }
  b.globalAlpha = 1;

  if (v.phase === 'warn') {
    // the pipe shudders and drips accelerate: a different picture from the sweep
    const px = m.x1 - 4, py = m.top + v.height;
    b.globalAlpha = 0.5 + 0.5 * Math.abs(Math.sin(t * 26));
    b.fillStyle = '#9FD1E8';
    b.fillRect(px - 1.2, py, 2.4, 0.5);
    for (let i = 0; i < 7; i++) {
      const k = ((t * 1.8 + i / 7) % 1);
      b.globalAlpha = 1 - k;
      b.fillRect(px - 0.12 + (hash(i * 5) - 0.5) * 1.4, py - k * 6, 0.24, 0.7 + k * 0.6);
    }
    b.globalAlpha = 1;
    return;
  }
  if (v.phase !== 'active') return;

  // ---- the jet ----
  const x0 = v.x - v.dir * 7;                 // where it leaves the pipe
  const y0 = m.top + v.height;
  const x1 = v.x, y1 = m.top;                 // where it lands
  const seg = 16;
  for (let i = 0; i < seg; i++) {
    const k = i / (seg - 1);
    // quadratic: flat out of the pipe, steep at the end
    const x = x0 + (x1 - x0) * k;
    const y = y0 + (y1 - y0) * (k * k);
    const w = v.radius * (0.45 + 0.55 * k);
    b.globalAlpha = 0.30 + 0.28 * k;
    b.fillStyle = '#AEDCF0';
    b.beginPath(); b.ellipse(x, y, w * 0.55, w * 0.42, 0, 0, TAU); b.fill();
  }
  // droplets running along the arc, so it reads as moving water and not a painted band
  for (let i = 0; i < 22; i++) {
    const h1 = hash(i * 13);
    const k = ((t * 1.9 + h1) % 1);
    const x = x0 + (x1 - x0) * k + (hash(i * 7) - 0.5) * 1.6;
    const y = y0 + (y1 - y0) * (k * k) + (hash(i * 29) - 0.5) * 1.2;
    b.globalAlpha = 0.75 * (1 - k * 0.4);
    b.fillStyle = i % 3 ? '#DFF3FB' : '#FFFFFF';
    b.fillRect(x, y, 0.22, 0.5);
  }
  // impact fan on the roof
  for (let i = 0; i < 12; i++) {
    const h1 = hash(i * 53);
    const k = ((t * 3.2 + h1) % 1);
    const a = PI * 0.18 + h1 * PI * 0.64;
    const sp = k * 5.5;
    b.globalAlpha = (1 - k) * 0.7;
    b.fillStyle = '#EAF7FD';
    b.fillRect(v.x + Math.cos(a) * sp * v.dir, m.top + Math.sin(a) * sp * 0.6, 0.24, 0.24);
  }
  b.globalAlpha = 1;
}

// ---------------------------------------------------------------------------- ANTENNA ARC ----
// Charge builds as a glow at both masts, then a jagged bolt with branches. The bolt is re-seeded
// every other frame so it crackles instead of sitting still.
function drawArc(b, v, t, pal) {
  const { x1, x2, y } = v;
  if (v.phase === 'warn') {
    // Violet-white, NOT sky blue. The charge glow used to be #9AD8FF on a stage whose whole sky is
    // in that family — measured at about 1.08 contrast, the palest thing in the game. Violet is
    // the one hue absent from Rooftops' palette, so it can never blend into the backdrop.
    const k = v.k;
    for (const mx of [x1, x2]) {
      b.globalAlpha = 0.35 + 0.65 * k * Math.abs(Math.sin(t * 30));
      b.fillStyle = '#E6CFFF';
      b.beginPath(); b.arc(mx, y, 0.6 + k * 1.3, 0, TAU); b.fill();
      b.globalAlpha = 0.5 * k;
      b.fillStyle = '#8B5CE0';
      b.beginPath(); b.arc(mx, y, 1.4 + k * 2.4, 0, TAU); b.fill();
      // feelers reaching toward the middle: the motion cue that says WHERE, not just that
      for (let i = 0; i < 4; i++) {
        const h1 = hash(i + Math.floor(t * 20) * 7);
        b.globalAlpha = 0.35 + k * 0.55;
        b.fillStyle = '#F2E6FF';
        b.fillRect(mx + (mx < 0 ? 1 : -1) * h1 * 6 * k, y + (h1 - 0.5) * 2.4, 0.8, 0.2);
      }
    }
    b.globalAlpha = 1;
    return;
  }
  if (v.phase !== 'active') return;
  const seed = Math.floor(t * 30);                     // re-seeded twice a frame-pair: crackle
  const draw = (width, colour, alpha, spread) => {
    b.globalAlpha = alpha; b.strokeStyle = colour; b.lineWidth = width;
    b.beginPath(); b.moveTo(x1, y);
    const n = 11;
    for (let i = 1; i <= n; i++) {
      const k = i / n;
      const jag = (hash(seed * 97 + i) - 0.5) * spread * Math.sin(k * PI);
      b.lineTo(x1 + (x2 - x1) * k, y + jag);
    }
    b.stroke();
  };
  draw(0.9, '#4FA8E8', 0.35, 7);                       // outer glow
  draw(0.42, '#BFE8FF', 0.8, 5);
  draw(0.16, '#FFFFFF', 1, 4);                         // white core
  // branches that fork off and die
  b.globalAlpha = 0.6; b.strokeStyle = '#BFE8FF'; b.lineWidth = 0.14;
  for (let i = 0; i < 5; i++) {
    const h1 = hash(seed * 13 + i);
    const bx = x1 + (x2 - x1) * (0.15 + h1 * 0.7);
    b.beginPath(); b.moveTo(bx, y);
    b.lineTo(bx + (hash(seed + i) - 0.5) * 6, y - 2 - hash(seed * 3 + i) * 4);
    b.stroke();
  }
  b.globalAlpha = 1;
}

// ---------------------------------------------------------------------------- DUST DEVIL ----
// A cone, not a box. Stacked rotating rings, narrow at the base and wide at the top, with grit
// orbiting them and a plume dragging along the ground. The warning is dust skittering in from
// the side it is about to arrive from, so you know which way to run before you can see it.
function drawDustDevil(b, v, t, pal, stage) {
  const m = stage.main;
  if (v.warn && !v.active) {
    const k = v.warnK;
    for (let i = 0; i < 14; i++) {
      const h1 = hash(i * 19);
      const run = ((t * 2.2 + h1) % 1);
      const x = v.from + (v.from < 0 ? 1 : -1) * run * 22;
      b.globalAlpha = (1 - run) * 0.85 * k;
      b.fillStyle = '#5A4A2C';                             // dark grit on a pale flat: legible
      b.fillRect(x, m.top + h1 * 1.4, 1.9 + h1 * 2.0, 0.3);
    }
    b.globalAlpha = 1;
    return;
  }
  if (!v.active) return;

  const base = m.top;
  // ground plume: a low skirt of dust being dragged along
  for (let i = 0; i < 14; i++) {
    const h1 = hash(i * 23);
    const k = ((t * 1.6 + h1) % 1);
    const x = v.x - v.dir * k * 9;
    b.globalAlpha = (1 - k) * 0.4;
    b.fillStyle = '#CBB489';
    b.beginPath(); b.ellipse(x, base + 0.3 + k * 1.2, 1.4 + k * 2.6, 0.5 + k * 0.7, 0, 0, TAU); b.fill();
  }
  // the funnel: rings up the cone, each rotated a little more than the one below
  const rings = 20;   // 13 left visible gaps between the ellipses instead of a body
  for (let i = 0; i < rings; i++) {
    const up = i / (rings - 1);
    const y = base + up * v.height;
    const r = v.radius * (0.35 + 0.65 * up);
    const spin = v.spin + up * 3.4;
    // the ring is drawn as an ellipse offset by its own rotation, so the cone visibly turns
    const wob = Math.sin(spin) * r * 0.22;
    // Saltflat is tan on tan, so the funnel cannot be tan. Measured against this stage's own sky
    // the old ramp came out at 1.01 / 1.05 / 1.28 — an eleven-by-twenty-stud tornado whose quiet,
    // warning and event frames were the same picture. The whole ramp is a full value step down,
    // and the alpha roughly doubled.
    b.globalAlpha = 0.34 + 0.34 * (1 - up);
    b.fillStyle = up < 0.35 ? '#5A4A2C' : up < 0.7 ? '#7A6440' : '#9C8558';
    b.beginPath(); b.ellipse(v.x + wob, y, r, r * 0.30, 0, 0, TAU); b.fill();
    // a brighter leading edge, which is what sells the rotation
    b.globalAlpha = 0.55 * (1 - up * 0.4);
    b.fillStyle = '#FFF2D2';
    b.beginPath();
    b.ellipse(v.x + wob, y, r, r * 0.30, 0, spin % TAU, (spin % TAU) + 1.5);
    b.lineWidth = 0.3; b.strokeStyle = '#F0E0BC'; b.stroke();
  }
  // grit orbiting the outside
  for (let i = 0; i < 20; i++) {
    const h1 = hash(i * 37), h2 = hash(i * 37 + 91);
    const up = (h1 + t * 0.35) % 1;
    const a = v.spin * (0.8 + h2 * 0.6) + h1 * TAU;
    const r = v.radius * (0.5 + 0.7 * up) * (0.85 + h2 * 0.4);
    b.globalAlpha = 0.35 + 0.4 * (1 - up);
    b.fillStyle = h2 > 0.7 ? '#8C7A56' : '#E4D2AC';
    const sz = 0.18 + h2 * 0.3;
    b.fillRect(v.x + Math.cos(a) * r, base + up * v.height + Math.sin(a) * r * 0.28, sz, sz);
  }
  b.globalAlpha = 1;
}

// ---------------------------------------------------------------------------- SANDFALL ----
// A curtain of grains off the mesa lip, with a billow where it lands. The warning is the lip
// itself starting to shed — a thin trickle before the pour.
function drawSandfall(b, v, t) {
  const warn = v.phase === 'warn', on = v.phase === 'active';
  if (!warn && !on) return;
  // The pre-pour trickle used to top out at 0.15 alpha, which is not a warning. It now has a
  // floor of 0.35 so the lip visibly starts shedding before the curtain arrives.
  const k = on ? Math.sin(clamp(v.k, 0, 1) * PI) : 0.35 + v.k * 0.35;
  const n = on ? 46 : 10;
  for (let i = 0; i < n; i++) {
    const h1 = hash(i * 11), h2 = hash(i * 11 + 401);
    const fall = ((t * (0.7 + h2 * 0.5) + h1) % 1);
    const y = v.from - fall * (v.from - v.to);
    const x = v.x + (h1 - 0.5) * v.width * (0.5 + fall * 0.6);
    // A full value step darker than Saltflat's sky. The old grains (#E6D2AC / #C9AE7E) were tan
    // on a tan-and-cream palette — measured at 1.05 contrast, the closest thing in the game to
    // invisible. Sand in shadow is dark; falling sand especially so.
    b.globalAlpha = (1 - fall * 0.55) * 0.75 * k;
    b.fillStyle = h2 > 0.6 ? '#6E5636' : '#8A6E45';
    b.fillRect(x, y, 0.24 + h2 * 0.22, 1.0 + fall * 1.5);
  }
  // the lip itself, shedding
  b.globalAlpha = 0.6 * k;
  b.fillStyle = '#6E5636';
  b.fillRect(v.x - v.width * 0.34, v.from - 0.6, v.width * 0.68, 0.9);
  b.globalAlpha = 0.5 * k;
  b.fillStyle = '#F0E0BC';
  b.fillRect(v.x - v.width * 0.34, v.from - 0.7, v.width * 0.68, 0.22);
  b.globalAlpha = 1;
}

// ---------------------------------------------------------------------------- TIDE ----
// Water with an actual surface, and — the part that took two goes — water you can SEE.
//
// The first version painted #3D7A95 at 0.42 alpha. Undertow's sky bottoms out at #33566E, so the
// water as drawn came out at rgb(55,101,126) against a sky of rgb(51,86,110): four, fifteen and
// sixteen units of difference per channel. It was not subtle, it was invisible — and it was
// LIGHTER than the sky above it, which is backwards for a body of water and read as haze.
//
// So: the sea is now decisively darker than anything above it, it deepens with distance below the
// surface, and the surface itself is built the way a 2D artist builds a waterline — a bright foam
// crest with a hard dark band immediately under it. That dark band is what does the work; a light
// line on its own washes into a light sky, but light-on-dark is legible against anything.
// The tide's colour ramp, named so a test can assert it against the stage's own sky. Contrast
// here is not a matter of taste: the waterline is the most important thing to read on Undertow,
// and the first version differed from the sky behind it by four units of red.
export const TIDE_RAMP = {
  deep: '#10303C',
  shelves: ['#17485A', '#1F6076', '#2C7E97'],
  underCrest: '#0A2029',
  foam: '#EAFBFF',
};

function drawTide(b, v, t, pal, stage) {
  const m = stage.main;
  const bl = stage.blast;
  // Two swells at incommensurate periods rather than one, so the surface never visibly repeats
  // over a long set.
  const surfaceAt = (x) => v.level
    + Math.sin(v.swell * 1.1 + x * 0.12) * v.amp
    + Math.sin(v.swell * 0.43 + x * 0.047) * v.amp * 0.55;
  const bands = [[bl.left, -v.edge], [v.edge, bl.right]];
  const floor = bl.bottom - 10;

  for (const [xa, xb] of bands) {
    const poly = (yOff) => {
      b.beginPath();
      b.moveTo(xa, floor);
      for (let x = xa; x <= xb; x += 2) b.lineTo(x, surfaceAt(x) + yOff);
      b.lineTo(xb, floor);
      b.closePath();
    };
    // Deep body. Nearly opaque and much darker than the darkest sky stop, so the horizon line is
    // unambiguous no matter what the backdrop is doing behind it.
    b.globalAlpha = 0.92;
    b.fillStyle = TIDE_RAMP.deep;
    poly(0); b.fill();
    // Three shelves of lighter water stacked near the surface: cheap depth, and it makes the
    // volume read as water rather than as a filled shape.
    const shelves = [[9, TIDE_RAMP.shelves[0], 0.85], [4.5, TIDE_RAMP.shelves[1], 0.8], [1.6, TIDE_RAMP.shelves[2], 0.75]];
    for (const [d, col, a] of shelves) {
      b.globalAlpha = a;
      b.fillStyle = col;
      b.beginPath();
      b.moveTo(xa, surfaceAt(xa) - d);
      for (let x = xa; x <= xb; x += 2) b.lineTo(x, surfaceAt(x));
      b.lineTo(xb, surfaceAt(xb) - d);
      b.closePath(); b.fill();
    }
    // The hard dark band under the crest. This is the single element that makes the waterline
    // readable against a pale sky.
    b.globalAlpha = 0.9;
    b.strokeStyle = TIDE_RAMP.underCrest; b.lineWidth = 0.75;
    b.beginPath();
    for (let x = xa; x <= xb; x += 1.5) {
      const y = surfaceAt(x) - 0.55;
      if (x === xa) b.moveTo(x, y); else b.lineTo(x, y);
    }
    b.stroke();
    // foam crest, in the stage's own accent so it belongs to the palette
    b.globalAlpha = 1;
    b.strokeStyle = TIDE_RAMP.foam; b.lineWidth = 0.42;
    b.beginPath();
    for (let x = xa; x <= xb; x += 1.5) {
      const y = surfaceAt(x);
      if (x === xa) b.moveTo(x, y); else b.lineTo(x, y);
    }
    b.stroke();
    b.globalAlpha = 0.55;
    b.strokeStyle = pal.accent || '#59D9F2'; b.lineWidth = 0.9;
    b.beginPath();
    for (let x = xa; x <= xb; x += 1.5) {
      const y = surfaceAt(x) + 0.35;
      if (x === xa) b.moveTo(x, y); else b.lineTo(x, y);
    }
    b.stroke();
    // broken foam riding the crests
    for (let i = 0; i < 22; i++) {
      const h1 = hash(i * 61 + (xa < 0 ? 0 : 997));
      const x = xa + (xb - xa) * ((h1 + t * 0.05) % 1);
      const y = surfaceAt(x);
      b.globalAlpha = 0.45 + 0.45 * Math.sin(t * 4 + i);
      b.fillStyle = '#FFFFFF';
      b.fillRect(x, y - 0.1, 0.6 + h1 * 0.8, 0.22);
    }
  }

  // Under the island, where it can still drown you. Same treatment, dimmed, so it reads as the
  // same sea seen through the structure rather than as a separate rectangle.
  const under = Math.min(v.level, m.bottom);
  b.globalAlpha = 0.55;
  b.fillStyle = TIDE_RAMP.deep;
  b.fillRect(-v.edge, floor, v.edge * 2, under - floor);
  b.globalAlpha = 0.4;
  b.strokeStyle = TIDE_RAMP.underCrest; b.lineWidth = 0.5;
  b.beginPath(); b.moveTo(-v.edge, under); b.lineTo(v.edge, under); b.stroke();
  b.globalAlpha = 1;
}

// ---------------------------------------------------------------------------- ROGUE WAVE ----
// A travelling crest with a breaking foam cap. Warned by the water drawing back.
function drawRogueWave(b, v, t, stage, tideLevel) {
  const lvl = tideLevel != null ? tideLevel : 0;
  if (v.warn && !v.active) {
    // the suck-back: a bright line racing the way the wave will come from
    b.globalAlpha = 0.35 * v.warnK;
    b.strokeStyle = '#E8F6FB'; b.lineWidth = 0.5;
    const m = stage.main;
    b.beginPath(); b.moveTo(m.x1 - 20, lvl + 0.4); b.lineTo(m.x2 + 20, lvl + 0.4); b.stroke();
    b.globalAlpha = 1;
    return;
  }
  if (!v.active) return;
  const w = v.width, h = v.crest;
  b.globalAlpha = 0.55;
  b.fillStyle = '#4E93AE';
  b.beginPath();
  b.moveTo(v.x - w, lvl);
  for (let i = 0; i <= 20; i++) {
    const k = i / 20;
    b.lineTo(v.x - w + k * w * 2, lvl + Math.sin(k * PI) * h);
  }
  b.lineTo(v.x + w, lvl - 12);
  b.lineTo(v.x - w, lvl - 12);
  b.closePath(); b.fill();
  // A bright leading face traced up the front of the crest. Without it the wave (#4E93AE) sits on
  // water it is nearly the same hue as and disappears for most of its travel.
  b.globalAlpha = 0.95;
  b.strokeStyle = '#E8F6FB'; b.lineWidth = 0.5;
  b.beginPath();
  for (let i = 0; i <= 20; i++) {
    const k = i / 20;
    const px = v.x - w + k * w * 2, py = lvl + Math.sin(k * PI) * h;
    if (i === 0) b.moveTo(px, py); else b.lineTo(px, py);
  }
  b.stroke();
  // breaking cap, leaning the way it travels
  b.globalAlpha = 0.9;
  b.fillStyle = '#EAF7FD';
  for (let i = 0; i < 16; i++) {
    const h1 = hash(i * 71);
    const k = 0.3 + h1 * 0.4;
    const x = v.x - w + k * w * 2 + v.dir * h1 * 3;
    const y = lvl + Math.sin(k * PI) * h + h1 * 1.2;
    b.fillRect(x, y, 0.5 + h1, 0.4);
  }
  b.globalAlpha = 1;
}

// ---------------------------------------------------------------------------- CROSSWIND ----
// The warning and the gust are two DIFFERENT PICTURES, in two different parts of the screen.
//
// The first version drew the same white sky streaks for both and separated them by alpha alone
// (0.15 warn, 0.28 gust) — which is the exact thing the rule at the top of this file forbids, and
// worse on The Span than anywhere else because its sky is the palest in the game (#D6E4EE to
// #E2EDF3): white-on-near-white at 0.15 alpha is not a warning, it is nothing.
//
//   WARN  grit skitters along the DECK, low and horizontal, with the deck's own cable stays
//         leaning the way the gust is about to blow. On the ground, dark on light, where nothing
//         else is happening — you read it without looking up.
//   GUST  streaks in the SKY, above the fight, carrying the fighters. Nothing on the deck.
//
// Different place, different value, different motion. No alpha comparison required.
function drawCrosswind(b, v, t, pal, stage) {
  const bl = stage.blast;
  const m = stage.main;
  if (v.phase === 'calm') return;

  if (v.phase === 'warn') {
    // grit running along the deck, in the direction the gust will come from
    for (let i = 0; i < 18; i++) {
      const h1 = hash(i * 29), h2 = hash(i * 29 + 137);
      const run = ((t * (0.9 + h2 * 0.8) + h1) % 1);
      const x = v.dir > 0 ? m.x1 + run * m.w : m.x2 - run * m.w;
      b.globalAlpha = Math.sin(run * PI) * (0.45 + h2 * 0.4);
      b.fillStyle = '#6B7A88';                         // dark on a pale deck: always legible
      b.fillRect(x, m.top + 0.15 + h1 * 0.9, (1.4 + h2 * 2.6) * v.dir, 0.26);
    }
    // the stays lean: a big, slow, unmissable shape change at the edges of the deck
    b.globalAlpha = 0.55;
    b.strokeStyle = '#5A6675'; b.lineWidth = 0.4;
    for (const sx of [m.x1 + 6, m.x2 - 6]) {
      const lean = v.dir * 3.2;
      b.beginPath();
      b.moveTo(sx, m.top);
      b.quadraticCurveTo(sx + lean * 0.6, m.top + 9, sx + lean, m.top + 17);
      b.stroke();
      // a pennant at the top, pointing downwind
      b.globalAlpha = 0.8;
      b.fillStyle = pal.accent || '#D9534F';
      b.beginPath();
      b.moveTo(sx + lean, m.top + 17);
      b.lineTo(sx + lean + v.dir * 3.4, m.top + 15.6);
      b.lineTo(sx + lean + v.dir * 0.6, m.top + 14.6);
      b.closePath(); b.fill();
      b.globalAlpha = 0.55;
    }
    b.globalAlpha = 1;
    return;
  }

  // ---- the gust itself: in the sky, well above the deck ----
  const k = v.strength;
  for (let i = 0; i < 30; i++) {
    const h1 = hash(i * 43), h2 = hash(i * 43 + 17);
    const run = ((t * (1.1 + h2 * 1.5) + h1) % 1);
    const x = v.dir > 0 ? bl.left + run * (bl.right - bl.left) : bl.right - run * (bl.right - bl.left);
    const y = m.top + 4 + h1 * (bl.top - m.top - 8);
    const len = (3 + h2 * 9) * (0.6 + k);
    // A dark leader under a white streak. On a pale sky the white alone vanishes; the pair reads
    // as a moving object at any alpha.
    b.globalAlpha = k * (0.30 + h2 * 0.30) * Math.sin(run * PI);
    b.fillStyle = '#7D8C9B';
    b.fillRect(x, y + 0.24, len * v.dir, 0.24);
    b.globalAlpha = k * (0.55 + h2 * 0.4) * Math.sin(run * PI);
    b.fillStyle = '#FFFFFF';
    b.fillRect(x, y, len * v.dir, 0.26);
  }
  b.globalAlpha = 1;
}

// ---------------------------------------------------------------------------- EMBER DRIFT ----
// Two columns of rising sparks just off each ledge. Fixed, gentle, and the only stage element in
// the game that is purely helpful — so it is drawn warm and calm, with no warning state at all.
function drawEmberDrift(b, v, t) {
  for (let pi = 0; pi < v.positions.length; pi++) {
    const px = v.positions[pi];
    const span = v.to - v.from;
    // a faint warm column so the boundary of the effect is visible without being loud
    b.globalAlpha = 0.05 + 0.03 * v.pulse;
    b.fillStyle = '#FF9A3C';
    b.fillRect(px - v.width / 2, v.from, v.width, span);
    for (let i = 0; i < 18; i++) {
      const h1 = hash(pi * 97 + i), h2 = hash(pi * 97 + i + 313);
      const rise = ((t * (0.18 + h2 * 0.16) + h1) % 1);
      const y = v.from + rise * span;
      const x = px + Math.sin(rise * 6 + h1 * TAU) * v.width * 0.34;
      const fade = Math.sin(rise * PI);
      b.globalAlpha = fade * (0.5 + h2 * 0.5);
      b.fillStyle = h2 > 0.55 ? '#FFD37A' : '#FF7A3C';
      const sz = 0.16 + h2 * 0.2;
      b.fillRect(x, y, sz, sz);
    }
  }
  b.globalAlpha = 1;
}

// -------------------------------------------------------------------------------------------
// Draw order matters: the tide is a backdrop the fighters stand in front of, the wave sits on
// it, and everything else is foreground. The renderer calls this twice — once before fighters
// for the `back` layer and once after for `front` — so a fighter is inside the steam rather than
// painted over it.
const BACK = new Set(['tide', 'roguewave', 'emberdrift', 'crosswind']);

export function drawHazards(b, stage, t, layer) {
  const v = stage.visual || {};
  const pal = stage.data.palette;
  const want = (key) => (layer === 'back') === BACK.has(key);

  if (v.tide && want('tide')) drawTide(b, v.tide, t, pal, stage);
  if (v.roguewave && want('roguewave')) drawRogueWave(b, v.roguewave, t, stage, stage.waterLevel);
  if (v.emberdrift && want('emberdrift')) drawEmberDrift(b, v.emberdrift, t);
  if (v.crosswind && want('crosswind')) drawCrosswind(b, v.crosswind, t, pal, stage);
  if (v.vents && want('vents')) drawVents(b, v.vents, t, pal, stage);
  if (v.slagfall && want('slagfall')) drawSlag(b, v.slagfall, t);
  if (v.sprinkler && want('sprinkler')) drawSprinkler(b, v.sprinkler, t, pal, stage);
  if (v.antennaarc && want('antennaarc')) drawArc(b, v.antennaarc, t, pal);
  if (v.dustdevil && want('dustdevil')) drawDustDevil(b, v.dustdevil, t, pal, stage);
  if (v.sandfall && want('sandfall')) drawSandfall(b, v.sandfall, t);
  b.globalAlpha = 1;
}

export { hash };
