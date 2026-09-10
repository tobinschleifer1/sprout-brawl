// Turns keyboard and gamepad state into one input frame per player source, once per sim frame.
// Frame shape: { x, y, jump, light, heavy, dodge, guard, grab, taunt, pickup, ult, jumpHeld, guardHeld, heavyHeld, lightHeld, downTap, anyPress }
// "jump/light/..." are press edges for this frame; "*Held" are levels.

const KB1 = {
  left: ['KeyA'], right: ['KeyD'], up: ['KeyW'], down: ['KeyS'],
  jump: ['Space', 'KeyW'], light: ['KeyJ'], heavy: ['KeyK'], dodge: ['KeyL', 'ShiftLeft'],
  guard: ['KeyI', 'ControlLeft'], grab: ['KeyU'], taunt: ['KeyT'], ult: ['KeyO'],
};
const KB1_ARROWS = { left: ['ArrowLeft'], right: ['ArrowRight'], up: ['ArrowUp'], down: ['ArrowDown'], jump: ['ArrowUp'] };
const KB2 = {
  left: ['ArrowLeft'], right: ['ArrowRight'], up: ['ArrowUp'], down: ['ArrowDown'],
  jump: ['ArrowUp', 'Enter'], light: ['Numpad4'], heavy: ['Numpad5'], dodge: ['Numpad6'],
  guard: ['Numpad8'], grab: ['Numpad7'], taunt: ['Numpad3'], ult: ['Numpad9'],
};

export const BINDINGS_TEXT = {
  kb1: 'Move WASD · Jump Space/W · Light J · Heavy K · Dodge L · Guard I · Grab U · Taunt T · Ultimate O',
  kb2: 'Move Arrows · Jump Up/Enter · Light , · Heavy . · Dodge / · Guard RShift · Grab M · Taunt N · Ultimate RCtrl',
  pad: 'Move Stick · Jump A · Light X · Heavy Y · Dodge B · Guard RB · Grab LB · Ultimate stick-click',
};

const EMPTY = () => ({ x: 0, y: 0, jump: false, light: false, heavy: false, dodge: false, guard: false, grab: false, taunt: false, pickup: false, ult: false,
  jumpHeld: false, guardHeld: false, heavyHeld: false, lightHeld: false, downTap: false, anyPress: false });

export class InputManager {
  constructor() {
    this.keys = new Set();
    this.kb2Active = false;
    this.prevLevels = new Map(); // source -> level snapshot
    this.frames = new Map();
    this.padPrev = new Map();
    window.addEventListener('keydown', (e) => {
      if (e.repeat) return;
      this.keys.add(e.code);
      if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Slash', 'Tab', 'ControlRight'].includes(e.code)) e.preventDefault();
    });
    window.addEventListener('keyup', (e) => this.keys.delete(e.code));
    window.addEventListener('blur', () => this.keys.clear());
  }

  _levelsFromKeys(map, extra) {
    const down = (list) => list.some((k) => this.keys.has(k));
    const l = {
      left: down(map.left) || (extra && down(extra.left)),
      right: down(map.right) || (extra && down(extra.right)),
      up: down(map.up) || (extra && down(extra.up)),
      down: down(map.down) || (extra && down(extra.down)),
      jump: down(map.jump) || (extra && down(extra.jump)),
      light: down(map.light), heavy: down(map.heavy), dodge: down(map.dodge),
      guard: down(map.guard), grab: down(map.grab), taunt: down(map.taunt),
      ult: map.ult ? down(map.ult) : false,
    };
    return l;
  }

  _levelsFromPad(index) {
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    const p = pads[index];
    if (!p) return null;
    const b = (i) => !!(p.buttons[i] && p.buttons[i].pressed);
    const ax = p.axes[0] || 0, ay = -(p.axes[1] || 0);
    const dead = 0.25;
    return {
      left: ax < -dead || b(14), right: ax > dead || b(15), up: ay > dead || b(12), down: ay < -dead || b(13),
      ax: Math.abs(ax) > dead ? ax : 0, ay: Math.abs(ay) > dead ? ay : 0,
      jump: b(0), light: b(2), heavy: b(3), dodge: b(1), guard: b(5) || b(7), grab: b(4) || b(6), taunt: b(9),
      ult: b(10) || b(11),
    };
  }

  _build(source, levels) {
    const prev = this.prevLevels.get(source) || {};
    const edge = (k) => !!levels[k] && !prev[k];
    const f = EMPTY();
    f.x = levels.ax !== undefined && levels.ax !== 0 ? levels.ax : (levels.right ? 1 : 0) - (levels.left ? 1 : 0);
    f.y = levels.ay !== undefined && levels.ay !== 0 ? levels.ay : (levels.up ? 1 : 0) - (levels.down ? 1 : 0);
    f.jump = edge('jump'); f.light = edge('light'); f.heavy = edge('heavy'); f.dodge = edge('dodge');
    f.guard = edge('guard'); f.grab = edge('grab'); f.taunt = edge('taunt'); f.ult = edge('ult');
    f.downTap = edge('down');
    f.jumpHeld = !!levels.jump; f.guardHeld = !!levels.guard; f.heavyHeld = !!levels.heavy; f.lightHeld = !!levels.light;
    f.anyPress = f.jump || f.light || f.heavy || f.dodge || f.guard || f.grab || f.ult;
    this.prevLevels.set(source, { ...levels });
    return f;
  }

  poll() {
    this.frames.set('kb1', this._build('kb1', this._levelsFromKeys(KB1, this.kb2Active ? null : KB1_ARROWS)));
    this.frames.set('kb2', this._build('kb2', this._levelsFromKeys(KB2)));
    for (let i = 0; i < 4; i++) {
      const lv = this._levelsFromPad(i);
      this.frames.set('pad' + i, lv ? this._build('pad' + i, lv) : EMPTY());
    }
  }

  get(source) {
    return this.frames.get(source) || EMPTY();
  }

  isDown(code) { return this.keys.has(code); }
}

export const emptyFrame = EMPTY;
