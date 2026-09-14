// Player-made characters: validation, storage and registration.
//
// Everything a player can author arrives here as untrusted data. It comes out of localStorage,
// which anyone can edit by hand, and it goes straight into the renderer's paint path and the HUD -
// so nothing in this file trusts a single field. `sanitize` REBUILDS an avatar out of known-good
// values rather than checking the incoming one for problems: an unknown feature becomes the
// default, a colour that is not #rrggbb becomes the default, a name that is four thousand
// characters of markup becomes eighteen characters of plain text. A corrupt save degrades into a
// plain character instead of throwing on frame one of a match, which is the only failure mode that
// really matters here - nobody should lose a match because their saved hat did not parse.
//
// Storage is injected rather than reached for, so the tests drive the real code with a fake store
// instead of needing a browser.

import { FEATURES, FEATURE_KEYS, DEFAULT_FEATURES, PALETTE_KEYS, DEFAULT_AVATAR, PRESET_IDS,
  registerAvatar, unregisterAvatar } from './avatars.js';
import { SAVE_KEY } from './branding.js';

export const STORE_KEY = SAVE_KEY + '-avatars';
export const MAX_CUSTOM = 24;          // a full grid, and a ceiling on what a loop can write
export const MAX_NAME = 18;

const HEX = /^#[0-9a-fA-F]{6}$/;
const ID_OK = /^custom:[a-z0-9]{1,24}$/i;
// Names keep letters, digits, spaces and a little punctuation. Everything else goes, which covers
// angle brackets and quotes without this file needing to know where the name will be rendered.
const NAME_OK = /[^A-Za-z0-9 ._-]/g;
const ALLOWED = Object.fromEntries(FEATURE_KEYS.map((k) => [k, new Set(FEATURES[k].map((o) => o.id))]));

// localStorage that cannot throw. Private-mode Safari throws on setItem when the quota is zero,
// and a save button that explodes is worse than one that quietly does not persist.
export function browserStore() {
  return {
    get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); return true; } catch (e) { return false; } },
  };
}

export const newId = () => 'custom:' + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36).padStart(2, '0');

function cleanName(raw, fallback) {
  const s = String(raw == null ? '' : raw).replace(NAME_OK, '').replace(/\s+/g, ' ').trim();
  return s ? s.slice(0, MAX_NAME) : fallback;
}

// Build a valid avatar out of whatever turned up. Never throws, never returns null.
export function sanitize(raw, index) {
  const i = index || 0;
  const src = (raw && typeof raw === 'object') ? raw : {};
  const id = (typeof src.id === 'string' && ID_OK.test(src.id) && !PRESET_IDS.has(src.id)) ? src.id : newId();
  const palette = {};
  for (const k of PALETTE_KEYS) {
    const v = src.palette && src.palette[k];
    palette[k] = (typeof v === 'string' && HEX.test(v)) ? v.toLowerCase() : DEFAULT_AVATAR.palette[k];
  }
  const features = {};
  for (const k of FEATURE_KEYS) {
    const v = src.features && src.features[k];
    features[k] = (typeof v === 'string' && ALLOWED[k].has(v)) ? v : DEFAULT_FEATURES[k];
  }
  return { id, name: cleanName(src.name, 'Fighter ' + (i + 1)), rig: 'avatar', custom: true, palette, features };
}

export function blankAvatar(index) {
  return sanitize({ name: 'Fighter ' + ((index || 0) + 1), palette: { ...DEFAULT_AVATAR.palette }, features: { ...DEFAULT_FEATURES } }, index);
}

// ------------------------------------------------------------------------------ storage -----

export function readCustom(store) {
  let parsed = null;
  try { parsed = JSON.parse(store.get(STORE_KEY) || 'null'); } catch (e) { parsed = null; }
  const list = Array.isArray(parsed) ? parsed : [];
  const out = [], seen = new Set();
  for (const raw of list.slice(0, MAX_CUSTOM)) {
    const a = sanitize(raw, out.length);
    // A duplicate id would make one character unreachable and the other unsaveable, so the second
    // is re-issued rather than dropped: the player keeps the character they made.
    if (seen.has(a.id)) a.id = newId();
    seen.add(a.id);
    out.push(a);
  }
  return out;
}

