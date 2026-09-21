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
node tools/gen-combat-traces.mjs
node tools/gen-match-traces.mjs
node tools/gen-ai-traces.mjs
node tools/gen-rng-fixture.mjs
node tools/gen-channel-traces.mjs
node tools/gen-weapon-traces.mjs
node tools/gen-hud-fixture.mjs

rojo sourcemap default.project.json --output sourcemap.json >/dev/null
echo "== luau-lsp analyze =="
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src/

echo "== snapshot: the fighter state, encoded and decoded =="
lune run tests/snapshot
echo "== codec: the input frame, packed and unpacked =="
lune run tests/codec
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
echo "== what a client is allowed to ask the server for =="
lune run tests/match-config
echo "== prediction: rollback and replay against a straight simulation =="
lune run tests/prediction
echo "== the client's view-only stage, moved by the server =="
lune run tests/stage-view
echo "== parity: Stage vs web/src/engine/stage.js =="
lune run tests/stage-parity
echo "== parity: Fighter vs web/src/engine/fighter.js =="
lune run tests/fighter-parity
echo "== parity: Hazards vs web/src/engine/hazards.js =="
lune run tests/hazard-parity
echo "== parity: Combat vs web/src/engine/combat.js =="
lune run tests/combat-parity
echo "== parity: Match vs web/src/engine/match.js =="
lune run tests/match-parity
echo "== parity: Ai vs web/src/engine/ai.js =="
lune run tests/ai-parity
echo "== parity: Channels vs web/src/render2d/channels.js =="
lune run tests/channel-parity
echo "== parity: WeaponPose vs web/src/render2d/weapons2d.js =="
lune run tests/weapon-parity
