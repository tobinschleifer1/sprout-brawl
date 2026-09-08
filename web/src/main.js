import { InputManager } from './engine/input.js';
import { Match } from './engine/match.js';
import { CHARACTER_BY_ID, CHARACTERS } from './data/characters/index.js';
import { preload as preloadModels } from './render/models.js';
import { preloadProps } from './render/props.js';
import { STAGE_BY_ID } from './data/stages/index.js';
import { SceneView } from './render/scene.js';
import { buildRig, pose as poseAny } from './render/rigs.js';
import { StageView } from './render/stageview.js';
import { Effects } from './render/effects.js';
import { HUD, PLAYER_MARKS } from './ui/hud.js';
import { Menus } from './ui/menus.js';
import { SFX } from './audio/sfx.js';
import { Music } from './audio/music.js';
import { FRAME } from './config.js';

const SFX_FOR = { hit: 'hit', chip: 'chip', block: 'block', ko: 'ko', jump: 'jump', doublejump: 'doublejump', land: 'land', dash: 'dash', dodge: 'dodge', ledge: 'ledge', shieldbreak: 'shieldbreak', grabhit: 'grab', explosion: 'explosion', beam: 'beam', burst: 'burst', freeze: 'freeze', counter: 'counter', summon: 'summon', projectile: 'projectile', bloom: 'bloom', momentumready: 'momentum', pickup: 'pickup', throwitem: 'throwitem', tech: 'tech', vent: 'vent', count: 'count', go: 'go', suddendeath: 'suddendeath', game: 'game', teleport: 'teleport', fruiting: 'explosion', pulse: 'burst', shock: 'land' };

class App {
  constructor() {
    this.canvas = document.getElementById('game');
    this.ui = document.getElementById('ui');
    this.view = new SceneView(this.canvas);
    this.effects = new Effects(this.view.scene);
    this.input = new InputManager();
    this.hud = new HUD(this.ui);
    this.sfx = new SFX();
    this.music = new Music(this.sfx);
    this.menus = new Menus(this.ui, { onQuick: () => this.quickPlay(), onStart: (c) => this.startFromConfig(c), onTraining: (c) => this.startTraining(c), onSettings: (s) => this.applySettings(s) });
    this.match = null; this.rigs = []; this.stageView = null;
    this.state = 'menu';
    this.acc = 0; this.last = performance.now(); this.t = 0;
    this.applySettings(this.menus.settings);
    this.menus.show('title');
    this.hud.onPause = (a) => { if (a === 'resume') this.togglePause(false); else this.quitToMenu(); };
    window.addEventListener('keydown', (e) => this.onKey(e));
    window.addEventListener('pointerdown', () => this.sfx.ensure(), { once: false });
    window.addEventListener('keydown', () => this.sfx.ensure(), { once: false });
    this.ui.addEventListener('click', (e) => { if (e.target.closest('button')) { this.sfx.ensure(); this.sfx.play('ui'); } });
    // Load whatever Blender-built characters exist; anything missing falls back to primitives.
    Promise.all([preloadModels(CHARACTERS), preloadProps()]).then(([r, propCount]) => {
      const n = r.filter(Boolean).length;
      console.log(`[sprout] ${n} modelled characters, ${propCount} scenery props loaded`);
      this._buildIdleScene();
    });
    this._buildIdleScene();
    requestAnimationFrame((n) => this.loop(n));
  }

  applySettings(s) {
    this.settings = s;
    this.effects.debug = !!s.hitboxes;
    if (this.stageView) this.stageView.setDebug(!!s.hitboxes);
    this.sfx.setVolume(s.sfx); this.music.setVolume(s.music);
  }

  // A calm scene behind the title: Potting Bench with two idle fighters.
  _buildIdleScene() {
    const stage = STAGE_BY_ID.PottingBench;
    this.idleMatch = new Match({ mode: 'Training', stage, input: this.input, stocks: 3, items: false, fighters: [
      { char: CHARACTER_BY_ID.Thornlock, skin: 0, source: 'bot', isBot: true, botLevel: 'normal', name: 'Thornlock', team: 0 },
      { char: CHARACTER_BY_ID.Cacto, skin: 0, source: 'bot', isBot: true, botLevel: 'normal', name: 'Cacto', team: 1 },
    ] });
    this.idleMatch.countdown = 1;
    this._mount(this.idleMatch, true);
  }

