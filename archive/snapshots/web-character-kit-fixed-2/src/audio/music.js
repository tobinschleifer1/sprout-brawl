// The score.
//
// This replaces a 150 BPM chiptune sequencer with drums, a square lead and hats on every eighth.
// That was fine arcade furniture and completely wrong for the game around it: six stages of quiet
// industrial landscape with a moon over them, and a drum kit playing over the top.
//
// What is here instead is written to the conventions of ambient sandbox-game music - slow, sparse,
// modal, solo-piano-led, no percussion at all, and long gaps where nothing happens. All of the
// melodic material is generated, not sampled or transcribed: each stage gets a mode, a chord
// progression and a seeded phrase generator, so a stage always sounds like itself and never like a
// one-bar loop repeating.
//
// Three things do most of the work, in order of how much they matter:
//
//   1. REVERB. More than the notes. A dry piano note is a beep; the same note into two and a half
//      seconds of tail is an instrument in a room. The impulse response is generated here rather
//      than loaded, because a 200KB .wav for one convolver is not worth it.
//   2. SPACE. The generator rests far more than it plays - roughly two beats of silence for every
//      note. The temptation when writing this by hand is to fill the bar, and filling the bar is
//      what makes it sound like a game loop.
//   3. TIMBRE. A "piano" here is a fundamental plus two decaying partials with a slight detune on
//      one of them, through a lowpass that closes as the note decays. Struck, wooden, and soft.

const NOTE = { C: 0, 'C#': 1, Db: 1, D: 2, Eb: 3, E: 4, F: 5, 'F#': 6, G: 7, Ab: 8, A: 9, Bb: 10, B: 11 };
const freq = (semi, octave) => 440 * Math.pow(2, (semi - 9 + (octave - 4) * 12) / 12);

// The modes actually used. Lydian and mixolydian are here because a raised fourth and a flat
// seventh are most of what makes this kind of music sound open rather than merely major.
export const MODES = {
  ionian:     [0, 2, 4, 5, 7, 9, 11],
  aeolian:    [0, 2, 3, 5, 7, 8, 10],
  dorian:     [0, 2, 3, 5, 7, 9, 10],
  lydian:     [0, 2, 4, 6, 7, 9, 11],
  mixolydian: [0, 2, 4, 5, 7, 9, 10],
};

// Chord shapes as scale-degree stacks. Sevenths and suspensions, because plain triads in a row is
// what a hymn sounds like and the whole point is to avoid arriving anywhere.
const SHAPES = {
  triad: [0, 2, 4],
  sus:   [0, 3, 4],
  seventh: [0, 2, 4, 6],
  open:  [0, 4, 2 + 7],       // a tenth: the widest voicing here, and the most characteristic
  ninth: [0, 4, 1 + 7],
};

// A track is a mode, a progression of [degree, shape] pairs, and a register. Each is composed for
// its stage rather than transposed from one template.
const TRACKS = {
  // Foundry Floor - cold, mechanical, a minor mode that never resolves upward.
  'Cold Iron': { mode: 'aeolian', bpm: 66, register: 4, spread: 0.55,
    prog: [[0, 'open'], [5, 'triad'], [3, 'seventh'], [4, 'sus'], [0, 'open'], [2, 'triad'], [5, 'ninth'], [4, 'triad']] },
  // The Span - high, exposed, lydian for the height of it.
  'Long Drop': { mode: 'lydian', bpm: 60, register: 5, spread: 0.7,
    prog: [[0, 'open'], [1, 'sus'], [4, 'seventh'], [0, 'ninth'], [3, 'triad'], [4, 'sus'], [0, 'open'], [5, 'triad']] },
  // Smeltworks - the hottest stage, so the warmest mode and the lowest register.
  'Pour': { mode: 'mixolydian', bpm: 72, register: 3, spread: 0.45,
    prog: [[0, 'seventh'], [6, 'triad'], [3, 'open'], [0, 'sus'], [4, 'seventh'], [3, 'triad'], [0, 'ninth'], [6, 'sus']] },
  // Rooftops - night, rain, the most static progression of the six.
  'Nine Floors Up': { mode: 'dorian', bpm: 63, register: 4, spread: 0.6,
    prog: [[0, 'ninth'], [0, 'open'], [3, 'seventh'], [4, 'sus'], [0, 'ninth'], [6, 'triad'], [3, 'open'], [4, 'seventh']] },
  // Saltflat - the emptiest stage gets the emptiest music: two chords and a lot of nothing.
  'Nothing For Miles': { mode: 'ionian', bpm: 56, register: 5, spread: 0.85,
    prog: [[0, 'open'], [0, 'open'], [4, 'sus'], [4, 'sus'], [5, 'triad'], [5, 'ninth'], [3, 'open'], [0, 'sus']] },
  // Undertow - water, so the one progression here that genuinely cycles.
  'Ebb and Flow': { mode: 'dorian', bpm: 58, register: 4, spread: 0.7,
    prog: [[0, 'sus'], [3, 'triad'], [6, 'seventh'], [3, 'sus'], [0, 'open'], [4, 'triad'], [6, 'ninth'], [3, 'open']] },
};

