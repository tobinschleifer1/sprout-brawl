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
   - **trading** (the owner wants it, 2026-10-18) follows `IsPaidItemTradingAllowed`: a player for whom
     it is false can never trade an item that came from Robux, directly or through a bought key. Every
     owned item is therefore an *instance* that remembers whether it was paid for (see Trading).
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

## Prices: volume over margin (2026-10-18)

The owner wants many small purchases rather than few large ones. Every price below is lower than the
first draft, and bundles get steadily cheaper per unit. Prices are always shown plainly in Robux
before purchase: no premium currency that disguises Robux, no fake "was" prices, no countdown
pressure. Many players are children, and Roblox requires clear prices and odds.

| What | Price | Per unit |
|---|---|---|
| Forge Key | 25 R$ | 25 |
| 5 Forge Keys | 110 R$ | 22 |
| 12 Forge Keys | 240 R$ | 20 |
| 30 Forge Keys | 540 R$ | 18 |
| Clothing piece (GPT's tiers) | 3 / 5 / 8 R$ | accent / standard / statement |
| Clothing pack | 22-26 R$ | about 25% off its pieces |
| Featured shop item | 29 / 49 / 99 / 199 R$ | by rarity |
| VIP | 199 R$ | |
| Character Studio+ | 149 R$ | |
| Wardrobe | 79 R$ | |
| Season Pass (8-week season) | 149 R$ | |
| Emote Pack | 99 R$ | |

These replace the price tables earlier in this document. The estimated value's key price `K` becomes
the best per-key rate, 18 R$: values scale with it, and the ladder's shape does not change.

**Seasons are 8 weeks.** A season brings a new crate series and a new season track.

**Duplicates are kept** (changed from the first draft, now that trading is in): a second copy is a
tradeable instance with its own serial, and the Locker has Salvage to turn any copy into its rarity's
Sparks. The odds never change per player either way.

## Decided (2026-10-18)

1. **Keys are sold for Robux**, under the policy rules above.
2. **The recommended prices** in the tables above stand.
3. **Phase 2 has started**: cosmetics drawn in matches.
4. **Trading is in**, and items show their rarity and how many exist.
5. **Clothing sells one piece at a time** as well as in packs, and players can **draw their own**.
6. **Estimated value** is worked out below; it is not built yet.

Still open: Series 1's start date; phase 6's answers. Decided 2026-10-18: GPT's clothing prices,
8-week seasons, volume pricing (above), the recommended VIP core, and CPU matches counting three
quarters of a match toward the drop meter.

## VIP: what it could include (for the owner to pick, 2026-10-18)

VIP is the one pass a player should feel every session. Rules: nothing that changes a fight, and
nothing random (a pass that grants crates or keys would itself be a paid random item, and blocked for
restricted players).

**Recommended core (199 R$):**
1. **Status you can see:** a gold name plate in the plaza, a VIP title, a gold [VIP] chat tag.
2. **+10% Sparks** from everything (down from the first draft's +20%: Sparks are the free route to
   every item, and +10% speeds it without making it a Robux race).
3. **A VIP cosmetic every season,** fixed and not random: a gold swing trail in Series 1, a different
   piece each 8-week season, kept forever.
4. **A VIP spawn effect,** a gold sparkle when you respawn. Everyone in the match sees it, which also
   advertises VIP.
5. **Doubled daily first-win Sparks.**
6. **Five saved cosmetic loadouts** in the Locker (switch between whole outfits with one press).

**Optional extras:**
7. A **VIP lounge** in the plaza: a rooftop terrace only VIPs can enter, with its own mirror.
8. **Room host perks:** VIPs can host rooms with extra rule options (item frequency, stage hazards
   off, a longer timer).
9. **Early access:** the featured shop's new items 24 hours before everyone else.
10. **A VIP emote and victory pose** (after phase 6).

**Not in VIP, on purpose:** extra drops, crates or keys (paid random items), shorter drop meters,
better odds, anything that changes damage, speed or timing.

## Phase 6: the questions still open

Phase 6 is emotes, the KO departure and victory poses. Its questions, from the character plan:

1. **How are emotes chosen?** Four emote slots; how a player picks one mid-lobby or mid-match:
   (a) the taunt key plays one of the four at random; (b) taunt plus a direction picks one of the
   four (recommended: fast, no menu); (c) a radial menu while the key is held.
2. **What does a KO look like for the fighter going out?** (a) one classic exit for everyone (they
   fly off with a twinkle); (b) a "KO departure" item each player owns and wears for their OWN exit
   (spin away, shatter, rocket off), separate from the KO effect, which belongs to whoever took the
   stock (recommended: it is a second sellable item type and reads clearly); (c) both, with (a) as
   the free default.
3. **Victory poses on the podium: by player or by weapon?** (a) one pose per character; (b) each weapon
   has its own pose; (c) the player picks a pose per weapon (recommended: the most expressive, and
   still one choice per weapon).
4. **Are emotes and poses items?** Recommended: four free ones for everyone, the rest in crates, the
   shop and VIP, like every other cosmetic.

## Clothing, one piece at a time

New clothing (tops, bottoms, headwear, hair, back pieces, gloves, shoes, face accessories) comes in
themed packs, and **every piece is also sold on its own** for a few Robux, so a player who wants only
the jacket buys only the jacket.

| | Price |
|---|---|
| A common piece | 15 R$ |
| An uncommon or rare piece | 25 R$ |
| An epic piece (capes, animated-looking hair) | 49 R$ |
| A whole pack (5-6 pieces) | about 35% less than its pieces bought one by one |
| A piece you already own counts toward the pack | the pack's price drops by what you paid |

Sold as Developer Products by price tier ("clothing piece, 25 R$"), with the server recording which
piece the player chose before prompting; a receipt grants that piece (the existing `Purchases.luau`
keeps a receipt to one grant). Pieces are direct purchases, never random, so the paid-random rules do
not apply to them. GPT is designing the first pieces and packs (`docs/briefs/gpt-cosmetics.md`).

**The kit code.** `k1` cannot name options that did not exist when it was specified. New pieces need
the `k2` format already planned in the character rework (phase 5): versioned decoding, canonical ids,
and an ownership check where saves and rooms are validated, so a code naming a piece its wearer does
not own falls back to the default.

## Drawing your own (Pixel Studio)

Part of the Character Studio+ pass: a pixel editor for clothing layers in the kit's own format, the
same grids and colour roles the shipped parts use (so a drawn top recolours with the outfit and
animates with the rig). Templates per slot (a top is the torso grid plus sleeve layers), a cap on
cells per layer so drawn items stay inside the draw budget, and mirror/fill tools.

What others see is the hard part. A drawing is user-generated content, and Roblox holds experiences
responsible for moderating what they show. So:

- **you and your friends** see your drawings, and so does anyone in a private room you made;
- **everyone else** sees the slot's default until a drawing is approved for public view (a review
  queue the owner works through in an admin tool), and any player can report one, which hides it
  until it is reviewed;
