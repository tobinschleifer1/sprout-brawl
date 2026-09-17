# Review brief — six new weapons, round 1

Read `README.md` in this folder first for the bands and the house rules. **Measure everything; do
not grade effort.** Every number below is a CLAIM TO VERIFY, not a fact — my own measurements have
been wrong in several earlier rounds, and finding that is the job.

**Do not edit anything under `src/`, `test/` or `docs/`.** Scratch scripts go in `web/.tmp/` and are
deleted when you finish. If something needs changing, describe it with exact numbers.

---

## What this round is

The roster went from six weapons to twelve in one change (commit `37f2a79`). The owner supplied a
brief — `new_weapons.txt` — giving each weapon a name, an archetype, a stat line, a combo tree and
a signature description. **Frame data, hitboxes, aerials, ultimates, mechanics and all art are
mine**, and they are what needs judging.

Six weapons is a wide scope for one round. **Prefer breadth: find the worst problem on each weapon
rather than every problem on one.** If you run short, the order of value is: does each weapon feel
like the thing the brief describes → is any one of them dominant or unplayable → does the art read.

### Where I deliberately departed from the owner's brief

These three are judgement calls and are fair game to disagree with:

1. The brief's stat line says **"Momentum"** on five of the six, but the signature text describes
   four different mechanics, and Momentum is specifically bought by running. Each weapon took the
   mechanic its own signature describes: `Surge` (Gauntlets' Overdrive and the Daggers' Bloodrush —
   one counter, tuned opposite ways), `Draw` (Longbow), `Snare` (Flail). Hammer keeps Momentum and
   Shield keeps Brace, as asked.
2. The brief's **"Ground Slam +Heavy -> Earthshatter"** was dropped. Earthshatter is 30 frames of
   startup off a 20-frame recovery; I could not find a percent at which anything reaches it.
3. The brief's **"Shield Jab +Heavy -> Counterguard"** was dropped, because a counter has no hitbox
   at all — it is a window that converts an incoming hit — so no combo can connect into it.

---

## Files to read — this list is complete, you should not need others

| File | What to look at |
|---|---|
| `web/src/data/weapons/gauntlets.js` | whole file — header table, frame data, the `Surge` tuning |
| `web/src/data/weapons/hammer.js` | whole file — note the two `crater` blocks and the shield multipliers |
| `web/src/data/weapons/longbow.js` | whole file — `Draw`, the `charge` on Power Shot, the `starfall` ultimate |
| `web/src/data/weapons/flail.js` | whole file — the two-hitbox out-and-back moves, `kind: 'vortex'` on Snare |
| `web/src/data/weapons/shield.js` | whole file — `kind: 'counter'` on Counterguard |
| `web/src/data/weapons/daggers.js` | whole file — the four-link light string |
| `web/src/engine/fighter.js` | **only** the `Surge`, `Draw` and `Snare` branches: search for those three strings (mechanic init, `_mechanicsFrame`, the spend path in `startMove`, `speedMul`, `resource`) |
| `web/src/engine/combat.js` | **only** the `Snare` block inside the `kind === 'vortex'` branch, and the `C.minDamage ?? 1` line in the slam/crater branch |
| `web/src/render2d/weapons2d.js` | `SWING_BY_WEAPON` entries for Hammer / Flail / Daggers, the six new shape functions, and the six new branches in `ultimatePose` |
| `web/src/render2d/channels.js` | **only** the six new branches in `ultChannels` |

Do not read the original six weapon files unless you are comparing balance; the numbers you would
get from them are in the tables below.

---

## Commands

```bash
cd "/Users/tobyschleif/roblox 2d fighting game/web"
npm test                      # everything, ~90s at twelve weapons, 302 checks
node test/combo.test.mjs      # ~35s — prints the full MEASURED confirm/trap table for all twelve
node test/ultimate.test.mjs   # ~20s — kill bands, shield checks, ultimate resolution
node test/weapons.test.mjs    # ~25s — frame-data consistency, 144 weapon pairings
node test/geometry.test.mjs   # ~1s  — traces the real drawing code, blade-vs-hitbox angle
```

**Do not run `test/soak.test.mjs`.** `npm test` already covers correctness.

To look at the animation: `node serve.cjs 8123 &` then `http://localhost:8123/anim.html`. That page
draws a frame-by-frame filmstrip of every move for every weapon **using the real renderer**. It is
now twelve weapons long and takes ten seconds or so to finish painting — give it time before
scrolling, and scroll to a weapon by its heading.

---

