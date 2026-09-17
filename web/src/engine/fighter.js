import { FRAME, GRAVITY, LAUNCH_DRAG, TUMBLE_THRESHOLD, MOVE, SHIELD, LEDGE, DASH, SPOT_DODGE, AIR_DODGE, GROUND_POUND, GRAB, TECH, KNOCKDOWN, TAUNT_FRAMES, RESPAWN, INPUT_BUFFER, ULTIMATE } from '../config.js';
import { hitstun as hitstunFor, velocity as launchVelocity, blockstun as blockstunFor } from './knockback.js';
import { emptyFrame } from './input.js';

const sign = (v) => (v < 0 ? -1 : 1);
// The ceiling on any environmental acceleration, in studs/s².
//
// This was 130 — deliberately "just under gravity (150) so a hazard can never fling you" — which
// sounds right and is completely wrong: it meant no updraft in the game could lift anybody at
// all. A vent parked under a fighter for thirty seconds raised them thirteen studs. Anything that
// is supposed to hold you up has to beat gravity or it is not holding you up.
//
// 260 gives a maximum net rise of 110 studs/s², which is under a fighter's own jump (a jump
// starts at 63 studs/s and a strong updraft tops out around 40), so a hazard can carry you but
// still cannot out-move you. That is the line: hazards beat gravity, players beat hazards.
const ENV_MAX = 260;
const clampEnv = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);

const NO_GRAVITY_STATES = new Set(['ledge', 'grabbed', 'holding', 'frozen', 'tether', 'ko', 'respawn', 'ledgeaction']);

export class Fighter {
  constructor(opts) {
    this.index = opts.index;
    this.char = opts.char;
    this.skin = opts.skin || 0;
    this.team = opts.team == null ? opts.index : opts.team;
    this.source = opts.source || 'bot';
    this.isBot = !!opts.isBot;
    this.botLevel = opts.botLevel || 'normal';
    this.name = opts.name || this.char.name;
    this.r = this.char.radius;
    this.h = this.char.height;
    this.weight = this.char.weight;
    this.stocks = opts.stocks == null ? 3 : opts.stocks;
    this.percent = 0;
    this.alive = true;
    this.stats = { kos: 0, falls: 0, damageDealt: 0, damageTaken: 0, selfDestructs: 0 };
    this.input = emptyFrame();
    this.buffer = { jump: 0, light: 0, heavy: 0, dodge: 0, guard: 0, grab: 0, taunt: 0, ult: 0, pickup: 0 };
    this.frameCount = 0;
    this.item = null;
    this.effects = { chill: { stacks: 0, timer: 0 }, tangle: { stacks: 0, timer: 0 }, grit: { hide: 0, slow: 0 }, slow: 0, frozenBonus: false };
    this.mech = this._initMechanic();
    this.reset(opts.x || 0, opts.y || 0);
  }

  _initMechanic() {
    const m = this.char.mechanic;
    if (!m) return {};
    switch (m.id) {
      case 'Bloom': return { id: 'Bloom', hits: [], bloomed: false, timer: 0, cooldown: 0 };
      case 'Fruiting': return { id: 'Fruiting', ring: 0 };
      case 'Light': return { id: 'Light', segments: 0, still: 0 };
      case 'Tangle': return { id: 'Tangle' };
      case 'Spines': return { id: 'Spines', spines: m.max, regen: 0 };
      case 'Momentum': return { id: 'Momentum', runFrames: 0, ready: false };
      case 'Brace': return { id: 'Brace', guardFrames: 0, ready: false };
      case 'Network': return { id: 'Network' };
      case 'Chill': return { id: 'Chill' };
      default: return { id: m.id };
    }
  }

  reset(x, y, opts = {}) {
    this.x = x; this.y = y; this.prevX = x; this.prevY = y;
    this.vx = 0; this.vy = 0;
    this.facing = x < 0 ? 1 : -1;
    this.onGround = false; this.platform = null;
    this.jumpsLeft = this.char.jumps; this.airDodgeUsed = false; this.recoveryUsed = false; this.ledgeGrabs = 0; this.fastFalling = false;
    this.dropTimer = 0; this.ledgeCooldown = 0;
    this.state = opts.state || 'respawn'; this.sf = 0;
    this.shield = SHIELD.max; this.blockstun = 0;
    this.hitstun = 0; this.hitlag = 0; this.tumbling = false; this.pendingLaunch = null;
    this.invincible = opts.invincible == null ? RESPAWN.invinc : opts.invincible;
    this.move = null; this.moveId = null; this.mf = 0; this.startupEff = 0; this.startupShift = 0; this.hitVictims = new Map(); this.moveLanded = false; this.charge = 0; this.armorUsed = false;
    this.bonusDamage = 0; this.launchMul = 1;
    this.hold = null; this.holder = null; this.la = null; this.lag = 0; this.tether = null; this.frozenFrames = 0;
    this.di = { x: 0, y: 0 };
    this.techPress = 0; this.techRoll = 0; this.volleyCount = 0; this.rangeMul = 1; this.chargeMods = null; this.noGravityFrame = false;
    // Ultimate meter. reset() runs on respawn, so losing a stock wipes the charge.
    this.ultCharge = 0; this.ultActive = 0;
    this.ultTarget = null; this.ultHeld = []; this.ultShots = 0; this.ultCooldown = 0; this.ultEndAt = 0;
    this.carryX = 0;
    this.lastHitBy = null; this.lastHitFrame = -9999;
    this.inWater = false;
    // What the stage is doing to this fighter THIS FRAME. Zeroed by the stage before hazards run
    // (see StageRuntime.step), written by hazards.js, read by _physics and _friction. Keeping it
    // in one bag means a hazard never reaches into the state machine, and the state machine never
    // learns which hazards exist.
    this.env = { updraft: 0, windX: 0, traction: 1, grip: 1, damp: 1 };
    // Wind is carried in its OWN velocity, not folded into vx.
    //
    // Folding it into vx did not work and the measurements were brutal: _stepState runs before
    // _physics, and _airDrift pulls vx toward +/-airSpeed at airSpeed/airAccelFrames = 108
    // studs/s^2. Every horizontal hazard force in the game is under half that (crosswind 46,
    // roguewave 58, sprinkler 54, dust devil 44). So any player touching the stick erased the
    // wind completely: a full Span gust moved the recovery envelope by ONE stud, and only for a
    // player who was not holding a direction. Wind mattered to people who were not playing.
    //
    // carryX is added at the position step instead, so drift and wind compose rather than fight.
    this.carryX = 0;
    this.effects.chill = { stacks: 0, timer: 0 }; this.effects.tangle = { stacks: 0, timer: 0 }; this.effects.grit = { hide: 0, slow: 0 }; this.effects.slow = 0; this.effects.frozenBonus = false;
    this.effects.lodestone = 0; this.effects.lodestoneDef = null;
    if (opts.percent != null) this.percent = opts.percent;
    if (this.mech.id === 'Momentum') { this.mech.runFrames = 0; this.mech.ready = false; }
    if (this.mech.id === 'Brace') { this.mech.guardFrames = 0; this.mech.ready = false; }
    if (this.mech.id === 'Light') { this.mech.segments = 0; this.mech.still = 0; }
    if (this.mech.id === 'Surge') { this.mech.hits = []; this.mech.surged = false; this.mech.timer = 0; }
    if (this.mech.id === 'Draw') { this.mech.draw = 0; this.mech.ready = false; }
    if (this.mech.id === 'Snare') { this.mech.snared = null; this.mech.timer = 0; this.mech.ready = false; }
    this.item = null;
    this.events = [];
  }

