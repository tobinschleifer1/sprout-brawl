import { FRAME, GRAVITY, GRAB, GROUND_POUND, LEDGE, SHIELD, ITEMS as ITEM_CFG } from '../config.js';
import { launchSpeed, hitlag as hitlagFor } from './knockback.js';
import { ITEMS, ITEM_LIST } from '../data/items.js';

const overlap = (a, b) => a.x1 < b.x2 && a.x2 > b.x1 && a.y1 < b.y2 && a.y2 > b.y1;
const rectFrom = (cx, cy, w, h) => ({ x1: cx - w / 2, x2: cx + w / 2, y1: cy - h / 2, y2: cy + h / 2, cx, cy, w, h });
const sign = (v) => (v < 0 ? -1 : 1);

const DIVE_MOVE = { id: 'GroundPound', label: 'Ground Pound', ...GROUND_POUND.dive, heavy: true, kind: 'melee', hitboxes: [{ frames: [1, 999], ...GROUND_POUND.dive.hitbox }] };
const LEDGE_ATTACK = { id: 'LedgeAttack', label: 'Ledge Attack', damage: LEDGE.options.attack.damage, base: LEDGE.options.attack.base, growth: LEDGE.options.attack.growth, angle: LEDGE.options.attack.angle, kind: 'melee', hitboxes: [LEDGE.options.attack.hitbox] };
const WALL_MOVE = { id: 'Trellis', damage: 5, base: 8, growth: 0, angle: 80, kind: 'summon', extraHitstun: 6 };
const CLOUD_MOVE = { id: 'SporeCloud', damage: 2, base: 8, growth: 0, angle: 80, kind: 'summon', applies: { slow: 12 } };
const NODE_MOVE = { id: 'NodeTick', damage: 1, base: 3, growth: 0, angle: 80, kind: 'summon' };

export class Combat {
  constructor(match) {
    this.match = match;
    this.projectiles = []; this.summons = []; this.bursts = []; this.items = [];
    this.events = []; this.debugBoxes = [];
    this.itemTimer = 0;
  }
  get fighters() { return this.match.fighters; }
  get stage() { return this.match.stage; }
  emit(e) { this.events.push(e); }
  sameTeam(a, b) { return a.team === b.team; }
  enemiesOf(f) { return this.fighters.filter((v) => v !== f && v.alive && !this.sameTeam(f, v)); }

  hitboxRect(f, hb) {
    const rm = f.rangeMul || 1;
    return rectFrom(f.x + hb.offset[0] * rm * f.facing, f.y + hb.offset[1], hb.size[0] * rm, hb.size[1]);
  }

  activeHitboxes(f) {
    const out = [];
    if (f.state === 'attack' && f.move) {
      const fa = f.moveFrameAbs;
      for (const hb of f.move.hitboxes) if (fa >= hb.frames[0] && fa <= hb.frames[1]) out.push({ rect: this.hitboxRect(f, hb), hb, move: f.move });
    } else if (f.state === 'groundpound' && f.sf > GROUND_POUND.hang) {
      const hb = DIVE_MOVE.hitboxes[0];
      out.push({ rect: this.hitboxRect(f, hb), hb, move: DIVE_MOVE });
    } else if (f.state === 'ledgeaction' && f.la && f.la.kind === 'attack') {
      const hb = LEDGE_ATTACK.hitboxes[0];
      if (f.sf >= hb.frames[0] && f.sf <= hb.frames[1]) out.push({ rect: this.hitboxRect(f, hb), hb, move: LEDGE_ATTACK });
    }
    return out;
  }

  step() {
    this.debugBoxes = [];
    for (const f of this.fighters) {
      // Hitlag freezes the attacker, including its frame counter. Evaluating hitboxes during it
      // would let one active frame connect over and over.
      if (!f.alive || f.hitlag > 0) continue;
      for (const b of this.activeHitboxes(f)) {
        this.debugBoxes.push({ rect: b.rect, kind: 'hit' });
        const frameKey = f.state === 'attack' ? f.mf : f.sf;
        for (const v of this.fighters) {
          if (v === f || !v.alive || this.sameTeam(f, v)) continue;
          if (!overlap(b.rect, v.hurtbox)) continue;
          const last = f.hitVictims.get(v.index);
          if (last != null && (!b.hb.rehitEvery || frameKey - last < b.hb.rehitEvery)) continue;
          f.hitVictims.set(v.index, frameKey);
          this.resolveHit(f, v, b.move, b.hb, b.rect, {});
        }
        for (const s of [...this.summons]) {
          if (s.destructible && s.owner !== f && !this.sameTeam(s.owner, f) && overlap(b.rect, s.rect) && (b.hb.damage ?? b.move.damage) >= 4) this.destroySummon(s);
        }
      }
      if (f.state === 'attack' && f.move && f.move.kind === 'spray' && f.moveActive) this.sprayFrame(f);
    }
    this.stepProjectiles();
    this.stepSummons();
    this.stepBursts();
    this.stepItems();
  }

