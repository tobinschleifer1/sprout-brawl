#!/usr/bin/env bash
# Every UI screen recorded (no pictures) and linted: outlined buttons at least 8 px apart between
# their outer strokes (tools/ui-lint.mjs). The same screens and sizes as render-gallery.sh.
#   roblox/tools/ui-lint.sh            exit 1 when any screen has buttons too close
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
while IFS='|' read -r name screen w h variant; do
  lune run tools/render-ui "$OUT/$name.json" "$screen" "$w" "$h" $variant > /dev/null
done <<'LIST'
plaza|plaza|1280|720|
plaza-phone|plaza|844|390|
hud-fight|hud|1280|720|fight
hud-countdown|hud|1280|720|countdown
results|results|1280|720|
records|records|1280|720|
notice|notice|1280|720|
notice-error|notice|1280|720|error
people|people|1280|720|
climb|climb|1280|720|
studio-presets|studio|1280|720|presets
studio-outfit|studio|1280|720|clothing
studio-phone|studio|844|390|body
locker|locker|1280|720|
locker-crates|locker|1280|720|crates
locker-odds|locker|1280|720|odds
locker-workshop|locker|1280|720|workshop
shop|shop|1280|720|
shop-odds|shop|1280|720|odds
shop-phone|shop|390|844|
LIST
for s in "select-pick|1v1|pick" "select-map|2v2|map" "select-rules|3v3|rules"; do
  IFS='|' read -r name fmt phase <<< "$s"
  lune run tools/render-select "$OUT/$name.json" 1280 720 "$fmt" "$phase" > /dev/null
done
node tools/ui-lint.mjs "$OUT"/*.json
echo "ui lint: $(ls "$OUT"/*.json | wc -l | tr -d ' ') screens, no outlined buttons closer than 8 px"
