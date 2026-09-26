// The battle builder's rules: what a match can be set to, and the presets that set everything at
// once - after Brawlhalla's custom rooms, whose lobby offers a Tournament 1v1 preset beside the
// individual settings. Pure data, generated into roblox/src/shared/Data/Rules.luau, so the web
// setup screen and a Roblox room offer the same choices under the same names.

export const RULES = {
  // Stock: lives run out. Timed: the clock runs out and the most KOs wins.
  modes: [
    { id: 'stock', name: 'Stock', hint: 'Last one with lives left wins.' },
    { id: 'timed', name: 'Timed', hint: 'Most KOs when the clock runs out.' },
  ],
  stocks: [1, 2, 3, 4, 5],
  times: [120, 180, 240, 300],
  disasters: ['off', 'stage', 'chaos'],
  mapChoices: ['host', 'vote', 'random'],
  mapSets: ['all', 'ranked'],
  presets: [
    { id: 'tournament', name: 'Tournament 1v1', hint: '3 lives, no items or disasters, ranked maps by vote.',
      rules: { mode: 'stock', stocks: 3, time: 180, items: false, disasters: 'off', mapChoice: 'vote', mapSet: 'ranked' } },
    { id: 'casual', name: 'Casual', hint: '3 lives, items on, each map brings its own disaster.',
      rules: { mode: 'stock', stocks: 3, time: 180, items: true, disasters: 'stage', mapChoice: 'host', mapSet: 'all' } },
    { id: 'chaos', name: 'Chaos', hint: 'Three minutes on the clock, every disaster, a random map.',
      rules: { mode: 'timed', stocks: 3, time: 180, items: true, disasters: 'chaos', mapChoice: 'random', mapSet: 'all' } },
  ],
};

// The engine's mode id for a rules mode, free-for-all or teams.
export function engineMode(mode, teams) {
  return (mode === 'timed' ? 'Timed' : 'Stock') + (teams ? 'Teams' : 'FFA');
}
