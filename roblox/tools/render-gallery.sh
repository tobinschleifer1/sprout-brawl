#!/usr/bin/env bash
# Every UI screen, rendered for review: SVGs and a gallery page in one folder.
#
#   roblox/tools/render-gallery.sh <out-dir> [theme]
#
# View the gallery in a real browser (it loads the game's fonts from Google Fonts; Quick Look and
# most SVG converters silently fall back to Arial/Times, which is the wrong look to judge):
#   python3 -m http.server -d <out-dir> 8131   then open http://localhost:8131/
# Picture frames drawn by game code (item art, fighter previews) are not drawn by these tools.
set -euo pipefail
mkdir -p "$1"; OUT="$(cd "$1" && pwd)"
cd "$(dirname "$0")/.."
export UI_THEME="${2:-${UI_THEME:-}}"
shots=(
  "plaza|plaza|1280|720|"
  "plaza-phone|plaza|844|390|"
  "hud-fight|hud|1280|720|fight"
  "hud-countdown|hud|1280|720|countdown"
  "results|results|1280|720|"
  "records|records|1280|720|"
  "notice|notice|1280|720|"
  "notice-error|notice|1280|720|error"
  "people|people|1280|720|"
  "climb|climb|1280|720|"
  "studio-presets|studio|1280|720|presets"
  "studio-outfit|studio|1280|720|clothing"
  "studio-phone|studio|844|390|body"
  "locker|locker|1280|720|"
  "locker-crates|locker|1280|720|crates"
  "locker-odds|locker|1280|720|odds"
  "locker-workshop|locker|1280|720|workshop"
  "shop|shop|1280|720|"
  "shop-odds|shop|1280|720|odds"
  "shop-phone|shop|390|844|"
)
for s in "${shots[@]}"; do
  IFS='|' read -r name screen w h variant <<< "$s"
  lune run tools/render-ui "$OUT/$name.json" "$screen" "$w" "$h" $variant > /dev/null
  node tools/gui-svg.mjs "$OUT/$name.json" "$OUT/$name.svg" > /dev/null
done
for s in "select-pick|1v1|pick" "select-map|2v2|map" "select-rules|3v3|rules"; do
  IFS='|' read -r name fmt phase <<< "$s"
  lune run tools/render-select "$OUT/$name.json" 1280 720 "$fmt" "$phase" > /dev/null
  node tools/gui-svg.mjs "$OUT/$name.json" "$OUT/$name.svg" > /dev/null
done
rm -f "$OUT"/*.json
{
  echo '<!doctype html><meta charset="utf-8"><title>Blockfall UI</title><style>body{background:#222;color:#ddd;font:14px sans-serif;margin:16px}'
  echo 'figure{margin:0 0 28px}figcaption{margin:4px 0}img{display:block;max-width:100%;border:1px solid #444}</style>'
  for f in "$OUT"/*.svg; do b=$(basename "$f" .svg); echo "<figure><figcaption>$b</figcaption><object data=\"$b.svg\" type=\"image/svg+xml\"></object></figure>"; done
} > "$OUT/index.html"
echo "rendered $(ls "$OUT"/*.svg | wc -l | tr -d ' ') screens into $OUT"
