// The big words in the middle of the screen: what each is and how long it holds. Both builds
// read this (generated into roblox/src/shared/Data/Callouts.luau), so a KO or the start of sudden
// death is announced the same way everywhere; the Roblox HUD used to know only the countdown.
import { GO_CALL } from './branding.js';

export const CALLOUTS = {
  count: { ms: 700, colour: '#FFFFFF' },
  go: { text: GO_CALL, ms: 900, colour: '#FFD58A' },
  stage: { ms: 1600, colour: '#E9E5DB' },
  ko: { text: 'KO!', ms: 1100, colour: '#FFFFFF' },
  suddendeath: { text: 'SUDDEN DEATH', ms: 1600, colour: '#E8622A' },
  shrink: { text: 'Closing in', ms: 800, colour: '#E8622A' },
  game: { text: 'GAME!', ms: 1800, colour: '#FFD58A' },
};
