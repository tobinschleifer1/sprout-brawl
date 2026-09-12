// The 2D renderer.
//
// Everything is drawn into a small fixed backbuffer and blown up with nearest-neighbour sampling,
// which is what makes it read as pixel art rather than as smooth vector shapes at any resolution.
// All drawing happens in WORLD units (studs, y-up); one transform at the top of the frame maps
// world to backbuffer pixels, so nothing downstream has to think about the camera.
//
// It replaces render/scene.js, render/stageview.js, render/effects.js and render/rigs.js in one
// object, because in 2D there is no scene graph to keep in sync - each frame is painted from
// scratch out of the simulation state.

import { channelsFor } from './channels.js';
import { weaponPose, drawWeapon, drawTrail, drawMuzzle, drawUltimate, REACH } from './weapons2d.js';
import { drawHazards } from './hazards2d.js';
import { drawAmbient } from './ambient2d.js';

const PI = Math.PI;
const BH = 270;                       // backbuffer HEIGHT is fixed, so one world pixel is always
                                      // the same size; the width follows the window's aspect.
const BW_MIN = 320, BW_MAX = 900;

const lerp = (a, b, k) => a + (b - a) * k;
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

export const PLAYER_TINT = ['#5FBF4B', '#E8862E', '#4A90D9', '#9A6BD6'];

