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

1. **Readability** (done). The kill hit is predicted and marked (white flash, ring, burst); hit
   sparks, ring and shake scale with the launch; anyone near their KO percent smokes (measured,
   not guessed: the median real side/top KO is 122%); heavy startups glint; team matches spark in
   team colours; Roblox labels hold at the screen edge with an arrow when a fighter is off screen
   and say YOU on yours; KO callouts name who did it; bots in rooms are "CPU n". Checked live in
   Studio (2v2, hard bots): YOU, edge arrows, smoke, "KO! ▲ CPU 3 by ■ CPU 2", and the flash on
   a kill hit. Found on the way: in a 6-fighter match nearly everyone fights on fists for the
   first 20 s (four drops for six people), and 136 of 184 KOs in bot matches are off the bottom
   - failed recoveries, which is where depth and team saves should look.
2. **Depth** (done). Agreed with the user: bounces off walls and ceilings, armour on every heavy
   against lights, mild staling; no clashes and no edge/recovery work.
   - Staling: the last 8 moves landed, 5% off per repeat among them, floor 60%; once per swing;
     throws and the ultimate never stale, blocked hits are not landed. Small hits barely stale -
     a 3-damage jab rounds back to 3 until four repeats - which is mild on purpose.
   - Armour: a heavy's startup shrugs off the first light hit (damage taken and counted, swing goes
     on, a metal clank); a heavy, a grab or the ultimate still go through.
   - Bounces: launched (hitstun or tumbling) into a wall or ceiling above 30, rebound at 60%;
     techable off both. 47 wall and 6 ceiling rebounds in 232 bot-minutes; KO sides unchanged.
   Bot ladder held throughout. Studio (2v2, Saltflat): armour fired and clanked, no errors; no
   rebound came up in the sample.
3. **Team play.** Save a launched ally by touching them, team combos (a combo carried on by an ally
   counts for both, with an assist), team throws (grab an ally and throw them at a foe), and KO
   assist credit in every mode.
4. **Online feel.** Instant local feedback when your attack visibly connects (confirmed or taken
   back by the server), then lag compensation on the server for your hits.

Each phase lands in `web/` and `roblox/` together, held by `check.sh` replay, with every test
mutation-checked, and a Studio playtest at the end.