  // ---------- helpers ----------
  get hurtbox() { return { x1: this.x - this.r, x2: this.x + this.r, y1: this.y, y2: this.y + this.h }; }
  get cy() { return this.y + this.h / 2; }
  get isInvincible() { return this.invincible > 0; }
  get inHitstun() { return this.state === 'hitstun'; }
  get busy() { return !['idle', 'run', 'air'].includes(this.state); }
  speedMul() {
    let m = 1 - 0.08 * this.effects.chill.stacks;
    if (this.effects.grit.slow > 0) m *= 0.9;
    if (this.effects.slow > 0) m *= 0.8;
    // Carrying a Bulwark is slow. That is the cost, and it is the reason you drop it when the
    // fight turns back into a chase.
    if (this.item && this.item.def.guard && this.item.hp > 0) m *= this.item.def.guard.speedMul;
    // Drawing a bow is not something you do while moving.
    if (this.mech.id === 'Draw' && this.mech.draw > 6) m *= this.char.mechanic.slowMul;
    if (this.inWater) m *= 0.4;
    return m;
  }
  jumpMul() {
    const L = this.effects.lodestone > 0 ? this.effects.lodestoneDef : null;
    return (1 - 0.08 * this.effects.chill.stacks) * (L ? L.jumpMul : 1);
  }
  setState(s) { this.state = s; this.sf = 0; }
  get ultReady() { return this.ultCharge >= ULTIMATE.hitsRequired && !!this.char.moves.Ultimate; }
  get ultMeter() { return Math.min(1, this.ultCharge / ULTIMATE.hitsRequired); }
  // Called by combat when this fighter lands a real hit. Chip and tick damage do not charge.
  // The meter fills for everyone; whether it can be SPENT is the weapon's business (ultReady).
  chargeUltimate(n = 1) {
    const was = this.ultReady;
    this.ultCharge = Math.min(ULTIMATE.hitsRequired, this.ultCharge + n);
    if (!was && this.ultReady) this.emit({ type: 'ultready' });
  }
  consume(b) { if (this.buffer[b] > 0) { this.buffer[b] = 0; return true; } return false; }
  emit(e) { this.events.push(e); }

  applyInput(frame) {
    this.input = frame;
    for (const b of ['jump', 'light', 'heavy', 'dodge', 'guard', 'grab', 'taunt', 'ult', 'pickup']) if (frame[b]) this.buffer[b] = INPUT_BUFFER;
    // Teching has its own window (TECH.window = 8) which is wider than INPUT_BUFFER, so it cannot
    // be expressed as a guard-buffer threshold.
    if (frame.guard) this.techPress = TECH.window;
  }

  // ---------- main step ----------
  step(ctx) {
    this.frameCount++;
    // DI is re-sampled every frame, hitlag included: the stick held when the freeze ends is the
    // one that bends the launch angle. See _applyLaunch.
    this.di = { x: this.input.x, y: this.input.y };
    if (!this.alive) return;
    if (this.hitlag > 0) {
      // Buffers deliberately do NOT tick here. Hitlag runs up to HITLAG_CAP (12) frames, longer
      // than INPUT_BUFFER (6), so ticking during the freeze silently ate every escape input.
      this.hitlag--;
      if (this.hitlag === 0 && this.pendingLaunch) this._applyLaunch();
      return;
    }
    for (const k in this.buffer) if (this.buffer[k] > 0) this.buffer[k]--;
    this._tickTimers();
    this.sf++;
    this.prevX = this.x; this.prevY = this.y;
    this.noGravityFrame = false;
    this._stepState(ctx);
    this._physics(ctx);
    this._mechanicsFrame(ctx);
    // Ticked last, so a guard pressed on the same frame a landing resolves still counts. The
    // window is TECH.window frames wide with the press frame included.
    if (this.techPress > 0) this.techPress--;
  }

  _tickTimers() {
    if (this.invincible > 0) this.invincible--;
    if (this.ledgeCooldown > 0) this.ledgeCooldown--;
    if (this.dropTimer > 0) this.dropTimer--;
    const e = this.effects;
    if (e.chill.timer > 0 && --e.chill.timer === 0) e.chill.stacks = 0;
    if (e.tangle.timer > 0 && --e.tangle.timer === 0) e.tangle.stacks = 0;
    if (e.grit.hide > 0) e.grit.hide--;
    if (e.grit.slow > 0) e.grit.slow--;
    if (e.slow > 0) e.slow--;
    if (e.lodestone > 0 && --e.lodestone === 0) e.lodestoneDef = null;
    if (this.state !== 'shield') this.shield = Math.min(SHIELD.max, this.shield + SHIELD.regenPerSec * FRAME);
  }

  // Runs on the frame hitlag ends. The launch vector is built here rather than at hit time so
  // that DI held during the freeze actually counts (design doc: "hold a direction while hit").
  // combat.js overwrites pendingLaunch with a raw {vx, vy} for drag moves; that shape passes through.
  _applyLaunch() {
    const p = this.pendingLaunch;
    this.pendingLaunch = null;
    let vx, vy;
    if (p.vx !== undefined) { vx = p.vx; vy = p.vy; }
    else {
      const v = launchVelocity(p.launch, p.angle, p.facing, this.di);
      vx = v.vx; vy = v.vy;
      if (this.onGround && vy < 0) vy = -vy * 0.8;
    }
    this.vx = vx; this.vy = vy;
    if (vy > 0.5 || !this.onGround) { this.onGround = false; this.platform = null; }
  }

  _stepState(ctx) {
    switch (this.state) {
      case 'idle': case 'run': return this._stepGround(ctx);
      case 'jumpsquat': return this._stepJumpsquat();
      case 'air': case 'helpless': return this._stepAir(ctx);
      case 'attack': return this._stepAttack(ctx);
      case 'landing': if (this.sf > this.lag) this.setState('idle'); this._friction(); return;
      case 'dash': return this._stepDash(ctx);
      case 'spotdodge': this._friction(); if (this.sf > SPOT_DODGE.frames) this.setState('idle'); return;
      case 'airdodge': return this._stepAirDodge();
      case 'shield': return this._stepShield(ctx);
      case 'shielddrop': this._friction(); if (this.sf > SHIELD.dropFrames) this.setState('idle'); return;
      case 'stunned': this._friction(); if (this.sf > SHIELD.breakStun) this.setState('idle'); return;
      case 'hitstun': return this._stepHitstun();
      case 'knockdown': this._friction(); if (this.sf > KNOCKDOWN.frames) this.setState('idle'); return;
      case 'tech': return this._stepTech();
      case 'ledge': return this._stepLedge(ctx);
      case 'ledgeaction': return this._stepLedgeAction(ctx);
      case 'grab': return this._stepGrab(ctx);
      case 'holding': return this._stepHolding(ctx);
      case 'grabbed': return;
      case 'groundpound': return this._stepGroundPound();
      case 'recovery': if (this.sf > 18) this.setState('helpless'); return;
      case 'tether': return this._stepTether(ctx);
      case 'frozen': return this._stepFrozen();
      case 'taunt': this._friction(); if (this.sf > TAUNT_FRAMES || (this.sf > 10 && this.input.anyPress)) this.setState('idle'); return;
      case 'respawn': return this._stepRespawn();
      case 'ko': return;
    }
  }

  // ---------- ground ----------
  _stepGround(ctx) {
    const inp = this.input;
    if (inp.downTap && this.platform && this.platform.soft) { this.dropThrough(); return; }
    if (this.consume('jump')) { this.setState('jumpsquat'); return; }
    if (this.item) {
      if (this.consume('light')) { ctx.combat.useItem(this, 'light'); return; }
      if (this.consume('heavy')) { ctx.combat.useItem(this, 'heavy'); return; }
    }
    if (this.consume('grab') || (this.buffer.light > 0 && inp.guardHeld)) { this.buffer.light = 0; this._startGrab(); return; }
    if (this.consume('light')) { this._startGroundLight(inp); return; }
    if (this.consume('heavy')) { this._startGroundHeavy(inp, ctx); return; }
    if (this.consume('dodge')) { if (Math.abs(inp.x) > 0.5) this._startDash(sign(inp.x)); else this.setState('spotdodge'); return; }
    // Pick up / drop. `pickup` is its own button now: it was declared in the input frame from the
    // beginning, bound to nothing and read by nothing, so the only way to take an item was to tap
    // guard next to it - undiscoverable, and impossible for a bot to stumble into. Guard still
    // works, because that is what anyone who learned it the old way will press.
    if (this.consume('pickup') || this.consume('guard')) {
      if (this.item && inp.y < -0.5) { ctx.combat.dropItem(this, false); return; }
      const it = ctx.combat.itemNear(this);
      if (it && !this.item) { ctx.combat.pickupItem(this, it); return; }
    }
    if (inp.guardHeld) { this.setState('shield'); return; }
    if (this._tryUltimate(ctx)) return;
    if (this.consume('taunt')) { this.setState('taunt'); return; }
    this._groundMove(inp);
  }

