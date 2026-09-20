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
| **The simulation** | **complete.** Everything left is Roblox-side |
| `src/shared/InputCodec.luau` | the input frame packed into one integer, round-trip tested exhaustively |
| `src/shared/Net.luau` | remotes and the wire format |
| `src/shared/Snapshot.luau` | the fighter snapshot, encoded and decoded in one place |
| `src/server/*` | **runs the match**: fixed 60Hz loop, remote input with a jitter buffer, snapshots |
| `src/client/*` | 60Hz input sampling, snapshot interpolation, the 2D canvas, camera and stage |
| `src/client/Channels.luau` | ported - the whole pose system, 30 states and all twelve ultimate bodies |
| `src/client/WeaponPose.luau` | ported - every swing arc, the aimed weapons, and all twelve ultimate poses |
| `src/client/Weapons2D.luau` | the twelve weapon shapes, as hybrid rect-and-tip silhouettes (see below) |
| `src/client/Predictor.luau` | client-side prediction: rollback and replay for the local fighter |
| `src/client/Hud.luau` | percent, stocks, ultimate meter, timer, callouts and the scoreboard |
| `src/client/HudColors.luau` | the damage ramp and player palette, held to the JavaScript |
| `src/client/Avatar2D.luau` | head shapes, faces, headgear and chest marks |
| Ultimate VFX, audio, character/stage select, persistence, matchmaking | not started |

**The Roblox-side code has had one playtest.** It reached Studio, synced, and ran; the first bug it
found is below. Everything above the line is verified against the
JavaScript by replay; everything from `Net.luau` down type-checks, builds a place file, and has had
its one testable pure part (the codec) mutation-tested, but no part of it has executed inside
Studio. Treat the first playtest as the real test.

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
| `weaponPose`'s `REST[wid] ?? 0` fallback | all twelve weapons have a REST entry |
| `weaponScale`/`holdFrames`/`reload` falling back through `||` | no weapon datum is 0, so the JavaScript's falsy-zero path never fires |

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

### The Roblox half: what is built and what it assumes

- **Server authority, with prediction on the local fighter.** `MatchService` is still the only
  place the simulation advances, at a fixed 60Hz accumulator - never on delta time, because the
  simulation is only defined at 1/60 and every parity guarantee in `tests/` depends on it. The
  client now runs its own fighter ahead of the server and rolls back when corrected, which is what
  `Fighter:snapshot()`/`restore()` were built for in Phase 2.

  Only the local fighter, and only its movement: combat is a silent stub of the same shape
  `tests/fighter-parity.luau` replays against, so a predicted frame never invents a hit, a grab or
  a pickup. Those arrive from the server and land at the next reconcile. A fighter who gets hit
  mid-prediction visibly snaps; a fighter running and jumping does not.

  Reconciliation is lossy and has to be: `Fighter:snapshot()` carries object references - the
  platform, a grab victim - that cannot cross a network. So the server sends the wire fields, the
  client restores its OWN full snapshot from the acknowledged frame, writes the server's fields
  over the top, and replays. Restoring the local snapshot is the part that is easy to skip and
  impossible to get away with: without it the replay applies inputs the fighter has already
  consumed and every buffered press is counted twice.

  The server echoes how many input frames it has CONSUMED per player, not how many it received.
  Frames coalesced away by the jitter-buffer drain and frames dropped on overflow are both counted,
  because a client whose replay window drifted by one after the first hiccup would drift forever.

  `tests/prediction.luau` runs two fighters from one start on identical inputs - one stepped
  straight through as the server, one predicted and reconciled at lags of 0, 1, 2, 4 and 7 frames -
  and compares every wire field plus the non-wire state the wire cannot carry. 225,264 values
  across 5,944 reconciles, four weapons. It injects genuine mispredicts the client could not have
  seen (a launch, a chill, a move it is not in) and asserts convergence once the correction has
  been delivered, refusing to pass if no such comparison ever ran. Eight mutations, eight caught.

  `hitstun` had to join the wire because of it: the state name says a fighter IS in hitstun and not
  how much of it is left, so a predicting client replayed a launch under ordinary air control.

- **The HUD is a rewrite, not a port.** `web/src/ui/hud.js` is a DOM tree - divs, CSS classes and
  innerHTML - so unlike `channels.js` and `weapons2d.js` there is nothing in it to translate. What
  carries over is what it SAYS and where: a band of per-fighter tiles along the bottom, a timer
  above them, a callout in the middle, and a percent floating over each fighter's head.

  It is its own ScreenGui on purpose. Canvas2D owns a pool of Frames it hides and reuses every
  frame, and a HUD sharing that pool would flicker or be recycled out from under itself.

  One piece of it IS arithmetic and is held to the JavaScript: the damage colour ramp, in
  `HudColors.luau`, checked against 693 sampled percents plus both sides of every stop. That ramp
  is the only part of a HUD nobody would notice was wrong - one off by a stop still produces a
  plausible colour for every percent - so it is the only part with a test. Seven mutations, seven
  caught.

  `ultMeter` and `ultReady` are computed from `ultCharge` rather than sent. They are a division and
  a comparison against a shared constant, and putting them on the wire would be sending an opinion
  the client can derive. The Match config gained `timed` and `timeLimit`, which a client cannot
  derive and needs before it can show a clock.

  `Canvas2D.project` was added for the floating labels: the HUD lives in a different ScreenGui and
  needs the renderer's camera, and a second copy of the camera's arithmetic is the kind of
  duplicate that stays right until somebody changes one of them.
- **Input is sampled at 60Hz on the client**, not per render frame. The server consumes exactly one
  frame per tick; a 144Hz client sampling per render would send 144 frames a second into a queue
  that drains at 60 and spend the match falling behind its own inputs.
