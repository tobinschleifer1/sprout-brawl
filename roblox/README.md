# Roblox build

This folder is the Roblox Studio version of Sprout Brawl. The web build in `../web` is the playable
prototype; this path ships the same design on Roblox, following sections 4 and 5 of the design
document (`../docs/design.html`) and the weapon system in section 0.

Nothing here is required to play the web build.

## Status

| | |
|---|---|
| Toolchain | installed (Rokit 1.2.0, Rojo 7.7.0, luau-lsp 1.69.0, Lune 0.10.5) |
| `default.project.json` | written — `rojo build` produces a place file |
| `src/shared/Config.luau` | ported, all constants |
| `src/shared/Knockback.luau` | ported, verified numerically identical to the JS |
| Everything else | not started |

```bash
./check.sh          # type-check the Luau tree, then verify parity with the JavaScript
rojo serve          # sync into Studio (needs the Rojo Studio plugin)
rojo build --output SproutBrawl.rbxl
```

### Parity with the JavaScript

`web/src/engine/knockback.js` is the source of truth for the damage model. `tests/parity.luau`
checks **25,995 values** — `launchSpeed`, `hitstun`, `blockstun`, `hitlag` and the full DI-bent
`velocity` across a grid of bases, growths, damages, percents, weights, angles and stick directions
— against a fixture generated from the JavaScript, and fails on any drift. Run it with
`lune run tests/parity`, or via `./check.sh`.

Regenerate the fixture after any change to the JS damage model:

```bash
cd ../web && node --input-type=module -e "
import * as K from './src/engine/knockback.js'; import fs from 'fs';
const launch=[]; for (const base of [8,12,16,20,26,30,32,34]) for (const growth of [0,0.8,1.6,2.4,3.2,4.4,5.2,5.7])
 for (const damage of [1,3,5,8,12,15,17]) for (const pct of [0,37,80,113,150,199,300]) for (const weight of [90,96,100,108]) {
   const L=K.launchSpeed(base,growth,damage,pct,weight); launch.push([base,growth,damage,pct,weight,+L.toFixed(9),K.hitstun(L)]); }
const velocity=[]; for (const l of [8,20,33.5,45,60,88]) for (const a of [20,40,55,70,88,275]) for (const f of [1,-1])
 for (const di of [null,{x:0,y:1},{x:0,y:-1},{x:1,y:0},{x:-1,y:0},{x:0.5,y:-0.5}]) {
   const v=K.velocity(l,a,f,di); velocity.push([l,a,f,di?di.x:0,di?di.y:0,di?1:0,+v.vx.toFixed(9),+v.vy.toFixed(9)]); }
const misc=[]; for (const d of [0,1,2,3,5,8,12,15,17,20,30]) misc.push([d,K.blockstun(d),K.hitlag(d,false),K.hitlag(d,true)]);
fs.writeFileSync('../roblox/tests/knockback-fixture.json', JSON.stringify({launch,velocity,misc}));
console.log('fixture regenerated');"
```

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

- `web/src/config.js`, `knockback.js`, `data/characters/*.js`, `data/stages/index.js`, `data/items.js` are pure data and
  arithmetic. They become ModuleScripts under `ReplicatedStorage/Shared` unchanged in substance.
- `engine/fighter.js`, `combat.js`, `stage.js`, `match.js` become the server-authoritative modules described in
  design section 5 (`CombatServer`, `HitboxService`, `StageService`, `MatchService`). The hitbox rectangles become
  `workspace:GetPartBoundsInBox` queries against hurtbox parts.
- `render/rigs.js` is replaced by the Blender pipeline in design section 4 (skinned meshes, R15-named bones, 20 clips).
- `ui/*` becomes ScreenGuis; `audio/*` becomes uploaded OGG assets referenced from an `Audio` module.
- Data persistence, the store, the battle pass, matchmaking and anti-exploit are Roblox-only and are specified in
  design sections 5.7, 5.8, 6 and 9.

`src/` here is an empty Rojo-style skeleton (`shared`, `server`, `client`) ready for that work.
