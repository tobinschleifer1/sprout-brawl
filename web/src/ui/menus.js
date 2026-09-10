import { WEAPONS } from '../data/weapons/index.js';
import { AVATARS } from '../data/avatars.js';
import { buildLoadout } from '../data/loadout.js';
import { STAGES } from '../data/stages/index.js';
import { BINDINGS_TEXT } from '../engine/input.js';
import { PLAYER_COLORS, PLAYER_MARKS } from './hud.js';
import { onBlock } from '../engine/knockback.js';
import { TITLE, TAGLINE, SUBTITLE, SAVE_KEY } from '../data/branding.js';

const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
const SLOT_TYPES = [['off', 'Off'], ['kb1', 'Keyboard 1'], ['kb2', 'Keyboard 2'], ['pad0', 'Gamepad 1'], ['pad1', 'Gamepad 2'], ['pad2', 'Gamepad 3'], ['pad3', 'Gamepad 4'], ['bot-easy', 'Bot · Easy'], ['bot-normal', 'Bot · Normal'], ['bot-hard', 'Bot · Hard'], ['bot-elite', 'Bot · Elite'], ['bot-impossible', 'Bot · Impossible'] ];
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
  }

  _title() {
    return `<div class="screen title"><div class="title-card">
      <div class="eyebrow">${TAGLINE}</div>
      <h1>${TITLE}</h1>
      <p class="sub">${SUBTITLE}</p>
      <div class="col">
        <button class="primary big" data-act="quick">Quick play <small>you vs a bot on Potting Bench</small></button>
        <button class="big" data-act="setup">Set up a match</button>
        <button class="big" data-act="training">Training</button>
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
            <img src="assets/ui/weapons/${x.id.toLowerCase()}.png" alt="" width="32" height="32">
            <span class="wname">${x.name}</span><span class="warch">${x.archetype}</span>
            <span class="wdiff" title="difficulty ${x.difficulty}/3">${dots(x.difficulty)}</span></button>`).join('')}</div>
        <div class="wepinfo"><b>${w.tagline}</b>
          <span class="mono">Weight ${L.weight} · Run ${L.runSpeed.toFixed(1)} · Air ${L.airSpeed.toFixed(1)} · ${w.mechanic.id} · ${L.recovery.kind} recovery</span></div>
        <div class="slot-foot">
          <span class="avlabel">Avatar</span>
          <span class="avrow">${AVATARS.map((a) => `<button class="avtile ${a.id === sl.avatarId ? 'sel' : ''}" data-slot="${i}" data-avatar="${a.id}" title="${a.name}">
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
        <div class="roster-head"><img src="assets/ui/weapons/${w.id.toLowerCase()}.png" alt="" width="32" height="32"><h3>${w.name}</h3><span class="arche">${w.archetype} · ${w.tagline}</span></div>
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
    const t = e.target.closest('[data-act],[data-weapon],[data-avatar],[data-stage]');
    if (!t) return;
    if (t.dataset.weapon) { this.config.slots[+t.dataset.slot].weaponId = t.dataset.weapon; this.save(); this.render(); return; }
    if (t.dataset.avatar) { this.config.slots[+t.dataset.slot].avatarId = t.dataset.avatar; this.save(); this.render(); return; }
    if (t.dataset.stage) { this.config.stageId = t.dataset.stage; this.save(); this.render(); return; }
    const a = t.dataset.act;
    if (a === 'title' || a === 'setup' || a === 'controls' || a === 'settings' || a === 'roster') { this.show(a); return; }
    if (a === 'quick') { this.h.onQuick(); return; }
    if (a === 'training') { this.h.onTraining(this.config); return; }
    if (a === 'start') { this.h.onStart(this.config); return; }
  }

  _change(e) {
    const t = e.target;
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
