// Natural disasters: big, scheduled, telegraphed events - distinct from hazards, which are a
// stage's small permanent features. Roadmap R5 of the revamp plan.
//
// THE CONTRACT every disaster keeps (each clause is asserted in test/disasters.test.mjs):
//   - It is OFF unless the match asks for it. Ranked never does. With disasters off this file
//     draws nothing from the seeded generator, so every existing match replays unchanged.
//   - It WARNS for at least 90 frames before it can touch anyone, and says where.
//   - It hits through the real knockback curves (launchSpeed / stunSpeed at the victim's
//     percent), with low growth, so it cannot take a stock off a low-percent fighter.
//   - It has somewhere safe to stand AND a timing answer (jump it, shield it, get airborne).
//   - It never touches the untouchable: respawning, invincible, dodging or KO'd fighters.
//   - It is deterministic: every random choice comes from the stage's seeded generator.
//
// Scheduling: the first disaster no earlier than 45 s into the fight, then one every 40-55 s.
// Never during the countdown or sudden death, and never two at once.
import { FRAME, SHIELD } from '../config.js';
import { launchSpeed, stunSpeed } from './knockback.js';

export const MODES = ['off', 'stage', 'chaos'];
export const FIRST_AT = 45;
export const GAP = [40, 55];
export const MIN_WARN = 90;                       // frames; the contract's floor

const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
// Never 0 - which is why no call below needs JavaScript's usual `x || 1` guard against sign(0).
const sign = (v) => (v < 0 ? -1 : 1);

// Everyone a disaster may touch. The same exclusions hazards use, for the same reason: weather
// that hits you on your respawn platform is the most infuriating thing a stage can do.
function targets(ctx) {
  return ctx.fighters.filter((f) => f.alive && !f.untouchable && f.state !== 'respawn' && f.state !== 'ko');
}

// One disaster hit: through the knockback curves, blocked by a shield like any other hit.
// Returns true if it connected (blocked or not), so callers can mark the fighter as hit.
export function disasterHit(ctx, f, p) {
  if (f.untouchable) return false;
  const facing = p.facing ?? sign(f.x - p.x);
  if (f.state === 'shield' && p.blockable !== false) {
    const perfect = f.sf <= SHIELD.perfectFrames;
    f.applyBlock({ damage: p.damage, facing, perfect });
    ctx.match.combat.emit({ type: 'block', x: f.x, y: f.cy, perfect, victim: f.index, disaster: p.kind });
    return true;
  }
  const after = f.percent + p.damage;
  const launch = launchSpeed(p.base, p.growth, p.damage, after, f.weight);
  const stun = stunSpeed(p.base, p.growth, p.damage, after, f.weight);
  f.applyHit({ damage: p.damage, launch, stun, angle: p.angle, facing, attacker: null, hitlag: p.hitlag ?? 6 });
  const kill = ctx.match.combat.killHit(f);
  ctx.match.combat.emit({ type: 'hit', x: f.x, y: f.cy, damage: p.damage, launch, heavy: false, weight: f.weight,
    attacker: -1, victim: f.index, angle: p.angle, facing, disaster: p.kind, kill });
  return true;
}

// Damage with no knockback at all: a burning crater, standing in the lava's afterglow.
function chip(ctx, f, damage, kind) {
  if (f.untouchable) return;
  f.percent = Math.min(999, f.percent + damage);
  f.stats.damageTaken += damage;
  ctx.match.combat.emit({ type: 'chip', x: f.x, y: f.cy, damage, victim: f.index, disaster: kind });
}

// Where the ground is: the extents of the solids, for placing strikes on something standable.
function groundSpan(stage) {
  let lo = Infinity, hi = -Infinity;
  for (const s of stage.solids) { lo = Math.min(lo, s.x1); hi = Math.max(hi, s.x2); }
  return [lo, hi];
}
function surfaceY(stage, x) {
  const s = stage.surfaceUnder(x, 999);
  return s ? s.top : stage.main.top;
}

// ------------------------------------------------------------------------------- the six ----
// Each: warn/strike/after in frames, begin(d, ctx) to roll its random choices, and
// step(d, ctx, phase, k) run every frame of the event. `d.hit` remembers who has been hit.
// The order disasters are considered in when one is drawn at random. Explicit, because a random
// pick indexes into this list and Luau tables have no iteration order to rely on.
export const ORDER = ['lavasurge', 'lightning', 'tornado', 'tsunami', 'earthquake', 'meteor'];

