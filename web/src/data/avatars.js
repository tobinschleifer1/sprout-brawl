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

import { isKitCode, kitAvatar, encodeKit, presetKit, kitPalette } from './avatarKit.js';

// The six presets are KIT characters under their old ids (docs/briefs/character-rework-plan.md,
// phase 1): every save, room, roster and test that says 'Classic' still resolves, and draws the kit's
// richer parts in the preset's own colours and signature. Their legacy `features` stay as the
// starting point the original creator (customAvatars.js, still the hand-drawing mode) copies from;
// nothing draws them. Designed by GPT from the kit catalogue, checked against it part by part; then
// compared with the old drawings side by side, and four colours moved closer to the old identity
// (Ember's coral and Vapor's lavender heads - the kit has no orange or pink skin - Moss's hood
// lifted off its face, Steel's cap grey).
const LOOKS = {
  Classic: { parts: {'head': 'block', 'ears': 'none', 'eyes': 'dot', 'brows': 'none', 'nose': 'none', 'hair': 'bald', 'top': 'jersey', 'bottom': 'jeans', 'shoes': 'sneakers'},
    colours: {'skin': 12, 'hair': 0, 'eyes': 1, 'top': 14, 'trim': 0, 'bottom': 23, 'shoes': 23, 'accessory': 14} },
  Noir: { parts: {'head': 'block', 'ears': 'none', 'brows': 'none', 'nose': 'none', 'mouth': 'neutral', 'hair': 'bald', 'eyewear': 'shades', 'top': 'suit', 'bottom': 'slacks', 'shoes': 'dress'},
    colours: {'skin': 16, 'hair': 0, 'eyes': 1, 'top': 4, 'trim': 0, 'bottom': 3, 'shoes': 4, 'accessory': 18} },
  Ember: { parts: {'head': 'round', 'eyes': 'round', 'brows': 'angry', 'nose': 'none', 'mouth': 'smirk', 'hair': 'bald', 'top': 'leather', 'bottom': 'ripped', 'shoes': 'combat', 'headwear': 'horns'},
    colours: {'skin': 17, 'hair': 4, 'eyes': 1, 'top': 6, 'trim': 0, 'bottom': 20, 'shoes': 20, 'accessory': 7} },
  Moss: { parts: {'build': 'stocky', 'head': 'wide', 'eyes': 'round', 'brows': 'none', 'nose': 'none', 'mouth': 'smile', 'hair': 'bald', 'top': 'hoodie', 'bottom': 'cargo', 'shoes': 'boots', 'headwear': 'hood'},
    colours: {'skin': 13, 'hair': 13, 'eyes': 1, 'top': 12, 'trim': 0, 'bottom': 12, 'shoes': 12, 'accessory': 11} },
  Vapor: { parts: {'build': 'slim', 'head': 'long', 'brows': 'none', 'nose': 'none', 'hair': 'bald', 'eyewear': 'visor', 'headwear': 'antenna', 'top': 'bomber', 'bottom': 'leggings', 'shoes': 'hightops'},
    colours: {'skin': 15, 'hair': 14, 'eyes': 9, 'top': 17, 'trim': 0, 'bottom': 16, 'shoes': 16, 'accessory': 19} },
  Steel: { parts: {'build': 'broad', 'head': 'block', 'brows': 'none', 'nose': 'none', 'hair': 'bald', 'eyewear': 'goggles', 'headwear': 'cap', 'top': 'bomber', 'bottom': 'cargo', 'shoes': 'combat', 'gloves': 'gauntlets'},
    colours: {'skin': 16, 'hair': 9, 'eyes': 9, 'top': 2, 'trim': 0, 'bottom': 3, 'shoes': 3, 'accessory': 3} },
};
// A preset: its legacy entry, plus the kit it is drawn as. `code` is what the renderers draw; the id
// stays the preset's name, so it is still a preset everywhere ids travel.
const kitPreset = (legacy) => {
  const kit = presetKit(LOOKS[legacy.id]);
  return { ...legacy, kit, code: encodeKit(kit), palette: kitPalette(kit) };
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
].map(kitPreset);

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
// A kit code (avatarKit.js) is resolved on demand rather than registered: it is its own complete
// description, and every client in a match has to be able to draw a character it has never seen.
const KITS = new Map();
export function avatarById(id) {
  const hit = REGISTRY.get(id);
  if (hit) return hit;
  if (isKitCode(id)) {
    if (!KITS.has(id)) KITS.set(id, kitAvatar(id));
    return KITS.get(id) || DEFAULT_AVATAR;
  }
  return DEFAULT_AVATAR;
}
export function allAvatars() { return [...REGISTRY.values()]; }
// The kit code an avatar id is drawn as - a preset's, or a kit code itself - or null for a legacy
// custom character, which the original creator's rig draws.
export function kitCodeOf(id) { const a = avatarById(id); return a && a.kit ? a.code : null; }
export function customAvatars() { return [...REGISTRY.values()].filter((a) => !PRESET_IDS.has(a.id)); }
export function featuresOf(avatar) { return { ...DEFAULT_FEATURES, ...((avatar && avatar.features) || {}) }; }