  _groundMove(inp) {
    const run = Math.abs(inp.x) >= 0.5, walk = Math.abs(inp.x) > 0.15;
    const speed = (run ? this.char.runSpeed : this.char.walkSpeed) * this.speedMul();
    // env.grip is the slick's effect on ACCELERATION, as distinct from env.traction which is its
    // effect on stopping. It was being written by the sprinkler and read by nothing at all, so a
    // wet roof cost you your brakes but not your launch. Floored at 0.3 for the same reason
    // traction is: a stage may make you clumsy, never helpless.
    const accel = (this.char.runSpeed / MOVE.groundAccelFrames) * Math.max(0.3, this.env.grip);
    if (walk) {
      this.facing = sign(inp.x);
      const target = sign(inp.x) * speed;
      if (this.vx < target) this.vx = Math.min(target, this.vx + accel); else if (this.vx > target) this.vx = Math.max(target, this.vx - accel);
      this.state = run ? 'run' : 'idle';
    } else {
      this._friction();
      this.state = Math.abs(this.vx) > 0.5 ? this.state : 'idle';
      if (this.state === 'run') this.state = 'idle';
    }
  }

  _friction() {
    if (!this.onGround) return;
    // Traction floors at 0.25: a slick surface should cost you your stop, never your agency.
    const decel = (this.char.runSpeed / MOVE.groundStopFrames) * Math.max(0.25, this.env.traction);
    if (Math.abs(this.vx) <= decel) this.vx = 0; else this.vx -= sign(this.vx) * decel;
  }

  _airDrift(inp, mul = 1) {
    // A stuck Lodestone takes most of your air control away. Combined with the fall speed below,
    // the recovery you have learned stops reaching - which is the whole item.
    const L = this.effects.lodestone > 0 ? this.effects.lodestoneDef : null;
    const target = inp.x * this.char.airSpeed * mul * (L ? L.airMul : 1) * this.speedMul();
    const accel = this.char.airSpeed / MOVE.airAccelFrames;
    if (Math.abs(inp.x) > 0.15) {
      if (this.vx < target) this.vx = Math.min(target, this.vx + accel); else if (this.vx > target) this.vx = Math.max(target, this.vx - accel);
    } else {
      this.vx *= MOVE.airDrag;
    }
  }

  dropThrough() {
    if (!this.platform || !this.platform.soft) return;
    this.dropTimer = 10; this.onGround = false; this.platform = null; this.vy = -2;
    if (this.state === 'idle' || this.state === 'run') this.setState('air');
  }

  _stepJumpsquat() {
    this._friction();
    if (this.sf >= MOVE.jumpsquat) {
      this.vy = this.char.jumpVelocity * this.jumpMul();
      if (!this.input.jumpHeld) this.vy *= MOVE.shortHopMul;
      this.onGround = false; this.platform = null; this.jumpsLeft = this.char.jumps - 1;
      this.fastFalling = false;
      this.setState('air');
      this.emit({ type: 'jump' });
    }
  }

  _startGroundLight(inp) {
    if (inp.y < -0.5) return this.startMove('LightDown');
    // Up + Light. Without this the up-light was reachable only as a chain link, which stranded any
    // weapon whose kill confirm ran through it.
    if (inp.y > 0.5 && this.char.moves.LightUp) return this.startMove('LightUp');
    if (Math.abs(inp.x) > 0.5) { this.facing = sign(inp.x); return this.startMove('LightSide1'); }
    return this.startMove('LightNeutral1');
  }

  _startGroundHeavy(inp, ctx) {
    if (inp.y < -0.5) {
      if (this.mech.id === 'Fruiting' && this.mech.ring >= this.char.mechanic.ringMax && ctx.combat.hasFruit(this)) { ctx.combat.fruiting(this); return; }
      return this.startMove('SigDown');
    }
    if (Math.abs(inp.x) > 0.5) { this.facing = sign(inp.x); return this.startMove('SigSide'); }
    // Neutral Heavy is its own signature when the loadout defines one, else it reuses the side sig.
    return this.startMove(this.char.moves.SigNeutral ? 'SigNeutral' : 'SigSide');
  }

  _startDash(dir) {
    this.facing = dir;
    this.vx = dir * this.char.runSpeed * DASH.speedMul * this.speedMul();
    this.setState('dash');
    this.emit({ type: 'dash' });
  }

  _stepDash(ctx) {
    const inp = this.input;
    this.vx = this.facing * this.char.runSpeed * DASH.speedMul * this.speedMul();
    if (this.sf >= 4 && this.consume('jump')) { this.setState('jumpsquat'); return; }
    if (this.sf >= DASH.cancelLightFrom) {
      if (this.consume('light')) { this._startGroundLight(inp); return; }
      if (this.consume('heavy')) { this._startGroundHeavy(inp, ctx); return; }
    }
    if (this.sf >= DASH.cancelShieldFrom && inp.guardHeld) { this.setState('shield'); return; }
    if (this.mech.id === 'Momentum') this.mech.runFrames++;
    if (this.sf > DASH.frames) { this.vx = this.facing * this.char.runSpeed * this.speedMul(); this.setState('run'); }
  }

  // ---------- air ----------
  _stepAir(ctx) {
    const inp = this.input;
    if (this.state === 'helpless') {
      this._airDrift(inp, 0.6);
      if (this.consume('dodge') && !this.airDodgeUsed) this._startAirDodge(inp);
      return;
    }
    if (this.jumpsLeft > 0 && this.consume('jump')) {
      this.jumpsLeft--; this.vy = this.char.jumpVelocity * this.jumpMul(); this.fastFalling = false; this.tumbling = false;
      if (Math.abs(inp.x) > 0.5) this.facing = sign(inp.x);
      this.emit({ type: 'doublejump' });
    }
    if (this._tryUltimate(ctx)) return;
    if (this.consume('light')) { this._startAerial(inp); return; }
    if (this.consume('heavy')) { if (inp.y < -0.5) this._startGroundPound(); else this._startRecovery(ctx); return; }
    if (this.consume('dodge') && !this.airDodgeUsed) { this._startAirDodge(inp); return; }
    if ((inp.downTap || (inp.y < -0.5 && this.vy < 0 && this.vy > -6)) && this.vy <= 0 && !this.fastFalling) { this.fastFalling = true; this.emit({ type: 'fastfall' }); }
    this._airDrift(inp);
  }

  // Spending the meter is all-or-nothing: the whole bar goes, and the move gets a short window of
  // invincibility on startup so an ultimate cannot simply be poked out of the air the frame it starts.
  _tryUltimate(ctx) {
    if (this.buffer.ult <= 0) return false;
    if (!this.ultReady) { this.buffer.ult = 0; this.emit({ type: 'ultdenied' }); return false; }
    // A slam that opens the floor has to be standing on one. Without this the crater fired all
    // its bursts mid-air while the "planted in the floor" pose played in open sky.
    if (this.char.moves.Ultimate.grounded && !this.onGround) { this.emit({ type: 'ultdenied' }); return false; }
    this.buffer.ult = 0;
    this.ultCharge = 0;
    this.ultActive = 1;
    // ULTIMATE.freezeFrames was declared in config and never read by anything: activating an
    // ultimate had no moment at all. Everyone freezes, the CASTER INCLUDED - it is a beat of
    // theatre, not an advantage, and freezing only the victims would make every ultimate
    // unavoidable (Colossus's blade lands on frame 25 of a 26-frame freeze).
    if (ctx && ctx.combat) for (const v of ctx.combat.fighters) v.hitlag = Math.max(v.hitlag, ULTIMATE.freezeFrames);
    this.invincible = Math.max(this.invincible, ULTIMATE.invincibleFrames);
    this.emit({ type: 'ultimate', move: 'Ultimate', label: this.char.moves.Ultimate.label, weapon: this.char.weapon ? this.char.weapon.id : null, fighter: this.index, x: this.x, y: this.cy });
    this.startMove('Ultimate');
    return true;
  }

