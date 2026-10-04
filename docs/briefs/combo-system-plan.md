# Combo system plan: skill through timing, air strings and finishers

Status: phases 1-4 done (engine, weapon data, prediction and bots, animations); phase 5 next. Branch: `revamp/sprites-disasters`.

The decisions behind it:

- **Skill comes from three places:** timed links, air strings with cancels, and long finisher strings.
- **Animations:** new pose families, with a swing arc for each weapon.
- **Defence:** damage scaling plus a timed escape.
- **Scope:** all 12 weapons in one pass.

**No new keys.** Everything uses Move, Light, Heavy, Jump and Dodge as they are bound today
(`roblox/src/client/Bindings.luau`, `web/src/engine/input.js`).

## Where we are

- **Every weapon already has a combo tree.**
  - `chains` and `chainsTo` pick the next light from the direction held.
  - `chainsHeavy` cashes a string out into a signature.
  - `Fighter._chainInto` (`web/src/engine/fighter.js:624`) runs it.
  - `web/test/combo.test.mjs` measures which routes are true combos.
- **Mashing performs exactly as well as timing.** A press is buffered for 6 frames
  (`INPUT_BUFFER`), and a chain fires on the first frame it can. So pressing Light over and over
  plays a weapon's string perfectly. No skill is tested.
- **Aerials do not chain at all.** One exception: Sword's Overhead gives the jump back on hit.
- **The chain steps look identical.**
  - `channels.js` picks a body pose from the move-id prefix, so `LightNeutral1/2/3` all play the
    same `jab`, and `LightSide1/2` the same `side`.
  - Only the Flail's weapon swing overrides that (`SWING_BY_MOVE`).
- **The client never predicts a chained attack.**
  - The predictor's combat is a stub, and `moveLanded` is not in the snapshot.
  - So the client cannot know its hit landed, and every chain arrives one round trip late as a
    correction.
  - Timed links would feel bad online without fixing this, so it is part of the plan (phase 3).
- **Performance headroom** (measured live in Studio, 2026-10-04, during a 2-player fight):
  - Client: 60 fps; draw 1.12 ms (the fight 0.77 ms, the HUD 0.21 ms).
  - Server: 0.09 ms per step.
  - Network: 0 prediction corrections; 60 Hz snapshots at 6.5 KB/s in.
  - There is plenty of room for more poses and effects.

## The mechanics

All numbers are starting values in `web/src/config.js`, under one new `COMBO` block. They will be
tuned in playtests.

### 1. Timed links ("perfect" links)

**The rule.** A follow-up is perfect when its button was pressed **during the previous move's strike**:

- the press falls between that move's first active frame and `PERFECT_LATE` (4) frames after its
  last one;
- and the move then lands.

A press during the wind-up (a mash) still chains, exactly as today, but it is an ordinary link.

**Why the window is measured on the attacker's own move.** The client draws your fighter from
local prediction, so your own swing is on screen with no lag. Inputs reach the server as numbered
frames, played back in order (`RemoteInput`), so the server judges the press on the same frame
the player saw. The window works the same at 10 ms and at 150 ms of ping.

The window is 5–7 frames wide, depending on the move's active length. That absorbs the one frame
of precision that input coalescing can cost.

**The reward for a perfect link:**

- the follow-up's startup is 2 frames shorter (never below 2);
- it does +1 damage;
- it gives +25% more ultimate charge;
- and it emits a `perfectlink` event, which draws a gold flash and an afterimage.

The faster startup is what turns some "trap" routes into true combos. It is measured, not assumed
(see Testing).

**How it is detected.**

- `Fighter.applyInput` already stamps a press into `buffer`. We add `pressedAt[b] = frameCount`
  alongside it, so a press's frame survives the buffer.
- `_chainInto` compares `pressedAt` with the frame the current move's strike started.
- The result is kept on the fighter as `linkPerfect`, plus `perfectStreak`, the number of perfect
  links in a row.

### 2. Air strings and cancels

**Air chains.** Aerials gain `chains` and `chainsHeavy` in the weapon data, in the same shape the
ground lights use. `_stepAttack` already runs `_chainInto` for any move, so an aerial with
`chains` chains on hit with no new engine code.

**Two weapon routes everyone learns:**

- `AirNeutral → AirForward → AirUp`, the carry;
- `AirForward → AirDown`, the spike route.

Each weapon's exact tree is in the per-weapon table below.

**The jump cancel.**

- After a move with `cancels.jump` has **landed** and its active frames are done, Jump cancels
  its recovery into a jump.
- On launchers (LightUp, some SigNeutrals), this is how a ground string becomes an air string.
- It spends the jump normally.