  // ---------- hit resolution ----------
  resolveHit(attacker, victim, move, hb, rect, opts) {
    if (!victim.alive || victim.untouchable) return false;
    if (victim.state === 'grabbed' && move.kind === 'grab') return false;
    const direct = !opts.projectile && !opts.summon;
    let damage = (hb && hb.damage != null ? hb.damage : move.damage) + (direct ? (attacker.bonusDamage || 0) : 0);
    let base = hb && hb.base != null ? hb.base : move.base;
    let growth = hb && hb.growth != null ? hb.growth : move.growth;
    if (direct && attacker.chargeMods && attacker.move === move) { damage += attacker.chargeMods.damage; base = attacker.chargeMods.base; growth = attacker.chargeMods.growth; }
    const cx = rect ? (rect.x1 + rect.x2) / 2 : victim.x, cy = rect ? (rect.y1 + rect.y2) / 2 : victim.cy;
    const isMelee = direct && move.kind !== 'grab' && !opts.item;

    // Counter window
    if (victim.state === 'attack' && victim.move && victim.move.kind === 'counter' && victim.moveActive && move.kind !== 'grab' && !opts.chip) {
      victim.triggerCounter(damage);
      if (direct) attacker.hitlag = 8;
      this.emit({ type: 'counter', x: victim.x, y: victim.cy });
      return true;
    }
    // Armour (Barrel Roll)
    if (victim.state === 'attack' && victim.move && victim.move.armor && victim.moveActive && !victim.armorUsed && damage < victim.move.armor) {
      victim.armorUsed = true; victim.percent = Math.min(999, victim.percent + damage);
      if (direct) { attacker.hitlag = hitlagFor(damage); attacker.moveLanded = true; }
      this.emit({ type: 'armor', x: cx, y: cy });
      return true;
    }
    // Shield
    if (victim.state === 'shield' && !move.unblockable && move.kind !== 'grab' && !opts.chip) {
      const perfect = victim.sf <= SHIELD.perfectFrames;
      victim.applyBlock({ damage, facing: opts.facing ?? attacker.facing, perfect });
      if (direct) { attacker.hitlag = hitlagFor(damage, move.heavy); attacker.moveLanded = true; }
      this.emit({ type: 'block', x: cx, y: cy, perfect, victim: victim.index });
      return true;
    }
    // Command grab
    if (move.kind === 'grab') {
      if (!victim.onGround) return false;
      if (victim.state === 'holding') victim.releaseHold();
      attacker.startHold(victim, { reel: move.reelFrames || 0, throwData: { damage: move.damage + (attacker.bonusDamage || 0), base, growth, angle: move.angle, behind: !!move.behind }, tangle: attacker.mech.id === 'Tangle' });
      return true;
    }
    if (opts.chip) {
      victim.percent = Math.min(999, victim.percent + damage);
      victim.stats.damageTaken += damage; attacker.stats.damageDealt += damage;
      this.emit({ type: 'chip', x: cx, y: cy, damage });
      return true;
    }
    const angle = hb && hb.angle != null ? hb.angle : move.angle;
    let launch = launchSpeed(base, growth, damage, victim.percent + damage, victim.weight) * (direct ? (attacker.launchMul || 1) : 1);
    if (opts.fixedLaunch != null) launch = opts.fixedLaunch;
    const facing = move.behind ? -attacker.facing : (opts.facing ?? attacker.facing);
    const hl = hitlagFor(damage, move.heavy);
    if (direct) { attacker.hitlag = hl; attacker.moveLanded = true; }
    attacker.stats.damageDealt += damage;
    victim.applyHit({ damage, launch, angle, facing, attacker, hitlag: opts.summon ? Math.min(hl, 4) : hl, extraHitstun: move.extraHitstun || 0, applies: move.applies, pull: move.pullVictim, attackerX: attacker.x, trip: move.trip });
    if (direct && move.onHit) {
      if (move.onHit.bounce && !attacker.onGround) { attacker.vy = move.onHit.bounce; attacker.fastFalling = false; }
      if (move.onHit.regainJump) attacker.jumpsLeft = Math.max(attacker.jumpsLeft, 1);
      if (move.onHit.regainAirDodge) attacker.airDodgeUsed = false;
    }
    if (direct && move.dragVictim && hb && hb.rehitEvery && victim.pendingLaunch) victim.pendingLaunch = { vx: attacker.vx * 0.95, vy: 6 };
    this.onHitLanded(attacker, victim, move, isMelee);
    if (victim.item && damage >= ITEM_CFG.knockOutDamage) this.dropItem(victim, true);
    this.emit({ type: 'hit', x: cx, y: cy, damage, launch, heavy: !!move.heavy, weight: victim.weight, attacker: attacker.index, victim: victim.index, angle, facing });
    return true;
  }

