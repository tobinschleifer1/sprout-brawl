# Blockfall

A **2D** platform fighter. Your Roblox avatar is who you look like; the **weapon** you pick is how
you play. Four weapons, six avatars, six stages, percent-based knockback, ring-outs on four sides.

The avatar is cosmetic — every avatar shares one stat line, so a match is decided by the weapon and
by how you use it.

The name lives in [`web/src/data/branding.js`](web/src/data/branding.js); change it there and the
title screen, browser tab and round-start callout all follow.

The full design document is in [`docs/design.html`](docs/design.html).

This project began as **Sprout Brawl**, a 3D fighter with a plant-and-fungus roster. That game
still exists and still plays — it lives in its own folder at `../sprout ball`, with its own copy of
everything. Nothing is shared between the two.

## Play it now (web build)

The `web/` folder is a complete, playable build. Pure 2D canvas — no engine, no build step, no
dependencies. It needs Node (to serve the files) and a browser, nothing else.

```bash
cd web && node serve.cjs
```

Then open http://localhost:5173

- **Quick play**: you against a bot on Foundry Floor.
- **Set up a match**: 2–4 players, stock or timed, free-for-all or 2v2, items on or off, any stage. Slots can be Keyboard 1, Keyboard 2, a gamepad, or a bot at three difficulties.
- **Training**: a still dummy, frame data readout, hitbox display (H), reset (R), and B to make the dummy fight back.

### Controls

| Action | Keyboard 1 | Keyboard 2 | Gamepad |
|---|---|---|---|
| Move | WASD | Arrows | Left stick / D-pad |
| Jump | Space or W | Up or Enter | A |
| Light | J | , | X |
| Heavy (signature) | K | . | Y |
| Dodge / dash | L or Shift | / | B |
| Guard (shield / ledge / pickup) | I or Ctrl | Right Shift | RB |
| Grab | U (or Guard + Light) | M | LB |
| Taunt | T | N | Start |

Up + Heavy in the air is the recovery. Down + Heavy in the air is the ground pound. Esc or P pauses. M mutes music.

### Weapons

| Weapon | Archetype | Weight | Run / Air | Mechanic | Signature KO |
|---|---|---|---|---|---|
| **Sword** | All-rounder | 100 | 23.0 / 18.0 | Momentum — a second of running buys a stronger signature | Crescent Rush 111% |
| **Scythe** | Reach / combo | 96 | 20.7 / 16.6 | Bloom — 5 hits in 4s, then a longer, harder next heavy | Reaper's Arc 113% at the tip, 122% at the handle |
| **Blasters** | Zoner | 90 | 24.4 / 19.4 | Magazine — 6 rounds, one back every 0.75s | Scattergun 140% |
| **Grimoire** | Heavy zoner | 108 | 21.2 / 16.9 | Light — charges only while standing still | Runebrand 120% |

Each has 14 moves: a light string that branches on the direction held for the follow-up, four
aerials, and three signatures. A landed string cashes out into a signature by holding Heavy.

Every confirm percentage quoted in `web/src/data/weapons/*.js` is **measured in the engine**, not
derived from frame data: `confirmsAt()` in `web/test/balance.mjs` runs a real match, lands the
opener, chains the follow-up, and has the victim spot-dodge on their first actionable frame.
`npm test` fails if any advertised route stops connecting.

```bash
cd web && npm test        # 63 assertions: engine, weapons, combo validity
cd web && npm run balance # KO percents and stat spread
cd web && npm run test:soak
```

Weapon icons and swing effects are generated as real `.piskel` documents — see [`pixel/`](pixel/).

### How it is drawn

Everything is painted into a 480x270-ish backbuffer and scaled up with nearest-neighbour sampling,
which is what makes it read as pixel art at any window size. The backbuffer's *height* is fixed so
one game pixel is always the same size; its width follows the window's aspect.

- `src/render2d/renderer2d.js` — camera, parallax, stage, fighters, projectiles, particles, debug
- `src/render2d/weapons2d.js` — the weapons themselves, and how each one animates per move
- `src/render2d/channels.js` — the pose of a fighter for one frame, as plain numbers

Fighters are drawn as jointed 2D puppets rather than sprite sheets, so a new move animates without
new art. Weapon swings are keyframed as `[windup, contact, follow-through]` and interpolated across
each move's real startup / active / recovery, so the arc always lines up with the frames that hit.

