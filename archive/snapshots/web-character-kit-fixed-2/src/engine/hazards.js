// Stage hazards: the natural things a stage does to the people fighting on it.
//
// Every hazard is one entry in HAZARDS, and every entry is the same shape:
//
//   step(h, ctx)   run once a frame. `h` is the stage's hazard data plus `h.state` (scratch that
//                  survives between frames). `ctx` is { stage, match, fighters, visual }.
//                  Write to `ctx.visual[key]` to tell the renderer what to draw.
//
// The rule this file is built around: a hazard is PRESSURE, never an execution. Nothing in here
// KOs on its own. Hazards push, lift, carry, slow and chip; they can absolutely throw you into a
// blast zone, but the kill is always the stage's geometry finishing what the hazard started, and
// the player always had frames in which to do something about it. That is what keeps a match a
// fight between two players rather than a fight against the weather.
//
// The second rule: EVERY hazard telegraphs. A hazard with a warning phase is a decision — leave,
// or take it and use it. A hazard without one is a dice roll. Every entry below has an explicit
// warn/charge phase long enough to react to, and it is the renderer's job to sell it.
//
// Fighters expose `f.env`, a per-frame bag zeroed before hazards run:
//   env.updraft   studs/s² added to vertical velocity while airborne (vents, embers, funnels)
//   env.windX     studs/s² added to horizontal velocity while airborne (gusts, jets, spray)
//   env.traction  multiplier on ground friction; below 1 is slippery, and it is CLAMPED so a
//                 stage can never take ground control away entirely
//   env.grip      multiplier on horizontal ground acceleration, same idea
import { FRAME } from '../config.js';

const sign = (v) => (v < 0 ? -1 : 1);
const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
// Smooth 0→1→0 over a normalised span. Every hazard that ramps in and out uses this, so no
// hazard ever switches on at full strength on a single frame.
const bell = (k) => Math.sin(clamp(k, 0, 1) * Math.PI);
const smooth = (k) => { const c = clamp(k, 0, 1); return c * c * (3 - 2 * c); };

// A hazard's cycle, as a phase name plus how far through that phase we are. Written once here
// because every hazard has the same shape — quiet, then a warning, then the event — and getting
// that consistent is most of what makes a stage learnable.
function cyclePhase(s, period, warnSeconds, activeSeconds) {
  s.timer = (s.timer || 0) + FRAME;
  const t = s.timer % period;
  const warnStart = period - warnSeconds - activeSeconds;
  const activeStart = period - activeSeconds;
  if (t >= activeStart) return { phase: 'active', k: (t - activeStart) / activeSeconds, t };
  if (t >= warnStart) return { phase: 'warn', k: (t - warnStart) / warnSeconds, t };
  return { phase: 'idle', k: (t - 0) / Math.max(0.001, warnStart), t };
}

// Everyone who is alive and can be touched. Hazards deliberately skip fighters who are already
// dead, respawning or invincible — being hit by the weather during your respawn platform drop is
// the single most infuriating thing a stage can do.
function targets(ctx) {
  return ctx.fighters.filter((f) => f.alive && !f.untouchable && f.state !== 'respawn' && f.state !== 'ko');
}

// Everyone a hazard is allowed to PUSH. The extra rule over `targets` is that a fighter already
// in hitstun or tumbling is off limits.
//
// This is not a nicety, it is what keeps the game finishable. Without it a launched fighter gets
// caught by whatever weather happens to be between them and the blast zone, held up, and survives
// a hit that had already killed them — measured on Saltflat, where the dust devil's updraft was
// catching everyone blown off the left side and matches ran past four minutes without resolving.
// A hazard may create a kill; it must never cancel one somebody else earned. Once the victim
// techs, lands or recovers, the weather applies to them again.
function pushable(ctx) {
  return targets(ctx).filter((f) => f.state !== 'hitstun' && !f.tumbling);
}

