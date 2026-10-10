// Hit and impact effects: what each match event throws on screen - sparks, impact rings, screen
// shake - as pure data, so both builds show the same thing (roblox/src/client/Effects.luau, held
// to this by tests/effects-parity.luau). This used to live inline in renderer2d.js, which is how
// the Roblox build shipped with none of it: hitting a bot there produced no spark, no ring and no
// shake at all.
//
// Randomness is injected (`rand()` in [0,1)), so the parity test can feed both builds the same
// numbers; in play each build uses its own generator, which is fine - sparks are not simulation.
//
// State is { parts, rings, shake }. spawnEffect adds to it for one event, stepEffect advances it,
// effectShapes lists what to draw: ['r', x, y, w, h, colour, alpha] and ['l', x0, y0, x1, y1,
// width, colour, alpha] in world units, y up.

const PI = Math.PI;
export const PLAYER_TINT = ['#5FBF4B', '#E8862E', '#4A90D9', '#9A6BD6'];
export const GRAVITY = 26;       // studs/s^2 on a spark
export const SHAKE_DECAY = 9;    // shake units per second
export const RING_SEGMENTS = 16;

export function newEffects() { return { parts: [], rings: [], shake: 0, shields: {} }; }
export const SHIELD_FLARE = 0.3;   // seconds a struck shield flares where it was hit

// The last impact on fighter i's shield, as render2d/shield.js takes it: { k: 1 fresh .. 0, x, y }.
export function shieldHit(fx, i) {
  const s = fx.shields && fx.shields[i];
  return s ? { k: s.life / s.max, x: s.x, y: s.y } : null;
}

