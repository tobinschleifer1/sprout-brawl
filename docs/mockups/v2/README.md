# Blockfall UI study 02

Open `../blockfall-live-ui.html` for the self-contained interactive study. Use the controls above the game to switch screens, room sizes, viewport, example opponent and stock/timed mode. Buttons in the designs update local sample state; they do not write to Roblox or send chat.

- `design.js`: one scene generator for the prototype and the exported vector boards.
- `screens/`: 45 standalone SVG compositions. Display text is outlined in exports to preserve the live font.
- `previews/`: PNG renders and a six-screen visual board.
- `social-data.json`: the eight live pixel stamps and fourteen quick messages.
- `avatar-options.json`: category and option names read from the live Studio build.
- `../live-art-2026-10-06.json`: read-only canvas/sprite/weapon reference from Studio.
- `fonts/`: the existing Luckiest Guy font and license.
- `shell.html`: review navigation around the game designs.

Build with Node and the `@napi-rs/canvas` package available, then render with `sharp`:

```sh
node docs/mockups/v2/build.mjs
node docs/mockups/v2/render-previews.cjs
```

The delivered prototype already embeds its art, data and display font, so it has no network dependencies. Portraits show the captured live fighter. Option thumbnails, scenery and arena compositions are illustrative. The main fighter preview does not animate or apply body-part changes; use the live Roblox avatar renderer for implementation.

See `../../reviews/roblox-ui-improvements-2026-10-06.md` for grading, changes and implementation notes.
