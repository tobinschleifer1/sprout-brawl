#!/usr/bin/env bash
# The lobby, rendered for review: the Skyhold Bazaar's districts and stations, a busy roof, a phone,
# and a fight's lounge, each with its real GUI, as true-font PNGs through headless Chrome.
#   roblox/tools/render-lobby.sh <out-dir>
set -euo pipefail
mkdir -p "$1"; OUT="$(cd "$1" && pwd)"
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
shots=(
  "square|1280|720|0,8"
  "square-crowd|1280|720|0,8,12"
  "board|1280|720|-40,15"
  "tailor|1280|720|-122,12"
  "arcade|1280|720|138,11"
  "arcade-crowd|1280|720|138,9,10"
  "gates|1280|720|217,13"
  "climb|1280|720|268,12"
  "phone|844|390|0,8"
  "lounge-duel|1280|720|0,9,0,Duel"
  "lounge-triples|1280|720|-2,15,0,Triples"
)
for s in "${shots[@]}"; do
  IFS='|' read -r name w h variant <<< "$s"
  lune run tools/render-ui "$OUT/$name.json" plaza "$w" "$h" "$variant" > /dev/null
  node tools/gui-svg.mjs "$OUT/$name.json" "$OUT/$name.svg" > /dev/null
done
rm -f "$OUT"/*.json
if [ -x "$CHROME" ]; then
  for f in "$OUT"/*.svg; do
    size=$(head -c 300 "$f" | sed -n 's/.*width="\([0-9]*\)" height="\([0-9]*\)".*/\1,\2/p')
    url="file://$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$f")"
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size="${size:-1280,720}" --virtual-time-budget=4000 \
      --user-data-dir="${TMPDIR:-/tmp}/blockfall-lobby-chrome" --screenshot="${f%.svg}.png" "$url" > /dev/null 2>&1 || true
  done
fi
echo "rendered $(ls "$OUT"/*.svg | wc -l | tr -d ' ') lobby shots into $OUT"