// `glow(i)` is fighter i's weapon glow colour (or null), and `height(i)` their height in studs: a
// fighter's own events carry their centre, and dust belongs at their feet.
export const DUST = '#D9D2C2';
export function spawnEffect(fx, e, glow, rand, height = () => 5) {
  const feet = () => e.y - height(e.fighter) / 2;
  // dust thrown sideways along the floor, never much above it
  const dust = (x, y, n, spread, lift, life, size) => {
    for (let i = 0; i < n; i++) {
      const vx = (rand() - 0.5) * 2 * spread, vy = lift * (0.4 + rand() * 0.6);
      fx.parts.push({ x: x + (rand() - 0.5) * 0.8, y, vx, vy, life: life * (0.7 + rand() * 0.5), max: life, c: DUST, s: size });
    }
  };
  const push = (x, y, n, c, sp, life, size) => {
    for (let i = 0; i < n; i++) {
      const a = rand() * PI * 2, s = sp * (0.4 + rand() * 0.8);
      fx.parts.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: life * (0.6 + rand() * 0.7), max: life, c, s: size });
    }
  };
  const ring = (x, y, r, life, c, heavy, rot) => fx.rings.push({ x, y, r, life, max: life, c, heavy, rot });
  const shake = (v) => { fx.shake = Math.max(fx.shake, v); };
  switch (e.type) {
    case 'hit': {
      const heavy = !!e.heavy;
      const col = glow(e.attacker) || '#FFFFFF';
      push(e.x, e.y, heavy ? 16 : 7, col, heavy ? 26 : 14, heavy ? 0.5 : 0.28, heavy ? 0.32 : 0.2);
      push(e.x, e.y, heavy ? 8 : 4, '#FFFFFF', heavy ? 18 : 10, 0.24, 0.22);
      if (heavy) { ring(e.x, e.y, 2.6, 0.34, col, true, rand() * PI); shake(0.5); } else shake(0.14);
      break;
    }
    case 'explosion':
      push(e.x, e.y, 22, '#FFC44D', 30, 0.5, 0.34); ring(e.x, e.y, e.radius || 3, 0.4, '#FFD37A', true, 0); shake(0.7); break;
    case 'block':
      // Energy dispersing off the shell where it was struck - the user's reference - and the
      // struck point remembered so the shell can flare there (render2d/shield.js).
      push(e.x, e.y, 6, e.perfect ? '#FFFFFF' : '#9FD1E8', 12, 0.25, 0.2);
      push(e.x, e.y, e.perfect ? 18 : 12, '#7FE8FF', 20, 0.35, 0.18);
      if (e.victim != null) fx.shields[e.victim] = { life: SHIELD_FLARE, max: SHIELD_FLARE, x: e.x, y: e.y };
      break;
    case 'ko': {
      const c = PLAYER_TINT[e.fighter % 4];
      push(e.x, e.y, 28, c, 34, 0.7, 0.4); ring(e.x, e.y, 4, 0.5, c, true, 0); shake(1.0); break;
    }
    case 'projectile': case 'beam':
      push(e.x, e.y, 5, '#FFF3D0', 10, 0.2, 0.18); break;
    case 'land':
      if (e.hard) { push(e.x, e.y, 8, '#D9C9A8', 12, 0.3, 0.24); shake(0.35); }
      else dust(e.x, feet(), 5, 5, 1.5, 0.26, 0.34);   // a soft landing still meets the floor
      break;
    case 'ultimate':
      push(e.x, e.y, 30, glow(e.fighter) || '#FFFFFF', 30, 0.6, 0.4); shake(1.4); break;
    case 'ultready': shake(0.2); break;
    case 'soulescape': push(e.x, e.y, 12, '#FFFFFF', 24, 0.35, 0.26); break;
    case 'crater':
      // rock and light thrown out of the floor where the greatsword landed
      push(e.x, e.y, e.first ? 26 : 12, '#5A4A3E', e.first ? 26 : 17, 0.55, e.first ? 0.42 : 0.3);
      push(e.x, e.y, e.first ? 18 : 8, '#FFB43C', e.first ? 30 : 20, 0.42, 0.3);
      ring(e.x, e.y, e.radius, 0.32, '#FFD37A', true, 0); shake(e.first ? 1.1 : 0.35); break;
    case 'rundown':
      // each dash arrives as a burst of impact at the target, and the last one is the send
      push(e.x, e.y, e.last ? 26 : 12, '#FFE9C4', e.last ? 30 : 18, 0.36, e.last ? 0.4 : 0.26);
      push(e.x, e.y, e.last ? 14 : 6, '#FF9A4A', e.last ? 24 : 14, 0.3, 0.24);
      ring(e.x, e.y, e.last ? 4.6 : 2.8, 0.26, '#FFC98A', !!e.last, rand() * PI); shake(e.last ? 0.9 : 0.28); break;
    case 'upheaval':
      // a column of floor coming up, so the debris is thrown UPWARD rather than outward
      for (let i = 0; i < 22; i++) {
        fx.parts.push({ x: e.x + (rand() - 0.5) * 4.6, y: e.y + rand() * 2, vx: (rand() - 0.5) * 8, vy: 22 + rand() * 26,
          life: 0.6, max: 0.6, c: i % 3 ? '#8A94A6' : '#4A4038', s: 0.22 + rand() * 0.3 });
      }
      ring(e.x, e.y + 3.5, 3.4, 0.3, '#D8DCE2', true, PI / 2); shake(0.7); break;
    case 'heartseeker': push(e.x, e.y, 16, '#8EE86A', 34, 0.3, 0.22); shake(0.5); break;
    case 'anchorset': push(e.x, e.y, 20, '#6E7684', 20, 0.42, 0.3); ring(e.x, e.y, 2.4, 0.3, '#C86AE8', true, 0); shake(0.45); break;
    case 'anchorsnap': push(e.x, e.y, 26, '#C86AE8', 30, 0.45, 0.32); ring(e.x, e.y, 4.2, 0.34, '#D8B0F0', true, 0); shake(1.0); break;
    case 'aegis':
      // their own damage, coming back at them
      push(e.x, e.y, 18, '#7FD4FF', 26, 0.38, 0.28); ring(e.x, e.y, 3.0, 0.28, '#FFFFFF', true, 0); shake(0.55); break;
    case 'aegisbreak': push(e.x, e.y, 30, '#FFFFFF', 34, 0.45, 0.34); ring(e.x, e.y, 5.4, 0.36, '#7FD4FF', true, 0); shake(1.1); break;
    case 'bleedmark':
      // a mark landing: small, and it stacks visibly so the player can count what they are owed
      for (let i = 0; i < 4; i++) {
        fx.parts.push({ x: e.x + (rand() - 0.5) * 1.6, y: e.y + (rand() - 0.5) * 2, vx: (rand() - 0.5) * 6, vy: 4 + rand() * 8,
          life: 0.4, max: 0.4, c: '#FF4A6A', s: 0.2 });
      }
      break;
    case 'exsanguinate': {
      // and the collection: one burst per victim, sized by what they were carrying
      const n = Math.min(12, e.marks);
      push(e.x, e.y, 10 + n * 3, '#FF4A6A', 22 + n * 2, 0.5, 0.3); ring(e.x, e.y, 1.8 + n * 0.32, 0.34, '#FFFFFF', true, 0);
      shake(0.4 + n * 0.06); break;
    }
    case 'soulgrab': push(e.x, e.y, 14, '#C79BFF', 20, 0.4, 0.26); break;
    case 'soulorb':
      // matter being dragged inward: particles spawned OUTSIDE and pulled to the centre
      if (rand() < 0.7) {
        const a = rand() * PI * 2, d = 5 + rand() * 4;
        fx.parts.push({ x: e.x + Math.cos(a) * d, y: e.y + Math.sin(a) * d, vx: -Math.cos(a) * d * 2.4, vy: -Math.sin(a) * d * 2.4,
          life: 0.4, max: 0.4, c: '#B36BFF', s: 0.2 });
      }
      break;
    case 'soulburst':
      push(e.x, e.y, 34, '#C79BFF', 40, 0.6, 0.4); push(e.x, e.y, 14, '#FFFFFF', 26, 0.35, 0.26);
      ring(e.x, e.y, e.radius, 0.45, '#B36BFF', true, 0); ring(e.x, e.y, e.radius * 1.7, 0.3, '#150B22', true, 0); shake(1.2); break;
    case 'snipe': push(e.x, e.y, 9, '#FFF3D0', 16, 0.24, 0.24); shake(0.4); break;
    case 'starfall': push(e.x, e.y, 6, '#B36BFF', 8, 0.35, 0.22); break;
    case 'mark': shake(0.25); break;
    case 'counter': case 'freeze': case 'summonbreak': push(e.x, e.y, 10, '#FFFFFF', 16, 0.3, 0.22); break;
    // Movement, which the web never marked at all: dust off the floor, rings in the air.
    case 'jump': dust(e.x, feet(), 8, 7, 3, 0.34, 0.42); break;
    case 'doublejump': dust(e.x, feet(), 5, 5, -2, 0.28, 0.34); ring(e.x, feet(), 1.3, 0.22, '#FFFFFF', false, 0); break;
    case 'dash': dust(e.x, feet(), 9, 10, 2, 0.36, 0.44); break;
    case 'dodge': ring(e.x, e.y, 2.0, 0.2, '#BFE6FF', false, 0); break;
    case 'ledge': dust(e.x, e.y, 4, 3, 1, 0.28, 0.3); break;
    case 'tech': push(e.x, e.y, 8, '#FFFFFF', 14, 0.26, 0.22); ring(e.x, e.y, 2.2, 0.26, '#FFFFFF', false, 0); break;
    // Impacts the web left silent.
    case 'shieldbreak': push(e.x, e.y, 24, '#9FD1E8', 28, 0.55, 0.3); ring(e.x, e.y, 4, 0.4, '#FFFFFF', true, 0); shake(0.8); break;
    case 'grabhit': push(e.x, e.y, 8, '#FFE9C4', 12, 0.25, 0.22); shake(0.2); break;
    case 'itembreak': case 'projectilebreak': push(e.x, e.y, 10, '#C9B79C', 14, 0.35, 0.24); break;
    case 'spring':
      for (let i = 0; i < 10; i++) {
        fx.parts.push({ x: e.x + (rand() - 0.5) * 2, y: e.y, vx: (rand() - 0.5) * 6, vy: 14 + rand() * 12, life: 0.4, max: 0.4, c: '#FFD37A', s: 0.24 });
      }
      break;
    case 'teleport': push(e.x, e.y, 12, '#B36BFF', 16, 0.35, 0.24); ring(e.x, e.y, 2.5, 0.3, '#B36BFF', false, 0); break;
    case 'pickup': push(e.x, e.y, 6, '#FFD58A', 8, 0.3, 0.2); break;
    default: break;
  }
}