## Claims to verify

### Stat spread across the whole roster (so you need not open twelve files)

```
             weight  run   air   fall  jumps  mechanic   furthest hitbox
Daggers        72   29.0  24.0  30.0    3    Surge            5.2
Gauntlets      78   27.5  22.5  32.0    3    Surge            5.6
Longbow        82   23.0  18.5  34.0    2    Draw             7.7
Blasters       90   24.4  19.4  35.0    2    Spines          26.0
Pike           94   22.3  18.7  36.5    2    Brace           20.0
Scythe         96   20.7  16.6  39.9    2    Bloom            9.7
Sword         100   23.0  18.0  38.0    2    Momentum         7.4
Flail         101   20.5  17.0  38.0    2    Snare            9.6
Grimoire      108   21.2  16.9  33.4    2    Light            4.9
Shield        110   19.5  15.5  42.0    2    Brace            8.7
Axe           118   18.9  15.5  44.8    2    Momentum         8.4
Hammer        125   17.2  14.0  47.0    2    Momentum         6.6
```

The stat lines came from the brief verbatim. The spread widened from 90–118 to 72–125.

### Measured, and printed by the suites above

| Claim | Where to check |
|---|---|
| Every advertised `chainsHeavy` route on all twelve weapons lands at some percent | `combo.test.mjs` |
| Each new weapon has at least one CONFIRM into a signature that kills | `combo.test.mjs` |
| The header table in each weapon file reproduces exactly — it is generated from the engine | `combo.test.mjs` |
| New signatures kill between 106% and 153% (the old six sit at 97–137%) | `combo.test.mjs` |
| Ultimates deal 22–44% from 4 studs: Hundred Hands 35, Meteor 42, Arrowfall 22, Maelstrom 44, Last Stand 33, Thousand Cuts 34 | `ultimate.test.mjs` |
| No ultimate can be cleanly blocked at any of three probe ranges | `ultimate.test.mjs` |
| Blade points at its own hitbox: Gauntlets 60°, Hammer 54°, Longbow 52°, Flail 58°, Shield 45°, Daggers 49° (Sword 49° for comparison) | `geometry.test.mjs` |
| The weapon stays in the hand: worst gap 0.35 studs on a 5.2-stud fighter | `geometry.test.mjs` |

### Measured combo tables (these are the generated headers; verify they still reproduce)

```
GAUNTLETS  Body Blow +Heavy+side   -> Rush Elbow     CONFIRM 0-180%   kills 126%
           Rising Fist +Heavy      -> Overdrive Blow CONFIRM 0-180%   kills 125%
           Rising Fist +Heavy+down -> Meteor Fist    CONFIRM 20-180%  no KO angle
HAMMER     Overhead +Heavy+side    -> Breach         CONFIRM 20-80%   kills 106%
           Rising Hammer +Heavy    -> Crushing Blow  CONFIRM 60-180%  kills 133%
LONGBOW    Sky Arrow +Heavy        -> Power Shot     CONFIRM 100-180% kills 149%
           Bowstave +Heavy+down    -> Tripwire       CONFIRM 20-40%   kills 150%
FLAIL      Full Circle +Heavy+side -> Reaper         CONFIRM 80-100%  kills 120%
SHIELD     Rising Bash +Heavy+down -> Aegis Slam     CONFIRM 80-160%  kills 153%
           Wall Break +Heavy+side  -> Bulwark Charge CONFIRM 140-180% kills 140%
DAGGERS    Twin Strike +Heavy+side -> Execution      CONFIRM 0-180%   kills 138%
           Rising Blades +Heavy    -> Blade Storm    CONFIRM 0-180%   kills 247%
```

### Decisions I made that are worth challenging

- **Two weapons share the `Surge` mechanic.** The Gauntlets' Overdrive cuts two frames of startup;
  the Daggers' Bloodrush adds five damage and resets on a whiff. I argue that is two mechanics with
  one implementation. It may just be one mechanic on two weapons.
- **Three CONFIRM windows read 0-180%** (Gauntlets ×1, Daggers ×2). Every other confirm in the game
  has a percent window you have to earn. A route that is guaranteed at every percent may be too
  good, or may be fine because the signatures it reaches are small.
- **Blade Storm kills at 247%** and Meteor Fist has no killing angle at all. Both are reachable on a
  0-180% confirm. Check whether "confirms always, kills never" is a dead move or a damage tool.
- **The Hammer's Breach kills at 106%**, the earliest in the game, on a weapon with 125 weight.
  Check the superheavy is not simply the best weapon.
