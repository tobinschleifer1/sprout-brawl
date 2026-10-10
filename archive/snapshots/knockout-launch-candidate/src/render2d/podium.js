// The results podium, as pure layout: where each placed fighter stands and where their stat card
// goes, for a W x H screen. Both builds draw from this - the web in ui/hud.js, Roblox in
// client/Podium.luau's twin, replayed by tests/podium-parity.luau - so a result looks the same on
// either. After the Brawlhalla end screen: fighters on stepped pillars in finishing order, left to
// right, winners celebrating and the rest hanging their heads, each over a card of their stats.

// What each card lists, in order: label and the results-row field it reads.
export const STATS = [
  ['Score', 'score'], ['KOs', 'kos'], ['Falls', 'falls'], ['Accidents', 'sds'],
  ['Dmg Done', 'damage'], ['Dmg Taken', 'taken'],
];

export function ordinal(n) {
  const t = n % 100;
  if (t >= 11 && t <= 13) return `${n}th`;
  const u = n % 10;
  return `${n}${u === 1 ? 'st' : u === 2 ? 'nd' : u === 3 ? 'rd' : 'th'}`;
}

// Place for each row, with ties sharing one: a team game's winners are all "1st", and in a free
// for all nobody else shares, because rows are already totally ordered by Match.finish.
export function places(rows, teams) {
  const out = [];
  for (let i = 0; i < rows.length; i++) {
    if (teams && i > 0 && rows[i].team === rows[i - 1].team) out.push(out[i - 1]);
    else out.push(i === 0 ? 1 : out[i - 1] + 1);
  }
  return out;
}

// Who won, in words. A team is named only when it is more than one fighter: rooms run every
// lobby match as teams, and a 1v1 announced as "Orange team wins" reads like the wrong result.
export function podiumTitle(rows, teams) {
  const w = rows[0];
  if (!w) return '';
  const mates = rows.filter((r) => r.team === w.team).length;
  if (teams && mates > 1) return `${w.team === 0 ? 'Green team' : 'Orange team'} wins`;
  return `${w.name} wins`;
}

// The card's number for a stat. Damage is shown whole, as the rest are counts.
export function statValue(row, field) {
  const v = row[field];
  return v == null ? 0 : Math.round(v);
}

export function podiumLayout(n, W, H) {
  const margin = W * 0.04;
  const colW = (W - margin * 2) / Math.max(1, n);
  // Each place a step lower than the last; the step shrinks with more players so eighth place still
  // stands on something.
  const step = n > 1 ? Math.min(H * 0.045, (H * 0.2) / (n - 1)) : 0;
  const figureH = Math.min(colW * 0.6, H * 0.24);
  const cardW = Math.min(colW * 0.9, H * 0.52);
  const slots = [];
  for (let i = 0; i < n; i++) {
    const cx = margin + colW * (i + 0.5);
    const top = H * 0.5 + step * i;
    const cardY = top + H * 0.06;
    slots.push({
      cx, top, colW, figureH,
      pillar: { x: cx - colW * 0.42, y: top, w: colW * 0.84, h: H - top },
      cap: { x: cx - colW * 0.46, y: top - H * 0.012, w: colW * 0.92, h: H * 0.024 },
      card: { x: cx - cardW / 2, y: cardY, w: cardW, h: Math.max(0, H - cardY - H * 0.03) },
      rowH: Math.max(0, H - cardY - H * 0.03) / (STATS.length + 2.2),
    });
  }
  return slots;
}
