// Custom stage backgrounds: drop an image in, and it is the sky.
//
// See assets/backgrounds/README.md for the whole workflow. The short version is that a file named
// after a stage id - assets/backgrounds/foundryfloor.png - is picked up with no code change at
// all, and this file exists only for the tuning you may or may not want afterwards.
//
// Everything here is deliberately failure-tolerant. A missing file, a corrupt file, a file the
// browser cannot decode: all of them fall back to the procedural sky, silently, because a stage
// that will not render is a much worse outcome than a stage with no photo on it.

import { STAGES } from './stages/index.js';

// Where the loader looks, and in what order. First hit wins.
export const BG_DIR = 'assets/backgrounds/';
export const BG_EXTENSIONS = ['png', 'jpg', 'jpeg', 'webp', 'gif'];

// OPTIONAL per-stage tuning. Add an entry only if the defaults are wrong for your image; a stage
// with no entry here still gets its background as long as the file is named correctly.
//
//   parallax  how much the image slides against the camera. 0 pins it to the screen, 0.5 makes it
//             feel close enough to be part of the stage. Default 0.12, which reads as far away.
//   fit       'cover' scales the image until it fills the screen, cropping the overflow - right
//             for a painted or photographic backdrop. 'tile' repeats it, for a seamless texture.
//   scenery   whether the game's own chimneys, towers and mesas still draw in front of your image.
//             Default false: a photograph with procedural silhouettes standing on it looks like a
//             mistake. Set true if your image is a plain sky you want the stage furniture on.
//   dim       0-1, how much to darken the image. Backdrops that look fine on their own often
//             swallow the fighters; this is the fastest fix. Default 0.
//   file      only needed if you want a name that is not the stage id.
export const BACKGROUNDS = {
  // FoundryFloor: { parallax: 0.18, fit: 'cover', scenery: false, dim: 0.25 },
};

const DEFAULTS = { parallax: 0.12, fit: 'cover', scenery: false, dim: 0 };

export function backgroundConfig(stageId) {
  const cfg = { ...DEFAULTS, ...(BACKGROUNDS[stageId] || {}) };
  cfg.parallax = Math.max(0, Math.min(1, +cfg.parallax || 0));
  cfg.dim = Math.max(0, Math.min(1, +cfg.dim || 0));
  if (cfg.fit !== 'tile') cfg.fit = 'cover';
  return cfg;
}

// The candidate URLs for a stage, in order. A stage id is matched case-insensitively, so
// FoundryFloor.png and foundryfloor.png both work - which matters, because the two obvious things
// to type are the stage id and its lowercase form.
export function backgroundCandidates(stageId) {
  const cfg = BACKGROUNDS[stageId] || {};
  if (cfg.file) return [BG_DIR + cfg.file];
  const names = [stageId, stageId.toLowerCase()];
  const out = [];
  for (const n of [...new Set(names)]) for (const ext of BG_EXTENSIONS) out.push(`${BG_DIR}${n}.${ext}`);
  return out;
}

export const STAGE_IDS = STAGES.map((s) => s.id);
