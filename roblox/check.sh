#!/usr/bin/env bash
# Type-check the Luau tree and confirm it still matches the JavaScript numerically.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.rokit/bin:$PATH"

rojo sourcemap default.project.json --output sourcemap.json >/dev/null
echo "== luau-lsp analyze =="
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src/
echo "== parity against web/src/engine/knockback.js =="
lune run tests/parity
