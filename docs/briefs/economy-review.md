# Crates economy exploit review — 2026-10-18

Reviewed on `chore/gpt-economy-review`. Scope: Roblox Economy, Mint, Locker,
AvatarStore, Inventory, Loot, Cosmetics, the server remotes/results hook, and
LockerScreen's requests. Also followed persistence into Purchases and match timing
into MatchService. No web source, generated Data, or generated fixtures were hand-edited.

**Do not enable Robux keys or trading on the strength of this review alone.** The
single-record spending exploits below are fixed, but the remaining paid-pity,
receipt, and trading work described below is a launch prerequisite for those features.

## Findings and fixes

### 1. High — concurrent opens/crafts spend the same balance (fixed)

Reproduce: give a player one Forge Crate and one earned key (or exactly 30 Sparks).
Suspend `Mint:serial` during its DataStore call. Send another open/craft after the
remote's 0.25-second rate limit. Both requests pass the original affordability
check; both grant; the balance becomes negative. Sanitization later clamps the debt
to zero. The same overlap can reuse the guarantee state and misidentify which key
paid for an item. Rate limiting does not serialize yielding operations.

Fix: every public economy mutation runs through `AvatarStore:inventoryTransaction`.
A per-player lock covers policy, serial reservation, and save yields. Operations
work on a private inventory; reward, debit and guarantee are published together.
Locker changes and wardrobe flushes cannot interleave with that transaction.
Regression: suspended open and craft with a second spend; assert exactly one item,
one charge, and no negative crate/key/Spark balance.

### 2. High — acknowledged rolls can roll back; stale servers overwrite each other (fixed)

Reproduce: load the same record on two AvatarStores, with one crate. Open on A and
then B. Originally both report success without saving; subsequent `SetAsync` calls
can overwrite either result. A failed leave/save or server crash also restores the
old crate and pity after the client has learned the outcome. This is a reroll and
lost-progress vulnerability today, and becomes item duplication once another system
can transfer the unsaved reward.

Fix: use a persisted `_revision` and `UpdateAsync` compare-and-swap for **all** record
writes. Economy success requires the complete result to be durable first. A stale
writer cannot overwrite a newer revision. A failed/ambiguous economy write hides
the candidate and disables further spending in that session; rejoining reads the
actual durable outcome. An uncertain acknowledgement is not grounds to refund or
reroll locally. Failed initial reads cannot mint, craft, or save defaults over data.

Regression: two actual stores sharing one fake DataStore; immediate rejoin after a
successful open; failed saving; failed loading. These fakes copy values and expose
yield points, instead of treating mutable Lua tables as persistent storage.

This is optimistic concurrency, **not an exclusive session lease or a two-player
trade transaction**. Both servers may read, but only a version-matching write wins.
Drain older servers before deployment: an old `SetAsync` writer ignores this fence.

### 3. High — saves and releases race with record changes (fixed)

Reproduce: suspend a save after its snapshot, mutate the record, resume. Originally
the first save clears `dirty` unconditionally. Start two saves and their completions
can also reorder. Separately, leave during a serial reservation or record read: the
old continuation can grant into an orphan inventory or reinstall a departed record.

Fix: single-flight detached saves; clear dirty only if the current record still
matches the saved snapshot. A placeholder prevents competing loads, and a released
load cannot publish its answer. Release marks an active transaction closing, then
waits for its continuation to finish. Failed ordinary leave saves retain their
record for retry. Hello is single-flight per Player; economy replies and result
callbacks recheck the exact Player object after yielding.

Regression: edit and second flush during a suspended save; release during serial
reservation; concurrent load/release. The original failed-read overwrite protection
is retained and tested.

### 4. High — paid keys ignore player restrictions (fixed at the opening boundary)

Reproduce: give a restricted player a Forge Crate and only a paid Forge Key; invoke
`Economy` with `{action="open", crate="forge"}`. Originally there is no policy check.
No paid key products are registered yet, but the server already accepts this record.

Fix: the server checks PolicyService when a paid-key opening is requested. Missing,
failed or non-explicitly-allowed responses deny it before rolling/spending. Earned
keys are still preferred and can open through the free route. The request also sends
the displayed pity count; paid spending rejects a stale/missing count so a different
probability modifier cannot silently be used. Client-supplied pity never sets state.

Regression: restricted, throwing, missing and allowed policy providers; unchanged
balances on denial; earned-key fallback; stale and correct pity disclosures.