  onHitLanded(attacker, victim, move, isMelee) {
    if (attacker.mech.id === 'Bloom') attacker.mech.hits.push(attacker.frameCount);
    if (victim.mech.id === 'Spines' && isMelee) { attacker.percent = Math.min(999, attacker.percent + victim.char.mechanic.recoil); this.emit({ type: 'recoil', x: attacker.x, y: attacker.cy }); }
  }

  resolveThrow(attacker, victim, td, tangle) {
    const damage = td.damage + (attacker.bonusDamage || 0);
    let facing = attacker.facing;
    if (td.behind) { facing = -attacker.facing; if (!td.keepFacing && !attacker.move) attacker.facing = facing; }
    victim.x = attacker.x + facing * (attacker.r + victim.r + 0.5); victim.y = attacker.y + 0.3;
    victim.holder = null;
    const launch = launchSpeed(td.base, td.growth, damage, victim.percent + damage, victim.weight) * (attacker.launchMul || 1);
    victim.onGround = false; victim.platform = null;
    victim.applyHit({ damage, launch, angle: td.angle, facing, attacker, hitlag: hitlagFor(damage, true) });
    victim.hitlag = 2;
    if (tangle) victim._applyEffects({ tangle: 1 });
    attacker.stats.damageDealt += damage;
    this.emit({ type: 'hit', x: victim.x, y: victim.cy, damage, launch, heavy: true, weight: victim.weight, attacker: attacker.index, victim: victim.index, angle: td.angle, facing, throw: true });
  }

  checkGrab(f) {
    const rect = this.hitboxRect(f, GRAB.hitbox);
    this.debugBoxes.push({ rect, kind: 'grab' });
    for (const v of this.fighters) {
      if (v === f || !v.alive || this.sameTeam(f, v) || !v.onGround || v.untouchable) continue;
      if (['grabbed', 'holding', 'ko', 'respawn', 'ledge'].includes(v.state)) continue;
      if (!overlap(rect, v.hurtbox)) continue;
      if (v.hold) v.releaseHold();
      f.startHold(v, { tangle: f.mech.id === 'Tangle' });
      return;
    }
  }

  hazardHit(f, p) {
    if (f.untouchable) return;
    const facing = sign(f.x - p.x || 1);
    f.applyHit({ damage: p.damage, launch: p.launch, angle: p.angle, facing, attacker: null, hitlag: 6 });
    this.emit({ type: 'hit', x: f.x, y: f.cy, damage: p.damage, launch: p.launch, heavy: false, weight: f.weight, attacker: -1, victim: f.index, angle: p.angle, facing });
  }

  // ---------- move triggers ----------
  onMoveActive(f, m) {
    if (m.kind === 'beam' && m.charge) {
      const k = Math.min(1, f.charge / m.charge.maxHold);
      const lerp = (a, b) => a + (b - a) * k;
      f.chargeMods = { damage: Math.round(lerp(m.damage, m.charge.damage)) - m.damage, base: lerp(m.base, m.charge.base), growth: lerp(m.growth, m.charge.growth) };
      this.emit({ type: 'beam', x: f.x, y: f.y + 3.6, facing: f.facing, charge: k, frames: m.active });
      return;
    }
    f.chargeMods = null;
    if (m.kind === 'burst') { this.emit({ type: 'burst', x: f.x, y: f.y + 3, radius: 7, frames: m.active }); return; }
    if (m.kind === 'projectile') { this.spawnProjectile(f, m); return; }
    if (m.kind === 'summon') { this.spawnSummon(f, m); return; }
    if (m.kind === 'pulse') {
      for (const n of this.nodesOf(f)) this.spawnBurst(f, { x: n.x, y: n.y + 1.5, damage: m.damage, base: m.base, growth: m.growth, angle: m.angle, frames: m.active, size: [m.pulse.radius * 2, m.pulse.radius * 2], heavy: true });
      this.emit({ type: 'pulse', nodes: this.nodesOf(f).map((n) => ({ x: n.x, y: n.y })) });
      return;
    }
    if (m.kind === 'freeze') {
      const M = f.char.mechanic;
      for (const v of this.enemiesOf(f)) {
        if (v.untouchable || v.effects.chill.stacks < 3) continue;
        if (Math.hypot(v.x - f.x, v.cy - f.cy) > m.freeze.range) continue;
        v.percent = Math.min(999, v.percent + m.damage); v.stats.damageTaken += m.damage; f.stats.damageDealt += m.damage;
        v.effects.chill.stacks = 0;
        v.freeze(M.freezeFrames);
        f.moveLanded = true;
        this.emit({ type: 'freeze', x: v.x, y: v.cy, victim: v.index });
        break;
      }
      return;
    }
  }

