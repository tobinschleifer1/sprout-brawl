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
| `src/shared/Knockback.luau` | ported, verified numerically identical to the JS (both curves) |
| Everything else | not started |

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

- `web/src/config.js`, `knockback.js`, `data/weapons/*.js`, `data/avatars.js`, `data/stages/index.js`, `data/items.js`
  are pure data and arithmetic. They become ModuleScripts under `ReplicatedStorage/Shared` unchanged in substance.
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
