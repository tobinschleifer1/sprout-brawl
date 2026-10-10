// Synthesised sound effects. No audio assets needed.
export class SFX {
  constructor() {
    this.ctx = null; this.master = null; this.volume = 0.8;
  }
  ensure() {
    if (this.ctx) { if (this.ctx.state === 'suspended') this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    this.ctx = new AC();
    this.master = this.ctx.createGain(); this.master.gain.value = this.volume; this.master.connect(this.ctx.destination);
    this.musicBus = this.ctx.createGain(); this.musicBus.connect(this.ctx.destination);
    this.noiseBuf = this._noise();
  }
  setVolume(v) { this.volume = v; if (this.master) this.master.gain.value = v; }
  _noise() {
    const len = this.ctx.sampleRate * 1.5; const buf = this.ctx.createBuffer(1, len, this.ctx.sampleRate); const d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    return buf;
  }
  _env(node, t, a, d, peak = 1) { const g = this.ctx.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(peak, t + a); g.gain.exponentialRampToValueAtTime(0.0001, t + a + d); node.connect(g); g.connect(this.master); return g; }
  tone(freq, type, a, d, peak = 0.3, slideTo = null, t0 = 0) {
    if (!this.ctx) return; const t = this.ctx.currentTime + t0;
    const o = this.ctx.createOscillator(); o.type = type; o.frequency.setValueAtTime(freq, t);
    if (slideTo) o.frequency.exponentialRampToValueAtTime(slideTo, t + a + d);
    this._env(o, t, a, d, peak); o.start(t); o.stop(t + a + d + 0.05);
  }
  noise(a, d, peak = 0.3, filterFreq = 2000, q = 0.7, type = 'bandpass', t0 = 0) {
    if (!this.ctx) return; const t = this.ctx.currentTime + t0;
    const s = this.ctx.createBufferSource(); s.buffer = this.noiseBuf;
    const f = this.ctx.createBiquadFilter(); f.type = type; f.frequency.value = filterFreq; f.Q.value = q;
    s.connect(f); this._env(f, t, a, d, peak); s.start(t); s.stop(t + a + d + 0.05);
  }

  play(name, p = {}) {
    if (!this.ctx) return;
    switch (name) {
      case 'hit': {
        const w = p.weight || 100; const heavy = p.heavy || p.launch > 60;
        const f = w <= 90 ? 330 : w <= 105 ? 210 : 130;
        this.noise(0.005, heavy ? 0.16 : 0.08, heavy ? 0.5 : 0.3, w <= 90 ? 2600 : 1400, 0.8);
        this.tone(f, 'sine', 0.005, heavy ? 0.22 : 0.12, heavy ? 0.5 : 0.35, f * 0.5);
        if (p.launch > 100) { this.tone(60, 'sine', 0.01, 0.4, 0.6, 30); this.noise(0.02, 0.35, 0.35, 900, 0.5, 'lowpass'); }
        else if (p.launch > 60) this.tone(90, 'triangle', 0.01, 0.25, 0.35, 45);
        break;
      }
      case 'chip': this.tone(600, 'triangle', 0.005, 0.05, 0.12); break;
      case 'whiff': this.noise(0.02, 0.12, 0.12, 1200, 0.6, 'bandpass'); break;
      case 'whiffheavy': this.noise(0.03, 0.2, 0.2, 500, 0.6, 'lowpass'); this.tone(120, 'sine', 0.02, 0.15, 0.1, 60); break;
      case 'jump': this.tone(300, 'square', 0.005, 0.09, 0.08, 620); break;
      case 'doublejump': this.tone(420, 'square', 0.005, 0.1, 0.09, 880); this.noise(0.01, 0.08, 0.06, 3000); break;
      case 'land': this.noise(0.005, 0.06, p.hard ? 0.4 : 0.12, 500, 0.5, 'lowpass'); if (p.hard) this.tone(70, 'sine', 0.005, 0.2, 0.4, 40); break;
      case 'dash': this.noise(0.02, 0.14, 0.16, 1800, 0.5); break;
      case 'dodge': this.noise(0.01, 0.16, 0.14, 2400, 0.4); this.tone(900, 'sine', 0.01, 0.12, 0.05, 300); break;
      case 'shield': this.tone(240, 'triangle', 0.005, 0.08, 0.12); break;
      case 'block': if (p.perfect) { this.tone(1200, 'sine', 0.005, 0.18, 0.25); this.tone(1800, 'sine', 0.005, 0.22, 0.18); } else { this.tone(180, 'square', 0.005, 0.08, 0.15, 120); this.noise(0.005, 0.05, 0.15, 1500); } break;
      case 'shieldbreak': this.noise(0.005, 0.5, 0.5, 3000, 0.3, 'highpass'); this.tone(500, 'sawtooth', 0.01, 0.6, 0.3, 80); break;
      case 'grab': this.noise(0.01, 0.1, 0.18, 900, 0.8); this.tone(150, 'sine', 0.005, 0.12, 0.25, 90); break;
      case 'ledge': this.noise(0.005, 0.08, 0.2, 700, 0.8); this.tone(200, 'sine', 0.005, 0.06, 0.2); break;
      case 'ko': this.noise(0.01, 0.8, 0.7, 1200, 0.3, 'lowpass'); this.tone(90, 'sine', 0.01, 0.9, 0.8, 30); this.tone(1400, 'square', 0.02, 0.5, 0.1, 200); setTimeout(() => this.tone(520, 'triangle', 0.01, 0.4, 0.2, 260), 120); break;
      case 'count': this.tone(660, 'square', 0.005, 0.12, 0.2); break;
      case 'go': this.tone(660, 'square', 0.005, 0.3, 0.25); this.tone(990, 'square', 0.005, 0.35, 0.2, null, 0.02); this.tone(1320, 'triangle', 0.005, 0.5, 0.2, null, 0.04); break;
      case 'explosion': this.noise(0.005, 0.5, 0.6, 800, 0.4, 'lowpass'); this.tone(70, 'sine', 0.005, 0.5, 0.6, 25); break;
      case 'beam': this.tone(220, 'sawtooth', 0.02, 0.35, 0.25, 880); this.noise(0.02, 0.3, 0.2, 4000, 0.3, 'highpass'); break;
      case 'burst': this.tone(330, 'triangle', 0.01, 0.3, 0.3, 660); this.noise(0.01, 0.25, 0.25, 2000); break;
      case 'freeze': this.tone(1800, 'sine', 0.01, 0.4, 0.2, 2600); this.tone(2400, 'triangle', 0.01, 0.5, 0.12, 3400); this.noise(0.01, 0.3, 0.1, 6000, 0.5, 'highpass'); break;
      case 'counter': this.tone(400, 'square', 0.005, 0.2, 0.25, 900); this.noise(0.01, 0.2, 0.3, 2500); break;
      case 'summon': this.tone(300, 'triangle', 0.02, 0.15, 0.15, 500); break;
      case 'projectile': this.noise(0.01, 0.12, 0.15, 2200, 0.7); this.tone(500, 'square', 0.005, 0.08, 0.08, 300); break;
      case 'bloom': this.tone(880, 'sine', 0.02, 0.35, 0.18, 1320); this.tone(1320, 'sine', 0.02, 0.45, 0.12, 1760, 0.05); break;
      case 'momentum': this.tone(500, 'square', 0.005, 0.15, 0.12, 1000); break;
      case 'pickup': this.tone(700, 'square', 0.005, 0.08, 0.12, 1050); break;
      case 'throwitem': this.noise(0.01, 0.15, 0.18, 1600); break;
      case 'tech': this.tone(1000, 'sine', 0.005, 0.1, 0.15); this.noise(0.005, 0.06, 0.15, 3000); break;
      case 'vent': this.noise(0.05, 0.5, 0.3, 3500, 0.3, 'highpass'); break;
      case 'ui': this.tone(900, 'sine', 0.003, 0.06, 0.1); break;
      case 'suddendeath': this.tone(110, 'sawtooth', 0.02, 0.8, 0.3, 55); this.noise(0.02, 0.6, 0.3, 600, 0.5, 'lowpass'); break;
      case 'game': this.tone(523, 'square', 0.01, 0.3, 0.2); this.tone(659, 'square', 0.01, 0.3, 0.2, null, 0.12); this.tone(784, 'square', 0.01, 0.3, 0.2, null, 0.24); this.tone(1046, 'triangle', 0.01, 0.8, 0.25, null, 0.36); break;
      case 'taunt': this.tone(440, 'triangle', 0.01, 0.15, 0.12, 660); this.tone(660, 'triangle', 0.01, 0.2, 0.1, 880, 0.15); break;
      case 'teleport': this.tone(1200, 'sine', 0.01, 0.2, 0.15, 300); break;
    }
  }
}
