# Characters: better made, full of life

The character rework, agreed 2026-10-11. Two authors: Claude, with OpenAI GPT working through the
Codex CLI. GPT drafted an independent proposal from the code; a Claude Sonnet sub-agent mapped the
character pipeline and a Haiku sub-agent gathered the facts; Claude merged them and checked every
claim against the code; GPT critiqued the merge and its corrections are in. Phases land one at a
time, each on its own branch, in both builds, held by tests, with a Studio playtest at the end.

## What the owner decided

- **Cosmetic only, deeper feel.** Weapons keep every stat. No body, part or animation changes a
  hitbox, weight, speed or timing. "How characters operate" means how they feel: stance, movement,
  reactions, faces, emotes, victory.
- **Blocky, on a far better rig.** The Roblox-blocky look stays (square heads, block bodies, crisp
  outlined pixels), rebuilt with elbows and knees, hands and feet, and faces that carry expression.
- **Creator plus earned parts.** The character studio grows; some parts are earned through play, and
  later the shop grants the same kind of entitlement.
- **Plan, then phase 1.**

## Where characters stand today

- **Three body systems.** The legacy feature avatar (six presets; 4 heads, 6 faces, 6 hats, 4 torso
  marks, 5 colours; `avatars.js`, drawn by `avatar2d.js` / `Avatar2D.luau`); hand-drawn pixel parts
  (web only, through the old editor); and the kit (`avatarKit.js`, `avatarParts.js`: 17 categories,
  192 options, 8 colour slots, 18 presets, a 27-character `k1` code that is the avatar id; composed
  by `avatarCompose.js` / `AvatarCompose.luau`).
- **Who gets which.** Roblox players already start on a kit body: `AvatarStore` hands every new
  player a default kit and the client wears it when the avatar view arrives. But `Classic`, the
  legacy body, is still the hard-coded fallback in room profiles (`Rooms.luau`), the default match
  config (`MatchConfig.luau`), the web's default select and its menus, and some bot looks. On the web,
  a new player is on the legacy body.
- **A five-piece puppet.** A kit fighter is seven sprites (head, torso, pelvis, two arms, two legs)
  at fixed joints - hip 0.34, shoulder 0.70, head 0.78 of a 5.2-stud height. There is no elbow, knee
  or foot: each limb is one rigid piece rotated at the shoulder or hip, and arm extension stretches the
  sprite, distorting the hand. The torso carries all the squash, stretching the pixel art unevenly.
- **Good motion, little articulation.** `channels.js` and its exact Luau twin give anticipation,
  easing, follow-through, limb lag, squash, hit reactions and tumble (632,408 replayed values). Every
  body shares one timing. Walking reuses idle; a KO'd fighter is simply not drawn (both renderers
  return before drawing one); the only expressive states are `taunt`, `victory` (a hop and a fist)
  and `defeat`.
- **Faces are frozen** at what the creator chose.
- **Divergences no test sees.** The web draws a hit-flash box over every fighter; Roblox re-tints kit
  sprites instead. Roblox's composed-sprite cache is unbounded (the web keeps 32 codes).
- **A code-format trap** (found by GPT, verified). `k1` writes the category digits, then the colour
  digits, so appending a category - which the comment in `avatarKit.js` calls safe - shifts where
  every old code's colours are read. Options may be appended to a category; categories may not be
  added without a new version. And `canonicalKit` rewrites any accepted code into the current format,
  so a migration must not decode and overwrite blindly.
- **Cost.** A kit fighter is about 81-199 rectangles at full detail and 53-89 at half. Roblox draws a
  sprite as one EditableImage where it can, else as pooled Frames; on the Frame path a change of
  picture (an expression, a tint) can rebuild a sprite's child Frames, and body sprites are never
  deferred. A fighter is about 26 px tall at the default zoom, so a kit cell is under a pixel at most
  zooms - hence the half-detail level.

## The target

**A kit body for everyone.** The six legacy presets become kit codes that read like them, under the
same ids (`Classic` still resolves, to its kit lookalike), so every save, room and reference keeps
working. Hand-drawn web characters are preserved and still selectable.

