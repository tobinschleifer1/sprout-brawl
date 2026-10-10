# Blockfall native pixel UI — implementation package

Built 7 October 2026 from the live Studio Ui interface and Study 03 visual direction.

## Deliverables

- `dist/BlockfallPixelUI.rbxm`: importable Folder containing native `Ui` and `Screens` ModuleScripts.
- `dist/BlockfallPixelUIDemo.rbxl`: standalone place with a local demonstration adapter. Open separately and Play to inspect controls.
- `src/Ui.luau`: compatible live `Ui` API, square pixel edges, navy/blue/gold palette, bevels, display lettering, keycaps, panels, pixelated image slots and ten-block meters.
- `src/Screens.luau`: native ScreenGui builders, data-driven screen models, input callbacks, responsive fitting, renderer lifecycle hooks and allocation-stable HUD updates.
- `Verify.luau`: Studio smoke checks. Pass the two required modules into its returned function.

This package is ready to import and wire into the game. It is not installed in the current live place. Generated mockup PNGs are not used as backgrounds or click maps. The richer environments and fighter poses in those illustrations are art references, not shipped Roblox sprite assets.

## Import

1. Import `dist/BlockfallPixelUI.rbxm` into ReplicatedStorage using Studio's model insertion from file.
2. Require `ReplicatedStorage.BlockfallPixelUI.Screens` from the current client controller.
3. Supply real model data and connect action callbacks to the existing controller. Keep server authority for room state, votes and purchases.
4. Connect `mountArt` to the current fighter/arena renderer, or supply Roblox image IDs owned by the experience. Empty art slots are transparent so the game's world remains visible.
5. Disable only the corresponding old overlay once its replacement is wired and visually verified. Do not run two interactive overlays for the same screen.

The local checkout is older than the running place: it lacks the live `SelectScreen`, `AvatarEditor` and `PodiumView`. This package deliberately leaves the existing entry point alone. Bring the live client source into version control before replacing those controllers. Never sync the entire older checkout over the live place just to install this UI.

## Minimal usage

```lua
local Screens = require(game.ReplicatedStorage.BlockfallPixelUI.Screens)
local screen = Screens.new(game.Players.LocalPlayer.PlayerGui, function(request)
    -- Dispatch to the current client controller, with its real validation/remote path.
    -- request = { action, value, slot, id, revision }
    onUiRequest(request)
end)
screen:show("pick", modelFromAcceptedRoomState)
-- On each combat snapshot:
screen:updateHud(hudModel)
-- On controller shutdown:
screen:destroy()
```

Do not use the demo adapter in production. In the live game room phases advance from server state; Ready does not locally advance to map voting.

## Screen models

All models accept `title`, `status`, optional `background` Roblox image ID, room `id` and `revision`. A model is caller-owned; callbacks do not optimistically rewrite it. Call `show` on a page or structural change. Use `updateHud` for repeated combat snapshots.

| Page | Fields | Actions |
|---|---|---|
| `pick` | `weapons[{id,name,image?}]`, selected `weapon`, `ready`, `difficulty`, `slots[{name,teamColour,isLocal,empty,image,weaponName,stats[{name,value}],ready}]`, optional `botVote{message}` | weapon, ready, leave, hide, appearance, bot(value=difficulty,slot=index), ballot(boolean) |
| `maps` | `choices[{id,name,image,detail,votes}]`, `selected`, `seconds` | vote(id), back |
| `rules` | same choices, detail contains actual rule facts | rule(id), back |
| `board` | same choices for room boards, social lists, records or confirmation choices | choose(id), back |
| `studio` | `name`, `image`, `avatar`, `groups`, `group`, `categories`, `category`, `options`, `option`, `colors`, `color`, `locked`, `canUndo`, `canRedo` | name, group, category, option, color(index), pose, turn, zoom, slots, lock, random, undo, redo, saveNew, save, delete, close |
| `hud` | `fighters[{name,teamColour,isLocal,damage,damageColour,stocks,ultimate,eliminated}]`, `timed`, `clock`, `ability`, `spectating` | stopWatching |
| `results` | `players[{rank,name,teamColour,image,summary}]`, `returnStatus` | gg |
| `bazaar` | optional proximity `prompt` | interact, stamp, say, people, map, appearance |
| `climb` | `checkpoint`, `time`, `falls`, `canSkip` | leave, restart, records, requestPurchase |
| `notice` | `heading`, `message`, `error` | acknowledge only on error |

Use exact source weapon IDs, presets, stage IDs, stats and AvatarKit options. Slot indices must correspond to the server room array; sort its visual representation only if retaining a source index mapping. Team color should come from the current team palette. Feed percent color from the existing HudColors implementation, not a duplicate damage formula.

The native editor emits requests; AvatarEditor remains responsible for editing history, saved slots, unsaved-change and delete confirmations, persistence limits and rendering the actual avatar. Likewise social messages, bot removals/difficulty menus, six-player team grouping, cinematic events and purchases stay with their existing controllers. This package supplies reusable presentation, not replacement gameplay logic.

## Live Ui compatibility path

The new `Ui` module retains the currently observed exports: all color/font constants, `shade`, `keyLabel`, `topInset`, `make`, `corner`, `stroke`, `outline`, `text`, `button`, `paint`, `keycap`, `keyButton`, `textWidth`, `chipWidth`, `hintRow`, `panel`, `pill`. Existing callers can adopt it without changing callback signatures. `button`, `panel`, `pill` and keycaps have square borders in this variant; explicit callers of `corner` still receive their requested radius. This compatibility route changes shared chrome, not all existing layouts or scenery.

## Rendering hook

```lua
model.mountArt = function(target, kind, item)
    -- kind = fighter | avatar | choice | podium
    -- Read target Position/Size after layout to align the live Canvas2D projection.
    -- Bind the existing preview renderer; imageId is another supported path.
    local binding = attachExistingPreviewRenderer(target, kind, item)
    return function() binding:destroy() end
end
```

Cleanup runs before the screen is replaced and when the UI is destroyed. If using the world canvas, account for the centered 1280×720 design frame, its UIScale and Roblox safe inset; do not use same-tick AbsolutePosition as layout truth. All UI coordinates are available as Position/Size.

## Verification and limits

- Rojo built both model and demo place.
- `luau-lsp analyze` passed for the package and demo with Roblox type definitions.
- Studio created the native hierarchy under an unparented Folder and checked callbacks, room revision, renderer cleanup, editor fields, ten page types, stock clock behavior, HUD instance stability over 30 updates and destruction.
- Deliberately adding a Frame on every HUD update made the allocation assertion fail. Mutation was in-memory only and never written into the package.
- Main `roblox/check.sh` passed. No shared simulation or production client source changed.
- This verifies native construction and behavior, not visual fidelity. No live PlayerGui was replaced. In-game rendering, device safe areas, gamepad focus, touch target sizes and frame cost with actual art remain to be reviewed.
- Layout currently fits a 1280×720 design canvas uniformly inside the available safe area. It supports two to six HUD/selection cards, but phone layouts and six-player text sizes need an explicit visual pass. It is not yet a shipping mobile UI.

## Rebuild

From this folder:

```sh
rojo build model.project.json -o dist/BlockfallPixelUI.rbxm
rojo build demo.project.json -o dist/BlockfallPixelUIDemo.rbxl
rojo sourcemap demo.project.json --output /tmp/pixel-ui-sourcemap.json
luau-lsp analyze --sourcemap=/tmp/pixel-ui-sourcemap.json --definitions=../globalTypes.d.luau src demo
```
