# Roblox posture review — 2026-10-12

The fighter's stiff appearance had two separate causes: one torso transform carried the head and
shoulders rigidly, and the equal-bone limb solver produced a large angular bend from a small bone
length surplus. Authored elbow bends magnified that surplus. The lower sprite's exposed square top
edge made the bend read as a broken joint. Existing shear checks covered limbs; the head and weapon
could still rotate inside torso squash, a transform Roblox Frames cannot represent.

`Posture.luau` is a Roblox-only presentation layer after Channels. It keeps the authored grip and
foot endpoints, moves the shoulders and hip roots, and calls the unchanged Rig solver in the
fighter's unsquashed coordinates. Rest elbows are 8° (front) and about 8–10° (back); rest knees are
9°. Wind-up and crouch bends remain, and the back elbow never exceeds 24°. The waist bends, chest
and hips counter-rotate during running/strikes, shoulders rise with overhead reach, and the head
follows attack motion three frames later using stateless phase evaluation. Chest breathing and hip
sway do not move planted feet. Simulation, hitboxes, timings, web/, shared/, and all replay-held
client modules are unchanged.

`PostureArt.luau` caches a chest/abdomen cut with four rows of overlap and beveled joint ends. Lower
limbs draw first so their top edge is covered by the upper segment. There are 12 body sprites at
full detail and 8 at half detail: one extra sprite in each case. Each part reaches Canvas2D through
rotation followed by axis scaling, including the head and weapon. Limb widths do not inherit squash.

## Evidence

- `cd roblox && ./check.sh` exited 0, including generation, type-checking, every replay suite and
  the new posture tests. `cd web && npm test` also exited 0. Logs are
  `/tmp/charplan/check-posture-final.log` and `/tmp/charplan/web-tests.log`.
- `tests/posture.luau` checks 7,644 shipping-renderer draws across weapons, moves, other states,
  both facings and both LODs. Every sprite is checked for shear. Joints, waist overlap, neck,
  weapon/hand equality, and the weapon's original authored anchor are checked independently.
- Idle foot coordinates and knee separation are checked throughout breathing. Explicit properties
  cover counter-rotation, head lag, shoulder rise, rest bends, action bends and overhead ledge reach.
- Real Canvas2D Frames in Lune retain their child Instances through moving poses. Across the kit
  presets: peak 228 body child Frames, at most 20 more than the old art. A local 600-draw warm run
  measured about 0.13–0.15 ms per fighter; this is not a Roblox device benchmark.
- Existing kit-draw joint/grip/planted/shear checks remain. Its state sweep now sets `Fighter.sf`,
  which Snapshot encodes, instead of setting an unused `Fighter.stateFrame` field. Creator/climb
  tests now expect the exact 12/8-piece bodies, still rejecting missing or duplicated parts.

## Deliberate mutations

Each mutation below was applied independently, failed `lune run tests/posture` at the corresponding
assertion, and was restored before the clean checks. Full failure output is in
`/tmp/charplan/posture-mutations.log` and `.json`; the repeatable driver is
`/tmp/charplan/mutate-posture.py`.

1. Offset a lower segment's joint by 0.1: joint equality failed.
2. Extend the drawn hand 0.1 past its endpoint: hand/grip equality failed.
3. Add 40 rectangles per segment: child Frame budget failed.
4. Raise the rest front elbow to 65°: rest elbow limit failed.
5. Raise rest knees to 55°: rest knee limit failed.
6. Fold the back elbow to 100°: back elbow limit failed.
7. Swap the hip-root signs: knee separation failed.
8. Add hip sway to foot x: planted x failed.
9. Add bob to foot y: planted y failed.
10. Remove idle hip sway: weight-shift range failed.
11. Remove the added chest breathing (isolated from Channels' squash): breathing range failed.
12. Remove hip rotation: strike counter-rotation failed.
13. Weld chest rotation to abdomen rotation: strike counter-rotation failed.
14. Remove the three-frame head delay: head lag failed.
15. Remove wind-up elbow loading: action bend failed.
16. Remove crouch knee bending: crouch bend failed.
17. Remove run chest swing: stride counter-rotation failed.
18. Clamp the ledge support arm to the hanging-arm range: overhead reach failed.
19. Remove shoulder rise: overhead shoulder motion failed.
20. Offset waist y by 0.4: torso join failed.
21. Cut the chest at the waist, with no overlap: painted waist coverage failed.
22. Offset head y by 0.2: neck attachment failed.
23. Draw the lower segment over the upper: hidden top-edge order failed.
24. Remove the joint bevels: corner coverage failed.
25. Scale limb width by 1.4: constant thickness failed.
26. Restore inherited torso squash on the weapon: weapon shear failed.
27. Scale the head before rotating it: head shear failed.
28. Move BOTH hand and weapon by 0.2: independent authored-grip check failed.
29. Disable the art cache: picture identity failed.
30. Include time in each sprite key: Frame child reuse failed.
31. Draw the chest twice: body sprite count failed.

## Images inspected

All images came from the shipping renderer. The before images use this branch's original
Fighter2D source. No image-generation or image-editing model was used.

| View | Before | After |
| --- | --- | --- |
| Jab / dash slash / forward aerial | `/tmp/charplan/posture-before.png` | `/tmp/charplan/posture-after.png` |
| Idle / run / squat and landing | `/tmp/charplan/posture-rest-before.png` | `/tmp/charplan/posture-rest-after.png` |
| Seeded match, frames 25 / 60 / 120 | `/tmp/charplan/posture-fight-before.png` | `/tmp/charplan/posture-fight-after.png` |

Also inspected `/tmp/charplan/posture-mirrored.png` (knight, facing left) and
`/tmp/charplan/posture-half.png` (half-resolution Classic, facing left). The initial two-row waist
version is `/tmp/charplan/posture-v1.png`; overlap was increased after inspecting it.

Reproduce from roblox/:

```sh
lune run tools/render-poses /tmp/charplan/poses.json Sword LightNeutral1,LightSide1,AirForward Classic
node tools/fight-png.mjs /tmp/charplan/poses.json /tmp/charplan/poses.png 3 2
lune run tools/render-posture /tmp/charplan/rest.json Classic 26 1
node tools/fight-png.mjs /tmp/charplan/rest.json /tmp/charplan/rest.png 3 2
lune run tools/render-fight /tmp/charplan/fight.json Sword 25,60,120 Classic FoundryFloor 2 7 right brawl
node tools/fight-png.mjs /tmp/charplan/fight.json /tmp/charplan/fight.png 1 1
```

## Limits

Studio tools were discovered and reported a running Studio instance. Its Luau inspection was
rejected because this session's approval policy is `never`; no live game was modified. PNG review
and Lune Frame geometry are verified, but live Studio appearance and lowest-device performance
still need a playtest. Authored attack/run foot trajectories are preserved, so moving legs can
still cross; the rest stance is separated. The art stays blocky, and strong bends retain a visible
pixel corner rather than becoming round limbs.

Commit preparation was blocked: `git add` could not create the index lock under the parent
repository's `.git/worktrees/gpt-posture/` because that directory is outside the writable sandbox.
The changes remain in feature/gpt-posture's working tree. `/tmp/charplan/posture.patch` contains the
complete patch; `/tmp/charplan/posture-commit-message.txt` contains the intended message and required
co-author trailer.
