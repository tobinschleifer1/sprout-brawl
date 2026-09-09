import sword from './sword.js';
import scythe from './scythe.js';
import blasters from './blasters.js';
import grimoire from './grimoire.js';

export const WEAPONS = [sword, scythe, blasters, grimoire];
export const WEAPON_BY_ID = Object.fromEntries(WEAPONS.map((w) => [w.id, w]));
export const DEFAULT_WEAPON = sword;

// Derived fields, filled once so the engine never has to guess. Same contract the old character
// files had: every move carries its own id, total frame count, kind and hitbox array.
for (const w of WEAPONS) {
  for (const [id, m] of Object.entries(w.moves)) {
    m.id = id;
    m.total = m.startup + m.active + m.recovery;
    m.kind = m.kind || 'melee';
    m.hitboxes = m.hitboxes || [];
  }
}
