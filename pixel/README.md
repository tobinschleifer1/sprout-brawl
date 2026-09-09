# Pixel art pipeline

Weapon icons and weapon VFX, authored in Python and written straight out as `.piskel` documents.

## Why not draw in the browser

A `.piskel` file is plain JSON: `{"modelVersion":2,"piskel":{name,width,height,fps,layers:[...]}}`
where each entry in `layers` is itself a **JSON string** holding `{name,opacity,frameCount,chunks}`,
and each chunk carries a base64 PNG of that layer's frames laid out left to right.

So the files can be generated exactly, in version control, and regenerated after a balance change —
and they still open in <https://www.piskelapp.com> (File → Open → the `.piskel`) for hand-tweaking
like any other document. Every file in `out/` has been validated against the structure of a real
Piskel export.

## Layout

```
lib/sbpixel.py     the authoring library: Frame, drawing primitives, PNG encoder, Piskel writer
lib/preview.py     scaled-up contact sheets, so the art can actually be looked at
weapon_icons.py    32x32 select-screen icons, one per weapon
weapon_fx.py       swing arcs, muzzle flashes and cast circles
out/icons/*        <weapon>.piskel (editable) + <weapon>.png (flattened sheet)
out/fx/*           <effect>.piskel + <effect>.png
out/*/_preview.png contact sheet at 4-8x, for eyeballing
```

## Regenerate

```bash
cd pixel && python3 weapon_icons.py && python3 weapon_fx.py
```

Stdlib only — no Pillow, no npm. `python3 -c "import sbpixel"` is the whole dependency list.

## Authoring styles

Two ways to make a frame, mixed per asset depending on which gives better art:

- **`from_map(rows, palette)`** — one character per pixel, `.` transparent. Used for the sword and
  the pistol, where a hand-placed silhouette reads better than anything procedural.
- **drawing into a `Frame`** — `line`, `arc`, `poly`, `disc`, `ring`. Used for the scythe crescent,
  the book, and every animated effect, where the shape is genuinely geometric.

`Frame.outline(INK)` traces a border after the fact, so maps stay readable without hand-drawing the
outline into them. All four icons share one outline colour so the set reads as a family.

## Conventions

- Effects are authored **facing right**. The game mirrors by `facing`; there is one asset per
  effect, never a left and a right copy.
- Frame counts line up with the active windows in `web/src/data/weapons/*.js`. If you retune a
  move's `active` frames, retune the effect to match.
- Colour comes from `ramp(base, n)`, which builds a shading ramp around a base hue, so a weapon's
  palette in `data/weapons/<w>.js` and its art stay in sync by construction.
