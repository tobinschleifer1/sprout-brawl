import { HUB } from '../data/hub.js';
import { Fighter } from './fighter.js';
import { StageRuntime } from './stage.js';
import { emptyFrame } from './input.js';

// A harmless local hub avatar, using the real fighter's movement and collision. No attacks,
// items, ultimates, hits or RNG from the match simulation run while exploring the lobby.
export class Lobby {
  constructor(char, data = HUB) {
    this.data = data;
    this.stage = new StageRuntime(data, 1);
    this.setLoadout(char);
  }
  setLoadout(char) {
    this.char = char;
    const old = this.fighter;
    this.fighter = new Fighter({ index: 0, char, x: old?.x ?? this.data.spawn.x, y: old?.y ?? this.data.spawn.y, stocks: 3 });
    const f = this.fighter;
    f.facing = old?.facing ?? 1;
    f.onGround = f.y === 0;
    f.platform = f.onGround ? this.stage.main : null;
    f.setState(f.onGround ? 'idle' : 'air');
    this.ctx = { stage: this.stage, fighters: [f], combat: { fighters: [f] } };
  }
  setScene(data) {
    this.data = data;
    this.stage = new StageRuntime(data, 1);
    this.fighter = null;
    this.setLoadout(this.char);
  }
  step(input) {
    const clean = emptyFrame();
    clean.x = input.x; clean.y = input.y;
    clean.jump = input.jump; clean.jumpHeld = input.jumpHeld; clean.downTap = input.downTap;
    const f = this.fighter;
    f.applyInput(clean); f.step(this.ctx);
    const x = Math.max(this.data.main.x1 + 3, Math.min(this.data.main.x2 - 3, f.x));
    if (x !== f.x) f.vx = 0;
    f.x = x;
    if (f.y < -12) { f.x = this.data.spawn.x; f.y = this.data.spawn.y; f.vx = 0; f.vy = 0; }
  }
  nearest() {
    const f = this.fighter;
    return this.data.stations.find(s => Math.abs(f.x - s.x) <= 7 && Math.abs(f.y - s.y) <= 3) ?? null;
  }
}