export const DISASTERS = {
  // LAVA SURGE (Smeltworks). The pour spills: the floor-level fills with slag to a telegraphed line.
  // Safe: any shelf above the line (the west shelf at 13 is one jump; a jump peaks at 13.2).
  // Timing: the launch out of the lava can be DI'd onto a shelf.
  lavasurge: {
    warn: 120, strike: 360, after: 120, chaos: false,
    params: { line: 3, low: -14, damage: 14, base: 55, growth: 0.25, angle: 90, cooldown: 60 },
    begin(d) { d.level = d.p.low; d.cool = new Map(); },
    step(d, ctx, phase, k) {
      const p = d.p;
      if (phase === 'strike') d.level = p.low + (p.line - p.low) * clamp(k * 6, 0, 1);         // rises over the first sixth
      else if (phase === 'after') d.level = p.line + (p.low - p.line) * clamp(k, 0, 1);
      else d.level = p.low;
      for (const [i, t] of d.cool) if (t > 0) d.cool.set(i, t - 1);
      if (phase === 'warn') return;
      for (const f of targets(ctx)) {
        if (f.y >= d.level || (d.cool.get(f.index) || 0) > 0) continue;
        d.cool.set(f.index, p.cooldown);
        disasterHit(ctx, f, { kind: 'lavasurge', damage: p.damage, base: p.base, growth: p.growth, angle: p.angle, x: f.x, blockable: false });
      }
    },
    visual(d) { return { level: d.level, line: d.p.line }; },
  },

  // LIGHTNING STORM (Rooftops; any map in Chaos). Waves of strikes, each marked on the ground first.
  // Rods pull any strike within 8 studs onto themselves, so near a rod is DANGEROUS, not safe.
  // Timing: a bolt is live for 6 frames - shield it.
  lightning: {
    warn: 90, strike: 4 * 40 + 3 * 12 + 6, after: 30, chaos: true,
    params: { waves: 4, perWave: 3, waveGap: 40, stagger: 12, markWarn: 90, bolt: 6, width: 2.5, damage: 11, base: 40, growth: 0.3, angle: 80, pull: 8, rods: [] },
    begin(d, ctx) {
      const p = d.p, [lo, hi] = groundSpan(ctx.stage);
      d.strikes = [];
      for (let w = 0; w < p.waves; w++) for (let s = 0; s < p.perWave; s++) {
        let x = lo + 3 + ctx.stage.rng() * (hi - lo - 6);
        for (const r of p.rods) if (Math.abs(x - r) < p.pull) x = r;
        // `at` counts from the start of the WARN phase, so the first marker still gets its full
        // warning even though the event's own warn phase is shorter than a marker's.
        d.strikes.push({ x, at: w * p.waveGap + s * p.stagger, hit: new Set() });
      }
    },
    step(d, ctx, phase, k, frame) {
      const p = d.p;
      for (const s of d.strikes) {
        const t = frame - s.at;                       // frames since this strike's marker appeared
        s.live = t >= p.markWarn && t < p.markWarn + p.bolt;
        s.marked = t >= 0 && t < p.markWarn;
        if (!s.live) continue;
        for (const f of targets(ctx)) {
          if (s.hit.has(f.index) || Math.abs(f.x - s.x) > p.width + f.r) continue;
          s.hit.add(f.index);
          disasterHit(ctx, f, { kind: 'lightning', damage: p.damage, base: p.base, growth: p.growth, angle: p.angle, x: s.x, hitlag: 12 });
        }
      }
    },
    visual(d, ctx) { return { strikes: d.strikes.filter((s) => s.marked || s.live).map((s) => ({ x: s.x, y: surfaceY(ctx.stage, s.x), live: !!s.live })) }; },
  },

  // TORNADO (Saltflat; Chaos). Forms at one edge, crosses at 9 studs/s - slower than a WALK (12).
  // Caught: thrown out at 75 degrees, DI-able. Safe: anything above 16 studs. Timing: the funnel
  // is 3 studs wide at the floor, so a full hop clears it.
  tornado: {
    warn: 120, strike: 720, after: 60, chaos: true,
    params: { speed: 9, radiusTop: 5, radiusFloor: 1.5, height: 16, damage: 8, base: 45, growth: 0.6, angle: 75, pull: 14 },
    begin(d, ctx) {
      const [lo, hi] = groundSpan(ctx.stage);
      d.dir = ctx.stage.rng() < 0.5 ? 1 : -1;
      d.x = d.dir > 0 ? lo - 4 : hi + 4;
      d.floor = ctx.stage.main.top;
      d.hit = new Set();
    },
    step(d, ctx, phase) {
      const p = d.p;
      if (phase !== 'strike') return;
      d.x += d.dir * p.speed * FRAME;
      for (const f of targets(ctx)) {
        const up = f.y - d.floor;
        if (up < -1 || up > p.height) continue;
        const r = p.radiusFloor + (p.radiusTop - p.radiusFloor) * clamp(up / p.height, 0, 1);
        const dx = f.x - d.x;
        if (Math.abs(dx) <= r + f.r) {
          if (d.hit.has(f.index)) continue;
          d.hit.add(f.index);
          disasterHit(ctx, f, { kind: 'tornado', damage: p.damage, base: p.base, growth: p.growth, angle: p.angle, facing: d.dir, x: d.x });
        } else if (Math.abs(dx) < r * 3 && !f.onGround && f.state !== 'hitstun' && !f.tumbling) {
          f.env.windX += -sign(dx) * p.pull;            // the inflow: pressure, never a capture
        }
      }
    },
    visual(d) { return { x: d.x, floor: d.floor, height: d.p.height, radiusTop: d.p.radiusTop, radiusFloor: d.p.radiusFloor, dir: d.dir }; },
  },

  // TSUNAMI (Undertow). The horizon rises, then a 10-stud crest sweeps across at 30 studs/s.
  // Safe: the gull (27), the raft (12) and the buoys at their peak. Timing: jump the wave.
  // The crest height is set by that timing answer, not by look: a jump (63 studs/s against 150
  // gravity) stays above 12 studs for only 0.256 s, and a 6-stud crest at 30 studs/s overlaps a
  // fighter for 0.273 s - so a 12-stud wave could not be jumped however well it was timed. The
  // design said it could; the test proved it wrong. Above 10 studs a full jump spends frames 16-45
  // after the press (3 of them jumpsquat), so pressing jump while the crest is 12-18 studs away -
  // a quarter to half a second ahead - clears it. That window is the skill.
  tsunami: {
    warn: 150, strike: 480, after: 180, chaos: false,
    params: { speed: 30, crest: 10, width: 6, base0: -9, damage: 16, base: 50, growth: 0.35, angle: 30, current: 20 },
    begin(d, ctx) {
      d.dir = ctx.stage.rng() < 0.5 ? 1 : -1;
      d.x = d.dir > 0 ? ctx.stage.blast.left : ctx.stage.blast.right;
      d.hit = new Set();
    },
    step(d, ctx, phase, k) {
      const p = d.p;
      if (phase === 'warn') return;
      const strength = phase === 'after' ? 1 - k : 1;
      if (phase === 'strike') d.x += d.dir * p.speed * FRAME;
      for (const f of targets(ctx)) {
        const behind = (d.x - f.x) * d.dir > 0;
        const inCrest = phase === 'strike' && Math.abs(f.x - d.x) <= p.width / 2 + f.r && f.y < p.crest && f.y > p.base0 - 2;
        if (inCrest && !d.hit.has(f.index)) {
          d.hit.add(f.index);
          disasterHit(ctx, f, { kind: 'tsunami', damage: p.damage, base: p.base, growth: p.growth, angle: p.angle, facing: d.dir, x: d.x });
        } else if (behind && f.y < p.crest && f.state !== 'hitstun' && !f.tumbling) {
          f.env.windX += d.dir * p.current * strength;   // the backwash drags, it does not kill
        }
      }
    },
    visual(d) { return { x: d.x, dir: d.dir, crest: d.p.crest, width: d.p.width, base: d.p.base0 }; },
  },

  // EARTHQUAKE (Faultline). 1-2 plates' seams glow; they drop 4 studs and stay down 4 s; ledges
  // everywhere lock for 90 frames. On a plate as it drops: popped up. Timing: be airborne on the
  // drop frame. On a map without plates this is TREMOR: the ledge lock and a floor ripple only.
  earthquake: {
    warn: 120, strike: 280, after: 30, chaos: true,
    params: { drop: 4, dropFrames: 10, lockFrames: 90, damage: 6, base: 40, growth: 0.2, angle: 90, tremorDamage: 3, tremorBase: 30 },
    begin(d, ctx) {
      const solids = ctx.stage.solids;
      d.plates = [];
      if (solids.length >= 3) {
        // Never both outermost solids: somewhere must always have a ledge to recover to.
        // ...and never the main floor: the stable ground a stage is built around.
        const inner = solids.filter((s) => s !== ctx.stage.main && s !== solids.reduce((a, b) => (a.x1 < b.x1 ? a : b)) && s !== solids.reduce((a, b) => (a.x2 > b.x2 ? a : b)));
        const pool = inner.length ? inner : solids.filter((s) => s !== ctx.stage.main);
        const n = pool.length > 1 && ctx.stage.rng() < 0.5 ? 2 : 1;
        for (let i = 0; i < n; i++) {
          const pick = pool[Math.floor(ctx.stage.rng() * pool.length)];
          if (!d.plates.includes(pick)) d.plates.push(pick);
        }
      }
      d.base = d.plates.map((s) => s.top);
      d.done = false;
    },
    step(d, ctx, phase, k, frame) {
      const p = d.p, t = frame - d.warn;               // frames into the strike
      ctx.stage.ledgesLocked = phase === 'strike' && t < p.lockFrames;
      if (phase === 'warn') return;
      if (phase === 'strike' && t === 0 && !d.done) {
        d.done = true;
        const tremor = d.plates.length === 0;
        for (const f of targets(ctx)) {
          if (!f.onGround) continue;                     // airborne on the drop frame: untouched
          if (!tremor && !d.plates.includes(f.platform)) continue;
          disasterHit(ctx, f, { kind: 'earthquake', damage: tremor ? p.tremorDamage : p.damage, base: tremor ? p.tremorBase : p.base, growth: p.growth, angle: p.angle, x: f.x });
        }
      }
      d.plates.forEach((s, i) => {
        let off = 0;
        if (phase === 'strike') off = -p.drop * clamp(t / p.dropFrames, 0, 1);
        else if (phase === 'after') off = -p.drop * (1 - k);
        const ny = d.base[i] + off;
        s.dy = ny - s.top; s.top = ny; s.bottom = ny - (s.thickness || 5);
        // Flag for the Roblox clients' prediction (Stage.dynamicState ships displaced platforms);
        // set in both builds so the two ports stay line for line.
        s.displaced = off !== 0;
      });
    },
    end(d, ctx) { ctx.stage.ledgesLocked = false; d.plates.forEach((s, i) => { s.dy = d.base[i] - s.top; s.top = d.base[i]; s.bottom = d.base[i] - (s.thickness || 5); s.displaced = false; }); },
    visual(d) { return { plates: d.plates.map((s) => ({ x1: s.x1, x2: s.x2, top: s.top })) }; },
  },

  // METEOR SHOWER (Ashfall Summit; Chaos). Waves of six; each meteor's shadow grows 100 frames
  // before it lands, and leaves a burning crater. Timing: the impact is live 4 frames - shield it.
  meteor: {
    warn: 100, strike: 3 * 70 + 104, after: 180, chaos: true,
    params: { waves: 3, perWave: 6, waveGap: 70, shadow: 100, impact: 4, radius: 5, spacing: 10, damage: 13, base: 50, growth: 0.3, angle: 65, crater: 180, craterRadius: 3, chip: 2, chipEvery: 30 },
    begin(d, ctx) {
      const p = d.p, [lo, hi] = groundSpan(ctx.stage);
      d.rocks = [];
      for (let w = 0; w < p.waves; w++) {
        const wave = [];
        for (let tries = 0; wave.length < p.perWave && tries < 60; tries++) {
          const x = lo + 2 + ctx.stage.rng() * (hi - lo - 4);
          if (wave.every((r) => Math.abs(r.x - x) >= p.spacing)) wave.push({ x, at: w * p.waveGap, hit: new Set() });
        }
        d.rocks.push(...wave);
      }
    },
    step(d, ctx, phase, k, frame) {
      const p = d.p;
      for (const r of d.rocks) {
        const t = frame - r.at;
        r.y = surfaceY(ctx.stage, r.x);
        r.shadow = t >= 0 && t < p.shadow ? t / p.shadow : 0;
        r.live = t >= p.shadow && t < p.shadow + p.impact;
        r.burning = t >= p.shadow + p.impact && t < p.shadow + p.impact + p.crater;
        for (const f of targets(ctx)) {
          const dx = f.x - r.x, dy = f.cy - r.y;
          // sqrt, never Math.hypot: the two differ in the last bits between engines, which this repo
          // found the hard way - and a distance compared against a radius is exactly where it shows.
          if (r.live && !r.hit.has(f.index) && Math.sqrt(dx * dx + dy * dy) <= p.radius + f.r) {
            r.hit.add(f.index);
            disasterHit(ctx, f, { kind: 'meteor', damage: p.damage, base: p.base, growth: p.growth, angle: p.angle, facing: sign(dx), x: r.x });
          } else if (r.burning && f.onGround && Math.abs(dx) <= p.craterRadius && (t - p.shadow - p.impact) % p.chipEvery === 0) {
            chip(ctx, f, p.chip, 'meteor');
          }
        }
      }
    },
    visual(d) { return { rocks: d.rocks.filter((r) => r.shadow > 0 || r.live || r.burning).map((r) => ({ x: r.x, y: r.y, shadow: r.shadow, live: !!r.live, burning: !!r.burning })) }; },
  },
};