export function writeCustom(list, store) {
  const clean = list.slice(0, MAX_CUSTOM).map((a, i) => sanitize(a, i));
  return store.set(STORE_KEY, JSON.stringify(clean));
}

// Load from storage and put them in the avatar registry, so `avatarById` resolves a player's
// character exactly the way it resolves a preset.
export function initCustomAvatars(store) {
  const st = store || browserStore();
  const list = readCustom(st);
  for (const a of list) registerAvatar(a);
  return list;
}

export function saveAvatar(avatar, store) {
  const st = store || browserStore();
  const list = readCustom(st);
  const clean = sanitize(avatar, list.length);
  const at = list.findIndex((a) => a.id === clean.id);
  if (at >= 0) list[at] = clean;
  else if (list.length >= MAX_CUSTOM) return { ok: false, reason: 'You can keep ' + MAX_CUSTOM + ' characters. Delete one first.', list };
  else list.push(clean);
  const ok = writeCustom(list, st);
  registerAvatar(clean);      // usable in a match right now, saved or not
  return { ok, reason: ok ? null : 'This browser would not let the game save. The character works until you reload.', avatar: clean, list };
}

export function deleteAvatar(id, store) {
  const st = store || browserStore();
  const list = readCustom(st).filter((a) => a.id !== id);
  writeCustom(list, st);
  unregisterAvatar(id);
  return list;
}

export function duplicateAvatar(avatar, store) {
  const copy = sanitize({ ...avatar, id: undefined, name: cleanName(avatar.name, 'Fighter').slice(0, MAX_NAME - 5) + ' copy' });
  return saveAvatar(copy, store);
}

// A character the player is about to lose is worth one more chance: export hands them the text,
// import takes it back. It is also the only way a character moves between two browsers.
export function exportAvatars(list) { return JSON.stringify(list.map((a, i) => sanitize(a, i)), null, 2); }

export function importAvatars(text, store) {
  const st = store || browserStore();
  let parsed = null;
  try { parsed = JSON.parse(text); } catch (e) { return { ok: false, reason: 'That is not valid character data.' }; }
  const incoming = (Array.isArray(parsed) ? parsed : [parsed]).filter((x) => x && typeof x === 'object');
  if (!incoming.length) return { ok: false, reason: 'No characters in that data.' };
  const list = readCustom(st);
  let added = 0;
  for (const raw of incoming) {
    if (list.length >= MAX_CUSTOM) break;
    // Imported characters always take a NEW id. Pasting your own export back in should give you
    // copies, not silently overwrite the characters you already have.
    const a = sanitize({ ...raw, id: undefined }, list.length);
    list.push(a); registerAvatar(a); added++;
  }
  writeCustom(list, st);
  return { ok: added > 0, added, skipped: incoming.length - added, list,
    reason: added ? null : 'No room: you already have ' + MAX_CUSTOM + ' characters.' };
}

// ------------------------------------------------------------------------- readability -----
// A character the player cannot see in a match is a bad character, however good it looks against
// the editor's dark background. This is ADVICE: it is shown as a hint and never blocks a save,
// because a player who wants an all-black ninja is allowed to have one.

const lum = (h) => {
  const v = [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255)
    .map((c) => (c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)));
  return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2];
};
export const contrast = (a, b) => { const l1 = lum(a), l2 = lum(b); return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05); };

export function readabilityWarning(avatar) {
  const p = avatar.palette;
  // Against the lightest and the darkest sky in the game, and against its own torso.
  const worstSky = Math.min(contrast(p.primary, '#f6e8ce'), contrast(p.primary, '#1e2430'));
  if (worstSky < 1.3) return 'This head colour washes out against some stages. Try going lighter or darker.';
  if (contrast(p.primary, p.secondary) < 1.25) return 'Head and torso are nearly the same value, so the silhouette reads flat.';
  return null;
}
