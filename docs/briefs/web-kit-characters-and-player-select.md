# Brief: bring the Roblox character kit to the web game, and make player select look amazing

You are working on **Blockfall Knockout**, a 2D platform fighter. It exists twice in one repository:
a finished JavaScript web game in `web/` (published on CrazyGames) and a Roblox port in `roblox/`
(Luau). Your job is web-only: bring the Roblox build's pixel-art character system — the
"character kit" — into the web game, so web players can build, save and fight as kit characters,
and rebuild the web player-select / character screens so they look and feel great.

Work on the branch `revamp/sprites-disasters` (or a new branch cut from it). Read `AGENTS.md` at the
repository root before you start, and `roblox/README.md` if you touch anything shared.

---

## 1. Rules of this repository (non-negotiable)

1. **`web/` is the source of truth.** The Roblox build is held to it by replay tests
   (`roblox/check.sh`), not by review. Anything in `web/src/data/**`, `web/src/engine/**` and
   `web/src/render2d/avatarCompose.js` is **shared**: the Roblox build is generated from it or ported
   line for line from it.
   - **Do not change** `web/src/data/avatarParts.js`, `web/src/data/avatarKit.js` or
     `web/src/render2d/avatarCompose.js` unless you absolutely must. You should only need to
     *consume* them.
   - If you do change a shared file, you must make the same change in the Luau port in the same
     commit and run `cd roblox && ./check.sh` (it needs `rojo`, `lune` and `luau-lsp` from Rokit; see
     `AGENTS.md`). If you cannot run it, stop and say so. Do not guess.
   - Never edit `roblox/src/shared/Data/**` or any `roblox/tests/*-fixture.json`/`trace-*.json`:
     they are generated.
2. **UI is not shared.** `web/src/ui/**`, `web/src/render2d/renderer2d.js`, `web/src/render2d/avatar2d.js`,
   `web/src/render2d/preview.js`, `web/src/main.js`, `web/index.html` and `web/style.css` are web-only.
   This is where your work goes.
3. **Tests are held to a high bar.**
   - `cd web && npm test` must pass (about a minute; the Skyline Climb solver takes about 33 s).
   - Every test you add must be verified by deliberately breaking the code it covers and seeing it
     fail. Do not weaken or delete an existing test to make something pass.
4. **The web build ships as static files** to CrazyGames. That means no new dependencies, no build
   step, no new network requests (Google Fonts is the only external request today) and no console
   errors. `node tools/export.mjs <dir>` makes the upload folder and checks every import resolves.
   Run it before you finish.
5. **Commit messages explain *why*.** The diff already says what.

---

## 2. What already exists, and what is missing

### The character kit (already in `web/`, shared with Roblox)

- `web/src/data/avatarParts.js` is the part catalogue.
  - **17 categories, 192 options:** build, head, ears, eyes, brows, nose, mouth, facialHair, hair,
    marks, top, neck, bottom, shoes, gloves, eyewear, headwear.
  - **8 colour slots,** each a curated swatch list: skin, hair, eyes, top, trim, bottom, shoes,
    accessory.
  - **18 presets.**
  - **`GROUPS`** gives the creator's tabs and display order: Presets, Body, Face, Hair, Outfit,
    Extras.
  - **Layout:** a character is five puppet pieces (head 18×20 cells, torso 16×18, arm 6×16,
    leg 7×18, pelvis 14×10), each with a joint `(ox, oy)` and a `span` (see `PARTS`).
- `web/src/data/avatarKit.js` holds the code format and its helpers.
  - **The code:** a character is `'k1'` plus one base-36 digit per category, then one per colour
    slot. That is 27 characters, and the code *is* the avatar id.
  - **Codec:** `encodeKit`, `decodeKit`, `canonicalKit`, `sanitizeKit` and `isKitCode`.
  - **Presets and defaults:** `presetKit(preset)` and `DEFAULT_KIT`.
  - **Resolving:** `kitAvatar(code)` turns a code into an avatar object with a palette.
  - **Earned parts:** `kitUnlocks(spec)` lists the rewards a character's parts need (see §5.4).