const DEFAULT_TRACK = TRACKS['Cold Iron'];

// A small deterministic generator, so a stage sounds the same every time you load it without any
// of it being written out note by note.
function rng(seed) {
  let s = seed >>> 0 || 1;
  return () => { s ^= s << 13; s >>>= 0; s ^= s >> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
}

export class Music {
  constructor(sfx) {
    this.sfx = sfx; this.playing = false; this.volume = 0.6; this.intensity = 0; this.track = null;
    this.step = 0; this.nextTime = 0; this.timer = null; this.notes = 0;
  }
  get ctx() { return this.sfx.ctx; }
  setVolume(v) { this.volume = v; if (this.bus) this.bus.gain.value = v * 1.5; }

  // ---------------------------------------------------------------------------- reverb ----
  // A generated impulse response: noise under an exponential decay, with the very start attenuated
  // so there is a little pre-delay and the attack of a note still reads as an attack.
  _impulse(seconds = 2.6, decay = 3.4) {
    const rate = this.ctx.sampleRate;
    const len = Math.floor(rate * seconds);
    const buf = this.ctx.createBuffer(2, len, rate);
    for (let ch = 0; ch < 2; ch++) {
      const d = buf.getChannelData(ch);
      for (let i = 0; i < len; i++) {
        const u = i / len;
        const pre = Math.min(1, i / (rate * 0.012));
        d[i] = (Math.random() * 2 - 1) * Math.pow(1 - u, decay) * pre;
      }
    }
    return buf;
  }

  start(track) {
    if (!this.ctx) return;
    this.stop();
    const name = (track && track.name) || null;
    const T = TRACKS[name] || DEFAULT_TRACK;
    this.track = { key: 'C', ...T, ...(track || {}), bpm: (track && track.bpm) || T.bpm };
    // A stage's declared bpm belongs to the old sequencer and is far too fast for this; the
    // composed tempo wins unless a caller passes one deliberately slow.
    if (this.track.bpm > 96) this.track.bpm = T.bpm;
    this.scale = MODES[this.track.mode] || MODES.ionian;
    this.root = NOTE[this.track.key] ?? 0;
    this.rand = rng(name ? [...name].reduce((a, c) => a * 31 + c.charCodeAt(0), 7) : 7);

    this.bus = this.ctx.createGain();
    // 1.5, not 0.55: measured, the score sat at about -38 dBFS RMS at the default volume
    // setting, which is quiet enough to be a rumour. This puts it near -28.
    this.bus.gain.value = this.volume * 1.5;
    this.bus.connect(this.ctx.destination);

    // dry and wet, with most of the signal wet - this music is mostly room
    this.dry = this.ctx.createGain(); this.dry.gain.value = 0.55; this.dry.connect(this.bus);
    this.wet = this.ctx.createGain(); this.wet.gain.value = 0.85;
    try {
      this.verb = this.ctx.createConvolver();
      this.verb.buffer = this._impulse();
      this.wet.connect(this.verb); this.verb.connect(this.bus);
    } catch (e) {
      this.verb = null; this.wet.connect(this.bus);      // no convolver: still plays, just dry
    }

    // The intensity layer. No drums: a low drone and an octave under the bass, which is how this
    // kind of music gets tense without changing what it is.
    this.layer = this.ctx.createGain(); this.layer.gain.value = 0;
    this.layer.connect(this.dry); this.layer.connect(this.wet);

    this.step = 0; this.notes = 0; this.phrase = []; this.phraseAt = 0;
    this.nextTime = this.ctx.currentTime + 0.15;
    this.playing = true;
    this.timer = setInterval(() => this._schedule(), 40);
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null; this.playing = false;
    if (this.drone) { try { this.drone.stop(this.ctx.currentTime + 1.2); } catch (e) { /* */ } this.drone = null; }
    if (this.bus) {
      try { this.bus.gain.setTargetAtTime(0, this.ctx.currentTime, 0.35); } catch (e) { /* */ }
      const b = this.bus; setTimeout(() => b.disconnect(), 1600);
      this.bus = null;
    }
  }

  setIntensity(v) {
    if (this.intensity === v || !this.layer) return;
    this.intensity = v;
    // Slow either way. A hard cut into the last stock would be the most jarring thing in the game.
    this.layer.gain.setTargetAtTime(v ? 1 : 0, this.ctx.currentTime, v ? 1.6 : 2.4);
  }

  // ------------------------------------------------------------------------- the voices ----

  // A struck note: fundamental plus two partials, the second detuned, under a lowpass that closes
  // as it decays. Long tails, and every note goes to the reverb.
  _piano(f, t, dur, gain, dest = null) {
    const out = dest || this.dry;
    const lp = this.ctx.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.setValueAtTime(Math.min(7000, f * 8), t);
    lp.frequency.exponentialRampToValueAtTime(Math.max(300, f * 2.2), t + dur * 0.8);
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(gain, t + 0.012);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    lp.connect(g); g.connect(out);
    if (out !== this.wet) g.connect(this.wet);
    for (const [mul, lvl, det] of [[1, 1, 0], [2, 0.34, 0], [3, 0.12, 1.004]]) {
      const o = this.ctx.createOscillator();
      o.type = 'sine';
      o.frequency.value = f * mul * det || f * mul;
      const pg = this.ctx.createGain(); pg.gain.value = lvl;
      o.connect(pg); pg.connect(lp);
      o.start(t); o.stop(t + dur + 0.05);
    }
    this.notes++;
  }

  // A held chord voice: slow in, slow out, gently detuned against itself.
  _pad(f, t, dur, gain, dest = null) {
    const out = dest || this.dry;
    const lp = this.ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = Math.min(2600, f * 5);
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(gain, t + dur * 0.35);
    g.gain.linearRampToValueAtTime(0.0001, t + dur);
    lp.connect(g); g.connect(out);
    if (out !== this.wet) g.connect(this.wet);
    for (const det of [0.997, 1.003]) {
      const o = this.ctx.createOscillator(); o.type = 'triangle'; o.frequency.value = f * det;
      o.connect(lp); o.start(t); o.stop(t + dur + 0.1);
    }
    this.notes++;
  }

  // ---------------------------------------------------------------------- the generator ----
  // A phrase is two to four notes and then a rest that is usually longer than the phrase was.
  // `spread` is how much of a stage's character is silence: Saltflat is 0.85 and barely plays.
  _newPhrase(degree) {
    const r = this.rand;
    const len = 2 + Math.floor(r() * 3);
    const notes = [];
    // start on a chord tone, then move mostly by step, occasionally by a fourth or a sixth
    let idx = [0, 2, 4][Math.floor(r() * 3)] + degree;
    for (let i = 0; i < len; i++) {
      notes.push(idx);
      const roll = r();
      const move = roll < 0.55 ? (r() < 0.5 ? 1 : -1)
        : roll < 0.8 ? (r() < 0.5 ? 2 : -2)
        : roll < 0.93 ? (r() < 0.5 ? 3 : -3)
        : (r() < 0.5 ? 5 : -5);
      idx += move;
      if (idx > degree + 10) idx -= 7;
      if (idx < degree - 4) idx += 7;
    }
    return notes;
  }

  _degreeToSemi(idx, octave) {
    const oct = Math.floor(idx / 7);
    const semi = this.root + this.scale[((idx % 7) + 7) % 7];
    return freq(semi, octave + oct);
  }

  _schedule() {
    if (!this.playing) return;
    const T = this.track;
    const spb = 60 / T.bpm;
    const step = spb / 2;                       // an eighth is the finest grid this music needs
    while (this.nextTime < this.ctx.currentTime + 0.25) {
      const s = this.step;
      const bar = Math.floor(s / 8) % T.prog.length;
      const inBar = s % 8;
      const t = this.nextTime;
      const [degree, shapeName] = T.prog[bar];
      const shape = SHAPES[shapeName] || SHAPES.triad;

      // The chord, once a bar, held almost the whole bar.
      if (inBar === 0) {
        for (const d of shape) {
          this._pad(this._degreeToSemi(degree + d, T.register - 2), t, spb * 3.6, 0.05);
        }
        // and a root an octave below it, quietly, so the harmony has a floor
        this._piano(this._degreeToSemi(degree, T.register - 3), t, spb * 3.2, 0.09);
      }

      // The melody. A phrase is started, played out over the next few eighths, and then the
      // generator waits - `spread` decides how long.
      if (!this.phrase.length && this.rand() > T.spread * 0.55) {
        this.phrase = this._newPhrase(degree);
        this.phraseAt = 0;
      }
      if (this.phrase.length) {
        // notes land on eighths but not every eighth: a held note is normal here
        if (inBar % 2 === 0 || this.rand() < 0.3) {
          const idx = this.phrase[this.phraseAt++];
          const dur = spb * (1.2 + this.rand() * 1.6);
          this._piano(this._degreeToSemi(idx, T.register), t, dur, 0.15 + this.rand() * 0.06);
          // an octave doubling now and then, which is the one flourish this style allows
          if (this.rand() < 0.12) this._piano(this._degreeToSemi(idx, T.register + 1), t, dur * 0.7, 0.05);
          if (this.phraseAt >= this.phrase.length) this.phrase = [];
        }
      }

      // THE FINAL-STOCK LAYER. Still no percussion - but measured at its first gains it lifted the
      // whole mix by 1.06x, which is a change nobody can hear, and an escalation nobody hears is
      // not an escalation. A fifth drone, a bass octave on the bar, a second voice a bar-half
      // later, and a low tonic held right through underneath.
      // Tuned by measurement, twice, in both directions. At the first gains the layer lifted the
      // whole mix by 1.06x - inaudible. At the second it measured LOUDER than everything else put
      // together, which is not tension, it is a different piece of music starting. These land it
      // at about half the level of the rest of the mix: unmistakable, still underneath.
      if (inBar === 0) {
        this._pad(this._degreeToSemi(degree + 4, T.register - 3), t, spb * 4.4, 0.085, this.layer);
        this._pad(this._degreeToSemi(degree, T.register - 4), t, spb * 4.4, 0.095, this.layer);
        this._piano(this._degreeToSemi(degree, T.register - 4), t, spb * 2.6, 0.12, this.layer);
      }
      if (inBar === 4) {
        this._piano(this._degreeToSemi(degree + 4, T.register - 4), t, spb * 2.0, 0.08, this.layer);
        this._pad(this._degreeToSemi(degree + 2, T.register - 3), t, spb * 2.2, 0.055, this.layer);
      }

      this.nextTime += step;
      this.step++;
    }
  }
}
