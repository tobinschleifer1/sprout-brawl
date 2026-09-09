// The avatar is the player's Roblox character. It is COSMETIC ONLY: every avatar shares one stat
// line, so a match is decided by the weapon you picked and how you play it, never by which body
// you happen to be wearing. Weapons apply the stat spread (see data/weapons/).
//
// BASE is deliberately close to the R15 default: ~5 studs tall, two jumps, mid weight.

export const BASE = {
  weight: 100,        // 100 = neutral knockback taken; lighter dies earlier, heavier survives
  runSpeed: 23,
  walkSpeed: 12,
  airSpeed: 18,
  jumps: 2,
  jumpVelocity: 63,
  fallSpeed: 38,
  height: 5.2,
  radius: 1.1,
};

// Presets shown in the avatar column of the select screen. `rig` picks the placeholder geometry
// until real R15 avatars are loaded; `palette` drives the material swap in render/models.js.
export const AVATARS = [
  { id: 'Classic',  name: 'Classic',   rig: 'avatar', palette: { primary: '#F2C94C', secondary: '#4A90D9', tertiary: '#2E5F8A', accent: '#FFF3D0', glow: '#8ED8FF' } },
  { id: 'Noir',     name: 'Noir',      rig: 'avatar', palette: { primary: '#E8E8EC', secondary: '#23232B', tertiary: '#3A3A46', accent: '#FFFFFF', glow: '#9AA6FF' } },
  { id: 'Ember',    name: 'Ember',     rig: 'avatar', palette: { primary: '#F2994A', secondary: '#8A2E1F', tertiary: '#4A1B14', accent: '#FFE0C0', glow: '#FF7A3C' } },
  { id: 'Moss',     name: 'Moss',      rig: 'avatar', palette: { primary: '#8FBF6A', secondary: '#3E6B3A', tertiary: '#294B2A', accent: '#E4F3D6', glow: '#A8FF7A' } },
  { id: 'Vapor',    name: 'Vapor',     rig: 'avatar', palette: { primary: '#F49AC2', secondary: '#6C63C7', tertiary: '#3E3A78', accent: '#FFE4F1', glow: '#FF6BD6' } },
  { id: 'Steel',    name: 'Steel',     rig: 'avatar', palette: { primary: '#B8C0CC', secondary: '#5A6472', tertiary: '#333A45', accent: '#EDF1F6', glow: '#7FD4FF' } },
];

export const AVATAR_BY_ID = Object.fromEntries(AVATARS.map((a) => [a.id, a]));
export const DEFAULT_AVATAR = AVATARS[0];
