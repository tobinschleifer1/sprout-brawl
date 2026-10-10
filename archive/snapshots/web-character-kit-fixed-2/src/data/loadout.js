import { BASE, avatarById, DEFAULT_AVATAR } from './avatars.js';
import { WEAPON_BY_ID, DEFAULT_WEAPON } from './weapons/index.js';

// A loadout is an avatar (cosmetic) plus a weapon (everything that matters). It is composed into
// exactly the shape the engine already expected from a character file, so engine/fighter.js,
// combat.js and match.js never learn that weapons exist. That is deliberate: the Luau port stays a
// straight translation of the engine, and the weapon system is pure data on top of it.
//
// Stat spread comes only from the weapon:
//   stats.set  absolute overrides   { weight: 96 }
//   stats.mul  multipliers on BASE  { runSpeed: 0.97 }

const STAT_KEYS = ['weight', 'runSpeed', 'walkSpeed', 'airSpeed', 'jumps', 'jumpVelocity', 'fallSpeed', 'height', 'radius'];

export function applyStats(weapon) {
  const s = weapon.stats || {};
  const out = { ...BASE };
  for (const k of STAT_KEYS) {
    if (s.mul && s.mul[k] != null) out[k] = out[k] * s.mul[k];
    if (s.set && s.set[k] != null) out[k] = s.set[k];
  }
  out.jumps = Math.max(1, Math.round(out.jumps));
  return out;
}

export function buildLoadout(avatarId, weaponId) {
  const avatar = avatarById(avatarId);   // resolves presets and player-made characters alike
  const weapon = WEAPON_BY_ID[weaponId] || DEFAULT_WEAPON;
  return {
    id: `${avatar.id}:${weapon.id}`,
    name: weapon.name,                 // the HUD names the weapon; the avatar is who you look like
    avatar, weapon,
    archetype: weapon.archetype,
    tagline: weapon.tagline,
    bio: weapon.blurb,
    ...applyStats(weapon),
    palette: avatar.palette,           // body colours
    weaponPalette: weapon.palette,     // weapon mesh + trail colours
    trail: weapon.trail,
    skins: [],                         // paletteFor() indexes this; avatars carry their own colours
    rig: avatar.rig,
    recovery: weapon.recovery,
    mechanic: weapon.mechanic,
    signature: weapon.signature,
    moves: weapon.moves,               // shared by reference: move objects are read-only at runtime
  };
}

// Convenience for menus and tests: every weapon on a default body.
export function weaponRoster(avatarId = DEFAULT_AVATAR.id) {
  return Object.keys(WEAPON_BY_ID).map((w) => buildLoadout(avatarId, w));
}
