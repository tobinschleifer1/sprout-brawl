import { FRAME, LEDGE } from '../config.js';

// Runtime stage: platforms (including moving and sinking ones), ledges, blast zones and hazards.
export class StageRuntime {
  constructor(data) {
    this.data = data;
    this.time = 0;
    this.blast = { ...data.blast };
    this.platforms = [];
    const m = data.main;
    this.main = { id: 'main', solid: true, x1: m.x1, x2: m.x2, top: m.y, bottom: m.y - m.thickness, cx: (m.x1 + m.x2) / 2, w: m.x2 - m.x1, dx: 0, dy: 0, ledges: m.ledges === undefined ? true : m.ledges };
    this.platforms.push(this.main);
    this.solids = [this.main];
    for (const p of data.platforms) {
      // A `moving` spec can carry an `x` range, a `y` range, or both, each with its own period
      // and phase, so an island can slide, bob, or drift in a slow loop. The old flat
      // {from,to,period,phase} shape (still used by a couple of stages) means "x only".
      let move = null;
      if (p.moving) {
        move = p.moving.x || p.moving.y ? p.moving : { x: p.moving };
      }
      const thickness = p.thickness || (p.solid ? 5 : 1);
      const built = { id: p.id, solid: !!p.solid, soft: !p.solid, cx: p.x, cy: p.y, baseY: p.y, w: p.w,
        x1: p.x - p.w / 2, x2: p.x + p.w / 2, top: p.y, bottom: p.y - thickness, dx: 0, dy: 0,
        thickness, tris: p.tris || null,
        moving: move, bobPhase: Math.random() * Math.PI * 2,
        sinking: !!p.sinking, sink: 0, occupiedFrames: 0,
        // A solid can opt out of being grabbable, for blocks you are meant to fight on top of
        // rather than hang off.
        ledges: p.solid ? (p.ledges === undefined ? true : p.ledges) : false };
      this.platforms.push(built);
      if (built.solid) this.solids.push(built);
    }
    // Ledges, per edge. `ledges: false` gives none (a block you fight on top of); `ledges: 'outer'`
    // gives only the edge facing away from stage centre, which is what makes a pit between two
    // islands actually dangerous instead of the safest place to be knocked into.
    this.ledges = [];
    const centre = (Math.min(...this.solids.map((s) => s.x1)) + Math.max(...this.solids.map((s) => s.x2))) / 2;
    for (const sp of this.solids) {
      const mode = sp === this.main ? (sp.ledges === undefined ? true : sp.ledges) : sp.ledges;
      if (!mode) continue;
      const outerIsRight = sp.cx >= centre;
      if (mode !== 'outer' || !outerIsRight) this.ledges.push({ x: sp.x1, y: sp.top, side: -1, platform: sp });
      if (mode !== 'outer' || outerIsRight) this.ledges.push({ x: sp.x2, y: sp.top, side: 1, platform: sp });
    }
    this.hazards = data.hazards.map((h) => ({ ...h, state: {} }));
    this.waterLevel = null;
    this.events = [];
    this.visual = {}; // renderer hints: vent phase, sprinkler x, dust devil, tide
  }

  step(match) {
    this.time += FRAME;
    // Moving platforms
    for (const p of this.platforms) {
      p.dx = 0; p.dy = 0;
      if (p.moving) {
        if (p.moving.x) {
          const M = p.moving.x;
          const t = ((this.time / M.period) + M.phase) * Math.PI * 2;
          const mid = (M.from + M.to) / 2, amp = (M.to - M.from) / 2;
          const nx = mid + amp * Math.sin(t);
          p.dx = nx - p.cx;
          p.cx = nx; p.x1 = nx - p.w / 2; p.x2 = nx + p.w / 2;
        }
        if (p.moving.y) {
          const M = p.moving.y;
          const t = ((this.time / M.period) + M.phase) * Math.PI * 2;
          const mid = (M.from + M.to) / 2, amp = (M.to - M.from) / 2;
          const ny = mid + amp * Math.sin(t);
          p.dy = ny - p.top;
          p.top = ny; p.cy = ny; p.bottom = ny - (p.thickness || 1);
        }
      }
      if (p.sinking) {
        const stood = match.fighters.some((f) => f.alive && f.onGround && f.platform === p);
        if (stood) { p.occupiedFrames++; p.sink = Math.min(4, p.sink + 4 / 60); } else { p.occupiedFrames = 0; p.sink = Math.max(0, p.sink - 4 / 60); }
        const ny = p.baseY - p.sink;
        p.dy = ny - p.top;
        p.top = ny; p.cy = ny; p.bottom = ny - 1;
        if (p.occupiedFrames > 120) {
          for (const f of match.fighters) if (f.onGround && f.platform === p) f.dropThrough();
          p.occupiedFrames = 0;
        }
      }
    }
    for (const h of this.hazards) this._stepHazard(h, match);
  }