**Weapon animations**, per the four archetypes:

| Weapon | Attack animation |
|---|---|
| Sword | swing arcs with a bright smear trail; heavier arcs on signatures |
| Scythe | wider, slower crescent arcs with a long trail |
| Blasters | aim, muzzle flash on the firing frame, recoil kick, bullet tracers |
| Grimoire | a rune ring blooms at the cast point, then a glowing orb travels out |

Signatures add an impact ring and a shower of weapon-coloured sparks on contact, plus screen shake.

To see every attack as a filmstrip at 15x, open <http://localhost:5173/anim.html>. It draws from the
same `weapons2d.js` the match uses, so it cannot drift from the game.

### Repository layout

- `web/` – the playable 2D build. No dependencies, no build step; `node serve.cjs` and a browser.
- `roblox/` – the Luau port: project file, shared modules, a parity test, and a copy of the
  simulation engine kept in sync for translation.
- `pixel/` – the `.piskel` asset pipeline (standard-library Python, no dependencies).
- `docs/design.html` – the design and production document.

### What is in the web build

- `src/config.js` – global constants (frame rate, gravity, shield, ledge, dodge, grab and throw numbers)
- `src/engine/knockback.js` – the launch, hitstun, blockstun and hitlag formulas
- `src/data/weapons/*.js` – one file per weapon: moves with frame data and hitboxes, combo tree, mechanic, stat spread, palette
- `src/data/avatars.js` – the shared base stat line and the cosmetic avatar presets
- `src/data/loadout.js` – composes avatar + weapon into the character-shaped object the engine consumes
- `src/data/stages/index.js` – platform layouts, blast zones, hazards, spawns
- `src/data/items.js` – Blast Keg, Rivet Gun, Bulwark, Spring Plate, Lodestone: one verb each (throw, shoot, hold, place, apply)
- `src/data/branding.js` – the game's name and callouts, in one place
- `src/engine/fighter.js` – the fighter state machine (movement, jumps, shield, dodges, ledge, grabs, recovery, hitstun, tech, mechanics)
- `src/engine/combat.js` – hit resolution, projectiles, summons, bursts, fields, counters, items
- `src/engine/stage.js` – platform collision, walls, ledges, blast zones, hazards (vents, sinking gantry, moving raft, sprinkler, dust devil, tide)
- `src/engine/match.js` – countdown, KOs, respawns, stocks and team pools, timer, sudden death, results
- `src/engine/ai.js` – bots: difficulty is a perception handicap (`sight`, frames of staleness in what a bot sees) plus committed input chains, not an aggression dial
- `src/render2d/*` – the 2D renderer, weapons and animation channels
- `src/ui/*` – HUD and menus
- `src/audio/*` – synthesised sound effects and a procedural chiptune sequencer with the final-stock intensity layer

Balance changes are data changes: edit a weapon file and reload. Then run `npm test` — the combo
suite re-measures every advertised confirm against the engine and fails if a route stopped working.

### Your own art

- **Characters.** The **Characters** screen builds a fighter and saves it in your browser: five
  colours, a head shape, a face, headgear and a chest mark — or draw the parts pixel by pixel and
  the rig animates what you drew. Avatars are cosmetic only; a character you make cannot change a
  single stat.
- **Stage backgrounds.** Drop an image into
  [`web/assets/backgrounds/`](web/assets/backgrounds/README.md) named after a stage — 
  `foundryfloor.png` — and it becomes that stage's sky. No code change and no build step. That
  folder's README covers naming, sizing, the optional per-stage tuning, and how to check it worked;
  `web/backgrounds.html` shows all six stages with a panning camera and tells you which ones picked
  your image up.

## Roblox build

The `roblox/` folder holds the port plan and a self-contained copy of the simulation engine for
translation to Luau. See [`roblox/README.md`](roblox/README.md). Nothing in the web build depends on it.

The toolchain is installed: Rokit 1.2.0, Rojo 7.7.0, luau-lsp 1.69.0, Lune 0.10.5 (on `PATH` via
`~/.zshrc`). Two steps still need Studio's UI: `rojo plugin install`, and Game Settings → Security →
"Enable Studio Access to API Services".