  _mount(match, idle) {
    this._unmount();
    this.match = match;
    this.stageView = new StageView(this.view.scene, match.stage);
    this.stageView.setDebug(!!this.settings.hitboxes && !idle);
    this.rigs = match.fighters.map((f) => { const r = buildRig(f.char, f.skin); this.view.scene.add(r); return r; });
    this.view.frame(match.fighters, match.stage, 1, true);
    this.idle = !!idle;
  }
  _unmount() {
    if (this.stageView) this.stageView.dispose();
    for (const r of this.rigs) this.view.scene.remove(r);
    this.rigs = []; this.effects.clear(); this.stageView = null; this.match = null;
  }

  fightersFromConfig(c) {
    const teams = c.mode.includes('Teams');
    const out = [];
    c.slots.forEach((sl, i) => {
      if (sl.type === 'off') return;
      const isBot = sl.type.startsWith('bot');
      out.push({ char: CHARACTER_BY_ID[sl.charId] || CHARACTERS[0], skin: sl.skin || 0, source: isBot ? 'bot' : sl.type, isBot, botLevel: isBot ? sl.type.split('-')[1] : undefined, name: isBot ? `Bot ${i + 1}` : `P${i + 1}`, team: teams ? sl.team : i });
    });
    return out;
  }

  startFromConfig(c) {
    const fighters = this.fightersFromConfig(c);
    if (fighters.length < 2) { alert('Turn on at least two players.'); return; }
    if (c.mode.includes('Teams') && new Set(fighters.map((f) => f.team)).size < 2) { alert('Team modes need both teams.'); return; }
    this.lastConfig = c;
    this.startMatch({ mode: c.mode === 'Training' ? 'Training' : c.mode, stage: STAGE_BY_ID[c.stageId] || STAGE_BY_ID.PottingBench, stocks: c.stocks, timeLimit: c.time, items: c.items && c.mode !== 'Training', fighters });
  }

  quickPlay() {
    const c = this.menus.config;
    const me = c.slots[0].charId || 'Duststorm';
    const pool = CHARACTERS.filter((x) => x.id !== me);
    const foe = pool[Math.floor(Math.random() * pool.length)];
    this.lastConfig = null;
    this.startMatch({ mode: 'StockFFA', stage: STAGE_BY_ID.PottingBench, stocks: 3, timeLimit: 180, items: true, fighters: [
      { char: CHARACTER_BY_ID[me], skin: c.slots[0].skin || 0, source: 'kb1', isBot: false, name: 'P1', team: 0 },
      { char: foe, skin: 0, source: 'bot', isBot: true, botLevel: 'normal', name: 'Bot', team: 1 },
    ] });
  }

  startTraining(c) {
    const me = c.slots[0].charId || 'Duststorm';
    const dummy = c.slots[1].charId || 'Cacto';
    this.lastConfig = null;
    this.startMatch({ mode: 'Training', stage: STAGE_BY_ID[c.stageId] || STAGE_BY_ID.PottingBench, stocks: 3, timeLimit: 0, items: false, fighters: [
      { char: CHARACTER_BY_ID[me], skin: c.slots[0].skin || 0, source: 'kb1', isBot: false, name: 'P1', team: 0 },
      { char: CHARACTER_BY_ID[dummy], skin: 0, source: 'bot', isBot: true, botLevel: 'dummy', name: 'Dummy', team: 1 },
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
      if (e.code === 'KeyR') { this.match.resetTraining(); this.effects.clear(); }
      if (e.code === 'KeyB') { const d = this.match.fighters[1]; d.botLevel = d.botLevel === 'dummy' ? 'normal' : 'dummy'; this.hud.message(d.botLevel === 'dummy' ? 'Dummy: still' : 'Dummy: fighting back', '', 900); }
    }
  }

  handleEvents(match) {
    for (const e of match.events) {
      this.effects.handle(e, match, this.view);
      const s = SFX_FOR[e.type];
      if (s) this.sfx.play(s, e);
      if (e.type === 'movestart') this.sfx.play(e.heavy ? 'whiffheavy' : 'whiff');
      if (this.idle) continue;
      if (e.type === 'count') this.hud.message(String(e.n), 'count', 700);
      if (e.type === 'go') this.hud.message('GROW!', 'go', 900);
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
    match.fighters.forEach((f, i) => poseAny(this.rigs[i], f, this.t));
    this.stageView.update(this.t);
    this.effects.syncEntities(match, this.t);
    this.effects.update(dt);
    this.view.frame(match.fighters, match.stage, dt, false);
    if (!this.idle) {
      this.hud.update(match, this.view);
      const last = match.fighters.some((f) => f.alive && !match.timed && !match.training && f.stocksLeft() === 1 && f.percent >= 80);
      const late = match.timed && match.timeLimit - match.time < 30;
      this.music.setIntensity(match.state === 'suddendeath' || last || late ? 1 : 0);
    }
    this.view.render();
  }
}

window.app = new App();
