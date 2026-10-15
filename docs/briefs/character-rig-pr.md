# `feature/character-rig` → `main`

Draft pull-request text. The PR is not opened, and the branch is not merged until the owner says so.

## What this changes, and why

Blockfall's fighters were seven rigid pieces. Arms and legs had no bend, so a kick and a stance
read the same at 26 px tall, and the faces never changed. This branch is the character rework in
`docs/briefs/character-rework-plan.md`, phases 1-4. It also adds two weapons that exist only in
Roblox and makes two performance passes on the Roblox renderer.

**Characters**
- **Kit bodies** (phase 1): the six presets are now kit bodies, kept under their old ids, so saved
  loadouts still resolve.
- **Elbows and knees** (phase 3): twelve body sprites at full detail and eight at half detail.
  The actions are re-posed to use the new joints.
  - The front hand still sits exactly on the weapon grip.
  - Planted feet stay planted.
  - Every sprite reaches the canvas as a rotation plus an axis scale, because Roblox Frames cannot
    shear.
- **Posture** (`Posture.luau`, `PostureArt.luau`): weight shifts through the chest, abdomen and
  pelvis. This answers "the torso looks stiff" without breaking either invariant above.
- **Faces that act** (phase 2): ten expressions, held at least 4 frames and cached at most 128.
  There is no blinking mid-attack. A last-stock face appears only when the match has more than one
  stock.
- **Movement and trailing parts** (phase 4): a walk and run driven by distance, plus jumps and hit
  reactions. Hair, scarves, mantles and coat hems trail the body.
- **Hit flash**: a silhouette where images are cheap, and one box on the Frame fallback.
- **Portraits use the fight's body**: the avatar editor tiles, the lobby list and the kit sheet
  (`KitBody.luau`, shared with `Fighter2D`). Before this, a player designed one character and
  fought as another.

**Roblox-only weapons** (`src/shared/RobloxWeapons.luau`, merged into the roster by `Weapons.luau`)
- **Chakram**: two returning rings, with a HUD ring count, bots that throw them, and its own poses.
- **Rocket Boots**: a fuel rushdown.
  - Signatures and the recovery spend fuel when they ignite, so an interrupted startup costs
    nothing.
  - Fuel refills after 30 grounded frames.
  - The ultimate is the three-pass Redline Reversal.
  - They are worn, one boot on each foot, not held. The HUD shows the tank.
  - Bots keep enough fuel for their recovery near a ledge.
- Both are added to replay-held modules only behind fields or ids that no web weapon has (`ring`,
  `fuelCost`, `ThrustFuel`, `kind == "redline"`, `wid == "Chakram"`), so the web replay is
  unchanged. Fuel and rings travel on the snapshot (`rg`, `fu`, `fg`) and the client predicts them
  (`RobloxResources.luau`, which the server's Combat and the Predictor share).

**Performance on the lowest devices** (the Frame fallback, with no EditableImage). Details are in
`roblox/docs/match-performance.md`.
- **Fewer writes**: 38% fewer engine property writes a frame on a six-fighter match, with identical
  GUI output.
  - The HUD writes a property only when its value changed.
  - The sky gradient and the effect list are no longer rebuilt every frame.
  - Canvas2D skips writes that cannot change the picture.
- **Fewer Frames**: effects and realm art are drawn as overlapping layers, giving 15% fewer live
  Frames with the same pixels.
- **Countdown warm-up**: the fighters' sprites are now built during the countdown. Before, they were
  built on the first fight frame, about 2,500 Instances in one burst.
  - The trade-off: about 14 countdown frames are not redrawn while the warm-up builds.
  - A late joiner skips the warm-up.

**Web.** Phases 1 and 3 changed `web/` too: the rig, the channels, the kit, the renderer and their
tests, 11 files. That was before the owner paused the web build (2026-10-11). Everything after that
is Roblox-only.

## How it was verified

- `cd roblox && ./check.sh` exits 0 on the branch head: generation, type-check and every replay
  suite. `cd web && npm test` passes.
- **Every new test was mutation-checked**: the code it covers was broken on purpose and the test
  was confirmed to fail. Each commit message lists the mutations tried. New or tightened suites:
  - movement, posture, expressions;
  - chakram, rocketboots, prediction-roblox;
  - fighter-warmup, perf-budget, canvas-writes, hud-writes, render-reuse;
  - creator-ui, podium-view.
- **Rendered and inspected as PNGs** at pose scale and at match scale: poses, fights, posture,
  portraits and the kit sheet (`tools/render-*.luau`, `tools/fight-png.mjs`). `tools/perf-raster`
  compares renders pixel by pixel across the performance passes.
- **Balance**: hard bots, 8 matches per opponent, 112 matches each. Win rates were Chakram 47%,
  Rocket Boots 41% and Sword 53%, with no timeouts.
- **Benchmark**: `tools/perf-match.luau` for the six-fighter match, enforced by
  `tests/perf-budget.luau`.

## What has NOT been verified

- **Nothing on this branch has been seen running in Roblox Studio or on a device.** Keyboard input
  sent from the tools never reached the game, so no live match was played. The owner must play it
  first:
  - a match with each new weapon;
  - the countdown warm-up;
  - a late join;
  - the editor portraits;
  - the plaza rack;
  - the podium.
- **Real frame times on low-end phones are unmeasured.** The performance numbers count writes and
  Instances offline; they are not timings.
- **The image path is untested in a live place.** EditableImage is off in the place's settings
  (Experience Settings → Security), so the place falls back to Frames until the owner enables it.
- **The prediction of fuel and rings** is checked against the server in Lune, not over a real
  network with latency.

## Risks

- **Runtime errors that Lune cannot see**: nil snapshot fields for old clients mid-update, the
  plaza and podium previews, and a Studio-only API shape. A renderer error shows up as one warning
  per fighter, not a crash, because each rig is posed inside its own `pcall`.
- **Frame cost on the weakest devices**: more sprites a fighter (12 instead of 7) and the faces.
  The budget test caps them, but only measured devices can confirm it.
- **Balance**: Rocket Boots at 41% is inside the 40-50% band but near its floor. Hard bots are not
  players.
- **The web and Roblox builds now diverge** in the Roblox-only gated code. That is by design, and
  is documented in `roblox/README.md` under "Roblox-only code".

🤖 Generated with [Claude Code](https://claude.com/claude-code)
