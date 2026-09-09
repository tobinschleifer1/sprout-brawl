import { FRAME, RESPAWN, SUDDEN_DEATH } from '../config.js';
import { Fighter } from './fighter.js';
import { StageRuntime } from './stage.js';
import { Combat } from './combat.js';
import { computeBotInput } from './ai.js';
import { emptyFrame } from './input.js';

// Orchestrates one match: countdown, fight, KOs, respawns, items, timer, sudden death, results.
export class Match {
  constructor(cfg) {
    this.cfg = cfg;
    this.mode = cfg.mode; // 'StockFFA' | 'TimedFFA' | 'StockTeams' | 'TimedTeams' | 'Training'
    this.teams = this.mode.includes('Teams');
    this.timed = this.mode.startsWith('Timed');
    this.training = this.mode === 'Training';
    this.stage = new StageRuntime(cfg.stage);
    this.input = cfg.input;
    this.frame = 0; this.time = 0;
    this.timeLimit = cfg.timeLimit || 180;
    this.itemsOn = !!cfg.items;
    this.fighters = cfg.fighters.map((fc, i) => {
      const spawnX = this.stage.data.spawns[i % this.stage.data.spawns.length];
      const f = new Fighter({ index: i, char: fc.char, skin: fc.skin, team: this.teams ? fc.team : i, source: fc.source, isBot: fc.isBot, botLevel: fc.botLevel, name: fc.name, stocks: cfg.stocks || 3, x: spawnX, y: RESPAWN.height });
      f.setState('respawn'); f.invincible = 0; f.eliminatedAt = null; f.koTimer = 0; f._match = this;
      return f;
    });
    this.teamPool = {};
    if (this.teams) for (const f of this.fighters) this.teamPool[f.team] = (this.teamPool[f.team] || 0) + (cfg.stocks || 3);
    this.combat = new Combat(this);
    this.state = 'countdown';
    this.countdown = 3 * 60 + 30;
    this.events = [];
    this.results = null;
    this.sdTimer = 0;
    this.paused = false;
    this.ctx = { stage: this.stage, combat: this.combat, match: this };
    this.input.kb2Active = this.fighters.some((f) => f.source === 'kb2');
    this.events.push({ type: 'matchstart' });
  }

  get alivePlayers() { return this.fighters.filter((f) => f.alive || (f.stocksLeft() > 0)); }

  step() {
    if (this.paused || this.state === 'results') return;
    this.frame++;
    // The clock starts on GO. Ticking it through the 3.5s countdown used to shave that time off
    // every timed match.
    if (this.state !== 'countdown') this.time += FRAME;
    this.input.poll();
    const inputsOn = this.state !== 'countdown';
    for (const f of this.fighters) {
      let frame = emptyFrame();
      if (inputsOn) frame = f.isBot ? computeBotInput(f, this) : this.input.get(f.source);
      f.applyInput(frame);
    }
    this.stage.step(this);
    for (const f of this.fighters) f.step(this.ctx);
    this.combat.step();
    // collect events
    for (const f of this.fighters) { for (const e of f.events) this.events.push({ ...e, fighter: f.index, x: e.x ?? f.x, y: e.y ?? f.cy }); f.events.length = 0; }
    for (const e of this.combat.events) this.events.push(e); this.combat.events.length = 0;

    if (this.state === 'countdown') {
      this.countdown--;
      if (this.countdown === 180) this.events.push({ type: 'count', n: 3 });
      if (this.countdown === 120) this.events.push({ type: 'count', n: 2 });
      if (this.countdown === 60) this.events.push({ type: 'count', n: 1 });
      if (this.countdown <= 0) { this.state = 'fight'; this.events.push({ type: 'go' }); }
      return;
    }
    // KOs
    for (const f of this.fighters) {
      if (f.alive && this.stage.outsideBlast(f)) this.knockOut(f);
      if (!f.alive && f.koTimer > 0) {
        f.koTimer--;
        if (f.koTimer === 0 && (this.training || this.timed || f.stocksLeft() > 0)) this.respawn(f);
      }
    }
    if (this.itemsOn && this.state === 'fight') this.combat.maybeSpawnItem(this.fighters.length);
    if (this.state === 'suddendeath') {
      this.sdTimer += FRAME;
      if (this.sdTimer >= SUDDEN_DEATH.shrinkEvery) { this.sdTimer = 0; this.stage.shrink(SUDDEN_DEATH.shrinkFactor); this.events.push({ type: 'shrink' }); }
    }
    if (this.training) return;
    if (this.timed && this.state === 'fight' && this.time >= this.timeLimit) {
      const tied = this.tiedTeams();
      if (tied.length > 1) this.startSuddenDeath(tied); else this.finish();
      return;
    }
    if (this.winnerDecided()) this.finish();
  }