**The rig: eleven pieces.** Head, torso, pelvis, two upper arms, two forearms with hands, two thighs,
two shins with feet. Shoulders, elbows, hips and knees are named anchors in kit data. Proportions stay
blocky: a head about 28% of the figure, a compact torso, a clear gap between the legs in stance, big
rectangular hands and shoes. Limbs bend instead of stretching; squash is brief and broad.

**The grip is an invariant.** Today the front arm and the weapon share one endpoint, computed from the
weapon's angle and the arm's extension inside the torso's lean and squash. The new elbow is solved
between that exact shoulder and that exact endpoint, and the weapon is drawn from the unchanged
endpoint - so the blade-to-hitbox geometry tests keep holding. When the target is further than the two
segments reach, the arm straightens and extends along its line (the current behaviour); the grip never
silently moves. Tested in world coordinates, both facings, every thrust, extreme squash and trails.
Legs get knee and foot targets that keep feet on the floor, with nothing changed in the simulation.

**Faces that act.** The player's chosen eyes, brows and mouth are the neutral identity; the game
derives blink, focused, effort, hurt, startled, delighted and dejected from them, each baked into a
head variant. Visors, goggles and masks get equivalents (a lit slit, a tilt). Blinks come from the
fighter's index and frame count, so both builds agree to the frame. Every expression must still differ
from neutral at half detail.

**A full performance.**

| Performance | What it shows |
|---|---|
| idle, walk, run, dash | a breathing ready stance; real low-speed steps; a full stride; explosive first frames |
| jumpsquat, rise, apex, fall, fast-fall, landing | load, trail, hang, search for ground, commit, compress and settle |
| attack startup / active / recovery | the move's warning, contact and follow-through - weapon timing stays authoritative |
| hitstun, tumble, knockdown, breakout, tech, stunned | impact direction, a tucked spin, stirring, the escape, the recovery, dizziness |
| shield, spotdodge, airdodge | brace, duck through, roll through |
| ledge, ledge actions, helpless, recovery, respawn | effort, the chosen action, lost control, regained control, a clear re-entry |
| grab, holding, grabbed, flung, team catch and throw | readable hands and bodies in every special interaction |
| taunt, emotes, victory, defeat, KO departure | personality; a short cosmetic exit as a fighter goes out, driven by the KO event - it cannot delay any rule |

**Secondary motion.** Hair, capes, scarves and coat tails trail the body (a lagged channel, the same
technique as the existing limb lag).

**Emotes and victory.** The taunt key plays one of four chosen emotes, and each character has a
chosen victory pose for the podium. Some are earned. They change nothing in play.

**Attitude** (last). Measured, restless or showy: idle accents, taunt, podium pose and expression
preference within fixed timing bounds. Never telegraphs, input response or hit timing.

**The catalogue.** All 17 categories grow from 192 options to about 221, weighted toward what reads at
fight scale (heads, eyes, mouths, hair, tops, bottoms, headwear). Earned parts show in the studio with
their source and a lock; randomise skips what a player does not own. Skyline Climb's two rewards are
the first; progression and the shop grant the same entitlement later, validated where saves are
checked today (`AvatarStore.luau`).

## How it is built

- **Data-driven, web-owned.** Anchors, piece sizes, layer masks, expression substitutions and pose
  parameters live in web data and are generated into Luau like everything else. `channelsFor` and its
  twin stay pure functions and gain elbow, knee, foot and expression outputs.
- **Parity at the drawing boundary, not only the data.** Kit parity compares codes and composed
  rectangles; channel parity compares pose values. New matched web/Luau checks compare what is drawn:
  transformed joint and grip positions, the chosen expression, the detail level and the piece order.
  The current draw tests expect seven sprites and legacy presets; they are replaced with assertions
  that mean something for the new rig, never just loosened.
- **Direct properties too.** The hand meets the grip; feet stay on the floor through landings; joints
  line up across every pose; every expression differs from neutral at both detail levels; appearance
  never changes a loadout (the existing avatars test, extended).
