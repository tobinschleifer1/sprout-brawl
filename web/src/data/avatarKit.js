// The character kit: a fighter assembled from ready-made pixel parts.
//
// A kit character is a LIST OF CHOICES, not a picture: one option from each part category (build,
// head, eyes, hair, top, shoes...) and one swatch from each colour slot (skin, hair, top...). The
// picture is composed from those choices on the client (render2d/avatarCompose.js, ported as
// AvatarCompose.luau), which is why a character is a 27-character code instead of a bitmap, and why
// every player in a match can see everyone else's character without an image ever being uploaded.
//
// Still cosmetic only, for the reason at the top of avatars.js: a kit code resolves to an avatar
// with no stats in it, and buildLoadout reads stats from the weapon alone.
//
// THE CODE. 'k1' then one base-36 digit per part category, in KIT_CATEGORIES order, then one per
// colour slot, in KIT_COLOURS order. The code IS the avatar id: it travels through the room, the
// roster, the hub presence and the saved profile exactly where a preset id like 'Classic' does, so
// none of those paths had to learn that player-made characters exist. The order of both lists is
// therefore PERMANENT - add new categories and options at the end, never reorder or remove, or every
// saved character changes.
//
// Every option in the catalogue is drawn by the composer; test/avatar-kit.test.mjs fails if an
// option paints nothing different from its neighbours, the same dead-data rule as the old features.

import { CATEGORIES, PARTS, ROLES, FIXED, COLOURS, PRESETS } from './avatarParts.js';

export const KIT_VERSION = 'k1';
export const KIT_PARTS = PARTS;
export const KIT_ROLES = ROLES;
export const KIT_FIXED = FIXED;
export const KIT_CATEGORIES = CATEGORIES;
export const KIT_COLOURS = COLOURS;
export const KIT_PRESETS = PRESETS;
export const OUTLINE = '#120E16';

const DIGITS = '0123456789abcdefghijklmnopqrstuvwxyz';
export const CODE_LENGTH = KIT_VERSION.length + CATEGORIES.length + COLOURS.length;

export const DEFAULT_KIT = {
  parts: Object.fromEntries(CATEGORIES.map((c) => [c.id, c.options[c.fallback || 0].id])),
  colours: Object.fromEntries(COLOURS.map((c) => [c.id, c.fallback || 0])),
};

export const isKitCode = (s) => typeof s === 'string' && s.startsWith(KIT_VERSION) && s.length <= 64;

// Rebuild a spec out of known-good values. Unknown options fall back to the category default and
// out-of-range colours to the slot default, the same "degrade, never throw" contract as sanitize()
// in customAvatars.js: this feeds the renderer on every client in the match.
export function sanitizeKit(raw) {
  const src = raw && typeof raw === 'object' ? raw : {};
  const parts = {}, colours = {};
  for (const c of CATEGORIES) {
    const v = src.parts && src.parts[c.id];
    parts[c.id] = c.options.some((o) => o.id === v) ? v : DEFAULT_KIT.parts[c.id];
  }
  for (const c of COLOURS) {
    const v = src.colours && src.colours[c.id];
    colours[c.id] = (Number.isInteger(v) && v >= 0 && v < c.list.length) ? v : DEFAULT_KIT.colours[c.id];
  }
  return { parts, colours };
}

export function encodeKit(raw) {
  const spec = sanitizeKit(raw);
  let out = KIT_VERSION;
  for (const c of CATEGORIES) out += DIGITS[c.options.findIndex((o) => o.id === spec.parts[c.id])];
  for (const c of COLOURS) out += DIGITS[spec.colours[c.id]];
  return out;
}

// Anything that is not a kit code is null; a kit code with bad digits decodes with those choices
// defaulted. A short code (from an older version with fewer categories) keeps its choices and
// defaults the rest - which is what makes adding a category at the end safe.
export function decodeKit(code) {
  if (!isKitCode(code)) return null;
  const body = code.slice(KIT_VERSION.length).toLowerCase();
  const parts = {}, colours = {};
  // A missing digit is -1, not indexOf('') - which is 0 and would silently pick the first option.
  const digit = (k) => (k < body.length ? DIGITS.indexOf(body[k]) : -1);
  CATEGORIES.forEach((c, i) => {
    const d = digit(i);
    parts[c.id] = d >= 0 && d < c.options.length ? c.options[d].id : DEFAULT_KIT.parts[c.id];
  });
  COLOURS.forEach((c, i) => {
    const d = digit(CATEGORIES.length + i);
    colours[c.id] = d >= 0 && d < c.list.length ? d : DEFAULT_KIT.colours[c.id];
  });
  return { parts, colours };
}

export const canonicalKit = (code) => (isKitCode(code) ? encodeKit(decodeKit(code)) : null);

// The five-colour palette the rest of the game still reads off an avatar: smear ghosts, the dirt a
// hauled weapon kicks up, and anything else drawn in "the fighter's colours".
export function kitPalette(spec) {
  const pick = (slot) => COLOURS.find((c) => c.id === slot).list[spec.colours[slot]];
  return { primary: pick('top'), secondary: pick('trim'), tertiary: pick('bottom'), accent: pick('skin'), glow: pick('accessory') };
}

// A kit code as an avatar, in the same shape as a preset, so avatarById can hand it out.
export function kitAvatar(code) {
  const canon = canonicalKit(code);
  if (!canon) return null;
  const kit = decodeKit(canon);
  return { id: canon, name: 'Custom', rig: 'avatar', custom: true, kit, palette: kitPalette(kit) };
}

// How many different characters the parts alone make, before a single colour is changed.
// A preset's full spec: its own choices over the defaults.
export const presetKit = (p) => sanitizeKit({ parts: { ...DEFAULT_KIT.parts, ...p.parts }, colours: { ...DEFAULT_KIT.colours, ...p.colours } });

export const partCombinations = () => CATEGORIES.reduce((n, c) => n * c.options.length, 1);
export const colourCombinations = () => COLOURS.reduce((n, c) => n * c.list.length, 1);
