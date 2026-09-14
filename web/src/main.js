import { InputManager } from './engine/input.js';
import { Match } from './engine/match.js';
import { WEAPONS } from './data/weapons/index.js';
import { buildLoadout } from './data/loadout.js';
import { initCustomAvatars } from './data/customAvatars.js';
import { STAGE_BY_ID } from './data/stages/index.js';
import { Renderer2D } from './render2d/renderer2d.js';
import { HUD, PLAYER_MARKS } from './ui/hud.js';
import { Menus } from './ui/menus.js';
import { SFX } from './audio/sfx.js';
import { Music } from './audio/music.js';
import { FRAME } from './config.js';
import { GO_CALL } from './data/branding.js';

const SFX_FOR = { hit: 'hit', chip: 'chip', block: 'block', ko: 'ko', jump: 'jump', doublejump: 'doublejump', land: 'land', dash: 'dash', dodge: 'dodge', ledge: 'ledge', shieldbreak: 'shieldbreak', grabhit: 'grab', explosion: 'explosion', beam: 'beam', burst: 'burst', freeze: 'freeze', counter: 'counter', summon: 'summon', projectile: 'projectile', bloom: 'bloom', momentumready: 'momentum', pickup: 'pickup', throwitem: 'throwitem', tech: 'tech', vent: 'vent', count: 'count', go: 'go', suddendeath: 'suddendeath', game: 'game', teleport: 'teleport', fruiting: 'explosion', pulse: 'burst', shock: 'land' };

class App {
  constructor() {
    // Player-made characters have to be in the avatar registry before anything resolves an id -
    // the saved match config, the menu, a preview. Load them first, ahead of the renderer.
    initCustomAvatars();
    this.canvas = document.getElementById('game');
    this.ui = document.getElementById('ui');
    this.view = new Renderer2D(this.canvas);
    window.addEventListener('resize', () => this.view.resize());
    this.input = new InputManager();
    this.hud = new HUD(this.ui);
    this.sfx = new SFX();
    this.music = new Music(this.sfx);
    this.menus = new Menus(this.ui, { onQuick: () => this.quickPlay(), onStart: (c) => this.startFromConfig(c), onTraining: (c) => this.startTraining(c), onSettings: (s) => this.applySettings(s) });
    this.match = null;
    this.state = 'menu';
    this.acc = 0; this.last = performance.now(); this.t = 0;
    this.applySettings(this.menus.settings);
    this.menus.show('title');
    this.hud.onPause = (a) => { if (a === 'resume') this.togglePause(false); else this.quitToMenu(); };
    window.addEventListener('keydown', (e) => this.onKey(e));
    window.addEventListener('pointerdown', () => this.sfx.ensure(), { once: false });
    window.addEventListener('keydown', () => this.sfx.ensure(), { once: false });
    this.ui.addEventListener('click', (e) => { if (e.target.closest('button')) { this.sfx.ensure(); this.sfx.play('ui'); } });
    this._buildIdleScene();
    requestAnimationFrame((n) => this.loop(n));
  }

  applySettings(s) {
    this.settings = s;
    this.view.debug = !!s.hitboxes;
    this.sfx.setVolume(s.sfx); this.music.setVolume(s.music);
  }

  // A calm scene behind the title: Foundry Floor with two idle fighters.
  _buildIdleScene() {
    const stage = STAGE_BY_ID.FoundryFloor;
    this.idleMatch = new Match({ mode: 'Training', stage, input: this.input, stocks: 3, items: false, fighters: [
      { char: buildLoadout('Classic', 'Sword'), skin: 0, source: 'bot', isBot: true, botLevel: 'normal', name: 'Sword', team: 0 },
      { char: buildLoadout('Noir', 'Scythe'), skin: 0, source: 'bot', isBot: true, botLevel: 'normal', name: 'Scythe', team: 1 },
    ] });
    this.idleMatch.countdown = 1;
    this._mount(this.idleMatch, true);
  }

  _mount(match, idle) {
    this._unmount();
    this.match = match;
    this.view.setStage(match.stage);
    this.view.debug = !!this.settings.hitboxes && !idle;
    this.view.frame(match, 1, this.t, true);
    this.idle = !!idle;
  }
  _unmount() {
    this.view.dispose(); this.match = null;
  }

  fightersFromConfig(c) {
    const teams = c.mode.includes('Teams');
    const out = [];
    c.slots.forEach((sl, i) => {
      if (sl.type === 'off') return;
      const isBot = sl.type.startsWith('bot');
      out.push({ char: buildLoadout(sl.avatarId, sl.weaponId), skin: 0, source: isBot ? 'bot' : sl.type, isBot, botLevel: isBot ? sl.type.split('-')[1] : undefined, name: isBot ? `Bot ${i + 1}` : `P${i + 1}`, team: teams ? sl.team : i });
    });
    return out;
  }

  startFromConfig(c) {
    const fighters = this.fightersFromConfig(c);
    if (fighters.length < 2) { alert('Turn on at least two players.'); return; }
    if (c.mode.includes('Teams') && new Set(fighters.map((f) => f.team)).size < 2) { alert('Team modes need both teams.'); return; }
    this.lastConfig = c;
    this.startMatch({ mode: c.mode === 'Training' ? 'Training' : c.mode, stage: STAGE_BY_ID[c.stageId] || STAGE_BY_ID.FoundryFloor, stocks: c.stocks, timeLimit: c.time, items: c.items && c.mode !== 'Training', fighters });
  }

