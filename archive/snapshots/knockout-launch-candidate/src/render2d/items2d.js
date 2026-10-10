// ITEM ART
//
// One drawing per item, used everywhere that item appears: lying on the floor, in a fighter's
// hand, and in flight after it is thrown. They used to be one shared 1.2 x 1.0 rectangle in three
// colours - about six pixels at gameplay zoom - which is a large part of why nobody could tell
// what they had picked up.
//
// Local space is the item's own: origin at the item's base, +Y up, one unit = one stud.

const PI = Math.PI;
const TAU = PI * 2;

const poly = (b, pts, fill) => {
  b.beginPath(); b.moveTo(pts[0][0], pts[0][1]);
  for (let i = 1; i < pts.length; i++) b.lineTo(pts[i][0], pts[i][1]);
  b.closePath(); b.fillStyle = fill; b.fill();
};

const ART = {
  // A banded iron keg with a fuse. The fuse is the read: it shortens and sparks as the fuse
  // burns, so how long you have is on the object rather than in a HUD.
  BlastKeg(b, d, t, fuse) {
    poly(b, [[-0.62, 0], [0.62, 0], [0.72, 0.55], [0.62, 1.1], [-0.62, 1.1], [-0.72, 0.55]], d.colour);
    b.fillStyle = 'rgba(0,0,0,0.30)';
    b.fillRect(-0.72, 0.20, 1.44, 0.12); b.fillRect(-0.72, 0.80, 1.44, 0.12);
    b.fillStyle = d.accent;
    b.fillRect(-0.34, 0.42, 0.68, 0.28);                                  // the plate
    if (fuse != null) {
      const k = Math.max(0, Math.min(1, fuse));
      b.strokeStyle = '#C9B489'; b.lineWidth = 0.10;
      b.beginPath(); b.moveTo(0, 1.1); b.lineTo(0.1, 1.1 + 0.42 * k); b.stroke();
      b.fillStyle = k > 0.35 ? '#FFD37A' : '#FF6A3C';
      const r = 0.13 + Math.sin(t * 30) * 0.04 * (1 - k);
      b.beginPath(); b.arc(0.1, 1.1 + 0.42 * k, r, 0, TAU); b.fill();
    }
  },

  // A stubby industrial nailer: body, grip, and a magazine that empties as it is used.
  RivetGun(b, d, t, _f, uses) {
    poly(b, [[-0.55, 0.42], [0.62, 0.42], [0.62, 0.86], [-0.55, 0.86]], d.colour);
    poly(b, [[0.55, 0.52], [1.02, 0.52], [1.02, 0.74], [0.55, 0.74]], '#3A4250');   // barrel
    poly(b, [[-0.38, 0], [-0.02, 0], [0.06, 0.44], [-0.30, 0.44]], '#3A4250');      // grip
    b.fillStyle = d.accent;
    const n = uses == null ? 1 : Math.max(0, Math.min(1, uses / 8));
    b.fillRect(-0.48, 0.88, 0.84 * n, 0.16);                                        // the magazine
    b.fillStyle = 'rgba(255,255,255,0.22)';
    b.fillRect(-0.55, 0.78, 1.17, 0.08);
  },

  // A riveted slab with a viewing slit and a grip behind it. Drawn face-on, because that is the
  // side that matters.
  Bulwark(b, d, t, _f, _u, hp) {
    poly(b, [[-0.72, 0], [0.72, 0], [0.86, 1.2], [0.72, 2.3], [-0.72, 2.3], [-0.86, 1.2]], d.colour);
    b.fillStyle = 'rgba(0,0,0,0.28)';
    b.fillRect(-0.86, 1.52, 1.72, 0.26);                                            // the slit
    b.fillStyle = d.accent;
    for (let i = 0; i < 5; i++) { b.fillRect(-0.6 + i * 0.3, 0.28, 0.14, 0.14); b.fillRect(-0.6 + i * 0.3, 2.0, 0.14, 0.14); }
    if (hp != null) {                                                               // damage shows
      const k = Math.max(0, Math.min(1, hp));
      b.fillStyle = 'rgba(0,0,0,0.35)';
      b.fillRect(-0.86, 0, 1.72, 2.3 * (1 - k));
    }
  },

  // A sprung floor plate: two coils under a tread.
  SpringPlate(b, d, t, _f, _u, _h, armed) {
    const squash = armed === false ? 0.45 : 1;
    b.fillStyle = '#2E3440';
    b.fillRect(-1.7, 0, 3.4, 0.16);
    b.strokeStyle = d.accent; b.lineWidth = 0.13;
    for (const cx of [-0.85, 0.85]) {
      b.beginPath();
      for (let i = 0; i <= 12; i++) {
        const u = i / 12;
        b.lineTo(cx + Math.sin(u * PI * 4) * 0.26, 0.16 + u * 0.55 * squash);
      }
      b.stroke();
    }
    poly(b, [[-1.7, 0.16 + 0.55 * squash], [1.7, 0.16 + 0.55 * squash], [1.7, 0.16 + 0.9 * squash], [-1.7, 0.16 + 0.9 * squash]], d.colour);
    b.fillStyle = 'rgba(255,255,255,0.25)';
    b.fillRect(-1.7, 0.16 + 0.9 * squash - 0.1, 3.4, 0.1);
  },

  // A dark iron sphere with a field around it. The field is the only bright thing on it, so it
  // reads as a magnet rather than as a rock.
  Lodestone(b, d, t) {
    b.globalAlpha = 0.28; b.fillStyle = d.accent;
    b.beginPath(); b.arc(0, 0.55, 0.86 + Math.sin(t * 5) * 0.08, 0, TAU); b.fill();
    b.globalAlpha = 1;
    b.fillStyle = d.colour;
    b.beginPath(); b.arc(0, 0.55, 0.52, 0, TAU); b.fill();
    b.strokeStyle = d.accent; b.lineWidth = 0.1;
    b.beginPath(); b.arc(0, 0.55, 0.52, -0.6, 0.8); b.stroke();
    b.fillStyle = 'rgba(255,255,255,0.5)';
    b.beginPath(); b.arc(-0.16, 0.72, 0.13, 0, TAU); b.fill();
  },
};