  _startAerial(inp) {
    this.tumbling = false;
    if (inp.y < -0.5) return this.startMove('AirDown');
    if (inp.y > 0.5 && this.char.moves.AirUp) return this.startMove('AirUp');
    if (Math.abs(inp.x) > 0.5) { this.facing = sign(inp.x); return this.startMove('AirForward'); }
    return this.startMove('AirNeutral');
  }

  _startAirDodge(inp) {
    this.airDodgeUsed = true; this.tumbling = false; this.fastFalling = false;
    const len = Math.hypot(inp.x, inp.y);
    if (len > 0.3) { this.vx = (inp.x / len) * 36; this.vy = (inp.y / len) * 36; } else { this.vx = 0; this.vy = 0; }
    this.setState('airdodge');
    this.emit({ type: 'dodge' });
  }

  _stepAirDodge() {
    if (this.sf <= 10) { this.vx *= 0.85; this.vy *= 0.85; this.noGravityFrame = true; }
    if (this.sf > AIR_DODGE.frames) this.setState('air');
  }

  _startGroundPound() {
    this.tumbling = false; this.fastFalling = false; this.vx = 0; this.vy = 0;
    this.hitVictims = new Map();
    this.setState('groundpound');
  }

  _stepGroundPound() {
    if (this.sf <= GROUND_POUND.hang) { this.vy = 0; this.vx *= 0.8; this.noGravityFrame = true; }
    else { this.vy = -GROUND_POUND.speed; this.noGravityFrame = true; }
  }

  _startRecovery(ctx) {
    if (this.recoveryUsed) return;
    this.recoveryUsed = true; this.tumbling = false; this.fastFalling = false;
    const rec = this.char.recovery; const inp = this.input;
    const dir = Math.abs(inp.x) > 0.3 ? sign(inp.x) : this.facing;
    const stage = ctx.stage;
    this.emit({ type: 'recovery', kind: rec.kind });
    if (rec.kind === 'tether') {
      const { ledge, dist } = stage.nearestLedge(this.x, this.cy);
      const outside = (this.x - ledge.x) * ledge.side > -2 || this.y < ledge.y - 2;
      if (ledge && dist <= rec.range && outside && this.ledgeGrabs < LEDGE.maxGrabs) {
        this.tether = { ledge, tx: ledge.x + ledge.side * LEDGE.hangOffsetX, ty: ledge.y + LEDGE.hangOffsetY, speed: rec.speed };
        this.vx = 0; this.vy = 0; this.facing = -ledge.side;
        this.setState('tether');
        return;
      }
      this.vy = rec.hopVy; this.vx = (stage.main.cx > this.x ? 1 : -1) * this.char.airSpeed; this.facing = sign(this.vx);
      this.setState('recovery'); return;
    }
    if (rec.kind === 'teleport') {
      const node = ctx.combat.nearestNode(this, rec.range);
      if (node) {
        ctx.combat.removeSummon(node);
        this.x = node.x; this.y = node.y + 0.1; this.vx = 0; this.vy = 6;
        this.emit({ type: 'teleport', x: node.x, y: node.y });
        this.setState('recovery'); return;
      }
      this.vy = rec.puffVy; this.vx = dir * rec.puffVx; this.setState('recovery'); return;
    }
    if (rec.kind === 'puff') { this.vy = rec.vy; this.vx = dir * rec.vx; this.setState('recovery'); return; }
    // hop
    this.vy = rec.vy * this.jumpMul(); this.vx = dir * rec.vx; this.facing = dir;
    this.setState('recovery');
  }

  _stepTether(ctx) {
    const t = this.tether;
    const dx = t.tx - this.x, dy = t.ty - this.y, d = Math.hypot(dx, dy);
    const stepLen = t.speed * FRAME;
    this.noGravityFrame = true; this.vx = 0; this.vy = 0;
    if (d <= stepLen) { this.x = t.tx; this.y = t.ty; this.tether = null; this.grabLedge(t.ledge); return; }
    this.x += (dx / d) * stepLen; this.y += (dy / d) * stepLen;
    if (this.sf > 60) { this.tether = null; this.setState('helpless'); }
  }

  // ---------- attacks ----------
  startMove(moveOrId, opts = {}) {
    const move = typeof moveOrId === 'string' ? this.char.moves[moveOrId] : moveOrId;
    if (!move) return;
    if (move.ammo && this.mech.id === 'Spines') {
      if ((this.mech.spines || 0) < move.ammo) { this.emit({ type: 'dryfire' }); return; }
      this.mech.spines -= move.ammo;
    }
    this.move = move; this.moveId = move.id; this.mf = 0; this.moveLanded = false; this.hitVictims = new Map();
    this.charge = 0; this.armorUsed = false; this.volleyCount = 0; this.spawnedActive = false;
    // per-ultimate scratch: who the sniper painted, who the vortex is holding, shots left
    this.ultTarget = null; this.ultHeld = []; this.ultShots = 0; this.ultCooldown = 0; this.ultEndAt = 0;
    this.bonusDamage = 0; this.launchMul = 1; this.rangeMul = 1; this.tumbling = false;
    this.startupEff = move.startup;
    // mechanic modifiers on move start
    const M = this.char.mechanic;
    // BRACE (Warpike): banked by holding shield, spent by a signature. Deliberately the mirror of
    // Momentum — one weapon is paid for moving, the other for refusing to.
    if (this.mech.id === 'Brace' && this.mech.ready && move.heavy) {
      this.bonusDamage += M.bonusDamage; this.launchMul *= M.launchMul;
      this.mech.ready = false; this.mech.guardFrames = 0;
      this.emit({ type: 'momentum' });
    }
    if (this.mech.id === 'Surge' && this.mech.surged) {
      if (M.startupCut) this.startupEff = Math.max(2, this.startupEff - M.startupCut);
      if (move.heavy) { this.bonusDamage += M.bonusDamage; this.launchMul *= M.launchMul; this.mech.surged = false; this.mech.hits = []; this.emit({ type: 'momentum' }); }
    }
    if (this.mech.id === 'Draw' && this.mech.ready && move.heavy) { this.bonusDamage += M.bonusDamage; this.launchMul *= M.launchMul; this.mech.ready = false; this.mech.draw = 0; this.emit({ type: 'momentum' }); }
    if (this.mech.id === 'Momentum' && this.mech.ready && move.heavy) { this.bonusDamage += M.bonusDamage; this.launchMul *= M.launchMul; this.mech.ready = false; this.mech.runFrames = 0; this.emit({ type: 'momentum' }); }
    else if (this.mech.id === 'Momentum') { this.mech.runFrames = 0; }   // spent by signatures only; a light does not burn it
    if (this.mech.id === 'Bloom' && this.mech.bloomed && move.heavy) { this.bonusDamage += M.bonusDamage; this.rangeMul = M.rangeMul; this.mech.bloomed = false; this.mech.cooldown = M.cooldownFrames; this.emit({ type: 'bloomspend' }); }
    if (this.mech.id === 'Light' && move.kind === 'beam' && this.mech.segments > 0) { this.startupEff = Math.max(4, move.startup - M.windupPerSegment * this.mech.segments); this.mech.segments = 0; }
    this.startupShift = move.startup - this.startupEff;
    this.setState('attack');
    this.emit({ type: 'movestart', move: move.id, heavy: !!move.heavy });
  }

  get moveActive() {
    if (this.state !== 'attack' || !this.move) return false;
    return this.mf > this.startupEff && this.mf <= this.startupEff + this.move.active;
  }
  get moveFrameAbs() { return this.mf + this.startupShift; }

