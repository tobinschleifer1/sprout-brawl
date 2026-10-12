# Roblox movement and combat feel — 2026-10-13

Phase 4 is implemented downstream of the replay-held renderer in `Movement.luau`, `Posture.luau`
and `Secondary.luau`, applied by `Fighter2D.luau`. The web build, shared simulation/data,
Channels, Rig, AvatarCompose and WeaponPose have no changes. No collision, input, hitbox, move
or state duration changes are involved.

## What changed and why

The old low-speed run barely stepped, both feet could float above the floor, and the legs made an
X as they passed. Grounded movement now uses distance travelled for its phase. A support foot
cancels the body's travel, including through acceleration; the swing foot clears it. Speed blends
low walking lift into a higher running knee. Projected hip/knee lanes keep both thighs and shins
from crossing. Chest/hip counter-motion and the free arm follow that same stride. The armed hand
continues to hit the exact authored grip, so its weapon aim stays authoritative.

Jump load, trailing rise leg, gathered apex, reaching fall, fast-fall commitment, and landing
compression/settle have separate silhouettes. Defence adds a shield brace and spot-dodge duck;
air dodges, rolls and tumble gather the limbs around the existing authored rotations. Initial
hitstun displaces the body along the launch direction in either facing. Knockdown turns back up
within its existing duration, solving feet back through the cosmetic root transform to keep them
on the floor. Ledge hangs retain the overhead arm and raise a climbing knee. Getup/attack hold
that knee during the initial pull, then plant on the simulation's existing arrival frames (10/8).
The resumed WIP had lowered this knee too soon and failed its direct assertion; the pose was
fixed, not the assertion.

Other meaningful authored actions (attacks, dash, grabs/throws, breakout, stunned, helpless,
recovery and respawn) retain their existing action channels. Attack timings and weapon geometry
continue through the original replay and blade-to-hitbox checks.

The actual kit catalogue has eight separable rear-hair styles, `scarf` and `summitMantle` in
**neckwear**, and `trench`/`robe` hems in **tops**. One cached trailing sprite is selected at full
detail, prioritizing neckwear, then coat hem, then rear hair. Other hair follows the lagging head.
Cuts remove the duplicate art from the original piece, respect headwear trimming, and retain
expressions without restoring the cut hair. A damped follower trails velocity and settles after
stopping; repeated draws do not advance it, and seeks reset it. The new art cache holds at most
64 appearances. Pictures and keys are independent of animation time. At match LOD there is no
extra sprite or accessory composition; the original welded art is used.

Every piece is attached by a transformed point and reaches Canvas2D as rotation then axis scale.
No shear is introduced. Existing Frame budgets stay in place, including the optional tail's
rectangles; the twelve-piece body count remains exact and the tail gets its own one-sprite cap.
The posture test setup also now assigns Fighter's real `invincible` field instead of unused
`invul`.

## Verification

- `cd roblox && ./check.sh`: exit 0; `/tmp/charplan/movement-check-final.log`.
- `cd web && npm test`: exit 0; `/tmp/charplan/movement-web-tests.log` (web source unchanged).
- `tests/movement.luau`: 1,928 dense gait samples across four speeds and both facings, plus
  acceleration/deceleration, action preservation and the jump/defence/reaction/ledge properties.
  Minimum passing-foot clearance: **0.441 studs**. Support endpoints stay fixed in world space.
- Existing `tests/posture.luau`: **7,644 shipping draws** checking joints, waist, exact hand/grip,
  original authored weapon anchor, constant limb width and shear. Existing replay and weapon
  geometry suites remain intact.
- `tests/secondary.luau`: **1,296 shipping draws** across twelve accessory combinations, nine
  states, both facings and both LODs. Direct attached-root, lag/settle/reset, expression-cut,
  hat-trim, cache and child-Instance identity checks. Largest tested tail: **21 rectangles**,
  within the 24-rectangle / 196-cell small-picture limits.