- **A measured draw gate.** Rectangle limits are set from measurement, not guessed: the current test
  allows 260 at full and 140 at half detail; the new rig's typical and worst compositions are measured
  first and the gate set from that. In Studio, six fighters with weapons, trails and hit flashes, on
  both the image path and the forced-Frame fallback: peak live instances, sprite rebuilds, property
  writes, image memory and frame time - through expression changes and hit flashes, where the Frame
  path rebuilds. Every cache is bounded: the composed sprites, the images, the tints, the per-slot sets.
- **Codes stay readable forever.** `k1` decodes indefinitely and its round trips are tested in both
  builds. Anything that needs a new category - attitude, the emote set, the victory pose - goes in an
  explicit `k2`, specified before anything is stored: version-specific decoding, canonical ids, save
  migration and room validation, and old codes keep rendering in matches.

## Phases

Each on its own `feature/` branch off `main`, merged when `check.sh` and `npm test` pass; every new
test is mutation-checked; each ends with a Studio playtest.

1. **A kit body by default.** The six presets become kit lookalikes under their old ids; defaults,
   the select screens, bots, rooms, the default match config and saved-config fallbacks all use them,
   in both builds. The legacy rig stays only for hand-drawn web characters. The `avatarKit.js`
   comment is corrected. Verified: every preset id resolves and draws as a kit; old saves, rooms and
   room profiles that say `Classic` still load; stats are byte-identical for every preset; the kit
   parity and draw tests updated with real expectations; a Studio look at all six.
2. **Faces that act.** The expressions, baked per head; blink timing; visor and mask equivalents; the
   studio preview shows them. Every cache bounded, including the Roblox composed-sprite cache. Proven
   on the existing head before it multiplies across eleven pieces: readability at half detail, and the
   cost of an expression change on the Frame path.
3. **The articulated rig.** Joint data moved out of the renderers; eleven pieces; the grip invariant;
   foot targets; one hit-flash behaviour in both builds; parity at the drawing boundary; the measured
   draw gate. Starter parts first, then every part. Risks: gaps at joints and rectangle growth.
4. **Movement and combat feel.** Walk, the revised run, jumps and landings, hit reactions, tumble,
   defence, ledges, secondary motion. Combat timing and hitboxes untouched. Risk: a clearer body makes
   an unchanged attack look early or late - checked against the blade-to-hitbox geometry tests.
5. **Codes and entitlements.** The `k2` format and its migration; one entitlement model (owned parts,
   emotes and poses; earned now, bought later) checked on save and in rooms.
6. **Emotes, KO and the podium.** Four emote slots on the taunt key, chosen victory poses, a KO
   departure driven by the KO event (the fighter's simulated lifetime unchanged), the new rig on the
   podium, in previews and in portraits.
7. **The catalogue and the studio.** About 29 new options with their own motion, expression previews,
   earned labels and locks; the studio rebuilt to the v3 mockup's hierarchy (presets, body, face, hair,
   outfit, extras; stand, run, jump, attack and cheer previews) with a proven phone layout. The v3
   mockup's fighter is drawn anime-pixel, not blocky: its layout is the reference, not its art.
8. **Attitude.** Selectable attitudes, stored in `k2`.

## Answered (2026-10-11)

1. **Attitudes** are measured, restless and showy.
2. **Earned cosmetics are Roblox-only.** The web build has no account to earn into; it keeps stripping
   earned parts from imported codes, as it does today.
3. **Hand-drawing stays a creator mode** on the web. Hand-drawn characters keep their pixel art and
   the legacy rig that draws it; nothing converts them.
4. **The performance target is the lowest devices**, so everyone can play without lag. Every phase's
   draw budget is set for a low-end phone on Roblox's Frame fallback (no EditableImage), not for a
   desktop: the six-fighter Studio measurement runs with the image path forced off, and a phase whose
   characters cost more than the fighters they replace has to buy that cost back (detail levels,
   fewer pieces at small sizes) before it merges.