The applicable requirements are the current [Roblox paid random items guidelines](https://create.roblox.com/docs/production/monetization/paid-random-items):
individual numerical odds before spending, updated modifiers, and per-player policy
restrictions. The new opening check does not implement a key-purchase flow.

### 5. High for future trading — salvage launders paid provenance (fixed conservatively)

Reproduce: salvage a paid Legendary for 400 Sparks; craft a 30-Spark Common. The new
copy has `p=false`, even though its funding came from Robux. Repeating converts a
restricted paid item into several apparently earned, tradeable items. Separately,
malformed stored provenance such as `p="true"` originally becomes `false` on load.

Fix: paid instances cannot be salvaged into the untagged, earned-only Spark balance.
Only explicit `p=false` is treated as earned for instance records; legacy pre-instance
ownership still migrates as earned. This intentionally changes paid salvage behavior.
A later provenance-aware currency design could restore it safely.

Regression: paid salvage leaves item and balance untouched; malformed provenance
stays restricted; ordinary earned salvage remains covered by the existing suite.

### 6. High for serial integrity; medium for future trade cooldown — numeric fields use the balance cap (fixed)

Reproduce: save serials 1,000,001 and 1,000,002, then sanitize/rejoin. Both become
1,000,000. An `os.time()` obtained date also becomes 1,000,000 (January 1970), so any
future three-day trade hold would already have expired. A high uid sequence moves
backwards if its highest surviving item has been salvaged.

Fix: balances retain their one-million cap; serials, dates and uid sequence use the
exact-integer range. Nonfinite numeric input is rejected. Regression round-trips
large serial/date/sequence and the paid bit, including deletion of the high uid.
Already truncated historical serials/dates cannot be reconstructed by sanitization;
restore those from trustworthy history if such records have already been saved.

### 7. Medium — Mint accounting loses/doubles counts; unavailable storage can reuse local serials (fixed in part)

Reproduce: suspend a Mint flush, issue another serial/destroy, and start another
flush. Originally the callbacks share mutable deltas, and completion replaces the
pending table with zeros, losing or double-counting events. A full Locker also
reserves/counts a copy before `Inventory.add` refuses it. Finally, a server whose
Mint store construction fails silently uses local serials starting at 1.

Fix: serialize writes/reservations/refreshes per item, freeze each written delta,
subtract only that delta, and use the committed UpdateAsync result. Validate counters
and exact-integer capacity before reserving. Check Locker capacity before minting.
Local serials require explicit Studio/test mode; live missing storage fails closed.
Regression: events during flush; full Locker; NaN/exhausted counters; missing live store.

**Remaining:** the count is still not an authoritative supply ledger. A crash can
lose pending deltas; a successfully reserved serial whose inventory commit fails can
count a nonexistent copy; an ambiguous Mint write can be counted again on retry.
Serial uniqueness does not depend on these display counts. Before supply affects
trading/value, add idempotent durable mint/destruction events and reconciliation.

### 8. Medium — qualifying time includes countdown and time after elimination (fixed)

Reproduce: play 41.5 seconds after the 3.5-second countdown, or take damage and lose
all stocks early while the other fighters keep playing. The original qualification
uses the whole match's frame count, so it credits 45 seconds the player did not fight.

Fix: MatchService counts each fighter's unpaused fight/sudden-death frames only until
elimination, and sends that count in their result row. Economy requires 45 seconds
of that count; Training remains excluded. No shared simulation behavior changed.
Regression: direct qualification boundaries, the real MatchService's first 300
ticks (exactly 90 fight ticks), elimination, pause, and the result row sent to Economy.

### 9. Medium — fixed hour buckets allow boundary farming (fixed)

Reproduce: complete twelve qualifying games before the hour boundary and another
twelve after it. The original counter resets at `floor(os.time()/3600)` even though
the earlier games remain in the previous sixty minutes. Rejoining should not help,
but unsaved counters also had the rollback problem in finding 2.

Fix: persist the most recent twelve qualifying timestamps, prune entries a full
hour old, and save meter/cap/drop together. Legacy hour-only records migrate
conservatively by placing their counted games at the end of that hour (which can
restrict them for up to an extra hour once). Regression crosses the boundary through
a fresh store and proves the meter and cap survive; a full elapsed hour frees a slot.

## Remaining launch work / limitations

- **High, before paid keys/trading: paid progress can finance an apparently earned
  guarantee.** Reproduce by making 39 non-Legendary paid Forge openings, then opening
  with an earned key: the guarantee was financed by paid progress, but the item is
  marked earned and the policy check sees an earned key. The shared pity counter
  carries no provenance. Fix by separating earned/paid guarantee tracks, or tracking
  paid influence and applying policy/provenance to the guaranteed outcome. This
  needs a defined free-route/migration UX; it is not fixed in this patch.
- **High, before repeatable key products: the receipt journal is not permanent.**
  AvatarStore/Purchases remember only the latest 50 receipt ids. Re-deliver an older
  receipt after 51 distinct receipts and it can be applied again. Concurrent yielding
  handlers also lack a shared receipt lock. Roblox controls receipt delivery (this is
  not a client RemoteEvent exploit), but the proposed key integration must not assume
  this proves exactly-once grants. Fix with durable idempotent receipt records and a
  transactional grant/retry protocol, then fault-test receipt retries and crashes.
  Existing skip product behavior was not redesigned in this crates review.
- **Medium, economy design: bots and passive damage remain eligible.** A player can
  take one hit, survive 45 seconds and complete a bot match without active play.
  This follows the written “dealt OR took damage” rule. The rolling cap bounds it
  to twelve counted matches per hour, but is not an anti-idle detector. If that is
  unwanted, require recent server-observed combat activity across the match or
  exclude CPU matches; specify the intended rule before tightening it.
- **Trading is not implemented or verified.** IsPaidItemTradingAllowed, atomic
  two-record recovery, the three-day hold, and receipt/payment provenance remain
  required. Do not describe the record revision fence as implementing trading.
- **Odds examined:** Loot.roll consumes Loot.odds directly; LockerScreen.oddsRows
  consumes the same data. No independent/mismatched rarity table was found. Existing
  loot tests check the distribution, exact totals within floating-point tolerance,
  guarantees and formatting. The displayed rounding disclaimer exists. Purchase-time
  disclosure still needs implementation when key products are added.
- **Hostile messages examined:** wrong types, NaN, infinity, tables and a 100KB string
  are rejected by the real Economy/Locker paths without spending/equipping. Extra
  client balance, paid flag or outcome fields are unused. The original type guards
  already handled these cases; the patch also bounds economy id/uid lengths. There
  is no client-callable match-result grant remote.
- **Availability tradeoff:** spending now needs a durable record write. Throttling
  can delay/refuse a transaction; failed/ambiguous economy writes require rejoining.
  No unsaved result is promised. This favors balance integrity over offline spending.
- **Studio:** one Studio was connected in Edit mode. A read-only Luau inspection
  was attempted and refused with “MCP tool call requires approval, but approval policy
  is never.” No live PolicyService/DataStore/playtest or visual validation was possible.
  Rendering was not changed or claimed verified.

## Verification

`tests/economy-security.luau` is registered in `check.sh`. The initial adversarial
run produced **13 failures and one passing hostile-input test** on the original
implementation. Two subsequent drop qualification/cap tests also failed before their
fixes, and the added real MatchService countdown assertion failed before its fix.
The final adversarial file has **20 passing cases**, including a successful storage
commit whose response is lost and a save whose candidate must remain invisible.
All existing assertions were preserved; fake stores were updated from SetAsync to
UpdateAsync to exercise the real persistence API. Match inputs now include the
server's actual participation field, with positive duration in the hitless/Training
tests so those assertions still test their intended rejection.

**33/33 deliberate source mutations were caught:** 24 targeting transaction locks,
commit ordering, revision checks, dirty tracking, release/load guards, numeric
sanitizing, paid provenance/policy/pity, capacity, Mint counts, payload validation
and the hourly cap; five targeting countdown/elimination/pause/result-row timing
and the client disclosure field; two targeting candidate privacy and ambiguous
write fencing; and two rechecking the original Training/hitless requirements. Mutations ran in isolated temporary source copies, never against
the working tree or a concurrently running full suite.

`cd web && npm test` exited **0**. The first full `check.sh` also exited **0**;
a final run covers the added release/visibility and integration assertions.

## For Claude

Changed the record's save/transaction boundary, remote lifecycle checks, policy guard,
paid salvage restriction, inventory numeric sanitization, Mint write coordination,
and drop qualification/cap persistence. LockerScreen only adds the disclosed pity
value to its open request. No web changes. Review the migration and availability
tradeoffs above, and resolve the remaining paid/trading prerequisites before selling
keys or enabling trades.

Final `check.sh` run: pending completion; the initial complete run exited 0.
`npm test` exited 0; all 20 security cases and 33 mutation checks pass.

Git staging was attempted and blocked: creating
`.git/worktrees/gpt-review/index.lock` returned `Operation not permitted`.
All changes are therefore uncommitted and unstaged for your review/merge.
