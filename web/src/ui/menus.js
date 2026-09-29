import { WEAPONS } from '../data/weapons/index.js';
import { AVATARS, FEATURES, FEATURE_KEYS, PALETTE_KEYS, PALETTE_LABELS, allAvatars, avatarById, PRESET_IDS } from '../data/avatars.js';
import { blankAvatar, saveAvatar, deleteAvatar, duplicateAvatar, sanitize, readabilityWarning,
  exportAvatars, importAvatars, readCustom, browserStore, MAX_CUSTOM, MAX_NAME } from '../data/customAvatars.js';
import { Renderer2D } from '../render2d/renderer2d.js';
import { posedFighter } from '../render2d/preview.js';
import { drawWeapon, REACH } from '../render2d/weapons2d.js';
import { PART_GRIDS, PART_IDS, INKS, inkColour, blankPart, setCell, cellAt } from '../data/pixelArt.js';
import { traceProcedural, blitPixelPart } from '../render2d/pixels2d.js';
import { buildLoadout } from '../data/loadout.js';
import { STAGES } from '../data/stages/index.js';
import { stageThumb, randomThumb } from '../render2d/stageThumb.js';
import { RULES, engineMode } from '../data/rules.js';
import { BINDINGS_TEXT } from '../engine/input.js';
import { PLAYER_COLORS, PLAYER_MARKS } from './hud.js';
import { onBlock } from '../engine/knockback.js';
import { TITLE, TAGLINE, SUBTITLE, SAVE_KEY } from '../data/branding.js';
import { KIT_CATEGORIES, KIT_COLOURS, KIT_GROUPS, KIT_PRESETS, DEFAULT_KIT,
  decodeKit, encodeKit, kitAvatar, presetKit } from '../data/avatarKit.js';
import { KIT_PARTS } from '../data/avatarKit.js';
import { drawKitPiece } from '../render2d/kitCanvas.js';
import { KitDraft, readKitCharacters, writeKitCharacters, registerKitCharacters,
  saveKitCharacter, deleteKitCharacter, webKitCode, MAX_KIT_CHARACTERS } from './kitCharacters.js';

const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const SLOT_TYPES = [['off', 'Off'], ['kb1', 'Keyboard 1'], ['kb2', 'Keyboard 2'], ['pad0', 'Gamepad 1'], ['pad1', 'Gamepad 2'], ['pad2', 'Gamepad 3'], ['pad3', 'Gamepad 4'], ['bot-easy', 'Bot · Easy'], ['bot-normal', 'Bot · Normal'], ['bot-hard', 'Bot · Hard'], ['bot-elite', 'Bot · Elite'], ['bot-impossible', 'Bot · Impossible'], ['bot-just_dont', 'Bot · Just Don\'t']];
// Natural disasters (engine/disasters.js): off by default, as in the Roblox rooms.
const DISASTER_MODES = [['off', 'Off'], ['stage', "This map's own"], ['chaos', 'Chaos']];
const MODES = [['StockFFA', 'Stock · Free-for-all'], ['TimedFFA', 'Timed · Free-for-all'], ['StockTeams', 'Stock · 2v2'], ['TimedTeams', 'Timed · 2v2'], ['Training', 'Training']];

// Map-select thumbnails from the shape list both builds draw (render2d/stageThumb.js), as SVG.
function thumbSVG(shapes, w, h) {
  return `<svg viewBox="0 0 ${w} ${h}" shape-rendering="crispEdges">${shapes.map(([, x, y, rw, rh, c, a]) =>
    `<rect x="${x}" y="${y}" width="${rw}" height="${rh}" fill="${c}"${a < 1 ? ` fill-opacity="${a}"` : ''}/>`).join('')}</svg>`;
}
const stageSVG = (s) => thumbSVG(stageThumb(s, 160, 90), 160, 90);

// The maps a Random pick draws from, by map set: everything, or the competitive rotation.
export const MAP_SETS = [['all', 'All maps'], ['ranked', 'Ranked']];
// Rule presets on a local setup (data/rules.js). The mode keeps the screen's own free-for-all or
// teams choice; a preset that draws the map at random selects Random, and one that votes keeps
// the map you picked if it is in the preset's set - there is nobody else here to vote.
export function applyPreset(config, id) {
  const p = RULES.presets.find((x) => x.id === id);
  if (!p) return config;
  const r = p.rules;
  const teams = config.mode.includes('Teams');
  const next = { ...config, mode: engineMode(r.mode, teams), stocks: r.stocks, time: r.time, items: r.items, disasters: r.disasters, mapSet: r.mapSet };
  if (r.mapChoice === 'random' || (next.stageId !== 'Random' && !mapSet(r.mapSet).some((s) => s.id === next.stageId))) next.stageId = 'Random';
  return next;
}
export function presetOf(config) {
  const p = RULES.presets.find((x) => {
    const r = x.rules;
    return config.mode === engineMode(r.mode, config.mode.includes('Teams')) && config.stocks === r.stocks && config.time === r.time
      && config.items === r.items && config.disasters === r.disasters && (config.mapSet || 'all') === r.mapSet
      && (r.mapChoice !== 'random' || config.stageId === 'Random');
  });
  return p ? p.id : null;
}

export function mapSet(set) { return set === 'ranked' ? STAGES.filter((s) => s.ranked) : STAGES; }

export class Menus {
  constructor(root, handlers) {
    this.root = el('div', 'menus');
    root.appendChild(this.root);
    this.h = handlers;
    this.kitRoster = readKitCharacters();
    registerKitCharacters(this.kitRoster);
    this.kitGroup = 'presets'; this.kitCategory = 'build'; this.kitPose = 'idle';
    this.config = this._defaultConfig();
    this.settings = { hitboxes: false, music: 0.6, sfx: 0.8, shake: true };
    try {
      const s = JSON.parse(localStorage.getItem(SAVE_KEY + '-settings') || 'null');
      if (s && typeof s === 'object') {
        for (const key of ['sfx', 'music']) if (Number.isFinite(s[key])) this.settings[key] = Math.max(0, Math.min(1, s[key]));
        for (const key of ['hitboxes', 'shake']) if (typeof s[key] === 'boolean') this.settings[key] = s[key];
      }
    } catch (e) { /* ignore */ }
    try {
      const c = JSON.parse(localStorage.getItem(SAVE_KEY + '-config') || 'null');
      if (c && typeof c === 'object') {
        if (MODES.some(([id]) => id === c.mode)) this.config.mode = c.mode;
        if (c.stageId === 'Random' || STAGES.some(s => s.id === c.stageId)) this.config.stageId = c.stageId;
        if (MAP_SETS.some(([id]) => id === c.mapSet)) this.config.mapSet = c.mapSet;
        if (Number.isInteger(c.stocks)) this.config.stocks = Math.max(1, Math.min(5, c.stocks));
        if ([120, 180, 240, 300].includes(c.time)) this.config.time = c.time;
        if (typeof c.items === 'boolean') this.config.items = c.items;
        if (DISASTER_MODES.some(([id]) => id === c.disasters)) this.config.disasters = c.disasters;
        if (Array.isArray(c.slots)) this.config.slots = this.config.slots.map((fallback, i) => {
          const slot = c.slots[i];
          if (!slot || typeof slot !== 'object') return fallback;
          return {
            type: SLOT_TYPES.some(([id]) => id === slot.type) ? slot.type : fallback.type,
            weaponId: WEAPONS.some(w => w.id === slot.weaponId) ? slot.weaponId : fallback.weaponId,
            avatarId: allAvatars().some(a => a.id === slot.avatarId) ? slot.avatarId : fallback.avatarId,
            team: slot.team === 0 || slot.team === 1 ? slot.team : fallback.team,
          };
        });
      }
    } catch (e) { /* ignore */ }
    this.screen = 'title';
    this.root.addEventListener('click', (e) => this._click(e));
    this.root.addEventListener('change', (e) => this._change(e));
    this.root.addEventListener('input', (e) => this._change(e));
    if (typeof window !== 'undefined') window.addEventListener('keydown', (e) => this._kitKey(e));
  }

  _defaultConfig() {
    return { mode: 'StockFFA', stocks: 3, time: 180, items: true, disasters: 'off', stageId: 'FoundryFloor', mapSet: 'all',
      slots: Array.from({ length: 8 }, (_, i) => ({ type: i ? 'off' : 'kb1',
        weaponId: ['Sword', 'Scythe', 'Blasters', 'Grimoire'][i % 4],
        avatarId: ['Classic', 'Noir', 'Ember', 'Moss'][i % 4], team: i % 2 })) };
  }