- **The Daggers are 72 weight with three jumps and the best stats in the game.** The intended cost
  is dying about 30% of a stock earlier. Check that is actually the trade and not a free upgrade.
- **The Longbow's `Draw` slows you to 55% while held.** Check the bow can function at all against
  the Gauntlets or the Daggers, who close from across the stage in about a second.
- **The Flail's Snare** attaches for 90 frames and lets either fighter be reeled in. Check it is not
  simply a free kill on anyone standing near a ledge.
- **The Smeltworks pit was resized from 20 to 17.5 studs** to fit the Hammer's jump, the second time
  that stage has been resized for a new weapon. Check the stage is not now trivial.

---

## Score

Score 1–10 for each, then one overall:

1. **Gauntlets** — does it read as rushdown, and is the Overdrive counter worth chasing?
2. **War Hammer** — does "armour breaker" mean anything in play, or is it just a slow axe?
3. **Longbow** — is the draw a real decision, and can it survive being closed down?
4. **Chain Flail** — does the out-and-back arc read, and is Snare interesting or oppressive?
5. **Shield** — is Counterguard a real option given it cannot be comboed into?
6. **Dual Daggers** — is the combo counter the payoff, and is the glass half of glass cannon real?
7. **The twelve-weapon roster** — does anything dominate, fold, or duplicate another weapon?
8. **Art and animation** — do the six read distinctly at gameplay size, and do the ultimates?

Finish with a ranked list of changes and say plainly whether the six are shippable.


---

## Round 1 result — scored 5.5/10 ("getting better, not good enough")

The review found one broken mechanic, one balance outlier, and **three wrong numbers in this very
brief**. All three corrections were verified independently before being accepted:

| Brief claimed | Actually |
|---|---|
| worst hand-to-grip gap 0.35 studs | **0.50** (Hammer, tied with the old Scythe) |
| three 0-180% CONFIRM windows, Gauntlets x1 / Daggers x2 | **four**, split 2/2 |
| Breach at 106% is the earliest kill in the game | the Axe's Wide Arc kills at **97%**. Breach is the earliest *guaranteed-confirm* kill, which is the finding that matters |

### Fixed in round 1

1. **The Chain Flail's Snare was a complete no-op.** It added its pull to `vx`, which `_groundMove`
   and `_friction` rewrite from the stick every frame. Measured over a full 90-frame hold the victim
   moved **0.00 studs** and the attacker moved 29.99 — which is just the flail's own run speed. The
   review's account of the mechanism was wrong (it described a runaway on small inputs, and drove
   the wrong fighter's stick), but the finding was right and the truth was worse: dead in *both*
   directions. Fixed by moving the pull onto `carryX`, the same fix hazard wind needed when
   `_airDrift` was erasing every gust in the game, plus a brace that stops the attacker sprinting
   away from their own pull. Now: 12 studs closes to 0.12 reeling yourself in, 0.36 reeling them in,
   and 12.00 untouched with no input.
2. **A fully drawn Power Shot killed from 37%, and from 21% with Draw banked.** The review only
   flagged this as "worth confirming whether the two charge systems stack"; measured, it was a
   projectile taking a stock at a fifth of the percent anything else needs. A `charge` block
   silently replaces damage, base and growth, and every other measurement in the project reads the
   *uncharged* move. Now 99%, against Overcharge's 129% and Starfall's 106%.
3. **Four CONFIRM windows read 0-180%** — guaranteed from the first hit of the match. All four
   traced to an opener carrying enough `extraHitstun` to cover the signature at zero percent. None
   remain; the tightest is now 60-180%.
4. **Breach nerfed** from a 106% guaranteed-confirm kill to 120%, against the Sword's 111% and the
   Axe's 117%.
5. **Blade Storm** confirmed at every percent and killed at 247%; now 163% on a 60-180% window.
   **Meteor Fist** confirmed and could not kill at any percent; re-angled from 286 to 308 so a spike
   also sends.

Two new checks, both verified to fail when the fix is reverted: a charged move has to stay inside
the roster's kill band, and the Snare has to move somebody in both directions and nobody when the
stick is neutral.

### Still open for round 2

- The review could not measure **whether the Longbow survives being closed down** by the Gauntlets
  or the Daggers, and correctly declined to guess from a small sample. That needs 15+ duels.
- The **Daggers' "dies 30% of a stock earlier"** trade was never independently verified.
- **Two weapons sharing the `Surge` mechanic** was disclosed and not resolved either way.
