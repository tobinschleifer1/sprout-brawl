// A tiny step sequencer: chiptune lead over synthesised drums and bass, with an intensity layer.
const NOTE = { C: 0, 'C#': 1, Db: 1, D: 2, Eb: 3, E: 4, F: 5, 'F#': 6, G: 7, Ab: 8, A: 9, Bb: 10, B: 11 };
const MAJOR = [0, 2, 4, 5, 7, 9, 11];
const freq = (semi, octave) => 440 * Math.pow(2, (semi - 9 + (octave - 4) * 12) / 12);

// Chord progression per 8 bars (degrees, 0-based): I V vi IV · I V IV V
const PROG = [0, 4, 5, 3, 0, 4, 3, 4];
// Lead motif per bar in scale-degree offsets from the chord root (16 steps), -1 = rest
const MOTIFS = [
  [0, -1, 2, 4, -1, 4, 2, 0, 7, -1, 4, -1, 2, 4, 7, 9],
  [0, 2, 4, -1, 7, -1, 4, 2, 0, -1, 4, 7, 9, 7, 4, -1],
  [4, -1, 4, 2, 0, -1, 2, 4, 7, 7, -1, 9, 7, 4, 2, 0],
  [0, 4, 7, 9, 7, 4, 0, -1, 2, 4, 7, -1, 9, 11, 9, 7],
];

export class Music {
  constructor(sfx) {
    this.sfx = sfx; this.playing = false; this.volume = 0.6; this.intensity = 0; this.track = null;
    this.step = 0; this.nextTime = 0; this.timer = null;
  }
  get ctx() { return this.sfx.ctx; }
  setVolume(v) { this.volume = v; if (this.bus) this.bus.gain.value = v * 0.5; }

  start(track) {
    if (!this.ctx) return;
    this.stop();
    this.track = { bpm: 150, key: 'C', swing: false, ...track };
    this.bus = this.ctx.createGain(); this.bus.gain.value = this.volume * 0.5; this.bus.connect(this.ctx.destination);
    this.layer = this.ctx.createGain(); this.layer.gain.value = 0; this.layer.connect(this.bus);
    this.step = 0; this.nextTime = this.ctx.currentTime + 0.1; this.playing = true;
    this.root = NOTE[this.track.key] ?? 0;
    this.timer = setInterval(() => this._schedule(), 25);
  }
  stop() { if (this.timer) clearInterval(this.timer); this.timer = null; this.playing = false; if (this.bus) { try { this.bus.gain.setTargetAtTime(0, this.ctx.currentTime, 0.1); } catch (e) { /* */ } const b = this.bus; setTimeout(() => b.disconnect(), 400); this.bus = null; } }
  setIntensity(v) {
    if (this.intensity === v || !this.layer) return;
    this.intensity = v;
    this.layer.gain.setTargetAtTime(v ? 1 : 0, this.ctx.currentTime, v ? 0.4 : 0.9);
  }

  _osc(type, f, t, dur, gain, dest, slide) {
    const o = this.ctx.createOscillator(); o.type = type; o.frequency.setValueAtTime(f, t); if (slide) o.frequency.exponentialRampToValueAtTime(slide, t + dur);
    const g = this.ctx.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(gain, t + 0.005); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g); g.connect(dest); o.start(t); o.stop(t + dur + 0.02);
  }
  _noise(t, dur, gain, dest, hp = 6000) {
    const s = this.ctx.createBufferSource(); s.buffer = this.sfx.noiseBuf;
    const f = this.ctx.createBiquadFilter(); f.type = 'highpass'; f.frequency.value = hp;
    const g = this.ctx.createGain(); g.gain.setValueAtTime(gain, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    s.connect(f); f.connect(g); g.connect(dest); s.start(t); s.stop(t + dur + 0.02);
  }

  _schedule() {
    if (!this.playing) return;
    const T = this.track; const spb = 60 / T.bpm; const s16 = spb / 4;
    while (this.nextTime < this.ctx.currentTime + 0.12) {
      const step = this.step; const bar = Math.floor(step / 16) % 8; const i16 = step % 16;
      let t = this.nextTime;
      if (T.swing && i16 % 2 === 1) t += s16 * 0.3;
      const deg = PROG[bar]; const chordRoot = this.root + MAJOR[deg];
      // kick: 1 and 3 plus the "and" of 2 for bounce
      if (i16 === 0 || i16 === 8 || i16 === 6) this._osc('sine', 130, t, 0.14, 0.9, this.bus, 40);
      // snare
      if (i16 === 4 || i16 === 12) { this._noise(t, 0.12, 0.35, this.bus, 1800); this._osc('triangle', 220, t, 0.08, 0.2, this.bus, 120); }
      // hats (8ths) + intensity 16ths
      if (i16 % 2 === 0) this._noise(t, 0.04, 0.12, this.bus, 8000);
      else this._noise(t, 0.03, 0.14, this.layer, 9000);
      if (i16 === 14) this._noise(t, 0.16, 0.1, this.layer, 7000);
      // bass on 8ths: root, root, fifth, root
      if (i16 % 2 === 0) { const pat = [0, 0, 7, 0, 0, 12, 7, 5]; const semi = chordRoot + pat[(i16 / 2) % 8]; this._osc('triangle', freq(semi, 2), t, s16 * 1.6, 0.5, this.bus); this._osc('square', freq(semi, 2), t, s16 * 0.9, 0.08, this.bus); }
      // lead
      const motif = MOTIFS[bar % 4]; const off = motif[i16];
      if (off >= 0) {
        const scaleIdx = deg + Math.floor(off / 2) * 0 + 0;
        const semi = this.root + MAJOR[(deg + [0, 1, 2, 2, 3, 4, 4, 5, 6, 6, 7, 7][Math.min(off, 11)]) % 7] + (off >= 7 ? 12 : 0);
        this._osc('square', freq(semi, 4), t, s16 * 0.9, 0.11, this.bus);
        this._osc('square', freq(semi, 5), t, s16 * 0.8, 0.09, this.layer);
        this._osc('sine', freq(semi, 3), t, s16 * 0.9, 0.05, this.bus);
      }
      // chord pad on the bar
      if (i16 === 0) for (const n of [0, 4, 7]) this._osc('triangle', freq(chordRoot + n, 3), t, spb * 3.5, 0.045, this.bus);
      this.nextTime += s16; this.step++;
    }
  }
}