**The dodge cancel.**

- After a move with `cancels.dodge` has landed, Dodge cancels its recovery into a dash on the
  ground or a directional air dodge in the air. This is the chase.
- In the air it spends the air dodge, so it is a real resource decision.
- It is on hit only. A whiffed move still has its full recovery, which is where the skill (and
  the risk) is.

### 3. Finisher strings

**Two new moves per weapon:**

- `Finisher` on the ground, at the end of the weapon's longest route;
- `AirFinisher` at the end of its air string.

**They only open on a perfect streak.** A finisher appears in a move's chains only when every
link of the string so far was perfect. The data shape is `chains: { neutral: 'LightNeutral3',
finisher: 'Finisher' }`, where `finisher` is taken instead of the ordinary branch when
`perfectStreak` covers the whole string.

This is the long-string skill: Light, Light, Light, then Light again on time gives a fourth hit
that does not exist for a masher.

**Finishers are combo enders:**

- big knockback, but a lower kill percent than a raw signature, so they reward the route rather
  than replace the signature;
- and a heavier hit-freeze (hitlag +3) for impact.

They still get measured in `combo.test.mjs` like every other route.

### 4. Defence: scaling and the combo break

**Combo scaling.**

- The victim counts `comboHits`, the hits taken without becoming actionable in between. It resets
  the first frame they can act.
- From the 3rd hit, each hit does less damage: ×(1 − 0.08 × (hits − 2)), floored at ×0.5.
- **Knockback is not scaled.** Kills stay where the balance tables put them; scaling only stops a
  long string from adding 80%.

**The combo break.**

- After the 4th hit in a combo, a Dodge pressed **during that hit's freeze** breaks out. The
  freeze is the hitlag, 4–12 frames, and it is the same input as a tech, with its own window.
- The victim bursts free: brief invincibility, and the attacker is pushed back.
- They cannot break again for 6 seconds (`breakCooldown`), shown on the HUD.
- **It is a read, not an escape hatch.** Pressing Dodge early (during the 3rd hit, or mashing)
  locks the break out for that combo. The defender has to time it too.

## The animations

All 12 weapons need distinct poses for every new and existing combo step. Here is the plan.

### New pose families

They live in `web/src/render2d/channels.js` (the body) and are ported to `Channels.luau`. Both
are held by `channel-parity`.

| Family | Used by | The pose |
|---|---|---|
| `jab2` | LightNeutral2 | Backhand return: the arm comes back across the body the opposite way, and the torso counter-rotates |
| `jab3` | LightNeutral3 | Stepping cross: the back foot drives, the hips turn through, and the lean is bigger than the first jab |
| `side2` | LightSide2 | Follow-through spin: a pivot on the front foot into a second strike |
| `finisher` | Finisher | Full-body commitment: a jump-in overhead or a spinning cleave (by weapon class), a long contact hold, and an overshooting settle |
| `air2` | the 2nd and 3rd links of an air string | A flip-cut: the body inverts slightly, a tucked roll into extension |
| `airfinisher` | AirFinisher | A spike or a slam: arms overhead into a downward drive, with stretch-then-squash |
| `cancel` | jump or dodge cancel | A 3-frame snap out of the follow-through: hips first, weapon trailing (overlapping action) |
| `breaker` | combo break | The arms throw out, the body spreads into an X, then settles |

The existing `jab`, `side`, `up`, `down` and air families stay for the first hits.

**How a move picks its family.** Moves declare it in data (`pose: 'jab2'`), falling back to the
current prefix rule. `gen-data.mjs` carries `pose` into the generated Luau automatically, so
there is one place to say it.

**Weapon swings.** Each family needs a swing arc per weapon in `web/src/render2d/weapons2d.js`
`SWING`, ported to `WeaponPose.luau`. That is 6 attack families × 12 weapons = 72 arc entries.
Two rules carry over from what exists:

- thrusting weapons map through `THRUSTABLE` (Pike, Longbow, Blasters thrust their `jab2`,
  `jab3` and `side2`);
- the Flail's out-and-behind overrides in `SWING_BY_MOVE` extend to its new moves.

**Feeding the art pipeline.** The manifest in `web/src/data/animations.js` gets two templates:

- `link`: anticipation is short, because the previous move is the wind-up;
- `finisher`: a sig-length tell with a held contact.

The production doc and the placeholder sprites then cover the new moves automatically.

### Roblox-only presentation

This layer sits over the parity-held modules, the same way FxPlayer and ShieldArt do.

- **The perfect link:**
  - a gold flash at the contact point;
  - a one-frame afterimage of the fighter (a `Canvas2D.tinted` silhouette, already built);
  - a rising pitch on the hit spark per streak step.
