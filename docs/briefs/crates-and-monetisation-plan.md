# Crates, keys, drops and Robux: the plan

Owner's ask (2026-10-17): a system that keeps players playing, through crates and random drops
every 2-5 games, with the rarest things hardest to get; crates holding weapon skins, kill (KO)
effects, hit effects and other cosmetics; keys; game passes and other ways to spend Robux on skins,
effects and deeper character customisation. Plan it, add ideas, and start the designs and
components before implementing.

Everything here is **Roblox-only** (the web build is paused and has no accounts). Designs are
rendered by `roblox/tools/cosmetic-sheet.mjs` through the game's own art compiler, so what the plan
shows is what ships.

## The rules this is built on

1. **Cosmetic only.** Nothing for sale or in a crate changes a hitbox, damage, speed, knockback or
   timing. A skin keeps its weapon's grid: same silhouette, same grip, same reach (players read range
   off the shape). A test will hold every skin to its weapon's footprint.
2. **Everything is earnable.** Every item that can come out of a crate can also be crafted with
   Sparks, which are only ever earned. Paying speeds things up and buys some exclusives that are not
   random (passes, the featured shop); it never locks a random-only item behind Robux.
3. **Roblox's paid random items policy, in full** ([docs](https://create.roblox.com/docs/production/monetization/paid-random-items)):
   - a crate opened with a key bought with Robux is a paid random item: **every outcome and its odds
     as percentages summing to exactly 100% are shown before the key is used or bought**, behind a
     button labelled "Odds & Details" (a bare (i) icon is not allowed);
   - the guarantee counter (pity) is a probability modifier: its effect is explained before purchase
     and the shown odds change while it is in force;
   - `PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted` is checked for every
     player. Where it is true, Robux keys are not sold and a bought key cannot open anything; the
     player keeps the free route (earned crates, earned keys, Sparks crafting) and the featured shop,
     where items are priced directly. If the check fails, the player is treated as restricted;
   - **no trading** at launch, which keeps `IsPaidItemTradingAllowed`, scams and duplication out of it.
4. **One source of odds.** The table the server rolls from is the table the odds screen shows. It is
   data, not two copies of the numbers, and a test holds every table to exactly 100%.
5. **Server authority.** Rolls, drops, grants and spends happen on the server, from a saved record
   (the existing `AvatarStore` pattern: sanitise everything read back, never write over a record that
   could not be read). The client only asks.
6. **Lowest devices first**, as for everything else: every cosmetic is measured against the Frame
   fallback budgets (`tests/perf-budget.luau`) before it ships.

## What players collect

Six rarities, each with a colour used everywhere (crate reel, inventory border, drop banner):

| Rarity | Colour | Duplicate gives | Craft cost |
|---|---|---|---|
| Common | `#B8C0CC` grey | 5 Sparks | 30 |
| Uncommon | `#5FD068` green | 15 | 90 |
| Rare | `#4A9BFF` blue | 40 | 250 |
| Epic | `#B35CFF` purple | 120 | 750 |
| Legendary | `#FFB730` gold | 400 | 2,500 |
| Mythic | `#FF4A6A` red | 1,200 | 8,000 |

Item types (each is a slot in the Locker; one equipped per slot, per weapon for weapon skins):

| Type | What it changes | How it is built |
|---|---|---|
| **Weapon skin** | the weapon's colours, its awakened glow, and its swing trail tint | a palette + ink overrides over the weapon's own grid (zero extra Frames) |
| **Hit effect** | what your landed hits look like (FxPlayer) | Common-Rare: the existing hit drawings in a new colour ramp (free); Epic+: new drawings (petals, comic "POW!", ink splats) |
| **KO effect** | the burst when you take someone's stock | a new layer on the KO event; Legendary/Mythic get unique drawings (black hole, firework, dragon's breath) |
| **Swing trail** | the arc behind your attacks | trail colour/style, independent of the weapon skin |
| **Step trail** | dust from running/landing | the existing dust in a new ramp, or new particles |
| **Spawn effect** | how you arrive on a respawn | a layer on the spawn event |
| **Shield skin** | the bubble's colour and pattern | ShieldArt variants |
| **Character parts** | hats, hair, tops, capes, faces | new kit options, owned through the phase 5 entitlement model |
| **Emotes / victory poses** | the taunt key and the podium | phase 6 (still needs your answers) |
| **Titles and name plates** | your name in the lobby and on the HUD card | text + frame; some only earnable (mastery, seasons) |
| **Ultimate banner** | the frame of your ultimate's cinematic | UltBanner variants |

## How players get things

### Drops every 2-5 games

After every **qualifying match** the server counts one off the player's drop meter. When it reaches
zero they get a drop and the meter resets to a new random 2, 3, 4 or 5 (uniformly chosen, saved, so
rejoining does not reset it). A match qualifies if the player was in it for at least 45 seconds of
fight and did something (dealt or took damage); at most 12 qualifying matches an hour count, so
farming idle rooms against bots does not pay.