  onMoveActiveFrame(f, m) {
    if (m.kind === 'volley') {
      const p = m.projectile;
      const k = f.mf - f.startupEff - 1;
      if (k % p.every === 0 && f.volleyCount < p.count && f.mech.spines > 0) {
        f.mech.spines--; f.volleyCount++;
        this.spawnProjectile(f, m, { yJitter: (f.volleyCount - 3) * 0.35 });
      }
    } else if (m.kind === 'field') {
      const F = m.field;
      if (!f.fieldThrew || f.mf === f.startupEff + 1) f.fieldThrew = new Set();
      for (const v of this.enemiesOf(f)) {
        if (v.untouchable || !v.onGround || v.state === 'grabbed' || f.fieldThrew.has(v.index)) continue;
        const dx = f.x - v.x, ad = Math.abs(dx);
        if (ad > F.radius) continue;
        if (ad <= F.throwRange + v.r + f.r) {
          f.fieldThrew.add(v.index);
          this.resolveHit(f, v, { ...m, kind: 'melee', unblockable: true }, null, rectFrom(v.x, v.cy, 2, 2), { facing: sign(v.x - f.x) });
        } else {
          v.x += sign(dx) * Math.min(ad, F.pullSpeed * FRAME);
          if (v.state === 'idle' || v.state === 'run') v.vx *= 0.5;
        }
      }
    }
  }

  sprayFrame(f) {
    const def = f.item ? f.item.def : ITEMS.WateringCan;
    const S = def.spray;
    const rect = rectFrom(f.x + f.facing * (S.range / 2 + 1), f.y + 2, S.range, S.height);
    this.debugBoxes.push({ rect, kind: 'push' });
    for (const v of this.enemiesOf(f)) {
      if (v.untouchable || !overlap(rect, v.hurtbox)) continue;
      const target = f.facing * S.push;
      if (f.facing > 0 ? v.vx < target : v.vx > target) v.vx += f.facing * 2.5;
      if (v.onGround && (v.state === 'idle' || v.state === 'run')) v.x += f.facing * S.push * FRAME;
    }
    if (f.item) { f.item.uses--; if (f.item.uses <= 0) { f.item.uses = 0; f.endMove(); } }
    this.emit({ type: 'spray', x: f.x + f.facing * 2, y: f.y + 3, facing: f.facing });
  }

  // ---------- projectiles ----------
  spawnProjectile(f, m, extra = {}) {
    const p = m.projectile;
    const rm = f.rangeMul || 1;
    const pr = {
      owner: f, move: m, x: f.x + p.spawnOffset[0] * f.facing, y: f.y + p.spawnOffset[1] + (extra.yJitter || 0),
      vx: f.facing * p.speed, vy: 0, w: p.size[0], h: p.size[1], life: Math.round(p.lifetime * rm), shape: p.shape || 'bolt',
      grounded: !!p.grounded, gravity: 0, hitVictims: new Set(), facing: f.facing, item: false, bloom: rm > 1,
    };
    pr.rect = rectFrom(pr.x, pr.y, pr.w, pr.h);
    this.projectiles.push(pr);
    this.emit({ type: 'projectile', shape: pr.shape, x: pr.x, y: pr.y });
    return pr;
  }

