import { stepHazard } from './hazards.js';
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

  // Highest platform at or below `yMax` under `x`. Hazards need this to know where their drops
  // land and where their slicks lie; combat.js has its own copy for projectiles.
  surfaceUnder(x, yMax) {
    let best = null;
    for (const p of this.platforms) {
      if (x < p.x1 || x > p.x2) continue;
      if (p.top > yMax + 0.5) continue;
      if (!best || p.top > best.top) best = p;
    }
    return best;
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
    // Hazards write into each fighter's `env` bag, so it is cleared here, once, immediately
    // before they run. Doing it anywhere else lets a force from last frame leak into this one.
    for (const f of match.fighters) {
      f.env.updraft = 0; f.env.windX = 0; f.env.traction = 1; f.env.grip = 1; f.env.damp = 1;
    }
    this.visual = {};
    const ctx = { stage: this, match, fighters: match.fighters, visual: this.visual };
    for (const h of this.hazards) stepHazard(h, ctx);
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
