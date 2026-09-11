# Stage hazard design review

The standing brief for the scored design review of the stage hazards, plus the history of what
each round found. Kept so a round can be restarted verbatim at any time, including from a session
that has none of this in context.

## Process

A 2D visual game design agent scores the work. Three rounds; stop early if any round scores above
8. If 8 is not reached after three, carry on anyway.

| Band | Meaning |
|---|---|
| under 4.5 | bad design |
| 4.5 – 6.5 | getting better, not good enough |
| 6.5 – 8 | almost there, only a few iterations left |
| 8 – 10 | workable |

Score each of the 10 hazards, the ambient layer, and one overall.

## Round history

### Round 1 — **6.5 / 10** ("almost there")

Three hazards measured at near-invisible contrast against their own stage's palette, and two of
the findings were violations of rules written at the top of the very files that broke them.

| # | Finding | Fix |
|---|---|---|
| 1 | Foundry Floor's ambient `embers` collided with its `emberdrift` hazard — same rising motion, same orange family, same layer, ambient spread full-width through the hazard's own columns | Ambient replaced with `ash`: grey flakes falling **downward**. Differs on direction and value, the two channels the eye reads fastest |
| 2 | Crosswind's warning was a fainter copy of its gust (0.15 vs 0.28 alpha, identical streaks) | Warn and gust are now different pictures in different places — warn is dark grit on the **deck** plus leaning cable stays and a downwind pennant; gust is streaks in the **sky** only |
| 3 | Antenna arc's warn glow ~1.08 contrast — pale blue on a pale blue sky | Violet-white `#E6CFFF` over a `#8B5CE0` halo; violet is the one hue absent from Rooftops' palette. Arc also moved y=40 → y=44, because the crane tier at 33 put a standing head at 38.2, inside a band centred on 40 |
| 4 | Sandfall grains ~1.05 contrast — tan on a tan palette | Grains `#8A6E45` / `#6E5636`, a full value step darker; pre-pour trickle alpha floor 0.15 → 0.35 |
| 5 | Dust devil and sandfall footprints overlapped at the mesa lip | Funnel gained `eastStop: 9`. Footprints now dustdevil x−57..25, sandfall x25..34 |
| 6 | Rogue wave had the shortest telegraph and blended into the tide it rides on | `warn` 1.6s → 2.4s, plus a bright `#E8F6FB` leading face up the crest |
| 7 | Polish | Vent billow tail `#DCD6CE` → `#B8ADA0`, warn-puff alpha floor 0.45; slag drops got a `#5A2E18` rim and a bigger highlight; sprinkler slick cells overlap with a feathered skirt and the warn has 7 drips not 4; dust devil rings saturate to `#8A7448` at the base; the tide's swell is two incommensurate sines so it never visibly loops |

Changed in the same round, independently of the review:

- **Tide contrast rebuilt.** The old water composited to rgb(55,101,126) against a sky of
  rgb(51,86,110) — 4/15/16 per channel, and *lighter* than the sky, which reads as haze. Now a
  ramp: deep `#10303C`, three shelves, a hard `#0A2029` band under the crest, white + accent foam.
- **New test** — the waterline must sit at least 25 luminance below its darkest sky stop, the
  under-crest band must be the darkest part of the water, and the foam must clear the sky by 90.
- **New test** — "no two hazards fight over the same ground". Each hazard's force footprint is
  measured *in isolation* (the stage is rebuilt carrying only that hazard) and compared as an x/y
  box. Crediting every active hazard with the whole range measures nothing.
- **Soak frame cap raised** 15,600 → 28,800, after measuring that hazards do not lengthen matches
  (median 9,632 with vs 9,737 without) but do add ~7% to the tail (p90 12,295 vs 11,438). The old
  cap sat 1.2× above the natural maximum and tripped on a slow seed about one run in five.

### Round 2 — not scored

Launched, then stopped by request before it reported. It had got as far as confirming the new
`ash` ambient reads as distinct from the ember columns. Nothing it did was written to the repo; the
tree is exactly as round 1's fixes left it. Relaunch it with the brief below.

### Round 3 — not started

## Open, deliberately not fixed

- **A bot reached 456% with all three stocks intact** in a stalled soak match — it was never
  killed once. This is bot reachability, not a hazard: it predates the hazard work and the hazard
  footprints are clear of it. Worth its own pass if bots need to hold up in 4-player.

## The brief (paste as the agent prompt)

> You are a senior 2D environmental / VFX designer on platform fighters (Brawlhalla, Rivals of
> Aether, Smash). Review and SCORE the stage hazards in a 2D platform fighter.
>
> PROJECT: `/Users/tobyschleif/roblox 2d fighting game/web`
>
> **Constraints set by the game's owner.** Hazards are PRESSURE ONLY — nothing may KO on its own;
> they can throw you into a blast zone, but the kill is always the geometry finishing what the
> hazard started. The two ranked stages (Foundry Floor, The Span) get SUBTLE hazards. Scope covers
> hazards, moving stage parts, ambient weather, and a signature hazard per stage.
>
> **Read the real current code, do not trust any summary:** `src/engine/hazards.js` (the registry —
> vents, slagfall, sprinkler, antennaarc, dustdevil, sandfall, tide, roguewave, crosswind,
> emberdrift); `src/render2d/hazards2d.js` (the visuals — the main thing being scored);
> `src/render2d/ambient2d.js`; `src/data/stages/index.js` (tuning, and each stage's `palette` /
> `skyStops` / `ambient`); `src/engine/fighter.js` (the `env` bag, `ENV_MAX`, `_physics`,
> `_friction`); `src/render2d/renderer2d.js` (`frame()` draw order); `test/hazards.test.mjs`.
>
> **Run things.** `npm test` runs all suites. `node test/hazards.test.mjs` and
> `node test/soak.test.mjs` run individually. Write throwaway `.mjs` scripts under `web/.tmp/`
> importing `./test/harness.mjs` to measure anything — how far a vent lifts, how long a slick
> lasts, how far the funnel carries, what a gust does to a recovery. Ground every claim in measured
> numbers. Delete the scratch files afterwards.
>
> **Look at it.** `node serve.cjs 8123 &` then `http://localhost:8123/hazards.html` — every hazard
> at quiet / WARNING / EVENT captured at the PEAK of each phase, plus a live canvas per stage.
> `maps.html` shows stage layouts to scale. Use the browser tools; if the pane is unstable, say so
> explicitly and judge the visuals from the drawing code against each stage's palette.
>
> **Score** each of the 10 hazards 1–10, the ambient layer 1–10, and ONE overall 1–10 using the
> bands above. For each: the score, what works, and SPECIFIC fixes with exact numbers.
>
> **Judge on:** does it look like the thing it is (at 480×270, shape and contrast are all you
> have); is the WARNING as legible as the event, and is it a different picture rather than a dimmer
> one; contrast against that stage's own palette — compute it; does the interaction earn its place
> and differ from the other nine; is it fair (telegraph length, escapability, can it cheat someone
> out of a stock); 4-player behaviour and whether two hazards on one stage compete for attention;
> ambient-vs-hazard confusion per stage; drawing-code correctness and the zero-allocation claim.
>
> Finish with a ranked list of what is still worth changing, and state plainly whether the set is
> shippable. Be direct and critical — a 6 with a concrete fix list is worth far more than a 9 with
> praise.

When relaunching a later round, prepend the round history above so the agent verifies that each
previous fix actually landed and actually solved what it claimed, rather than re-deriving it.
