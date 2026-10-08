# Combat: readable, deeper, fought together

The whole combat pass, agreed 2026-10-09. It comes before the rest of the earlier plan (new weapons,
KO effects and emotes, progression), which waits until this is done.

## What the user asked for

- Every problem is real: fights are **hard to read**, **too shallow**, **teams feel solo**, and the
  **online feel** is off (hits land late or differently from what was on screen).
- "Fighting together" means **team mechanics**, **crowded fights** (3-6 fighters) and the
  **multiplayer feel**. Not friendly fire.
- Audience: **easy to pick up, deep for those who look** (Brawlhalla, not Smash's skill floor).
- **Teams:** save a launched ally, team combos, team throws.
- **Gang-ups are allowed:** two on one is a real tactic. Credit KO assists and keep it readable;
  no protection mechanic.
- **Netcode:** go as far as lag compensation (the server judges your hit against where you saw
  your foe).
- **Mechanics:** bounces and armour, plus whatever else I recommend.
- Order: **read, then depth, then team, then net**. One phase at a time, both builds each time.

## Phases

1. **Readability.** Who is who in a crowd, what is coming (heavy and signature startups), how hard
   a hit was, who is in danger (kill percent), and who got the KO and the assist.
2. **Depth.** Wall and ceiling bounces for a launched fighter (techable), armour that heavy moves
   can push through light hits with, clashes (two attacks meeting cancel out), and stale moves
   (a move repeated loses power) so mashing one button stops working.
3. **Team play.** Save a launched ally by touching them, team combos (a combo carried on by an ally
   counts for both, with an assist), team throws (grab an ally and throw them at a foe), and KO
   assist credit in every mode.
4. **Online feel.** Instant local feedback when your attack visibly connects (confirmed or taken
   back by the server), then lag compensation on the server for your hits.

Each phase lands in `web/` and `roblox/` together, held by `check.sh` replay, with every test
mutation-checked, and a Studio playtest at the end.
