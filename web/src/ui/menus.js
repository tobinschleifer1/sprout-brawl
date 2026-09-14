import { WEAPONS } from '../data/weapons/index.js';
import { AVATARS, FEATURES, FEATURE_KEYS, PALETTE_KEYS, PALETTE_LABELS, allAvatars, avatarById, PRESET_IDS } from '../data/avatars.js';
import { blankAvatar, saveAvatar, deleteAvatar, duplicateAvatar, sanitize, readabilityWarning,
  exportAvatars, importAvatars, readCustom, browserStore, MAX_CUSTOM, MAX_NAME } from '../data/customAvatars.js';
import { Renderer2D } from '../render2d/renderer2d.js';
import { posedFighter } from '../render2d/preview.js';
import { drawWeapon, REACH } from '../render2d/weapons2d.js';
import { buildLoadout } from '../data/loadout.js';
import { STAGES } from '../data/stages/index.js';
import { BINDINGS_TEXT } from '../engine/input.js';
import { PLAYER_COLORS, PLAYER_MARKS } from './hud.js';
import { onBlock } from '../engine/knockback.js';
import { TITLE, TAGLINE, SUBTITLE, SAVE_KEY } from '../data/branding.js';

const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
const SLOT_TYPES = [['off', 'Off'], ['kb1', 'Keyboard 1'], ['kb2', 'Keyboard 2'], ['pad0', 'Gamepad 1'], ['pad1', 'Gamepad 2'], ['pad2', 'Gamepad 3'], ['pad3', 'Gamepad 4'], ['bot-easy', 'Bot · Easy'], ['bot-normal', 'Bot · Normal'], ['bot-hard', 'Bot · Hard'], ['bot-elite', 'Bot · Elite'], ['bot-impossible', 'Bot · Impossible'], ['bot-just_dont', 'Bot · Just Don\'t']];
const MODES = [['StockFFA', 'Stock · Free-for-all'], ['TimedFFA', 'Timed · Free-for-all'], ['StockTeams', 'Stock · 2v2'], ['TimedTeams', 'Timed · 2v2'], ['Training', 'Training']];

function stageSVG(s) {
  const b = s.blast; const W = b.right - b.left, H = b.top - b.bottom;
  const X = (x) => ((x - b.left) / W) * 100, Y = (y) => ((b.top - y) / H) * 60;
  let out = `<svg viewBox="0 0 100 60"><rect x="0" y="0" width="100" height="60" fill="${s.palette.sky}"/>`;
  out += `<rect x="${X(s.main.x1)}" y="${Y(s.main.y)}" width="${X(s.main.x2) - X(s.main.x1)}" height="${(s.main.thickness / H) * 60}" fill="${s.palette.ground}"/>`;
  for (const p of s.platforms) out += `<rect x="${X(p.x - p.w / 2)}" y="${Y(p.y)}" width="${(p.w / W) * 100}" height="1.2" fill="${s.palette.platform}"/>`;
  return out + `</svg>`;
}

export class Menus {
  constructor(root, handlers) {
    this.root = el('div', 'menus');
    root.appendChild(this.root);
    this.h = handlers;
    this.config = this._defaultConfig();
    this.settings = { hitboxes: false, music: 0.6, sfx: 0.8, shake: true };
    try { const s = JSON.parse(localStorage.getItem(SAVE_KEY + '-settings') || 'null'); if (s) Object.assign(this.settings, s); } catch (e) { /* ignore */ }
    try {
      const c = JSON.parse(localStorage.getItem(SAVE_KEY + '-config') || 'null');
      if (c && c.slots && c.slots.every((sl) => sl.weaponId)) this.config = { ...this.config, ...c };
    } catch (e) { /* ignore */ }
    this.screen = 'title';
    this.root.addEventListener('click', (e) => this._click(e));
    this.root.addEventListener('change', (e) => this._change(e));
    this.root.addEventListener('input', (e) => this._change(e));
  }

  _defaultConfig() {
    return { mode: 'StockFFA', stocks: 3, time: 180, items: true, stageId: 'FoundryFloor',
      slots: [ { type: 'kb1', weaponId: 'Sword', avatarId: 'Classic', team: 0 },
               { type: 'bot-normal', weaponId: 'Scythe', avatarId: 'Noir', team: 1 },
               { type: 'off', weaponId: 'Blasters', avatarId: 'Ember', team: 0 },
               { type: 'off', weaponId: 'Grimoire', avatarId: 'Moss', team: 1 } ] };
  }

