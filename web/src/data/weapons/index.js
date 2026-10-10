import sword from './sword.js';
import scythe from './scythe.js';
import blasters from './blasters.js';
import grimoire from './grimoire.js';
import axe from './axe.js';
import pike from './pike.js';
import gauntlets from './gauntlets.js';
import hammer from './hammer.js';
import longbow from './longbow.js';
import flail from './flail.js';
import shield from './shield.js';
import daggers from './daggers.js';
import whip from './whip.js';
import fists from './fists.js';

export const WEAPONS = [sword, scythe, blasters, grimoire, axe, pike,
  gauntlets, hammer, longbow, flail, shield, daggers, whip];
export const WEAPON_BY_ID = Object.fromEntries(WEAPONS.map((w) => [w.id, w]));
export const DEFAULT_WEAPON = sword;
// What a fighter fights with holding neither of their two weapons (DROPS in config.js). Kept out
// of WEAPONS and WEAPON_BY_ID on purpose: nothing that lists the weapons - the roster, the select
// screen, a bot choosing - should ever offer it.
export const FISTS = fists;

// Derived fields, filled once so the engine never has to guess. Same contract the old character
// files had: every move carries its own id, total frame count, kind and hitbox array.
for (const w of [...WEAPONS, FISTS]) {
  for (const [id, m] of Object.entries(w.moves)) {
    m.id = id;
    m.total = m.startup + m.active + m.recovery;
    m.kind = m.kind || 'melee';
    m.hitboxes = m.hitboxes || [];
  }
}