  _stepHazard(h, match) {
    const s = h.state;
    if (h.type === 'vents') {
      s.timer = (s.timer || 0) + FRAME;
      const cycle = h.period;
      const t = s.timer % cycle;
      const warnStart = cycle - (h.warn + h.erupt) / 60;
      const eruptStart = cycle - h.erupt / 60;
      s.phase = t >= eruptStart ? 'erupt' : t >= warnStart ? 'warn' : 'idle';
      this.visual.vents = { phase: s.phase, positions: h.positions, width: h.width };
      if (s.phase === 'erupt') {
        for (const f of match.fighters) {
          if (!f.alive || !f.onGround || !f.platform || !f.platform.solid) continue;
          if (h.positions.some((px) => Math.abs(f.x - px) < h.width / 2 + f.r)) f.launchNoStun(0, h.launch);
        }
      }
    } else if (h.type === 'sprinkler') {
      s.timer = (s.timer || 0) + FRAME;
      const t = s.timer % h.period;
      const tickStart = h.period - h.tick / 60 - h.sweepSeconds;
      const sweepStart = h.period - h.sweepSeconds;
      if (t >= sweepStart) {
        const k = (t - sweepStart) / h.sweepSeconds;
        const x = this.main.x1 - 10 + k * (this.main.w + 20);
        s.phase = 'sweep'; s.x = x;
        for (const f of match.fighters) {
          if (!f.alive || f.onGround) continue;
          // Bounded to the drawn column. It used to act over 12 studs with no vertical limit at
          // all, so it shoved players recovering far below the stage, outward, invisibly.
          if (f.y < -6 || f.y > 22) continue;
          if (Math.abs(f.x - x) < 3) f.vx += Math.sign(f.x - x || 1) * (h.push * 4) * FRAME;
        }
      } else if (t >= tickStart) { s.phase = 'tick'; } else { s.phase = 'idle'; }
      this.visual.sprinkler = { phase: s.phase, x: s.x || 0 };
    } else if (h.type === 'dustdevil') {
      s.timer = (s.timer || 0) + FRAME;
      const t = s.timer % h.period;
      const start = h.period - h.crossSeconds;
      if (t >= start) {
        if (!s.active) { s.active = true; s.dir = Math.random() < 0.5 ? 1 : -1; s.hits = new Map(); }
        const k = (t - start) / h.crossSeconds;
        const from = s.dir > 0 ? this.main.x1 - 12 : this.main.x2 + 12;
        const to = s.dir > 0 ? this.main.x2 + 12 : this.main.x1 - 12;
        s.x = from + (to - from) * k;
        for (const f of match.fighters) {
          if (!f.alive) continue;
          const last = s.hits.get(f.index) || -999;
          if (match.frame - last < 60) continue;
          if (Math.abs(f.x - s.x) < h.width / 2 + f.r && f.y < h.height && f.y + f.h > 0) {
            s.hits.set(f.index, match.frame);
            match.combat.hazardHit(f, { damage: h.damage, launch: h.launch, angle: h.angle, x: s.x, y: f.y + 2 });
          }
        }
      } else { s.active = false; }
      this.visual.dustdevil = s.active ? { x: s.x, w: h.width, h: h.height } : null;
    } else if (h.type === 'tide') {
      s.timer = (s.timer || 0) + FRAME;
      const t = s.timer % h.period;
      const riseStart = h.period - (h.rise + h.hold + h.fall);
      let level = h.low;
      if (t >= riseStart && t < riseStart + h.rise) level = h.low + (h.high - h.low) * ((t - riseStart) / h.rise);
      else if (t >= riseStart + h.rise && t < riseStart + h.rise + h.hold) level = h.high;
      else if (t >= riseStart + h.rise + h.hold) level = h.high - (h.high - h.low) * ((t - riseStart - h.rise - h.hold) / h.fall);
      this.waterLevel = level;
      this.visual.tide = { level, edge: h.edge };
      for (const f of match.fighters) {
        if (!f.alive) continue;
        const inWater = f.y < level && (Math.abs(f.x) > h.edge || f.y < this.main.bottom);
        if (inWater && !f.inWater) { /* entering: jumps are not consumed */ }
        f.inWater = inWater;
        if (inWater) f.vx += Math.sign(f.x || 1) * 6 * FRAME * 4;
      }
    }
  }

