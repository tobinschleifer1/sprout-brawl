# Clothing catalogue and weapon-skin expansion

Design handoff, 2026-10-18. Roblox only. Clothing is **design data, not a shop or live kit extension**.
The 24 pieces live in `roblox/src/shared/RobloxClothing.luau`; each has its own permanent id,
category, display name, rarity, pack, suggested price tier, and role-coloured puppet layers.

## Buy one piece, or the pack

Every row below is one purchase. A top includes its sleeves; gloves and shoes include both hands
or feet. No piece requires the rest of its pack. A pack grants the same six individual item ids,
so its pieces can be mixed with free parts and other packs. Hats normally hide part of a hairstyle;
buying a pack does not force players to wear its hat and hair together.

Suggested tiers: **accent = 3 Robux**, **standard = 5 Robux**, **statement = 8 Robux**. These are
proposals, not registered products or confirmed live prices. Rarity describes the design, not a
stat bonus or random purchase. These clothes are proposed direct purchases; no loot pool is changed
by the clothing data. A later shop should recognise already-owned pieces and show exactly which
remaining pieces a pack grants; do not silently charge again for a fully owned pack.

| Pack | Visual theme | Six singles | Whole pack | Saving |
|---|---|---:|---:|---:|
| Neon Night | Racing stripes, square cuffs, forward sweep | 31 | 24 | 7 Robux |
| Frostforged | Broad yokes, rolled cuffs, warm outerwear | 34 | 26 | 8 Robux |
| Candy Club | Broad candy bands, soft shapes, short hems | 31 | 22 | 9 Robux |
| Void Court | Deep V, pleats, dark mantle, horizontal visor | 32 | 24 | 8 Robux |

## Neon Night

| Item id / name | Kit category | Rarity | Tier / Robux | Why it reads at fight scale |
|---|---|---|---|---|
| `neon_circuit_bomber` — Circuit Bomber | `top` | Rare | statement / 8 | The double-width lightning chevron and bright cuffs make a clear chest-and-wrist rhythm. |
| `neon_sideband_joggers` — Sideband Joggers | `bottom` | Common | standard / 5 | A two-cell racing stripe runs down each leg; the dark cuff separates it from shoes. |
| `neon_signal_cap` — Signal Cap | `headwear` | Uncommon | standard / 5 | The long two-row visor and rectangular badge survive as a cap silhouette. |
| `neon_voltage_sweep` — Voltage Sweep | `hair` | Uncommon | standard / 5 | A stepped, forward-rising quiff with a broad highlight gives the hair a single strong direction. |
| `neon_pulse_gloves` — Pulse Gloves | `gloves` | Common | accent / 3 | Two bright cuff rows distinguish the gloves even when the fist is a few pixels. |
| `neon_nightstep_hightops` — Nightstep Hightops | `shoes` | Uncommon | standard / 5 | Tall shoe shafts and a solid contrast sole read more reliably than tiny laces. |

## Frostforged

| Item id / name | Kit category | Rarity | Tier / Robux | Why it reads at fight scale |
|---|---|---|---|---|
| `frost_rimeguard_coat` — Rimeguard Coat | `top` | Rare | statement / 8 | The four-row shoulder yoke, front opening, and hem make a cold-weather coat without extra coat-tail geometry. |
| `frost_ridgeguard_trousers` — Ridgeguard Trousers | `bottom` | Common | standard / 5 | A chunky knee patch on each leg reads as protective trousers at low detail. |
| `frost_snowline_beanie` — Snowline Beanie | `headwear` | Uncommon | standard / 5 | The square pompom and thick rolled brim identify the hat before its colour does. |
| `frost_whiteout_halfcape` — Whiteout Halfcape | `neck` | Rare | statement / 8 | The pale shoulder shelf and drape down the back remain visible beside a plain shirt. Uses the existing neck slot. |
| `frost_icebreak_mitts` — Icebreak Mitts | `gloves` | Common | accent / 3 | A dark accessory cuff surrounds a solid trim-colour mitten block, the reverse of Pulse Gloves. |
| `frost_snowdrift_boots` — Snowdrift Boots | `shoes` | Uncommon | standard / 5 | The two-row cuff sits above a tall, uninterrupted boot block. |

