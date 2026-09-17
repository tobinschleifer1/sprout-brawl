import { FRAME, GRAVITY, GRAB, GROUND_POUND, LEDGE, SHIELD, ITEMS as ITEM_CFG } from '../config.js';
import { launchSpeed, hitlag as hitlagFor } from './knockback.js';
import { ITEMS, ITEM_LIST } from '../data/items.js';

const overlap = (a, b) => a.x1 < b.x2 && a.x2 > b.x1 && a.y1 < b.y2 && a.y2 > b.y1;
const rectFrom = (cx, cy, w, h) => ({ x1: cx - w / 2, x2: cx + w / 2, y1: cy - h / 2, y2: cy + h / 2, cx, cy, w, h });
const sign = (v) => (v < 0 ? -1 : 1);
const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);

const DIVE_MOVE = { id: 'GroundPound', label: 'Ground Pound', ...GROUND_POUND.dive, heavy: true, kind: 'melee', hitboxes: [{ frames: [1, 999], ...GROUND_POUND.dive.hitbox }] };
const LEDGE_ATTACK = { id: 'LedgeAttack', label: 'Ledge Attack', damage: LEDGE.options.attack.damage, base: LEDGE.options.attack.base, growth: LEDGE.options.attack.growth, angle: LEDGE.options.attack.angle, kind: 'melee', hitboxes: [LEDGE.options.attack.hitbox] };
const WALL_MOVE = { id: 'Trellis', damage: 5, base: 8, growth: 0, angle: 80, kind: 'summon', extraHitstun: 6 };
const CLOUD_MOVE = { id: 'SporeCloud', damage: 2, base: 8, growth: 0, angle: 80, kind: 'summon', applies: { slow: 12 } };
const NODE_MOVE = { id: 'NodeTick', damage: 1, base: 3, growth: 0, angle: 80, kind: 'summon' };