export const HAZARDS = {
  // ---------------------------------------------------------------- STEAM VENTS (Smeltworks)
  // Pressure builds under a grate and lets go. The old version was a single frame of
  // `launchNoStun` — you were 12 studs in the air with no idea why. Now it is a sustained column
  // you can see coming, and once it is up it is a genuine updraft: standing in one is a mistake,
  // but recovering through one is a route. The hazard and the tool are the same object.
  vents: {
    step(h, ctx) {
      const s = h.state;
      const c = cyclePhase(s, h.period, h.warn / 60, h.erupt / 60);
      s.phase = c.phase;
      // ONE grate per cycle, alternating. The first build armed every vent every time, which is
      // what the comment here claimed it did not do: both islands went off together every nine
      // seconds, nobody on Smeltworks was ever on the ground, and matches stopped resolving
      // inside the soak's time limit. Arming one at a time also makes the stage readable — the
      // grate that is about to blow is the one that is glowing, and the other one is safe.
      const cycleId = Math.floor(s.timer / h.period);
      if (s.cycleId !== cycleId) {
        s.cycleId = cycleId;
        s.armed = [h.positions[cycleId % h.positions.length]];
      }
      const armed = s.armed || h.positions;
      const strength = c.phase === 'active' ? bell(c.k) : 0;
      ctx.visual.vents = { phase: c.phase, k: c.k, positions: h.positions, armed, width: h.width, strength };
      if (c.phase !== 'active') return;
      const half = h.width / 2;
      for (const f of pushable(ctx)) {
        if (!armed.some((px) => Math.abs(f.x - px) < half + f.r)) continue;
        if (f.y > h.reach) continue;                       // the column has a top; above it, nothing
        // Sustained lift, ramped by the bell, so the column has a soft edge in time as well as
        // in space. A fighter standing on the grate is peeled off it; one falling through gets
        // caught. Neither is hitstun, so you keep control the whole way up.
        f.env.updraft += h.lift * strength;
        if (f.onGround) { f.onGround = false; f.platform = null; f.vy = Math.max(f.vy, h.lift * 0.16 * strength); }
      }
    },
  },

  // ---------------------------------------------------------------- SLAG DRIP (Smeltworks)
  // The gantry overhead leaks. Small, frequent, localised — the counterweight to the vents:
  // where the vents make the islands unsafe, the slag makes the free crossing cost something.
  slagfall: {
    step(h, ctx) {
      const s = h.state;
      s.timer = (s.timer || 0) + FRAME;
      s.drops = s.drops || [];
      s.next = (s.next || 0) - FRAME;
      if (s.next <= 0) {
        // From the stage's seeded generator, not Math.random: this is the only stochastic hazard
        // in the game, and one unseeded call makes a whole match unreplayable.
        s.next = h.every * (0.6 + ctx.stage.rng() * 0.8);
        s.drops.push({ x: h.x + (ctx.stage.rng() - 0.5) * h.spread, y: h.from, vy: 0, hit: false, life: 0 });
      }
      for (let i = s.drops.length - 1; i >= 0; i--) {
        const d = s.drops[i];
        d.vy -= 90 * FRAME; d.y += d.vy * FRAME; d.life += FRAME;
        // A drop lands on whatever is under it, splashes, and is gone. It never pools, because a
        // permanent damaging patch on the only crossing would just close the crossing.
        const surf = ctx.stage.surfaceUnder(d.x, d.y);
        if (!d.hit) for (const f of targets(ctx)) {
          if (Math.abs(f.x - d.x) < f.r + 0.5 && d.y > f.y && d.y < f.y + f.h) {
            d.hit = true;
            ctx.match.combat.hazardHit(f, { damage: h.damage, launch: h.launch, angle: 78, x: d.x, y: d.y });
            break;
          }
        }
        if (d.hit || (surf && d.y <= surf.top + 0.4) || d.y < ctx.stage.blast.bottom) {
          if (!d.splash) { d.splash = 1; d.y = surf ? surf.top + 0.3 : d.y; d.vy = 0; }
          d.splash -= FRAME * 4;
          if (d.splash <= 0) s.drops.splice(i, 1);
        }
      }
      ctx.visual.slagfall = { drops: s.drops.map((d) => ({ x: d.x, y: d.y, splash: d.splash || 0 })), from: h.from, x: h.x, spread: h.spread };
    },
  },

  // ---------------------------------------------------------------- SPRINKLER (Rooftops)
  // A burst pipe on the roof. It sweeps, it pushes you the way it is travelling, and — the part
  // that makes it a stage feature rather than a shove — it leaves the roof WET. The jet is four
  // seconds; the slick it leaves behind is ten. Long after the water has gone the fight is still
  // being shaped by where it went.
  sprinkler: {
    step(h, ctx) {
      const s = h.state;
      const c = cyclePhase(s, h.period, h.tick / 60, h.sweepSeconds);
      s.wet = s.wet || [];
      const m = ctx.stage.main;
      if (c.phase === 'active') {
        const dir = (Math.floor(s.timer / h.period) % 2) ? -1 : 1;   // alternates, so neither side is safe
        const from = dir > 0 ? m.x1 - 8 : m.x2 + 8;
        const to = dir > 0 ? m.x2 + 8 : m.x1 - 8;
        s.x = from + (to - from) * smooth(c.k);
        s.dir = dir;
        for (const f of pushable(ctx)) {
          if (f.y < m.top - 8 || f.y > h.height) continue;           // the jet has a top and a bottom
          const d = Math.abs(f.x - s.x);
          if (d > h.radius + f.r) continue;
          const falloff = 1 - d / (h.radius + f.r);
          // Pushed the way the jet is going, not away from it: the sweep herds you toward a ledge
          // rather than shoving you off wherever you happen to stand.
          f.env.windX += dir * h.push * falloff;
          if (!f.onGround) f.env.updraft -= h.push * 0.25 * falloff;
        }
        // lay down the slick behind the jet
        const surf = ctx.stage.surfaceUnder(s.x, m.top + 2);
        if (surf) {
          const cell = Math.round(s.x / 3) * 3;
          const found = s.wet.find((w) => w.x === cell);
          if (found) found.life = h.wetSeconds;
          else s.wet.push({ x: cell, y: surf.top, life: h.wetSeconds });
        }
      } else s.phase = c.phase;
      // Hoisted out of the loop. With ~20-25 live slicks this was calling pushable() once per
      // cell per frame — 50 arrays a frame from one hazard, measured at ~2 KB/frame of heap growth
      // on Rooftops, in a file whose header claims it does not allocate.
      const wetTargets = pushable(ctx);
      for (let i = s.wet.length - 1; i >= 0; i--) {
        const w = s.wet[i];
        w.life -= FRAME;
        if (w.life <= 0) { s.wet.splice(i, 1); continue; }
        for (const f of wetTargets) {
          if (!f.onGround || Math.abs(f.x - w.x) > 2.2 || Math.abs(f.y - w.y) > 1.5) continue;
          const soak = clamp(w.life / h.wetSeconds, 0, 1);
          f.env.traction *= 1 - h.slip * soak;
          f.env.grip *= 1 - h.slip * 0.6 * soak;
        }
      }
      ctx.visual.sprinkler = {
        phase: c.phase, k: c.k, x: s.x || 0, dir: s.dir || 1, radius: h.radius, height: h.height,
        wet: s.wet.map((w) => ({ x: w.x, y: w.y, k: clamp(w.life / h.wetSeconds, 0, 1) })),
      };
    },
  },

  // ---------------------------------------------------------------- ANTENNA ARC (Rooftops)
  // Electricity jumps between the two masts on the high tier. A thin horizontal line of danger
  // near the ceiling, on a long telegraph — it exists so the top of a vertical stage is not
  // simply the safest place to camp.
  antennaarc: {
    step(h, ctx) {
      const s = h.state;
      const c = cyclePhase(s, h.period, h.warn / 60, h.arc / 60);
      s.phase = c.phase;
      if (c.phase === 'active') {
        // Per fighter, not global. A single shared `lastHit` meant the 30-frame cooldown was
        // consumed by whoever was checked first: with four fighters standing in the band the
        // measured damage was 6/0/0/0 then 12/0/0/0 — players 1 through 3 were permanently
        // immune. The whole suite is two-player, which is why 152 green checks never saw it.
        s.lastHit = s.lastHit || {};
        for (const f of targets(ctx)) {
          if (f.x < h.x1 || f.x > h.x2) continue;
          if (f.y + f.h < h.y - h.thickness || f.y > h.y + h.thickness) continue;
          const last = s.lastHit[f.index] ?? -999;
          if (ctx.match.frame - last < 30) continue;
          s.lastHit[f.index] = ctx.match.frame;
          ctx.match.combat.hazardHit(f, { damage: h.damage, launch: h.launch, angle: 88, x: f.x, y: h.y });
        }
      }
      ctx.visual.antennaarc = { phase: c.phase, k: c.k, x1: h.x1, x2: h.x2, y: h.y };
    },
  },

  // ---------------------------------------------------------------- DUST DEVIL (Saltflat)
  // The old one crossed the stage and hit you once for 7%. A whirlwind that touches you once is
  // a moving hitbox with a costume on. This one CARRIES: step inside and you are drawn to the
  // core, lifted, and spun up the funnel until it spits you out of the top. It is terrifying,
  // it does almost no damage, and the whole time you are inside it you still have air control —
  // so a good player rides it across the stage and a panicking one gets thrown out over the pit.
  dustdevil: {
    step(h, ctx) {
      const s = h.state;
      s.timer = (s.timer || 0) + FRAME;
      const t = s.timer % h.period;
      const start = h.period - h.crossSeconds - h.warn;
      const crossStart = h.period - h.crossSeconds;
      const m = ctx.stage.main;
      if (t >= crossStart) {
        if (!s.active) {
          s.active = true;
          s.dir = s.nextDir || 1;
          s.caught = new Map();
        }
        const k = (t - crossStart) / h.crossSeconds;
        // It crosses the ISLAND, not the sky beyond it: 14 studs of overhang put a lifting
        // funnel out over the blast zone, which is the last place a hazard should reach.
        //
        // The east turnaround is pulled in further than the west (`eastStop`) so the funnel never
        // enters the sandfall's column at the mesa lip. Two hazards sharing a strip of ground is
        // not depth, it is noise — a player caught there cannot tell which one is acting on them.
        const east = m.x2 - (h.eastStop || 0) + 5;
        const west = m.x1 + (h.westStop || 0) - 5;
        const from = s.dir > 0 ? west : east;
        const to = s.dir > 0 ? east : west;
        s.x = from + (to - from) * k;
        s.spin = (s.spin || 0) + FRAME * 9;
        for (const f of pushable(ctx)) {
          const dx = f.x - s.x;
          const up = clamp((f.y - m.top) / h.height, 0, 1);
          // The funnel is a cone: narrow at the ground, wide at the top.
          const rAt = h.radius * (0.45 + 0.55 * up);
          if (Math.abs(dx) > rAt + f.r || f.y + f.h < m.top - 2 || f.y > m.top + h.height) {
            s.caught.delete(f.index); continue;
          }
          const held = (s.caught.get(f.index) || 0) + 1;
          s.caught.set(f.index, held);
          const grip = 1 - Math.abs(dx) / (rAt + f.r);
          // pulled toward the core, lifted up it, and dragged along with its travel
          f.env.windX += (-sign(dx) * h.pull * grip) + (s.dir * h.drag * grip);
          f.env.updraft += h.lift * grip;
          if (f.onGround && grip > 0.35) { f.onGround = false; f.platform = null; f.vy = Math.max(f.vy, 10); }
          // Held long enough and it throws you out of the top. One small hit, so the exit reads
          // as an event, and upward so it is a reset and not a ring-out.
          if (held >= h.throwAfter) {
            s.caught.set(f.index, 0);
            ctx.match.combat.hazardHit(f, { damage: h.damage, launch: h.launch, angle: h.angle, x: s.x, y: f.y + 2 });
          }
        }
      } else if (s.active) {
        s.active = false;
        s.nextDir = -s.dir;                                // it comes back the other way
      }
      const warning = t >= start && t < crossStart;
      ctx.visual.dustdevil = {
        active: s.active, warn: warning, warnK: warning ? (t - start) / h.warn : 0,
        x: s.x || 0, dir: s.dir || 1, spin: s.spin || 0, radius: h.radius, height: h.height,
        from: (s.nextDir || 1) > 0 ? m.x1 : m.x2,
      };
    },
  },

  // ---------------------------------------------------------------- SANDFALL (Saltflat)
  // Sand pours off the lip of the mesa in a curtain. It does not hurt; it just makes the space
  // under the mesa a bad place to be, which is exactly the space an edgeguarder wants.
  sandfall: {
    step(h, ctx) {
      const s = h.state;
      const c = cyclePhase(s, h.period, h.warn / 60, h.pourSeconds);
      s.phase = c.phase;
      if (c.phase === 'active') {
        const strength = bell(c.k);
        for (const f of pushable(ctx)) {
          if (Math.abs(f.x - h.x) > h.width / 2 + f.r) continue;
          if (f.y > h.from || f.y + f.h < h.to) continue;
          f.env.updraft -= h.push * strength;               // pushed DOWN, which is the whole point
          f.env.windX += sign(h.x - f.x) * h.push * 0.2 * strength;
        }
      }
      ctx.visual.sandfall = { phase: c.phase, k: c.k, x: h.x, width: h.width, from: h.from, to: h.to };
    },
  },

  // ---------------------------------------------------------------- TIDE (Undertow)
  // Water is not a hazard so much as a second set of physics. In it you are slow, you float, and
  // — the part that makes it interesting — knockback is DAMPED. At 140% the water is the safest
  // place on the stage and also the place you cannot fight from. Deciding when to be in it is
  // the stage.
  tide: {
    step(h, ctx) {
      const s = h.state;
      s.timer = (s.timer || 0) + FRAME;
      const t = s.timer % h.period;
      const riseStart = h.period - (h.rise + h.hold + h.fall);
      let level = h.low, phase = 'low';
      if (t >= riseStart && t < riseStart + h.rise) { level = h.low + (h.high - h.low) * smooth((t - riseStart) / h.rise); phase = 'rising'; }
      else if (t >= riseStart + h.rise && t < riseStart + h.rise + h.hold) { level = h.high; phase = 'high'; }
      else if (t >= riseStart + h.rise + h.hold) { level = h.high - (h.high - h.low) * smooth((t - riseStart - h.rise - h.hold) / h.fall); phase = 'falling'; }
      // a slow swell on top of the tide, so the surface is never a straight line
      s.swell = (s.swell || 0) + FRAME;
      ctx.stage.waterLevel = level;
      const m = ctx.stage.main;
      for (const f of ctx.fighters) {
        if (!f.alive) { f.inWater = false; continue; }
        const surfaceHere = level + Math.sin(s.swell * 1.1 + f.x * 0.12) * h.swell;
        const outside = Math.abs(f.x) > h.edge || f.y < m.bottom;
        const inWater = f.y < surfaceHere && outside;
        f.inWater = inWater;
        if (!inWater) continue;
        if (f.state === 'hitstun' || f.tumbling) continue;
        const under = surfaceHere - f.y;
        // Buoyancy reaches `h.depth` studs down and no further. Without a floor on it the surface
        // was a permanent refuge: a fighter launched into the sea floated back up forever and
        // could not be killed from it. Below the depth you are simply falling, in water.
        // Tapered at the surface and damped, because an undamped spring is not buoyancy. Traced:
        // a passive fighter two studs under at high tide was thrown clear of the water (y 8.4 vs a
        // level of 8.0), fell back in at -11.8, sank past `depth` where buoyancy is zero, and
        // drowned. "Floats you back to the surface" launched you out once and then killed you.
        const depth = clamp(1 - under / h.depth, 0, 1) * clamp(under / 1.5, 0, 1);
        f.env.updraft += h.buoyancy * depth;
        f.vy *= 0.90;                                       // water is viscous; it does not ring
        f.env.windX += sign(f.x || 1) * h.drift;            // and carries you out, slowly
        f.env.damp = Math.min(f.env.damp, h.damp);          // water eats knockback
      }
      ctx.visual.tide = { level, phase, edge: h.edge, swell: s.swell, amp: h.swell };
    },
  },

  // ---------------------------------------------------------------- ROGUE WAVE (Undertow)
  // Only at high tide, and only once. A crest rolls the length of the stage and shoves everyone
  // it passes toward one side. It is the reason high tide is tense rather than just wet.
  roguewave: {
    step(h, ctx) {
      const s = h.state;
      s.timer = (s.timer || 0) + FRAME;
      const t = s.timer % h.period;
      // `at` pins the crossing to a moment in the cycle instead of hanging it off the end of the
      // period. Both this and the tide run on a 34s period, and the tide's hold is t=21..31, but
      // `period - crossSeconds` put the crossing at 30.4 — so the crest entered as the tide was
      // already falling and spent 83% of its travel below the island's own bottom edge, hidden
      // behind the stage. Measured before the fix: 108 of 648 active frames at high tide.
      const crossStart = h.at != null ? h.at : h.period - h.crossSeconds;
      const start = crossStart - h.warn;
      const m = ctx.stage.main;
      if (t >= crossStart && t < crossStart + h.crossSeconds) {
        if (!s.active) { s.active = true; s.dir = s.nextDir || 1; }
        const k = (t - crossStart) / h.crossSeconds;
        const from = s.dir > 0 ? m.x1 - 30 : m.x2 + 30;
        s.x = from + (s.dir > 0 ? 1 : -1) * (m.w + 60) * k;
        const lvl = ctx.stage.waterLevel != null ? ctx.stage.waterLevel : 0;
        for (const f of pushable(ctx)) {
          const d = Math.abs(f.x - s.x);
          if (d > h.width / 2 + f.r) continue;
          if (f.y > lvl + h.crest || f.y + f.h < lvl - 4) continue;
          const g = 1 - d / (h.width / 2 + f.r);
          f.env.windX += s.dir * h.push * g;
          f.env.updraft += h.lift * g;
        }
      } else if (s.active) { s.active = false; s.nextDir = -s.dir; }
      const warning = t >= start && t < crossStart;
      ctx.visual.roguewave = {
        active: s.active, warn: warning, warnK: warning ? (t - start) / h.warn : 0,
        x: s.x || 0, dir: s.dir || 1, width: h.width, crest: h.crest,
      };
    },
  },

  // ---------------------------------------------------------------- CROSSWIND (The Span, ranked)
  // The subtle one. A bridge in the open gets wind; the wind pushes you sideways in the air and
  // never touches you on the ground. No damage, no stun, and it alternates on a long, obvious
  // cycle — but it changes every recovery and every edgeguard on the stage, which is exactly as
  // much as a ranked layout should ever do.
  crosswind: {
    step(h, ctx) {
      const s = h.state;
      s.timer = (s.timer || 0) + FRAME;
      const t = s.timer % h.period;
      const gustStart = h.period - h.gustSeconds;
      const warnStart = gustStart - h.warn;
      let strength = 0, phase = 'calm';
      if (t >= gustStart) { phase = 'gust'; strength = bell((t - gustStart) / h.gustSeconds); }
      else if (t >= warnStart) { phase = 'warn'; }
      if (s.cycleId !== Math.floor(s.timer / h.period)) {
        s.cycleId = Math.floor(s.timer / h.period);
        s.dir = -(s.dir || -1);                            // strictly alternating: learnable
      }
      const dir = s.dir || 1;
      if (phase === 'gust') {
        for (const f of pushable(ctx)) {
          if (f.onGround) continue;                        // grounded play is untouched, deliberately
          f.env.windX += dir * h.push * strength;
        }
      }
      ctx.visual.crosswind = { phase, dir, strength, k: t / h.period };
    },
  },

  // ---------------------------------------------------------------- EMBER DRIFT (Foundry Floor, ranked)
  // The other subtle one, and the harder one to get right. The first version was a single column
  // of rising heat at the CENTRE of the stage — which is the most-used space on the most-used
  // layout, where both players spawn and where all of neutral happens. A permanent physics change
  // there is not subtle, it is the stage. It also made the engine tests flaky, which is what
  // caught it.
  //
  // So the columns sit OFF the stage instead, just outside each ledge, rising from below the
  // floor. Centre-stage neutral is untouched. What changes is edgeguarding: a fighter recovering
  // low gets a little help in the last few studs, and the player chasing them has to decide
  // whether to follow into the column. Learnable, fixed, never damages, and it only ever slows a
  // FALL — it cannot boost a rise, so it is not a free extra jump.
  emberdrift: {
    step(h, ctx) {
      const s = h.state;
      s.timer = (s.timer || 0) + FRAME;
      const pulse = 0.75 + 0.25 * Math.sin(s.timer * 0.9);   // a slow breathe, never a surprise
      for (const f of pushable(ctx)) {
        if (f.onGround) continue;
        if (f.y < h.from || f.y > h.to) continue;
        if (!h.positions.some((px) => Math.abs(f.x - px) < h.width / 2 + f.r)) continue;
        if (f.vy < 0) f.env.updraft += h.lift * pulse;
      }
      ctx.visual.emberdrift = { positions: h.positions, width: h.width, from: h.from, to: h.to, pulse, t: s.timer };
    },
  },
};

export function stepHazard(h, ctx) {
  const def = HAZARDS[h.type];
  if (!def) return;
  if (!h.state) h.state = {};
  def.step(h, ctx);
}

export { clamp, bell, smooth };
