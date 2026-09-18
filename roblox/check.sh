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

echo "== generating from web/src =="
node tools/gen-data.mjs
node tests/genfixture.mjs
node tools/gen-traces.mjs
node tools/gen-fighter-traces.mjs
node tools/gen-hazard-traces.mjs
node tools/gen-rng-fixture.mjs

rojo sourcemap default.project.json --output sourcemap.json >/dev/null
echo "== luau-lsp analyze =="
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src/

echo "== parity: the seeded generator vs web/src/engine/rng.js =="
lune run tests/rng-parity
echo "== parity: engine numbers vs web/src/engine/knockback.js =="
lune run tests/parity
echo "== parity: data layer vs web/src/data =="
lune run tests/data-parity
echo "== parity: Stage vs web/src/engine/stage.js =="
lune run tests/stage-parity
echo "== parity: Fighter vs web/src/engine/fighter.js =="
lune run tests/fighter-parity
echo "== parity: Hazards vs web/src/engine/hazards.js =="
lune run tests/hazard-parity