  _stepAttack(ctx) {
    const m = this.move; const inp = this.input;
    if (!m) { this.setState(this.onGround ? 'idle' : 'air'); return; }
    // Charge holds at the last startup frame.
    if (m.charge && this.mf === this.startupEff && inp.heavyHeld && this.charge < m.charge.maxHold) {
      this.charge++;
      if (m.kind === 'burst' && this.mech.id === 'Light' && this.charge % m.charge.lightEvery === 0) this.mech.segments = Math.min(this.char.mechanic.segments, this.mech.segments + 1);
      if (this.onGround) this._friction();
      return;
    }
    this.mf++;
    const active = this.moveActive;
    const total = this.startupEff + m.active + m.recovery;
    if (m.stall && this.mf <= m.stall) { this.vy = 0; this.noGravityFrame = true; }
    // A GROUNDED lunge only drives while there is ground under it.
    //
    // It used to drive unconditionally, and because the airborne branch below was skipped for any
    // move with a lunge, a signature thrown near an edge carried its full drive speed off the
    // stage with no friction, no drift and no way to influence it. Crescent Rush leaves at 120
    // studs/s and Full Extension at 90, against an air drift that pulls back at 108 studs/s^2
    // toward a target of ~15 — so it took over a second to even turn the fighter around, by which
    // time they were through the blast zone. Both weapons self-destructed off their own signature.
    //
    // Now the drive cuts the moment the fighter is airborne, what it already imparted is capped to
    // a speed the fighter could have reached on their own, and drift is handed straight back.
    const groundLunge = m.lunge && m.grounded !== false;
    if (m.lunge && active && (this.onGround || !groundLunge)) {
      this.vx = this.facing * (m.lunge / m.active) / FRAME;
      // ...and it stops at the ledge. A lunge is the fighter stepping into their own swing, which
      // is not something anyone does off the side of a stage. Without this clamp a signature
      // started one stud from the edge walked its user straight into open air at 120 studs/s,
      // still in attack state, unable to act: thirty studs of the sixty to the blast zone, given
      // away for pressing a button while standing where the game asks you to stand.
      if (groundLunge && this.onGround && this.platform) {
        const pf = this.platform;
        const nx = this.x + this.vx * FRAME;
        if (nx > pf.x2 - 0.1) this.vx = Math.max(0, (pf.x2 - 0.1 - this.x) / FRAME);
        else if (nx < pf.x1 + 0.1) this.vx = Math.min(0, (pf.x1 + 0.1 - this.x) / FRAME);
      }
    }
    // A move can declare that it is a STANCE rather than a swing, and keep partial ground control
    // while it is live. Deadeye needs this: rooting a light fighter in place for two seconds in a
    // four-player match is a cost nobody would ever pay.
    else if (m.walkSpeed && active && this.onGround) {
      const target = inp.x * this.char.runSpeed * m.walkSpeed * this.speedMul();
      this.vx += (target - this.vx) * 0.22;
    }
    else if (this.onGround) {
      // A lunge is a STEP, not a shove. The drive speed used to be left in vx when the active
      // frames ended and bled off through friction over the whole recovery, so a move that
      // advertises 8 studs of lunge actually carried the fighter 40 - more than half the width of
      // Foundry Floor, from a standing start, with no input. Crescent Rush and Full Extension were
      // the worst because their drive speeds are the highest, and both of them slid their own user
      // off the stage. Stop the drive with the swing that produced it; the recovery is the fighter
      // planted, which is also what the animation shows.
      if (m.lunge && this.mf > this.startupEff + m.active) this.vx = 0;
      this._friction();
    }
    else {
      if (groundLunge) {
        const cap = this.char.airSpeed * 1.2;
        if (Math.abs(this.vx) > cap) this.vx = sign(this.vx) * cap;
      }
      this._airDrift(inp, 0.7);
    }
    if (m.fastFallActive && active && !this.onGround) this.vy = Math.min(this.vy, -this.char.fallSpeed * MOVE.fastFallMul);
    if (this._chainInto(m, inp)) return;
    if (this.mf === this.startupEff + 1 && !this.spawnedActive) { this.spawnedActive = true; ctx.combat.onMoveActive(this, m); }
    if (active) ctx.combat.onMoveActiveFrame(this, m);
    if (this.mf > total) this.endMove();
  }

  // Combo strings. Once a move has connected and its active frames are done, the follow-up is
  // chosen by the direction held: `chains` keyed by up/side/down/neutral, with `chainsTo` as the
  // fallback so single-branch strings still read as before. `chainsHeavy` lets a light string
  // cash out into a signature, which is what makes a weapon's combo tree worth learning.
  _chainInto(m, inp) {
    if (!this.moveLanded || this.mf < this.startupEff + m.active) return false;
    const dir = inp.y > 0.5 ? 'up' : inp.y < -0.5 ? 'down' : Math.abs(inp.x) > 0.5 ? 'side' : 'neutral';
    const go = (id, buf) => {
      if (!id || !this.char.moves[id]) return false;
      this.buffer[buf] = 0;
      if (dir === 'side') this.facing = sign(inp.x);
      this.startMove(id);
      return true;
    };
    if (this.buffer.heavy > 0 && m.chainsHeavy) {
      const id = typeof m.chainsHeavy === 'string' ? m.chainsHeavy : m.chainsHeavy[dir];
      if (go(id, 'heavy')) return true;
    }
    if (this.buffer.light > 0) {
      const id = (m.chains && m.chains[dir]) || m.chainsTo;
      if (go(id, 'light')) return true;
    }
    return false;
  }

  endMove() {
    if (this.moveId === 'Ultimate') { this.ultActive = 0; this.ultTarget = null; this.ultHeld = []; }
    this.move = null; this.moveId = null;
    this.setState(this.onGround ? 'idle' : 'air');
  }

  // Counter (Spine Guard) triggered: replace the move with a burst.
  triggerCounter(incomingDamage) {
    const m = this.move; const c = m.counter;
    const dmg = Math.max(c.minDamage, Math.round(incomingDamage * c.multiplier));
    const burst = { id: 'CounterBurst', label: 'Spine Burst', startup: 0, active: c.burstFrames, recovery: c.burstRecovery, damage: dmg, base: m.base, growth: m.growth, angle: m.angle, heavy: true, kind: 'melee', total: c.burstFrames + c.burstRecovery,
      hitboxes: [{ frames: [1, c.burstFrames], offset: c.hitbox.offset, size: c.hitbox.size }] };
    this.startMove(burst);
    if (this.mech.id === 'Spines') this.mech.spines = this.char.mechanic.max;
    this.emit({ type: 'counter' });
  }

  // ---------- shield ----------
  _stepShield(ctx) {
    const inp = this.input;
    this._friction();
    this.shield -= SHIELD.drainPerSec * FRAME;
    if (this.shield <= 0) { this.breakShield(); return; }
    if (this.blockstun > 0) { this.blockstun--; return; }
    if (this.consume('jump')) { this.setState('jumpsquat'); return; }
    if (this.consume('grab') || this.consume('light')) { this._startGrab(); return; }
    if (this.consume('dodge')) { this.setState('spotdodge'); return; }
    if (!inp.guardHeld) { this.setState('shielddrop'); return; }
  }

  breakShield() {
    this.shield = SHIELD.resetHp; this.blockstun = 0;
    this.setState('stunned');
    this.emit({ type: 'shieldbreak' });
  }

  applyBlock({ damage, facing, perfect }) {
    const stun = blockstunFor(damage);
    this.blockstun = perfect ? Math.floor(stun / 2) : stun;
    if (!perfect) this.shield -= damage * SHIELD.damageMul;
    this.vx = facing * (damage / 5) * 10;
    if (this.shield <= 0) this.breakShield();
  }

