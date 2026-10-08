#!/usr/bin/env bash
# Generate, type-check, and confirm the Luau still matches the JavaScript numerically.
#
# Generation runs FIRST and every time, on purpose. Both fixtures and the whole of
# src/shared/Data are derived from web/, and a check that compares the port against a committed
# snapshot of its own source can only catch drift somebody already noticed - which is exactly how
# the knockback port went stale without this script saying a word.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.rokit/bin:$PATH"

# ---------------------------------------------------------------- preflight ----
# Everything below needs four tools and one downloaded file, and the failure when they are missing
# is unhelpful enough to have cost real time: without globalTypes.d.luau, luau-lsp does not say
# "missing definitions", it reports thousands of "Unknown global 'Enum'" errors that look like the
# port is broken. So check for them here and say what to do.
missing=""
for tool in node rojo lune luau-lsp; do
	command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
	echo "missing tools:$missing" >&2
	echo "node comes from your package manager; the rest are Rokit tools:" >&2
	echo "  curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash" >&2
	echo "  rokit add --global rojo-rbx/rojo JohnnyMorganz/luau-lsp lune-org/lune" >&2
	echo "  (then open a new shell, or: export PATH=\"\$HOME/.rokit/bin:\$PATH\")" >&2
	exit 1
fi

# The Roblox API definitions luau-lsp type-checks against. Gitignored because it is downloaded
# rather than written, and fetched here so a fresh clone can just run this script.
if [ ! -f globalTypes.d.luau ]; then
	echo "== fetching globalTypes.d.luau =="
	curl -fsSL -o globalTypes.d.luau \
		https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi

echo "== generating from web/src =="
node tools/gen-data.mjs
node tests/genfixture.mjs
node tools/gen-traces.mjs
node tools/gen-fighter-traces.mjs
node tools/gen-hazard-traces.mjs
node tools/gen-disaster-traces.mjs
node tools/gen-cinematic-fixture.mjs
node tools/gen-podium-fixture.mjs
node tools/gen-stage-thumb-fixture.mjs
node tools/gen-effects-fixture.mjs
node tools/gen-shield-fixture.mjs
node tools/gen-kit-fixture.mjs
node tools/gen-combat-traces.mjs
node tools/gen-match-traces.mjs
node tools/gen-drops-traces.mjs
node tools/gen-ai-traces.mjs
node tools/gen-rng-fixture.mjs
node tools/gen-channel-traces.mjs
node tools/gen-weapon-traces.mjs
node tools/gen-hud-fixture.mjs
node tools/gen-plaza-trace.mjs
node tools/gen-parkour-trace.mjs

rojo sourcemap default.project.json --output sourcemap.json >/dev/null
echo "== luau-lsp analyze =="
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src/

echo "== snapshot: the fighter state, encoded and decoded =="
lune run tests/snapshot
echo "== codec: the input frame, packed and unpacked =="
lune run tests/codec
echo "== runtime input: focus, packet ordering, rematches and disconnects =="
lune run tests/runtime-input
lune run tests/abilities
echo "== launch: the lobby's wait for a match, timeout and retry =="
lune run tests/launch-state
echo "== the lobby: walking the rooftop market, its stations and its drawing =="
lune run tests/plaza-view
lune run tests/social-ui
lune run tests/plaza-parity
lune run tests/parkour-parity
lune run tests/climb-view
lune run tests/records-ui
echo "== match launch: all roster sizes and snapshot cadence =="
lune run tests/match-launch
lune run tests/rooms
lune run tests/cabinets
lune run tests/climb-progress
lune run tests/climb-boards
lune run tests/purchases
lune run tests/room-ui
echo "== the select screen: layout, stat bars, every control; and the bot vote =="
lune run tests/ui-kit
lune run tests/select-screen
lune run tests/bot-vote
lune run tests/room-phases
lune run tests/multiplayer
lune run tests/presence-codec
lune run tests/snapshot-codec
lune run tests/avatar-store
echo "== scene: visible projectiles, items, hazards and backdrops =="
lune run tests/scene-view
echo "== parity: the seeded generator vs web/src/engine/rng.js =="
lune run tests/rng-parity
echo "== parity: engine numbers vs web/src/engine/knockback.js =="
lune run tests/parity
echo "== parity: data layer vs web/src/data =="
lune run tests/data-parity
echo "== parity: the HUD's damage ramp vs web/src/ui/hud.js =="
lune run tests/hud-parity
echo "== the ultimate VFX draw, every weapon and phase =="
lune run tests/ultimate-vfx
echo "== sprites as images, with Frames to fall back on =="
lune run tests/canvas-images
echo "== the connection: scene deltas, interpolation, eased corrections, the monitor =="
lune run tests/net-smooth
echo "== the fight camera: framing at every resolution =="
lune run tests/camera
echo "== the ultimates' pixel-art effects, played in real matches =="
lune run tests/ult-fx
echo "== combos on screen: the counter, the break prompt, the guide, and the combo effects =="
lune run tests/combo-hud
echo "== hits, the shield and flying: impacts, the shell, speed lines and smoke =="
lune run tests/hit-fx
echo "== what a client is allowed to ask the server for =="
lune run tests/match-config
echo "== prediction: rollback and replay against a straight simulation =="
lune run tests/prediction
lune run tests/prediction-platforms
echo "== combos predicted on the server's frames: timed strings, chases, the victim's break =="
lune run tests/prediction-combos
echo "== the client's view-only stage, moved by the server =="
lune run tests/stage-view
echo "== parity: Stage vs web/src/engine/stage.js =="
lune run tests/stage-parity
echo "== parity: Fighter vs web/src/engine/fighter.js =="
lune run tests/fighter-parity
echo "== parity: Hazards vs web/src/engine/hazards.js =="
lune run tests/hazard-parity
echo "== parity: Disasters vs web/src/engine/disasters.js =="
lune run tests/disaster-parity
echo "== disaster shapes: Roblox draws each disaster as the web does =="
lune run tests/disaster-shapes
echo "== ultimate cutscene: Roblox times and lays it out as the web does =="
lune run tests/cinematic-parity
lune run tests/ult-banner
echo "== podium: the results screen is laid out as the web lays it out =="
lune run tests/podium-parity
lune run tests/podium-view
echo "== map select: thumbnails drawn as the web draws them =="
lune run tests/stage-thumb
echo "== effects: hit sparks, rings and shake as the web throws them =="
lune run tests/effects-parity
lune run tests/predictor-events
lune run tests/team-marks
echo "== character kit: codes and composed parts as the web builds them =="
lune run tests/kit-parity
lune run tests/kit-draw
lune run tests/canvas-writes
lune run tests/creator-ui
lune run tests/shield-parity
echo "== parity: Combat vs web/src/engine/combat.js =="
lune run tests/combat-parity
echo "== parity: Match vs web/src/engine/match.js =="
lune run tests/match-parity
lune run tests/drops-parity
echo "== parity: Ai vs web/src/engine/ai.js =="
lune run tests/ai-parity
echo "== parity: Channels vs web/src/render2d/channels.js =="
lune run tests/channel-parity
echo "== disasters, hazards and weather in the realms' pixel art, played in real matches =="
lune run tests/disaster-art
echo "== the realms: every stage as a floating island, drawn on its geometry =="
lune run tests/realms
echo "== stage art: a ledge marker only where there is a ledge =="
lune run tests/stage-art
echo "== weapon art: Roblox draws the shared pixel art exactly =="
lune run tests/weapon-art
echo "== parity: WeaponPose vs web/src/render2d/weapons2d.js =="
lune run tests/weapon-parity
