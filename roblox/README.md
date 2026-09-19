# Roblox build

This folder is the Roblox Studio version of Blockfall. The web build in `../web` is the playable
prototype; this path ships the same design on Roblox, following sections 4 and 5 of the design
document (`../docs/design.html`) and the weapon system in section 0.

Nothing here is required to play the web build.

## Status

| | |
|---|---|
| Toolchain | installed (Rokit 1.2.0, Rojo 7.7.0, luau-lsp 1.69.0, Lune 0.10.5) |
| `default.project.json` | written — `rojo build` produces a place file |
| `src/shared/Config.luau` | ported, all constants |
| `src/shared/Data/*.luau` | **generated** from `web/src/data` — 12 weapons, 6 avatars, 6 stages, 5 items |
| `src/shared/Loadout.luau` | ported, all 72 avatar x weapon combinations checked against the JS |
| `src/shared/Stage.luau` | ported (geometry, platforms, ledges, collision, sudden death) |
| `src/shared/Fighter.luau` | ported, including snapshot/restore for client-side prediction |
| `src/shared/Input.luau` | the input frame shape (polling is the client's job on Roblox) |
| `src/shared/Hazards.luau` | all ten hazards, ported |
| `src/shared/Rng.luau` | the seeded generator, bit-exact with the JavaScript |
| `src/shared/Combat.luau` | **done** — hit resolution, grabs, throws, bursts, projectiles, mine summons, all twelve ultimates, the whole item system |
| `src/shared/Knockback.luau` | ported, verified numerically identical to the JS (both curves) |
| `src/shared/Match.luau` | ported — countdown, KOs, respawns, stocks, timer, sudden death, results |
| `src/shared/Ai.luau` | ported — the whole difficulty ladder, chains, item use and edgeguarding |
| **The simulation** | **complete.** Everything left is Roblox-side: rigs, camera, netcode, UI, persistence |
| Netcode, rigs, UI, audio, persistence | not started |

```bash
./check.sh          # type-check the Luau tree, then verify parity with the JavaScript
rojo serve          # sync into Studio (needs the Rojo Studio plugin)
rojo build --output Blockfall.rbxl
```

### Parity with the JavaScript

`web/src/engine/knockback.js` is the source of truth for the damage model. `tests/parity.luau`
checks **38,542 values** — `launchSpeed`, `stunSpeed`, `hitstun`, `blockstun`, `hitlag` and the full
DI-bent `velocity` across a grid of bases, growths, damages, percents, weights, angles and stick
directions — against a fixture generated from the JavaScript, and fails on any drift.

`check.sh` regenerates that fixture from the live JavaScript on every run, and that is deliberate.
The fixture used to be a committed snapshot rebuilt by hand from a command in this README, which
meant the check could only catch drift somebody had already noticed. The day the web build split the
launch curve in two (`KNOCKBACK.slope` vs `stunSlope`) the Luau port silently stopped matching it and
`./check.sh` still printed "matches exactly". Now the check compares the port against the JavaScript
as it is on disk:

```bash
node tests/genfixture.mjs   # what check.sh runs first; needs node
./check.sh                  # analyze + regenerate + parity, exits 1 on any drift
```

Two curves, not one: `launchSpeed` is how far a hit sends you and `stunSpeed` is how long you cannot
act. Whatever ports `Combat` must compute **both** for every hit and carry both into `applyHit` —
feeding `launchSpeed` into `hitstun` compiles, runs, plays with different combos from the web build,
and passes every check in this folder except the parity one.

### The data layer is generated, not written

Everything under `src/shared/Data/` is emitted from `web/src/data/**.js` by `tools/gen-data.mjs`.
**Do not edit those files** — change the JavaScript and re-run `./check.sh`, which regenerates them
on every invocation. The JavaScript keeps the design commentary and stays the single source of
truth, and a Roblox build that disagrees with the web build becomes impossible rather than merely
discouraged.

The generator refuses anything it cannot translate faithfully: a function, a `null`, a shared or
cyclic reference, or a number needing 17 significant digits (see below). `tests/data-parity.luau`
then walks the emitted Luau against a JSON dump of what the generator was handed — in both
directions, 6,648 leaves — so a dropped field, an invented field, a rounded number or an array
emitted as a dictionary fails the build. All four were verified by deliberately introducing them.

`Loadout.luau` is hand-written because it is logic rather than data, so all 72 avatar x weapon
combinations are compared against `buildLoadout` in the JavaScript.

**Lune's JSON decoder keeps about 16 significant digits.** Composed stats reach 17 — `18 * 0.778`
is `14.004000000000001336` — so the loadout fixture carries them as decimal *strings* and parses
them with `tonumber`. Without that, a bit-exact port fails the test. The generator asserts that
every literal in the source data still fits in 16 digits, so this cannot start mattering silently.

### The engine is checked by replay, not by reading

`tools/gen-traces.mjs` and `tools/gen-fighter-traces.mjs` drive the **real JavaScript classes** and
record what they did, frame by frame; `tests/stage-parity.luau` and `tests/fighter-parity.luau`
replay the same scripts through the Luau and report the first frame that differs. The scenarios are
data inside the trace file, so the two harnesses cannot drift apart and quietly test different
things. 112,237 stage values and 564,445 fighter values across 44 scenarios.

Reading two files side by side does not catch a flipped comparison or an off-by-one index, so every
check here was verified by deliberately breaking the port and confirming it failed. That found real
holes in the tests themselves, and each one is written up where it was fixed:

- No stage has a moving **solid**, so `collide`'s ejection branch was unreachable and could be
  deleted without failing anything. It now runs against a synthetic stage carried in the trace.
- No probe had `vy == 0`, and none had a fighter standing still while a platform rose into them —
  the only case that reads `prevTop = p.top - p.dy`.
- No scenario pressed a button near a hit, so ticking the input buffers during hitlag — the thing
  the source comment specifically warns about — passed all thirty scenarios.
- Every hit passed `stun == launch`, which made the two knockback curves indistinguishable.
- `isDodgeInvincible` and the other computed properties were not recorded at all.
- Sweeping probes across a stage found the hazards that cover ground and missed the ones that do
  not: across 7,700 frames the first hazard trace triggered **two** hazard hits in total, leaving
  the slag drip, the antenna arc and the dust devil's throw untested. Probes are now parked on each
  hazard's own coordinates.

### The sort that had to change

`match.js` sorts its results table, and JavaScript's sort is stable where Luau's `table.sort` is
not. Two fighters tied on elimination order, stocks and percent — which is what the surviving
members of a winning team look like — kept their original order in the web build by luck of the
spec, and would have come out in a different order on Roblox. Both builds now break that tie on
`index`, which makes the ordering total and means the same thing in both languages.

This is the only place the port asked for a change in the web build's behaviour rather than a
change in the port.

### The match is seeded, not random

`Math.random` is gone from `stage.js` and `hazards.js`. The stage owns a seeded generator
(`new StageRuntime(data, seed)`) that the slag drip and the item spawner draw from, and `Match`
picks a seed once at construction and keeps it. A match is now a pure function of its seed and its
inputs, which is what makes it replayable, what a server-authoritative build needs, and what lets
the hazards be parity-tested at all. Unseeded play still varies — the seed is drawn once rather
than a thousand times a second from inside the simulation.

The generator is xorshift32, chosen because it is shifts and xors only: no multiply, so `bit32`
reproduces it exactly with no 32-bit-multiply workaround. `tests/rng-parity.luau` checks 12,000
outputs across six seeds, bit-exact with no tolerance.

`combat.js` still has two `Math.random` calls. They become Phase 3's problem.

Snapshot/restore is checked three ways: structurally (every field the fighter owns is in the
snapshot), for independence (the snapshot is poked and must not follow the fighter, and vice versa
after a restore), and behaviourally (snapshot, run on, restore, replay — the replayed frames must
still match the JavaScript). That last one is what client-side prediction actually does.

### Unreachable code the port keeps finding

Breaking the port on purpose and watching the tests *not* fail turns out to be a good way to find
code the game cannot run. Six so far, all faithfully ported (except `field`) and none of them
load-bearing today:

| where | why it cannot run |
|---|---|
| `stage.collide` moving-solid ejection | no stage has a moving solid |
| `antennaarc` per-fighter cooldown | 30 frames, but the arc is only live for 22 |
| `sign(0)` | every call site is guarded by a threshold |
| `resolveHit` armour branch | no move sets `armor` |
| `resolveHit` command grab | no move sets `kind: "grab"` |
| `onMoveActiveFrame` `field` kind | no weapon used it — **deleted from the web build** |
| `wall`, `cloud`, `node` summons | only `mine` is used — not ported |
| the `pulse` move kind, `teleport` recovery, `nearestNode` | nothing spawns nodes — not ported |
| the Fruiting, Network, Tangle and Chill mechanics | no weapon has them — `fruiting` not ported |
| projectile-vs-summon damage threshold | every projectile that can reach a mine deals 15, well over the 4 it tests |
| the crater's fade rounding | Colossus is the only `slam`, and its `minDamage: 10` dominates every faded step |
| the `burst` and `freeze` move kinds | no weapon uses either — ported anyway, they are a dozen lines |
| `p.grounded` projectiles | nothing in the roster sets it |
| `dropItem`'s empty-gun removal | `useItem` deletes a spent gun immediately, so a held one is never at zero uses |
| the `place` guard and the Bulwark throw exception's `onGround` term | `useItem` is only reachable from `_stepGround` |
| `it.spent` in `stepItems` | read there, set nowhere |
| `move.total` | written for every move, read nowhere in the simulation, renderer or UI |
| the respawn timer's rounding | `RESPAWN.delay` is 2.0, so 2.0 x 60 is exact |
| the bots' `setup` plan | read by a branch, assigned by nothing |

`field` is now deleted from the web build. The rest are left in place: the five above are guards
that would start working the moment the data changes, and the unused summon types and mechanics are
plausibly for weapons that do not exist yet. They are simply not carried into the Luau.

### Two traps this port has already hit

**`math.round` is not `Math.round`.** Luau rounds halves away from zero, JavaScript rounds them
toward +infinity, so they disagree at `-2.5`. `math.floor(x + 0.5)` is the JavaScript behaviour.

**Luau arrays are 1-indexed.** Engine code that reads `hitboxes[0]` or `hitboxes[U.count - 1]`
shifts by one. Every `inv[0]`/`inv[1]` pair in config became `[1]`/`[2]`, and
`LEDGE.invinc[min(grabs - 1, 2)]` became `LEDGE.invinc[min(grabs, 3)]`.

**`sign(0)` is +1 in this engine, and 0 in `math.sign`.** The JavaScript defines its own
`sign = (v) => (v < 0 ? -1 : 1)`; the port keeps that helper rather than reaching for the built-in.

**Unreachable branches are worth knowing about.** Three places in the engine cannot be reached by
the current data, each found by deliberately breaking the port and watching nothing fail: `collide`'s
moving-solid ejection (no stage has a moving solid), the antenna arc's 30-frame per-fighter cooldown
(the arc is only live for 22), and `sign(0)` (every call site is guarded by a threshold). All three
stay — they are correct defensive code — but none of them is load-bearing today, and the tests say
so rather than implying coverage they do not have.

**`table.insert(t, nil)` inserts nothing.** It does not leave a hole, it shifts everything after it.
This cost an hour: a nil `moveId` shifted every later column of the trace snapshot left, and the
test reported forty scenarios failing on a field that was correct.

`sourcemap.json` and `globalTypes.d.luau` are generated/downloaded by `check.sh` and are gitignored.
The definitions come from the luau-lsp repo:

```bash
curl -fsSL -o globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
```

## Toolchain (already installed — kept here for a fresh machine)

All four are managed by Rokit, so nothing needs Homebrew.

1. **Rokit** (toolchain manager)
   ```bash
   curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
   ```
   Close the terminal window and open a new one. If `rokit --version` says command not found, the PATH line
   did not take effect in that window: run `source ~/.zshrc` in the same window you type `rokit` into, and
   check `echo $PATH` contains `.rokit/bin`.

2. **Rojo** (syncs a source tree into Studio, or builds a place file)
   ```bash
   rokit add --global rojo-rbx/rojo
   ```
3. **Luau LSP** (type-checks Luau against the Roblox API: `luau-lsp analyze`)
   ```bash
   rokit add --global JohnnyMorganz/luau-lsp
   ```
4. **Lune** (runs Luau outside Roblox, for tests)
   ```bash
   rokit add --global lune-org/lune
   ```
5. **Rojo's Studio plugin**
   ```bash
   rojo plugin install
   ```
6. Verify
   ```bash
   rojo --version && luau-lsp --version && lune --version
   ```
   If macOS blocks a binary the first time: `xattr -d com.apple.quarantine "$(which rojo)"` (same for the others).

In Studio: sign in, and turn on Game Settings → Security → "Enable Studio Access to API Services" so DataStores work while testing.

## Plan for the port

The web build was written so that the port is mostly translation:

- `web/src/config.js` and `knockback.js` are arithmetic and are hand-ported, held to the JavaScript by
  `tests/parity.luau`. **Done.**
- `data/weapons/*.js`, `data/avatars.js`, `data/stages/index.js` and `data/items.js` are pure data and are
  **generated**, not hand-written — see below. **Done.**
- `engine/fighter.js`, `combat.js`, `stage.js`, `match.js` become the server-authoritative modules described in
  design section 5 (`CombatServer`, `HitboxService`, `StageService`, `MatchService`). The hitbox rectangles become
  `workspace:GetPartBoundsInBox` queries against hurtbox parts.
- `render2d/*` has no Roblox counterpart to port: it is a 2D canvas renderer, and in Studio the player's own
  R15 avatar is the body. What DOES carry over is `render2d/weapons2d.js` as a spec — it defines where each weapon
  sits and how it swings on every frame of every move, which is what the Studio weapon welds and animations reproduce.
- `ui/*` becomes ScreenGuis; `audio/*` becomes uploaded OGG assets referenced from an `Audio` module.
- Data persistence, the store, the battle pass, matchmaking and anti-exploit are Roblox-only and are specified in
  design sections 5.7, 5.8, 6 and 9.

`src/` here is an empty Rojo-style skeleton (`shared`, `server`, `client`) ready for that work.
