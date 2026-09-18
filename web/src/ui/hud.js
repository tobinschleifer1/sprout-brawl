import { onBlock } from '../engine/knockback.js';
import { ULTIMATE } from '../config.js';
import { posedFighter } from '../render2d/preview.js';

export const PLAYER_COLORS = ['#3E8A2E', '#DE621C', '#3F7FD6', '#9A5FC8', '#D64C8C', '#2FA39A', '#C9A227', '#8A5A2B'];
export const PLAYER_MARKS = ['●', '■', '▲', '◆', '✿', '★', '⬢', '❋'];
export const TEAM_COLORS = { 0: '#3E8A2E', 1: '#DE621C' };

const RAMP = [[0, [246, 248, 241]], [50, [243, 217, 92]], [100, [242, 162, 60]], [150, [232, 98, 42]], [200, [180, 35, 30]]];
export function percentColor(p) {
  const v = Math.min(200, p);
  for (let i = 1; i < RAMP.length; i++) {
    if (v <= RAMP[i][0]) {
      const [a, ca] = RAMP[i - 1], [b, cb] = RAMP[i];
      const k = (v - a) / (b - a);
      const c = ca.map((x, j) => Math.round(x + (cb[j] - x) * k));
      return `rgb(${c[0]},${c[1]},${c[2]})`;
    }
  }
  return 'rgb(180,35,30)';
}

const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };

export class HUD {
  constructor(root) {
    this.root = el('div', 'hud hidden');
    this.timer = el('div', 'timer'); this.tiles = el('div', 'tiles'); this.center = el('div', 'center'); this.labels = el('div', 'labels'); this.training = el('div', 'training hidden');
    this.pause = el('div', 'overlay hidden', '<div class="panel"><h2>Paused</h2><p class="hint">Esc or P to resume</p><div class="row"><button data-act="resume">Resume</button><button data-act="quit">Quit to menu</button></div></div>');
    this.results = el('div', 'overlay hidden');
    this.root.append(this.timer, this.labels, this.center, this.tiles, this.training, this.pause, this.results);
    root.appendChild(this.root);
    this.tileEls = [];
    this.msgTimer = 0;
    this.onPause = null;
    this.pause.addEventListener('click', (e) => { const a = e.target.dataset.act; if (a && this.onPause) this.onPause(a); });
    this.lastPercents = [];
    // The camera has to know how much of the bottom edge the tiles are covering, so it can frame
    // the fight above them instead of behind them. Measured rather than hard-coded: the band's
    // height depends on the tile count, the wrap at narrow widths and the 700px media query.
    this.safeDirty = true;
    window.addEventListener('resize', () => { this.safeDirty = true; });
  }

  // CSS pixels of the bottom edge the tiles occupy, including their 14px offset and a little air.
  _measureSafeBottom(view) {
    if (!view) return;
    if (!this.safeDirty) return;
    const h = this.tiles.offsetHeight;
    if (h <= 0) return;                 // still hidden; measure on a later frame
    view.safeBottom = h + 20;
    this.safeDirty = false;
  }

  show() { this.root.classList.remove('hidden'); }
  hide() { this.root.classList.add('hidden'); this.results.classList.add('hidden'); this.pause.classList.add('hidden'); }

  bind(match) {
    this.match = match;
    this.tiles.innerHTML = ''; this.labels.innerHTML = '';
    this.safeDirty = true;              // a different fighter count is a different band height
    this.tileEls = []; this.labelEls = [];
    for (const f of match.fighters) {
      const color = match.teams ? TEAM_COLORS[f.team] || PLAYER_COLORS[f.index] : PLAYER_COLORS[f.index];
      const t = el('div', 'tile');
      t.style.setProperty('--pc', color);
      // The tile now carries a PORTRAIT of the actual fighter, drawn by the real renderer. With a
      // character creator in the game the tile was the one place a player never saw the character
      // they made - it named their weapon and nothing else - and four grey boxes in a four-player
      // match are hard to tell apart at a glance anyway.
      const who = (f.char.avatar && f.char.avatar.name) || '';
      t.innerHTML = `<div class="tile-top"><canvas class="portrait" width="38" height="46"></canvas>
          <span class="who"><span class="mark">${PLAYER_MARKS[f.index]}</span><span class="pname">${f.name}</span>
          ${who ? `<span class="aname">${who}</span>` : ''}<span class="cname">${f.char.name}</span></span></div>
        <div class="tile-mid"><span class="pct">0%</span><span class="stocks"></span></div>
        <div class="res"><span class="res-label"></span><span class="res-bar"><i></i></span></div>
        <div class="ult"><span class="ult-label">ULT</span><span class="ult-bar"><i></i></span><span class="ult-n">0/${ULTIMATE.hitsRequired}</span></div>`;
      if (f.source === 'kb1' || f.source === 'kb2' || f.source.startsWith('pad')) t.classList.add('local');
      this.tiles.appendChild(t);
      this.tileEls.push({ el: t, portrait: t.querySelector('.portrait'), painted: false, pct: t.querySelector('.pct'), stocks: t.querySelector('.stocks'), resLabel: t.querySelector('.res-label'), resBar: t.querySelector('.res-bar i'), res: t.querySelector('.res'),
        ult: t.querySelector('.ult'), ultBar: t.querySelector('.ult-bar i'), ultN: t.querySelector('.ult-n') });
      const L = el('div', 'label'); L.style.setProperty('--pc', color); L.innerHTML = `<span class="mark">${PLAYER_MARKS[f.index]}</span><span class="lp">0%</span>`;
      this.labels.appendChild(L);
      this.labelEls.push({ el: L, pct: L.querySelector('.lp') });
    }
    this.training.classList.toggle('hidden', !match.training);
    this.lastPercents = match.fighters.map(() => 0);
  }

