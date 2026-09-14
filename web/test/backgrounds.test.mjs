// Whatever is sitting in assets/backgrounds/ right now.
//
// This suite is unusual: it tests the PLAYER'S files, not the project's. It passes on a clean
// checkout with nothing in the folder, and starts having something to say the moment somebody
// drops an image in. That is the point - the failure modes of "put a file here" are all naming and
// format problems, and every one of them is silent in a browser, which just quietly falls back to
// the painted sky and tells you nothing.
//
// See assets/backgrounds/README.md.
import { readdirSync, statSync, openSync, readSync, closeSync, existsSync } from 'node:fs';
import { STAGES } from '../src/data/stages/index.js';
import { BG_DIR, BG_EXTENSIONS, BACKGROUNDS, backgroundConfig, backgroundCandidates } from '../src/data/backgrounds.js';

let pass = 0, fail = 0;
const check = (n, c, d) => { (c ? pass++ : fail++); console.log(`${c ? 'PASS' : 'FAIL'}  ${n}\n      ${d}`); };

const dir = new URL('../assets/backgrounds/', import.meta.url);
const dirPath = dir.pathname.replace(/%20/g, ' ');
const files = existsSync(dirPath)
  ? readdirSync(dirPath).filter((f) => !f.startsWith('.') && f.toLowerCase() !== 'readme.md')
  : [];

// What the first bytes of a file say it really is. The extension is a claim; this is the fact.
// A .webp renamed to .png is the single most common way a downloaded image fails to load, and it
// is completely invisible until a browser refuses it.
function sniff(path) {
  const fd = openSync(path, 'r');
  const buf = Buffer.alloc(16);
  const n = readSync(fd, buf, 0, 16, 0);
  closeSync(fd);
  if (n >= 8 && buf.slice(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'png';
  if (n >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'jpg';
  if (n >= 12 && buf.slice(0, 4).toString('ascii') === 'RIFF' && buf.slice(8, 12).toString('ascii') === 'WEBP') return 'webp';
  if (n >= 6 && buf.slice(0, 6).toString('ascii').startsWith('GIF8')) return 'gif';
  return null;
}
const SAME = { jpeg: 'jpg' };

const ids = STAGES.map((s) => s.id);
const lower = new Map(ids.map((id) => [id.toLowerCase(), id]));
const named = new Set(Object.values(BACKGROUNDS).map((c) => c && c.file).filter(Boolean));

// ---- 1. every file in the folder is named after a stage the game has ----
{
  const strays = [];
  for (const f of files) {
    if (named.has(f)) continue;                       // pointed at explicitly by backgrounds.js
    const dot = f.lastIndexOf('.');
    const base = dot > 0 ? f.slice(0, dot) : f;
    if (!lower.has(base.toLowerCase())) strays.push(f);
  }
  check('every background file is named after a real stage', strays.length === 0,
    strays.length ? `${strays.join(', ')} — no stage has that id, so the game will never look for it. Stage ids: ${ids.join(', ')}`
      : files.length ? `${files.length} file${files.length === 1 ? '' : 's'}, all matching a stage: ${files.join(', ')}`
        : `nothing in ${BG_DIR} yet — add an image named after a stage id and it becomes that stage's sky`);
}

// ---- 2. every file is the format its extension claims ----
{
  const wrong = [], unreadable = [];
  for (const f of files) {
    const ext = (f.split('.').pop() || '').toLowerCase();
    if (!BG_EXTENSIONS.includes(ext)) { wrong.push(`${f}: .${ext} is not a format the loader tries (${BG_EXTENSIONS.join(', ')})`); continue; }
    const real = sniff(dirPath + f);
    if (!real) { unreadable.push(`${f} is not an image at all`); continue; }
    if (real !== (SAME[ext] || ext)) wrong.push(`${f} is really a ${real}, renaming it will not make a browser read it as ${ext}`);
  }
  const bad = wrong.concat(unreadable);
  check('every background file really is the format its name claims', bad.length === 0,
    bad.length ? bad.join('; ')
      : files.length ? `${files.length} checked by file signature, not by extension` : 'no files to check');
}

// ---- 3. nothing is big enough to stall the first frame ----
{
  const MAX_MB = 8;
  const heavy = files.map((f) => [f, statSync(dirPath + f).size]).filter(([, n]) => n > MAX_MB * 1024 * 1024);
  const sizes = files.map((f) => `${f} ${(statSync(dirPath + f).size / 1024).toFixed(0)}KB`);
  check('no background is heavy enough to hold up the first frame', heavy.length === 0,
    heavy.length ? heavy.map(([f, n]) => `${f} is ${(n / 1048576).toFixed(1)}MB, over the ${MAX_MB}MB guide`).join('; ')
      : sizes.length ? sizes.join(', ') : 'no files to check');
}

// ---- 4. every tuning entry points at a stage, and its values are usable ----
// A typo'd key here is silent: the stage keeps its defaults and nothing says why.
{
  const bad = [];
  for (const [id, cfg] of Object.entries(BACKGROUNDS)) {
    if (!ids.includes(id)) { bad.push(`BACKGROUNDS.${id} is not a stage id`); continue; }
    const c = backgroundConfig(id);
    if (cfg.parallax != null && c.parallax !== Math.max(0, Math.min(1, +cfg.parallax))) bad.push(`${id}: parallax ${cfg.parallax} is out of 0-1`);
    if (cfg.dim != null && c.dim !== Math.max(0, Math.min(1, +cfg.dim))) bad.push(`${id}: dim ${cfg.dim} is out of 0-1`);
    if (cfg.fit && cfg.fit !== 'cover' && cfg.fit !== 'tile') bad.push(`${id}: fit "${cfg.fit}" is not cover or tile`);
    if (cfg.file && !files.includes(cfg.file)) bad.push(`${id}: file "${cfg.file}" is not in ${BG_DIR}`);
  }
  const n = Object.keys(BACKGROUNDS).length;
  check('every tuning entry names a real stage and real settings', bad.length === 0,
    bad.length ? bad.join('; ') : n ? `${n} tuned: ${Object.keys(BACKGROUNDS).join(', ')}` : 'no per-stage tuning, every stage on defaults');
}

// ---- 5. the loader would actually find what is here ----
// The end-to-end claim the README makes: drop a correctly named file in and the game picks it up.
{
  const missed = [];
  for (const f of files) {
    if (named.has(f)) continue;
    const base = f.slice(0, f.lastIndexOf('.'));
    const id = lower.get(base.toLowerCase());
    if (!id) continue;                                 // already reported by check 1
    if (!backgroundCandidates(id).includes(BG_DIR + f)) missed.push(`${f} is named for ${id} but the loader never asks for it`);
  }
  const found = files.filter((f) => !named.has(f) && lower.has(f.slice(0, f.lastIndexOf('.')).toLowerCase()));
  check('the loader asks for every file that is here', missed.length === 0,
    missed.length ? missed.join('; ')
      : found.length ? `${found.map((f) => f + ' -> ' + lower.get(f.slice(0, f.lastIndexOf('.')).toLowerCase())).join(', ')}`
        : 'nothing to load yet');
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