  stepProjectiles() {
    const m = this.stage.main;
    for (let i = this.projectiles.length - 1; i >= 0; i--) {
      const p = this.projectiles[i];
      const px = p.x, py = p.y;
      if (p.gravity) p.vy -= p.gravity * FRAME;
      p.x += p.vx * FRAME; p.y += p.vy * FRAME; p.life--;
      p.rect = rectFrom(p.x, p.y, p.w, p.h);
      this.debugBoxes.push({ rect: p.rect, kind: 'proj' });
      let dead = p.life <= 0;
      // stage body
      const inMain = p.x > m.x1 && p.x < m.x2 && p.y < m.top && p.y > m.bottom;
      if (inMain && !p.grounded) { dead = true; if (p.explode) this.explode(p); }
      // landing for lobbed items
      if (p.gravity && p.vy <= 0) {
        for (const pl of this.stage.platforms) {
          if (p.x > pl.x1 && p.x < pl.x2 && py >= pl.top - 0.2 && p.y < pl.top + 0.2) { dead = true; if (p.explode) this.explode(p); break; }
        }
      }
      // thorn walls stop projectiles
      for (const s of this.summons) {
        if (s.type === 'wall' && s.owner !== p.owner && !this.sameTeam(s.owner, p.owner) && overlap(p.rect, s.rect)) { dead = true; this.emit({ type: 'projectilebreak', x: p.x, y: p.y }); }
        if (s.destructible && s.owner !== p.owner && !this.sameTeam(s.owner, p.owner) && overlap(p.rect, s.rect) && p.move.damage >= 4) { this.destroySummon(s); dead = true; }
      }
      if (!dead) {
        for (const v of this.fighters) {
          if (v === p.owner || !v.alive || this.sameTeam(p.owner, v) || v.untouchable || p.hitVictims.has(v.index)) continue;
          if (!overlap(p.rect, v.hurtbox)) continue;
          // catching a seed bomb
          if (p.explode && v.buffer.guard > 0 && !v.item && ['air', 'idle', 'run'].includes(v.state)) {
            v.buffer.guard = 0; this.giveItem(v, ITEMS.SeedBomb); dead = true; this.emit({ type: 'catch', x: v.x, y: v.cy }); break;
          }
          p.hitVictims.add(v.index);
          if (p.explode) { this.explode(p); dead = true; break; }
          const hit = this.resolveHit(p.owner, v, p.move, { angle: p.move.angle }, p.rect, { projectile: true, facing: sign(p.vx), item: p.item });
          if (hit) { dead = true; break; }
        }
      }
      if (p.y < this.stage.blast.bottom - 10 || Math.abs(p.x) > 200) dead = true;
      if (dead) this.projectiles.splice(i, 1);
    }
  }

  explode(p) {
    const e = p.explode;
    this.spawnBurst(p.owner, { x: p.x, y: p.y, damage: e.damage, base: e.base, growth: e.growth, angle: e.angle, frames: 3, size: [e.radius * 2, e.radius * 2], heavy: true, hitsOwner: true });
    this.emit({ type: 'explosion', x: p.x, y: p.y, radius: e.radius });
  }

  // ---------- bursts (instant area hits) ----------
  spawnBurst(owner, b) {
    const burst = { owner, x: b.x, y: b.y, frames: b.frames || 3, move: { id: b.id || 'Burst', damage: b.damage, base: b.base, growth: b.growth, angle: b.angle, heavy: !!b.heavy, kind: 'melee', applies: b.applies }, hitVictims: new Set(), rect: rectFrom(b.x, b.y, b.size[0], b.size[1]), hitsOwner: !!b.hitsOwner };
    this.bursts.push(burst);
    return burst;
  }

  stepBursts() {
    for (let i = this.bursts.length - 1; i >= 0; i--) {
      const b = this.bursts[i];
      this.debugBoxes.push({ rect: b.rect, kind: 'burst' });
      for (const v of this.fighters) {
        if (!v.alive || b.hitVictims.has(v.index)) continue;
        if (v === b.owner && !b.hitsOwner) continue;
        if (v !== b.owner && this.sameTeam(b.owner, v)) continue;
        if (!overlap(b.rect, v.hurtbox)) continue;
        b.hitVictims.add(v.index);
        this.resolveHit(b.owner, v, b.move, null, b.rect, { summon: true, facing: sign(v.x - b.x || b.owner.facing) });
      }
      for (const s of [...this.summons]) if (s.destructible && s.owner !== b.owner && overlap(b.rect, s.rect)) this.destroySummon(s);
      b.frames--;
      if (b.frames <= 0) this.bursts.splice(i, 1);
    }
  }