- `web/src/render2d/avatarCompose.js` does the composing (pure functions).
  - `kitSprites(codeOrSpec)` returns `{ head, torso, arm, leg, pelvis }`, each `{ full, half }`.
  - Each of those is a list of rectangles `[col, row, w, h, hex, alpha]` in cells, with **rows
    counted down from the top of the piece's canvas**.
  - `shadeRects(rects)` makes the darkened copy used for the far arm and far leg.
  - `half` is a half-resolution cut for when a cell is smaller than about 1.3 screen pixels.
- `web/src/data/avatars.js` already resolves kit codes: `avatarById('k1…')` returns `kitAvatar(code)`.
- `web/src/data/loadout.js` already builds a loadout from a kit code. A kit character is purely
  cosmetic: its stats are exactly the weapon's (`test/avatar-kit.test.mjs` checks this).

### What is missing in the web game (your job)

1. **The web renderer cannot draw kit characters.** `web/src/render2d/renderer2d.js`
   (`_fighter`, around line 270) draws every fighter as the block rig plus the old "features"
   (`avatar2d.js` `drawHead` / `drawTorsoMark`). A kit code in a match slot draws as a plain block
   figure today.
2. **The web character UI is the old system.** `web/src/ui/menus.js` has the "Characters" screen
   (around line 350) with the old feature-and-palette editor (`web/src/data/customAvatars.js`,
   localStorage, `MAX_CUSTOM = 24`). The match-setup screen's slots (around line 386) pick
   `avatarId` from `AVATARS` plus those old custom avatars. There is no kit creator on the web.

### The reference implementation (Roblox, Luau). Read these before designing anything.

- `roblox/src/client/Fighter2D.luau`, **lines 69–260**. This is how a kit character hangs off the
  rig. Every piece is drawn from the same joints and channel angles the block body uses:
  - **Cell size:** one cell is `PW = char.radius * 1.15 / 12` studs wide, a twelfth of the head,
    the same on every piece.
  - **Anchoring:** each piece is placed at its joint `(ox, oy)` from `KIT_PARTS`, x from
    `-ox * PW`, and its top edge at `oy * ph`.
  - **Head:** vertical cell size `ph = PW` (square cells), at the head joint.
  - **Torso:** `ph = (SHO - HIP) / torso.span`, spanning hip to shoulder.
  - **Pelvis:** `ph = h * 0.10 / pelvis.span`.
  - **Arms:** `ph = L / arm.span`, where `L` is the arm's drawn length, including the thrust
    extension `a.ext`. This is why the art stretches when a thrust extends the arm.
  - **Legs:** `ph = legLength / leg.span`.
  - **Far limbs:** the far arm and far leg use `shadeRects(...)`, a darkened copy.
  - **Level of detail:** use `half` when `PW × (on-screen scale) < 1.3` px (`KIT_LOD_PX`).
  - **Replacements:** a kit character draws **no** block head, chest mark or block limbs. The kit
    pieces replace them. The weapon, smears, effects, shields and team marks stay exactly as they
    are.
  - **Draw order:** follow the Luau.
- `roblox/src/client/Canvas2D.luau`, `eachSpriteRect` and `sprite`. These define the rectangle
  convention in a **y-up** world transform:
  - a rectangle's x is `x0 + col * pw`;
  - its y is `y1 - (row + h) * ph`;
  - its size is `(w * pw, h * ph)`.
  - `(x0, y1)` is the piece canvas's top-left corner.
  - Mirroring for facing −1 comes from the transform. The web canvas can simply `scale(-1, 1)`.
- `roblox/src/client/KitPortrait.luau`: still portraits (standing figure and head-and-shoulders)
  for tiles and cards. It uses the rig's standing proportions: `H = 5.2`, `R = 1.1`,
  `HIP = H*0.34`, `SHO = H*0.70`, `HEAD = H*0.78`.
- `roblox/src/client/AvatarEditor.luau` (about 1000 lines): the creator's UX, described in §4.
- `roblox/tests/kit-draw.luau`: the assertions the Roblox kit renderer meets. Mirror them in JS.

---

## 3. Task A: draw kit characters in the web renderer

1. **Draw the pieces.** In `renderer2d.js` `_fighter`, when `f.char.avatar.kit` is set (the avatar
   id is a kit code), draw the kit pieces instead of the block head, torso mark and limbs, placed
   as in `Fighter2D.luau` (§2). Keep everything else unchanged: channels (poses), squash/stretch,
   rotation pivot, smears, weapon, shield, team disc and chevron, ultimate cinematic and effects.