  save() { try { localStorage.setItem(SAVE_KEY + '-config', JSON.stringify(this.config)); localStorage.setItem(SAVE_KEY + '-settings', JSON.stringify(this.settings)); } catch (e) { /* ignore */ } }

  show(screen) { this.screen = screen; this.root.classList.remove('hidden'); this.render(); }
  hide() { this.root.classList.add('hidden'); }

  render() {
    const s = this.screen;
    if (s === 'title') this.root.innerHTML = this._title();
    else if (s === 'setup') this.root.innerHTML = this._setup();
    else if (s === 'controls') this.root.innerHTML = this._controls();
    else if (s === 'settings') this.root.innerHTML = this._settings();
    else if (s === 'roster') this.root.innerHTML = this._roster();
    else if (s === 'chars') this.root.innerHTML = this._chars();
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
    for (const cv of this.root.querySelectorAll('canvas[data-avatar-preview]')) {
      const av = avatarById(cv.dataset.avatarPreview);
      const editing = this.editing && this.editing.id === av.id ? this.editing : null;
      this._paintOne(cv, editing || av, cv.dataset.weapon || 'Sword', +(cv.dataset.ppu || 15));
    }
    const live = this.root.querySelector('canvas[data-live-preview]');
    if (live && this.editing) this._paintOne(live, this.editing, this.previewWeapon || 'Sword', +(live.dataset.ppu || 26));
    this._tickPreview(!!live);
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
      if (!live || !this.editing) { this._raf = null; return; }
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
    cv.width = Math.round(cv.clientWidth * dpr) || cv.width;
    cv.height = Math.round(cv.clientHeight * dpr) || cv.height;
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
    const px = 34;
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
        ${rows}
        ${warn ? `<p class="warn">${warn}</p>` : ''}
        <div class="row end">
          ${this._isSaved(a.id) ? `<button data-act="char-delete" data-id="${a.id}">${this.confirmDelete === a.id ? 'Delete for good' : 'Delete'}</button>` : ''}
          <button data-act="char-cancel">Cancel</button>
          <button class="primary" data-act="char-save">Save character</button>
        </div>
        ${this.charMsg ? `<p class="warn">${this.charMsg}</p>` : ''}
      </div></div>`;
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
        <button class="big" data-act="chars">Characters</button>
        <div class="row"><button data-act="roster">Weapons</button><button data-act="controls">Controls</button><button data-act="settings">Settings</button></div>
      </div>
      <p class="hint">Keyboard 1: WASD move · Space jump · J light · K heavy · L dodge · I guard · U grab</p>
    </div><div class="title-bg"></div></div>`;
  }