- drawings carry no text field and cannot be traded or sold to others; the palette is the kit's roles,
  not free colours, which also keeps them on-style.

## Trading

Player-to-player swaps of items (not Sparks, not keys, never Robux), at a Trading Post in the plaza.

- **Both sides** offer up to six items; both accept; any change resets the acceptance; a five-second
  countdown; both accept again. The server swaps the items in one step.
- **Who can trade:** Fighter Level 10+ and an account at least 7 days old (slows alt-farming);
  `IsPaidItemTradingAllowed` decides whether paid items may be offered by or to that player.
- **Fresh items** cannot be traded for 3 days after they are obtained (blunts stolen-account
  laundering and bots dumping drops).
- **Scam guards:** each side's estimated value is shown, with a warning when a trade is lopsided; the
  countdown restarts on any change; a full trade history per player.
- **No duplication.** A trade writes both players' records through one trade log entry: each record
  gets the trade id, the swap is applied, and a crash part-way is finished from the log on next load.
  Records need session locking (one server owns a player's record at a time) before trading ships;
  today's `AvatarStore` does not have it. This is the riskiest engineering in the plan, and it gets its
  own tests: a crash at every step, the same trade applied twice, two servers racing.

**Instances.** To trade, show serials and honour the paid flag, an owned item becomes an instance:
`{ uid, item, serial, paid, obtained, source }`. Items owned before instances exist are migrated as
earned (`paid = false`) instances.

## How rare is mine? Serials and copies in existence

Every item instance carries a **serial** (#57 of the Starforged), and every item shows **how many
exist**. Both are shown on the item card with its rarity colour.

- **Serials** come from a global counter per item. A DataStore key can only be written about once every
  six seconds, so a server reserves a block of serials at a time (10 to start, doubling for items it
  mints quickly) and hands them out; unused serials in a block are skipped. Serials are unique, not
  contiguous.
- **Copies in existence** is minted minus destroyed (a Mythic salvaged for Sparks no longer exists),
  kept as a per-item count updated with each block and refreshed hourly for display ("about 1,240").
- **Low serials** (#1-#100) get a small badge: collectors care, and it costs nothing.

## Estimated value (designed, not built)

A number shown on each item, in **value points**, where one point is one Robux of key spending. It
answers "what is this worth in a trade?", and it has to be hard to game.

**1. What the crate says (the model value).** A Forge Key costs `K` Robux at the best bundle rate
(700 / 12 = 58.3). Opening a Forge Crate spends `K`, and the crate's items share that value by
scarcity. For an item `i` with per-opening chance `p_i` (its rarity's share divided by the number of
items in that rarity):

```
V_model(i) = K * (1 / p_i)^a / sum_j( p_j * (1 / p_j)^a )
```

The denominator makes the expected value of one opening exactly `K` (the crate is worth what it costs),
and `a` sets how steeply rarity raises value. At `a = 1` every item contributes equally to the crate,
which with today's Forge table (14 Rares sharing 62%, 2 Mythics sharing 1.5%) leaves a Mythic worth
only about four Rares: too flat for a collectible. Computed from `Loot.luau`'s tables:

| `a` | Rare | Epic | Legendary | Mythic |
|---|---|---|---|---|
| 1 | 41 | 71 | 117 | 190 |
| 1.5 | 32 | 73 | 154 | 318 |
| **2 (suggested)** | **24** | **71** | **192** | **502** |
| 2.5 | 16 | 64 | 223 | 745 |

At `a = 2` a Mythic is worth about 21 Rares while an opening is still worth exactly one key.

Scrap Crate items are free to open, so their model value comes from the Workshop instead: their
Sparks craft cost, converted at the exchange rate the Forge items imply (points per Spark for a Rare,
which both crates hold).

**2. What exists (the supply adjustment).** The model assumes copies exist in proportion to their
odds. When an item is scarcer or more common than its odds predict (a retired series, a mass of
salvaging), value follows:

```
V_supply(i) = V_model(i) * (expected_copies(i) / copies(i))^b,   b = 0.5
```

`expected_copies` is total openings of its crate times `p_i`. Retired series are scarce by
construction, so their items drift up over time, which is the effect the owner wants.

**3. What players pay (the market).** Once trading has history, trades reveal value: in an item-for-item
trade, each side's items are worth what the other side's are. A trade gives each item an implied value
(its share of the other side's model value, split by model value within its own side). The market
value is the median of its last 30 implied values, and the shown value blends model and market by how
much evidence there is:

```
V_shown(i) = (n * V_market(i) + 10 * V_supply(i)) / (n + 10)      n = trades in the window
```

**4. Not gameable.** Lopsided trades (one side under a third of the other), trades between accounts
that trade only with each other, and trades of fresh items are left out of the market median. A value
moves at most 15% a day. Low serials and Pixel Studio drawings carry no value bonus (collectors may pay
more; the number stays honest).

**Building it:** a pure `Value.luau` beside `Loot.luau`, with the model computed from the same crate
tables, and tests that the expected value of an opening equals the key price, that scarcer is worth
more, that a retired series rises, and that a ring of wash trades does not move the market value.

## Before keys go on sale (from GPT's exploit review, 2026-10-18)

`docs/briefs/economy-review.md` found and fixed double spends, reroll-by-failed-save, stale servers
overwriting each other, unchecked paid keys, paid items laundered through salvage, capped serials and
miscounted match time. It also left these, which phase 5 must close before a key is sold:

1. **Paid progress toward a guarantee.** The guarantee count is shared by earned and paid openings, so
   39 paid openings can make an earned key's opening the guaranteed one, and its item counts as earned.
   Keep separate earned and paid guarantee counts (or carry provenance on the count).
2. **Receipts remembered forever.** Only the latest 50 receipt ids are kept; a 51st purchase lets an old
   receipt be granted again if Roblox redelivers it. Keep durable, per-purchase receipt records and
   grant through one transaction.
3. **Bot and idle matches.** Taking one hit in a 45-second match against bots qualifies. The hourly cap
   bounds it; decide whether CPU matches should count at all.
4. **Deploying the save change.** Records are now written with a revision check (`UpdateAsync`), and an
   older server still running `SetAsync` ignores it: shut down old servers when this ships.

## Phases, revised

1. Foundations (done: catalogue, loot, tests).
2. **Wearing things** (in progress): weapon skins, hit and KO effects and swing trails drawn in matches;
   the inventory and equipped loadout in the saved record; ownership validated; perf measured.
3. **Earning things (done 2026-10-18):** instances with serials (`Inventory` v2, `Mint`), the drop meter
   with its rules, crates and keys (earned keys first; items from paid keys marked paid), guarantees,
   crafting, salvaging, and the line under the results (`DropBanner`). Remotes `Economy` /
   `EconomyView`. The crate-opening screen and the Workshop screen are phase 4.
4. **Screens (done 2026-10-18):** the Locker (`LockerScreen`, a LOCKER button and L in the plaza):
   item cards with rarity, lowest serial, copies owned and in existence, WEAR / TAKE OFF, SALVAGE
   (press twice); CRATES with keys, the guarantee countdown, OPEN and ODDS & DETAILS; the crate
   reel landing on the server's roll; the Workshop (CRAFT, press twice). Thumbnails through the
   game's own renderers (`ItemArt`).
5. **Robux (server done 2026-10-18; the Shop screen is GPT's):** `Products` (every price; ids 0 until
   created in the Creator Dashboard), `Passes`, `Shop` (the daily featured four, key bundles hidden from
   restricted players, prompts only for what is on sale, credits for a purchase with no remembered
   choice), every receipt remembered permanently (`BlockfallReceipts1`) and granted inside the record's
   own write, separate paid and earned guarantee counts, CPU matches at three quarters, VIP (gold name
   and chat tag, +10% Spark drops, the VIP Gold Rush trail and VIP Sparkle respawn, double first-win
   Sparks, five saved outfits), the Wardrobe's 16 characters. Respawn effects now draw. Clothing goes on
   sale with phase 6, when it can be worn.
6. Clothing and `k2`: GPT's pieces joined to the kit; Pixel Studio.
7. Trading: session locking first, then the Trading Post; estimated value.
8. Coming back: levels, season track, challenges, mastery, login calendar.
