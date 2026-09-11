// Ambient weather: the part of a stage that never touches a fighter.
//
// This exists because a stage that only moves when a hazard fires is dead between hazards, and
// the gap between hazards is most of a match. Rain falling, heat wobbling, sand streaming, gulls
// crossing — none of it is gameplay, all of it is the difference between a place and a backdrop.
//
// Two hard rules, both about not lying to the player:
//
//   1. Ambient NEVER looks like a hazard. It lives in a different part of the screen (high, far
//      back, or behind the stage body), it is low-contrast, and it never occupies the column or
//      band that a real hazard uses. Heat shimmer on Smeltworks is deliberately drawn as a wobble
//      of the BACKDROP rather than as rising particles, because rising particles on that stage
//      mean a vent is about to go off.
//   2. Ambient is cheap and unbounded in time. Everything is a function of (index, t) through the
//      same deterministic hash the hazards use — no arrays, no allocation, no drift, and it looks
//      identical whether you have been watching for four seconds or four minutes.
import { hash } from './hazards2d.js';

const PI = Math.PI;
const TAU = PI * 2;

// Rain: long thin streaks leaning with the wind, plus the occasional splash on the top surface
// of the main platform. Drawn in front of everything at low alpha so it reads as weather between
// the camera and the fight.
function rain(b, A, t, stage, view) {
  const bl = stage.blast;
  const n = Math.round(70 * A.rate);
  const wind = A.wind || 0;
  const top = bl.top, bottom = stage.main.top;
  const span = top - bottom;
  for (let i = 0; i < n; i++) {
    const h1 = hash(i * 7), h2 = hash(i * 7 + 91);
    const fall = ((t * (1.3 + h2 * 0.6) + h1) % 1);
    const x = bl.left + h1 * (bl.right - bl.left) + fall * wind;
    const y = top - fall * span;
    b.globalAlpha = 0.10 + h2 * 0.16;
    b.fillStyle = A.tint;
    b.fillRect(x, y, wind * 0.045, 1.6 + h2 * 1.4);
  }
  // splashes where it lands on the roof
  for (let i = 0; i < Math.round(14 * A.rate); i++) {
    const h1 = hash(i * 131);
    const k = ((t * 2.2 + h1) % 1);
    b.globalAlpha = (1 - k) * 0.35;
    b.fillStyle = A.tint;
    const x = stage.main.x1 + h1 * stage.main.w;
    b.fillRect(x - k * 0.8, stage.main.top + 0.1, 0.22, 0.16);
    b.fillRect(x + k * 0.8, stage.main.top + 0.1, 0.22, 0.16);
  }
  b.globalAlpha = 1;
}

// Blowing sand: near-horizontal streaks low over the flat, thickest near the ground.
function sand(b, A, t, stage) {
  const bl = stage.blast;
  const n = Math.round(56 * A.rate);
  for (let i = 0; i < n; i++) {
    const h1 = hash(i * 17), h2 = hash(i * 17 + 53);
    const run = ((t * (0.35 + h2 * 0.5) + h1) % 1);
    const x = bl.left + run * (bl.right - bl.left);
    // bias low: sand is heavier than air and this keeps it off the fighters' faces
    const y = stage.main.top + Math.pow(h1, 2.2) * 26 - 2;
    b.globalAlpha = (0.14 + h2 * 0.18) * Math.sin(run * PI);
    b.fillStyle = A.tint;
    b.fillRect(x, y, 2.5 + h2 * 5, 0.2 + h2 * 0.16);
  }
  b.globalAlpha = 1;
}

// Heat shimmer: a wobble applied to horizontal slices of the backdrop, NOT particles. On a stage
// whose hazard is a rising column of steam, anything rising has to mean the vent.
function heat(b, A, t, stage) {
  const m = stage.main;
  const bl = stage.blast;
  for (let i = 0; i < 16; i++) {
    const y = m.top + 1 + i * 1.7;
    const wob = Math.sin(t * 1.7 + i * 0.9) * 0.5 + Math.sin(t * 2.9 + i * 2.1) * 0.25;
    b.globalAlpha = 0.13 * A.shimmer * (1 - i / 16);
    b.fillStyle = A.tint;
    b.fillRect(bl.left + wob, y, bl.right - bl.left, 1.1);
  }
  // a glow sitting over the pour, low and wide
  b.globalAlpha = 0.06;
  b.fillStyle = A.tint;
  b.beginPath(); b.ellipse(0, m.top - 6, m.w * 0.6, 9, 0, 0, TAU); b.fill();
  b.globalAlpha = 1;
}

