# Frame fallback match performance

A render-side pass for the lowest Roblox devices (Frame fallback, `Canvas2D.IMAGES = false`). It
cuts engine property assignments by 38% on a six-fighter match, with identical GUI output. It
does not touch retained art, cold Instance construction, the simulation, or any replay-held
module. It is a write/allocation pass, not a device FPS measurement: Lune has no layout, GPU,
or replication cost.

Baseline: `feature/character-rig` at `83bf18d` (Chakram, Rocket Boots, posture, movement and
secondary motion all included). The shipping changes are confined to `Canvas2D`, `Hud`,
`FxPlayer` and `RealmArt`.

## Reproduce

From `roblox/`:

```sh
lune run tools/perf-match before.json 360 120 before - feature/character-rig   # baseline, read with `git show`
lune run tools/perf-match after.json  360 120 after                            # working tree
cmp before-hashes.json after-hashes.json                                       # identical output, every frame
lune run tools/perf-match n.json 360 120 - native                              # timings without the counting proxies
```

`perf-scene` drives the shipping `FightScene`, effects, Canvas and HUD with six view snapshots
(Sword, Hammer, Chakram, Rocket Boots, Scythe, Gauntlets) on Smeltworks at 960x540 / 18 px per
stud: camera movement, running and idle poses, turns, invincibility flicker, percent and meter
changes, vents, slag drops, weather, projectiles, drops, heavy hits and a finisher. Frames 121-480
are measured after setup, the first draw and warmup are recorded separately.

Each counting proxy forwards to a real `@lune/roblox` Instance. Every assignment counts, even if
equal to the existing value; Destroy counts descendants. `perf-budget` calibrates that boundary
first. `perf-output` reads the actual Instances after drawing (hierarchy order, Position, Size,
Rotation, colours, transparency, text, strokes, corners), not Canvas caches.

## Results (steady state, per frame)

| | before | after |
|---|---:|---:|
| Property assignments, mean | 956.9 | 592.7 |
| Property assignments, peak | 4,682 | 2,926 |
| Instances created (4 across 360 frames, in one burst) | 0.01 | 0.01 |
| Instances destroyed | 0 | 0 |
| Live Frames, peak (hidden cached art included) | 11,870 | 11,870 |
| Native Lune ms (median of 3) | 1.833 | 1.525 |

Output equality: **360/360** ordered GUI hashes match, and the four captured draw lists are
byte-identical.

| Section | Writes/f | Native ms/f (median of 3) |
|---|---:|---:|
| Fighters | 353.4 -> 217.3 | 0.787 -> 0.636 |
| HUD | 194.3 -> 6.0 | 0.197 -> 0.098 |
| Effects/other | 116.4 -> 114.2 | 0.180 -> 0.189 |
| World | 97.0 -> 81.4 | 0.176 -> 0.178 |
| Hazards | 76.8 -> 70.8 | 0.126 -> 0.124 |
| Timed effects | 73.6 -> 72.0 | 0.078 -> 0.074 |
| Weather | 19.2 -> 18.3 | 0.089 -> 0.092 |
| Sky | 11.1 -> 0.6 | 0.141 -> 0.076 |
| Stage | 10.3 -> 7.3 | 0.028 -> 0.029 |
| Finish | 4.7 -> 4.7 | 0.016 -> 0.016 |

By property: Size 143.5 -> 27.5, Position 322.8 -> 258.4, Visible 69.5 -> 9.5,
BackgroundColor3 75.4 -> 15.7, Text 34.0 -> 0.7. Rotation, ZIndex and BackgroundTransparency
are unchanged and are now the bulk of what is left.

Not improved, and the larger low-end costs: the first draw creates ~2,965 Instances and writes
~21,400 properties, warmup creates ~8,900 more (peaking at ~593 in a frame), and ~11,800 Frames
stay alive. Those are construction costs of the retained art.

## What changed and why it is equivalent

- `Canvas2D.place` compares the final `UDim2` before crossing the engine boundary: offsets are
  integers in the engine, so subpixel camera/bone movement often builds an equal value.
- Turning a sprite rewrites only off-centre cell positions (a centred cell's mirrored row is
  its own row) and no sizes; a change of canvas dimensions still relays out every cell.
- `translate`/`rotate`/`scale` are the general multiply with the constant operand folded in
  (checked against the removed `mul` for 600 random mixed steps), and `save` shares the
  matrix instead of cloning it. This is safe only because every transform replaces `m`.
- `Hud` remembers the last value it wrote per widget property (weak keys, so a rebound roster
  starts fresh), reuses its fighter-index table, and resolves prompt and callout size once per
  frame. The rig's RINGS and FUEL status lines go through the same cache.
- `RealmArt.sky` compiles each realm's 30 gradient colours once per palette.
- `FxPlayer.step` compacts its list in place, in order (alpha overlap depends on order).

## Tests

`canvas-hotpath`, `hud-writes`, `render-reuse` and `perf-budget` are registered in `check.sh`.
`perf-budget` has no wall-clock assertion (shared-host time is noise): 620 mean / 3,050 peak
assignments, at most 6 steady creations (4 in one frame: one pooled Frame and its UICorner, twice), zero destructions, 12,410 live Frames,
and cold and warm creation limits. Each test was verified by mutation; see the commit messages.

Not verified: how any of this looks or performs in Roblox Studio or on a device.

# Cold start and resident Frames (second pass)