- The six-fighter Frame test holds **827 child Frames / 881 Instances** at match LOD and
  **1,348 / 1,432** at full detail, with all indices fixed at zero to isolate moving pictures.
  It reports **zero warm rebuilt rectangles**. Its setup-inclusive timing is not the benchmark
  below.

## Measured comparison

`tools/measure-movement.luau` uses the real Canvas2D Frame fallback with six distinct accessory
loadouts, different fighter indices, and the same prebuilt run snapshots. A 360-frame pass warms
all existing blink/head pictures; the following 360 frames measure drawing plus Canvas.finish.
The before source is `4a0d6ee`; the after source is this branch. These are local Lune numbers,
**not Roblox Studio or low-end-device frame times**.

| Six fighters | Match LOD before | Match LOD after | Full before | Full after |
| --- | ---: | ---: | ---: | ---: |
| Child Frames, including warmed expression pictures and weapons | 1,018 | 1,018 | 1,693 | 1,708 |
| Total descendant Instances | 1,078 | 1,078 | 1,777 | 1,798 |
| Sprite slots | 60 | 60 | 84 | 90 |
| Extra trailing sprites | 0 | 0 | 0 | 6 |
| Warm rebuilt rectangles | 0 | 0 | 0 | 0 |
| Median ms per six-fighter draw | 0.462 | 0.475 | 0.607 | 0.689 |
| p95 ms | 0.550 | 0.604 | 0.741 | 0.889 |

The target match LOD has no Frame/Instance growth. Full detail costs 15 more child Frames and six
containers in this roster after removing the original tail pixels. The new cache is bounded, but
this change does not repair older unrelated composer caches. Measurement JSONs are
`/tmp/charplan/movement-perf-before.json` and `movement-perf-after.json`.

## Deliberate mutations

`python3 tools/mutate-movement.py` applies and restores each fault independently and requires the
expected property failure, not just a nonzero exit or a compiler error. **53 faults were rejected**;
the clean suites pass again afterward. Full output: `/tmp/charplan/movement-mutations-final.log`.

Movement faults (31):

