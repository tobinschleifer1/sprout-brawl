# Bug hunt: gameplay and UI (2026-10-22)

Branch `fix/bug-hunt`, off `feature/ui-arcade` (the newest UI, and what Rojo serves). Findings go in
`findings.md` beside this file, each with how it was found, the evidence, and its status. Fixes follow
the repo's rules: a test for each, mutation-checked; `check.sh` green; Roblox only.

## What the existing 139 suites already prove

Parity of the simulation with the web build (5.4M values), each screen's logic, the economy, the UI
kit, and spacing on 23 recorded screens. So this hunt aims at what nothing exercises today:

## 1. Every picture draws (automated, Lune)

"Images bugging out" in a game drawn entirely from Frames means: art that errors, draws nothing,
draws off its frame, or draws NaN-sized rects. For **every** id in each catalogue, draw it the way the
game does, through a recording canvas, and flag: an error; zero shapes; any shape outside its frame
by more than a pixel; NaN or infinite coordinates; absurd counts (a cost bug).

- ItemArt: every cosmetic (skins, hit/KO effects, trails, clothing, emotes, poses), every crate.
- Weapons: every weapon sprite, every skin of every weapon.
- Fighters: every preset avatar; the kit's every part in the Studio tiles (KitPortrait).
- Stages: every stage thumbnail (the map vote).

## 2. Every screen at every size and in every state (automated, renders + lint)

The 23 recorded screens are one size and one state each. Record each screen at 390x844 (phone
portrait), 844x390, 1024x600, 1366x768 and 1920x1080, and in edge states: an empty inventory, a full
one (hundreds of items), very long names, the largest balances (999,999,999), a 40-character player
name, every error message. Lint all of them, then look at the worst.

## 3. Long fuzzed matches (automated, Lune)

Run many server-side matches - every weapon against every weapon, every stage, bots of every
difficulty, items and disasters on, 1v1 to 3v3 - for minutes of game time each, and assert after
every frame: positions and velocities finite; nobody stuck inside a platform or outside the blast
zone without being KO'd; damage within 0..999; stocks never below 0; the match always ends; no Lua
error. Also replay random input mashing through the client's prediction and check it reconciles.

## 4. In Studio (needs the owner's Studio open and connected to the MCP)

The only place to see what actually renders and what it costs. Play, then read the console
(`[Blockfall]` lines and renderer warnings), walk the GUI tree for frames with NaN or zero sizes,
frames off-screen, and run each screen: plaza, Shop, Locker (open a crate), Studio, select, a CPU
match to the results. Read Position/Size, not AbsolutePosition.

## Order

1, 2 and 3 now (no Studio needed); 4 when Studio is connected. Report after each part.
