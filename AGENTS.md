# Working in this repository

Blockfall is a 2D platform fighter that exists **twice**: a finished, playable JavaScript build in
`web/`, and a Roblox port in Luau under `roblox/`. Read this before changing either.

## The one rule everything else follows from

**`web/` is the source of truth. The Luau port is held to it by replay, not by review.**

`roblox/check.sh` drives the real JavaScript classes, records what they did frame by frame, replays
the same scripts through the Luau, and fails on the first value that differs — about 5.4 million of
them across fourteen suites. This is not a formality. Every one of those suites exists because a
port drifted from the JavaScript and nobody noticed by reading.

Three consequences:

- **Never edit `roblox/src/shared/Data/**`.** It is generated from `web/src/data/**` by
  `roblox/tools/gen-data.mjs` and regenerated on every `check.sh` run. Change the JavaScript.
- **Never edit `roblox/tests/trace-*.json` or `*-fixture.json`.** Same: regenerated every run, and
  gitignored. A check that compares the port against a committed snapshot of its own source can
  only catch drift somebody already noticed.
- **A change to shared behaviour must land in BOTH builds in the same commit.** If you change
  `web/src/render2d/channels.js` you must make the same change in `roblox/src/client/Channels.luau`.
  Parity fails by design otherwise. This has happened four times so far and each is written up in
  `roblox/README.md`.

## Verifying your work

```bash
cd roblox && ./check.sh      # the whole thing: generate, type-check, replay. Exit 0 or it failed.
cd web && npm test           # the JavaScript's own suite, 13 files
```

`check.sh` bootstraps what it needs and tells you how to install the rest. It needs `node`, plus
`rojo`, `lune` and `luau-lsp` from Rokit:

```bash
curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
rokit add --global rojo-rbx/rojo JohnnyMorganz/luau-lsp lune-org/lune
```

**Run `check.sh` before you claim anything works.** It is the only thing in this repo that can tell
you the port still matches, and it takes under a minute.

## Verifying the parts `check.sh` cannot reach

`check.sh` proves the simulation and every ported piece of pure logic. It cannot tell you whether
anything *looks* right, or what it costs at runtime.

**Check whether you have Roblox Studio tools available** (an MCP server exposing Studio — you will
have tools for listing Studio instances, running Luau in them, and reading their output). Whether
you do depends on how you were set up, so look rather than assume.

**If you do**, use them. The workflow that works:

- `rojo serve` from `roblox/` syncs the source into an open Studio; the Studio plugin must be
  connected, and it needs Script Injection permission or it silently applies nothing.
- Start play, then read the console. `[Blockfall]` lines trace the match; a renderer error shows up
  as one warning per fighter, not a crash, because each rig is posed inside its own `pcall`.
- To see what was drawn, walk the GUI tree rather than screenshotting: the game renders entirely
  into a `ScreenGui`, so a viewport screenshot is empty. Read `Position`, `Size`, `Rotation` and
  `BackgroundColor3` off the Frames — **not `AbsolutePosition`**, which is a deferred layout result
  and gives you the previous frame's values when read in the same tick.
- `require` caches for the session: restart play after a sync or you are testing the old module.

**If you do not**, you can still count Frames and time a draw by calling it against a `Canvas2D` in
a Lune test — but you cannot know it looks right. Say so plainly in your summary and hand that part
back. **Never describe unverified rendering as working.**

## Testing discipline

The bar in this repo is higher than "the test passes":

- **Every test here was verified by deliberately breaking the code and confirming it failed.** If
  you add a test, mutate the thing it covers and check it catches it. Several tests in this repo
  were found to be asserting nothing that way.
- **A parity test alone is not enough for behaviour.** It proves the two builds agree; it cannot
  tell you they agree on something *wrong*. Where behaviour matters, assert the property directly —
  see the tumble assertions in `roblox/tests/channel-parity.luau`.
- **Do not weaken a test to make it pass.**

## Layout

| | |
|---|---|
| `web/src/engine/` | the simulation: fighter, combat, stage, match, knockback, ai, hazards |
| `web/src/data/` | weapons, avatars, stages, items — pure data, the source of the generated Luau |
| `web/src/render2d/` | the 2D renderer: channels (poses), weapons2d, avatar2d, renderer2d |
| `web/src/ui/` | HUD and menus, as DOM. These do NOT port; they are rewritten as ScreenGuis |
| `roblox/src/shared/` | the ported simulation, shared by client and server |
| `roblox/src/server/` | MatchService (the 60Hz loop), RemoteInput, entry point |
| `roblox/src/client/` | canvas renderer, prediction, HUD, input |
| `roblox/tests/` | the replay harnesses. `loader.luau` shims `script`, `game` and Color3 so client modules can be tested outside Roblox |
| `roblox/tools/` | the generators that produce the Luau data and the test fixtures from `web/` |

`roblox/README.md` is long and worth reading before touching the port. It documents the traps this
port has already hit — Luau's 1-indexed arrays, `math.round` vs `Math.round`, `sign(0)`,
`table.insert(t, nil)` — and a table of code that is unreachable with the current data.

## Roblox specifics that have caused real bugs

- **Luau arrays are 1-indexed.** JavaScript code indexing `arr[i - 1]` becomes `arr[i]`. This has
  bitten the port more than once; the damage colour ramp and the swing arc tables both.
- **`math.round` is not `Math.round`.** Luau rounds halves away from zero, JavaScript rounds toward
  +infinity. Use `math.floor(x + 0.5)` for the JavaScript's behaviour.
- **`0` is truthy in Lua.** `a or b` is not `a ?? b`: JavaScript's `||` also falls through on `0`.
- **`AbsolutePosition` is a deferred layout result.** Reading it in the same frame you set
  `Position` gives you the *previous* frame's value. Read `Position`/`Size`/`Rotation` instead.
- **`require` caches for the session.** Changing a ModuleScript does not affect a running playtest
  until it is restarted.

## Commits

Explain **why**, not what — the diff already says what. When a change fixes something found by
playing, say what the symptom was and what the cause turned out to be; when an investigation ruled
things out, say what was ruled out, because that is what stops the next person re-checking it.
