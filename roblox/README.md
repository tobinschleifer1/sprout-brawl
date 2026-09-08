# Roblox build — paused

This folder is the landing spot for the Roblox Studio version of Sprout Brawl. The web build in `../web` is the
playable prototype; this path is for shipping on Roblox with Blender-made characters and stages, following
sections 4 and 5 of the design document (`../docs/sprout-brawl-design.html`).

Nothing here is required to play the web build.

## Toolchain to install when you pick this up

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
