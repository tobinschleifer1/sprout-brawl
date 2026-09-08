import thornlock from './thornlock.js';
import capnspore from './capnspore.js';
import sunbeam from './sunbeam.js';
import kelpin from './kelpin.js';
import cacto from './cacto.js';
import duststorm from './duststorm.js';
import mycel from './mycel.js';
import frostbud from './frostbud.js';

export const CHARACTERS = [thornlock, capnspore, sunbeam, kelpin, cacto, duststorm, mycel, frostbud];
export const CHARACTER_BY_ID = Object.fromEntries(CHARACTERS.map((c) => [c.id, c]));

// Fill derived fields once so the engine never has to guess.
for (const c of CHARACTERS) {
  for (const [id, m] of Object.entries(c.moves)) {
    m.id = id;
    m.total = m.startup + m.active + m.recovery;
    m.kind = m.kind || 'melee';
    m.hitboxes = m.hitboxes || [];
  }
}