  _kitOpen(code = null) {
    const row = this.kitRoster.characters.find((a) => a.code === code);
    this.kitDraft = new KitDraft(row?.code || encodeKit(DEFAULT_KIT));
    this.kitName = row?.name || `Fighter ${this.kitRoster.characters.length + 1}`;
    this.kitOriginal = row?.code || null;
    this.kitBaseCode = this.kitDraft.code; this.kitBaseName = this.kitName;
    this.kitGroup = 'presets'; this.kitCategory = 'build'; this.kitMsg = null;
    this.kitPose = 'idle'; this.kitZoom = 'body'; this.previewWeapon = this.config.slots[0].weaponId;
    this.show('kit-edit');
  }

  _kitStash() {
    const input = this.root.querySelector('[data-kit-name]');
    if (input) this.kitName = input.value;
  }

  _kitLeave() {
    this._kitStash();
    if ((this.kitDraft.code !== this.kitBaseCode || this.kitName !== this.kitBaseName) &&
        typeof window !== 'undefined' && !window.confirm('Discard unsaved character changes?')) return;
    this.kitDraft = null; this.kitMsg = null; this.show('kit');
  }

  _kitCommit(roster, removed = null) {
    this.kitRoster = roster;
    if (removed) unregisterAvatar(removed);
    registerKitCharacters(roster);
    const persisted = writeKitCharacters(roster);
    this.save();
    return persisted;
  }

  _kitSave(asNew = false, wear = false) {
    this._kitStash();
    const result = saveKitCharacter(this.kitRoster, this.kitName, this.kitDraft.code, this.kitOriginal, asNew);
    if (!result.ok) { this.kitMsg = result.reason; this.render(); return; }
    const old = asNew ? null : this.kitOriginal;
    if (wear) { result.roster.wearing = result.code; this.config.slots[0].avatarId = result.code; }
    if (old && old !== result.code) for (const sl of this.config.slots) if (sl.avatarId === old) sl.avatarId = result.code;
    const persisted = this._kitCommit(result.roster, old && old !== result.code ? old : null);
    this.kitOriginal = result.code; this.kitBaseCode = result.code; this.kitBaseName = this.kitName;
    this.kitMsg = persisted
      ? (wear ? 'Now wearing this character in Player 1.' : 'Character saved.')
      : 'Saved for this visit, but browser storage is unavailable.';
    this.render();
  }