  stocksLeftFor(f) { return this.teams ? this.teamPool[f.team] : f.stocks; }

  knockOut(f) {
    const side = f.x < this.stage.blast.left ? 'left' : f.x > this.stage.blast.right ? 'right' : f.y > this.stage.blast.top ? 'top' : 'bottom';
    const credit = f.lastHitBy && f.frameCount - f.lastHitFrame < 480 ? f.lastHitBy : null;
    if (credit && credit !== f) credit.stats.kos++; else f.stats.selfDestructs++;
    // Timed modes score on KOs, not stocks, so a KO there costs nothing but the respawn wait.
    if (this.timed) { /* unlimited lives */ }
    else if (this.teams) this.teamPool[f.team] = Math.max(0, this.teamPool[f.team] - 1);
    else f.stocks = Math.max(0, f.stocks - 1);
    if (this.training) f.stocks = 3;
    f.knockOut();
    f.koTimer = Math.round(RESPAWN.delay * 60);
    if (!this.training && f.stocksLeft() === 0 && !this.timed) f.eliminatedAt = this.frame;
    this.events.push({ type: 'ko', fighter: f.index, by: credit ? credit.index : -1, x: Math.max(this.stage.blast.left, Math.min(this.stage.blast.right, f.x)), y: Math.max(this.stage.blast.bottom, Math.min(this.stage.blast.top, f.cy)), side, last: !this.timed && f.stocksLeft() === 0 });
  }

  respawn(f) {
    const spawnX = this.stage.data.spawns[f.index % this.stage.data.spawns.length];
    f.respawn(spawnX, { percent: this.state === 'suddendeath' ? SUDDEN_DEATH.percent : 0 });
    this.events.push({ type: 'respawn', fighter: f.index });
  }

  teamsAlive() {
    const alive = new Set();
    for (const f of this.fighters) if (f.alive || f.stocksLeft() > 0) alive.add(f.team);
    return alive;
  }

  winnerDecided() {
    if (this.timed) return false;
    return this.teamsAlive().size <= 1;
  }

  teamScore(team) {
    let s = 0;
    for (const f of this.fighters) if (f.team === team) s += f.stats.kos - f.stats.selfDestructs;
    return s;
  }
  tiedTeams() {
    const teams = [...new Set(this.fighters.map((f) => f.team))];
    const scores = teams.map((t) => ({ t, s: this.teamScore(t) }));
    const best = Math.max(...scores.map((x) => x.s));
    return scores.filter((x) => x.s === best).map((x) => x.t);
  }

  startSuddenDeath(tied) {
    this.state = 'suddendeath';
    this.timed = false;
    this.sdTimer = 0;
    for (const f of this.fighters) {
      if (tied.includes(f.team)) {
        f.stocks = 1; if (this.teams) this.teamPool[f.team] = 1;
        if (f.alive) { f.percent = SUDDEN_DEATH.percent; } else { f.koTimer = 1; }
      } else { f.stocks = 0; if (this.teams) this.teamPool[f.team] = 0; if (f.alive) f.knockOut(); f.eliminatedAt = this.frame; }
    }
    this.events.push({ type: 'suddendeath' });
  }

  finish() {
    this.state = 'results';
    const teams = [...new Set(this.fighters.map((f) => f.team))];
    const rows = this.fighters.map((f) => ({
      index: f.index, name: f.name, char: f.char, team: f.team, kos: f.stats.kos, falls: f.stats.falls, sds: f.stats.selfDestructs, damage: Math.round(f.stats.damageDealt), percent: f.percent,
      stocks: f.stocksLeft(), score: this.teamScore(f.team), eliminatedAt: f.eliminatedAt == null ? Infinity : f.eliminatedAt,
    }));
    rows.sort((a, b) => {
      if (this.timed) return b.score - a.score || a.percent - b.percent;
      return b.eliminatedAt - a.eliminatedAt || b.stocks - a.stocks || a.percent - b.percent;
    });
    const winnerTeam = rows[0].team;
    this.results = { rows, winnerTeam, teams: this.teams, timed: this.mode.startsWith('Timed'), mode: this.mode };
    this.events.push({ type: 'game', winner: rows[0].index });
  }

  resetTraining() {
    for (const f of this.fighters) {
      const spawnX = this.stage.data.spawns[f.index % this.stage.data.spawns.length];
      f.alive = true; f.reset(spawnX, RESPAWN.height, { state: 'respawn', percent: 0, invincible: 0 });
    }
    this.combat.projectiles.length = 0; this.combat.summons.length = 0; this.combat.bursts.length = 0; this.combat.items.length = 0;
  }
}

Fighter.prototype.stocksLeft = function () {
  const m = this._match;
  return m ? m.stocksLeftFor(this) : this.stocks;
};
