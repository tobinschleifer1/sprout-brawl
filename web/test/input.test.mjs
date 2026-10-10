import assert from 'node:assert/strict';
import { InputManager, matchShortcut } from '../src/engine/input.js';

const listeners = new Map();
globalThis.window = { addEventListener: (name, fn) => listeners.set(name, fn) };
let pads = [];
Object.defineProperty(globalThis, 'navigator', { configurable: true, value: { getGamepads: () => pads } });
const input = new InputManager();
const key = (code, extra = {}) => listeners.get('keydown')({ code, preventDefault() {}, ...extra });
const release = (code) => listeners.get('keyup')({ code });

key('KeyP'); input.poll();
assert.equal(input.get('kb1').pickup, true, 'P picks up');
assert.equal(matchShortcut({ code: 'KeyP' }), null, 'pickup must not pause');
assert.equal(matchShortcut({ code: 'Escape' }), 'pause');
assert.equal(matchShortcut({ code: 'Escape', repeat: true }), null, 'holding Esc must not repeatedly toggle');
assert.equal(matchShortcut({ code: 'KeyM' }, true), null, 'player two grabs without muting');
assert.equal(matchShortcut({ code: 'KeyM' }, false), 'mute');
release('KeyP'); input.poll();

input.kb2Active = true;
for (const [code, action] of Object.entries({ Comma: 'light', Period: 'heavy', Slash: 'dodge', ShiftRight: 'guard', KeyM: 'grab', KeyN: 'taunt', ControlRight: 'ult', BracketRight: 'pickup' })) {
  key(code); input.poll();
  const frame = input.get('kb2');
  assert.equal(frame[action], true, `${code} must trigger the advertised ${action}`);
  if (action !== 'pickup') assert.equal(frame.pickup, false, `${code} must not also pick up`);
  input.poll(); assert.equal(input.get('kb2')[action], false, `${action} is an edge`);
  release(code); input.poll();
}
key('ArrowRight'); input.poll();
assert.equal(input.get('kb2').x, 1);
assert.equal(input.get('kb1').x, 0, 'arrow keys belong only to player two in two-keyboard matches');
release('ArrowRight');

for (const [code, action] of [['KeyO','ult'],['KeyI','guard']]) {
  input.poll(); key(code); release(code); input.poll();
  assert.equal(input.get('kb1')[action], true, `${code} press/release between frames must survive`);
  if (action === 'guard') assert.equal(input.get('kb1').guardHeld, true, 'shield taps hold for their activation frame');
  input.poll(); assert.equal(input.get('kb1')[action], false, 'latched press fires once');
}

let prevented = false;
key('Space', { target: { tagName: 'INPUT' }, preventDefault() { prevented = true; } });
input.poll();
assert.equal(prevented, false, 'names can contain spaces');
assert.equal(input.get('kb1').jump, false, 'typing does not jump');
assert.equal(matchShortcut({ code: 'Escape', target: { tagName: 'TEXTAREA' } }), null);

pads = [{ axes: [0, 0], buttons: [{ pressed: true }] }];
input.poll(); assert.equal(input.get('pad0').jump, true);
pads = []; input.poll(); assert.equal(input.get('pad0').jumpHeld, false);
pads = [{ axes: [0, 0], buttons: [{ pressed: true }] }];
input.poll(); assert.equal(input.get('pad0').jump, true, 'reconnection must not inherit a stale held button');
console.log('PASS controls: advertised keys, shortcut conflicts, typing, press edges and controller reconnect');