  // ---------- summons ----------
  nodesOf(f) { return this.summons.filter((s) => s.type === 'node' && s.owner === f); }
  hasFruit(f) { return this.summons.some((s) => (s.type === 'cloud' || s.type === 'mine') && s.owner === f); }
  nearestNode(f, range) {
    let best = null, bd = range;
    for (const n of this.nodesOf(f)) { const d = Math.hypot(n.x - f.x, n.y - f.y); if (d <= bd) { bd = d; best = n; } }
    return best;
  }
  removeSummon(s) { const i = this.summons.indexOf(s); if (i >= 0) this.summons.splice(i, 1); }
  destroySummon(s) { this.removeSummon(s); this.emit({ type: 'summonbreak', kind: s.type, x: s.x, y: s.y }); }

  surfaceUnder(x, yMax) {
    let best = null;
    for (const p of this.stage.platforms) {
      if (x < p.x1 || x > p.x2) continue;
      if (p.top > yMax + 0.5) continue;
      if (!best || p.top > best.top) best = p;
    }
    return best;
  }

  spawnSummon(f, m) {
    const s = m.summon;
    const rm = f.rangeMul || 1;
    if (s.type === 'wall') {
      const x = f.x + s.offset[0] * f.facing, w = s.size[0], h = s.size[1] * rm;
      const wall = { type: 'wall', owner: f, x, y: f.y, w, h, life: s.lifetime, stunFrames: s.stunFrames, rehitEvery: s.rehitEvery, hits: new Map(), rect: rectFrom(x, f.y + h / 2, w, h), destructible: false };
      this.summons.push(wall);
    } else if (s.type === 'cloud') {
      const x = f.x + s.offset[0] * f.facing, y = f.y + s.offset[1];
      const cloud = { type: 'cloud', owner: f, x, y, r: s.radius * rm, vx: f.facing * s.speed, drift: s.driftFrames, life: s.lifetime, tickEvery: s.tickEvery, ticks: new Map(), slow: s.slow, rect: rectFrom(x, y, s.radius * 2, s.radius * 2), destructible: false };
      this.summons.push(cloud);
    } else if (s.type === 'mine') {
      const mine = { type: 'mine', owner: f, x: f.x + s.offset[0] * f.facing, y: f.y, hp: s.hp, life: s.lifetime, trigger: s.trigger, radius: s.radius, armed: 20, destructible: true };
      const surf = this.surfaceUnder(mine.x, f.y + 1);
      if (surf) mine.y = surf.top;
      mine.rect = rectFrom(mine.x, mine.y + 0.8, 1.6, 1.6);
      const mine_list = this.summons.filter((q) => q.type === 'mine' && q.owner === f);
      if (mine_list.length >= s.max) this.removeSummon(mine_list[0]);
      this.summons.push(mine);
      if (f.mech.id === 'Fruiting') f.mech.ring = Math.min(f.char.mechanic.ringMax, f.mech.ring + f.char.mechanic.perMine);
    } else if (s.type === 'node') {
      let x = f.x + f.facing * s.lob;
      let surf = this.surfaceUnder(x, f.y + 8);
      if (!surf) { x = f.x; surf = this.surfaceUnder(x, f.y + 8); }
      if (!surf) { this.emit({ type: 'nodefail', x: f.x, y: f.cy }); return; }
      const node = { type: 'node', owner: f, x, y: surf.top, hp: s.hp, life: s.lifetime, tickEvery: s.tickEvery, radius: s.radius, tick: 0, destructible: true, rect: rectFrom(x, surf.top + 0.8, 1.8, 1.8) };
      const nodes = this.nodesOf(f);
      if (nodes.length >= s.max) this.removeSummon(nodes[0]);
      this.summons.push(node);
    }
    this.emit({ type: 'summon', kind: s.type, x: f.x, y: f.y });
  }