  // ---------- hits ----------
  applyHit(hit) {
    // hit: { damage, launch, angle, facing, attacker, hitlag, extraHitstun, applies, pull, trip, fixedVy }
    if (this.holder) this.holder.releaseHold();
    if (this.hold) this.releaseHold();
    this.percent = Math.min(999, this.percent + hit.damage);
    this.stats.damageTaken += hit.damage;
    this.lastHitBy = hit.attacker || null; this.lastHitFrame = this.frameCount;
    this.hitlag = hit.hitlag;
    if (hit.applies) this._applyEffects(hit.applies);
    if (this.mech.id === 'Light') this.mech.segments = Math.max(0, this.mech.segments - 1);
    if (this.mech.id === 'Momentum') { this.mech.runFrames = 0; this.mech.ready = false; }
    if (this.mech.id === 'Brace') { this.mech.guardFrames = 0; this.mech.ready = false; }
    // Surge and Draw are wiped by being hit, the same way Momentum and Brace are: every one of
    // these mechanics is a reward for pressure, and taking a hit is the opposite of pressure.
    if (this.mech.id === 'Surge') { this.mech.hits = []; this.mech.surged = false; }
    if (this.mech.id === 'Draw') { this.mech.draw = 0; this.mech.ready = false; }
    this.move = null; this.hold = null; this.tether = null; this.la = null;
    if (hit.trip && this.percent < hit.trip && this.onGround) { this.setState('knockdown'); this.sf = 6; this.vx = 0; return; }
    let launch = hit.launch;
    if (this.effects.frozenBonus) { launch *= 1.2; this.effects.frozenBonus = false; }
    // Deep water eats knockback. It is why the tide is a refuge at high percent as well as a trap.
    if (this.env.damp < 1) launch *= this.env.damp;
    this.hitstun = hitstunFor(launch) + (hit.extraHitstun || 0);
    if (hit.pull) { this.x += -hit.facing * Math.min(hit.pull, Math.abs(this.x - (hit.attackerX ?? this.x))); }
    // Two hitboxes can land on the SAME frame - a greatsword and the crater it opens, a burst
    // inside a swing. Taking the last one meant the weaker of the pair decided where the victim
    // went: Colossus's 176-launch blade was being overwritten by its own 109-launch shockwave,
    // which pushed its kill percent from 56% to 226%. The bigger hit wins; both still do damage.
    if (!(this.pendingLaunch && this.pendingLaunchFrame === this.frameCount
          && this.pendingLaunch.launch >= launch)) {
      this.pendingLaunch = { launch, angle: hit.angle, facing: hit.facing };
      this.pendingLaunchFrame = this.frameCount;
    }
    if (this.hitlag <= 0) this._applyLaunch();
    this.tumbling = launch >= TUMBLE_THRESHOLD;
    this.fastFalling = false;
    this.setState('hitstun');
  }

  _applyEffects(applies) {
    const M = this.effects;
    if (applies.chill) { M.chill.stacks = Math.min(3, M.chill.stacks + applies.chill); M.chill.timer = 300; }
    if (applies.grit) { M.grit.hide = 180; M.grit.slow = 120; }
    if (applies.tangle) { M.tangle.stacks = Math.min(2, M.tangle.stacks + 1); M.tangle.timer = 600; }
    if (applies.slow) { M.slow = Math.max(M.slow, applies.slow); }
  }

  _stepHitstun() {
    this.hitstun--;
    if (this.hitstun <= 0) this.setState(this.onGround ? 'idle' : 'air');
  }

  launchNoStun(vx, vy) {
    this.vy = vy; this.vx += vx; this.onGround = false; this.platform = null;
    if (this.state === 'idle' || this.state === 'run' || this.state === 'shield' || this.state === 'shielddrop') this.setState('air');
    this.emit({ type: 'vent' });
  }

  freeze(frames) {
    this.frozenFrames = frames; this.vx = 0; this.vy = 0; this.move = null; this.tumbling = false;
    this.setState('frozen');
    this.effects.frozenBonus = true;
    this.emit({ type: 'frozen' });
  }
  _stepFrozen() {
    this.vx = 0; this.vy = 0; this.noGravityFrame = true;
    if (this.input.anyPress) this.frozenFrames = Math.max(this.frozenFrames - 2, 0);
    this.frozenFrames--;
    if (this.frozenFrames <= 0 || this.sf > 40) this.setState(this.onGround ? 'idle' : 'air');
  }

  // ---------- landing / physics ----------
  _physics(ctx) {
    const stage = ctx.stage;
    const noGravity = NO_GRAVITY_STATES.has(this.state) || this.noGravityFrame;
    // Environmental forces. Applied as accelerations rather than velocity sets, so they compose
    // with gravity and with each other and never yank a fighter out of a trajectory they were
    // reading. They are clamped so no stack of hazards can exceed a single strong one.
    // Wind accumulates into a carried velocity that decays on its own. On the ground it bleeds
    // off fast, so a gust never drags a standing fighter.
    if (this.env.windX && !this.onGround) this.carryX += clampEnv(this.env.windX, -ENV_MAX, ENV_MAX) * FRAME;
    this.carryX *= this.onGround ? 0.80 : 0.97;
    if (Math.abs(this.carryX) < 0.05) this.carryX = 0;

    if (!this.onGround && !noGravity) {
      this.vy -= GRAVITY * FRAME;
      let term = this.char.fallSpeed * (this.fastFalling ? MOVE.fastFallMul : 1);
      if (this.effects.lodestone > 0 && this.effects.lodestoneDef) term *= this.effects.lodestoneDef.fallMul;
      if (this.inWater) term *= 0.5;
      if (this.state === 'hitstun' || this.tumbling) term = Math.max(term, 80);
      // A downward environmental force has to be able to push PAST terminal velocity, and an
      // upward one has to survive the clamp. Applying env before this block meant the one-sided
      // clamp deleted both: sandfall moved a falling fighter 67.3 studs against 67.7 in free air,
      // and ember drift bought five frames over a forty-stud fall and exactly nothing once a
      // fighter reached fall speed. The clamp now opens up in proportion to the force pressing on
      // it, which is what "terminal velocity in a downdraft" physically means.
      // An updraft lowers your terminal fall speed and a downdraft raises it — that is what
      // terminal velocity IS, the speed where drag balances gravity, and drag is exactly what a
      // column of moving air changes. Without this, lift below gravity did nothing at all at
      // terminal speed: the clamp re-ran every frame and ate it, so ember drift bought 0 frames
      // over a 38-stud fall no matter how the number was tuned.
      if (this.env.updraft < 0) term *= 1 + Math.min(1.2, -this.env.updraft / GRAVITY);
      else if (this.env.updraft > 0 && this.vy < 0) term *= Math.max(0.22, 1 - this.env.updraft / GRAVITY);
      if (this.vy < -term) this.vy = -term;
    }
    // Applied AFTER the clamp, so lift is never silently erased.
    if (!this.onGround && this.env.updraft) this.vy += clampEnv(this.env.updraft, -ENV_MAX, ENV_MAX) * FRAME;
    if (this.state === 'hitstun' && !this.onGround) this.vx *= LAUNCH_DRAG;
    if (this.state === 'grabbed' || this.state === 'ledge' || this.state === 'ko' || this.state === 'respawn') return;
    let nx = this.x + (this.vx + this.carryX) * FRAME, ny = this.y + this.vy * FRAME;
    if (this.onGround && this.platform) { nx += this.platform.dx; ny = this.platform.top; }
    const res = stage.collide(this, this.x, this.y, nx, ny);
    this.x = res.x; this.y = res.y;
    if (res.wall) {
      if (this.tumbling && this.techPress > 0 && Math.abs(this.vx) > 20) {
        // Wall tech: kill the tumble, bounce off with control instead of sliding down the wall.
        this.techPress = 0; this.buffer.guard = 0; this.tumbling = false; this.hitstun = 0; this.techRoll = 0;
        this.vx = -sign(this.vx) * 18; this.vy = Math.max(this.vy, 8);
        this.setState('tech'); this.emit({ type: 'tech', wall: true });
      } else if (this.state === 'hitstun' && Math.abs(this.vx) > 40) { this.vx = -this.vx * 0.5; }
      else this.vx = 0;
    }
    if (res.bumped) this.vy = 0;
    if (res.landed && !this.onGround) this._land(res.landed, ctx);
    else if (res.landed) this.platform = res.landed;
    if (this.onGround && !stage.supported(this)) {
      this.onGround = false; this.platform = null;
      if (this.state === 'idle' || this.state === 'run' || this.state === 'dash') this.setState('air');
      if (this.state === 'shield' || this.state === 'shielddrop') this.setState('air');
    }
    if (!this.onGround && ['air', 'helpless', 'recovery'].includes(this.state)) {
      const L = stage.ledgeFor(this, this.buffer.guard > 0);
      if (L) { this.buffer.guard = 0; this.grabLedge(L); }
    }
    if (this.state === 'holding' && this.hold) this._positionHeld();
  }