// Foundry ash: cold flakes settling DOWNWARD, grey, slow.
//
// This replaced a rising-orange-ember ambient, which was a straight violation of the rule at the
// top of this file. Foundry Floor's hazard is `emberdrift` — two columns of rising orange sparks
// — and the ambient was rising orange sparks in the same colour family, on the same layer, spread
// across the full width of the stage, which necessarily includes the hazard's own columns. A
// player at the edge could not tell the harmless sparks from the ones that lift them.
//
// The fix is not a tint tweak. Ash differs from the hazard on the two channels the eye reads
// fastest: DIRECTION (down, not up) and VALUE (cold grey, not hot orange). Two things moving
// opposite ways in opposite colours are never confused, at any size.
function ash(b, A, t, stage) {
  const bl = stage.blast;
  const n = Math.round(30 * A.rate);
  for (let i = 0; i < n; i++) {
    const h1 = hash(i * 29), h2 = hash(i * 29 + 77);
    const fall = ((t * (0.06 + h2 * 0.06) + h1) % 1);
    // a lazy side-to-side drift, so it settles rather than drops
    const x = bl.left + h1 * (bl.right - bl.left) + Math.sin(fall * 7 + h1 * 9) * A.drift;
    const y = bl.top - fall * (bl.top - bl.bottom);
    b.globalAlpha = Math.sin(fall * PI) * (0.10 + h2 * 0.16);
    b.fillStyle = A.tint;
    const sz = 0.16 + h2 * 0.18;
    b.fillRect(x, y, sz, sz * 0.6);
  }
  b.globalAlpha = 1;
}

// Sea spray: fine mist drifting off the water, kept below the fighting line.
function spray(b, A, t, stage) {
  const bl = stage.blast;
  const lvl = stage.waterLevel != null ? stage.waterLevel : 0;
  const n = Math.round(30 * A.rate);
  for (let i = 0; i < n; i++) {
    const h1 = hash(i * 37), h2 = hash(i * 37 + 211);
    const k = ((t * (0.3 + h2 * 0.3) + h1) % 1);
    const x = bl.left + h1 * (bl.right - bl.left) + k * (A.wind || 0);
    const y = lvl + k * 9;
    b.globalAlpha = Math.sin(k * PI) * 0.35;
    b.fillStyle = A.tint;
    b.fillRect(x, y, 0.6 + h2 * 0.9, 0.26);
  }
  b.globalAlpha = 1;
}

// Gulls over the bridge: a handful of silhouettes crossing very high up on long loops, with a
// two-segment wing that flaps. Pure scenery, and the only ambient with a recognisable shape —
// The Span has the emptiest sky in the game and needed something in it.
function gulls(b, A, t, stage) {
  const bl = stage.blast;
  const n = Math.max(2, Math.round(7 * A.rate * 8));
  for (let i = 0; i < n; i++) {
    const h1 = hash(i * 83), h2 = hash(i * 83 + 19);
    const dir = h2 > 0.5 ? 1 : -1;
    const run = ((t * (0.035 + h1 * 0.03) + h1) % 1);
    const x = dir > 0 ? bl.left + run * (bl.right - bl.left) : bl.right - run * (bl.right - bl.left);
    const y = stage.main.top + 34 + h1 * (bl.top - stage.main.top - 40);
    const flap = Math.sin(t * (5 + h2 * 3) + i) * 0.6;
    const s = 0.8 + h2 * 0.7;
    b.globalAlpha = 0.22 + h1 * 0.16;
    b.strokeStyle = A.tint; b.lineWidth = 0.18;
    b.beginPath();
    b.moveTo(x - s, y + flap * s * 0.5);
    b.lineTo(x, y);
    b.lineTo(x + s, y + flap * s * 0.5);
    b.stroke();
  }
  b.globalAlpha = 1;
}

const KINDS = { rain, sand, heat, ash, spray, gulls };

// `layer` is 'back' (behind the stage body, before fighters) or 'front' (over everything).
// Weather that falls toward the camera goes in front; weather that lives in the distance goes
// behind, so the stage always sits between the two and reads as solid.
const FRONT = new Set(['rain', 'sand', 'spray', 'ash']);

export function drawAmbient(b, stage, t, layer) {
  const A = stage.data.ambient;
  if (!A) return;
  const fn = KINDS[A.kind];
  if (!fn) return;
  if ((layer === 'front') !== FRONT.has(A.kind)) return;
  fn(b, A, t, stage);
}