What a drop is:

| Drop | Chance |
|---|---|
| Scrap Crate | 60% |
| 50 Sparks | 20% |
| Forge Crate | 12% |
| Forge Key | 5% |
| A cosmetic straight from the Scrap Crate pool | 3% |

The drop arrives on the results screen as a banner in its rarity colour. Drops involve no Robux, so
the policy does not require odds for them; they are shown anyway in the Locker's "Odds & Details".

### Crates and keys

| Crate | Opens with | Contains |
|---|---|---|
| **Scrap Crate** | nothing: free to open | Common 60%, Uncommon 27%, Rare 10%, Epic 2.5%, Legendary 0.5% |
| **Forge Crate** | a Forge Key | Rare 62%, Epic 28%, Legendary 8.5%, Mythic 1.5% |

Within a rarity every item is equally likely, and the Odds & Details screen lists each item with its
own percentage (the rarity's share divided by the number of items in it).

- **Guarantees, shown on the crate:** a Forge Crate is guaranteed Legendary or better at the latest
  on the 40th opening since the last one; a Scrap Crate guarantees Epic or better by the 25th. The
  counter is visible, and on a guaranteed opening the odds screen shows the changed odds.
- **Duplicates** turn into Sparks (table above). No item is single-obtain, so the odds never change
  per player, which keeps the disclosure simple and honest.
- **Forge Keys come from:** drops (5%), the weekly challenges (one a week), every fifth Fighter Level,
  the season track, the 7-day login calendar's last day, or buying them (Robux).
- **Series.** Each season (about 8 weeks) brings a new crate series. Old series' items stay craftable
  with Sparks, so nothing is lost forever and nothing is a fear-of-missing-out purchase.

### Sparks and the Workshop

Sparks are earned only: duplicates, drops, challenges, levels, the season track. They are **never sold
for Robux**, which keeps crafting outside the paid-random rules and makes the Workshop the guaranteed
free path to any item. The Workshop crafts any item of any released series at the craft cost.

### Other reasons to come back

- **Fighter Level** from match XP (win or lose, more for playing well), rewards every level.
- **Season track:** free rewards for everyone; a premium track with the Season Pass.
- **Weekly challenges**, three a week ("land 40 kicks with Rocket Boots", "win 3 matches with
  Daggers", "take 10 stocks"): Sparks and a Forge Key.
- **Daily first win** bonus Sparks; a **7-day login calendar** ending in a Forge Key.
- **Weapon Mastery**: levels per weapon from playing it, unlocking mastery skins and titles that can
  be earned and never bought. The rarest-looking things in the game should be ones money cannot buy.
- **The Collection Book**: completing a set (every Series 1 hit effect, every Rare sword) awards a
  title or plate.

## Spending Robux

### Game passes (one-time)

| Pass | Price | What it gives |
|---|---|---|
| **VIP** | 499 | gold name plate and VIP title, +20% Sparks from everything, a VIP-only cosmetic each season (not random), a VIP lobby flourish |
| **Character Studio+** | 299 | the full colour picker for skin, hair, eyes and outfit (any colour, not just presets), saved palettes, a second accessory layer, mirrored/asymmetric options |
| **Wardrobe** | 149 | 16 saved characters instead of 8, and outfit sets per weapon |
| **Season Pass** (one per season) | 399 | the premium season track: exclusive skins, a KO effect, Forge Keys, Sparks, a title |
| **Emote Pack** | 199 | six emotes (after phase 6) |

None of these is random and none changes play. VIP deliberately does **not** grant crates or keys: a
pass that gives random items for Robux would itself be a paid random item.

### Developer products (repeatable)

| Product | Price | Notes |
|---|---|---|
| Forge Key | 75 | odds shown before purchase; not sold to restricted players |
| 5 Forge Keys | 325 | same |
| 12 Forge Keys | 700 | same |
| Featured shop item | 99 / 199 / 399 / 799 | four rotating items a day, bought outright, never random; also the policy's "direct purchase" alternative |
| Private room upgrades | later | custom rules, more slots |

Prices are starting points for you to set. Roblox's Premium Payouts also reward play time from
Premium members, which the retention systems above feed directly; Premium players get +10% Sparks.

## How it is built

**Data.** `src/shared/Cosmetics.luau`: the catalogue - id, type, name, rarity, series, the weapon a
skin is for, how it is earned or sold. `src/shared/CosmeticArt.luau`: generated by
`tools/gen-cosmetic-art.mjs` (to come) from the designs in `cosmetic-sheet.mjs`, like `RobloxArt.luau`.
`src/shared/Loot.luau`: crate and drop tables, the roll, the guarantees and the odds the screen
shows, from the same tables.

**The record.** The player's saved record grows a versioned `inventory`: owned item ids, equipped per
slot (and per weapon), Sparks, crates and keys by type, guarantee counters, the drop meter, challenge
progress, season progress, receipts (already kept by `Purchases.luau`). Sanitised on read like
everything else in `AvatarStore`; a record that cannot be read is never written over.

**Server.** `server/Economy.luau`: the drop meter at match end, opening crates, crafting, equipping
(validated against ownership), the policy check on join, and `AnalyticsService:LogEconomyEvent` for
every Spark and key in and out. Purchases go through the existing `Purchases.luau` (one
`ProcessReceipt`, receipts kept so a purchase is granted exactly once); passes through
`MarketplaceService:UserOwnsGamePassAsync` with `PromptGamePassPurchaseFinished`. Product and pass
ids live in a `server/Products.luau` table that starts at 0 = not created, like `SkipProducts.luau`.

**Drawing.** Equipped cosmetics travel with a fighter's loadout into rooms and matches (the server
checks ownership; the client never decides what someone owns). Weapon skins: `Weapons2D` draws a
skin's art under its own sprite key. Hit and KO effects: `FxPlayer` reads the attacker's equipped
effect. Trails: the swing trail colour. Each new drawing is cached and warmed in the countdown
(`FighterWarmup`), and measured against the perf budgets.

**Screens.**
- **The Locker** (a plaza station): slots, owned items, equip, preview on your own fighter.
- **Crate opening:** the crate shakes, bursts open, and a reel slows onto the item in its rarity
  colour. "Odds & Details" is a labelled button on the crate before you open it.
- **The Workshop:** craft by Sparks, browsing by series and type.
- **The Shop:** the featured rotation, keys, passes; odds before any key purchase.
- **Results screen:** XP, the drop meter ("next drop in 2 games"), any drop as a banner.

**Tests** (Lune, every one mutation-checked): every odds table sums to exactly 100%; the roll's
distribution over a million seeded rolls matches its table; guarantees fire exactly on time; the drop
meter yields a drop every 2-5 qualifying matches and never otherwise; duplicates convert at the
table's rates; a restricted player can neither buy a key nor open a paid crate; a purchase is granted
once across retries (extending `tests/purchases.luau`); a hostile record sanitises; every skin keeps
its weapon's footprint; equipping something unowned is refused.

## Phases

Each on its own branch, merged when `check.sh` passes, ending with a Studio playtest.

1. **Foundations.** The catalogue, the loot tables and the roll (pure, tested), the inventory record
   and its sanitising. *Started: see below.*
2. **Wearing things.** Weapon skins, hit effects, KO effects and trails drawn in matches; loadouts
   carry them; ownership validated. Perf measured.
3. **Earning things.** The drop meter, crates, guarantees, duplicates, the Workshop, the results
   banner.
4. **Screens.** Locker, crate opening, Workshop, Odds & Details.
5. **Robux.** Policy check, keys, the featured shop, the passes, receipts. Products created in the
   Creator Dashboard by you.
6. **Coming back.** Fighter Level, the season track, challenges, mastery, the login calendar.
7. **Live.** Series 2, limited-time crates, analytics review of drop rates and prices.

## Started now (2026-10-17)

- **26 weapon skins across all 15 weapons, crate and key art**, rendered through the game's compiler
  (`tools/cosmetic-sheet.mjs`): Rustwood Blade, Frostbite, Ember Oath, Starforged (Legendary, with its
  awakened form), Bone Fang, Neon Twins, Venomfang, Cobblestone, Thunderhead, Lumberjack, Glacier
  Cleaver, Harvest Moon, Reaper's Lantern, Toy Blasters, Chrome Rivets, Boxing Reds, Magma Fists,
  Royal Guard, Elmwood, Sunfire Bow, Necro Tome, Lionheart, Spiked Lantern, Thornvine, Golden Halos,
  Retro Rockets.
- **Hit and KO effect concepts**: the existing effect drawings in new ramps (Sakura, Static, Inkblot,
  Supernova, Toxic, Ember), rendered with `tools/fx-sheet` (`FX_KINDS` to pick drawings).
- **`src/shared/Cosmetics.luau` and `src/shared/Loot.luau`** with `tests/loot.luau`: the Series 1
  catalogue, the crate and drop tables, the roll, guarantees, duplicates and the disclosed odds.
  Not yet used by the game.
- The design board (an Artifact) with every design, the odds tables and the screen mockups.

## Decisions for you

1. **Sell keys for Robux at all?** Recommended yes, with the policy handled as above; the alternative
   is earned keys only and Robux only for passes and the featured shop.
2. **Prices** for the passes, keys and shop tiers (the tables are starting points).
3. **Season length** (8 weeks suggested) and when Series 1 starts.
4. **VIP's contents.** In particular, whether +20% Sparks is too strong a boost to an earned currency.
5. **Trading** later? Recommended not before the economy has run for a season.
6. **Phase 6** (emotes, KO departures, victory poses) feeds the catalogue; it still needs the answers
   you skipped earlier.