  quickPlay() {
    const c = this.menus.config;
    const mine = c.slots[0];
    const pool = WEAPONS.filter((x) => x.id !== mine.weaponId);
    const foe = pool[Math.floor(Math.random() * pool.length)];
    this.lastConfig = null;
    this.startMatch({ mode: 'StockFFA', stage: STAGE_BY_ID.FoundryFloor, stocks: 3, timeLimit: 180, items: true, fighters: [
      { char: buildLoadout(mine.avatarId, mine.weaponId), skin: 0, source: 'kb1', isBot: false, name: 'P1', team: 0 },
      { char: buildLoadout('Noir', foe.id), skin: 0, source: 'bot', isBot: true, botLevel: 'normal', name: 'Bot', team: 1 },
    ] });
  }

  startTraining(c) {
    this.lastConfig = null;
    this.startMatch({ mode: 'Training', stage: STAGE_BY_ID[c.stageId] || STAGE_BY_ID.FoundryFloor, stocks: 3, timeLimit: 0, items: false, fighters: [
      { char: buildLoadout(c.slots[0].avatarId, c.slots[0].weaponId), skin: 0, source: 'kb1', isBot: false, name: 'P1', team: 0 },
      { char: buildLoadout(c.slots[1].avatarId, c.slots[1].weaponId), skin: 0, source: 'bot', isBot: true, botLevel: 'dummy', name: 'Dummy', team: 1 },
    ] });
  }

  startMatch(cfg) {
    this.sfx.ensure();
    const match = new Match({ ...cfg, input: this.input });
    this._mount(match, false);
    this.menus.hide();
    this.hud.bind(match); this.hud.show();
    this.state = 'match';
    this.music.start(match.stage.data.music);
    this.hud.message(match.stage.data.name, 'stage', 1600);
  }

  endMatch(showResults) {
    if (showResults && this.match.results) {
      this.hud.showResults(this.match.results, (a) => {
        if (a === 'rematch') { this.hud.hideResults(); const cfg = this.match.cfg; this.startMatch({ ...cfg }); }
        else if (a === 'setup') { this.quitToMenu('setup'); }
        else this.quitToMenu('title');
      });
    }
  }

  quitToMenu(screen = 'title') {
    this.music.stop();
    this.hud.hide();
    this.state = 'menu';
    this._buildIdleScene();
    this.menus.show(screen);
  }

  togglePause(on) {
    if (!this.match || this.state !== 'match') return;
    const p = on == null ? !this.match.paused : on;
    this.match.paused = p; this.hud.showPause(p);
    if (p) this.music.setIntensity(0);
  }

  onKey(e) {
    if (this.state !== 'match' || !this.match) return;
    if (e.code === 'Escape' || e.code === 'KeyP') { this.togglePause(); e.preventDefault(); return; }
    if (e.code === 'KeyH') { this.settings.hitboxes = !this.settings.hitboxes; this.applySettings(this.settings); this.menus.save(); }
    if (e.code === 'KeyM') { this.settings.music = this.settings.music > 0 ? 0 : 0.6; this.applySettings(this.settings); this.menus.save(); }
    if (this.match.training) {
      if (e.code === 'KeyR') { this.match.resetTraining(); this.view.clear(); }
      if (e.code === 'KeyB') { const d = this.match.fighters[1]; d.botLevel = d.botLevel === 'dummy' ? 'normal' : 'dummy'; this.hud.message(d.botLevel === 'dummy' ? 'Dummy: still' : 'Dummy: fighting back', '', 900); }
    }
  }

  handleEvents(match) {
    for (const e of match.events) {
      this.view.handle(e, match);
      const s = SFX_FOR[e.type];
      if (s) this.sfx.play(s, e);
      if (e.type === 'movestart') this.sfx.play(e.heavy ? 'whiffheavy' : 'whiff');
      if (this.idle) continue;
      if (e.type === 'count') this.hud.message(String(e.n), 'count', 700);
      if (e.type === 'go') this.hud.message(GO_CALL, 'go', 900);
      if (e.type === 'ko') { const f = match.fighters[e.fighter]; this.hud.message(`KO! <small>${PLAYER_MARKS[f.index]} ${f.name}</small>`, 'ko', 1100); }
      if (e.type === 'suddendeath') this.hud.message('SUDDEN DEATH', 'sd', 1600);
      if (e.type === 'game') { this.hud.message('GAME!', 'game', 1800); setTimeout(() => this.endMatch(true), 1700); this.music.setIntensity(0); }
      if (e.type === 'shrink') this.hud.message('Closing in', 'sd', 800);
    }
    match.events.length = 0;
    if (!this.settings.shake) this.view.shake = 0;
  }

  loop(now) {
    requestAnimationFrame((n) => this.loop(n));
    const dt = Math.min(0.1, (now - this.last) / 1000); this.last = now; this.t += dt;
    const match = this.match;
    if (!match) return;
    this.acc += dt;
    let steps = 0;
    while (this.acc >= FRAME && steps < 4) { match.step(); this.acc -= FRAME; steps++; }
    if (steps === 4) this.acc = 0;
    this.handleEvents(match);
    if (this.idle && match.frame % 3600 === 3599) { this._buildIdleScene(); return; }
    this.view.frame(match, dt, this.t, false);
    if (!this.idle) {
      this.hud.update(match, this.view);
      const last = match.fighters.some((f) => f.alive && !match.timed && !match.training && f.stocksLeft() === 1 && f.percent >= 80);
      const late = match.timed && match.timeLimit - match.time < 30;
      this.music.setIntensity(match.state === 'suddendeath' || last || late ? 1 : 0);
    }
  }
}

window.app = new App();