  _setup() {
    const c = this.config;
    const teams = c.mode.includes('Teams');
    const slots = c.slots.map((sl, i) => {
      const L = buildLoadout(sl.avatarId, sl.weaponId);
      const w = L.weapon, av = L.avatar;
      const off = sl.type === 'off';
      const dots = (n) => '<i class="d on"></i>'.repeat(n) + '<i class="d"></i>'.repeat(3 - n);
      return `<div class="slot ${off ? 'off' : ''}" style="--pc:${PLAYER_COLORS[i]}">
        <div class="slot-head"><span class="mark">${PLAYER_MARKS[i]}</span><span>Player ${i + 1}</span>
          <select data-slot="${i}" data-field="type">${SLOT_TYPES.map(([v, l]) => `<option value="${v}" ${sl.type === v ? 'selected' : ''}>${l}</option>`).join('')}</select>
          ${teams ? `<select data-slot="${i}" data-field="team"><option value="0" ${sl.team === 0 ? 'selected' : ''}>Green</option><option value="1" ${sl.team === 1 ? 'selected' : ''}>Orange</option></select>` : ''}
        </div>
        ${off ? '' : `<div class="wepgrid">${WEAPONS.map((x) => `<button class="weptile ${x.id === sl.weaponId ? 'sel' : ''}" data-slot="${i}" data-weapon="${x.id}" title="${x.archetype} · ${x.tagline}">
            <canvas class="wicon" data-weapon-icon="${x.id}" width="34" height="34"></canvas>
            <span class="wname">${x.name}</span><span class="warch">${x.archetype}</span>
            <span class="wdiff" title="difficulty ${x.difficulty}/3">${dots(x.difficulty)}</span></button>`).join('')}</div>
        <div class="wepinfo"><b>${w.tagline}</b>
          <span class="mono">Weight ${L.weight} · Run ${L.runSpeed.toFixed(1)} · Air ${L.airSpeed.toFixed(1)} · ${w.mechanic.id} · ${L.recovery.kind} recovery</span></div>
        <div class="slot-foot">
          <span class="avlabel">Avatar</span>
          <span class="avrow">${allAvatars().map((a) => `<button class="avtile ${a.id === sl.avatarId ? 'sel' : ''}" data-slot="${i}" data-avatar="${a.id}" title="${a.name}">
            <i style="background:${a.palette.primary}"></i><i style="background:${a.palette.secondary}"></i></button>`).join('')}</span>
          <span class="arche">${av.name}</span></div>`}
      </div>`;
    }).join('');
    const stages = STAGES.map((s) => `<button class="stagetile ${s.id === c.stageId ? 'sel' : ''}" data-stage="${s.id}">${stageSVG(s)}<span>${s.name}${s.ranked ? ' <em>ranked</em>' : ''}</span><small>${s.theme}${s.hazards.length ? ' · ' + s.hazards.map((h) => h.type).join(', ') : ' · no hazards'}</small></button>`).join('');
    return `<div class="screen setup">
      <div class="setup-top"><button data-act="title">← Back</button><h2>Set up a match</h2>
        <div class="opts">
          <label>Mode <select data-field="mode">${MODES.map(([v, l]) => `<option value="${v}" ${c.mode === v ? 'selected' : ''}>${l}</option>`).join('')}</select></label>
          <label>Stocks <select data-field="stocks">${[1, 2, 3, 4, 5].map((n) => `<option ${c.stocks === n ? 'selected' : ''}>${n}</option>`).join('')}</select></label>
          <label>Time <select data-field="time">${[[120, '2:00'], [180, '3:00'], [240, '4:00'], [300, '5:00']].map(([v, l]) => `<option value="${v}" ${c.time === v ? 'selected' : ''}>${l}</option>`).join('')}</select></label>
          <label><input type="checkbox" data-field="items" ${c.items ? 'checked' : ''}> Items</label>
        </div></div>
      <div class="slots">${slots}</div>
      <h3>Stage</h3><div class="stages">${stages}</div>
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
      <tr><td>Match</td><td>Esc or P pauses. In training: R resets, H shows hitboxes, B toggles the dummy's brain.</td></tr>
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
    const t = e.target.closest('[data-act],[data-weapon],[data-avatar],[data-stage],[data-feature],[data-pose],[data-prevwep]');
    if (!t) return;
    // The editor's own controls. `_stash` reads the name box before every re-render, because the
    // screen is rebuilt from a string and an unsaved name would otherwise be thrown away by the
    // first colour the player picked after typing it.
    if (t.dataset.feature) { this._stash(); this.editing.features[t.dataset.feature] = t.dataset.value; this.render(); return; }
    // `hasAttribute`, not a truthiness test: the idle pose is the empty string.
    if (t.hasAttribute('data-pose')) { this._stash(); this.previewMove = t.dataset.pose || null; this.render(); return; }
    if (t.dataset.prevwep) { this._stash(); this.previewWeapon = t.dataset.prevwep; this.render(); return; }
    if (t.dataset.weapon) { this.config.slots[+t.dataset.slot].weaponId = t.dataset.weapon; this.save(); this.render(); return; }
    if (t.dataset.avatar) { this.config.slots[+t.dataset.slot].avatarId = t.dataset.avatar; this.save(); this.render(); return; }
    if (t.dataset.stage) { this.config.stageId = t.dataset.stage; this.save(); this.render(); return; }
    const a = t.dataset.act;
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
    if (t.dataset.colour && this.editing) {
      this.editing.palette[t.dataset.colour] = t.value;
      // Repaint the preview without rebuilding the screen: a colour input fires `input` on every
      // mouse move, and re-rendering would close the picker on the first drag.
      this._paintPreviews();
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
      else this.config[f] = parseInt(t.value, 10);
      this.save(); this.render();
    }
  }
}
