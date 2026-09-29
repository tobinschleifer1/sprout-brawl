// Climbing the Skyline Climb (data/parkour.js): the real fighter and stage engines on a course,
// plus checkpoints, falls and a clock. Ported line for line to roblox/src/shared/Parkour.luau and
// replayed against it by tests/parkour-parity.luau.
//
// Like the lobby, harmless: only direction, jump and drop-through are read from the input, so an
// attack button does nothing. The stage is stepped every frame, which is what moves the sliding
// girders and lifts and sinks the planks under whoever stands on them.

import { Fighter } from './fighter.js';
import { StageRuntime } from './stage.js';
import { emptyFrame } from './input.js';

// How close to a reward's middle counts as touching it, in studs, across and up and down.
export const REWARD_REACH = 1.6;

export class Parkour {
  // `from` is the checkpoint index to start at (a returning climber's furthest). `opts.climbed` is
  // the furthest checkpoint they have CLIMBED to before (skips excluded) and `opts.collected` the
  // rewards they already have: together they decide which rewards can be picked up.
  constructor(course, char, from = 0, opts = {}) {
    this.course = course;
    this.char = char;
    this.stage = new StageRuntime(course, 1);
    this.stage.placeMovers();
    this.reached = Math.max(0, Math.min(from, course.checkpoints.length - 1));
    this.deaths = 0;
    this.frames = 0;
    this.done = this.reached === course.checkpoints.length - 1;
    this.skipped = false;   // a checkpoint was skipped this climb (skipTo): not a clean, timed climb
    this.climbedTo = Math.max(0, opts.climbed || 0);
    this.collected = new Set(opts.collected || []);
    this.events = [];
    this.spawn();
  }

  pad(index) {
    const id = this.course.checkpoints[index].pad;
    return this.stage.platforms.find((p) => p.id === id);
  }

  // Standing on the checkpoint's pad, at its middle.
  spawn() {
    const p = this.pad(this.reached);
    const f = new Fighter({ index: 0, char: this.char, x: p.cx, y: p.top, stocks: 3 });
    f.invincible = 0;
    f.facing = 1;
    f.onGround = true;
    f.platform = p;
    f.setState('idle');
    this.fighter = f;
    this.padTop = p.top;
    this.ctx = { stage: this.stage, fighters: [f], combat: { fighters: [f] } };
  }

  // Back to the last checkpoint, counting the fall.
  fall() {
    this.deaths++;
    this.events.push({ type: 'fall', checkpoint: this.reached });
    this.spawn();
  }

  step(input) {
    const clean = emptyFrame();
    clean.x = input.x || 0; clean.y = input.y || 0;
    clean.jump = !!input.jump; clean.jumpHeld = !!input.jumpHeld; clean.downTap = !!input.downTap;
    const f = this.fighter;
    this.stage.step(this.ctx);
    f.applyInput(clean);
    f.step(this.ctx);
    if (!this.done) this.frames++;
    // Below the street, or too far below your checkpoint's pad (course.fallDepth): a fall.
    const floor = this.course.fallDepth != null ? Math.max(this.course.killY, this.padTop - this.course.fallDepth) : this.course.killY;
    if (f.y < floor) { this.fall(); return; }
    // A checkpoint counts when you land on its pad. Landing on a later one counts it (and the ones
    // before), so a player who skips a pad with a big jump is not punished for it.
    if (f.onGround && f.platform) {
      for (let i = this.reached + 1; i < this.course.checkpoints.length; i++) {
        if (this.course.checkpoints[i].pad === f.platform.id) {
          this.reached = i;
          this.padTop = f.platform.top;
          this.climbedTo = Math.max(this.climbedTo, i);
          this.events.push({ type: 'checkpoint', checkpoint: i });
          if (i === this.course.checkpoints.length - 1) {
            this.done = true;
            this.events.push({ type: 'summit', frames: this.frames, deaths: this.deaths });
          }
        }
      }
    }
    this.collect();
  }

  // A reward can be picked up by whoever climbed to its checkpoint (now or before) and has not got it.
  available(reward) {
    return !this.collected.has(reward.id) && this.climbedTo >= reward.checkpoint;
  }

  // Touching an available reward collects it.
  collect() {
    const f = this.fighter;
    for (const r of this.course.rewards || []) {
      if (this.available(r) && Math.abs(f.x - r.x) < REWARD_REACH && f.y < r.y + REWARD_REACH && f.y + f.h > r.y - REWARD_REACH) {
        this.collected.add(r.id);
        this.events.push({ type: 'reward', id: r.id, checkpoint: r.checkpoint });
      }
    }
  }

  // A skipped checkpoint (bought, in the Roblox build): stand on its pad as if you had reached it.
  // It raises no checkpoint or summit event - those mean you CLIMBED there, and they are what the
  // server counts - but a 'skip' event, and marks the climb skipped, so it is never timed as a
  // clean one. Skipping to the Summit finishes the climb. Only forward: false if already past it.
  skipTo(index) {
    const i = Math.max(0, Math.min(index, this.course.checkpoints.length - 1));
    if (i <= this.reached) return false;
    this.reached = i;
    this.skipped = true;
    if (i === this.course.checkpoints.length - 1) this.done = true;
    this.events.push({ type: 'skip', checkpoint: i });
    this.spawn();
    return true;
  }

  // Events since the last drain: checkpoints, falls, skips, the summit.
  drain() {
    const out = this.events;
    this.events = [];
    return out;
  }
}
