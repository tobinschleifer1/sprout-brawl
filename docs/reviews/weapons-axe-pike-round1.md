# Review brief — Battle Axe and Warpike, round 1

Read `README.md` in this folder first for the bands and the house rules. **Measure everything; do
not grade effort.** Every number below is a CLAIM TO VERIFY, not a fact — several of my own
measurements in earlier rounds turned out to be wrong, and finding that is the job.

**Do not edit anything under `src/`, `test/` or `docs/`.** Scratch scripts go in `web/.tmp/` and
are deleted when you finish. If you think something needs changing, describe it with exact numbers.

---

## What this round is

Two new weapons take the roster from four to six. The owner specified the first and left the second
to me.

**Battle Axe** (owner's spec, verbatim): *a massive battle axe that feels heavy in the user's hand
with clear animations of the user swinging and lugging it around.* Two explicit requirements:
- when walking or doing anything other than fighting, the fighter **drags it on the ground**,
  leaving small trails of dirt where the axe meets the floor
- heavy attacks show the axe **brought up to head height with great effort, then swung down
  letting gravity do most of the work**

**Warpike** (my choice). Picked as the axe's opposite: longest reach in the game on the thinnest
hitboxes, thrusts instead of swinging, and a mechanic that rewards standing still where the axe's
rewards moving.

Ultimates were specified as *"a more advanced version of that weapon, or a way to use it in a short
burst"*. Reave is the axe's weight finally winning — three accelerating revolutions. Lance Charge is
the pike telescoping into a cavalry lance for nine thrusts down one lane.

---

## Files to read — this list is complete, you should not need others

| File | What to look at |
|---|---|
| `web/src/data/weapons/axe.js` | whole file (135 lines) — header table, frame data, `drag: true`, the Reave hitbox stack |
| `web/src/data/weapons/pike.js` | whole file (110 lines) — same, plus the Lance Charge reach ramp |
| `web/src/render2d/weapons2d.js` | `SWING_BY_WEAPON` (the per-weapon arcs), the `axe()` and `pike()` drawing functions, and the `Axe` / `Pike` branches inside `ultimatePose` |
| `web/src/render2d/renderer2d.js` | the `wp.drag` block inside `_fighter` — the dirt trail. Nothing else changed here. |
| `web/src/engine/fighter.js` | **only** the three `Brace` branches (mechanic init, the per-frame tick beside Momentum, and the spend path in `startMove`) |
| `web/src/data/stages/index.js` | **only** the Smeltworks `east` platform comment — the pit was resized because the roster's worst jump changed |

Do not read the other four weapon files unless you are comparing balance; if you are, the numbers
you would get from them are in the table below.

---

## Commands

All of these are fast. **Do not run `test/soak.test.mjs`** (48 matches, ~90s) unless you have a
specific reason — `npm test` already covers correctness.

```bash
cd "/Users/tobyschleif/roblox 2d fighting game/web"
npm test                      # everything, ~8s, 190 checks
node test/combo.test.mjs      # 0.2s — prints the full MEASURED confirm/trap table for all six weapons
node test/ultimate.test.mjs   # 0.1s — kill bands, shield checks, ultimate resolution
node test/geometry.test.mjs   # 0.04s — traces the real drawing code, blade-vs-hitbox angle
```

To look at the animation: `node serve.cjs 8123 &` then `http://localhost:8123/anim.html`. That page
draws a **frame-by-frame filmstrip of every move for every weapon using the real renderer**
(`Renderer2D.drawFighterInto`) — body, limbs, weapon and all. It is the fastest way to judge the
animation and it is what the owner will be looking at.

---

## Claims to verify

### Measured, and printed by the suites above

| Claim | Where to check |
|---|---|
| Axe has exactly one guaranteed confirm: Uppercut Swing → Uproot, CONFIRM 60–180%, KO 117% | `combo.test.mjs` table |
| Pike has exactly one: Lunge Point → Pin, CONFIRM 160–180%, KO 135% | same |
| No advertised `chainsHeavy` route on either weapon is inert | `combo.test.mjs` |
| Reave deals 49% and its finisher KOs at 108%; Lance Charge deals 61% and KOs at 112% | `ultimate.test.mjs` |
| Blade points at its own hitbox: Axe 51°, Pike 20° mean error (Sword is 49° for comparison) | `geometry.test.mjs` |
| The weapon stays in the hand: worst gap Axe 0.30, Pike 0.70 studs on a 5.2-stud fighter | `geometry.test.mjs` |

### Stat spread across the whole roster (for balance context, so you need not open four files)

```
           weight   run   furthest hitbox reach
Sword        100   23.0        7.4
Scythe        96   20.7        9.7
Blasters      90   24.4       26.0
Grimoire     108   21.2        4.9
Axe          118   18.9        8.4     <- heaviest, slowest
Pike          94   22.3       42.0     <- Lance Charge's final thrust
```

### Decisions I made that are worth challenging

- **Reave and Lance Charge deal 49% and 61%** where the other four ultimates deal 18–39%. I argue
  a 200-frame multi-hit commitment earns it and that their finishers therefore kill later (108/112%
  vs the single-hit ones' 95–149%). That reasoning may be wrong; 61% is a lot.
- **Pike thrust offsets are capped at 0.7 studs.** A real spear slides through the hands, but this
  renderer's arm is a fixed-length limb, so sliding the prop detaches it — at 3.4 it ended up
  further from the hand than the fighter is tall. The reach lives in the haft instead. Judge
  whether the thrust still reads as a thrust.
- **Smeltworks' pit went from 20 studs to 17.5.** Adding the axe took the roster's worst horizontal
  jump from 24.7 studs to 21.0, so a pit that was 81% of a jump became 95% — uncrossable for the
  weapon most likely to be knocked into it. Check I did not just make the stage boring.
- **Full Extension (pike SigSide) combos from nothing at all.** I claim that is correct for a
  21-frame spacing tool thrown from outside everyone's range. It might just be a dead move.
- **The axe's only fast move is its jab**, and its one confirm hangs off the launcher. Check the
  weapon is not simply unplayable against anyone who rushes it.

---

## Score

Score 1–10 for each, then one overall:

1. **Axe identity** — does it read as heavy? Is the drag legible in motion, and does it cost the
   player something real rather than being decoration? Do the heavies read as lift-and-drop?
2. **Pike identity** — does it read as reach and spacing rather than as a thin sword?
3. **Animation quality** — wind-up, contact, follow-through, and whether the body and the weapon
   agree. Compare against the existing four on the same page.
4. **Reave** and 5. **Lance Charge** — as spectacle and as moves.
6. **Balance in the six-weapon roster** — does either dominate or fold?
7. **Frame data and combo structure** — is one confirm each enough, and are the trap windows real
   options or noise?

Finish with a ranked list of changes and say plainly whether the two weapons are shippable.