  message(html, cls = '', ms = 1200) {
    const m = el('div', 'msg ' + cls, html);
    this.center.appendChild(m);
    requestAnimationFrame(() => m.classList.add('in'));
    setTimeout(() => { m.classList.add('out'); setTimeout(() => m.remove(), 400); }, ms);
  }

  update(match, view) {
    const M = match;
    this._measureSafeBottom(view);
    if (M.timed && M.state !== 'suddendeath') { const left = Math.max(0, M.timeLimit - M.time); this.timer.textContent = `${Math.floor(left / 60)}:${String(Math.floor(left % 60)).padStart(2, '0')}`; this.timer.classList.toggle('low', left < 30); }
    else if (M.state === 'suddendeath') { this.timer.textContent = 'SUDDEN DEATH'; this.timer.classList.add('low'); }
    else if (M.training) { this.timer.textContent = 'TRAINING'; this.timer.classList.remove('low'); }
    else { this.timer.textContent = ''; }
    M.fighters.forEach((f, i) => {
      const T = this.tileEls[i]; if (!T) return;
      if (!T.painted && T.portrait) { this._portrait(T.portrait, f, view); T.painted = true; }
      const hidden = f.effects.grit.hide > 0;
      const pctText = hidden ? '??%' : `${Math.round(f.percent)}%`;
      T.pct.textContent = pctText; T.pct.style.color = percentColor(f.percent);
      if (f.percent !== this.lastPercents[i]) { T.pct.classList.remove('pop'); void T.pct.offsetWidth; T.pct.classList.add('pop'); this.lastPercents[i] = f.percent; }
      T.pct.classList.toggle('pulse', f.percent >= 150);
      const stocks = M.training ? 0 : f.stocksLeft();
      T.stocks.textContent = M.timed ? `KO ${f.stats.kos - f.stats.selfDestructs}` : '●'.repeat(Math.min(stocks, 8));
      T.el.classList.toggle('dead', !M.training && !f.alive && stocks === 0);
      T.el.classList.toggle('last', !M.timed && !M.training && stocks === 1);
      const r = f.resource();
      if (r) {
        let label = r.label;
        if (r.needsNodes) { const n = M.combat.nodesOf(f).length; r.value = n / r.segments; label = `Nodes ${n}/${r.segments}`; r.active = n === r.segments; }
        if (r.segments && !r.needsNodes) label = `${r.label} ${r.filled}/${r.segments}`;
        if (f.effects.chill.stacks) label += ` · Chill ${f.effects.chill.stacks}`;
        if (f.effects.tangle.stacks) label += ` · Tangled ${f.effects.tangle.stacks}`;
        T.resLabel.textContent = label; T.resBar.style.width = `${Math.round((r.value || 0) * 100)}%`; T.res.classList.toggle('active', !!r.active); T.res.classList.toggle('passive', !!r.passive);
      }
      // Ultimate meter. Hidden entirely for a loadout with no ultimate, so it never shows a bar
      // that can't fill.
      if (T.ult) {
        const has = !!f.char.moves.Ultimate;
        T.ult.classList.toggle('hidden', !has);
        if (has) {
          T.ultBar.style.width = `${Math.round(f.ultMeter * 100)}%`;
          // Mid-ultimate the bar stops being a meter and becomes whatever the move is spending.
          // Deadeye is the only one with something left to spend, so it shows its magazine.
          if (f.ultActive && f.move && f.move.kind === 'sniper') {
            T.ultBar.style.width = `${Math.round((f.ultShots / f.move.sniper.shots) * 100)}%`;
            T.ultN.textContent = `${f.ultShots} ROUND${f.ultShots === 1 ? '' : 'S'}`;
          } else {
            T.ultN.textContent = f.ultReady ? 'READY' : `${f.ultCharge}/${ULTIMATE.hitsRequired}`;
          }
          T.ult.classList.toggle('ready', f.ultReady || !!f.ultActive);
        }
      }

      const L = this.labelEls[i];
      if (!f.alive || f.state === 'ko') { L.el.style.display = 'none'; }
      else {
        const p = view.project(f.x, f.y + f.h + 1.4);
        L.el.style.display = p.visible ? '' : 'none';
        L.el.style.transform = `translate(${p.x}px, ${p.y}px)`;
        L.pct.textContent = pctText; L.pct.style.color = percentColor(f.percent);
        L.el.classList.toggle('offscreen', p.x < 0 || p.x > window.innerWidth || p.y < 0 || p.y > window.innerHeight);
        if (p.x < 0 || p.x > window.innerWidth || p.y < 0 || p.y > window.innerHeight) {
          const cx = Math.max(24, Math.min(window.innerWidth - 24, p.x)), cy = Math.max(24, Math.min(window.innerHeight - 24, p.y));
          L.el.style.transform = `translate(${cx}px, ${cy}px)`;
        }
      }
    });
    if (M.training) this._trainingInfo(M);
  }

