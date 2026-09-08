# Sprout Brawl

An original 2.5D platform fighter about plants, fungi and the small things that live among them.
Eight characters, six stages, percent-based knockback, ring-outs on four sides.

The full design document is in [`docs/sprout-brawl-design.html`](docs/sprout-brawl-design.html).
Every number in the game (frame data, knockback, stage layouts, blast zones) comes from that document.

## Play it now (web build)

The `web/` folder is a complete, playable Three.js build. It needs Node and a browser, nothing else.

```bash
cd web && node serve.cjs
```

Then open http://localhost:5173

- **Quick play**: you against a bot on Potting Bench.
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

### Characters

The eight fighters are Blender-built models loaded as glTF. Each is a Python script under
`blender/characters/` that composes real geometry, binds every part rigidly to an R15-named bone,
renders turnaround previews, and exports `.glb` into `web/assets/characters/`.

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python blender/characters/thornlock.py
```

Rebuild all eight:

```bash
for c in thornlock capnspore sunbeam kelpin cacto duststorm mycel frostbud; do \
  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python blender/characters/$c.py; done
```

Each build writes three things:

| Where | What |
|---|---|
| `blender/blends/<name>.blend` | Openable Blender scene: mesh, armature, materials, camera, lights |
| `web/assets/characters/<name>.glb` | The model the game loads |
| `blender/previews/<name>_*.png` | Side, three-quarter and front renders |

The `.blend` files are an output, not the source. Editing one by hand works, but the next script
run overwrites it. The Python script is the source of truth.

**To work on a character inside Blender's interface** rather than headless: open Blender, go to the
Scripting workspace, open `blender/characters/<name>.py`, and press Run. It builds the character
live in the viewport, and you can keep editing and re-running.

Previews are rendered side view first, because the game is played side-on and the
profile is the silhouette that matters. Colour is carried by material NAME, not baked pixels, so
the web build swaps palettes per skin at load time. Roles: `primary`, `secondary`, `tertiary`,
`accent`, `glow`, `dark`, `eyeWhite`, `eyeDark`.

The art direction these follow — silhouette rules, proportion budgets, the colour system, the
stage plan — is in the art bible, published as an artifact and summarised in `docs/`.

Every character stays inside an 8,000-triangle budget; the build prints `OVER_BUDGET` if not.

### What is in the web build

- `src/config.js` – global constants (frame rate, gravity, shield, ledge, dodge, grab and throw numbers)
- `src/engine/knockback.js` – the launch, hitstun, blockstun and hitlag formulas
- `src/data/characters/*.js` – one file per character: stats, moves with frame data and hitboxes, mechanic, palette and skins
- `src/data/stages/index.js` – platform layouts, blast zones, hazards, spawns
- `src/data/items.js` – Seed Bomb, Trowel, Watering Can
- `src/engine/fighter.js` – the fighter state machine (movement, jumps, shield, dodges, ledge, grabs, recovery, hitstun, tech, mechanics)
- `src/engine/combat.js` – hit resolution, projectiles, summons, bursts, fields, counters, items
- `src/engine/stage.js` – platform collision, ledges, blast zones, hazards (vents, sinking leaves, moving planters, sprinkler, dust devil, tide)
- `src/engine/match.js` – countdown, KOs, respawns, stocks and team pools, timer, sudden death, results
- `src/engine/ai.js` – bots
- `src/render/models.js` – loads the Blender `.glb` characters, swaps palettes by material name, builds the outline shell
- `src/render/toon.js` – banded toon ramp, fresnel rim light, inverted-hull outline
- `src/render/rigs.js` – skeletal posing driven by the animation channels, plus primitive fallback rigs for anything without a model
- `src/render/*` – Three.js scene, stage geometry, effects
- `src/ui/*` – HUD and menus
- `src/audio/*` – synthesised sound effects and a procedural chiptune sequencer with the final-stock intensity layer

Balance changes are data changes: edit a character file and reload.

## Roblox build (paused)

The `roblox/` folder holds the plan and the toolchain install steps for shipping the same design in Roblox Studio with Blender-made assets. See [`roblox/README.md`](roblox/README.md). Nothing in the web build depends on it.
