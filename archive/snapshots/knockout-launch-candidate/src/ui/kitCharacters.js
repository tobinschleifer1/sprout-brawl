// Browser-only character slots. A code remains the avatar id; names and the wearing choice are
// local presentation data. No old custom avatar storage is touched.
import { browserStore } from '../data/customAvatars.js';
import { registerAvatar, unregisterAvatar } from '../data/avatars.js';
import { DEFAULT_KIT, KIT_CATEGORIES, KIT_COLOURS, canonicalKit, decodeKit, encodeKit,
  kitAvatar, kitUnlocks, sanitizeKit } from '../data/avatarKit.js';
import { SAVE_KEY } from '../data/branding.js';

export const KIT_STORE_KEY = SAVE_KEY + '-kit-characters';
export const MAX_KIT_CHARACTERS = 8;
const starter = () => ({ name: 'Fighter 1', code: encodeKit(DEFAULT_KIT) });

export function cleanKitName(raw, fallback = 'Fighter') {
  const s = String(raw ?? '').replace(/[^A-Za-z0-9 ._'-]/g, '').replace(/\s+/g, ' ').trim();
  return (s || fallback).slice(0, 20);
}

// The shared codec intentionally accepts earned options so Roblox can display their owners.
// The web has no earning path, so clean them at this storage and UI boundary.
export function webKitCode(raw) {
  const spec = decodeKit(canonicalKit(raw));
  if (!spec) return encodeKit(DEFAULT_KIT);
  for (const c of KIT_CATEGORIES) {
    const picked = c.options.find((o) => o.id === spec.parts[c.id]);
    if (picked?.unlock) spec.parts[c.id] = DEFAULT_KIT.parts[c.id];
  }
  return encodeKit(spec);
}

export function readKitCharacters(store = browserStore()) {
  let raw;
  try { raw = JSON.parse(store.get(KIT_STORE_KEY) || 'null'); } catch { raw = null; }
  const rows = Array.isArray(raw?.characters) ? raw.characters : [];
  const characters = [], seen = new Set();
  for (const row of rows.slice(0, MAX_KIT_CHARACTERS)) {
    const code = webKitCode(row?.code);
    if (seen.has(code)) continue;
    seen.add(code);
    characters.push({ name: cleanKitName(row?.name, `Fighter ${characters.length + 1}`), code });
  }
  if (!characters.length) characters.push(starter());
  const wearing = characters.some((a) => a.code === raw?.wearing) ? raw.wearing : characters[0].code;
  return { characters, wearing };
}

export function writeKitCharacters(roster, store = browserStore()) {
  const clean = readKitCharacters({ get: () => JSON.stringify(roster) });
  try { return !!store.set(KIT_STORE_KEY, JSON.stringify(clean)); } catch { return false; }
}

export function registerKitCharacters(roster) {
  for (const a of roster.characters) registerAvatar({ ...kitAvatar(a.code), name: a.name });
}

export function saveKitCharacter(roster, name, rawCode, originalCode = null, asNew = false) {
  const code = webKitCode(rawCode);
  const characters = roster.characters.map((a) => ({ ...a }));
  const existing = characters.findIndex((a) => a.code === originalCode);
  const duplicate = characters.findIndex((a) => a.code === code && (asNew || a.code !== originalCode));
  if (duplicate >= 0) return { ok: false, reason: 'That look is already saved.' };
  if (asNew || existing < 0) {
    if (characters.length >= MAX_KIT_CHARACTERS) return { ok: false, reason: 'All 8 character slots are full.' };
    characters.push({ name: cleanKitName(name, `Fighter ${characters.length + 1}`), code });
  } else characters[existing] = { name: cleanKitName(name, characters[existing].name), code };
  const wearing = roster.wearing === originalCode ? code : roster.wearing;
  return { ok: true, roster: { characters, wearing }, code };
}

export function deleteKitCharacter(roster, code) {
  if (roster.characters.length <= 1) return { ok: false, reason: 'Keep at least one character.' };
  const characters = roster.characters.filter((a) => a.code !== code);
  return { ok: true, roster: { characters, wearing: roster.wearing === code ? characters[0].code : roster.wearing } };
}

export class KitDraft {
  constructor(code = encodeKit(DEFAULT_KIT)) {
    this.code = webKitCode(code);
    this.undoStack = []; this.redoStack = []; this.locks = new Set();
  }
  change(mutator) {
    const spec = sanitizeKit(decodeKit(this.code));
    mutator(spec);
    const next = webKitCode(encodeKit(spec));
    if (next === this.code) return false;
    this.undoStack.push(this.code);
    if (this.undoStack.length > 60) this.undoStack.shift();
    this.redoStack.length = 0;
    this.code = next;
    return true;
  }
  part(id, option) {
    const cat = KIT_CATEGORIES.find((c) => c.id === id);
    const opt = cat?.options.find((o) => o.id === option && !o.unlock);
    return opt ? this.change((s) => { s.parts[id] = option; }) : false;
  }
  colour(id, index) {
    const slot = KIT_COLOURS.find((c) => c.id === id);
    return slot && Number.isInteger(index) && index >= 0 && index < slot.list.length
      ? this.change((s) => { s.colours[id] = index; }) : false;
  }
  randomPart(id, rng = Math.random) {
    const cat = KIT_CATEGORIES.find((c) => c.id === id);
    if (!cat) return false;
    const current = decodeKit(this.code).parts[id];
    const pool = cat.options.filter((o) => !o.unlock && o.id !== current);
    return pool.length ? this.part(id, pool[Math.floor(rng() * pool.length)].id) : false;
  }
  randomise(rng = Math.random) {
    return this.change((s) => {
      for (const cat of KIT_CATEGORIES) {
        if (this.locks.has(cat.id)) continue;
        const pool = cat.options.filter((o) => !o.unlock);
        s.parts[cat.id] = pool[Math.floor(rng() * pool.length)].id;
      }
      for (const slot of KIT_COLOURS) {
        if (KIT_CATEGORIES.some((c) => c.paint.includes(slot.id) && !this.locks.has(c.id)))
          s.colours[slot.id] = Math.floor(rng() * slot.list.length);
      }
    });
  }
  undo() { if (!this.undoStack.length) return false; this.redoStack.push(this.code); this.code = this.undoStack.pop(); return true; }
  redo() { if (!this.redoStack.length) return false; this.undoStack.push(this.code); this.code = this.redoStack.pop(); return true; }
  unlocked() { return kitUnlocks(decodeKit(this.code)).length === 0; }
}