export class Combat {
  constructor(match) {
    this.match = match;
    this.projectiles = []; this.summons = []; this.bursts = []; this.items = []; this.plates = [];
    this.events = []; this.debugBoxes = [];
    this.itemTimer = 0;
  }
  get fighters() { return this.match.fighters; }
  get stage() { return this.match.stage; }
  emit(e) { this.events.push(e); }
  sameTeam(a, b) { return a.team === b.team; }
  enemiesOf(f) { return this.fighters.filter((v) => v !== f && v.alive && !this.sameTeam(f, v)); }
  // Nearest living enemy, by straight-line distance. Ultimates that pick their own victims all
  // want the same answer, and all of them want it again later if that victim dies mid-move.
  nearestEnemy(f, range = Infinity, exclude = null) {
    let best = null, bd = range;
    for (const v of this.enemiesOf(f)) {
      if (v.untouchable || (exclude && exclude.includes(v))) continue;
      const d = Math.hypot(v.x - f.x, v.cy - f.cy);
      if (d <= bd) { bd = d; best = v; }
    }
    return best;
  }

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
        // A live Blast Keg is a target for EVERYONE, including whoever threw it. That is the item:
        // a threat you do not fully control once it leaves your hands.
        for (const pr of [...this.projectiles]) {
          if (!pr.volatile || pr.dead) continue;
          if (!overlap(b.rect, pr.rect)) continue;
          const at = this.projectiles.indexOf(pr);
          if (at >= 0) this.projectiles.splice(at, 1);
          this.explode(pr);
        }
      }
    }
    this.stepProjectiles();
    this.stepSummons();
    this.stepBursts();
    this.stepItems();
    this.stepPlates();
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

    // AEGIS. A reflect window converts an incoming hit into an outgoing one, aimed back at whoever
    // threw it. Checked before everything else a victim can be doing, because for these two
    // seconds it is the only thing they ARE doing.
    // Grabs ARE reflected. A grab is the standard answer to a defensive stance, and the shield
    // probe found the hole immediately: light + guardHeld is a grab in this engine, so a defender
    // could shield-grab an Aegis all day and take nothing. Being thrown back by the thing you
    // reached for is exactly what a counter weapon should do.
    if (victim.reflecting && !opts.reflected && !opts.chip && attacker !== victim) {
      const R = victim.reflecting;
      const back = Math.max(R.min, Math.round(damage * R.mul));
      this.spawnBurst(victim, { id: 'Aegis', x: attacker.x, y: attacker.cy, damage: back,
        base: R.base, growth: R.growth, angle: R.angle, frames: 4, size: [R.radius * 2, R.radius * 2],
        heavy: true, hitsOwner: false, shieldDamageMul: R.shieldDamageMul });
      if (direct) attacker.hitlag = hitlagFor(back, true);
      R.absorbed = (R.absorbed || 0) + damage;
      this.emit({ type: 'aegis', x: attacker.x, y: attacker.cy, damage: back, victim: attacker.index });
      return true;
    }

    // BULWARK. A carried shield, checked before everything else because it is a property of the
    // fighter rather than of what they are doing - you keep it while attacking, while running, in
    // the air. It only covers the FRONT: `arc` is how much of the hemisphere in front of the
    // fighter counts, so getting behind someone holding one beats it completely.
    const bw = victim.item && victim.item.def.guard && victim.item.hp > 0 ? victim.item : null;
    if (bw && move.kind !== 'grab' && !opts.chip && !move.unblockable) {
      const from = cx - victim.x;
      const facingIt = Math.abs(from) < 0.2 || Math.sign(from) === victim.facing;
      if (facingIt) {
        const G = bw.def.guard;
        bw.hp -= damage;
        damage *= G.damageMul;
        base *= G.launchMul; growth *= G.launchMul;
        this.emit({ type: 'bulwark', x: cx, y: cy, victim: victim.index, broke: bw.hp <= 0 });
        if (bw.hp <= 0) { this.removeItem(bw); this.emit({ type: 'itembreak', x: victim.x, y: victim.cy }); }
      }
    }

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
      // An ultimate costs 20 landed hits and the whole meter, and dying wipes it. Holding one
      // button should not be a clean answer: three of the four used to be blocked for 0% with
      // most of a shield left. They now chew through a full shield instead.
      const shieldDmg = damage * ((hb && hb.shieldDamageMul) || move.shieldDamageMul || 1);
      victim.applyBlock({ damage: shieldDmg, facing: opts.facing ?? attacker.facing, perfect });
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
    // An ultimate does not just hit harder in the abstract - it multiplies the knockback the
    // victim would already have taken at their current percent, so it stays a finisher at 120%
    // instead of flattening into a fixed launch the way a raw `base` bump would.
    launch *= (hb && hb.knockbackMul != null ? hb.knockbackMul : move.knockbackMul) || 1;
    const facing = move.behind ? -attacker.facing : (opts.facing ?? attacker.facing);
    const hl = hitlagFor(damage, move.heavy);
    if (direct) { attacker.hitlag = hl; attacker.moveLanded = true; }
    // A projectile connecting also counts as the move landing, but only while its owner is still
    // executing the move that fired it. Without this a ranged light can never open a combo string,
    // because moveLanded (which gates chaining) was set by melee contact alone.
    else if (opts.projectile && attacker.move === move) attacker.moveLanded = true;
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
    // One landed hit, one point of ultimate charge - regardless of how much damage it did, so a
    // fast light string charges as fast as a signature and pressure is what fills the bar.
    if (attacker.chargeUltimate && move.id !== 'Ultimate') attacker.chargeUltimate(1);
    // A mark, not a launch. While Exsanguinate is live every connection stacks on the victim and
    // the knockback is held back until the window closes - see the `bleed` branch.
    if (attacker.marking) {
      victim.effects.bleed = Math.min(attacker.marking.max, (victim.effects.bleed || 0) + 1);
      this.emit({ type: 'bleedmark', x: victim.x, y: victim.cy, marks: victim.effects.bleed, victim: victim.index });
    }
    if (attacker.mech.id === 'Bloom') attacker.mech.hits.push(attacker.frameCount);
    // Surge counts the same way Bloom does: only CONNECTED hits, so the counter is a record of
    // pressure rather than of button presses.
    if (attacker.mech.id === 'Surge') (attacker.mech.hits = attacker.mech.hits || []).push(attacker.frameCount);
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
    // The sniper stance is the one ultimate that is not a single committed swing: it paints a
    // target and then waits for the player to pull the trigger, so the target has to be chosen
    // the moment the stance opens rather than the moment a bullet leaves.
    if (m.kind === 'sniper') {
      f.ultTarget = this.nearestEnemy(f, m.sniper.range);
      f.ultShots = m.sniper.shots;
      f.ultCooldown = 0; f.ultEndAt = 0;
      this.emit({ type: 'mark', x: f.x, y: f.cy, victim: f.ultTarget ? f.ultTarget.index : -1 });
      return;
    }
    if (m.kind === 'burst') { this.emit({ type: 'burst', x: f.x, y: f.y + 3, radius: 7, frames: m.active }); return; }
    if (m.kind === 'projectile') { this.spawnProjectile(f, m); return; }
    // Exsanguinate opens its marking window the moment it becomes active; the `bleed` branch in
    // onMoveActiveFrame collects on the last frame.
    if (m.kind === 'bleed') { f.marking = { max: m.bleed.maxMarks }; return; }
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
        f.mech.spines--;
        f.volleyCount++;
        this.spawnProjectile(f, m, { yJitter: (f.volleyCount - 3) * (p.spread || 0.35) });
      }
    } else if (m.kind === 'slam') {
      // The overhead slam. The blade's own hitbox is authored in the move; what happens HERE is
      // the impact: a crater that walks outward along the ground in both directions, so the kill
      // zone is the floor around the landing point and not just the arc of the swing.
      const C = m.crater;
      const k = f.mf - f.startupEff - 1;
      if (k < C.frame || (k - C.frame) % C.every !== 0) return;
      const step = Math.floor((k - C.frame) / C.every);
      if (step >= C.count) return;
      const surf = this.surfaceUnder(f.x, f.y + 1.5);
      const y = (surf ? surf.top : f.y) + 1.0;
      const fade = 1 - step / C.count;                       // the shockwave loses bite as it travels
      for (const dir of [-1, 1]) {
        if (step === 0 && dir === -1) continue;              // one crater at the centre, not two
        const x = f.x + dir * C.step * step;
        this.spawnBurst(f, { id: 'Crater', x, y, // `C.minDamage ?? 1`: without the fallback a crater that omits the optional floor computed
          // Math.max(undefined, n) = NaN, wrote NaN into the victim's percent, and corrupted the
          // match silently. The war hammer's two craters found this the day they were added.
          damage: step === 0 ? C.damage : Math.max(C.minDamage ?? 1, Math.round(C.damage * fade)),
          base: C.base, growth: C.growth, frames: 4, knockbackMul: C.knockbackMul,
          shieldDamageMul: C.shieldDamageMul,
          // The epicentre throws along the BLADE's angle, the outward steps pop upward. Without
          // this the crater's larger launch won the same-frame comparison and every Colossus kill
          // went out at the shockwave's 64 degrees - the sword's own 46 was dead data.
          angle: step === 0 ? (C.centreAngle ?? C.angle) : C.angle,
          size: [C.radius * 2, C.radius * (step === 0 ? 3.0 : 2.2)], heavy: true });
        this.emit({ type: 'crater', x, y, radius: C.radius * (step === 0 ? 1.5 : 1), first: step === 0 });
      }
    } else if (m.kind === 'vortex') {
      // Reach out, take hold of the two closest fighters, drag them into one point in front of
      // you, and detonate that point. The pull is the move: the damage is trivial until the ball
      // closes, and everything the victims can do about it they have to do before it does.
      const V = m.vortex;
      const k = f.mf - f.startupEff - 1;
      const ox = f.x + f.facing * V.orbOffset[0], oy = f.y + V.orbOffset[1];
      if (k === 0) {
        f.ultHeld = [];
        for (let i = 0; i < V.targets; i++) {
          const v = this.nearestEnemy(f, V.range, f.ultHeld);
          if (!v) break;
          f.ultHeld.push(v);
        }
        if (f.ultHeld.length) this.emit({ type: 'soulgrab', x: ox, y: oy, victims: f.ultHeld.map((v) => v.index) });
        // The Chain Flail's Snare is the same reach-and-hold, except it does not crush: it
        // ATTACHES, and hands the pull to the mechanic so the player decides for the next 90
        // frames which of the two of them crosses the gap. See the Snare branch in fighter.js.
        if (f.mech.id === 'Snare' && f.ultHeld.length) {
          f.mech.snared = f.ultHeld[0];
          f.mech.timer = f.char.mechanic.holdFrames;
          this.emit({ type: 'snare', x: ox, y: oy, victim: f.ultHeld[0].index });
        }
      }
      const held = f.ultHeld || [];
      if (k < V.holdFrames) {
        for (let i = held.length - 1; i >= 0; i--) {
          const v = held[i];
          // A dodge started AFTER the grab used to be cancelled by the forced hitstun state, so
          // there was no timing at all that beat this. Rolling out of a grab is a fighting-game
          // fundamental; invincibility frees you.
          if (!v.alive || v.untouchable) {
            held.splice(i, 1);
            if (v.alive) this.emit({ type: 'soulescape', x: v.x, y: v.cy, victim: v.index });
            continue;
          }
          // Mashing buys distance back. Twenty-two frames with no agency at all, ending in a
          // kill, is not a thing a fighting game should contain - so every button press pushes
          // the victim back out, and clearing the burst radius frees them outright.
          if (v.buffer.jump > 0 || v.buffer.dodge > 0 || v.buffer.light > 0) {
            v.ultEscape = Math.min(V.escapeCap, (v.ultEscape || 0) + V.escapePerPress);
            v.buffer.jump = 0; v.buffer.dodge = 0; v.buffer.light = 0;
          }
          // Hard drag, but the victim's stick still bends where in the ball they end up, which
          // decides the angle they eat when it goes off.
          const dx = ox - v.x, dy = oy - v.cy;
          const d = Math.hypot(dx, dy) || 1;
          // Enough mashing turns the pull negative and the victim starts drifting back out.
          const rate = (V.pullSpeed - (v.ultEscape || 0) * V.escapeBite) * FRAME;
          const step = rate >= 0 ? Math.min(d, rate) : rate;
          v.x += (dx / d) * step + v.input.x * V.diPerFrame;
          v.y += (dy / d) * step + v.input.y * V.diPerFrame;
          v.vx = 0; v.vy = 0; v.onGround = false; v.platform = null;
          v.hitstun = Math.max(v.hitstun, 3);
          if (v.state !== 'hitstun') v.setState('hitstun');
          f.moveLanded = true;
          // Only a victim who has actually fought their way out is released - the check cannot
          // fire on frame one, when everyone the scythe reached for is still standing where the
          // grab found them and is legitimately outside the ball.
          if ((v.ultEscape || 0) > 0 && Math.hypot(ox - v.x, oy - v.cy) > V.burst.radius * 1.6) {
            held.splice(i, 1); v.ultEscape = 0;
            this.emit({ type: 'soulescape', x: v.x, y: v.cy, victim: v.index });
          }
        }
        this.emit({ type: 'soulorb', x: ox, y: oy, k: k / V.holdFrames, held: held.length });
      } else if (k === V.holdFrames) {
        const B = V.burst;
        this.spawnBurst(f, { id: 'Ultimate', x: ox, y: oy, damage: B.damage, base: B.base, growth: B.growth,
          angle: B.angle, frames: 4, size: [B.radius * 2, B.radius * 2], heavy: true,
          knockbackMul: B.knockbackMul, shieldDamageMul: B.shieldDamageMul });
        this.emit({ type: 'soulburst', x: ox, y: oy, radius: B.radius });
        f.ultHeld = [];
      }
    } else if (m.kind === 'sniper') {
      // One bullet per trigger pull, three in the magazine. The stance holds until the player
      // spends them, which is why this reads the input buffer directly instead of firing on a
      // fixed frame the way every other projectile move does.
      const S = m.sniper;
      if (!f.ultTarget || !f.ultTarget.alive) f.ultTarget = this.nearestEnemy(f, S.range);
      if (f.ultTarget) f.facing = sign(f.ultTarget.x - f.x) || f.facing;
      if (f.ultCooldown > 0) f.ultCooldown--;
      if (f.ultEndAt) { if (f.mf >= f.ultEndAt) f.mf = f.startupEff + m.active; return; }
      if (f.buffer.ult > 0 && f.ultShots > 0 && f.ultCooldown <= 0) {
        f.buffer.ult = 0;
        f.ultShots--;
        f.ultCooldown = S.reload;
        const P = S.projectile;
        const pr = {
          owner: f, move: m, x: f.x + P.spawnOffset[0] * f.facing, y: f.y + P.spawnOffset[1],
          vx: f.facing * P.speed, vy: 0, w: P.size[0], h: P.size[1], life: P.lifetime, shape: 'tracer',
          grounded: false, gravity: 0, hitVictims: new Set(), facing: f.facing, item: false,
          ghost: true,                                   // a painted target is not saved by cover
          homing: { target: f.ultTarget, turn: P.turn, speed: P.speed, expireAfter: P.expireAfter },
        };
        pr.rect = rectFrom(pr.x, pr.y, pr.w, pr.h);
        this.projectiles.push(pr);
        this.emit({ type: 'snipe', x: pr.x, y: pr.y, facing: f.facing, shotsLeft: f.ultShots });
        if (f.ultShots <= 0) f.ultEndAt = f.mf + S.holdAfterLast;
      }
    } else if (m.kind === 'starfall') {
      // Two orbs for everyone. Aimed at where each enemy IS, not where the caster is looking, so
      // a four-player match turns into eight tracking orbs and nowhere on the stage is quiet.
      const S = m.starfall;
      const k = f.mf - f.startupEff - 1;
      if (k % S.every !== 0) return;
      const wave = k / S.every;
      if (wave >= S.perTarget) return;
      for (const v of this.enemiesOf(f)) {
        if (v.untouchable) continue;
        const jitter = (Math.random() - 0.5) * S.jitter + (wave ? v.vx * 0.18 : 0);
        const pr = {
          owner: f, move: m, x: v.x + jitter, y: v.cy + S.height,
          vx: 0, vy: -S.speed, w: S.size, h: S.size, life: 200, shape: 'orb',
          grounded: false, gravity: 0, hitVictims: new Set(), facing: 1, item: false, falling: true,
          homing: { target: v, turn: S.turn, speed: S.speed, axis: 'x' },
          explode: { id: 'Ultimate', damage: S.damage, base: S.base, growth: S.growth, angle: S.angle,
            radius: S.radius, knockbackMul: S.knockbackMul, shieldDamageMul: S.shieldDamageMul,
            // The first wave is the shield check; the second punishes you for still being in it.
            // Two blockable orbs left a full shield at 16/50, which made "hold guard" a clean
            // answer to a whole meter.
            unblockable: wave > 0, hitsOwner: false, fx: 'star' },
        };
        pr.rect = rectFrom(pr.x, pr.y, pr.w, pr.h);
        this.projectiles.push(pr);
        this.emit({ type: 'starfall', x: pr.x, y: pr.y, target: v.index });
      }
    } else if (m.kind === 'rundown') {
      // GAUNTLETS - RUNDOWN. The ultimate does not happen where you are standing: it PURSUES.
      // Every `every` frames it re-picks the nearest living enemy, teleport-dashes the fighter to
      // just short of them, and swings. In a four-player match it bounces between all of them.
      //
      // Nothing else in the game moves the ATTACKER to the target. The vortex moves victims to the
      // caster; this is the inverse, and it is the only shape that says "never let them breathe".
      const R = m.rundown;
      const k = f.mf - f.startupEff - 1;
      if (k % R.every !== 0) return;
      const step = Math.floor(k / R.every);
      if (step >= R.count) return;
      const target = this.nearestEnemy(f, R.range);
      if (!target) return;
      const side = Math.sign(f.x - target.x) || 1;
      f.x = target.x + side * R.standoff;
      f.y = target.y;
      f.facing = -side;
      f.vx = 0; f.vy = 0;
      f.onGround = target.onGround; f.platform = target.platform;
      this.spawnBurst(f, { id: 'Rundown', x: target.x, y: target.cy, damage: R.damage, base: R.base, growth: R.growth,
        angle: R.angle, frames: 3, size: [R.radius * 2, R.radius * 2], heavy: true, hitsOwner: false,
        knockbackMul: step === R.count - 1 ? R.finalMul : 1, shieldDamageMul: R.shieldDamageMul });
      this.emit({ type: 'rundown', x: target.x, y: target.cy, step, last: step === R.count - 1, victim: target.index });

    } else if (m.kind === 'upheaval') {
      // WAR HAMMER - UPHEAVAL. The floor attacks, and it attacks where THEY are standing.
      //
      // Colossus cracks the ground outward from the sword; this raises a column under each enemy
      // in turn. The difference matters in play: a crater is something you walk out of, a column
      // is somewhere you already are. Columns only rise from ground a fighter is standing on, so
      // being in the air is the answer to it.
      const U = m.upheaval;
      const k = f.mf - f.startupEff - 1;
      if (k % U.every !== 0) return;
      const step = Math.floor(k / U.every);
      if (step >= U.count) return;
      // NOT filtered to grounded fighters. The first version was, and the move countered itself:
      // its own first column threw the victim into the air and the remaining four rose under where
      // they used to be, for 14% total. The column is eleven studs tall and rises from the floor
      // under wherever they are now, so the counterplay is moving HORIZONTALLY between columns
      // rather than simply being airborne.
      const targets = this.enemiesOf(f);
      const v = targets[step % Math.max(1, targets.length)];
      if (!v) return;
      const surf = this.surfaceUnder(v.x, v.y + 1.5);
      const y = (surf ? surf.top : v.y) + 1.0;
      this.spawnBurst(f, { id: 'Upheaval', x: v.x, y, damage: U.damage, base: U.base, growth: U.growth,
        angle: U.angle, frames: 5, size: [U.width, U.height], heavy: true, hitsOwner: false,
        knockbackMul: U.knockbackMul, shieldDamageMul: U.shieldDamageMul });
      this.emit({ type: 'upheaval', x: v.x, y, step, victim: v.index });

    } else if (m.kind === 'pierce') {
      // LONGBOW - HEARTSEEKER. One arrow. It does not stop at the first thing it hits, it cannot
      // be blocked, and it crosses the entire stage.
      //
      // Every other ultimate in the game is a duration. This is a single frame of commitment with
      // a two-second wind-up in front of it, which is the most a precision weapon can say.
      const k = f.mf - f.startupEff - 1;
      if (k !== 0) return;
      const P = m.pierce;
      const pr = {
        owner: f, move: { ...m, kind: 'melee', unblockable: true },
        x: f.x + f.facing * 2.2, y: f.y + P.height, vx: f.facing * P.speed, vy: 0,
        w: P.size[0], h: P.size[1], life: P.lifetime, gravity: 0, hitVictims: new Set(),
        facing: f.facing, shape: 'heartseeker', ghost: true, pierce: true,
      };
      pr.rect = rectFrom(pr.x, pr.y, pr.w, pr.h);
      this.projectiles.push(pr);
      this.emit({ type: 'heartseeker', x: pr.x, y: pr.y, facing: f.facing });

    } else if (m.kind === 'anchor') {
      // CHAIN FLAIL - ANCHOR. The head is thrown into the ground and stays there. The chain
      // between the fighter and that point is live for the whole ultimate, and the fighter can
      // still move - so the weapon becomes a lethal line you drag around the stage.
      //
      // No other ultimate in the game leaves something ON the stage that the player then plays
      // around. It is the only one where where you STAND is the whole move.
      const A = m.anchor;
      const k = f.mf - f.startupEff - 1;
      if (k === 0) {
        const surf = this.surfaceUnder(f.x + f.facing * A.throwDistance, f.y + 1.5);
        f.ultAnchor = { x: f.x + f.facing * A.throwDistance, y: (surf ? surf.top : f.y) + 0.6 };
        this.emit({ type: 'anchorset', x: f.ultAnchor.x, y: f.ultAnchor.y });
      }
      // THE SNAP-BACK. On the last active frame the head is torn out of the ground and comes home
      // along the chain, and everything on that line comes with it. Without this the ultimate just
      // stopped: four seconds of chip with nothing at the end of it, and a launch that barely
      // scaled with percent because the only thing it ever threw was a chain tick.
      if (f.ultAnchor && k >= m.active - 1) {
        const ax = f.ultAnchor.x, ay = f.ultAnchor.y;
        const steps = 6;
        for (let i = 0; i <= steps; i++) {
          const u = i / steps;
          this.spawnBurst(f, { id: 'Snapback', x: ax + (f.x - ax) * u, y: ay + (f.y + 2.4 - ay) * u,
            damage: A.snapDamage, base: A.snapBase, growth: A.snapGrowth, angle: A.snapAngle,
            frames: 5, size: [A.thickness * 2.4, A.thickness * 2.4], heavy: true, hitsOwner: false,
            knockbackMul: 1.35, shieldDamageMul: A.shieldDamageMul * 2 });
        }
        this.emit({ type: 'anchorsnap', x: ax, y: ay });
        f.ultAnchor = null;
        return;
      }
      if (!f.ultAnchor || k % A.every !== 0) return;
      // The chain is a line: sample it and hit anything standing on it.
      const ax = f.ultAnchor.x, ay = f.ultAnchor.y;
      const hx = f.x, hy = f.y + 2.4;
      const span = Math.hypot(hx - ax, hy - ay);
      if (span > A.maxLength) { f.ultAnchor = null; this.emit({ type: 'anchorsnap', x: ax, y: ay }); return; }
      // ONE hit per fighter per tick. The first version sampled the line into overlapping bursts
      // and spawned one at each sample, so a victim standing on the chain was caught by three or
      // four of them at once - the ultimate dealt 124% where every other one in the game deals
      // between 18 and 55. Now the segment is tested against each fighter and at most one burst is
      // placed, on them.
      for (const v of this.enemiesOf(f)) {
        const dx = hx - ax, dy = hy - ay;
        const len2 = dx * dx + dy * dy || 1;
        const t = Math.max(0, Math.min(1, ((v.x - ax) * dx + (v.cy - ay) * dy) / len2));
        const px = ax + dx * t, py = ay + dy * t;
        if (Math.hypot(v.x - px, v.cy - py) > A.thickness + v.r) continue;
        this.spawnBurst(f, { id: 'Chain', x: px, y: py,
          damage: A.damage, base: A.base, growth: A.growth, angle: A.angle, frames: 2,
          size: [A.thickness * 2, A.thickness * 2], heavy: false, hitsOwner: false, shieldDamageMul: A.shieldDamageMul });
      }
      this.emit({ type: 'chainline', ax, ay, hx, hy });

    } else if (m.kind === 'reflect') {
      // SHIELD - AEGIS. Their damage becomes yours.
      //
      // For the whole window every hit that lands on this fighter is absorbed and thrown straight
      // back at whoever threw it, scaled up. The counter mechanic already does this for one hit on
      // one frame; this is the same idea held open for two seconds, which is the only ultimate in
      // the game that does nothing at all unless the opponent acts.
      if (!f.reflecting) {
        f.reflecting = { mul: m.reflect.multiplier, min: m.reflect.minDamage, radius: m.reflect.radius,
          angle: m.reflect.angle, base: m.reflect.base, growth: m.reflect.growth,
          shieldDamageMul: m.reflect.shieldDamageMul, absorbed: 0 };
      }
      // THE DISCHARGE. Without it Aegis is blanked completely by an opponent who simply holds
      // shield or walks away - the whole meter spent on nothing, which is not a tradeoff, it is a
      // dead ultimate. On the last frame everything it absorbed comes out at once, on a floor that
      // guarantees it does SOMETHING even if nobody ever swung.
      const k = f.mf - f.startupEff - 1;
      if (k >= m.active - 1) {
        const D = m.reflect;
        const stored = f.reflecting.absorbed;
        this.spawnBurst(f, { id: 'AegisBreak', x: f.x + f.facing * 2.2, y: f.y + 2.8,
          damage: D.dischargeMin + Math.round(stored * D.dischargeShare),
          base: D.base, growth: D.growth, angle: D.angle, frames: 5,
          size: [D.dischargeRadius * 2, D.dischargeRadius * 1.7], heavy: true, hitsOwner: false,
          knockbackMul: 1.3, shieldDamageMul: D.shieldDamageMul });
        this.emit({ type: 'aegisbreak', x: f.x, y: f.cy, stored });
      }

    } else if (m.kind === 'bleed') {
      // DUAL DAGGERS - EXSANGUINATE. Mark now, collect later.
      //
      // Every hit during the window leaves a mark instead of knockback. When the window ends every
      // mark on every victim goes off at once, and the size of that is the number of marks you
      // earned - so the finisher is not a fixed number in a data file, it is the combo you just
      // did. It is the only ultimate whose payload the player decides.
      const B = m.bleed;
      const k = f.mf - f.startupEff - 1;
      if (k < m.active - 1) return;
      for (const v of this.enemiesOf(f)) {
        const marks = (v.effects.bleed || 0);
        if (!marks) continue;
        v.effects.bleed = 0;
        this.spawnBurst(f, { id: 'Exsanguinate', x: v.x, y: v.cy,
          damage: B.perMark * marks, base: B.base + B.basePerMark * marks, growth: B.growth,
          angle: B.angle, frames: 4, size: [B.radius * 2, B.radius * 2], heavy: true, hitsOwner: false,
          knockbackMul: B.knockbackMul, shieldDamageMul: B.shieldDamageMul });
        this.emit({ type: 'exsanguinate', x: v.x, y: v.cy, marks, victim: v.index });
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
      // Homing. A tracked round steers toward its mark at a fixed turn rate rather than snapping
      // to it, so it still reads as a bullet in flight and can still be walked out of at range.
      if (p.homing && p.homing.target) {
        const tg = p.homing.target;
        // Tracking expires. Without this a sniper round chased a launched victim indefinitely and
        // every ordinary hit converted into a stock: correct DI has to be able to leave the cone.
        if (p.homing.expireAfter !== undefined && --p.homing.expireAfter <= 0) p.homing = null;
        else if (!tg.alive) p.homing = null;
        else {
          const H = p.homing;
          if (H.axis === 'x') {
            p.vx += clamp((tg.x - p.x) * H.turn, -H.speed * 0.6, H.speed * 0.6) - p.vx * 0.12;
          } else {
            const dx = tg.x - p.x, dy = tg.cy - p.y;
            const d = Math.hypot(dx, dy) || 1;
            const wx = (dx / d) * H.speed, wy = (dy / d) * H.speed;
            const blend = Math.min(1, H.turn * FRAME);
            p.vx += (wx - p.vx) * blend; p.vy += (wy - p.vy) * blend;
          }
        }
      }
      p.x += p.vx * FRAME; p.y += p.vy * FRAME; p.life--;
      p.rect = rectFrom(p.x, p.y, p.w, p.h);
      this.debugBoxes.push({ rect: p.rect, kind: 'proj' });
      let dead = p.life <= 0;
      // Stage body: every solid stops a shot, not just the main floor. This is what makes a tower
      // or a mesa actual cover instead of scenery.
      if (!p.grounded && !p.ghost) {
        for (const sp of this.stage.solids) {
          if (p.x > sp.x1 && p.x < sp.x2 && p.y < sp.top && p.y > sp.bottom) {
            dead = true;
            if (p.falling) p.y = sp.top + 0.6;             // burst ON the floor, not inside it
            if (p.explode) this.explode(p);
            else this.emit({ type: 'projectilebreak', x: p.x, y: p.y });
            break;
          }
        }
      }
      // Landing for lobbed items. Falling orbs are deliberately NOT in here: a drop-through
      // shelf is not something energy from the sky stops on, and bursting on the grating above
      // meant nobody standing under one could ever be hit.
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
          // Catching a keg out of the air. Timing a shield press on an incoming keg takes it out
          // of the air and puts it in your hands, which is the best thing you can do with a
          // thrown one and the reason throwing it at a good player is a risk.
          if (p.explode && v.buffer.guard > 0 && !v.item && ['air', 'idle', 'run'].includes(v.state)) {
            v.buffer.guard = 0; this.giveItem(v, p.itemDef || ITEMS.BlastKeg); dead = true; this.emit({ type: 'catch', x: v.x, y: v.cy }); break;
          }
          p.hitVictims.add(v.index);
          // The Lodestone does not launch: it ATTACHES. Two percent, no knockback worth the name,
          // and then five seconds of falling like a dropped anvil.
          if (p.stick) {
            this.resolveHit(p.owner, v, p.move, { angle: p.move.angle }, p.rect, { projectile: true, facing: sign(p.vx), item: true });
            v.effects.lodestone = p.stick.frames;
            v.effects.lodestoneDef = p.stick;
            this.emit({ type: 'lodestone', x: v.x, y: v.cy, fighter: v.index });
            dead = true; break;
          }
          if (p.explode) { this.explode(p); dead = true; break; }
          const hit = this.resolveHit(p.owner, v, p.move, { angle: p.move.angle }, p.rect, { projectile: true, facing: sign(p.vx), item: p.item });
          // A piercing shot keeps going. `hitVictims` already stops it hitting the same fighter
          // twice, so it crosses the stage taking everyone on the line.
          if (hit && !p.pierce) { dead = true; break; }
        }
      }
      if (p.y < this.stage.blast.bottom - 10 || Math.abs(p.x) > 200) dead = true;
      if (dead) this.projectiles.splice(i, 1);
    }
  }

  explode(p) {
    const e = p.explode;
    this.spawnBurst(p.owner, { id: e.id, x: p.x, y: p.y, damage: e.damage, base: e.base, growth: e.growth, angle: e.angle, frames: 3, size: [e.radius * 2, e.radius * 2], heavy: true, hitsOwner: e.hitsOwner !== false, knockbackMul: e.knockbackMul, shieldDamageMul: e.shieldDamageMul, unblockable: e.unblockable });
    this.emit({ type: 'explosion', x: p.x, y: p.y, radius: e.radius, kind: e.fx || null });
  }

  // ---------- bursts (instant area hits) ----------
  spawnBurst(owner, b) {
    const burst = { owner, x: b.x, y: b.y, frames: b.frames || 3, move: { id: b.id || 'Burst', damage: b.damage, base: b.base, growth: b.growth, angle: b.angle, heavy: !!b.heavy, kind: 'melee', applies: b.applies, knockbackMul: b.knockbackMul, shieldDamageMul: b.shieldDamageMul, unblockable: b.unblockable }, hitVictims: new Set(), rect: rectFrom(b.x, b.y, b.size[0], b.size[1]), hitsOwner: !!b.hitsOwner };
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
      const mine = { type: 'mine', owner: f, x: f.x + s.offset[0] * f.facing, y: f.y, hp: s.hp, life: s.lifetime, trigger: s.trigger, radius: s.radius, armed: 20, destructible: true,
        blast: { damage: 12, base: 26, growth: 4.0, angle: 70, ...(s.blast || {}) } };
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
              this.spawnBurst(s.owner, { x: s.x, y: s.y + 1, ...s.blast, frames: 3, size: [s.radius * 2, s.radius * 2], heavy: true });
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
    const it = { def, x, y, vx: 0, vy: 0, held: null, uses: def.uses, life: ITEM_CFG.despawnAfter * 60, onGround: false, cd: 0, hp: def.guard ? def.guard.hp : 0 };
    this.items.push(it);
    this.emit({ type: 'itemspawn', x, y, item: def.id });
    return it;
  }
  giveItem(f, def) { const it = { def, x: f.x, y: f.y, vx: 0, vy: 0, held: f, uses: def.uses, life: 0, onGround: false, cd: 0, hp: def.guard ? def.guard.hp : 0 }; this.items.push(it); f.item = it; }
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
    if (it.uses <= 0 && it.def.kind === 'shoot') this.removeItem(it);   // an empty gun is litter
    if (f.state === 'attack' && f.move && f.move.id === 'ItemSwing') f.endMove();
    this.emit({ type: 'itemdrop', x: it.x, y: it.y });
  }
  removeItem(it) { const i = this.items.indexOf(it); if (i >= 0) this.items.splice(i, 1); if (it.held) it.held.item = null; }

  // One verb per item. `button` is 'light' or 'heavy'; heavy always throws whatever you are
  // holding, which is the universal escape hatch and the reason no item can trap you in a stance.
  useItem(f, button) {
    const it = f.item; if (!it) return;
    const def = it.def;

    // Heavy throws it, on every item. The Bulwark is the exception while it still has hit points:
    // throwing a shield you are actively hiding behind by pressing the same button you bash with
    // was the first thing that felt wrong in testing.
    const wantsThrow = button === 'heavy' && !(def.id === 'Bulwark' && it.hp > 0 && f.onGround);
    if (wantsThrow && def.thrown) { this.throwItem(f, it, def.thrown); return; }

    if (def.kind === 'throw') {
      const T = def.throw;
      const pr = {
        owner: f, x: f.x + f.facing * 1.5, y: f.y + 3,
        vx: f.facing * T.vx + f.vx * 0.5, vy: T.vy, w: T.size[0], h: T.size[1],
        life: T.fuse, gravity: T.gravity, hitVictims: new Set(), facing: f.facing, item: true,
        shape: def.id, itemDef: def,
      };
      if (def.explode) {
        pr.move = { id: def.id, damage: def.explode.damage, base: def.explode.base, growth: def.explode.growth, angle: def.explode.angle, kind: 'melee', heavy: true };
        pr.explode = def.explode;
        // `volatile` makes the keg a hazard for everyone, the thrower included: any melee hitbox
        // that touches it sets it off. See the volatile check in resolveMelee.
        pr.volatile = !!def.volatile;
      } else if (def.stick) {
        pr.move = { id: def.id, damage: def.stick.damage, base: 4, growth: 0.1, angle: 80, kind: 'melee' };
        pr.stick = def.stick;
      }
      pr.rect = rectFrom(pr.x, pr.y, pr.w, pr.h);
      this.projectiles.push(pr);
      this.removeItem(it);
      f.lag = 12; f.setState('landing');
      this.emit({ type: 'throwitem', x: f.x, y: f.cy, item: def.id });
      return;
    }

    if (def.kind === 'shoot') {
      if (it.cd > 0) return;
      const S = def.shot;
      const pr = {
        owner: f, move: { id: 'Rivet', damage: S.damage, base: S.base, growth: S.growth, angle: S.angle, kind: 'melee', extraHitstun: S.extraHitstun },
        x: f.x + f.facing * 1.8, y: f.y + 3.1, vx: f.facing * S.speed, vy: 0,
        w: S.size[0], h: S.size[1], life: S.lifetime, gravity: 0, hitVictims: new Set(),
        facing: f.facing, item: true, shape: 'rivet', itemDef: def,
      };
      pr.rect = rectFrom(pr.x, pr.y, pr.w, pr.h);
      this.projectiles.push(pr);
      it.cd = S.cooldown;
      it.uses--;
      f.lag = 4; f.setState('landing');
      this.emit({ type: 'rivet', x: pr.x, y: pr.y, facing: f.facing });
      if (it.uses <= 0) { this.removeItem(it); this.emit({ type: 'itembreak', x: f.x, y: f.cy }); }
      return;
    }

    if (def.kind === 'place') {
      if (!f.onGround) return;                       // a plate needs a floor to sit on
      const P = def.plate;
      this.plates.push({ x: f.x, y: f.y, w: P.size[0], h: P.size[1], vy: P.vy, life: P.life, cd: 0, owner: f });
      this.removeItem(it);
      f.lag = 10; f.setState('landing');
      this.emit({ type: 'placeitem', x: f.x, y: f.y, item: def.id });
      return;
    }

    if (def.kind === 'hold') {
      const sw = { ...def.bash, id: 'ItemSwing', kind: 'melee', total: def.bash.startup + def.bash.active + def.bash.recovery };
      f.startMove(sw);
      return;
    }
  }

  throwItem(f, it, T) {
    const pr = {
      owner: f, move: { id: 'ThrownItem', damage: T.damage, base: T.base, growth: T.growth, angle: T.angle, kind: 'melee' },
      x: f.x + f.facing * 1.5, y: f.y + 3, vx: f.facing * T.speed, vy: 4,
      w: T.size[0], h: T.size[1], life: T.lifetime, gravity: 40, hitVictims: new Set(),
      facing: f.facing, item: true, shape: it.def.id, itemDef: it.def,
    };
    pr.rect = rectFrom(pr.x, pr.y, pr.w, pr.h);
    this.projectiles.push(pr);
    this.removeItem(it);
    f.lag = 12; f.setState('landing');
    this.emit({ type: 'throwitem', x: f.x, y: f.cy, item: it.def.id });
  }

  // ---------- spring plates ----------
  // A placed plate is part of the STAGE, not a hitbox: it never damages anyone and it does not
  // care who put it there. Whoever comes down on it goes up.
  stepPlates() {
    for (let i = this.plates.length - 1; i >= 0; i--) {
      const pl = this.plates[i];
      pl.life--; if (pl.cd > 0) pl.cd--;
      if (pl.life <= 0) { this.plates.splice(i, 1); this.emit({ type: 'itemgone', x: pl.x, y: pl.y }); continue; }
      if (pl.cd > 0) continue;
      for (const v of this.fighters) {
        if (!v.alive || v.untouchable) continue;
        if (Math.abs(v.x - pl.x) > pl.w / 2 + v.r) continue;
        if (v.y > pl.y + 2.2 || v.y < pl.y - 1.6) continue;
        if (v.vy > 12) continue;                     // already going up: do not re-launch a rise
        v.vy = pl.vy; v.onGround = false; v.platform = null;
        v.jumpsLeft = Math.max(v.jumpsLeft, 1);      // a plate gives you your options back
        if (v.state === 'idle' || v.state === 'run' || v.state === 'landing' || v.state === 'shield') v.setState('air');
        pl.cd = 24;
        this.emit({ type: 'spring', x: pl.x, y: pl.y, fighter: v.index });
        break;
      }
    }
  }

  stepItems() {
    for (let i = this.items.length - 1; i >= 0; i--) {
      const it = this.items[i];
      if (it.held) {
        if (it.cd > 0) it.cd--;
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