- **The finisher:**
  - a weapon-class impact two sizes up;
  - a screen-edge flash;
  - the existing camera shake at heavy strength.
- **The combo break:** a shockwave ring in the victim's shield colour, and the attacker skidding
  back.
- **A HUD combo counter** (`Hud.luau`, as ScreenGui):
  - hit count and total damage beside the attacker's portrait;
  - a "PERFECT ×3" tag while the streak holds;
  - the break cooldown on the victim's card.
- **Move list:** the in-game combo tree is read from data (as `web/src/ui/menus.js` does), so
  finisher routes appear in it automatically.

## Per-weapon combo design

Every weapon gets the same structure, shaped to its archetype:

- two ground routes, one ending in a Finisher and one in a launcher with a jump cancel;
- one air string, ending in an AirFinisher.

The names are working titles.

| Weapon | Archetype | Ground finisher route | Air string → AirFinisher | Cancels |
|---|---|---|---|---|
| Sword | All-rounder | Slash, Backslash, Cross Cut, **Judgement** (rising double cut) | Spin Cut → Arc Slash → **Falling Star** (dive slash) | jump on Rising Cut; dodge on Riposte |
| Battle Axe | Heavy bruiser | 3-hit, **Headsman** (overhead chop, ground bounce) | 2-link → **Guillotine** (spike) | jump on up-light only |
| Warpike | Spacer | Thrust, thrust, sweep, **Impale** (driving lunge) | Thrust → **Pole Vault** (vaulting kick) | dodge on side lights |
| Scythe | Reach / combo | 4-step reaping string, **Harvest** (full spin) | 3-link → **Reaper's Fall** | jump and dodge, both cheap: it is the combo weapon |
| Daggers | Combo monster | Longest string (5), **Thousand Cuts** (flurry) | 3-link → **Carve** (cross spike) | jump and dodge on every light |
| Gauntlets | Rushdown | Jab, jab, hook, **Haymaker** | Knee → **Meteor Fist** | dodge on everything: the chase is its identity |
| Hammer | Superheavy | 2-hit, **Earthquake** (stomp-slam) | 1-link → **Anvil Drop** | none: it trades combos for armour |
| Flail | Space control | Out, return, circle, **Wrecking Ball** (full orbit) | 2-link → **Pendulum** | jump on launcher |
| Shield | Counter attacker | Bash, bash, **Bulwark Rush** (shield charge) | 2-link → **Aegis Crash** | dodge after a counter only |
| Longbow | Precision zoner | Close-range strike string, **Point Blank** (charged close shot) | 1-link → **Rain Shot** (down volley) | dodge on hit to make space |
| Blasters | Zoner | Pistol-whip string, **Double Tap** | 1-link → **Recoil Jump** (shots down, user rises) | dodge on hit |
| Grimoire | Heavy zoner | Glyph string, **Seal** (rooting rune burst) | 1-link → **Starfall** | jump on launcher |

Zoners and superheavies get shorter strings and fewer cancels. Combo weapons get the longest.
This keeps the roster's identities, and every weapon's header comment gets the measured
CONFIRM/trap table it already has for its signatures.

## What phase 2 changed (measured, then decided)

Measuring each route through the engine (`routeAt` in `web/test/balance.mjs`) changed four things
in this design.

- **The chase.** Every hit sends its victim away, so no chained aerial ever reached the next one.
  Fixing that in data would have meant weakening every aerial in normal play.
  - The fix: a timed air link, or the first aerial within 24 frames of a cancel, carries the
    attacker toward the fighter just hit (`COMBO.chaseFrames`, `chaseSpeed` 48 studs/s).
  - It is aimed so the new move's hitbox meets where the victim will be.
  - Mashed links do not chase, so mashed air strings fall apart. `combo.test.mjs` asserts both
    halves.
- **Finishers cannot be broken.** The ground finisher is the 4th hit of its route, and the break
  opens on the 4th hit. So a defender who knew the freeze would have broken every finisher. The
  break is now for the long combos (launcher, cancel, air string) that reach hit 4 before their
  finisher does.
- **One cancel per combo.** A greedy attacker found a 14-hit Longbow loop: Bowstave dodge-cancelled
  into a dash, re-opened with Pierce, then the string run back to Bowstave and cancelled again.
  Now, once a fighter has cancelled, they cannot cancel again until their victim is out of the
  combo. No weapon holds anyone past 6 hits in the loop check, whose limit is 8.
