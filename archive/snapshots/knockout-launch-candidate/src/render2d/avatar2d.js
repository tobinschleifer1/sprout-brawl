// The character itself: head shape, face, headgear and the mark on the chest.
//
// These four choices are everything a player-made character owns beyond its five colours, and they
// all live here rather than inside renderer2d's `_fighter` for one reason: the character creator's
// preview has to be the SAME drawing as the match, and the only way to guarantee that is for there
// to be one drawing. The creator renders through Renderer2D.drawFighterInto, which calls straight
// into this file.
//
// Local space is the head's own: +Y up, one unit = one stud, origin at the neck joint. Every shape
// reports the box it occupied so the face and the hat can sit on it without knowing which head
// shape was picked.

const PI = Math.PI;
const TAU = PI * 2;
const EYE = '#1B1526';

// ------------------------------------------------------------------------------- heads -----
// Each returns { x0, y0, w, h } - the drawn box, in head-scale units.

const HEADS = {
  block(b, hs) { b.fillRect(-hs / 2, -hs * 0.15, hs, hs); return { x0: -hs / 2, y0: -hs * 0.15, w: hs, h: hs }; },
  round(b, hs) {
    b.beginPath(); b.arc(0, hs * 0.35, hs * 0.52, 0, TAU); b.fill();
    return { x0: -hs * 0.52, y0: hs * 0.35 - hs * 0.52, w: hs * 1.04, h: hs * 1.04 };
  },
  tall(b, hs) { b.fillRect(-hs * 0.38, -hs * 0.15, hs * 0.76, hs * 1.24); return { x0: -hs * 0.38, y0: -hs * 0.15, w: hs * 0.76, h: hs * 1.24 }; },
  wide(b, hs) { b.fillRect(-hs * 0.64, -hs * 0.06, hs * 1.28, hs * 0.82); return { x0: -hs * 0.64, y0: -hs * 0.06, w: hs * 1.28, h: hs * 0.82 }; },
};

// -------------------------------------------------------------------------------- faces -----
// Drawn forward of centre, because every fighter in this game is seen from the side and faces +X.

const FACES = {
  dot(b, p, k) { b.fillStyle = EYE; b.fillRect(k.x0 + k.w * 0.52, k.y0 + k.h * 0.52, k.w * 0.20, k.h * 0.20); },
  pair(b, p, k) {
    b.fillStyle = EYE;
    b.fillRect(k.x0 + k.w * 0.56, k.y0 + k.h * 0.54, k.w * 0.16, k.h * 0.18);
    b.fillRect(k.x0 + k.w * 0.28, k.y0 + k.h * 0.54, k.w * 0.13, k.h * 0.16);
  },
  visor(b, p, k) {
    b.fillStyle = EYE; b.fillRect(k.x0 + k.w * 0.10, k.y0 + k.h * 0.46, k.w * 0.86, k.h * 0.26);
    b.fillStyle = p.glow || p.accent; b.fillRect(k.x0 + k.w * 0.14, k.y0 + k.h * 0.52, k.w * 0.78, k.h * 0.12);
  },
  shades(b, p, k) {
    b.fillStyle = EYE;
    b.fillRect(k.x0 + k.w * 0.44, k.y0 + k.h * 0.48, k.w * 0.34, k.h * 0.22);
    b.fillRect(k.x0 + k.w * 0.14, k.y0 + k.h * 0.48, k.w * 0.24, k.h * 0.20);
    b.fillRect(k.x0 + k.w * 0.36, k.y0 + k.h * 0.58, k.w * 0.10, k.h * 0.06);   // the bridge
  },
  goggles(b, p, k) {
    b.fillStyle = p.tertiary; b.fillRect(k.x0, k.y0 + k.h * 0.50, k.w, k.h * 0.16);   // the strap
    b.fillStyle = p.accent;
    b.beginPath(); b.arc(k.x0 + k.w * 0.62, k.y0 + k.h * 0.58, k.w * 0.17, 0, TAU); b.fill();
    b.beginPath(); b.arc(k.x0 + k.w * 0.28, k.y0 + k.h * 0.58, k.w * 0.14, 0, TAU); b.fill();
    b.fillStyle = EYE;
    b.beginPath(); b.arc(k.x0 + k.w * 0.62, k.y0 + k.h * 0.58, k.w * 0.10, 0, TAU); b.fill();
    b.beginPath(); b.arc(k.x0 + k.w * 0.28, k.y0 + k.h * 0.58, k.w * 0.08, 0, TAU); b.fill();
  },
  blank() {},
};

// ------------------------------------------------------------------------------- hats -----