  stepSummons() {
    for (let i = this.summons.length - 1; i >= 0; i--) {
      const s = this.summons[i];
      s.life--;
      if (s.type === 'wall') {
        this.debugBoxes.push({ rect: s.rect, kind: 'summon' });
        for (const v of this.enemiesOf(s.owner)) {
          if (v.untouchable || !overlap(s.rect, v.hurtbox)) continue;
          const last = s.hits.get(v.index);
          if (last != null && this.match.frame - last < s.rehitEvery) continue;
          s.hits.set(v.index, this.match.frame);
          this.resolveHit(s.owner, v, WALL_MOVE, null, s.rect, { summon: true, facing: sign(v.x - s.x || 1), fixedLaunch: 10 });
        }
      } else if (s.type === 'cloud') {
        if (s.drift > 0) { s.drift--; s.x += s.vx * FRAME; s.rect = rectFrom(s.x, s.y, s.r * 2, s.r * 2); }
        this.debugBoxes.push({ rect: s.rect, kind: 'summon' });
        for (const v of this.enemiesOf(s.owner)) {
          if (v.untouchable) continue;
          if (Math.hypot(v.x - s.x, v.cy - s.y) > s.r + v.r) continue;
          v.effects.slow = Math.max(v.effects.slow, 4);
          const last = s.ticks.get(v.index);
          if (last != null && this.match.frame - last < s.tickEvery) continue;
          s.ticks.set(v.index, this.match.frame);
          this.resolveHit(s.owner, v, CLOUD_MOVE, null, s.rect, { summon: true, facing: sign(v.x - s.x || 1), fixedLaunch: 8 });
          if (s.owner.mech.id === 'Fruiting') s.owner.mech.ring = Math.min(s.owner.char.mechanic.ringMax, s.owner.mech.ring + s.owner.char.mechanic.perCloudTick);
        }
      } else if (s.type === 'mine') {
        this.debugBoxes.push({ rect: s.rect, kind: 'summon' });
        if (s.armed > 0) s.armed--;
        else {
          for (const v of this.enemiesOf(s.owner)) {
            if (v.untouchable) continue;
            if (Math.hypot(v.x - s.x, v.cy - (s.y + 1)) <= s.trigger + v.r) {
              this.spawnBurst(s.owner, { x: s.x, y: s.y + 1, damage: 12, base: 26, growth: 4.0, angle: 70, frames: 3, size: [s.radius * 2, s.radius * 2], heavy: true });
              this.emit({ type: 'explosion', x: s.x, y: s.y + 1, radius: s.radius });
              this.removeSummon(s); break;
            }
          }
        }
      } else if (s.type === 'node') {
        this.debugBoxes.push({ rect: s.rect, kind: 'summon' });
        s.tick++;
        if (s.tick >= s.tickEvery) {
          s.tick = 0;
          for (const v of this.enemiesOf(s.owner)) {
            if (v.untouchable) continue;
            if (Math.hypot(v.x - s.x, v.cy - (s.y + 1)) <= s.radius + v.r) this.resolveHit(s.owner, v, NODE_MOVE, null, s.rect, { summon: true, chip: true });
          }
        }
      }
      if (s.life <= 0 && this.summons[i] === s) this.summons.splice(i, 1);
    }
  }

  fruiting(f) {
    const B = f.char.mechanic.burst;
    for (const s of [...this.summons]) {
      if (s.owner !== f || (s.type !== 'cloud' && s.type !== 'mine')) continue;
      const y = s.type === 'cloud' ? s.y : s.y + 1;
      this.spawnBurst(f, { x: s.x, y, damage: B.damage, base: B.base, growth: B.growth, angle: B.angle, frames: 3, size: [B.radius * 2, B.radius * 2], heavy: true });
      this.emit({ type: 'explosion', x: s.x, y, radius: B.radius });
      this.removeSummon(s);
    }
    f.mech.ring = 0;
    f.lag = 20; f.setState('landing');
    this.emit({ type: 'fruiting', x: f.x, y: f.cy });
  }

  // ---------- items ----------
  spawnItem(def, x, y) {
    const it = { def, x, y, vx: 0, vy: 0, held: null, uses: def.uses, life: ITEM_CFG.despawnAfter * 60, onGround: false };
    this.items.push(it);
    this.emit({ type: 'itemspawn', x, y, item: def.id });
    return it;
  }
  giveItem(f, def) { const it = { def, x: f.x, y: f.y, vx: 0, vy: 0, held: f, uses: def.uses, life: 0, onGround: false }; this.items.push(it); f.item = it; }
  itemNear(f) {
    for (const it of this.items) if (!it.held && Math.abs(it.x - f.x) < 3 && Math.abs(it.y - f.y) < 3.5) return it;
    return null;
  }
  pickupItem(f, it) { it.held = f; f.item = it; it.life = 0; this.emit({ type: 'pickup', x: f.x, y: f.cy, item: it.def.id }); }
  dropItem(f, knocked) {
    const it = f.item; if (!it) return;
    it.held = null; f.item = null;
    it.x = f.x; it.y = f.y + 2; it.vy = knocked ? 22 : 0; it.vx = knocked ? -f.facing * 10 : 0; it.onGround = false;
    it.life = ITEM_CFG.despawnAfter * 60;
    if (it.def.id === 'WateringCan' && it.uses <= 0) this.removeItem(it);
    if (f.state === 'attack' && f.move && (f.move.kind === 'spray' || f.move.id === 'ItemSwing')) f.endMove();
    this.emit({ type: 'itemdrop', x: it.x, y: it.y });
  }
  removeItem(it) { const i = this.items.indexOf(it); if (i >= 0) this.items.splice(i, 1); if (it.held) it.held.item = null; }