  // Sudden death: shrink all four sides toward the origin.
  // Sudden death closes the blast box in. It must never close past the stage itself, or there is
  // solid ground sitting outside the kill boundary and a fighter standing on it dies for nothing.
  shrink(factor) {
    let l = Infinity, r = -Infinity, t = -Infinity;
    for (const sp of this.solids) { l = Math.min(l, sp.x1); r = Math.max(r, sp.x2); t = Math.max(t, sp.top); }
    for (const p of this.platforms) t = Math.max(t, p.top);
    const SIDE = 14;
    // The ceiling margin has to clear a double jump (25.4 studs) or late sudden death makes
    // jumping suicide.
    const ROOF = 30;
    this.blast.left = Math.min(this.blast.left * factor, l - SIDE);
    this.blast.right = Math.max(this.blast.right * factor, r + SIDE);
    this.blast.top = Math.max(this.blast.top * factor, t + ROOF);
    this.blast.bottom *= factor;
  }

  outsideBlast(f) {
    const b = this.blast;
    return f.x < b.left || f.x > b.right || f.y > b.top || f.y + f.h < b.bottom;
  }

  // Resolve movement from (px,py) to (nx,ny) for a fighter with half-width r and height h.
  // Returns { x, y, landed (platform|null), wall (bool), bumped (bool) }.
  collide(f, px, py, nx, ny) {
    const r = f.r, h = f.h;
    let x = nx, y = ny, landed = null, wall = false, bumped = false;
    // Horizontal against every solid's sides
    const bodyBottom = Math.min(py, ny), bodyTop = Math.max(py, ny) + h;
    for (const sp of this.solids) {
      if (!(bodyBottom < sp.top - 0.05 && bodyTop > sp.bottom)) continue;
      if (px <= sp.x1 - r + 0.001 && x > sp.x1 - r) { x = sp.x1 - r; wall = true; }
      else if (px >= sp.x2 + r - 0.001 && x < sp.x2 + r) { x = sp.x2 + r; wall = true; }
      else if (sp.dx && x > sp.x1 - r && x < sp.x2 + r) {
        // Only for a solid that MOVED this frame: it drove into a fighter who never moved into it,
        // so nothing above catches it. Eject out the nearer face. Restricted to moving solids
        // because a static one overlapping here is just a fighter landing on top of it.
        x = (x - sp.cx < 0) ? sp.x1 - r : sp.x2 + r;
        wall = true;
      }
    }
    // Vertical
    if (f.vy <= 0 || ny < py) {
      for (const p of this.platforms) {
        if (p.soft && f.dropTimer > 0) continue;
        const inside = x + r * 0.6 > p.x1 && x - r * 0.6 < p.x2;
        if (!inside) continue;
        const prevTop = p.top - p.dy; // where the platform surface was last frame
        if (py >= prevTop - 0.05 && y < p.top) { y = p.top; landed = p; }
      }
    } else if (f.vy > 0) {
      for (const sp of this.solids) {
        const inside = x + r * 0.6 > sp.x1 && x - r * 0.6 < sp.x2;
        if (inside && py + h <= sp.bottom && y + h > sp.bottom) { y = sp.bottom - h; bumped = true; break; }
      }
    }
    return { x, y, landed, wall, bumped };
  }

  // Is the fighter still supported by its platform?
  supported(f) {
    const p = f.platform;
    if (!p) return false;
    return f.x + f.r * 0.6 > p.x1 && f.x - f.r * 0.6 < p.x2 && Math.abs(f.y - p.top) < 0.5;
  }

  // Returns a ledge the fighter can grab right now, or null.
  ledgeFor(f, guardPressed) {
    if (f.ledgeCooldown > 0 || f.ledgeGrabs >= LEDGE.maxGrabs) return null;
    if (f.vy > 6) return null;
    for (const L of this.ledges) {
      const dx = (f.x - L.x) * L.side; // positive = outside the stage
      if (dx < 0.2 || dx > LEDGE.grabReach + f.r) continue;
      if (f.y > L.y + 1 || f.y < L.y - LEDGE.grabDepth) continue;
      if (f.facing === -L.side || guardPressed) return L;
    }
    return null;
  }

  nearestLedge(x, y) {
    let best = null, bd = Infinity;
    for (const L of this.ledges) {
      const d = Math.hypot(L.x - x, L.y - y);
      if (d < bd) { bd = d; best = L; }
    }
    return { ledge: best, dist: bd };
  }

  // Random spawn spot for an item: a point on top of a platform.
  itemSpawn() {
    const p = this.platforms[Math.floor(Math.random() * this.platforms.length)];
    return { x: p.x1 + 2 + Math.random() * (p.w - 4), y: p.top + 8 };
  }
}