// Advance by dt seconds, dropping what has burned out. Sparks fall; rings only age; shake decays.
export function stepEffect(fx, dt) {
  const parts = [];
  for (const p of fx.parts) {
    p.life -= dt;
    if (p.life <= 0) continue;
    p.x += p.vx * dt; p.y += p.vy * dt; p.vy -= GRAVITY * dt;
    parts.push(p);
  }
  fx.parts = parts;
  fx.rings = fx.rings.filter((r) => { r.life -= dt; return r.life > 0; });
  fx.shake = Math.max(0, fx.shake - dt * SHAKE_DECAY);
  for (const k of Object.keys(fx.shields)) {
    fx.shields[k].life -= dt;
    if (fx.shields[k].life <= 0) delete fx.shields[k];
  }
}

const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
// What to draw. A spark is a square fading with its life; a ring grows and thins as it fades,
// drawn as RING_SEGMENTS chords (Roblox UI has no arc), and a heavy ring throws eight spokes.
export function effectShapes(fx) {
  const out = [];
  for (const p of fx.parts) out.push(['r', p.x - p.s / 2, p.y - p.s / 2, p.s, p.s, p.c, clamp01(p.life / p.max)]);
  for (const s of fx.rings) {
    const k = 1 - s.life / s.max;
    const a = (1 - k) * 0.9;
    const r = s.r * (0.35 + k * 1.5);
    const w = 0.5 * (1 - k) + 0.12;
    for (let i = 0; i < RING_SEGMENTS; i++) {
      const a0 = (i / RING_SEGMENTS) * PI * 2, a1 = ((i + 1) / RING_SEGMENTS) * PI * 2;
      out.push(['l', s.x + Math.cos(a0) * r, s.y + Math.sin(a0) * r, s.x + Math.cos(a1) * r, s.y + Math.sin(a1) * r, w, s.c, a]);
    }
    if (s.heavy) {
      for (let n = 0; n < 8; n++) {
        const ang = (n / 8) * PI * 2 + s.rot;
        const r0 = s.r * (0.5 + k * 1.2), r1 = r0 + s.r * 0.8 * (1 - k);
        out.push(['l', s.x + Math.cos(ang) * r0, s.y + Math.sin(ang) * r0, s.x + Math.cos(ang) * r1, s.y + Math.sin(ang) * r1, 0.22 * (1 - k), s.c, a]);
      }
    }
  }
  return out;
}

// Grit kicked backwards where a hauled weapon's head scrapes the floor (the axe, the hammer):
// more of it the faster the fighter is hauling. Called once per drawn frame while it scrapes.
export function dragDirt(fx, x, floor, facing, vx, scrape, tertiary, rand) {
  if (rand() >= 0.25 + scrape * 0.75) return;
  fx.parts.push({ x, y: floor + 0.1, vx: -facing * (2 + rand() * 7) - vx * 0.12, vy: 1 + rand() * 5,
    life: 0.3 + rand() * 0.3, max: 0.6, c: rand() < 0.5 ? tertiary : '#6B5A44', s: 0.16 + rand() * 0.18 });
}

// Sparks trailing a bolt (the orb projectiles). Called once per drawn frame per orb.
export function orbSparks(fx, x, y, vx, glow, rand) {
  if (rand() >= 0.5) return;
  fx.parts.push({ x, y, vx: -vx * 0.08 + (rand() - 0.5) * 2, vy: (rand() - 0.5) * 2, life: 0.28, max: 0.28, c: glow || '#7DE8FF', s: 0.16 });
}