  _land(p, ctx) {
    this.onGround = true; this.platform = p; this.vy = 0;
    this.jumpsLeft = this.char.jumps; this.airDodgeUsed = false; this.recoveryUsed = false; this.ledgeGrabs = 0; this.fastFalling = false; this.dropTimer = 0;
    const s = this.state;
    this.emit({ type: 'land', hard: s === 'groundpound' });
    if (s === 'attack' && this.move && this.move.grounded === false) {
      const ended = this.mf > this.startupEff + this.move.active;
      this.lag = ended ? 4 : (this.move.landingLag || 8);
      this.move = null; this.setState('landing'); return;
    }
    if (s === 'attack') return; // grounded move keeps going (lunges off/on platforms)
    if (s === 'groundpound') {
      ctx.combat.spawnBurst(this, { ...GROUND_POUND.shock, x: this.x, y: this.y + 1, frames: GROUND_POUND.shock.frames, size: [GROUND_POUND.shock.radius * 2, 3] });
      this.lag = GROUND_POUND.landingLag; this.setState('landing'); this.emit({ type: 'shock' }); return;
    }
    if (s === 'hitstun' || (s === 'air' && this.tumbling)) {
      if (this.tumbling) {
        if (this.techPress > 0) {
          this.techPress = 0; this.buffer.guard = 0; this.tumbling = false;
          this.techRoll = Math.abs(this.input.x) > 0.5 ? sign(this.input.x) : 0;
          this.setState('tech'); this.emit({ type: 'tech' }); return;
        }
        this.tumbling = false; this.hitstun = 0; this.setState('knockdown'); return;
      }
      // Landing does NOT end hitstun. Zeroing it here let a launched fighter act the instant they
      // touched ground, which silently cut every ground-to-ground combo short by the victim's
      // remaining airtime. Keep the remaining frames and serve them out standing.
      if (this.hitstun > 0) { this.hitstun = Math.ceil(this.hitstun * 0.5); this.vx *= 0.5; this.setState('hitstun'); return; }
      this.setState('idle'); return;
    }
    if (s === 'helpless' || s === 'recovery') { this.lag = 8; this.setState('landing'); return; }
    if (s === 'airdodge') { this.lag = 8; this.setState('landing'); return; }
    if (s === 'frozen') return;
    this.setState('idle');
  }

  _stepTech() {
    const cfg = this.techRoll ? TECH.roll : TECH.inPlace;
    if (this.techRoll && this.sf <= 20) this.vx = this.techRoll * (cfg.distance / 20) / FRAME; else this._friction();
    if (this.sf > cfg.frames) this.setState('idle');
  }

  isDodgeInvincible() {
    const t = this.effects.tangle.stacks;
    if (this.state === 'spotdodge') return this.sf >= SPOT_DODGE.inv[0] && this.sf <= SPOT_DODGE.inv[1] - 3 * t;
    if (this.state === 'airdodge') return this.sf >= AIR_DODGE.inv[0] && this.sf <= AIR_DODGE.inv[1] - 4 * t;
    if (this.state === 'tech') { const cfg = this.techRoll ? TECH.roll : TECH.inPlace; return this.sf >= cfg.inv[0] && this.sf <= cfg.inv[1]; }
    if (this.state === 'knockdown') return this.sf <= KNOCKDOWN.getupInv[1];
    if (this.state === 'ledgeaction' && this.la) { const o = LEDGE.options[this.la.kind]; return this.sf >= o.inv[0] && this.sf <= o.inv[1]; }
    return false;
  }
  get untouchable() { return this.isInvincible || this.isDodgeInvincible() || this.state === 'ko' || this.state === 'respawn' || !this.alive; }

  // ---------- ledge ----------
  grabLedge(L) {
    this.ledgeGrabs++;
    const inv = LEDGE.invinc[Math.min(this.ledgeGrabs - 1, 2)];
    this.invincible = Math.max(this.invincible, inv);
    this.ledge = L;
    this.x = L.x + L.side * LEDGE.hangOffsetX; this.y = L.y + LEDGE.hangOffsetY;
    this.facing = -L.side; this.vx = 0; this.vy = 0;
    this.onGround = false; this.platform = null;
    this.airDodgeUsed = false; this.recoveryUsed = false; this.fastFalling = false; this.tumbling = false; this.move = null;
    this.setState('ledge');
    this.emit({ type: 'ledge' });
  }

  _stepLedge(ctx) {
    const inp = this.input; const L = this.ledge;
    const toward = inp.x * -L.side;
    if (this.sf > LEDGE.hangMax) { this._ledgeDrop(); return; }
    if (this.sf < 4) return;
    if (this.consume('jump') || inp.y > 0.5) {
      this.x = L.x - L.side * 1.2; this.y = L.y + 0.5; this.vy = this.char.jumpVelocity * this.jumpMul(); this.vx = -L.side * 6;
      this.jumpsLeft = this.char.jumps - 1; this.setState('air'); this.emit({ type: 'jump' }); return;
    }
    if (inp.y < -0.5) { this._ledgeDrop(); return; }
    if (this.consume('light') || this.consume('heavy')) { this._startLedgeAction('attack'); return; }
    if (this.consume('dodge') || this.consume('guard')) { this._startLedgeAction('roll'); return; }
    if (toward > 0.5) { this._startLedgeAction('getup'); return; }
  }

  _ledgeDrop() {
    this.y -= 0.5; this.ledgeCooldown = 14; this.jumpsLeft = this.char.jumps - 1; this.invincible = 0;
    this.setState('air');
  }

  _startLedgeAction(kind) {
    this.la = { kind, L: this.ledge };
    this.hitVictims = new Map();
    this.setState('ledgeaction');
  }

  _stepLedgeAction(ctx) {
    const { kind, L } = this.la; const o = LEDGE.options[kind];
    const onFrame = kind === 'roll' ? 6 : kind === 'attack' ? 8 : 10;
    if (this.sf === onFrame) { this.x = L.x - L.side * 1.6; this.y = L.y; }
    if (kind === 'roll' && this.sf > onFrame && this.sf <= 24) this.x += -L.side * (o.distance - 1.6) / 18;
    if (this.sf > o.frames) {
      this.x = L.x - L.side * o.distance; this.y = L.y; this.onGround = true; this.platform = ctx.stage.main; this.vx = 0; this.vy = 0;
      this.la = null; this.invincible = 0; this.setState('idle');
    }
  }

  // ---------- grabs ----------
  _startGrab() { this.setState('grab'); this.emit({ type: 'grab' }); }
  _stepGrab(ctx) {
    this._friction();
    if (this.sf > GRAB.startup && this.sf <= GRAB.startup + GRAB.active) ctx.combat.checkGrab(this);
    if (this.sf > GRAB.startup + GRAB.active + GRAB.whiffRecovery) this.setState('idle');
  }
  get grabActive() { return this.state === 'grab' && this.sf > GRAB.startup && this.sf <= GRAB.startup + GRAB.active; }

  startHold(victim, data) {
    this.hold = { victim, reel: data.reel || 0, frames: 0, throwData: data.throwData || null, tangle: !!data.tangle, dir: 'forward', startX: victim.x, startY: victim.y };
    victim.holder = this; victim.move = null; victim.hold = null; victim.tumbling = false; victim.vx = 0; victim.vy = 0;
    victim.setState('grabbed');
    this.vx = 0;
    this.setState('holding');
    this.emit({ type: 'grabhit', x: victim.x, y: victim.cy });
  }
  releaseHold() {
    if (!this.hold) return;
    const v = this.hold.victim;
    v.holder = null; if (v.state === 'grabbed') { v.setState('air'); v.vy = 12; v.vx = this.facing * 8; v.onGround = false; v.platform = null; }
    this.hold = null;
    if (this.state === 'holding') { this.lag = 8; this.setState('landing'); }
  }
  _positionHeld() {
    const h = this.hold; const v = h.victim;
    const tx = this.x + this.facing * (this.r + v.r + 0.4), ty = this.y;
    if (h.reel > 0) {
      const k = 1 / Math.max(1, h.reel);
      v.x += (tx - v.x) * k; v.y += (ty - v.y) * k; h.reel--;
    } else { v.x = tx; v.y = ty; }
    v.facing = -this.facing; v.onGround = this.onGround; v.vx = 0; v.vy = 0;
  }
  _stepHolding(ctx) {
    const h = this.hold; if (!h) { this.setState('idle'); return; }
    const inp = this.input;
    if (h.reel > 0) return;
    h.frames++;
    if (inp.y > 0.5) h.dir = 'up'; else if (inp.y < -0.5) h.dir = 'down'; else if (inp.x * this.facing < -0.5) h.dir = 'back'; else if (Math.abs(inp.x) > 0.5) h.dir = 'forward';
    if (h.frames >= GRAB.holdFrames) {
      const td = h.throwData || GRAB.throws[h.dir];
      ctx.combat.resolveThrow(this, h.victim, td, h.tangle);
      h.victim.holder = null; this.hold = null;
      this.lag = 10; this.setState('landing');
    }
  }