- **Route shapes that measurement moved:**
  - Axe and Flail finish off LightNeutral2: neither one's full light string is a true combo.
  - Scythe's air string starts from Long Reap: Whirl's 12 active frames lose the victim before the
    chain opens.
  - Shield's cancel is on its counter burst (`counter.cancels`).

The `pose` fields moved to phase 4, where they are first read, so no data sits unused in between.
Each weapon's header now quotes its timed routes (`ROUTE ... CONFIRM`), checked against the
measurement the same way the signature tables are.

## Implementation order

Everything below lands in **both builds in the same commit** (the AGENTS.md rule): web first,
then the Luau, with `check.sh` holding them together.

**1. Engine core (web).**

- `pressedAt`, perfect-link detection, `perfectStreak`, `finisher` branches, `cancels`,
  `comboHits` scaling, the break, and the `COMBO` config.
- New events: `perfectlink`, `combobreak`, `finisher`.
- Engine tests, mutation-checked.

**2. Combo data for all 12 weapons.**

- Air chains, `cancels`, 24 new moves (`Finisher` and `AirFinisher` per weapon), and `pose`
  fields on every chain step.
- Balance pass: `combo.test.mjs` extended (below), and kill percents re-measured with
  `balance.mjs`.

**3. Port and networking.**

- `Fighter.luau` and `Combat.luau`.
- `Snapshot` gains `moveLanded`, `perfectStreak`, `comboHits` and `breakCooldown`.
- **`moveLanded` in the snapshot is the prediction fix.** After a reconcile, the predictor replays
  your inputs knowing the hit landed, so your chain is predicted on the right frame instead of
  arriving as a correction.
- The AI learns to use perfect links and cancels at hard level, partly so that the parity traces
  actually exercise them.
- `check.sh` green.

**4. Animations.**

- The 8 pose families, the 72 weapon arcs, and the `pose` field in `channels.js` and
  `weapons2d.js`, ported to Luau.
- `channel-parity` covers them, and new direct assertions cover what parity cannot (below).
- A contact sheet per weapon from `tools/render-fight.luau`, reviewed frame by frame.

**5. Roblox presentation.**

- Perfect-link, finisher and break effects; the HUD combo counter and break cooldown; the move
  list.

**6. Playtest in Studio with you.**

- Tune the windows, the scaling and the finisher strength.
- PerfMonitor checked during long combos.

## Testing: what each piece must prove

Every new test is mutation-checked: break the code, confirm it fails.

**Timing.**

- A press during the strike is perfect; the same press one frame before the strike is not.
- Mashing (a press every frame) never produces a perfect link.
- A perfect press on a whiff gives nothing.

**Routes**, asserted against the engine in `combo.test.mjs`:

- every advertised perfect route and air string is a true combo across its stated percent range,
  against a victim who spot-dodges on their first actionable frame;
- the same route mashed is not;
- a finisher is unreachable without a perfect streak.

**Cancels.**

- Jump and dodge cancel only after a landed hit and only on moves that declare it.
- A whiff keeps its full recovery.
- A dodge cancel in the air spends the air dodge.

**Scaling and break.**

- Damage per hit follows the formula and floors at ×0.5; knockback is unscaled.
- The break works from the 4th hit only, only inside the freeze, never twice inside the cooldown,
  and an early press locks it out.
- **No infinites:** a search over every weapon's chains, with perfect links and cancels, finds no
  loop the break cannot end.

**Animations, asserted directly** (parity proves the two builds agree, not that they are right):

- consecutive chain steps have visibly different poses (the arm angle at contact differs by more
  than a threshold);
- every move resolves to a family;
- every family has an arc for every weapon;
- a finisher's contact hold is longer than a light's.

**Prediction.** With `moveLanded` in the snapshot, a chained attack is predicted on the server's
frame (corrections stay at 0 in `net-smooth`'s replay).

**Performance.** Frames in the worst combo frame stay under the `ult-fx` budget, and the new
effects respect the sprite build budget.

## Risks and open questions

- **Window width online.** Measuring on your own swing makes timing latency-independent in
  principle. The real feel needs a playtest at simulated latency. Studio can add it under Network
  settings; I would ask before changing that.
- **Balance churn.** Faster perfect startups and new finishers move every weapon's confirm table.
  The per-weapon headers are re-measured, not edited by hand.
- **Prediction of the hit itself.** Phase 3 makes the chain correct after the server confirms the
  hit. Predicting the hit locally (checking your hitbox against the drawn opponent) would make it
  instant, but risks a visible take-back on a miss. It stays a follow-up, decided by how phase 6
  feels.
- **Readability.** A HUD counter plus effects on every perfect link could get loud in a 4-player
  match. The effects scale with streak length rather than firing at full strength every time.
