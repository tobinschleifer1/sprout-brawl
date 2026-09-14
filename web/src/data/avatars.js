// The avatar is the player's character. It is COSMETIC ONLY: every avatar shares one stat line, so
// a match is decided by the weapon you picked and how you play it, never by which body you happen
// to be wearing. Weapons apply the stat spread (see data/weapons/).
//
// That rule is what makes a character CREATOR safe to ship. A player can build any body they like
// and it cannot touch weight, speed, reach or frame data — an avatar owns five colours and four
// cosmetic feature choices and nothing else. `buildLoadout` reads stats from the weapon alone, and
// test/avatars.test.mjs measures that a custom avatar produces byte-identical stats to a preset.
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

// The parts a character is made of. Every value here is drawn by render2d/renderer2d.js — the
// avatars test fails if an option is offered and never painted, which is the same dead-data check
// the stage palettes now carry.
export const FEATURES = {
  head: [
    { id: 'block', name: 'Blocky' },
    { id: 'round', name: 'Round' },
    { id: 'tall', name: 'Tall' },
    { id: 'wide', name: 'Wide' },
  ],
  face: [
    { id: 'dot', name: 'One eye' },
    { id: 'pair', name: 'Two eyes' },
    { id: 'visor', name: 'Visor' },
    { id: 'shades', name: 'Shades' },
    { id: 'goggles', name: 'Goggles' },
    { id: 'blank', name: 'Blank' },
  ],
  hat: [
    { id: 'none', name: 'Bare' },
    { id: 'cap', name: 'Cap' },
    { id: 'horns', name: 'Horns' },
    { id: 'crown', name: 'Crown' },
    { id: 'antenna', name: 'Antenna' },
    { id: 'hood', name: 'Hood' },
  ],
  torso: [
    { id: 'belt', name: 'Belt' },
    { id: 'sash', name: 'Sash' },
    { id: 'emblem', name: 'Emblem' },
    { id: 'plain', name: 'Plain' },
  ],
};

export const FEATURE_KEYS = Object.keys(FEATURES);
export const DEFAULT_FEATURES = { head: 'block', face: 'dot', hat: 'none', torso: 'belt' };
export const PALETTE_KEYS = ['primary', 'secondary', 'tertiary', 'accent', 'glow'];

// What each palette slot actually paints, so the editor can label them honestly rather than
// calling them "colour 1" through "colour 5".
export const PALETTE_LABELS = {
  primary: 'Head & front arm',
  secondary: 'Torso & back arm',
  tertiary: 'Legs',
  accent: 'Trim',
  glow: 'Highlight',
};

// Presets shown in the avatar row of the select screen.
export const AVATARS = [
  { id: 'Classic', name: 'Classic', rig: 'avatar', features: { head: 'block', face: 'dot', hat: 'none', torso: 'belt' },
    palette: { primary: '#F2C94C', secondary: '#4A90D9', tertiary: '#2E5F8A', accent: '#FFF3D0', glow: '#8ED8FF' } },
  { id: 'Noir', name: 'Noir', rig: 'avatar', features: { head: 'block', face: 'shades', hat: 'none', torso: 'sash' },
    palette: { primary: '#E8E8EC', secondary: '#23232B', tertiary: '#3A3A46', accent: '#FFFFFF', glow: '#9AA6FF' } },
  { id: 'Ember', name: 'Ember', rig: 'avatar', features: { head: 'round', face: 'pair', hat: 'horns', torso: 'belt' },
    palette: { primary: '#F2994A', secondary: '#8A2E1F', tertiary: '#4A1B14', accent: '#FFE0C0', glow: '#FF7A3C' } },
  { id: 'Moss', name: 'Moss', rig: 'avatar', features: { head: 'wide', face: 'pair', hat: 'hood', torso: 'plain' },
    palette: { primary: '#8FBF6A', secondary: '#3E6B3A', tertiary: '#294B2A', accent: '#E4F3D6', glow: '#A8FF7A' } },
  { id: 'Vapor', name: 'Vapor', rig: 'avatar', features: { head: 'tall', face: 'visor', hat: 'antenna', torso: 'emblem' },
    palette: { primary: '#F49AC2', secondary: '#6C63C7', tertiary: '#3E3A78', accent: '#FFE4F1', glow: '#FF6BD6' } },
  { id: 'Steel', name: 'Steel', rig: 'avatar', features: { head: 'block', face: 'goggles', hat: 'cap', torso: 'emblem' },
    palette: { primary: '#B8C0CC', secondary: '#5A6472', tertiary: '#333A45', accent: '#EDF1F6', glow: '#7FD4FF' } },
];

export const DEFAULT_AVATAR = AVATARS[0];
export const PRESET_IDS = new Set(AVATARS.map((a) => a.id));

// A REGISTRY, not a frozen table.
//
// Avatars used to be a static `AVATAR_BY_ID` object built once at import. Player-made characters
// have to resolve by id from exactly the same lookup the presets do — otherwise every id path in
// the game (saved match config, the menu, a replay) would need to know whether an avatar was built
// in or made by the player, and every one of them would be a place to get it wrong.
const REGISTRY = new Map(AVATARS.map((a) => [a.id, a]));

export function registerAvatar(a) { if (a && a.id) REGISTRY.set(a.id, a); }
export function unregisterAvatar(id) { if (!PRESET_IDS.has(id)) REGISTRY.delete(id); }
export function avatarById(id) { return REGISTRY.get(id) || DEFAULT_AVATAR; }
export function allAvatars() { return [...REGISTRY.values()]; }
export function customAvatars() { return [...REGISTRY.values()].filter((a) => !PRESET_IDS.has(a.id)); }
export function featuresOf(avatar) { return { ...DEFAULT_FEATURES, ...((avatar && avatar.features) || {}) }; }