// ------------------------------------------------------------------------------ the director ----
// Owned by the stage. `mode` is 'off' | 'stage' | 'chaos'; `own` is the stage's own disaster list.
export class DisasterDirector {
  constructor(mode, own, params = {}) {
    this.mode = MODES.includes(mode) ? mode : 'off';
    this.own = own || [];
    this.params = params;                  // per-stage overrides, e.g. Rooftops' rod positions
    this.clock = 0; this.next = null; this.active = null;
  }
  pool() {
    if (this.params.force) return [this.params.force];
    if (this.mode === 'stage') return this.own.slice();
    if (this.mode === 'chaos') {
      // the stage's own first, then every chaos-eligible disaster not already listed, in ORDER
      const out = this.own.slice();
      for (const k of ORDER) if (DISASTERS[k].chaos && !out.includes(k)) out.push(k);
      return out;
    }
    return [];
  }
  step(ctx) {
    const match = ctx.match;
    if (this.mode === 'off' || !match || match.state !== 'fight') { this.finish(ctx); return null; }
    const pool = this.pool();
    if (!pool.length) return null;
    this.clock += FRAME;
    if (this.next === null) this.next = this.params.firstAt ?? FIRST_AT;   // 45 s; `firstAt` is for traces
    if (!this.active && this.clock >= this.next) this.start(ctx, pool);
    if (!this.active) return null;
    const a = this.active, def = DISASTERS[a.type];
    const total = a.warn + def.strike + def.after;
    const phase = a.frame < a.warn ? 'warn' : a.frame < a.warn + def.strike ? 'strike' : 'after';
    const k = phase === 'warn' ? a.frame / a.warn : phase === 'strike' ? (a.frame - a.warn) / def.strike : (a.frame - a.warn - def.strike) / def.after;
    def.step(a, ctx, phase, k, a.frame);
    const view = { type: a.type, phase, k, frame: a.frame, warn: a.warn, total, ...def.visual(a, ctx) };
    a.frame++;
    if (a.frame >= total) this.finish(ctx);
    return view;
  }
  start(ctx, pool) {
    const type = pool[Math.floor(ctx.stage.rng() * pool.length)];
    const def = DISASTERS[type];
    this.active = { type, frame: 0, warn: Math.max(MIN_WARN, def.warn), p: { ...def.params, ...(this.params[type] || {}) } };
    def.begin(this.active, ctx);
    ctx.match.combat.emit({ type: 'disaster', disaster: type, phase: 'warn' });
  }
  finish(ctx) {
    if (!this.active) return;
    const def = DISASTERS[this.active.type];
    if (def.end) def.end(this.active, ctx);
    this.active = null;
    this.next = this.clock + GAP[0] + ctx.stage.rng() * (GAP[1] - GAP[0]);
  }
}