- **A starved tick repeats the holds and none of the presses** (`InputCodec.holdOnly`). Repeating a
  whole frame through packet loss would re-fire jump; clearing `guardHeld` would drop a shield.
  `guard` is cleared too, despite being how you shield - it is also the tech buffer, and repeating it
  would hand a player an automatic tech for the length of their packet loss.
- **Stage parts are `CanCollide = false` and anchored.** Collision is resolved by `Stage.collide`
  against the numbers, exactly as in the web build. If a part and the simulation disagreed the
  simulation would be right and the player would be confused, so nothing physical touches a fighter.
- **Rigs are normalized.** The hurtbox is `char.height` tall for everyone on a weapon, so every R15
  rig is forced to identical proportions and scaled to exactly that height. A player keeps their
  colours, clothing and face; they do not get to look like a bigger or smaller target than they are.
- **The wire's field names exist in exactly one file.** `Snapshot.encode`/`decode` are paired in
  `src/shared/Snapshot.luau` and nothing downstream of `decode` knows the short names. This is not
  tidiness: the first Studio playtest found `Rigs.pose` reading `s.facing` from a table whose field
  is `fc`, because the format changed and the camera's call site was updated while the rigs' was
  not. Nil is not an error in Luau until something compares it, so the rigs drew with no facing, no
  tumble, no KO hiding and no invincibility, and the only symptom was one console line. Adding a
  field is now one edit, and `tests/snapshot.luau` fails if a consumer's name and the wire's drift.
- **Bodies are animated; weapons are not.** `render2d/channels.js` is ported as
  `src/client/Channels.luau` and held to the JavaScript by `tests/channel-parity.luau`: 632,408
  channel values across 27,496 poses, 30 states and all twelve weapons, exact. Fighters now lean,
  squash, swing their limbs, smear, flash and settle exactly as they do on the web.

  The avatar - four head shapes, six faces, six hats and four chest marks - is ported as
  `Avatar2D.luau`. They hang off `HIP`, `SHO` and `HEAD`, which is why those proportions are the
  JavaScript's rather than convenient ones, and they live in one module for the reason the web
  build gives: the character creator's preview has to be the SAME drawing as the match, and the
  only way to guarantee that is for there to be one drawing.

  Three shapes trade a curve for steps, as the weapons do: the horns and crown are staircased
  triangles, and the hood's quadratic becomes a back panel and a stepped shoulder. The sash goes
  the other way and is now EXACT - it is one rotated rectangle, which is precisely what a Frame
  is, where the JavaScript draws a parallelogram. Measured in Studio: four fighters with weapons
  and full avatars cost 0.676ms a frame, 4.1% of a 16.7ms budget, against 216 pooled Frames.

  `channelsFor` turned out to be a pure function of the snapshot plus the weapon data, which is
  what made it testable at all: `tools/gen-channel-traces.mjs` writes every field it reads into the
  trace, so the fixture doubles as the proof that `Snapshot.FIELDS` carries enough to draw with.
  Nine fields had to be added for it - `startupEff`, `frameCount`, `charge`, `hitlag`,
  `fastFalling`, `ultCooldown`, `techRoll`, and `chillStacks`/`ledgeAction` flattened out of
  `f.effects.chill.stacks` and `f.la.kind`. `move` is NOT sent: everything the poses read off it is
  static weapon data the client already has, so it is looked up from `moveId`.

  Ten deliberate mutations, ten caught - including the one this port was always going to be at risk
  of, the chill tint table indexed JavaScript-style at `stacks - 1` against Luau's 1-indexed array.

- **Weapons swing.** `weaponPose` and `ultimatePose` are ported as `src/client/WeaponPose.luau` and
  held to the JavaScript by `tests/weapon-parity.luau`: 384,808 values across 22,696 poses and 41
  distinct output keys, exact. The key SET is compared as well as the values, in both directions,
  because `out.ult` carries a different set per weapon and per phase - a port that stops emitting
  `ult.chop` is a renderer that stops drawing the chop, and that has to fail rather than look
  slightly wrong. Twelve mutations, ten caught; the two survivors are recorded in the unreachable
  table above.

  The phase curve is SHARED with the body rather than copied: `WeaponPose` calls `Channels.swing`,
  exactly as weapons2d.js imports `swing` from channels.js. They were separate once and the torso
  and the weapon ended up fifteen frames out of phase.

  `ultShots` is the one snapshot field this needed, for Deadeye's round counter.

- **The weapon shapes are a deliberate divergence.** `weapons2d.js` builds each weapon from five to
  nine arbitrary polygons with bevels and fullers. Roblox UI cannot fill a polygon - `Canvas2D.tri`
  staircases one into six Frames - so a faithful sword is about ninety-six Frames, and four
  fighters with trails would run into the high hundreds every frame.

  `Weapons2D.luau` draws mass as rotated rectangles, which a Frame reproduces exactly, and spends a
  staircased triangle only where the silhouette needs a point: a blade tip, an axe bit, a spear
  head. Twelve to twenty Frames a weapon. Measured in Studio: four armed fighters cost **0.483 ms**
  a frame, 2.9% of a 16.7ms budget, against 117 pooled Frames. At gameplay size what distinguishes
  a hammer from an axe is the outline, not the bevel, and the outline is intact.

  The contour pass is NOT optional and is kept: every weapon is drawn twice, once flat in a dark
  value offset back and down. At gameplay zoom a weapon is twenty to thirty pixels of mid-grey
  against a sky of mid-grey, and without it the blade vanishes the moment it leaves the fighter's
  silhouette.

  `drawUltimate` - the afterimages, the reaper's moon, the second pistol, the rune stack - is not
  ported. Those are effects around the weapon rather than the weapon, and the ultimates read
  without them.