// A rivet in flight: a bright bolt with a short streak. Drawn in world space, not item space.
export function drawRivet(b, x, y, dir, accent) {
  b.globalAlpha = 0.4; b.fillStyle = accent || '#FFD37A';
  b.fillRect(x - dir * 1.3, y - 0.06, 1.3, 0.12);
  b.globalAlpha = 1;
  b.fillStyle = '#FFF3D0';
  b.fillRect(x - 0.22, y - 0.11, 0.44, 0.22);
}

// Draw an item at a world position. `opts` carries the live state the art reads: fuse fraction,
// uses left, shield hit points, whether a plate is compressed.
export function drawItem(b, def, x, y, t, opts = {}) {
  const art = ART[def.id];
  if (!art) { b.fillStyle = def.colour || '#FFFFFF'; b.fillRect(x - 0.6, y, 1.2, 1.0); return; }
  b.save();
  b.translate(x, y);
  if (opts.scale && opts.scale !== 1) b.scale(opts.scale, opts.scale);
  if (opts.spin) b.rotate(opts.spin);
  // A contour, the same trick the weapons use: at gameplay zoom an item is a dozen pixels against
  // a stage of the same value, and without one it is invisible the moment it stops moving.
  b.save(); b.translate(-0.1, -0.1);
  const dark = new Proxy({}, { get: () => 'rgba(20,16,24,0.55)' });
  art(b, dark, t, opts.fuse, opts.uses, opts.hp, opts.armed);
  b.restore();
  art(b, def, t, opts.fuse, opts.uses, opts.hp, opts.armed);
  b.restore();
}

export const ITEM_ART_IDS = Object.keys(ART);