  useItem(f, button) {
    const it = f.item; const def = it.def;
    if (def.id === 'SeedBomb') {
      const T = def.throw;
      const pr = { owner: f, move: { id: 'SeedBomb', damage: def.explode.damage, base: def.explode.base, growth: def.explode.growth, angle: def.explode.angle, kind: 'melee', heavy: true }, x: f.x + f.facing * 1.5, y: f.y + 3, vx: f.facing * T.vx + f.vx * 0.5, vy: T.vy, w: T.size[0], h: T.size[1], life: T.fuse, shape: 'bomb', gravity: T.gravity, hitVictims: new Set(), facing: f.facing, item: true, explode: def.explode };
      pr.rect = rectFrom(pr.x, pr.y, pr.w, pr.h);
      this.projectiles.push(pr);
      this.removeItem(it);
      f.lag = 12; f.setState('landing');
      this.emit({ type: 'throwitem', x: f.x, y: f.cy });
      return;
    }
    if (button === 'heavy' || (def.id === 'WateringCan' && it.uses <= 0)) {
      const T = def.thrown;
      const pr = { owner: f, move: { id: 'ThrownItem', damage: T.damage, base: T.base, growth: T.growth, angle: T.angle, kind: 'melee' }, x: f.x + f.facing * 1.5, y: f.y + 3, vx: f.facing * T.speed, vy: 4, w: T.size[0], h: T.size[1], life: T.lifetime, shape: def.id === 'Trowel' ? 'trowel' : 'can', gravity: 40, hitVictims: new Set(), facing: f.facing, item: true };
      pr.rect = rectFrom(pr.x, pr.y, pr.w, pr.h);
      this.projectiles.push(pr);
      this.removeItem(it);
      f.lag = 12; f.setState('landing');
      this.emit({ type: 'throwitem', x: f.x, y: f.cy });
      return;
    }
    if (def.id === 'Trowel') {
      const sw = { ...def.swing, id: 'ItemSwing', kind: 'melee', total: def.swing.startup + def.swing.active + def.swing.recovery };
      it.uses--;
      f.startMove(sw);
      if (it.uses <= 0) it.spent = true;
      return;
    }
    if (def.id === 'WateringCan') {
      const sp = { id: 'ItemSpray', label: 'Spray', startup: 4, active: 30, recovery: 8, damage: 0, base: 0, growth: 0, angle: 0, kind: 'spray', hitboxes: [], total: 42 };
      f.startMove(sp);
    }
  }

  stepItems() {
    for (let i = this.items.length - 1; i >= 0; i--) {
      const it = this.items[i];
      if (it.held) {
        if (it.spent && it.held.state !== 'attack') { this.removeItem(it); this.emit({ type: 'itembreak', x: it.held.x, y: it.held.cy }); }
        continue;
      }
      it.vy = Math.max(-40, it.vy - GRAVITY * FRAME);
      const py = it.y;
      it.x += it.vx * FRAME; it.y += it.vy * FRAME; it.vx *= 0.95;
      it.onGround = false;
      if (it.vy <= 0) for (const p of this.stage.platforms) {
        if (it.x > p.x1 && it.x < p.x2 && py >= p.top - 0.3 && it.y <= p.top) { it.y = p.top; it.vy = 0; it.onGround = true; break; }
      }
      if (it.onGround) it.life--;
      if (it.life <= 0 || it.y < this.stage.blast.bottom) { this.items.splice(i, 1); this.emit({ type: 'itemgone', x: it.x, y: it.y }); }
    }
  }

  maybeSpawnItem(playerCount) {
    this.itemTimer += FRAME;
    if (this.itemTimer < ITEM_CFG.spawnEvery) return;
    const max = playerCount >= 5 ? 2 : 1;
    if (this.items.filter((it) => !it.held).length >= max) return;
    this.itemTimer = 0;
    const def = ITEM_LIST[Math.floor(Math.random() * ITEM_LIST.length)];
    const p = this.stage.itemSpawn();
    this.spawnItem(def, p.x, p.y);
  }
}