export class Renderer2D {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.buf = document.createElement('canvas');
    this.BW = 480; this.BH = BH;
    this.buf.width = this.BW; this.buf.height = BH;
    this.b = this.buf.getContext('2d');
    this.cam = { x: 0, y: 12, ppu: 5, tx: 0, ty: 12, tppu: 5 };
    this.shake = 0;
    this.debug = false;
    this.stage = null;
    this.parts = [];                  // transient particles
    this.slashes = [];                // impact flashes from signatures
    this.time = 0;
    this.resize();
  }

  resize() {
    const r = this.canvas.getBoundingClientRect();
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    this.canvas.width = Math.max(1, Math.round(r.width * dpr));
    this.canvas.height = Math.max(1, Math.round(r.height * dpr));
    const aspect = r.height > 0 ? r.width / r.height : 16 / 9;
    const bw = clamp(Math.round((BH * aspect) / 2) * 2, BW_MIN, BW_MAX);
    if (bw !== this.BW) { this.BW = bw; this.buf.width = bw; }
    this.ctx.imageSmoothingEnabled = false;
  }

  setStage(stage) { this.stage = stage; this.parts.length = 0; this.slashes.length = 0; }

  // World point -> CSS pixels on the display canvas, for HUD markers that track a fighter.
  project(x, y) {
    const c = this.cam;
    const r = this.canvas.getBoundingClientRect();
    const k = Math.max(r.width / this.BW, r.height / BH);
    const ox = (r.width - this.BW * k) / 2, oy = (r.height - BH * k) / 2;
    return { x: ox + (this.BW / 2 + (x - c.x) * c.ppu) * k, y: oy + (BH / 2 - (y - c.y) * c.ppu) * k };
  }
  setFighters() { /* nothing to build: fighters are painted from state every frame */ }
  clear() { this.parts.length = 0; this.slashes.length = 0; }
  dispose() { this.stage = null; this.clear(); }

  // ---------------------------------------------------------------------- camera ----
  _camera(fighters, dt, instant) {
    const alive = fighters.filter((f) => f.alive);
    const src = alive.length ? alive : fighters;
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    for (const f of src) { x0 = Math.min(x0, f.x); x1 = Math.max(x1, f.x); y0 = Math.min(y0, f.y); y1 = Math.max(y1, f.y + f.h); }
    if (!isFinite(x0)) { x0 = x1 = 0; y0 = 0; y1 = 10; }
    const pad = 20;
    const w = Math.max(42, x1 - x0 + pad * 2);
    const hgt = Math.max(28, y1 - y0 + pad);
    // Capped at both ends: too far in and the stage vanishes, too far out and the fighters do.
    const ppu = clamp(Math.min(this.BW / w, BH / hgt), 2.4, 7.2);
    this.cam.tx = (x0 + x1) / 2;
    this.cam.ty = (y0 + y1) / 2 + 2;
    this.cam.tppu = ppu;
    const k = instant ? 1 : 1 - Math.pow(0.0025, dt);
    this.cam.x = lerp(this.cam.x, this.cam.tx, k);
    this.cam.y = lerp(this.cam.y, this.cam.ty, k);
    this.cam.ppu = lerp(this.cam.ppu, this.cam.tppu, k);
  }

  _world() {
    const b = this.b, c = this.cam;
    const sx = this.shake > 0 ? (Math.random() - 0.5) * this.shake * 2 : 0;
    const sy = this.shake > 0 ? (Math.random() - 0.5) * this.shake * 2 : 0;
    b.setTransform(c.ppu, 0, 0, -c.ppu, this.BW / 2 - c.x * c.ppu + sx, BH / 2 + c.y * c.ppu + sy);
  }
  _screen() { this.b.setTransform(1, 0, 0, 1, 0, 0); }

  // ---------------------------------------------------------------------- frame ----
  frame(match, dt, t, instant) {
    this.time = t;
    const fighters = match.fighters;
    this._camera(fighters, dt, instant);
    if (this.shake > 0) this.shake = Math.max(0, this.shake - dt * 9);

    this._sky(match.stage);
    this._world();
    this._backdrop(match.stage);
    this._stage(match.stage);
    // Distant weather and the hazards a fighter stands IN FRONT of (water, wind, embers).
    drawAmbient(this.b, match.stage, t, 'back');
    drawHazards(this.b, match.stage, t, 'back');
    this._summons(match.combat);
    this._orbMarks(match);
    this._items(match.combat);
    for (const f of fighters) this._fighter(f, t);
    // Hazards a fighter is INSIDE — steam, dust, water jets — draw over them, so the fighter is
    // swallowed by the column rather than pasted on top of it.
    drawHazards(this.b, match.stage, t, 'front');
    this._projectiles(match.combat);
    this._bursts(match.combat);
    this._particles(dt);
    drawAmbient(this.b, match.stage, t, 'front');
    for (const f of fighters) if (f.ultActive && f.alive) this._ultWorld(f, t);
    // Every caster gets a ring - `break` here meant that when two players activated on the same
    // frame only one of them was marked. The screen wash is still drawn once, from the first.
    let washed = false;
    for (const f of fighters) if (f.ultActive && f.alive) { this._ultAura(f, t, !washed); washed = true; }
    this._ultBanner(dt);
    if (this.debug) this._debug(match);
    this._screen();
    this._present();
  }

  // Draw a single fighter into an arbitrary canvas context at a given scale and screen position,
  // using the same pose and paint path the match uses.
  //
  // This exists because anim.html — the filmstrip the animation work is judged from — used to draw
  // its own hard-coded grey rectangles for the body and its own hand-rolled transform for the
  // weapon. It agreed with the game on nothing, which meant the page used to review the animation
  // was showing a different animation. A tool that does not share the renderer is a tool that
  // lies eventually.
  drawFighterInto(ctx, f, t, { ppu = 15, x = 0, y = 0 } = {}) {
    ctx.save();
    // same handedness as the match: +Y up, origin at the fighter's feet
    ctx.setTransform(ppu, 0, 0, -ppu, x, y);
    this._fighter(f, t, ctx);
    ctx.restore();
  }

  _present() {
    const cw = this.canvas.width, chh = this.canvas.height;
    const k = Math.max(cw / this.BW, chh / BH);
    const w = this.BW * k, h = BH * k;
    this.ctx.imageSmoothingEnabled = false;
    this.ctx.clearRect(0, 0, cw, chh);
    this.ctx.drawImage(this.buf, (cw - w) / 2, (chh - h) / 2, w, h);
  }

  // ---------------------------------------------------------------------- stage ----
  _sky(stage) {
    const b = this.b;
    this._screen();
    const p = stage.data.palette;
    const g = b.createLinearGradient(0, 0, 0, BH);
    const stops = p.skyStops || [[0, p.sky || '#BFE3E8'], [1, p.backdrop || '#EAF7F2']];
    for (const [o, col] of stops) g.addColorStop(clamp(o, 0, 1), col);
    b.fillStyle = g;
    b.fillRect(0, 0, this.BW, BH);
  }

  // Parallax hills: three bands that slide against the camera, which is most of what sells depth
  // in a 2D fighter without any actual depth.
  _backdrop(stage) {
    const b = this.b, c = this.cam, p = stage.data.palette;
    const left = c.x - this.BW / (2 * c.ppu) - 30, right = c.x + this.BW / (2 * c.ppu) + 30;
    const bands = [
      [0.10, 15, 5, p.backdrop || '#BFE3E8', 0.60],
      [0.22, 10, -2, p.accent || '#3E8F35', 0.28],
      [0.38, 6, -9, p.ground || '#6B4A2C', 0.20],
    ];
    for (const [par, amp, base, col, alpha] of bands) {
      b.globalAlpha = alpha;
      b.fillStyle = col;
      b.beginPath();
      b.moveTo(left, -90);
      for (let x = left; x <= right; x += 3) {
        const u = (x - c.x * par) * 0.030;
        b.lineTo(x, base + Math.sin(u) * amp * 0.5 + Math.sin(u * 0.41 + 2.1) * amp * 0.5);
      }
      b.lineTo(right, -90);
      b.closePath();
      b.fill();
    }
    b.globalAlpha = 1;
  }

  _stage(stage) {
    const b = this.b, p = stage.data.palette, m = stage.main;

    // Solids first: a body that runs off the bottom of the screen, a bright cap, and a lip on each
    // edge so you can see exactly where the ledge is - which is information the player needs.
    for (const sp of stage.solids) {
      const depth = sp === stage.main ? 60 : Math.max(sp.thickness, 6);
      b.fillStyle = p.ground || '#6B4A2C';
      b.fillRect(sp.x1, sp.top - depth, sp.x2 - sp.x1, depth);
      b.fillStyle = 'rgba(0,0,0,0.16)';                                  // shaded underside
      b.fillRect(sp.x1, sp.top - depth, sp.x2 - sp.x1, Math.min(depth, 1.2));
      b.fillStyle = p.groundTop || '#5FBF4B';
      b.fillRect(sp.x1, sp.top - 1.2, sp.x2 - sp.x1, 1.2);
      b.fillStyle = 'rgba(255,255,255,0.16)';                            // lit top edge
      b.fillRect(sp.x1, sp.top - 0.35, sp.x2 - sp.x1, 0.35);
      if (sp.ledges !== false) {                                         // grabbable corners
        b.fillStyle = p.accent || '#3E8F35';
        b.fillRect(sp.x1, sp.top - 2.0, 0.7, 2.0);
        b.fillRect(sp.x2 - 0.7, sp.top - 2.0, 0.7, 2.0);
      }
    }

    // Then the drop-through shelves, drawn thinner and lighter so they read as pass-through.
    for (const pl of stage.platforms) {
      if (pl.solid) continue;
      const th = pl.thickness || 1;
      b.fillStyle = p.platform || '#B8894A';
      b.fillRect(pl.x1, pl.top - th, pl.x2 - pl.x1, th);
      b.fillStyle = p.groundTop || '#5FBF4B';
      b.fillRect(pl.x1, pl.top - 0.4, pl.x2 - pl.x1, 0.4);
      b.fillStyle = 'rgba(255,255,255,0.20)';
      b.fillRect(pl.x1, pl.top - 0.15, pl.x2 - pl.x1, 0.15);
      if (pl.sinking) {                                                  // tell the player it sinks
        b.fillStyle = 'rgba(0,0,0,0.28)';
        for (let x = pl.x1 + 1; x < pl.x2 - 1; x += 3) b.fillRect(x, pl.top - th - 0.5, 1.2, 0.4);
      }
    }

  }

  // ---------------------------------------------------------------------- fighter ----
  // Draw one fighter, in world space, into `target` (defaults to the backbuffer). The target is a
  // parameter so tools can draw a real fighter with the real code — see drawFighterInto below.
  _fighter(f, t, target) {
    if (!f.alive || f.state === 'ko') return;
    const b = target || this.b;
    const ch = channelsFor(f, t);
    if (!ch.visible) return;

    const h = f.char.height, r = f.char.radius;
    const pal = f.char.palette;
    const wpal = f.char.weaponPalette || pal;
    const wid = f.char.weapon ? f.char.weapon.id : null;
    const wp = weaponPose(f, t);

    // Smear: two ghosts of the body trailing the direction of travel, drawn before the fighter.
    // Hand-drawn fighting games solve fast motion with smear frames — a limb drawn as a streak
    // across the distance it covered — because at 60Hz a genuinely fast move is between frames
    // more than it is on them. The channel bag asks for it; without this it was being computed
    // and thrown away.
    if (ch.smear > 0.02 && ch.visible) {
      // Ghosts trail. Standing still this used -facing, which put both of them IN FRONT of the
      // fighter, so the streak led the swing instead of following it.
      const dir = Math.abs(f.vx) > 1 ? Math.sign(f.vx) : f.facing;
      const dist = Math.min(2.6, 0.7 + Math.abs(f.vx) * 0.035) * ch.smear;
      for (let g = 1; g <= 2; g++) {
        b.save();
        b.globalAlpha = ch.opacity * ch.smear * (0.45 / g);
        b.translate(f.x - dir * dist * g * 0.55, f.y + ch.yOff);
        b.scale(f.facing, 1);
        // Rotate about the body's centre, not its feet. Pivoting at the origin swung the whole
    // drawing out of its own hurtbox: a tech roll at frame 6 spanned y -4.5..0.3, a full body
    // height below the floor, and an air dodge's centre swung 4.5 studs across. `rotPivot` is the
    // fraction of height to pivot at, so knockdown can keep its deliberate feet-pivot.
    if (ch.rigRotZ) {
      const pv = h * (ch.rotPivot ?? 0.5);
      b.translate(0, pv); b.rotate(ch.rigRotZ * f.facing); b.translate(0, -pv);
    }
        b.fillStyle = pal.primary;
        b.fillRect(-r * 0.82, h * 0.06, r * 1.64, h * 0.72);
        b.restore();
      }
      b.globalAlpha = 1;
    }

    b.save();
    b.translate(f.x + ch.shakeX, f.y + ch.yOff);
    b.scale(f.facing, 1);                       // one drawing, both facings
    b.rotate(ch.rigRotZ * f.facing);
    b.globalAlpha = ch.opacity;

    // ground shadow
    if (f.platform) {
      b.globalAlpha = ch.opacity * 0.22;
      b.fillStyle = '#000000';
      const d = clamp(1 - (f.y - f.platform.top) / 14, 0.25, 1);
      b.beginPath(); b.ellipse(0, f.platform.top - f.y + 0.1, r * 1.25 * d, 0.45 * d, 0, 0, PI * 2); b.fill();
      b.globalAlpha = ch.opacity;
    }

    const HIP = h * 0.34, SHO = h * 0.70, HEAD = h * 0.78;
    const lw = r * 0.42, ll = HIP;
    b.save();
    b.translate(0, ch.bob);

    // legs
    b.fillStyle = pal.tertiary;
    for (const [rot, dx] of [[ch.legL, -r * 0.30], [ch.legR, r * 0.30]]) {
      b.save(); b.translate(dx, HIP); b.rotate(-rot);
      b.fillRect(-lw / 2, -ll, lw, ll);
      b.fillStyle = pal.tertiary;
      b.restore();
    }

    // body, leaning
    b.save();
    b.translate(0, HIP);
    b.rotate(-ch.lean);
    b.scale(ch.sx, ch.sy);

    // back arm
    this._arm(b, pal.secondary, r, SHO - HIP, ch.armL, h);

    // torso
    b.fillStyle = pal.secondary;
    b.fillRect(-r * 0.80, 0, r * 1.60, SHO - HIP);
    b.fillStyle = pal.accent;
    b.fillRect(-r * 0.80, (SHO - HIP) * 0.42, r * 1.60, (SHO - HIP) * 0.22);

    // head
    b.fillStyle = pal.primary;
    const hs = r * 1.15;
    b.save(); b.translate(0, HEAD - HIP); b.rotate(-ch.head * 0.4);
    b.fillRect(-hs / 2, -hs * 0.15, hs, hs);
    b.fillStyle = '#1B1526';
    b.fillRect(hs * 0.06, hs * 0.34, hs * 0.20, hs * 0.20);           // eye
    b.restore();

    // front arm: driven by the weapon, so the swing and the limb always agree
    const armAng = wid ? wp.angle : ch.armR.z - PI / 2;
    this._arm(b, pal.primary, r, SHO - HIP, { z: armAng + PI / 2, x: ch.armR.x }, h, true);

    // weapon, at the hand
    if (wid && !wp.hide) {
      const AL = h * 0.30;
      const hx = r * 0.55 + Math.cos(armAng) * AL;
      const hy = (SHO - HIP) + Math.sin(armAng) * AL;
      // trail is drawn from the shoulder so the arc sweeps around the body
      if (wp.trail) { b.save(); b.translate(r * 0.55, SHO - HIP); drawTrail(b, wid, wpal, wp.trail, wp.scale || 1); b.restore(); }
      // A dragged weapon scrapes. The head's world position is the hand plus the weapon's own
      // reach along its angle, so the dirt comes off exactly where the axe meets the floor rather
      // than from under the fighter — which is the difference between "heavy" and "dusty".
      if (wp.drag && f.platform) {
        const rch = (REACH[wid] || 2.4);
        const headLocal = { x: hx + Math.cos(wp.angle) * rch, y: hy + Math.sin(wp.angle) * rch };
        const wx = f.x + headLocal.x * f.facing, wy = f.y + HIP + headLocal.y;
        const floor = f.platform.top;
        if (wy < floor + 1.2) {
          b.globalAlpha = 0.5;
          b.fillStyle = pal.tertiary;
          b.fillRect(wx - 0.5, floor, 1.0, 0.22);          // the scuff under the head
          b.globalAlpha = 1;
          // grit kicked backwards, more of it the faster you are hauling
          const rate = 0.25 + wp.drag.scrape * 0.75;
          if (Math.random() < rate) {
            this.parts.push({ x: wx, y: floor + 0.1,
              vx: -f.facing * (2 + Math.random() * 7) - f.vx * 0.12,
              vy: 1 + Math.random() * 5,
              life: 0.3 + Math.random() * 0.3, max: 0.6,
              c: Math.random() < 0.5 ? pal.tertiary : '#6B5A44', s: 0.16 + Math.random() * 0.18 });
          }
        }
      }

      b.save(); b.translate(hx, hy);
      drawUltimate(b, wid, wpal, wp, t);        // afterimages / moon / second pistol / rune stack
      drawWeapon(b, wid, wpal, wp);
      drawMuzzle(b, wid, wpal, wp, t);
      b.restore();
    }

    b.restore();  // body
    b.restore();  // bob
    b.restore();  // fighter

    // shield bubble
    if (ch.bubble > 0) {
      b.globalAlpha = 0.30 + ch.bubble * 0.25;
      b.fillStyle = '#9FD1E8';
      b.beginPath(); b.arc(f.x, f.y + h * 0.5, h * 0.62 * (0.55 + ch.bubble * 0.45), 0, PI * 2); b.fill();
      b.globalAlpha = 1;
    }
    // hit flash
    if (ch.tint) {
      b.globalAlpha = 0.5;
      b.fillStyle = ch.tint;
      b.fillRect(f.x - r, f.y, r * 2, h);
      b.globalAlpha = 1;
    }
    b.globalAlpha = 1;
  }

  _arm(b, colour, r, len, a, h, front = false) {
    const w = r * 0.34, L = h * 0.30;
    b.save();
    b.translate(front ? r * 0.55 : -r * 0.35, len);
    // Arm channels are "direction the limb points, +X forward, +Y up", the same convention the
    // weapon uses. The limb is drawn along local -Y, so pointing it at angle A needs rotate(A +
    // PI/2) — which is exactly what `a.z` already holds. The old `-(a.z - PI/2)` mirrored it, so
    // the arm and the weapon sat a permanent 90 degrees apart and the prop floated up to 3 studs
    // from the hand. It also inverted every channel-driven arm: a ledge hang (armL.z 2.9, meant to
    // be overhead) drew pointing backwards and down.
    // `a.x` is the across-the-body component: the run writes its whole arm swing into it and
    // nothing read it, so the front arm sat at a constant angle and the run had no arm animation
    // at all. Folded in as a forward/back bias on the same joint.
    b.rotate(a.z + (a.x || 0));
    b.fillStyle = colour;
    b.fillRect(-w / 2, -L, w, L);
    b.fillRect(-w * 0.7, -L - w * 0.8, w * 1.4, w * 1.1);   // hand
    b.restore();
  }

  // The parts of an ultimate that live in the WORLD rather than on the fighter: the sniper's
  // painted target, the crack the greatsword leaves in the floor, the sky going dark before the
  // orbs come down. These have to be drawn every frame rather than spawned as particles, because
  // they are state the player is meant to read and act on, not decoration.
  _ultWorld(f, t) {
    const b = this.b;
    const m = f.move;
    if (!m) return;
    const pal = f.char.weaponPalette || f.char.palette;

    if (m.kind === 'sniper') {
      const v = f.ultTarget;
      if (v && v.alive) {
        // The mark: a red box around the target, corner brackets, and a sight line that reaches
        // it through anything in between - that is the whole point of the stance.
        const x1 = v.x - v.r - 0.5, x2 = v.x + v.r + 0.5, y1 = v.y - 0.4, y2 = v.y + v.h + 0.5;
        const pulse = 0.55 + 0.45 * Math.sin(t * 11);
        b.globalAlpha = 0.18 * pulse;
        b.fillStyle = '#FF3A3A';
        b.fillRect(x1, y1, x2 - x1, y2 - y1);
        b.globalAlpha = 0.9;
        b.strokeStyle = '#FF4A4A'; b.lineWidth = 0.16;
        const c = 1.1;
        for (const [cx, cy, sx, sy] of [[x1, y1, 1, 1], [x2, y1, -1, 1], [x1, y2, 1, -1], [x2, y2, -1, -1]]) {
          b.beginPath();
          b.moveTo(cx, cy + sy * c); b.lineTo(cx, cy); b.lineTo(cx + sx * c, cy);
          b.stroke();
        }
        b.globalAlpha = 0.30 + 0.25 * pulse;
        b.lineWidth = 0.09;
        b.beginPath(); b.moveTo(f.x + f.facing * 2.6, f.y + 3.5); b.lineTo(v.x, v.cy); b.stroke();
        b.globalAlpha = 1;
      }
      return;
    }

    if (m.kind === 'slam' && f.mf > f.startupEff) {
      // A glowing split in the floor, widening as the shockwave walks outward. The reach is driven
      // off the CRATER's own schedule, not the active window: pacing it over `active` left the
      // outermost burst 8.8 studs ahead of the drawn crack, so players were being hit by floor
      // that had not visibly opened yet.
      const C = m.crater;
      const span = C.every * (C.count - 1);
      const k = Math.min(1, Math.max(0, f.mf - f.startupEff - 1) / Math.max(1, span));
      const y = f.platform ? f.platform.top : f.y;
      const reach = C.step * (C.count - 1) * k;
      b.globalAlpha = 0.55 * (1 - k * 0.5);
      b.fillStyle = pal.glow || '#FFB43C';
      b.fillRect(f.x - reach, y - 0.1, reach * 2, 0.55);
      b.globalAlpha = 0.9 * (1 - k * 0.7);
      b.fillStyle = '#FFFFFF';
      b.fillRect(f.x - reach, y + 0.1, reach * 2, 0.18);
      // rock thrown up along the split
      b.globalAlpha = 1;
      b.fillStyle = '#4A403A';
      for (let i = 1; i < C.count; i++) {
        const d = C.step * i;
        if (d > reach) break;
        const hgt = 1.6 * (1 - i / C.count) + 0.5;
        for (const dir of [-1, 1]) b.fillRect(f.x + dir * d - 0.45, y, 0.9, hgt);
      }
      return;
    }

    if (m.kind === 'starfall') {
      // The sky darkens under the spell and the top of the screen glows where the orbs come from.
      const k = Math.min(1, (f.mf - f.startupEff) / Math.max(1, m.active));
      if (k <= 0) return;
      this._screen();
      const g = this.b.createLinearGradient(0, 0, 0, BH * 0.55);
      g.addColorStop(0, 'rgba(150,90,255,0.42)');
      g.addColorStop(1, 'rgba(150,90,255,0)');
      b.fillStyle = g;
      b.fillRect(0, 0, this.BW, BH * 0.55);
      this._world();
    }
  }

  // A ring of light around whoever is mid-ultimate, plus a wash of their weapon colour over the
  // whole screen. Cheap, but it is what tells everyone else in a four-player match that something
  // different is happening.
  _ultAura(f, t, wash = true) {
    const b = this.b;
    const pal = f.char.weaponPalette || f.char.palette;
    const col = pal.glow || pal.accent || '#FFFFFF';
    const k = 0.5 + 0.5 * Math.sin(t * 9);
    b.globalAlpha = 0.16 + k * 0.10;
    b.strokeStyle = col; b.lineWidth = 0.6;
    b.beginPath(); b.arc(f.x, f.y + f.h * 0.5, f.h * (1.5 + k * 0.35), 0, PI * 2); b.stroke();
    b.globalAlpha = 0.28;
    b.beginPath(); b.arc(f.x, f.y + f.h * 0.5, f.h * 0.95, 0, PI * 2); b.stroke();
    b.globalAlpha = 1;
    if (!wash) return;
    this._screen();
    b.globalAlpha = 0.055 + k * 0.035;
    b.fillStyle = col;
    b.fillRect(0, 0, this.BW, BH);
    b.globalAlpha = 1;
    this._world();
  }

  // The activation moment: a white flash and the move's name across the screen. Without this the
  // only signal that someone had spent a whole meter was a 6%-alpha colour wash, which at
  // 480x270 with four fighters on screen is close to invisible.
  _ultBanner(dt) {
    const B = this.ultBanner;
    if (!B) return;
    B.life -= dt;
    if (B.life <= 0) { this.ultBanner = null; return; }
    const k = B.life / B.max;
    const b = this.b;
    this._screen();
    if (k > 0.82) { b.globalAlpha = (k - 0.82) / 0.18 * 0.8; b.fillStyle = '#FFFFFF'; b.fillRect(0, 0, this.BW, BH); }
    const slide = (1 - Math.min(1, (1 - k) * 6)) * 40;
    b.globalAlpha = Math.min(1, k * 2.2);
    b.fillStyle = B.color;
    b.fillRect(0, BH * 0.34, this.BW, 22);
    b.globalAlpha = Math.min(1, k * 2.6);
    b.fillStyle = '#0B0E14';
    b.fillRect(0, BH * 0.34 + 19, this.BW, 3);
    b.fillStyle = '#FFFFFF';
    b.font = 'bold 15px ui-monospace, monospace';
    b.textAlign = 'center';
    b.fillText(B.label.toUpperCase(), this.BW / 2 + slide, BH * 0.34 + 16);
    b.font = '8px ui-monospace, monospace';
    b.globalAlpha = Math.min(1, k * 2.6) * 0.8;
    b.fillText(B.name.toUpperCase(), this.BW / 2 - slide, BH * 0.34 - 4);
    b.textAlign = 'left';
    b.globalAlpha = 1;
    this._world();
  }

  // Where a falling orb is going to land, drawn on the floor for the whole of its fall. Astral
  // Rain spawns its orbs 20 studs up, which at 4-6 pixels per stud is the top edge of the
  // backbuffer or past it - without this the first thing a player learns about their orb is the
  // hit, and there is no dodge to make.
  _orbMarks(match) {
    const b = this.b;
    for (const p of match.combat.projectiles) {
      if (!p.falling || !p.homing || !p.homing.target) continue;
      const tg = p.homing.target;
      const surf = match.combat.surfaceUnder(p.x, tg.y + 1.5);
      const y = (surf ? surf.top : tg.y) + 0.15;
      const r = (p.explode && p.explode.radius) || 4.8;
      const close = Math.max(0, Math.min(1, 1 - (p.y - y) / 22));   // brightens as the orb closes
      b.globalAlpha = 0.20 + close * 0.45;
      b.strokeStyle = '#B36BFF'; b.lineWidth = 0.22 + close * 0.3;
      b.beginPath(); b.ellipse(p.x, y, r, r * 0.34, 0, 0, PI * 2); b.stroke();
      b.globalAlpha = 0.12 + close * 0.3;
      b.fillStyle = '#B36BFF';
      b.beginPath(); b.ellipse(p.x, y, r * close, r * 0.34 * close, 0, 0, PI * 2); b.fill();
      // a thin column joining the mark to the orb, so the eye follows it down
      b.globalAlpha = 0.12 + close * 0.16;
      b.fillRect(p.x - 0.12, y, 0.24, Math.max(0, p.y - y));
      b.globalAlpha = 1;
    }
  }

  // ---------------------------------------------------------------------- entities ----
  _projectiles(C) {
    const b = this.b;
    for (const p of C.projectiles) {
      const pal = (p.owner && p.owner.char.weaponPalette) || { primary: '#FFFFFF', glow: '#FFFFFF' };
      const dir = Math.sign(p.vx) || 1;
      if (p.shape === 'slug') {
        b.globalAlpha = 0.45; b.fillStyle = pal.glow || '#FFD37A';
        b.fillRect(p.x - dir * 2.2, p.y - 0.09, 2.2, 0.18);            // tracer
        b.globalAlpha = 1;
        b.fillStyle = '#FFF3D0';
        b.fillRect(p.x - 0.28, p.y - 0.13, 0.56, 0.26);
      } else if (p.shape === 'tracer') {
        // A tracked sniper round: a long hot streak, brightest at the head, with a thin red
        // guideline back the way it came so the shot reads even at 480x270.
        const L = 4.5;
        b.globalAlpha = 0.30; b.strokeStyle = '#FF4A4A'; b.lineWidth = 0.10;
        b.beginPath(); b.moveTo(p.x - p.vx * 0.10, p.y - p.vy * 0.10); b.lineTo(p.x, p.y); b.stroke();
        const a = Math.atan2(p.vy, p.vx);
        b.save(); b.translate(p.x, p.y); b.rotate(a);
        b.globalAlpha = 0.55; b.fillStyle = pal.glow || '#FFD37A';
        b.fillRect(-L, -0.16, L, 0.32);
        b.globalAlpha = 1; b.fillStyle = '#FFFFFF';
        b.fillRect(-0.5, -0.13, 1.1, 0.26);
        b.restore();
        b.globalAlpha = 1;
      } else if (p.shape === 'orb') {
        const s = 0.55 + Math.sin(this.time * 12) * 0.06;
        b.globalAlpha = 0.35; b.fillStyle = pal.glow || '#7DE8FF';
        b.beginPath(); b.arc(p.x, p.y, p.w * 0.85, 0, PI * 2); b.fill();
        b.globalAlpha = 1;
        b.fillStyle = pal.glow || '#7DE8FF';
        b.beginPath(); b.arc(p.x, p.y, p.w * 0.45 * s, 0, PI * 2); b.fill();
        b.fillStyle = '#FFFFFF';
        b.beginPath(); b.arc(p.x - 0.1, p.y + 0.1, p.w * 0.18, 0, PI * 2); b.fill();
        // sparks trailing the bolt
        if (Math.random() < 0.5) this.parts.push({ x: p.x, y: p.y, vx: -p.vx * 0.08 + (Math.random() - 0.5) * 2, vy: (Math.random() - 0.5) * 2, life: 0.28, max: 0.28, c: pal.glow || '#7DE8FF', s: 0.16 });
      } else {
        b.fillStyle = pal.primary || '#FFFFFF';
        b.fillRect(p.x - p.w / 2, p.y - p.h / 2, p.w, p.h);
      }
    }
    b.globalAlpha = 1;
  }

  _summons(C) {
    const b = this.b;
    for (const s of C.summons) {
      const pal = (s.owner && s.owner.char.weaponPalette) || {};
      if (s.type === 'wall') { b.fillStyle = pal.primary || '#3F7D3A'; b.fillRect(s.x - s.w / 2, s.y, s.w, s.h); }
      else if (s.type === 'cloud') { b.globalAlpha = 0.4; b.fillStyle = pal.glow || '#E39B2C'; b.beginPath(); b.arc(s.x, s.y, s.r, 0, PI * 2); b.fill(); b.globalAlpha = 1; }
      else if (s.type === 'mine') {
        const armed = s.armed <= 0;
        b.fillStyle = armed ? (pal.glow || '#7DE8FF') : '#8891A6';
        b.beginPath(); b.arc(s.x, s.y + 0.55, 0.55, 0, PI * 2); b.fill();
        if (armed) { b.globalAlpha = 0.25 + Math.sin(this.time * 8) * 0.12; b.strokeStyle = pal.glow || '#7DE8FF'; b.lineWidth = 0.12; b.beginPath(); b.arc(s.x, s.y + 0.55, s.trigger, 0, PI * 2); b.stroke(); b.globalAlpha = 1; }
      } else if (s.type === 'node') { b.fillStyle = pal.accent || '#9A7FB8'; b.beginPath(); b.arc(s.x, s.y + 0.6, 0.6, 0, PI * 2); b.fill(); }
    }
  }

  _items(C) {
    const b = this.b;
    for (const it of C.items) {
      if (it.held) continue;
      b.fillStyle = it.def.id === 'SeedBomb' ? '#6B8E23' : it.def.id === 'Trowel' ? '#B0B8C0' : '#3F8A2E';
      b.fillRect(it.x - 0.6, it.y, 1.2, 1.0);
    }
  }

  _bursts(C) {
    const b = this.b;
    for (const bu of C.bursts) {
      const k = bu.frames / 3;
      b.globalAlpha = clamp(k, 0, 1) * 0.8;
      b.fillStyle = '#FFFFFF';
      b.beginPath(); b.arc(bu.x, bu.y, (bu.rect.x2 - bu.rect.x1) * 0.5 * (1.15 - k * 0.15), 0, PI * 2); b.fill();
      b.globalAlpha = 1;
    }
  }

  _particles(dt) {
    const b = this.b;
    for (let i = this.parts.length - 1; i >= 0; i--) {
      const p = this.parts[i];
      p.life -= dt;
      if (p.life <= 0) { this.parts.splice(i, 1); continue; }
      p.x += p.vx * dt; p.y += p.vy * dt; p.vy -= 26 * dt;
      b.globalAlpha = clamp(p.life / p.max, 0, 1);
      b.fillStyle = p.c;
      b.fillRect(p.x - p.s / 2, p.y - p.s / 2, p.s, p.s);
    }
    // signature impact rings
    for (let i = this.slashes.length - 1; i >= 0; i--) {
      const s = this.slashes[i];
      s.life -= dt;
      if (s.life <= 0) { this.slashes.splice(i, 1); continue; }
      const k = 1 - s.life / s.max;
      b.globalAlpha = (1 - k) * 0.9;
      b.strokeStyle = s.c; b.lineWidth = 0.5 * (1 - k) + 0.12;
      b.beginPath(); b.arc(s.x, s.y, s.r * (0.35 + k * 1.5), 0, PI * 2); b.stroke();
      if (s.heavy) {
        b.lineWidth = 0.22 * (1 - k);
        for (let n = 0; n < 8; n++) {
          const a = (n / 8) * PI * 2 + s.rot;
          const r0 = s.r * (0.5 + k * 1.2), r1 = r0 + s.r * 0.8 * (1 - k);
          b.beginPath(); b.moveTo(s.x + Math.cos(a) * r0, s.y + Math.sin(a) * r0);
          b.lineTo(s.x + Math.cos(a) * r1, s.y + Math.sin(a) * r1); b.stroke();
        }
      }
    }
    b.globalAlpha = 1;
  }

  // ---------------------------------------------------------------------- events ----
  // Signature hits get a ring plus a shower of sparks; ordinary hits get a small pop. This is the
  // "effects when coming into contact" the ultimates are supposed to have.
  handle(e, match) {
    const b = this.parts;
    const push = (x, y, n, c, sp, life, size) => {
      for (let i = 0; i < n; i++) {
        const a = Math.random() * PI * 2, s = sp * (0.4 + Math.random() * 0.8);
        b.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: life * (0.6 + Math.random() * 0.7), max: life, c, s: size });
      }
    };
    if (e.type === 'hit') {
      const heavy = !!e.heavy;
      const atk = match.fighters[e.attacker];
      const col = (atk && atk.char.weaponPalette && atk.char.weaponPalette.glow) || '#FFFFFF';
      push(e.x, e.y, heavy ? 16 : 7, col, heavy ? 26 : 14, heavy ? 0.5 : 0.28, heavy ? 0.32 : 0.2);
      push(e.x, e.y, heavy ? 8 : 4, '#FFFFFF', heavy ? 18 : 10, 0.24, 0.22);
      if (heavy) {
        this.slashes.push({ x: e.x, y: e.y, r: 2.6, life: 0.34, max: 0.34, c: col, heavy: true, rot: Math.random() * PI });
        this.shake = Math.max(this.shake, 0.5);
      } else this.shake = Math.max(this.shake, 0.14);
    } else if (e.type === 'explosion') {
      push(e.x, e.y, 22, '#FFC44D', 30, 0.5, 0.34);
      this.slashes.push({ x: e.x, y: e.y, r: e.radius || 3, life: 0.4, max: 0.4, c: '#FFD37A', heavy: true, rot: 0 });
      this.shake = Math.max(this.shake, 0.7);
    } else if (e.type === 'block') {
      push(e.x, e.y, 6, e.perfect ? '#FFFFFF' : '#9FD1E8', 12, 0.25, 0.2);
    } else if (e.type === 'ko') {
      push(e.x, e.y, 28, PLAYER_TINT[e.fighter % 4], 34, 0.7, 0.4);
      this.slashes.push({ x: e.x, y: e.y, r: 4, life: 0.5, max: 0.5, c: PLAYER_TINT[e.fighter % 4], heavy: true, rot: 0 });
      this.shake = Math.max(this.shake, 1.0);
    } else if (e.type === 'projectile' || e.type === 'beam') {
      push(e.x, e.y, 5, '#FFF3D0', 10, 0.2, 0.18);
    } else if (e.type === 'land' && e.hard) {
      push(e.x, e.y, 8, '#D9C9A8', 12, 0.3, 0.24);
      this.shake = Math.max(this.shake, 0.35);
    } else if (e.type === 'ultimate') {
      const f = match.fighters[e.fighter];
      const pal = f && (f.char.weaponPalette || f.char.palette);
      this.ultBanner = { label: e.label || 'ULTIMATE', name: (f && f.name) || '', life: 1.1, max: 1.1,
        color: (pal && (pal.glow || pal.accent)) || '#FFFFFF' };
      push(e.x, e.y, 30, (pal && pal.glow) || '#FFFFFF', 30, 0.6, 0.4);
      this.shake = Math.max(this.shake, 1.4);
    } else if (e.type === 'ultready') {
      this.shake = Math.max(this.shake, 0.2);
    } else if (e.type === 'soulescape') {
      push(e.x, e.y, 12, '#FFFFFF', 24, 0.35, 0.26);
    } else if (e.type === 'crater') {
      // rock and light thrown out of the floor where the greatsword landed
      push(e.x, e.y, e.first ? 26 : 12, '#5A4A3E', e.first ? 26 : 17, 0.55, e.first ? 0.42 : 0.3);
      push(e.x, e.y, e.first ? 18 : 8, '#FFB43C', e.first ? 30 : 20, 0.42, 0.3);
      this.slashes.push({ x: e.x, y: e.y, r: e.radius, life: 0.32, max: 0.32, c: '#FFD37A', heavy: true, rot: 0 });
      this.shake = Math.max(this.shake, e.first ? 1.1 : 0.35);
    } else if (e.type === 'soulgrab') {
      push(e.x, e.y, 14, '#C79BFF', 20, 0.4, 0.26);
    } else if (e.type === 'soulorb') {
      // matter being dragged inward: particles spawned OUTSIDE and pulled to the centre
      if (Math.random() < 0.7) {
        const a = Math.random() * PI * 2, d = 5 + Math.random() * 4;
        this.parts.push({ x: e.x + Math.cos(a) * d, y: e.y + Math.sin(a) * d,
          vx: -Math.cos(a) * d * 2.4, vy: -Math.sin(a) * d * 2.4, life: 0.4, max: 0.4, c: '#B36BFF', s: 0.2 });
      }
    } else if (e.type === 'soulburst') {
      push(e.x, e.y, 34, '#C79BFF', 40, 0.6, 0.4);
      push(e.x, e.y, 14, '#FFFFFF', 26, 0.35, 0.26);
      this.slashes.push({ x: e.x, y: e.y, r: e.radius, life: 0.45, max: 0.45, c: '#B36BFF', heavy: true, rot: 0 });
      this.slashes.push({ x: e.x, y: e.y, r: e.radius * 1.7, life: 0.3, max: 0.3, c: '#150B22', heavy: true, rot: 0 });
      this.shake = Math.max(this.shake, 1.2);
    } else if (e.type === 'snipe') {
      push(e.x, e.y, 9, '#FFF3D0', 16, 0.24, 0.24);
      this.shake = Math.max(this.shake, 0.4);
    } else if (e.type === 'starfall') {
      push(e.x, e.y, 6, '#B36BFF', 8, 0.35, 0.22);
    } else if (e.type === 'mark') {
      this.shake = Math.max(this.shake, 0.25);
    } else if (e.type === 'counter' || e.type === 'freeze' || e.type === 'summonbreak') {
      push(e.x, e.y, 10, '#FFFFFF', 16, 0.3, 0.22);
    }
  }

  // ---------------------------------------------------------------------- debug ----
  _debug(match) {
    const b = this.b;
    b.lineWidth = 0.12;
    for (const box of match.combat.debugBoxes) {
      b.strokeStyle = box.kind === 'hit' ? 'rgba(232,60,60,0.9)' : box.kind === 'grab' ? 'rgba(210,120,240,0.9)' : 'rgba(120,200,255,0.8)';
      const r = box.rect;
      b.strokeRect(r.x1, r.y1, r.x2 - r.x1, r.y2 - r.y1);
    }
    for (const f of match.fighters) {
      if (!f.alive) continue;
      b.strokeStyle = 'rgba(90,230,120,0.85)';
      b.strokeRect(f.x - f.r, f.y, f.r * 2, f.h);
    }
    const bl = match.stage.blast;
    b.strokeStyle = 'rgba(255,80,80,0.5)';
    b.strokeRect(bl.left, bl.bottom, bl.right - bl.left, bl.top - bl.bottom);
  }
}