  _kitKey(e) {
    if (this.screen === 'setup' && e.code === 'Enter' && !this.config.slots.some((s) => s.type === 'kb2') &&
        (!e.target || e.target === document.body)) {
      const slot = this.config.slots.findIndex((s) => s.type === 'off');
      if (slot >= 0) { e.preventDefault(); this.config.slots[slot].type = 'kb2'; this.selectSlot = slot; this.showMoreSlots ||= slot >= 4; this.save(); this.render(); }
      return;
    }
    if (this.screen !== 'kit-edit' || !this.kitDraft || e.altKey || e.metaKey) return;
    const entry = e.target && /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName || '');
    if (e.ctrlKey && e.code === 'KeyZ') { e.preventDefault(); this._kitStash(); this.kitDraft.undo(); this.render(); return; }
    if (e.ctrlKey && e.code === 'KeyY') { e.preventDefault(); this._kitStash(); this.kitDraft.redo(); this.render(); return; }
    if (e.code === 'Escape') { e.preventDefault(); this._kitLeave(); return; }
    if (entry) return;
    if (e.code === 'KeyR') { e.preventDefault(); this.kitDraft.randomise(); this.render(); return; }
    const groups = KIT_GROUPS.map((g) => g.id);
    if (e.code === 'KeyQ' || e.code === 'KeyE') {
      e.preventDefault(); this._kitStash(); this.kitGroup = groups[(groups.indexOf(this.kitGroup) + (e.code === 'KeyQ' ? groups.length - 1 : 1)) % groups.length];
      this.kitCategory = KIT_GROUPS.find((g) => g.id === this.kitGroup).parts[0] || this.kitCategory;
      this.render(); return;
    }
    const group = KIT_GROUPS.find((g) => g.id === this.kitGroup);
    if (!group || !group.parts.length) return;
    if (e.code === 'ArrowUp' || e.code === 'ArrowDown') {
      e.preventDefault(); this._kitStash();
      const i = group.parts.indexOf(this.kitCategory);
      this.kitCategory = group.parts[(i + (e.code === 'ArrowUp' ? group.parts.length - 1 : 1)) % group.parts.length];
      this.render(); return;
    }
    if (e.code === 'ArrowLeft' || e.code === 'ArrowRight') {
      e.preventDefault(); this._kitStash();
      const cat = KIT_CATEGORIES.find((c) => c.id === this.kitCategory);
      const choices = cat.options.filter((o) => !o.unlock);
      const current = decodeKit(this.kitDraft.code).parts[cat.id];
      const i = choices.findIndex((o) => o.id === current);
      this.kitDraft.part(cat.id, choices[(i + (e.code === 'ArrowLeft' ? choices.length - 1 : 1)) % choices.length].id);
      this.render();
    }
  }

  save() { try { localStorage.setItem(SAVE_KEY + '-config', JSON.stringify(this.config)); localStorage.setItem(SAVE_KEY + '-settings', JSON.stringify(this.settings)); } catch (e) { /* ignore */ } }

  show(screen) {
    this.screen = screen; this.root.classList.remove('hidden'); this.root.scrollTop = 0; this.render();
    if (!this._padTimer && typeof navigator !== 'undefined' && navigator.getGamepads)
      this._padTimer = setInterval(() => this._pollMenuPads(), 100);
  }
  hide() {
    this.root.classList.add('hidden');
    if (this._padTimer) clearInterval(this._padTimer); this._padTimer = null;
    this._tickSelectPreviews(false);
  }

  _pollMenuPads() {
    if (document.hidden || this.root.classList.contains('hidden')) return;
    const pads = navigator.getGamepads() || [];
    for (let i = 0; i < pads.length; i++) {
      const pad = pads[i]; if (!pad) continue;
      const press = [0,1,12,13,14,15].map((n) => !!pad.buttons[n]?.pressed);
      const prev = this._padPrev?.[i] || [];
      this._padPrev ||= {}; this._padPrev[i] = press;
      if (press[0] && !prev[0]) {
        if (this.screen === 'setup' && !this.config.slots.some((s) => s.type === `pad${i}`)) {
          const slot = this.config.slots.findIndex((s) => s.type === 'off');
          if (slot >= 0) { this.config.slots[slot].type = `pad${i}`; this.selectSlot = slot; this.showMoreSlots ||= slot >= 4; this.save(); this.render(); }
        } else if (this._padFocus?.isConnected) this._padFocus.click();
      }
      if (press[1] && !prev[1]) {
        if (this.screen === 'kit-edit') this._kitLeave();
        else if (this.screen !== 'title') this.show('title');
      }
      const direction = [12,13,14,15].findIndex((_,k) => press[k+2] && !prev[k+2]);
      if (direction >= 0) this._movePadFocus(direction === 0 || direction === 2 ? -1 : 1);
    }
  }

  _movePadFocus(step) {
    const controls = [...this.root.querySelectorAll('button:not(:disabled),select')].filter((x) => x.getClientRects().length);
    if (!controls.length) return;
    const index = controls.indexOf(this._padFocus);
    this._padFocus?.classList.remove('gamepad-focus');
    this._padFocus = controls[(index + step + controls.length) % controls.length];
    this._padFocus.classList.add('gamepad-focus'); this._padFocus.focus();
  }

  render() {
    const s = this.screen;
    if (s === 'title') this.root.innerHTML = this._title();
    else if (s === 'setup') this.root.innerHTML = this._setup();
    else if (s === 'controls') this.root.innerHTML = this._controls();
    else if (s === 'settings') this.root.innerHTML = this._settings();
    else if (s === 'roster') this.root.innerHTML = this._roster();
    else if (s === 'chars') this.root.innerHTML = this._chars();
    else if (s === 'kit') this.root.innerHTML = this._kitScreen();
    else if (s === 'kit-edit') this.root.innerHTML = this._kitEditor();
    // Previews are real fighters drawn by the real renderer, so they can only be painted once the
    // canvases exist. Everything above is a string; this is the pass that fills them in.
    this._paintPreviews();
  }

  // ------------------------------------------------------------------ the character creator ----

  _view() {
    // One offscreen renderer for every preview on the screen. It never draws a stage, so it needs
    // no match - but Renderer2D wants a canvas at construction.
    if (!this._previewView) this._previewView = new Renderer2D(document.createElement('canvas'));
    return this._previewView;
  }

  _paintPreviews() {
    // Weapon tiles are drawn with the weapon's OWN drawing code rather than from a PNG per weapon.
    // Two of the six icons had simply never been made - the setup screen showed a broken image for
    // the axe and the pike from the day they shipped - and a hand-made icon can disagree with the
    // weapon it labels. This one cannot, and a seventh weapon would need no art at all.
    for (const cv of this.root.querySelectorAll('canvas[data-weapon-icon]')) this._paintWeaponIcon(cv);
    this._paintGrid();
    this._paintKitTiles();
    for (const cv of this.root.querySelectorAll('canvas[data-avatar-preview]')) {
      const av = avatarById(cv.dataset.avatarPreview);
      const editing = this.editing && this.editing.id === av.id ? this.editing : null;
      this._paintOne(cv, editing || av, cv.dataset.previewWeapon || cv.dataset.weapon || 'Sword', +(cv.dataset.ppu || 15));
    }
    const live = this.root.querySelector('canvas[data-live-preview]');
    if (live && this.editing) this._paintOne(live, this.editing, this.previewWeapon || 'Sword', +(live.dataset.ppu || 26));
    this._tickPreview(!!live || this.screen === 'kit-edit');
    this._tickSelectPreviews(this.screen === 'setup');
  }

  _tickSelectPreviews(want) {
    if (!want) { if (this._selectTimer) clearInterval(this._selectTimer); this._selectTimer = null; return; }
    if (this._selectTimer) return;
    this._selectTimer = setInterval(() => {
      if (document.hidden || this.screen !== 'setup') return;
      for (const cv of this.root.querySelectorAll('canvas[data-avatar-preview]')) {
        const r = cv.getBoundingClientRect();
        if (r.bottom < 0 || r.top > window.innerHeight) continue;
        this._paintOne(cv, avatarById(cv.dataset.avatarPreview), cv.dataset.previewWeapon || 'Sword', +(cv.dataset.ppu || 15));
      }
    }, 150);
  }

  // The big preview PLAYS. A still frame of a move is close to useless for judging a character -
  // frame 0 of a signature is a fighter standing still - and the whole point of the screen is to
  // see what you will be looking at for a whole match. The loop only runs while the editor's
  // canvas is on screen, and stops itself the moment it is not.
  _tickPreview(want) {
    if (!want) { if (this._raf) cancelAnimationFrame(this._raf); this._raf = null; return; }
    if (this._raf) return;
    const step = () => {
      const live = this.root.querySelector('canvas[data-live-preview]');
      const kitLive = this.root.querySelector('canvas[data-kit-live]');
      if ((!live || !this.editing) && (!kitLive || !this.kitDraft)) { this._raf = null; return; }
      if (document.hidden) { this._raf = requestAnimationFrame(step); return; }
      if (kitLive) { this._paintKitLive(kitLive); this._raf = requestAnimationFrame(step); return; }
      const mv = this.previewMove && this.editing ? (WEAPONS.find((w) => w.id === (this.previewWeapon || 'Sword')) || {}).moves : null;
      if (this.previewMove && mv && mv[this.previewMove]) {
        const m = mv[this.previewMove];
        // a beat of rest either side of the move, so the loop reads as an action and not a stutter
        const total = m.startup + m.active + m.recovery + 24;
        this.previewFrame = ((this.previewFrame || 0) + 1) % total;
      } else {
        this.previewFrame = 0;
      }
      this._paintOne(live, this.editing, this.previewWeapon || 'Sword', +(live.dataset.ppu || 26));
      this._raf = requestAnimationFrame(step);
    };
    this._raf = requestAnimationFrame(step);
  }

  _paintOne(cv, avatar, weaponId, ppu) {
    const ctx = cv.getContext('2d');
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const width = Math.round(cv.clientWidth * dpr) || cv.width;
    const height = Math.round(cv.clientHeight * dpr) || cv.height;
    if (cv.width !== width || cv.height !== height) { cv.width = width; cv.height = height; }
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, cv.width, cv.height);
    ctx.imageSmoothingEnabled = false;
    // The avatar being edited is not in the registry until it is saved, so the loadout is built
    // from a preset id and then has its avatar swapped in. That keeps unsaved edits out of the
    // registry entirely - an abandoned edit cannot leak into a match.
    const L = { ...buildLoadout(AVATARS[0].id, weaponId), avatar, palette: avatar.palette };
    const mv = this.previewMove ? L.moves[this.previewMove] : null;
    const total = mv ? mv.startup + mv.active + mv.recovery : 0;
    const fr = Math.min(this.previewFrame || 0, total);           // the tail of the loop is the idle beat
    const acting = !!mv && fr < total;
    const f = posedFighter(L, acting ? this.previewMove : null, acting ? fr : 0,
      { state: acting ? 'attack' : 'idle', onGround: true, frameCount: Math.floor(performance.now() / 16) });
    const groundY = cv.height * 0.88;
    ctx.fillStyle = 'rgba(30,42,27,0.13)';
    ctx.fillRect(0, groundY, cv.width, Math.max(1, 2 * dpr));
    ctx.beginPath();                                        // a soft contact shadow
    ctx.ellipse(cv.width / 2, groundY, ppu * dpr * 1.2, ppu * dpr * 0.28, 0, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(30,42,27,0.12)'; ctx.fill();
    this._view().drawFighterInto(ctx, f, performance.now() / 1000,
      { ppu: ppu * dpr, x: cv.width / 2, y: groundY });
  }

  _paintWeaponIcon(cv) {
    const id = cv.dataset.weaponIcon;
    const w = WEAPONS.find((x) => x.id === id);
    if (!w) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const px = 38;
    cv.width = px * dpr; cv.height = px * dpr;
    const ctx = cv.getContext('2d');
    ctx.clearRect(0, 0, cv.width, cv.height);
    ctx.imageSmoothingEnabled = false;
    // Fit the weapon's own reach into the tile, on a diagonal, +Y up like the world transform.
    const span = (REACH[id] || 2.4) + 1.8;
    const ppu = (px * dpr * 0.92) / span;
    ctx.setTransform(ppu, 0, 0, -ppu, cv.width * 0.24, cv.height * 0.78);
    drawWeapon(ctx, id, w.palette, { angle: Math.PI / 4, ox: 0, oy: 0, scale: 1, charge: 0, hide: false });
    ctx.setTransform(1, 0, 0, 1, 0, 0);
  }

  _paintKitTiles() {
    this._kitTileCache ||= new Map();
    for (const cv of this.root.querySelectorAll('canvas[data-kit-option]')) {
      const code = cv.dataset.kitOption, view = cv.dataset.view;
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      const width = Math.max(1, Math.round((cv.clientWidth || 96) * dpr));
      const height = Math.max(1, Math.round((cv.clientHeight || 90) * dpr));
      if (cv._painted === code && cv.width === width && cv.height === height) continue;
      const key = `${code}|${view}|${width}x${height}`;
      const cached = this._kitTileCache.get(key);
      if (cached) { cv.width = width; cv.height = height; cv.getContext('2d').drawImage(cached, 0, 0); cv._painted = code; continue; }
      cv.width = width; cv.height = height; cv._painted = code;
      if (view !== 'head') this._paintOne(cv, kitAvatar(code), 'Sword', Math.min(width / 5, height / 6));
      else {
        const ctx = cv.getContext('2d'), p = KIT_PARTS.head;
        ctx.clearRect(0, 0, width, height);
        const pw = Math.min(width / (p.w + 2), height / (p.h + 2));
        ctx.setTransform(1, 0, 0, -1, width / 2, height / 2 + (p.oy - p.h / 2) * pw);
        drawKitPiece(ctx, code, 'head', pw, pw);
        ctx.setTransform(1, 0, 0, 1, 0, 0);
      }
      const copy = document.createElement('canvas'); copy.width = cv.width; copy.height = cv.height;
      copy.getContext('2d').drawImage(cv, 0, 0);
      this._kitTileCache.set(key, copy);
      if (this._kitTileCache.size > 150) this._kitTileCache.delete(this._kitTileCache.keys().next().value);
    }
  }

  _paintKitLive(cv) {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const width = Math.max(1, Math.round((cv.clientWidth || 280) * dpr));
    const height = Math.max(1, Math.round((cv.clientHeight || 300) * dpr));
    if (cv.width !== width || cv.height !== height) { cv.width = width; cv.height = height; }
    const ctx = cv.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, width, height);
    const weapon = this.previewWeapon || 'Sword';
    const L = buildLoadout(this.kitDraft.code, weapon);
    const pose = this.kitPose || 'idle';
    const move = pose === 'attack' ? 'SigSide' : null;
    const m = move && L.moves[move];
    const frame = m ? Math.floor(performance.now() / 16) % (m.startup + m.active + m.recovery + 24) : 0;
    const f = posedFighter(L, m && frame < m.startup + m.active + m.recovery ? move : null, frame,
      { state: pose === 'jump' ? 'air' : pose, onGround: pose !== 'jump', vx: pose === 'run' ? 12 : 0, frameCount: Math.floor(performance.now() / 16), facing: this.kitFacing || 1 });
    const ppu = Math.min(width / 6.3, height / (this.kitZoom === 'face' ? 3.3 : 6.5));
    const ground = this.kitZoom === 'face' ? height * 1.48 : height * 0.88;
    ctx.fillStyle = '#EFB05A44'; ctx.fillRect(0, height * 0.88, width, Math.max(1, dpr));
    this._view().drawFighterInto(ctx, f, performance.now() / 1000, { ppu, x: width * 0.38, y: ground });
  }

  _kitScreen() {
    const cards = this.kitRoster.characters.map((a, i) => `<button class="kit-card" data-act="kit-edit" data-code="${a.code}" aria-label="Edit ${esc(a.name)}">
      <canvas data-avatar-preview="${a.code}" data-preview-weapon="${this.config.slots[0].weaponId}" data-ppu="18"></canvas>
      <span class="kit-card-copy"><strong>${esc(a.name)}</strong><small>${a.code === this.kitRoster.wearing ? 'Wearing · ' : ''}${this.config.slots[0].weaponId}</small></span><span class="kit-card-index">0${i + 1}</span></button>`).join('');
    return `<div class="screen kit-screen"><div class="kit-heading"><button data-act="title">← Back</button><div><div class="eyebrow">Build your fighter</div><h2>Character studio</h2></div><span>${this.kitRoster.characters.length} / ${MAX_KIT_CHARACTERS} saved</span></div>
      <p class="sub">Choose a look, then take it into the arena. Your weapon decides how you fight.</p>
      <div class="kit-roster">${cards}<button class="kit-card kit-new" data-act="kit-new"><b>＋</b><strong>New character</strong><small>Start with the Rookie kit</small></button></div>
      <div class="kit-legacy"><p>Made a character with the original editor? Those fighters are still here.</p><button data-act="chars">Open original characters</button></div>
      ${this.kitMsg ? `<p class="warn" role="status">${esc(this.kitMsg)}</p>` : ''}</div>`;
  }

  _kitEditor() {
    const spec = decodeKit(this.kitDraft.code);
    const tabs = KIT_GROUPS.map((g) => `<button class="kit-tab ${this.kitGroup === g.id ? 'sel' : ''}" data-kit-group="${g.id}">${g.name}</button>`).join('');
    const group = KIT_GROUPS.find((g) => g.id === this.kitGroup) || KIT_GROUPS[0];
    const cat = KIT_CATEGORIES.find((c) => c.id === (group.parts.includes(this.kitCategory) ? this.kitCategory : group.parts[0])) || KIT_CATEGORIES[0];
    const parts = group.parts.map((id) => { const c = KIT_CATEGORIES.find((x) => x.id === id); return `<button class="kit-part ${c.id === cat.id ? 'sel' : ''}" data-kit-category="${c.id}">${c.name}${this.kitDraft.locks.has(c.id) ? ' 🔒' : ''}</button>`; }).join('');
    const options = group.id === 'presets' ? KIT_PRESETS.map((p) => ({ id: p.id, name: p.name, code: encodeKit(presetKit(p)), view: 'body' }))
      : cat.options.map((o) => ({ ...o, code: encodeKit({ parts: {
        ...spec.parts, [cat.id]: o.id,
        ...(group.id === 'hair' ? { headwear: DEFAULT_KIT.parts.headwear } : {}),
      }, colours: spec.colours }), view: cat.view }));
    const tiles = options.map((o) => `<button class="kit-option ${group.id !== 'presets' && spec.parts[cat.id] === o.id ? 'sel' : ''}" ${o.unlock ? 'disabled' : ''} ${group.id === 'presets' ? `data-kit-preset="${o.id}"` : `data-kit-choice="${o.id}"`} aria-label="${esc(o.name)}${o.unlock ? ', earned in Blockfall on Roblox' : ''}">
      <canvas data-kit-option="${o.code}" data-view="${o.view}"></canvas><span>${esc(o.name)}</span>${o.unlock ? '<small>Earned on the Skyline Climb in Blockfall on Roblox</small>' : ''}</button>`).join('');
    const swatches = group.id === 'presets' ? '' : cat.paint.map((id) => {
      const slot = KIT_COLOURS.find((x) => x.id === id);
      return `<div class="kit-swatch-row"><b>${slot.name}</b><div>${slot.list.map((hex, i) => `<button class="kit-swatch ${spec.colours[id] === i ? 'sel' : ''}" data-kit-colour="${id}" data-kit-index="${i}" style="--sw:${hex}" aria-label="${slot.name} ${i + 1}"></button>`).join('')}</div></div>`;
    }).join('');
    return `<div class="screen kit-editor"><div class="kit-heading"><button data-act="kit-back">← Characters</button><div><div class="eyebrow">Character studio</div><h2>Make your mark</h2></div><button data-act="kit-close">Close</button></div>
      <div class="kit-tools"><button data-act="kit-undo" ${this.kitDraft.undoStack.length ? '' : 'disabled'}>↶ Undo</button><button data-act="kit-redo" ${this.kitDraft.redoStack.length ? '' : 'disabled'}>↷ Redo</button><button data-act="kit-random">✦ Randomise</button><span>Arrows: options / parts · Q E: tabs · R: random</span></div>
      <div class="kit-editor-body"><aside class="kit-preview"><div class="kit-preview-top"><canvas data-kit-live="1"></canvas><div class="kit-preview-controls"><div class="kit-posebar">${['idle','run','jump','attack','victory'].map((p) => `<button data-kit-pose="${p}" class="${this.kitPose === p ? 'sel' : ''}">${p}</button>`).join('')}</div>
        <div class="kit-posebar"><button data-act="kit-turn">↔ Turn</button><button data-act="kit-zoom">${this.kitZoom === 'face' ? 'Full body' : 'Face zoom'}</button></div></div></div>
        <label>Name <input data-kit-name maxlength="20" value="${esc(this.kitName || '')}"></label>
        <label>Weapon <select data-kit-weapon>${WEAPONS.map((w) => `<option value="${w.id}" ${this.previewWeapon === w.id ? 'selected' : ''}>${w.name}</option>`).join('')}</select></label>
        <div class="kit-save"><button data-act="kit-save" class="primary">Save</button><button data-act="kit-save-new">Save as new</button>${this.kitOriginal ? `<button data-act="kit-wear">Wear</button><button data-act="kit-delete">Delete</button>` : ''}</div>
        ${this.kitMsg ? `<p class="warn" role="status">${esc(this.kitMsg)}</p>` : ''}</aside>
      <section class="kit-catalog"><div class="kit-tabs">${tabs}</div>${group.id === 'presets' ? '' : `<div class="kit-parts">${parts}</div><div class="kit-part-tools"><b>${cat.name}</b><button data-act="kit-lock">${this.kitDraft.locks.has(cat.id) ? '🔒 Locked' : '🔓 Lock part'}</button><button data-act="kit-random-part">Random part</button></div>`}
        ${group.id === 'hair' && spec.parts.headwear !== DEFAULT_KIT.parts.headwear ? '<p class="kit-hint">Headwear is hidden in the option tiles so you can see each style.</p>' : ''}
        <div class="kit-options">${tiles}</div><div class="kit-swatches">${swatches}</div></section></div></div>`;
  }

  _charCard(a) {
    const preset = PRESET_IDS.has(a.id);
    return `<div class="charcard ${preset ? 'preset' : ''}">
      <canvas data-avatar-preview="${a.id}" data-ppu="15"></canvas>
      <b>${a.name}</b>
      <small>${preset ? 'Built in' : 'Yours'}</small>
      <div class="row">
        ${preset ? `<button data-act="char-copy" data-id="${a.id}">Start from this</button>`
                 : `<button data-act="char-edit" data-id="${a.id}">Edit</button><button data-act="char-dup" data-id="${a.id}">Copy</button>`}
      </div></div>`;
  }

  _charEditor() {
    const a = this.editing;
    const warn = readabilityWarning(a);
    const swatches = PALETTE_KEYS.map((k) => `<label class="sw"><input type="color" data-colour="${k}" value="${a.palette[k]}"><span>${PALETTE_LABELS[k]}</span></label>`).join('');
    const rows = FEATURE_KEYS.map((k) => `<div class="featrow"><span class="featname">${k}</span>${
      FEATURES[k].map((o) => `<button class="feat ${a.features[k] === o.id ? 'sel' : ''}" data-feature="${k}" data-value="${o.id}">${o.name}</button>`).join('')
    }</div>`).join('');
    const poses = [['', 'Idle'], ['LightNeutral1', 'Jab'], ['SigSide', 'Signature'], ['Ultimate', 'Ultimate']]
      .map(([v, l]) => `<button class="feat ${(this.previewMove || '') === v ? 'sel' : ''}" data-pose="${v}">${l}</button>`).join('');
    const weps = WEAPONS.map((w) => `<button class="feat ${(this.previewWeapon || 'Sword') === w.id ? 'sel' : ''}" data-prevwep="${w.id}">${w.name}</button>`).join('');
    return `<div class="chareditor">
      <div class="charstage">
        <canvas data-live-preview="1" data-ppu="26"></canvas>
        <div class="posebar">${poses}</div>
        <div class="posebar">${weps}</div>
        <p class="hint">Cosmetic only. Every character in this game has identical stats - the weapon decides how you play.</p>
      </div>
      <div class="charform">
        <label class="wide">Name <input type="text" data-charname value="${a.name}" maxlength="${MAX_NAME}"></label>
        <div class="swatches">${swatches}</div>
        ${this.drawMode ? this._pixelPanel() : rows}
        <div class="row"><button data-act="char-mode">${this.drawMode ? 'Back to the parts picker' : 'Draw the pixels yourself'}</button></div>
        ${warn && !this.drawMode ? `<p class="warn">${warn}</p>` : ''}
        <div class="row end">
          ${this._isSaved(a.id) ? `<button data-act="char-delete" data-id="${a.id}">${this.confirmDelete === a.id ? 'Delete for good' : 'Delete'}</button>` : ''}
          <button data-act="char-cancel">Cancel</button>
          <button class="primary" data-act="char-save">Save character</button>
        </div>
        ${this.charMsg ? `<p class="warn">${this.charMsg}</p>` : ''}
      </div></div>`;
  }

  _pixelPanel() {
    const a = this.editing;
    const part = this.drawPart || 'head';
    const g = PART_GRIDS[part];
    const drawn = PART_IDS.filter((k) => a.art && a.art[k]);
    const tabs = PART_IDS.map((k) => `<button class="feat ${k === part ? 'sel' : ''}" data-drawpart="${k}">${PART_GRIDS[k].name}${a.art && a.art[k] ? ' •' : ''}</button>`).join('');
    const inks = INKS.map((i) => {
      const col = inkColour(i.id, a.palette);
      const sel = (this.ink || '1') === i.id ? 'sel' : '';
      return `<button class="ink ${sel} ${i.id === '.' ? 'erase' : ''}" data-ink="${i.id}" title="${i.name}" style="--ink:${col || 'transparent'}"></button>`;
    }).join('');
    return `<div class="pixelpanel">
      <p class="hint">Draw the parts and the rig animates them — every wind-up, every swing, the weapon still in the hand. Leave a part undrawn and it keeps the built-in shape.</p>
      <div class="posebar">${tabs}</div>
      <div class="pixelrow">
        <canvas class="pixgrid" data-pixgrid="${part}" width="${g.w}" height="${g.h}"></canvas>
        <div class="pixtools">
          <div class="inks">${inks}</div>
          <button data-act="pix-trace">Trace the current look</button>
          <button data-act="pix-clear">Clear ${g.name.toLowerCase()}</button>
          ${drawn.length ? `<button data-act="pix-dropall">Use built-in shapes again</button>` : ''}
          <p class="hint small">${g.w} x ${g.h}. Colours follow the swatches above, so you can recolour a drawing any time.</p>
        </div>
      </div></div>`;
  }

  // The grid is a canvas rather than a few hundred divs: at 12x13 that is 156 elements rebuilt on
  // every stroke, and painting is a drag gesture - it has to be cheap per pointer move.
  _paintGrid() {
    const cv = this.root.querySelector('canvas[data-pixgrid]');
    if (!cv || !this.editing) return;
    const part = cv.dataset.pixgrid, g = PART_GRIDS[part];
    const px = (this.editing.art && this.editing.art[part]) || blankPart(part);
    const cell = Math.max(8, Math.floor(Math.min(300 / g.w, 320 / g.h)));
    cv.width = g.w * cell; cv.height = g.h * cell;
    cv.style.width = (g.w * cell) + 'px'; cv.style.height = (g.h * cell) + 'px';
    const c = cv.getContext('2d');
    c.imageSmoothingEnabled = false;
    for (let y = 0; y < g.h; y++) for (let x = 0; x < g.w; x++) {
      // A chequerboard under the art, so "transparent" is visibly transparent rather than a colour
      const even = (x + y) % 2 === 0;
      c.fillStyle = even ? '#e9eee2' : '#dde4d4';
      c.fillRect(x * cell, y * cell, cell, cell);
      const col = inkColour(cellAt(px, part, x, y), this.editing.palette);
      if (col) { c.fillStyle = col; c.fillRect(x * cell, y * cell, cell, cell); }
    }
    c.strokeStyle = 'rgba(30,42,27,0.14)'; c.lineWidth = 1;
    for (let x = 0; x <= g.w; x++) { c.beginPath(); c.moveTo(x * cell + 0.5, 0); c.lineTo(x * cell + 0.5, cv.height); c.stroke(); }
    for (let y = 0; y <= g.h; y++) { c.beginPath(); c.moveTo(0, y * cell + 0.5); c.lineTo(cv.width, y * cell + 0.5); c.stroke(); }
    if (!cv._wired) {
      cv._wired = true;
      const paint = (ev) => {
        const rect = cv.getBoundingClientRect();
        const gx = Math.floor(((ev.clientX - rect.left) / rect.width) * g.w);
        const gy = Math.floor(((ev.clientY - rect.top) / rect.height) * g.h);
        this._setPixel(part, gx, gy, ev.buttons === 2 || ev.shiftKey ? '.' : (this.ink || '1'));
      };
      cv.addEventListener('pointerdown', (ev) => {
        // Capture so a stroke that leaves the grid keeps painting, but never let it stop the
        // stroke: setPointerCapture throws for a pointer the browser does not consider active,
        // and an exception here would swallow the first cell of every stroke.
        try { cv.setPointerCapture(ev.pointerId); } catch (e) { /* keep drawing anyway */ }
        this._painting = true; paint(ev); ev.preventDefault();
      });
      cv.addEventListener('pointermove', (ev) => { if (this._painting) paint(ev); });
      cv.addEventListener('pointerup', () => { this._painting = false; });
      cv.addEventListener('pointercancel', () => { this._painting = false; });
      cv.addEventListener('contextmenu', (ev) => ev.preventDefault());   // right-drag erases
    }
  }

  _setPixel(part, x, y, ink) {
    const a = this.editing;
    if (!a) return;
    const g = PART_GRIDS[part];
    if (x < 0 || y < 0 || x >= g.w || y >= g.h) return;
    a.art = a.art || {};
    a.art[part] = setCell(a.art[part] || blankPart(part), part, x, y, ink);
    // Repaint the grid and the character, but do NOT re-render the screen: rebuilding the DOM
    // mid-drag drops the pointer capture and the stroke ends after one cell.
    this._paintGrid();
    this._paintPreviews();
  }

  _chars() {
    const mine = readCustom(browserStore());
    const grid = mine.map((a) => this._charCard(a)).join('') + AVATARS.map((a) => this._charCard(a)).join('');
    return `<div class="screen simple wide chars"><button data-act="title">← Back</button>
      <h2>Characters</h2>
      <p class="sub">Build a fighter and keep it. Saved in this browser - ${mine.length} of ${MAX_CUSTOM} slots used.</p>
      ${this.editing ? this._charEditor() : ''}
      <div class="row"><button class="primary" data-act="char-new">New character</button>
        <button data-act="char-io">${this.showIO ? 'Hide' : 'Backup or transfer'}</button></div>
      ${this.showIO ? `<div class="chario">
        <p class="hint">Characters live in this browser only. Copy this somewhere safe, or paste someone else's in to add theirs.</p>
        <textarea data-chario rows="6">${exportAvatars(mine)}</textarea>
        <div class="row"><button data-act="char-import">Add the characters in this box</button></div></div>` : ''}
      <div class="chargrid">${grid}</div></div>`;
  }

  _title() {
    return `<div class="screen title"><div class="title-card">
      <div class="eyebrow">${TAGLINE}</div>
      <h1>${TITLE}</h1>
      <p class="sub">${SUBTITLE}</p>
      <div class="col">
        <button class="primary big" data-act="quick">Quick play <small>you vs a bot on Foundry Floor</small></button>
        <button class="big" data-act="setup">Set up a match</button>
        <button class="big" data-act="training">Training</button>
        <button class="big" data-act="kit">Character studio</button>
        <div class="row"><button data-act="roster">Weapons</button><button data-act="controls">Controls</button><button data-act="settings">Settings</button></div>
      </div>
      <p class="hint">Keyboard 1: WASD move · Space jump · J light · K heavy · L dodge · I guard · U grab</p>
    </div><div class="title-bg"></div></div>`;
  }

  _setup() {
    const c = this.config;
    const teams = c.mode.includes('Teams');
    const active = Math.max(0, Math.min(7, this.selectSlot || 0));
    const selected = c.slots[active];
    const allSlots = this.showMoreSlots || active >= 4 || c.slots.slice(4).some((sl) => sl.type !== 'off');
    const slots = c.slots.slice(0, allSlots ? 8 : 4).map((sl, i) => {
      const off = sl.type === 'off', avatar = avatarById(sl.avatarId);
      return `<div class="select-slot ${off ? 'off' : 'ready'} ${active === i ? 'active' : ''}" style="--pc:${PLAYER_COLORS[i]}">
        <button class="select-slot-main" data-slot-pick="${i}" aria-label="Configure Player ${i + 1}">
          <span class="select-slot-mark">${PLAYER_MARKS[i]} <b>P${i + 1}</b></span>
          ${off ? '<span class="join-text">Press a button to join</span>' : `<canvas data-avatar-preview="${sl.avatarId}" data-preview-weapon="${sl.weaponId}" data-ppu="16"></canvas><strong>${esc(avatar.name)}</strong><small>${sl.weaponId}</small>`}
          <span class="ready-tag">${off ? 'EMPTY' : 'READY'}</span></button>
        <select aria-label="Player ${i + 1} input" data-slot="${i}" data-field="type">${SLOT_TYPES.map(([v, l]) => `<option value="${v}" ${sl.type === v ? 'selected' : ''}>${l}</option>`).join('')}</select>
        ${teams ? `<select aria-label="Player ${i + 1} team" data-slot="${i}" data-field="team"><option value="0" ${sl.team === 0 ? 'selected' : ''}>Green team</option><option value="1" ${sl.team === 1 ? 'selected' : ''}>Orange team</option></select>` : ''}
      </div>`;
    }).join('');
    const avatarList = [...AVATARS, ...this.kitRoster.characters.map((row) => avatarById(row.code)), ...readCustom(browserStore())];
    const avatarCards = avatarList.map((a, i) => `<button class="select-character ${a.id === selected.avatarId ? 'sel' : ''}" data-slot="${active}" data-avatar="${a.id}" aria-label="Choose ${esc(a.name)} for Player ${active + 1}" style="--delay:${Math.min(i, 12) * 25}ms">
      <canvas data-avatar-preview="${a.id}" data-preview-weapon="${selected.weaponId}" data-ppu="17"></canvas><strong>${esc(a.name)}</strong><small>${selected.weaponId}</small></button>`).join('');
    const L = buildLoadout(selected.avatarId, selected.weaponId), w = L.weapon;
    const bars = [['Speed', L.runSpeed, 34], ['Power', w.moves?.HeavyNeutral?.damage || 12, 30], ['Reach', REACH[w.id] || 2.4, 5], ['Weight', L.weight, 140]]
      .map(([name, value, max]) => `<div class="weapon-stat"><span>${name}</span><i><b style="width:${Math.min(100, Math.round(value / max * 100))}%"></b></i></div>`).join('');
    const weapons = WEAPONS.map((x) => `<button class="select-weapon ${x.id === selected.weaponId ? 'sel' : ''}" data-slot="${active}" data-weapon="${x.id}" aria-label="Choose ${x.name} for Player ${active + 1}"><canvas data-weapon-icon="${x.id}"></canvas><span>${x.name}</span></button>`).join('');
    const set = c.mapSet || 'all';
    const stages = `<button class="stagetile random ${c.stageId === 'Random' ? 'sel' : ''}" data-stage="Random">${thumbSVG(randomThumb(160, 90), 160, 90)}<span>Random</span><small>Any map in ${MAP_SETS.find(([id]) => id === set)[1].toLowerCase()}</small></button>` + mapSet(set).map((s) => `<button class="stagetile ${s.id === c.stageId ? 'sel' : ''}" data-stage="${s.id}">${stageSVG(s)}<span>${s.name}${s.ranked ? ' <em>ranked</em>' : ''}</span><small>${s.theme} · ${s.hazards.length ? s.hazards.map((h) => h.type).join(', ') : 'no hazards'} · Disaster: ${(s.disasters || []).join(', ') || 'none'}</small></button>`).join('');
    return `<div class="screen setup">
      <div class="setup-top"><button data-act="title">← Back</button><h2>Player select</h2>
        <div class="presets">${RULES.presets.map((p) => `<button class="preset ${presetOf(c) === p.id ? 'sel' : ''}" data-preset="${p.id}" title="${p.hint}">${p.name}</button>`).join('')}</div>
        <div class="opts">
          <label>Mode <select data-field="mode">${MODES.map(([v, l]) => `<option value="${v}" ${c.mode === v ? 'selected' : ''}>${l}</option>`).join('')}</select></label>
          <label>Stocks <select data-field="stocks">${[1, 2, 3, 4, 5].map((n) => `<option ${c.stocks === n ? 'selected' : ''}>${n}</option>`).join('')}</select></label>
          <label>Time <select data-field="time">${[[120, '2:00'], [180, '3:00'], [240, '4:00'], [300, '5:00']].map(([v, l]) => `<option value="${v}" ${c.time === v ? 'selected' : ''}>${l}</option>`).join('')}</select></label>
          <label><input type="checkbox" data-field="items" ${c.items ? 'checked' : ''}> Items</label>
          <label>Disasters <select data-field="disasters">${DISASTER_MODES.map(([v, l]) => `<option value="${v}" ${c.disasters === v ? 'selected' : ''}>${l}</option>`).join('')}</select></label>
        </div></div>
      <div class="select-slots">${slots}</div><button class="select-more" data-act="more-slots">${allSlots ? '− Hide players 5–8' : '＋ Add players 5–8'}</button>
      <div class="select-heading"><div><div class="eyebrow">${PLAYER_MARKS[active]} Player ${active + 1}</div><h3>Choose your fighter</h3></div><button data-act="kit-new">＋ New character</button></div>
      <div class="select-characters">${avatarCards}</div>
      <div class="select-heading"><div><div class="eyebrow">Your fighting style</div><h3>Choose a weapon</h3></div><p>${esc(w.archetype)} · ${esc(w.tagline)}</p></div>
      <div class="select-weapons">${weapons}</div><div class="select-weapon-info"><div><strong>${esc(w.name)}</strong><p>${esc(w.blurb)}</p><small>Signature: ${esc(w.moves[w.signature].label)}</small></div><div class="weapon-stats">${bars}</div></div>
      <h3>Stage</h3><div class="mapsets">${MAP_SETS.map(([id, l]) => `<button class="mapset ${id === set ? 'sel' : ''}" data-mapset="${id}">${l}</button>`).join('')}</div><div class="stages">${stages}</div>
      <div class="setup-bottom"><button class="primary big" data-act="start">Fight</button></div>
    </div>`;
  }

  _controls() {
    return `<div class="screen simple"><button data-act="title">← Back</button><h2>Controls</h2>
      <div class="cards">
        <div class="card"><h3>Keyboard 1</h3><p>${BINDINGS_TEXT.kb1}</p></div>
        <div class="card"><h3>Keyboard 2</h3><p>${BINDINGS_TEXT.kb2}</p></div>
        <div class="card"><h3>Gamepad</h3><p>${BINDINGS_TEXT.pad}</p></div>
      </div>
      <h3>Actions</h3>
      <table class="ctl"><tr><th>Action</th><th>How</th></tr>
      <tr><td>Light strings</td><td>Light, with neutral / side / down. Press again after a hit to chain.</td></tr>
      <tr><td>Aerials</td><td>Light in the air, with neutral / forward / down.</td></tr>
      <tr><td>Signatures</td><td>Heavy on the ground, with side or down. Some can be held to charge.</td></tr>
      <tr><td>Recovery</td><td>Heavy in the air (or Up + Heavy). Once per air time.</td></tr>
      <tr><td>Ground pound</td><td>Down + Heavy in the air.</td></tr>
      <tr><td>Dash / dodge</td><td>Dodge with a direction on the ground dashes; alone it spot dodges; in the air it air dodges.</td></tr>
      <tr><td>Shield / grab</td><td>Hold Guard to shield. Grab, or Guard + Light, grabs. Direction during the hold picks the throw.</td></tr>
      <tr><td>Ledge</td><td>Fall past a ledge facing it, or tap Guard. Then: toward stage to get up, Dodge to roll, Light to attack, Jump, Down to drop.</td></tr>
      <tr><td>Tech</td><td>Tap Guard just before hitting the ground while tumbling. Hold a direction to tech-roll.</td></tr>
      <tr><td>Items</td><td>Tap Guard over an item to pick up. Light uses it, Heavy throws it, Down + Guard drops it.</td></tr>
      <tr><td>Match</td><td>Esc pauses. P picks up items. M mutes music when Keyboard 2 is inactive. In training: R resets, H shows hitboxes, B toggles the dummy's brain.</td></tr>
      </table></div>`;
  }

  _settings() {
    const s = this.settings;
    return `<div class="screen simple"><button data-act="title">← Back</button><h2>Settings</h2>
      <div class="card settings-card">
        <label><input type="checkbox" data-setting="hitboxes" ${s.hitboxes ? 'checked' : ''}> Show hitboxes and blast zones</label>
        <label><input type="checkbox" data-setting="shake" ${s.shake ? 'checked' : ''}> Camera shake</label>
        <label>Music <input type="range" min="0" max="1" step="0.05" data-setting="music" value="${s.music}"></label>
        <label>Sound effects <input type="range" min="0" max="1" step="0.05" data-setting="sfx" value="${s.sfx}"></label>
      </div></div>`;
  }

  _roster() {
    const cards = WEAPONS.map((w) => {
      const L = buildLoadout('Classic', w.id);
      const moves = Object.values(w.moves).map((m) => `<tr><td>${m.label}</td><td class="mono">${m.startup}/${m.active}/${m.recovery}</td><td class="mono">${m.damage}%</td><td class="mono">${m.kind === 'melee' || m.kind === 'beam' || m.kind === 'burst' ? onBlock(m) : '—'}</td></tr>`).join('');
      // The combo tree is read straight off the data, so this screen can never drift from the game.
      const strings = [];
      for (const [id, m] of Object.entries(w.moves)) {
        for (const [dir, t] of Object.entries(m.chains || {})) strings.push(`${m.label} <em>+${dir}</em> → ${w.moves[t].label}`);
        const ch = m.chainsHeavy;
        if (ch) for (const [dir, t] of (typeof ch === 'string' ? [['', ch]] : Object.entries(ch))) strings.push(`<b>${m.label} <em>+Heavy${dir && dir !== '*' ? ' ' + dir : ''}</em> → ${w.moves[t].label}</b>`);
      }
      return `<div class="card roster-card" style="--pc:${w.palette.primary}">
        <div class="roster-head"><canvas class="wicon" data-weapon-icon="${w.id}" width="34" height="34"></canvas><h3>${w.name}</h3><span class="arche">${w.archetype} · ${w.tagline}</span></div>
        <p>${w.blurb}</p>
        <p class="mono small">Weight ${L.weight} · Run ${L.runSpeed.toFixed(1)} · Air ${L.airSpeed.toFixed(1)} · Fall ${L.fallSpeed.toFixed(1)} · Jumps ${L.jumps} · ${w.mechanic.id} · ${L.recovery.kind} recovery · signature ${w.moves[w.signature].label}</p>
        <h4 class="small">Combo tree</h4><ul class="strings small">${strings.map((x) => `<li>${x}</li>`).join('')}</ul>
        <table class="ctl small"><tr><th>Move</th><th>S/A/R</th><th>Dmg</th><th>On block</th></tr>${moves}</table></div>`;
    }).join('');
    return `<div class="screen simple wide"><button data-act="title">← Back</button><h2>Weapons</h2>
      <p class="sub">Your avatar is who you look like. Your weapon is how you play.</p>
      <div class="cards roster">${cards}</div></div>`;
  }

  _click(e) {
    const t = e.target.closest('[data-act],[data-slot-pick],[data-weapon],[data-avatar],[data-stage],[data-mapset],[data-preset],[data-feature],[data-pose],[data-prevwep],[data-drawpart],[data-ink],[data-kit-group],[data-kit-category],[data-kit-choice],[data-kit-preset],[data-kit-colour],[data-kit-pose]');
    if (!t) return;
    if (t.dataset.slotPick != null) { this.selectSlot = +t.dataset.slotPick; this.render(); return; }
    if (t.dataset.kitGroup) { this._kitStash(); this.kitGroup = t.dataset.kitGroup; this.kitCategory = KIT_GROUPS.find((g) => g.id === this.kitGroup).parts[0] || this.kitCategory; this.render(); return; }
    if (t.dataset.kitCategory) { this._kitStash(); this.kitCategory = t.dataset.kitCategory; this.render(); return; }
    if (t.dataset.kitChoice) { this._kitStash(); this.kitDraft.part(this.kitCategory, t.dataset.kitChoice); this.render(); return; }
    if (t.dataset.kitPreset) {
      this._kitStash(); const preset = KIT_PRESETS.find((p) => p.id === t.dataset.kitPreset);
      if (preset) this.kitDraft.change((s) => { const v = presetKit(preset); s.parts = v.parts; s.colours = v.colours; });
      this.render(); return;
    }
    if (t.dataset.kitColour) { this._kitStash(); this.kitDraft.colour(t.dataset.kitColour, +t.dataset.kitIndex); this.render(); return; }
    if (t.dataset.kitPose) { this._kitStash(); this.kitPose = t.dataset.kitPose; this.render(); return; }
    // The editor's own controls. `_stash` reads the name box before every re-render, because the
    // screen is rebuilt from a string and an unsaved name would otherwise be thrown away by the
    // first colour the player picked after typing it.
    if (t.dataset.feature) { this._stash(); this.editing.features[t.dataset.feature] = t.dataset.value; this.render(); return; }
    // `hasAttribute`, not a truthiness test: the idle pose is the empty string.
    if (t.hasAttribute('data-pose')) { this._stash(); this.previewMove = t.dataset.pose || null; this.render(); return; }
    if (t.dataset.prevwep) { this._stash(); this.previewWeapon = t.dataset.prevwep; this.render(); return; }
    if (t.dataset.drawpart) { this._stash(); this.drawPart = t.dataset.drawpart; this.render(); return; }
    if (t.dataset.ink) { this.ink = t.dataset.ink; this.render(); return; }
    if (t.dataset.weapon && t.dataset.slot != null) { this.config.slots[+t.dataset.slot].weaponId = t.dataset.weapon; this.save(); this.render(); return; }
    if (t.dataset.avatar && t.dataset.slot != null) { this.config.slots[+t.dataset.slot].avatarId = t.dataset.avatar; this.save(); this.render(); return; }
    if (t.dataset.stage) { this.config.stageId = t.dataset.stage; this.save(); this.render(); return; }
    if (t.dataset.preset) { this.config = applyPreset(this.config, t.dataset.preset); this.save(); this.render(); return; }
    if (t.dataset.mapset) {
      this.config.mapSet = t.dataset.mapset;
      // A map that has left the set is not still selected behind the filter.
      if (this.config.stageId !== 'Random' && !mapSet(this.config.mapSet).some((s) => s.id === this.config.stageId)) this.config.stageId = 'Random';
      this.save(); this.render(); return;
    }
    const a = t.dataset.act;
    if (a === 'more-slots') { this.showMoreSlots = !this.showMoreSlots; if (!this.showMoreSlots) this.selectSlot = 0; this.render(); return; }
    if (a === 'kit') { this.kitMsg = null; this.show('kit'); return; }
    if (a === 'kit-new') { this._kitOpen(); return; }
    if (a === 'kit-edit') { this._kitOpen(t.dataset.code); return; }
    if (a === 'kit-back' || a === 'kit-close') { this._kitLeave(); return; }
    if (a === 'kit-undo' || a === 'kit-redo') { this._kitStash(); this.kitDraft[a === 'kit-undo' ? 'undo' : 'redo'](); this.render(); return; }
    if (a === 'kit-random') { this._kitStash(); this.kitDraft.randomise(); this.render(); return; }
    if (a === 'kit-random-part') { this._kitStash(); this.kitDraft.randomPart(this.kitCategory); this.render(); return; }
    if (a === 'kit-lock') { this._kitStash(); const locks = this.kitDraft.locks; locks.has(this.kitCategory) ? locks.delete(this.kitCategory) : locks.add(this.kitCategory); this.render(); return; }
    if (a === 'kit-turn') { this._kitStash(); this.kitFacing = -(this.kitFacing || 1); this.render(); return; }
    if (a === 'kit-zoom') { this._kitStash(); this.kitZoom = this.kitZoom === 'face' ? 'body' : 'face'; this.render(); return; }
    if (a === 'kit-save' || a === 'kit-save-new' || a === 'kit-wear') { this._kitSave(a === 'kit-save-new', a === 'kit-wear'); return; }
    if (a === 'kit-delete') {
      if (this.confirmKitDelete !== this.kitOriginal) { this.confirmKitDelete = this.kitOriginal; this.kitMsg = 'Press Delete again to remove this character.'; this.render(); return; }
      const result = deleteKitCharacter(this.kitRoster, this.kitOriginal);
      if (!result.ok) { this.kitMsg = result.reason; this.render(); return; }
      const deleted = this.kitOriginal;
      for (const sl of this.config.slots) if (sl.avatarId === deleted) sl.avatarId = result.roster.wearing;
      this._kitCommit(result.roster, deleted); this.kitDraft = null; this.confirmKitDelete = null; this.show('kit'); return;
    }
    if (a === 'title' || a === 'setup' || a === 'controls' || a === 'settings' || a === 'roster') { this.editing = null; this.charMsg = null; this.show(a); return; }
    if (a === 'chars') { this.editing = null; this.charMsg = null; this.show('chars'); return; }
    if (a === 'char-new') { this._startEdit(blankAvatar(readCustom(browserStore()).length)); return; }
    if (a === 'char-copy') { const src = avatarById(t.dataset.id); this._startEdit(sanitize({ ...src, id: undefined, name: src.name + ' remix' })); return; }
    if (a === 'char-edit') { this._startEdit(sanitize(avatarById(t.dataset.id))); return; }
    if (a === 'char-dup') { const r = duplicateAvatar(avatarById(t.dataset.id)); this.charMsg = r.ok ? null : r.reason; this.render(); return; }
    if (a === 'char-delete') {
      const id = t.dataset.id;
      // A saved character is work. Ask once, in the button itself, rather than with a dialog that
      // interrupts the screen.
      if (this.confirmDelete !== id) { this.confirmDelete = id; this.charMsg = 'Press Delete again to remove this character for good.'; this.render(); return; }
      deleteAvatar(id); this.confirmDelete = null; this.editing = null; this.charMsg = null;
      this._repairSlots(); this.save(); this.render(); return;
    }
    if (a === 'char-cancel') { this.editing = null; this.charMsg = null; this.confirmDelete = null; this.render(); return; }
    if (a === 'char-save') {
      this._stash();
      const r = saveAvatar(this.editing);
      this.charMsg = r.ok ? null : r.reason;
      if (r.ok) { this.editing = null; this.confirmDelete = null; }
      this.render(); return;
    }
    if (a === 'char-mode') { this._stash(); this.drawMode = !this.drawMode; this.render(); return; }
    if (a === 'pix-trace') {
      const part = this.drawPart || 'head';
      this._stash();
      this.editing.art = this.editing.art || {};
      this.editing.art[part] = traceProcedural(part, this.editing.palette, this.editing.features);
      this.render(); return;
    }
    if (a === 'pix-clear') {
      const part = this.drawPart || 'head';
      this._stash();
      if (this.editing.art) delete this.editing.art[part];
      this.render(); return;
    }
    if (a === 'pix-dropall') { this._stash(); delete this.editing.art; this.render(); return; }
    if (a === 'char-io') { this._stash(); this.showIO = !this.showIO; this.render(); return; }
    if (a === 'char-import') {
      const box = this.root.querySelector('[data-chario]');
      const r = importAvatars(box ? box.value : '');
      this.charMsg = r.ok ? `Added ${r.added} character${r.added === 1 ? '' : 's'}.` : r.reason;
      this.render(); return;
    }
    if (a === 'quick') { this.h.onQuick(); return; }
    if (a === 'training') { this.h.onTraining(this.config); return; }
    if (a === 'start') { this.h.onStart(this.config); return; }
  }

  // Pull whatever the player has typed or dragged out of the live DOM and into `this.editing`,
  // before a re-render destroys the inputs.
  _stash() {
    if (!this.editing) return;
    const n = this.root.querySelector('[data-charname]');
    if (n) this.editing.name = n.value;
    for (const inp of this.root.querySelectorAll('input[data-colour]')) this.editing.palette[inp.dataset.colour] = inp.value;
  }

  // Only a character that is actually in storage can be deleted. A brand new one has nothing to
  // delete yet, and offering the button anyway is a dead control at best.
  _isSaved(id) { return !PRESET_IDS.has(id) && readCustom(browserStore()).some((a) => a.id === id); }

  _startEdit(avatar) {
    this.editing = avatar;
    this.charMsg = null; this.confirmDelete = null;
    this.previewMove = this.previewMove || null;
    this.previewWeapon = this.previewWeapon || 'Sword';
    this.show('chars');
  }

  // A deleted character can still be selected in the match config, which would silently hand that
  // player the default body. Point those slots at a character that exists instead.
  _repairSlots() {
    let changed = false;
    for (const sl of this.config.slots) {
      if (avatarById(sl.avatarId).id !== sl.avatarId) { sl.avatarId = AVATARS[0].id; changed = true; }
    }
    return changed;
  }

  _change(e) {
    const t = e.target;
    if (t.hasAttribute('data-kit-name')) { this.kitName = t.value; return; }
    if (t.hasAttribute('data-kit-weapon')) { this.previewWeapon = t.value; this._paintKitLive(this.root.querySelector('canvas[data-kit-live]')); return; }
    if (t.dataset.colour && this.editing) {
      this.editing.palette[t.dataset.colour] = t.value;
      // Repaint the preview without rebuilding the screen: a colour input fires `input` on every
      // mouse move, and re-rendering would close the picker on the first drag.
      this._paintPreviews();
      this._paintGrid();       // cells are palette indices, so a swatch recolours the drawing live
      return;
    }
    if (t.hasAttribute('data-charname') && this.editing) { this.editing.name = t.value; return; }
    if (t.dataset.setting) {
      const k = t.dataset.setting;
      this.settings[k] = t.type === 'checkbox' ? t.checked : parseFloat(t.value);
      this.save(); if (this.h.onSettings) this.h.onSettings(this.settings); return;
    }
    if (t.dataset.field && t.dataset.slot != null) {
      const sl = this.config.slots[+t.dataset.slot];
      const f = t.dataset.field;
      sl[f] = f === 'type' ? t.value : parseInt(t.value, 10);
      this.save(); this.render(); return;
    }
    if (t.dataset.field) {
      const f = t.dataset.field;
      if (f === 'items') this.config.items = t.checked;
      else if (f === 'mode') this.config.mode = t.value;
      else if (f === 'disasters') this.config.disasters = t.value;
      else this.config[f] = parseInt(t.value, 10);
      this.save(); this.render();
    }
  }
}
