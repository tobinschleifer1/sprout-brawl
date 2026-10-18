# GPT brief: review the crates economy for exploits (2026-10-18)

You are GPT-6-Astra in Codex, reviewing Blockfall's Roblox crates economy before it goes live.
Read `AGENTS.md`, then `docs/briefs/crates-and-monetisation-plan.md`. Roblox only: never modify
`web/`, never hand-edit `roblox/src/shared/Data/**` or test fixtures.

## Review these, as an attacker would

- `roblox/src/server/Economy.luau`, `Mint.luau`, `Locker.luau`, `AvatarStore.luau` (the record)
- `roblox/src/shared/Inventory.luau`, `Loot.luau`, `Cosmetics.luau`
- the remotes in `roblox/src/server/init.server.luau` (`Economy`, `Locker`, `onPlayerResult`)
- `roblox/src/client/LockerScreen.luau` (only for what it sends)

Look for: duplicating items or Sparks (races between two requests, a request during a save, two
servers holding one record, rejoining mid-open), opening or crafting without paying, keys or crates
going negative, a serial handed out twice, the drop meter farmed (the hourly cap, Training, bots,
leaving and rejoining), hostile client messages (wrong types, huge strings, NaN, tables where
strings go), a paid item losing its paid flag, records that fail to load being written over, and
anything that breaks Roblox's paid random items rules (odds shown are not the odds rolled).

## What to do

1. Write findings in `docs/briefs/economy-review.md`: each with severity, how to reproduce, and
   the fix.
2. Fix what you can, each fix with a test in `roblox/tests/economy.luau` (or a new test file
   registered in `roblox/check.sh`) that fails before the fix. Never weaken an assertion.
3. `cd roblox && ./check.sh` must exit 0.
4. Git may be blocked in your sandbox; if so leave the changes uncommitted and say so. Claude
   reviews and merges. End the review file with "For Claude": what you changed and what check.sh said.
