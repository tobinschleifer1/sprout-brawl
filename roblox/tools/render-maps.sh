#!/usr/bin/env bash
# Every stage, rendered for review: the whole map (a fixed wide camera) and the fight camera with the
# HUD composited over it, as true-font PNGs through headless Chrome.
#   roblox/tools/render-maps.sh <out-dir>
set -euo pipefail
mkdir -p "$1"; OUT="$(cd "$1" && pwd)"
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
png() {   # svg -> png at the svg's own size
  local f="$1" size url
  size=$(head -c 300 "$f" | sed -n 's/.*width="\([0-9]*\)" height="\([0-9]*\)".*/\1,\2/p')
  url="file://$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$f")"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size="${size:-1280,720}" --virtual-time-budget=4000 \
    --user-data-dir="${TMPDIR:-/tmp}/blockfall-maps-chrome" --screenshot="${f%.svg}.png" "$url" > /dev/null 2>&1 || true
}
lune run tools/render-ui "$TMP/hud.json" hud 1280 720 fight > /dev/null
for stage in $(printf 'local L = require("./tests/loader")\nfor _, s in L.load("Data/Stages").LIST do print(s.id) end\n' > "$TMP/ls.luau" && cp "$TMP/ls.luau" ./_ls_stages.luau && lune run _ls_stages; rm -f _ls_stages.luau); do
  # the whole map, two fighters standing on it
  lune run tools/render-fight "$TMP/$stage-wide.json" Sword 40 Classic "$stage" 1 7 right wide > /dev/null
  node tools/compose-shot.mjs "$TMP/$stage-wide.json" <(echo '{"w":1280,"h":720,"nodes":[]}') "$TMP/$stage-wide-c.json"
  node tools/gui-svg.mjs "$TMP/$stage-wide-c.json" "$OUT/$stage-wide.svg" > /dev/null
  # the fight camera with the HUD over it, twice: a close exchange (frame 50 of a brawl, the usual
  # view) and a spread one (frame 140, someone launched high, the camera at its widest)
  for shot in "fight|50" "spread|140"; do
    IFS='|' read -r name frame <<< "$shot"
    lune run tools/render-fight "$TMP/$stage-$name.json" Sword "$frame" Classic "$stage" 3 7 right brawl > /dev/null
    node tools/compose-shot.mjs "$TMP/$stage-$name.json" "$TMP/hud.json" "$TMP/$stage-$name-c.json"
    node tools/gui-svg.mjs "$TMP/$stage-$name-c.json" "$OUT/$stage-$name.svg" > /dev/null
  done
done
if [ -x "$CHROME" ]; then for f in "$OUT"/*.svg; do png "$f"; done; fi
echo "rendered $(ls "$OUT"/*.svg | wc -l | tr -d ' ') map shots into $OUT"