The first pass cut per-frame writes. This one goes after what it left: the Frames a match keeps
alive and the Instances it creates to get there. Same scene (`tools/perf-match`), same rules:
Roblox-only, replay-held modules untouched, no assertion loosened.

## Where the 11,870 live Frames were

`lune run tools/perf-owners` counts a drawn scene by sprite family (container Frames plus their
child Frames) rather than by the section that happened to be active when a Frame was created:

| owner | Frames |
|---|---:|
| effect flipbooks (FxArt: burst, ring, pop, xslash, flame, crescent, orb, spark) | ~7,400 |
| realm art (islands, shelves, four sky layers, two tiles each) | 1,754 |
| fighters (kit parts, far limbs, head/blink faces, weapons) | ~1,700 |
| pooled `rect`/`ellipse` Frames | 200 |
| HUD | 191 |

Two thirds of the match is the effect library: one Frame per rectangle of every flipbook frame
that has been drawn, kept ten seconds after its last use. The drawings are noisy (rim, dither):
half their rectangles are one cell. A better *partition* does not help (a column-first variant
was tried and was no smaller); a different *kind* of cover does.

## What changed

`PixelGrid.layers` covers a grid with overlapping rectangles, bottom layer first: a rectangle of a
lower layer may cover cells that a later layer paints over, so a dark outline becomes its filled
silhouette under its body instead of a ring of strips. It is only exact under three conditions, and
each is enforced and tested:

1. nothing translucent is ever covered, and nothing empty is ever covered (those cells are merged
   on their own, last, and never overlap);
2. every layer is opaque - two 45% rectangles on top of each other add up to 70%;
3. the sprite is drawn at full opacity, because a fade rewrites every child's transparency and
   overlapping children would then add up. `FxArt.draw` uses the stack only when the caller passes
   no alpha and the canvas is not itself faded; a caller that fades (`FxPlayer` items with
   `fadeAt`) uses the plain partition for every draw, so one effect is never built in both forms
   (`tests/ult-fx` counts sprites built and would have caught that: Hammer went to 162 against 150).
   `RealmArt` does the same for islands/shelves (canvas alpha) and sky tiles (their `alpha`).

`art.rects` is still the plain partition (`tests/ult-fx` asserts it has no overlaps); `art.stack`
is the layered one under its own sprite key.

## Results (same scene, 360 frames after 120 warm-up)

| | before | after |
|---|---:|---:|
| Live Frames, peak | 11,870 | 10,101 |
| First draw: Instances created | 2,989 | 2,576 |
| First draw: property writes | 21,576 | 18,685 |
| Warm-up (119 frames): Instances created | 8,888 (593/f peak) | 7,532 (401/f peak) |
| Steady writes per frame, mean | 592.7 | 592.7 |
| Steady writes per frame, peak | 2,926 | 2,926 |
| Lune ms/f (counting proxies) | 2.32 | 1.58 |

Effect drawings: 22,080 -> 16,790 rectangles (76%). Realm drawings: 33,295 -> 21,115 (63%).
Steady writes did not move because per-frame work is one container Frame per sprite; the saving is
in what a sprite costs to build and keep (and, when something fades, one write per child).

"Drawn unchanged" is proved on pixels, not by hash: the ordered GUI hash of the first pass cannot
compare two ways of cutting one picture into rectangles. `tools/perf-raster [out.json] [git-ref]`
flattens the real Frames after nine frames of the scene, rasterises them source-over at 960x540
with sample points off the pixel centres, and hashes the pixels. `0c548a4` and the working tree
give the same nine hashes (the shape count drops 3,886 -> 3,431 on the first). `tests/pixel-layers`
repaints every effect drawing (4 variations, two palettes, both facings) and every realm drawing
(9 realms) through `Canvas2D.paint` both ways and compares the buffers.

## Tried and not shipped

- **Sharing one set of children between palettes of the same drawing** (an effect in each weapon's
  glow is the same rectangles in different colours), recolouring in place when the palette changes.
  It cut live Frames to 8,700, but steady writes rose to 645-665/f (+9-12%) however the cache was
  capped, because six fighters' glows rotate and an LRU thrashes on a round robin. The write budget
  (620) would have had to be loosened, so it was dropped.
- **A column-first rectangle partition**: no smaller on any art measured.
- **Layers for kit parts and weapons** (they come from the held AvatarCompose / generated art):
  4% fewer rectangles, not worth a second form of every body part.
- **Stable ZIndex** (keep a Frame's old ZIndex while it still orders correctly) would remove ~57
  writes a frame, but `tests/canvas-writes` compares absolute ZIndex against an uncached canvas;
  it was left alone rather than rewriting that assertion.

## Not done, and why

- **Lazy `UICorner` on pooled Frames** would save ~200 Instances; `tests/canvas-writes` reads
  `poolState[i].corner` of every pooled Frame.
- **Building the first-draw sprites during the countdown** (`RealmArt.warm` already compiles the
  art there) would move the 2.5k-Instance burst off the first fight frame. It needs the slot
  numbering of `Canvas2D.sprite` mirrored in the warm-up and cannot be judged without a device.
- **Releasing sprites sooner than ten seconds**: invisible to this scene (every drawing recurs
  within 120 frames), so there is nothing to measure it against here.

Not verified: how any of this looks or performs in Roblox Studio or on a device. Seams where
adjacent Frames meet on fractional pixels are an engine behaviour Lune cannot show; overlapping
layers only remove such seams, they cannot add one.