  // One still frame of the fighter, idle, through Renderer2D.drawFighterInto - the same paint path
  // the match uses, so a hand-drawn character shows up here exactly as it does on the stage.
  // Painted once per match: nothing about it changes while the match runs.
  _portrait(cv, f, view) {
    if (!view || !view.drawFighterInto) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const w = cv.width, h = cv.height;
    cv.width = w * dpr; cv.height = h * dpr;
    const ctx = cv.getContext('2d');
    ctx.clearRect(0, 0, cv.width, cv.height);
    ctx.imageSmoothingEnabled = false;
    const ppu = (cv.height * 0.86) / f.char.height;
    try {
      view.drawFighterInto(ctx, posedFighter(f.char, null, 0, { state: 'idle', onGround: true, index: f.index }),
        0, { ppu, x: cv.width / 2, y: cv.height * 0.96 });
    } catch (e) { /* a portrait is never worth failing a frame over */ }
  }

  _trainingInfo(M) {
    const f = M.fighters[0];
    const mv = f.lastMoveInfo;
    let html = `<b>Training</b> · R reset · H hitboxes · B bot on/off<br>`;
    if (f.move) { const m = f.move; f.lastMoveInfo = m; }
    const m = f.lastMoveInfo;
    if (m && m.startup != null) html += `<span class="mono">${m.label || m.id}: ${m.startup}/${m.active}/${m.recovery} · ${m.damage}% · on block ${onBlock(m)}</span>`;
    const d = M.fighters[1];
    if (d) html += `<br><span class="mono">Dummy ${Math.round(d.percent)}% · ${d.state}${d.hitstun > 0 ? ' hitstun ' + d.hitstun : ''}</span>`;
    this.training.innerHTML = html;
  }

  showPause(on) { this.pause.classList.toggle('hidden', !on); }

  showResults(results, onAction) {
    const R = results;
    const rows = R.rows.map((r, i) => {
      const color = R.teams ? TEAM_COLORS[r.team] : PLAYER_COLORS[r.index];
      return `<tr class="${i === 0 ? 'win' : ''}"><td class="place">${i + 1}</td><td><span class="mark" style="color:${color}">${PLAYER_MARKS[r.index]}</span> ${r.name}<small>${(r.char.avatar && r.char.avatar.name ? r.char.avatar.name + ' · ' : '')}${r.char.name}${R.teams ? ' · Team ' + (r.team === 0 ? 'Green' : 'Orange') : ''}</small></td><td>${r.kos}</td><td>${r.falls}</td><td>${r.damage}%</td><td>${R.timed ? r.score : r.stocks}</td></tr>`;
    }).join('');
    const w = R.rows[0];
    this.results.innerHTML = `<div class="panel results"><div class="eyebrow">Results</div><h2>${R.teams ? (w.team === 0 ? 'Green team' : 'Orange team') : w.name} wins</h2>
      <table><tr><th></th><th>Player</th><th>KOs</th><th>Falls</th><th>Dmg dealt</th><th>${R.timed ? 'Score' : 'Stocks'}</th></tr>${rows}</table>
      <div class="row"><button data-act="rematch" class="primary">Play again</button><button data-act="setup">Character select</button><button data-act="menu">Main menu</button></div></div>`;
    this.results.classList.remove('hidden');
    this.results.onclick = (e) => { const a = e.target.dataset.act; if (a) onAction(a); };
  }
  hideResults() { this.results.classList.add('hidden'); }
}
