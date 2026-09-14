# Custom stage backgrounds

Drop an image in this folder and it becomes the sky for that stage. No code change, no build step,
no rebuild of anything.

---

## 1. Name the file after the stage

The six stage ids are:

| Stage | id | File to add |
|---|---|---|
| Foundry Floor | `FoundryFloor` | `foundryfloor.png` |
| The Span | `TheSpan` | `thespan.png` |
| Smeltworks | `Smeltworks` | `smeltworks.png` |
| Rooftops | `Rooftops` | `rooftops.png` |
| Saltflat | `Saltflat` | `saltflat.png` |
| Undertow | `Undertow` | `undertow.png` |

`FoundryFloor.png` works too — the id is matched either as written or all-lowercase. `.png`,
`.jpg`, `.jpeg`, `.webp` and `.gif` are all accepted, and they are tried in that order, so if you
have both a `.png` and a `.jpg` for a stage the `.png` wins.

**Put the file in this folder:** `web/assets/backgrounds/`

That is the whole basic workflow. Start the game and the stage has your background.

## 2. Check it worked

```bash
cd web && node serve.cjs 8123
```

Then open **http://localhost:8123/backgrounds.html**.

That page draws all six stages with the real renderer and a camera that pans slowly, so you can see
the parallax. Each stage is tagged:

- **CUSTOM** — your image is in use. The card shows which file was found, its pixel size, and the
  settings being applied.
- **BUILT-IN** — no image was found, so the stage is drawing its painted sky. The card lists every
  path it looked for, which is almost always enough to spot the typo.
- **LOOKING…** — still loading. If it stays there, the file is very large.

You can also run the file check from the terminal, which is faster and catches the problems a
browser hides:

```bash
cd web && node test/backgrounds.test.mjs
```

It verifies that every file in this folder is named after a real stage, that the contents actually
match the extension (a `.webp` renamed to `.png` will not load in some browsers and this is the
only thing that catches it), and that nothing is big enough to stall the first frame.

## 3. What makes a good background

The game renders to a **480 × 270** backbuffer and scales it up with nearest-neighbour, so:

- **Aim for 960 × 540 or larger.** Anything narrower than 480px will look soft. The check page
  warns you if it is.
- **16:9 fits exactly.** Other shapes are cropped from the centre, not squashed.
- **Keep the middle calm.** The fighters are small, dark-outlined and in constant motion across the
  centre of the screen. A busy or high-contrast background there makes the game genuinely harder to
  read, which is why the built-in stages fade everything toward the sky colour with distance.
- **Dark backgrounds are the safe default.** Use `dim` (below) if yours is too bright.

## 4. Tuning it

Optional. Edit `web/src/data/backgrounds.js` and add an entry — a stage with no entry uses the
defaults:

```js
export const BACKGROUNDS = {
  FoundryFloor: { parallax: 0.18, fit: 'cover', scenery: false, dim: 0.25 },
};
```

| Setting | Default | What it does |
|---|---|---|
| `parallax` | `0.12` | How much the image slides against the camera. `0` pins it to the screen like a painted backdrop; `0.5` makes it feel close enough to be part of the stage. |
| `fit` | `'cover'` | `cover` scales until the image fills the screen and crops the overflow. `tile` repeats it horizontally — for a seamless texture. |
| `dim` | `0` | `0` to `1`. Darkens the image. The fastest fix when fighters are hard to see against it. |
| `scenery` | `false` | Whether the game's own chimneys, towers and mesas still draw in front of your image. Off by default: procedural silhouettes standing on a photograph look like a mistake. Turn it on if your image is a plain sky. |
| `file` | — | Only if you want a filename that is not the stage id. |

The check page shows the settings in use for each stage, so you can edit, reload, and see the
result immediately.

## 5. Removing one

Delete the file. The stage goes back to its painted sky on the next reload. Nothing else to undo —
an entry left behind in `backgrounds.js` for a stage with no image does nothing.

## Troubleshooting

**The stage still shows the built-in sky.**
Open the check page and read the `tried:` line under that stage. It lists every path the loader
looked for; compare it with your filename. The most common causes are a capital letter in the
extension (`.PNG`), a double extension from the download (`sky.png.jpg`), or the file sitting in
`web/assets/` rather than `web/assets/backgrounds/`.

**It loads but looks blurry.**
The image is smaller than 480px wide, or close to it. The check page says so on the card.

**The fighters are hard to see.**
Raise `dim` to `0.3` or so, or pick a darker image. Every fighter is drawn with a dark contour, so
the hard case is a background that is itself dark and busy — a bright, low-contrast one is usually
easier to read against.

**It moves too much or too little when the camera pans.**
That is `parallax`. Lower it to pin the image down, raise it to make the background feel nearer.

**The browser console is full of 404s.**
Expected, and harmless. The loader does not know which extension you used, so it asks for
`<stage>.png`, `.jpg`, `.jpeg`, `.webp` and `.gif` in turn and stops at the first one that answers.
A stage with no custom background asks for all of them and gets nothing — that is what BUILT-IN
means. The check page probes all six stages at once, so it is the noisiest place you will see this;
a real match only ever probes the one stage you are playing.

**The page shows LOOKING… forever.**
The file is very large, or it is not a real image. Run `node test/backgrounds.test.mjs`, which
checks the actual file signature rather than trusting the extension.