## Candy Club

| Item id / name | Kit category | Rarity | Tier / Robux | Why it reads at fight scale |
|---|---|---|---|---|
| `candy_sugarstripe_tee` — Sugarstripe Tee | `top` | Common | statement / 8 | Two wide candy bands cross the torso; their spacing survives the half-detail composer. |
| `candy_bonbon_shorts` — Bonbon Shorts | `bottom` | Common | standard / 5 | The bright rolled hem above bare shins reads as shorts even beside tall shoes. |
| `candy_sundae_beret` — Sundae Beret | `headwear` | Uncommon | standard / 5 | A wide tilted dome and two-cell top nub separate this from both the cap and beanie. |
| `candy_softserve_swirl` — Softserve Swirl | `hair` | Rare | standard / 5 | A compact spiral rises in three broad steps; hair and its own highlight supply every colour. |
| `candy_sugarstar_specs` — Sugarstar Specs | `eyewear` | Uncommon | accent / 3 | Two thick star centres connected by a bar make a playful eye stripe; tiny star points are portrait detail. |
| `candy_taffy_trainers` — Taffy Trainers | `shoes` | Common | standard / 5 | The contrast toe patch and sole form a two-tone wedge on each foot. |

## Void Court

| Item id / name | Kit category | Rarity | Tier / Robux | Why it reads at fight scale |
|---|---|---|---|---|
| `void_eventide_vest` — Eventide Vest | `top` | Uncommon | statement / 8 | The deep, thick V contrasts with bare arms; the long central seam makes it read as a vest. |
| `void_rift_pleats` — Rift Pleats | `bottom` | Uncommon | standard / 5 | Wide two-cell pleats and a continuous hem make a short skirt with a distinct hip silhouette. |
| `void_comet_tail` — Comet Tail | `hair` | Rare | standard / 5 | A long back-of-head tail stays inside the head canvas; the broad crown highlight makes the tied hair readable. |
| `void_eclipse_mantle` — Eclipse Mantle | `neck` | Epic | statement / 8 | A strong clasp and angular shoulder mantle lead into a short pointed back drape; no new cape canvas. |
| `void_orbit_cuffs` — Orbit Cuffs | `gloves` | Uncommon | accent / 3 | Two thick bands bracket the forearm, leaving the hand visibly bare. |
| `void_null_visor` — Null Visor | `eyewear` | Rare | accent / 3 | A four-row visor becomes a clean horizontal eye band instead of isolated lens pixels. |

## Art contract

All colours are the existing kit's **slots and shades**, not literal hex colours or fixed-colour
roles: `a/A/u` top, `b/B` trim, `c/C` bottom, `f/F` shoes, `x/X/y` accessory, `h/H/i` hair. A pack's
name suggests a theme; the player still controls its colours. The two proof colourways deliberately
recast every piece: Midnight uses dark blue, cyan, purple and darker skin; Daybreak uses ivory,
oxblood, orange and lighter skin. They use existing swatches, with no colour-picker implementation.

Layers use the shipping format: zero-based `x/y`, `part`, `z`, and `rows`; `.` is transparent.
Tops and sleeves use `clip = true` against the chosen body's mask. Hair layers set `hair = true`,
and hats carry the existing `trim` row, so hair does not poke through their crowns. Layers never
create a new base mask. Z is the kit's existing order: top/sleeve/pants 20, skirt 26, cape tails 27,
neck/glove/shoe 30, back hair 10, front hair 50, eyewear 55, headwear 60.

Every layer stays within the original canvases:

| Puppet piece | Cells | Use here |
|---|---|---|
| Head | 18 × 20 | Hats, hair, glasses and visor |
| Torso | 16 × 18 | Tops and cape shoulders/drape |
| Arm | 6 × 16 | Sleeves, gloves, cuffs |
| Leg | 7 × 18 | Trousers, shorts, shoes |
| Pelvis | 14 × 10 | Waistbands, skirt, cape tails |

The two capes are **neck options**, like the existing mantle; their side drapes are painted onto
torso and pelvis. They add neither a rig joint nor cloth simulation. They replace the chosen neck
option, so a scarf is not worn in that same slot. At the smallest scale the design is a shoulder
shelf and a coloured back edge; individual folds and clasps are portrait detail. The two mitt/glove
designs deliberately reverse cuff/hand colours after the first small-scale preview looked too similar.
Eyewear similarly becomes a clear band at small scale, rather than preserving every lens or star point.

## Reproduce the clothing proof

From `roblox/`:

```bash
node tools/clothing-sheet.mjs /tmp/blockfall-clothing --self-test
node tools/cosmetic-sheet.mjs /tmp/blockfall-cosmetics
./check.sh
```

`clothing-sheet.mjs` embeds its Lune helper and removes the temporary helper afterward. It uses a
fresh instance of the existing test loader per outfit/colourway, replaces only the default option
in that process's private catalogue, and calls the shipping `KitPortrait`, `PostureArt`,
`AvatarCompose`, and `Canvas2D`. This is a preview adapter, **not a usable k1 code or a saved kit
migration**. It never writes generated data or changes the runtime composer. The helper is embedded
to keep the work inside the brief's allowed files.

Outputs are `<piece-id>.png`, `<pack-id>.png`, `baseline.png`, four `sheet-<pack-id>.png` contact
sheets, `packs.png`, and `index.json`. Each labelled tile contains two portraits, two views at
**26 pixels per stud**, and two native-size **26-pixel-tall fighters** using the actual half-detail
composer. These are different scales: a roughly five-stud fighter is about 130 pixels tall at
26 px/stud. Both were checked so the brief's small-fighter requirement is covered too.

The tool validates ids, categories, rarity, role usage, bounds, hair trimming, pack slot conflicts,
and suggested discounts. `--self-test` deliberately corrupts 13 catalogue properties and verifies
that each is rejected, then checks that the small-image visibility guard rejects an unchanged
baseline (14 mutations total). Every piece is compared with the same body and colourway at match
scale; the current minimum is **8 changed pixels**. That guard catches missing layers; the PNG
review is what judges whether the change makes a useful design.

The contact sheets and all four pack combinations were rendered and viewed. Rimeguard's yoke,
Whiteout's trim-colour drape and Icebreak's contrast mitten block were revised after that review,
then rerendered and viewed again. The proof covers the default body in a neutral pose, two
colourways, and both body detail levels. Arbitrary mixing, every build/head, expressions, weapon
occlusion (especially Rocket Boots hiding shoes), and combat motion still need integration review.

## Measured cost

The preview first records rectangles, then draws through a fresh **real Canvas2D Frame fallback**
against Lune's Roblox Instances. `index.json` records rectangle count, descendant Frame count
(including sprite containers), and mean time over 100 warm still draws per outfit/colourway/detail
level. It also verifies that those warm draws keep the same descendant instances.

| Default body plus | Full-detail Frames | Half-detail Frames | Largest increase over same-colour baseline |
|---|---:|---:|---|
| No new piece | 149 | 85 | — |
| One piece | 143–176 | 77–100 | +27 full / +15 half |
| One complete six-piece pack | 160–196 | 90–105 | +47 full / +20 half |

