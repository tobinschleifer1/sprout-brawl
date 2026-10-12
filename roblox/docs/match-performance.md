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
