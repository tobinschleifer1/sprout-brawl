# GPT brief: more skins, and clothing pieces (2026-10-18)

You are GPT-6-Astra in Codex, working on Blockfall (a 2D platform fighter, Roblox build in `roblox/`).
Read `AGENTS.md`, then `docs/briefs/crates-and-monetisation-plan.md`, then this. Claude is building
phase 2 of that plan (cosmetics drawn in matches) at the same time, so stay inside the files listed
under "Yours".

## Rules (the owner's; they override AGENTS.md where they differ)

1. **Roblox only.** Do not modify anything under `web/`.
2. **Never hand-edit** `roblox/src/shared/Data/**`, `tests/trace-*.json` or fixtures.
3. **Cosmetic only.** A weapon skin is a palette plus ink overrides over the weapon's own grid: never a
   new grid, never a changed silhouette, grip or reach.
4. **Lowest devices first.** Skins cost nothing extra (same rectangles). Clothing adds rectangles:
   keep every new part within the existing parts' sizes (see `web/src/data/avatarParts.js`).
5. **Look at what you make.** Render it and view the PNG before calling it done:
   `node tools/cosmetic-sheet.mjs <dir>` for skins; for clothing, the tool you write below.
6. **`cd roblox && ./check.sh` must exit 0** before you call anything finished. `tests/loot.luau`
   requires every catalogue weapon skin to have a design in `cosmetic-sheet.mjs` with the same id.
7. **Git:** work on branch `feature/gpt-cosmetics` (you are in its worktree). Small commits; messages
   explain WHY; end each with `Co-Authored-By: GPT-6-Astra (Codex) <noreply@openai.com>`. If stopped
   part-way, commit what you have as `WIP: <task>`. Do not merge anything; Claude reviews and merges.

## Yours

- `roblox/tools/cosmetic-sheet.mjs` (append to `SKINS`; do not change existing entries)
- `roblox/src/shared/Cosmetics.luau`, **only** the weapon-skin block (`skin(...)` lines): add a line per
  new skin, same id, name, rarity. Do not touch anything else in that file.
- `roblox/tools/clothing-sheet.mjs`, `roblox/src/shared/RobloxClothing.luau` (new; design data only,
  nothing reads it yet), and `docs/briefs/clothing-catalogue.md` (new).

## Task 1: thirty more weapon skins

Series 1 has 26 (`cosmetic-sheet.mjs`). Add about thirty, so every weapon has at least four, spread
over the rarities (more Commons and Uncommons than Legendaries; one or two Mythics, the most striking
things in the game). Give each a name that sounds like an item a player would brag about, and a
theme that holds across weapons where it can (a "Neon Night" set, a "Frostforged" set, a "Candy" set,
a "Void" set...). Use each grid's literal inks (the ink tables in `web/src/data/weaponArt.js`) so the
whole weapon changes, not just its palette. Check every one at 26 px a stud too (fighters are about 26
px tall): a skin has to read at match scale. Render them all and look.

## Task 2: clothing pieces, designed to be bought one at a time

The owner wants players able to buy a single piece of clothing for a few Robux, not only whole packs.
Design about twenty-four **single pieces** across the kit categories that read at fight scale: tops,
bottoms, headwear, hair, capes or back pieces, gloves, shoes, face accessories. Group them into four
or five themed packs (each pack is also sold whole, cheaper than its pieces bought separately).

- Draw them in the kit's own format (layers of text grids on the puppet pieces, colour ROLES not fixed
  colours, see the long comment at the top of `web/src/data/avatarParts.js`), as data in
  `roblox/src/shared/RobloxClothing.luau`: id, category, name, rarity, pack, suggested price tier, and
  the layers. Nothing reads this file yet; it is the design.
- Write `roblox/tools/clothing-sheet.mjs` to render each piece worn by a default kit body, in a couple
  of colourways, using the shipping composer and renderer the way `tools/kit-sheet.mjs` and
  `tools/render-portraits.luau` do (a Lune helper is fine). Look at every piece at portrait scale and
  at match scale.
- Write `docs/briefs/clothing-catalogue.md`: the packs, the pieces, why each reads at fight scale, and
  how they would join the kit later (the kit code `k1` cannot hold new options without the planned
  `k2` format: say what `k2` needs to carry them).

## When done

Leave a short summary at the end of `docs/briefs/clothing-catalogue.md` under "For Claude": what you
made, what you rendered and looked at, what `check.sh` said, anything unfinished.
