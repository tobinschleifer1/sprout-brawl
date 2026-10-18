# GPT brief: the Shop screen (2026-10-18)

You are GPT-6-Astra in Codex on Blockfall's Roblox build. Read `AGENTS.md`, then
`docs/briefs/crates-and-monetisation-plan.md` (especially "Prices: volume over margin", "VIP" and
"Before keys go on sale"). Claude is building the server side of phase 5 at the same time; you build
the client Shop screen against the contract below. Roblox only: never modify `web/`, never hand-edit
`roblox/src/shared/Data/**` or fixtures.

## Yours (touch nothing else)

- `roblox/src/client/ShopScreen.luau` (new)
- `roblox/tests/shop-ui.luau` (new), registered in `roblox/check.sh` after `tests/locker-ui`
- a `shop` screen in `roblox/tools/render-ui.luau` (add a branch; do not change the others)

## The contract

The server sends `EconomyView` (already used by `LockerScreen`) with a `shop` field:

```lua
shop = {
	restricted = boolean,   -- Roblox PolicyService says this player may not buy paid random items
	resetsIn = number,      -- seconds until the featured rotation changes (daily, UTC midnight)
	featured = { { id = itemId, price = robux, owned = boolean } },   -- four items, bought outright
	keys = { { bundle = "keys1", count = 1, price = 25 }, ... },     -- EMPTY when restricted
	passes = { { id = "vip", name = "VIP", price = 199, owned = boolean, available = boolean,
		perks = { "Gold name plate and VIP title", ... } } },
}
```

and, after a request, `event` may be `{ prompt = { kind = "product" | "pass", id = number } }` (the
screen then calls `opts.prompt(kind, id)`, which wraps MarketplaceService), `{ error = string }`, or
`{ purchased = { kind = "item" | "keys" | "pass", id = ..., count = ... } }` after Roblox confirms.

The screen sends, through `opts.send(msg)`:
`{ action = "buy", kind = "item", id = itemId }`, `{ action = "buy", kind = "keys", bundle = "keys5" }`,
`{ action = "buy", kind = "pass", id = "vip" }`. It never sends a price or decides ownership.

## What the screen must do

- Three sections: FEATURED (four item cards: picture via `opts.drawArt(frame, id, w, h)`, name,
  rarity colour, price in Robux, OWNED when owned, a countdown "new items in 7h 12m"), FORGE KEYS
  (bundle cards with count, price and the per-key price, e.g. "22 R$ each"), and PASSES (name, price,
  perks list, OWNED / BUY; `available = false` shows "coming soon" and cannot be bought).
- **Odds before buying keys** (Roblox's paid random items policy): the FORGE KEYS section has a
  worded "ODDS & DETAILS" button (never a bare icon) that lists every Forge Crate outcome and its odds,
  from `LockerScreen.oddsRows("forge", 0, false)` (require it; do not copy the numbers), with the
  guaranteed-opening view too and the rounding note. Key cards also say keys open Forge Crates.
- **Restricted players** (`restricted = true`): no key cards at all; one line explaining Forge Keys
  are not available for their account, and that crates still drop from matches and keys from play.
- **Prices shown plainly in Robux** on every card. No countdown pressure on purchases, no "was"
  prices, no premium currency. Many players are children.
- Buttons ask once (Roblox's own purchase prompt is the confirmation). Disable a BUY while its
  request is pending; show `event.error` and `event.purchased` on a message line.
- Match the game's UI kit (`roblox/src/client/Ui.luau`) and `LockerScreen.luau`'s look. Opens and
  closes like `LockerScreen` (`open`, `close`, `toggle`, `isOpen`, `setEconomy(view)`).

## Verification

- `tests/shop-ui.luau`: stub Instances as `tests/locker-ui.luau` does; assert every behaviour above,
  then break the code on purpose (each requirement) and confirm the test fails. Never weaken a test.
- Render with `lune run tools/render-ui /tmp/shop.json shop 1280 720` and
  `node tools/gui-svg.mjs /tmp/shop.json /tmp/shop.svg`; look at it (also at 390x844).
- `cd roblox && ./check.sh` must exit 0.
- Git may be blocked in your sandbox: leave changes uncommitted if so. Finish with a short note at
  the end of this file under "For Claude".