  // ---------- respawn / ko ----------
  knockOut() {
    this.alive = false; this.stats.falls++;
    if (this.hold) this.releaseHold();
    if (this.holder) this.holder.releaseHold();
    this.setState('ko');
  }
  respawn(x, opts = {}) {
    this.alive = true;
    this.reset(x, RESPAWN.height, { state: 'respawn', percent: opts.percent || 0, invincible: RESPAWN.invinc });
    this.facing = x < 0 ? 1 : -1;
  }
  _stepRespawn() {
    this.vx = 0; this.vy = 0; this.noGravityFrame = true;
    if (this.sf > 12 && (this.input.anyPress || Math.abs(this.input.x) > 0.5 || this.sf > 180)) { this.invincible = Math.max(this.invincible, 60); this.setState('air'); }
  }

  // ---------- mechanics per frame ----------
  _mechanicsFrame(ctx) {
    const M = this.char.mechanic; const m = this.mech;
    if (!M) return;
    if (m.id === 'Bloom') {
      const now = this.frameCount;
      m.hits = m.hits.filter((t) => now - t <= M.windowFrames);
      if (m.cooldown > 0) m.cooldown--;
      if (m.bloomed && --m.timer <= 0) { m.bloomed = false; m.cooldown = M.cooldownFrames; }
      if (!m.bloomed && m.cooldown === 0 && m.hits.length >= M.hitsRequired) { m.bloomed = true; m.timer = M.durationFrames; m.hits = []; this.emit({ type: 'bloom' }); }
    } else if (m.id === 'Light') {
      if (this.state === 'idle' && this.onGround && Math.abs(this.vx) < 0.5) { m.still++; if (m.still >= M.fillFrames) { m.still = 0; if (m.segments < M.segments) { m.segments++; this.emit({ type: 'light' }); } } }
      else m.still = 0;
    } else if (m.id === 'Spines') {
      if (m.spines < M.max) { m.regen++; if (m.regen >= M.regenFrames) { m.regen = 0; m.spines++; } }
    } else if (m.id === 'Momentum') {
      if (this.state === 'run') m.runFrames++;
      else if (this.state !== 'dash' && this.state !== 'jumpsquat' && this.state !== 'air') m.runFrames = 0;
      if (!m.ready && m.runFrames >= M.runFrames) { m.ready = true; this.emit({ type: 'momentumready' }); }
    } else if (m.id === 'Surge') {
      // SURGE, shared by the Gauntlets (Overdrive) and the Daggers (Bloodrush). Consecutive
      // CONNECTED hits inside a window bank it; while banked, startup is cut and the next heavy
      // spends the damage bonus. The two weapons differ only in their numbers and in
      // `resetOnWhiff`, which is what makes the daggers the riskier of the pair.
      const now = this.frameCount;
      m.hits = (m.hits || []).filter((t) => now - t <= M.windowFrames);
      if (m.surged && --m.timer <= 0) { m.surged = false; m.hits = []; }
      if (!m.surged && m.hits.length >= M.hitsRequired) { m.surged = true; m.timer = M.durationFrames; this.emit({ type: 'momentumready' }); }
    } else if (m.id === 'Draw') {
      // DRAW is banked by HOLDING heavy, grounded and near-still. It is the longbow's whole cost:
      // you cannot kite and draw at the same time.
      if (this.input.heavyHeld && this.onGround && Math.abs(this.vx) < 2) m.draw = Math.min(M.drawFrames, (m.draw || 0) + 1);
      else m.draw = Math.max(0, (m.draw || 0) - 3);
      const was = m.ready;
      m.ready = m.draw >= M.drawFrames;
      if (m.ready && !was) this.emit({ type: 'momentumready' });
    } else if (m.id === 'Snare') {
      // SNARE holds whoever the chain is attached to and reels one of you toward the other
      // depending on which way the stick is held - the brief's "pull them to you, or you to them".
      // It lets go on its own timer, when the victim stops being a valid target, or when the chain
      // runs out of length.
      if (m.snared) {
        const v = m.snared;
        const gone = !v.alive || v.state === 'ko' || v.state === 'respawn' || Math.abs(v.x - this.x) > M.range * 1.6;
        if (gone || --m.timer <= 0) { m.snared = null; m.timer = 0; }
        else {
          const toward = Math.sign(v.x - this.x) || 1;
          const pull = M.pullSpeed * FRAME;
          if (this.input.x * toward > 0.4) this.vx += toward * pull;             // reel yourself in
          else if (this.input.x * toward < -0.4) v.vx -= toward * pull * 1.2;    // reel them in
        }
      }
      m.ready = !!m.snared;
    } else if (m.id === 'Brace') {
      // Banked only while actually holding shield, and dropped the moment the shield does. A pike
      // user who wants the bonus has to stand still and take the pressure to get it.
      if (this.state === 'shield') m.guardFrames++;
      else if (this.state !== 'shielddrop') m.guardFrames = 0;
      if (!m.ready && m.guardFrames >= M.guardFrames) { m.ready = true; this.emit({ type: 'momentumready' }); }
    }
  }

  // HUD resource readout 0..1 plus label
  resource() {
    const M = this.char.mechanic; const m = this.mech;
    if (!M) return null;
    switch (m.id) {
      case 'Bloom': return { label: m.bloomed ? 'Bloomed' : m.cooldown > 0 ? 'Wilted' : 'Bloom', value: m.bloomed ? 1 : m.cooldown > 0 ? 1 - m.cooldown / M.cooldownFrames : m.hits.length / M.hitsRequired, active: m.bloomed };
      case 'Fruiting': return { label: m.ring >= M.ringMax ? 'Fruiting ready' : 'Spores', value: Math.min(1, m.ring / M.ringMax), active: m.ring >= M.ringMax };
      case 'Light': return { label: 'Light', value: m.segments / M.segments, segments: M.segments, filled: m.segments, active: m.segments === M.segments };
      case 'Spines': return { label: 'Spines', value: m.spines / M.max, segments: M.max, filled: m.spines, active: m.spines === M.max };
      case 'Momentum': return { label: m.ready ? 'Momentum' : 'Rolling', value: m.ready ? 1 : Math.min(1, m.runFrames / M.runFrames), active: m.ready };
      case 'Brace': return { label: m.ready ? 'Braced' : 'Bracing', value: m.ready ? 1 : Math.min(1, m.guardFrames / M.guardFrames), active: m.ready };
      case 'Surge': return { label: m.surged ? (M.label || 'Surge') : (M.label || 'Surge'), value: m.surged ? 1 : (m.hits || []).length / M.hitsRequired, segments: M.hitsRequired, filled: m.surged ? M.hitsRequired : (m.hits || []).length, active: !!m.surged };
      case 'Draw': return { label: m.ready ? 'Drawn' : 'Draw', value: Math.min(1, (m.draw || 0) / M.drawFrames), active: !!m.ready };
      case 'Snare': return { label: m.snared ? 'Snared' : 'Chain', value: m.snared ? Math.min(1, m.timer / M.holdFrames) : 0, active: !!m.snared };
      case 'Network': return { label: 'Nodes', value: 0, segments: M.maxNodes, filled: 0, needsNodes: true };
      case 'Tangle': return { label: 'Tangle', value: 0, passive: true };
      case 'Chill': return { label: 'Chill', value: 0, passive: true };
      default: return null;
    }
  }
}
