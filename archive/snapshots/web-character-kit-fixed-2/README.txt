Blockfall Web Character Kit — corrected player portraits

This folder is the playable static web export. The game files are index.html,
style.css and src/. Player select now scales each fighter to fit its portrait
canvas, so heads and weapons remain inside the slot frame.

To run it locally:
  python3 -m http.server 8124 --directory 'Blockfall Web Character Kit Fixed'
Then open http://localhost:8124/.

verification/player-select-fixed.png is a browser screenshot of the fix.
Source branch: codex/web-character-kit, commit c222aec.