2. **Performance:** six kit fighters must hold 60 fps.
   - Do **not** `fillRect` hundreds of cells per fighter per frame.
   - Instead, pre-render each piece once per `code × piece × (full | half) × (near | far)` into
     an offscreen canvas at one pixel per cell, with `imageSmoothingEnabled = false`, and
     `drawImage` it with the piece's transform.
   - Remember the world is y-up: flip the piece vertically when you draw it.
   - Cache by code and evict unused entries.
   - `kitSprites()` is pure and deterministic, so its output can be cached too.
3. **Pixel crispness:** keep `imageSmoothingEnabled = false` on the main context while drawing
   kit pieces, so the pixels stay square at every zoom.
4. **The other screens:** the podium (`podium.js`), the menu previews (`preview.js`) and the HUD
   portraits (`web/src/ui/hud.js`) must show kit characters too.
5. **Tests** (new `web/test/kit-render.test.mjs`, added to the `test` script in `package.json`),
   using a recording stub canvas like `test/render.test.mjs`:
   - A kit fighter draws its five pieces (seven draws: head, torso, pelvis, two arms, two legs)
     and no block head or chest mark.
   - The head's joint lands at the rig's neck, and the feet at the floor (compare with the
     block rig's joint positions).
   - The far arm and far leg use the darkened copy.
   - Below the LOD threshold the half-resolution pieces are used; above it, the full ones.
   - A preset (non-kit) avatar still draws the block body exactly as before.
   - Every stage renders a frame with kit fighters without throwing (extend `render.test.mjs`).
   - Break each piece of this on purpose and confirm the test fails.

## 4. Task B: the character creator, on the web

Port the Roblox creator (`AvatarEditor.luau`) to the web UI, replacing or sitting beside the old
Characters screen. Its UX is the spec:

- **Tabs** from `GROUPS`: Presets, Body, Face, Hair, Outfit, Extras. Each tab has part buttons,
  and each part has a grid of option tiles.
- **Every option tile shows YOUR character with that option**, in your colours: the hair tiles
  are your face with each hair. Use `view` ('head' or 'body') per category to pick a head
  close-up or a full figure. Redraw only the tiles whose picture changed.
- **Colour swatches** for the slots the current part is painted in (the category's `paint`).
- **A big live preview** using the real renderer: animated, holding the chosen weapon, with pose
  buttons (idle, run, jump, attack, victory) and a face/body zoom toggle.
- **Undo and redo:** Ctrl+Z and Ctrl+Y, plus buttons.
- **Randomise:**
  - with a per-part **lock**, so the player can keep the face and roll the outfit;
  - a colour slot stays when every part painted in it is locked;
  - a "random part" button that always changes the current part.
- **Keyboard:** arrows move through options and parts, Q and E switch tabs, R randomises,
  Escape closes (asking first if there are unsaved changes).
- **Saving:**
  - up to 8 named characters, stored as **kit codes** in localStorage;
  - follow the `customAvatars.js` `browserStore` pattern (try/catch everything; private mode
    must not crash);
  - clean names to 20 characters of letters, digits, spaces and `.-_'`;
  - offer Save, Save as new, Delete (keeping at least one) and "wearing" (the default character
    for Player 1);
  - migrate nothing and break nothing: old custom avatars must still load and still draw.
- **Match setup:** any saved kit character can be picked for any slot.
- **Earned parts:** see §5.4.
- **Tests:** codes round-trip through save and load; garbage in storage degrades to a valid
  character; undo and redo; Randomise respects locks and never picks an earned part; the keyboard
  paths work. Drive the real menu code where you can (see `test/menu-state.test.mjs`).

## 5. Task C: make player select look amazing

This is the screen players see first on CrazyGames, so it has to sell the game. Keep the existing
art direction: dark steel with warm amber, the tokens in `style.css :root` (`--paper`, `--ink`,
`--leaf` amber, `--hot`, `--gold`, `--line`) and the display font. The Roblox creator's palette
is INK `#10141B`, PANEL `#1C222C`, PANEL2 `#262E3B`, LINE `#3A4556`, TEXT `#E8ECF2`, DIM `#8C96A6`
and AMBER `#EFB05A`.

1. **Character select grid**
   - A card per character (presets, then the player's saved kit characters) with an **animated
     idle portrait** drawn by the real renderer.
   - The name, and the weapon it is set to.
   - Hover/focus lift, amber focus ring, and a subtle idle bob.
   - A "+ New character" card that opens the creator.
2. **Player slots, fighting-game style.** Up to 8 slots, each with:
   - a large portrait of the chosen fighter, in the slot's player colour frame (P1…P8, matching
     the HUD colours in `hud.js`);
   - the input source (keyboard, gamepad, bot and bot difficulty);
   - the team (in team modes);
   - a **READY** state with a satisfying transition.
   - Empty slots show "Press a button to join" for gamepads and keyboard 2.
3. **Weapon picker:**
   - weapon art (`weapons2d.js`; `fit()` frames a weapon pixel-exactly in a tile);
   - stat bars (speed, power, reach, weight, taken from the weapon data);
   - the archetype and tagline;
   - a short looping preview of the weapon's signature move, if you can drive it from the preview
     renderer.
4. **Stage select:** thumbnails from `stageThumb.js`, with the name, hazards and the disaster
   setting shown, plus Random.
5. **Motion and feedback:**
   - CSS transitions of 120–200 ms;
   - staggered card entrance;
   - hover and select sounds through the existing `audio/sfx.js`;
   - nothing that blocks input, and `prefers-reduced-motion` respected.
6. **Input everywhere.** Everything must work with the mouse, the keyboard and a gamepad (the
   game already reads gamepads in `engine/input.js`), with a visible focus state throughout.
7. **Responsive.** The game runs in the CrazyGames iframe:
   - it must look right from 800×450 up to 1920×1080;
   - nothing is cut off at 16:9 or 16:10;
   - no page scroll during menus.
8. **Performance:** idle menus must not burn CPU. Animate only what is on screen, and pause the
   previews when the tab is hidden.
9. **Accessibility:** buttons are real `<button>` elements, cards have labels, and text contrast
   is at least 4.5:1.

### 5.4 Earned parts (important)

Two kit options carry an `unlock` field:
- `headwear: 'skylineCrown'` (Skyline Crown);
- `neck: 'summitMantle'` (Summit Mantle).

They are rewards for reaching the top of the Skyline Climb **in the Roblox game**, and the web
game has no way to earn them. So on the web:
- show them, if at all, **locked** with the note "Earned on the Skyline Climb in Blockfall on
  Roblox";
- never let them be chosen, randomised or saved.

`kitUnlocks(spec)` tells you whether a character wears any. A pasted or imported code that wears
one must be refused or cleaned.

## 6. Natural disasters: already done, do not re-implement

The disaster visuals are **already at parity**:
- `web/src/render2d/disasterShapes.js` (the shared shape lists, which Roblox ports as
  `DisasterShapes.luau`);
- the warning banner in `renderer2d.js` (`_disasterBanner`);
- the disaster setting in the match rules.

Roblox has no disaster art the web lacks, so there is nothing to port. Two things to keep in mind:
- **Do not change** `disasterShapes.js` or `engine/disasters.js`. They are shared, and
  `roblox/check.sh` replays them.
- **Do surface disasters in the new UI:** show the disaster setting (off / stage / chaos) and each
  stage's disaster types on the stage-select cards, so players know what they are choosing.

## 7. Definition of done

- `cd web && npm test` passes, with the new tests added to `package.json` and each one
  mutation-checked.
- `node web/tools/export.mjs /tmp/bk && python3 -m http.server 8124 --directory /tmp/bk` works.
  In a browser at 800×450, 1280×720 and 1920×1080:
  - the game loads with no console errors and no failed requests;
  - a kit character can be built, saved, picked for a slot and fought with;
  - kit characters look right in the fight, the HUD, the podium and the menus;
  - six kit fighters run at 60 fps.
- No shared file changed. If one did, the Luau port matches it in the same commit and
  `roblox/check.sh` passes.
- Old saved custom avatars still load and draw.
- **Report plainly** what you verified in a real browser and what you could not. Include
  screenshots of the creator, player select, weapon picker and stage select.