1. Remove the passing-shin lane correction.
2. Invert the projected hip roots (crossed thighs).
3. Freeze distance phase (sliding support).
4. Push feet below the ground.
5. Remove swing clearance (also makes the sliding swing foot appear planted).
6. Give walk and run identical lift.
7. Swing the free arm with its leg.
8. Drive the torso from lifetime frame count again.
9. Freeze torso phase.
10. Lift jump-load feet from the floor.
11. Let landing feet follow squash/bob.
12. Drift landing stance width.
13. Remove the rise's trailing leg.
14. Flatten the apex.
15. Keep the fall leg raised (also destroys the rise's asymmetry).
16. Ignore fast fall.
17. Drop the shield arm.
18. Remove the spot-dodge duck.
19. Ignore facing in impact direction.
20. Remove the rolling leg tuck.
21. Leave the rolling arm extended.
22. Never turn upright after knockdown.
23. Offset getup foot y through the ground.
24. Offset getup foot x (also violates floor contact through the rotated root).
25. Drop the hanging/climbing knee.
26. Never plant the climbing foot.
27. Lower the climbing knee too early.
28. Plant after platform arrival.
29. Overwrite authored attack feet with a running pose.
30. Write to the frozen snapshot.
31. Write to the frozen channel bag.

Secondary faults (22):

1. Omit rear hair.
2. Choose the wrong accessory priority.
3. Split rigid short hair into an accessory.
4. Disable art caching.
5. Exceed the small-picture dimensions.
6. Leave the original painted tail on the body.
7. Rebuild cut expression art on each call.
8. Make the cut expression neutral.
9. Repaint detached rear hair during an expression.
10. Ignore headwear trimming.
11. Snap straight to the target angle (no lag).
12. Stop following when the body stops (never settles).
13. Advance lag on a duplicate draw.
14. Retain old motion after a seek.
15. Ignore facing in the wind target.
16. Detach the trailing root by 0.1 studs.
17. Rotate the tail inside nonuniform scale (shear).
18. Draw two trailing sprites.
19. Draw a trailing sprite at match LOD.
20. Clone the picture every draw.
21. Put frameCount in the sprite key.
22. Disable cache eviction.

An initial probe removing just the hip-root lane override survived once the torso phase was
synchronized with the feet: it did not produce crossing with that stride. The explicit root-sign
inversion above then verified the thigh-crossing assertion. No assertion was removed or relaxed.

## Images rendered and inspected

All PNGs were drawn through the shipping renderer, with identical inputs before/after. Contact
sheets have four columns, left to right. Gait: first eight frames walk, last eight run. Jump: load,
rise, apex, fall, fast fall, landing, settle. Reaction: shield, spot dodge, air dodge, two impact
directions, two tumble frames, three getup frames, in-place tech, rolling tech. Ledge: hang,
getup, attack, roll, jump. Secondary: each row is ponytail, dreads, scarf, mantle, trench; columns
are idle, early run, later run, stop.

| View | Before PNG | After PNG |
| --- | --- | --- |
| Walk/run | `/tmp/charplan/movement-gait-before.png` | `/tmp/charplan/movement-gait-after.png` |
| Jump/landing | `/tmp/charplan/movement-jump-before.png` | `/tmp/charplan/movement-jump-after.png` |
| Defence/reactions | `/tmp/charplan/movement-reaction-before.png` | `/tmp/charplan/movement-reaction-after.png` |
| Ledges | `/tmp/charplan/movement-ledge-before.png` | `/tmp/charplan/movement-ledge-after.png` |
| Hair/cloth | `/tmp/charplan/movement-secondary-before.png` | `/tmp/charplan/movement-secondary-after.png` |
| Seeded match, 960×540 per frame | `/tmp/charplan/movement-fight-before.png` | `/tmp/charplan/movement-fight-after.png` |
| 26px gait | `/tmp/charplan/movement-gait-match-before.png` | `/tmp/charplan/movement-gait-match-after.png` |
| 26px jump | `/tmp/charplan/movement-jump-match-before.png` | `/tmp/charplan/movement-jump-match-after.png` |
| 26px reactions | `/tmp/charplan/movement-reaction-match-before.png` | `/tmp/charplan/movement-reaction-match-after.png` |

At 26px, the lifted foot, stride, compressed load, gathered air pose and narrow fast fall change
the silhouette. Small LOD retains its existing straight, single-piece limbs, so individual knee
and elbow articulation is a full-detail benefit. The fight camera changes scale as fighters spread;
the 5-pixels-per-stud sheets explicitly check the plan's approximately 26px target. The close-up
sheets show the secondary lag; it is intentionally omitted at match LOD.

Reproduce from `roblox/` (replace `gait` with `jump`, `reaction`, `ledge` or `secondary`):

```sh
lune run tools/render-posture /tmp/charplan/movement-gait-after.json Classic 26 1 gait
node tools/fight-png.mjs /tmp/charplan/movement-gait-after.json /tmp/charplan/movement-gait-after.png 4 1
# Use scale 5 instead of 26 for a 26px fighter; facing -1 checks the mirror.
lune run tools/render-fight /tmp/charplan/movement-fight-after.json Sword 25,60,120 Classic FoundryFloor 2 7 right brawl
node tools/fight-png.mjs /tmp/charplan/movement-fight-after.json /tmp/charplan/movement-fight-after.png 1 1
lune run tools/measure-movement /tmp/charplan/movement-perf-after.json
```

## Remaining verification

Studio tools found one connected Edit-mode instance, but automatic approval review rejected the
Luau inspection: `MCP tool call requires approval, but approval policy is never`. No live game
was modified. PNG rendering and Lune Frame geometry/identity were inspected; live Studio
appearance, actual property-write cost, and lowest-device performance still require a playtest.
The larger emote/KO/podium work remains phase 6, outside this movement task.