Replacing a detailed free part can reduce the count. On this host the median warm still draw was
about 0.036 ms full / 0.025 ms half. These are Lune measurements, **not device or Studio frame-time
claims**. The largest pack is Void Court. The drawings stay inside existing canvases and are
composed into cached part art, rather than adding an independently drawn overlay per purchase.
Before release, add these owned options to the six-fighter Frame/image-path budget scenarios,
including mixed outfits and face/flash sprite churn. Do not infer that the current runtime budget
test exercises this dormant catalogue.

## Joining the kit: k2 and ownership

Keep `k1`'s category order, option meanings and colour offsets frozen. Its one base-36 digit per
category provides only 36 choices and has no extensible category boundary. This paid catalogue is
reserved for the planned **k2**, not patched into generated `Data/AvatarKit`. The later Roblox-only
format needs:

1. A version-specific decoder and canonical encoder. Decode old k1 with its original layout forever;
   migrate a saved avatar only after successfully reading it. Old ids must keep their old appearance.
2. Stable catalogue identifiers per category, with a registry namespace distinguishing free options
   from these permanent clothing ids. If the wire uses numeric ids, use an append-only registry and
   enough bits/variable-length fields for growth; do not serialize a current list position.
3. Explicit fields or lengths for categories and the existing eight colour slots. Preserve swatch
   selection; reserve versioned fields for planned custom colours, extra accessory layers,
   asymmetry, attitudes, emote slots and victory poses. A preview colourway is not an entitlement.
4. A defined single-choice slot rule: these tops replace top, bottoms replace bottom, shoes replace
   shoes, etc.; both cape designs replace neck. Preserve each design's `trim`, `clip`, `hair`, and z
   metadata when resolving the selected id. A future independent back slot needs an explicit field
   and layering policy, not an extra digit inserted before k1's colours.
5. Ownership stored separately from appearance. Buying a single grants its item id; buying a pack
   grants those same six ids through the existing idempotent receipt path. The server checks owned
   ids on save, equip and room admission, alongside existing earned unlocks. A copied appearance
   code is viewable by spectators but never proof that its wearer owns the parts.
6. Defined handling of unknown/retired ids, malformed lengths and unowned selections: canonical
   defaults and a clear equip rejection where appropriate. Audit the current 64-character code
   ceiling and every profile, room, presence, snapshot and loadout path before storing a longer code.
7. A Roblox registry/resolver that combines generated free options with this separate catalogue,
   without editing generated data. Include canonical appearance and catalogue version in bounded
   composition/image cache keys. Preserve selected clothing during expression overrides. Test k1
   round trips, k2 round trips, ownership rejection, pack grants and unchanged weapon stats directly.

## Weapon skins in this branch

Added **34**, rather than 30, because 26 existing designs across 15 weapons needed 34 additions to
reach four for every weapon. Total: **60**, exactly four each. The original 26 design entries are
unchanged. `Cosmetics.luau` differs only by the 34 matching `skin(...)` lines.

The additions contain **11 Common, 12 Uncommon, 4 Rare, 4 Epic, 1 Legendary and 2 Mythic** skins.
Candy uses pink/cream/mint; Frostforged uses ice-blue/teal; Neon Night uses violet/cyan/magenta;
Rustwood uses warm wood/olive; Void uses violet with pale edges. The two Mythics put bright surfaces
on large parts of the weapon so rarity does not depend on tiny dark details.