const HATS = {
  none() {},
  cap(b, p, k) {
    b.fillStyle = p.secondary;
    b.fillRect(k.x0 + k.w * 0.06, k.y0 + k.h * 0.80, k.w * 0.88, k.h * 0.26);      // the dome
    b.fillRect(k.x0 + k.w * 0.55, k.y0 + k.h * 0.74, k.w * 0.62, k.h * 0.10);      // the brim, forward
    b.fillStyle = p.accent;
    b.fillRect(k.x0 + k.w * 0.06, k.y0 + k.h * 0.98, k.w * 0.88, k.h * 0.06);
  },
  horns(b, p, k) {
    b.fillStyle = p.accent;
    for (const dir of [-1, 1]) {
      const x = k.x0 + k.w * (dir < 0 ? 0.18 : 0.82);
      b.beginPath();
      b.moveTo(x - k.w * 0.09, k.y0 + k.h * 0.86);
      b.lineTo(x + dir * k.w * 0.22, k.y0 + k.h * 1.30);
      b.lineTo(x + k.w * 0.09, k.y0 + k.h * 0.86);
      b.closePath(); b.fill();
    }
  },
  crown(b, p, k) {
    b.fillStyle = p.glow || p.accent;
    b.beginPath();
    b.moveTo(k.x0 + k.w * 0.08, k.y0 + k.h * 0.86);
    for (let i = 0; i < 4; i++) {
      const u = k.x0 + k.w * (0.08 + (i + 0.5) * 0.21);
      b.lineTo(u, k.y0 + k.h * 1.24);
      b.lineTo(u + k.w * 0.105, k.y0 + k.h * 0.94);
    }
    b.lineTo(k.x0 + k.w * 0.92, k.y0 + k.h * 0.86);
    b.closePath(); b.fill();
  },
  antenna(b, p, k) {
    b.fillStyle = p.tertiary;
    b.fillRect(k.x0 + k.w * 0.46, k.y0 + k.h * 0.84, k.w * 0.08, k.h * 0.42);
    b.fillStyle = p.glow || p.accent;
    b.beginPath(); b.arc(k.x0 + k.w * 0.50, k.y0 + k.h * 1.32, k.w * 0.13, 0, TAU); b.fill();
  },
  hood(b, p, k) {
    // Drawn OVER the head, open toward the front, so the face still reads.
    b.fillStyle = p.secondary;
    b.beginPath();
    b.moveTo(k.x0 - k.w * 0.10, k.y0 + k.h * 0.16);
    b.lineTo(k.x0 - k.w * 0.10, k.y0 + k.h * 0.86);
    b.quadraticCurveTo(k.x0 + k.w * 0.30, k.y0 + k.h * 1.30, k.x0 + k.w * 0.92, k.y0 + k.h * 1.02);
    b.lineTo(k.x0 + k.w * 0.62, k.y0 + k.h * 0.84);
    b.lineTo(k.x0 + k.w * 0.30, k.y0 + k.h * 0.84);
    b.lineTo(k.x0 + k.w * 0.30, k.y0 + k.h * 0.16);
    b.closePath(); b.fill();
  },
};

// ------------------------------------------------------------------------------ torso -----
// x runs -r*0.8 .. r*0.8, y runs 0 (hip) .. len (shoulder).

const TORSOS = {
  belt(b, p, r, len) { b.fillStyle = p.accent; b.fillRect(-r * 0.80, len * 0.42, r * 1.60, len * 0.22); },
  sash(b, p, r, len) {
    b.fillStyle = p.accent;
    b.beginPath();
    b.moveTo(-r * 0.80, len * 0.18); b.lineTo(r * 0.80, len * 0.72);
    b.lineTo(r * 0.80, len * 0.94); b.lineTo(-r * 0.80, len * 0.40);
    b.closePath(); b.fill();
  },
  emblem(b, p, r, len) {
    b.fillStyle = p.accent;
    b.beginPath();
    b.moveTo(0, len * 0.78); b.lineTo(r * 0.52, len * 0.54); b.lineTo(0, len * 0.30); b.lineTo(-r * 0.52, len * 0.54);
    b.closePath(); b.fill();
    b.fillStyle = p.glow || p.accent;
    b.beginPath();
    b.moveTo(0, len * 0.68); b.lineTo(r * 0.26, len * 0.54); b.lineTo(0, len * 0.40); b.lineTo(-r * 0.26, len * 0.54);
    b.closePath(); b.fill();
  },
  plain() {},
};

export const HEAD_IDS = Object.keys(HEADS);
export const FACE_IDS = Object.keys(FACES);
export const HAT_IDS = Object.keys(HATS);
export const TORSO_IDS = Object.keys(TORSOS);

// Head, face and hat, in that order: the hat is allowed to sit over the skull, the face is not
// allowed to sit over the hat.
export function drawHead(b, pal, hs, feat) {
  b.fillStyle = pal.primary;
  const box = (HEADS[feat.head] || HEADS.block)(b, hs);
  (FACES[feat.face] || FACES.dot)(b, pal, box);
  (HATS[feat.hat] || HATS.none)(b, pal, box);
  return box;
}

export function drawTorsoMark(b, pal, r, len, feat) {
  (TORSOS[feat.torso] || TORSOS.belt)(b, pal, r, len);
}
