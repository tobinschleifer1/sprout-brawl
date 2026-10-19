# UI arcade, round 3: reviews (2026-10-19)

Two independent reviewers, as the earlier UI rounds used.

**Claude: 5.9** (faithful 6.5 · fits 6.0 · readability 6.0 · consistency 5.5 · hierarchy 5.0)
**Codex (GPT-6-Astra): 6.2** (faithful 6.5 · fits 6.5 · readability 6.0 · consistency 6.5 · hierarchy 5.5)

Both: "getting better, not good enough". Three rounds without reaching 8: per README, carry on.

Found by both:
- HUD: Hud.luau wrote BackgroundTransparency 0.08 every frame, undoing the opaque card (percents
  4.21-4.47:1); the new test checked against an opaque card, so passed while the game failed.
- Studio: the larger pixel title runs under the saved-character chips (fixed offset 250).
- Shop on phone: passes 99 px wide - VIP's perks wrap to 26 lines over its title, price and
  neighbours; BUY SINGLY wider than its pill.
- Select: status bands bare white (3.58/4.30:1); the fighter's sword over the roster.
- Climb: pixel title at 10.7 px. render-select.luau still drew 0 px outlines.
- Plaza: icon buttons in a bottom row beside wide text buttons (two languages); icons ~46% of the face.
- Locker cards still dense. No pattern, no stepped motifs.

Claude only: Workshop CRAFT covers the rarity and price on every card (a regression); error notice
title outlined in blue on red; People status 3.51/4.34; three close-button styles; Nunito Sans (Builder
Sans' stand-in) missing from the render font import, so body text drew as Arial Black; Fredoka wrapped
at 0.50 where Studio measures 0.55; plaza phone hint has no padding; dead space in Crates, Records.