| Weapon | New names and rarities |
|---|---|
| Sword | None needed: already four |
| Daggers | Sugar Shivs — Common |
| Hammer | Permafrost — Uncommon; Jawbreaker — Common |
| Axe | Afterhours Hatchet — Uncommon; Rift Cleaver — Epic |
| Scythe | Sugar Reaper — Common; Rime Reaper — Uncommon |
| Blasters | Bubblegum Blasters — Common; Nightshift — Epic |
| Gauntlets | Cold Snap — Uncommon; Arcade Breakers — Rare |
| Pike | Roadwarden — Common; Icebound Standard — Uncommon; Eventide Sovereign — Mythic |
| Longbow | Licorice Recurve — Uncommon; Eclipse String — Legendary |
| Grimoire | Sugarspell — Common; Mossbound Ledger — Uncommon; Last Light Codex — Mythic |
| Shield | Ironbark — Common; Whiteout Bulwark — Uncommon; Afterimage Aegis — Epic |
| Flail | Scrapyard Wrecker — Common; Gumball Wrecker — Uncommon; Orbit Breaker — Rare |
| Whip | Taffy Snap — Common; Livewire Lash — Uncommon; Riftbinder — Epic |
| Chakram | Peppermint Rings — Common; Cold Orbit — Uncommon; Discotheque — Rare |
| Rocket Boots | Foundry Runners — Common; Sugar Rush — Uncommon; Nightdrive — Rare |

All additions override every native literal ink key where one exists; white glints may remain
white. Chakram and Rocket Boots have palette-only grids and therefore empty ink overrides.
No grid, anchor, grip, silhouette or reach changes. A direct compiler audit compared both ordinary
and awakened rectangle counts with the native weapon, including single-unit Daggers/Chakram grids:
**none of the additions increases either count**. Some equal colours merge into fewer rectangles.
The audit caught increases on early gauntlet/shield recolours; their ink separation was corrected.

All 60 skins were rendered by `cosmetic-sheet.mjs`. A temporary review script used that same
compiler to make five contact sheets at 48 px/stud, 26 px/stud, and 5 px/stud, with normal and
awakened small views. All five PNGs were viewed. Local evidence is in `/tmp/blockfall-cosmetics/`
(`page-1.png` through `page-5.png`); clothing evidence is in `/tmp/blockfall-clothing/`. Those are
local review artifacts, not committed assets. At 5 px/stud the small weapons are only a few pixels:
the material colour remains the signal, not individual rivets or an added effect. The whip proof
shows its native handle; the animated lash still belongs to the existing renderer/phase 2 hooks.

## For Claude

- Made 34 skins (60 total, four per weapon) and 24 single clothing pieces in four discounted packs.
  Only the five files permitted by the brief changed. No runtime clothing consumer, purchase code,
  generated data edits, or web edits.
- Viewed all 60 skin designs in five multi-scale contact sheets, and every clothing piece plus all
  four packs in two colourways at portrait, 26 px/stud and true 26-pixel-fighter half detail. The
  new clothing tool is reproducible and its 14 deliberate validation/visibility mutations fail.
- `cd roblox && ./check.sh`: **exit 0** on the final source (generation, strict analysis, every replay and direct suite). `cd web && npm test`: **13 passed, 0 failed**.
  The first check attempt could not download API definitions because DNS was unavailable; copied
  the existing ignored `globalTypes.d.luau` from the main checkout, then the full skin check exited 0. The final clothing check caught and fixed strict inference of optional layer fields; the complete rerun exited 0 too.
- Studio was connected in Edit mode. Automatic approval review rejected `execute_luau` with
  “MCP tool call requires approval, but approval policy is never”. No Studio sync, playtest or
  GUI inspection of these designs was performed. Offline art is reviewed; live appearance and
  device performance remain for integration.
- Git staging/commit was blocked by `Operation not permitted` creating
  `.git/worktrees/gpt-cosmetics/index.lock`. Changes remain in `feature/gpt-cosmetics`'s worktree,
  uncommitted and unpushed; nothing was merged. Intended small commits: “Give every weapon four
  collectible looks without adding draw cost”, then “Make affordable clothing readable as single
  purchases”. End each with `Co-Authored-By: GPT-6-Astra (Codex) <noreply@openai.com>`.
  Review patches are `/tmp/blockfall-01-skins.patch` and `/tmp/blockfall-02-clothing.patch`;
  the complete source changes are already present in this worktree.
- Remaining work is integration: k2/entitlements, shop products, all-build/mixed-outfit combat and
  Studio perf checks. The design catalogue and its preview tool are complete.
