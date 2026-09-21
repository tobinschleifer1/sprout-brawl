# Game audit and first dark pixel-art pass — September 21, 2026

## Scope and baseline

Audited the current web game and Roblox port, then began the requested dark, gritty, rich
pixel-art direction. The working tree was clean before this pass. Both `roblox/check.sh` and
`cd web && npm test` exited 0 before changes. This is a broad regression audit, not a claim
that every possible gameplay, multiplayer or device bug has been eliminated.

## Bugs fixed

- Web pickup P also paused the game; Keyboard 2's M grab could mute music. Pause is now Esc,
  and mute yields to the second player's controls. Advertised punctuation-key controls now
  work alongside numpad aliases. Text entry and repeated shortcut events are ignored.
- Disconnected web gamepads retained stale button edges, suppressing presses on reconnect.
- Invalid saved web settings/slots could break Quick Play. Saved values are validated and
  normalized against supported choices and defaults.
- The web preview server could crash on malformed URL escapes, and its string-prefix path
  check admitted sibling paths. It now rejects malformed/outside-root paths and binds localhost.
- Roblox D-pad movement depended on gamepad-state enumeration order; a neutral stick could
  erase it. Typing in chat could also drive a fighter. Both are covered by direct tests.
- Count-based prediction depended on inputs arriving reliably and in order, but used an
  unreliable remote. Input now uses a reliable ordered RemoteEvent; fighter snapshots remain
  unreliable. Input packet iteration is bounded to its numeric prefix.
- Old match traffic could reach a new match. Input, fighter snapshots and scene packets now
  carry a match generation, and client input/prediction buffers reset between rounds.
- Disconnected Roblox players could keep moving from repeated held input; their input state
  is now removed. Prediction history before the first snapshot is now bounded as well.
- Held-item snapshots read `item.id`, but live items store `item.def.id`.
- Rematch weapon/avatar callbacks captured an obsolete configuration. They now use the active
  configuration, saved rematch choices are normalized, and delayed teardown cannot stop a newer match.
- Selection rows overflowed the fixed panel. Rows scroll horizontally, the panel scales to the
  viewport, and the opponents summary sits between its row and the Fight button.
- The lobby emitted a misleading missing-snapshot warning before any match was requested.
- Roblox simulated world objects and hazards that its client did not draw. A separate reliable
  scene stream now carries serializable authoritative state for projectiles, all five items,
  placed plates, summons, bursts and all ten hazard families. Client visuals do not run physics.

## Art and graphics

- Six distinct layered industrial backdrops: dark silhouettes, warm furnaces/windows, cool
  atmospheric accents, pixel suns/stars and camera-relative parallax.
- Shared authored rectangle recipes live in `web/src/data/art.js`; the normal generator creates
  the Roblox data. Both builds use those recipes, with canvas gradients in web and pooled strips
  in Roblox. No uploaded image assets are needed.
- All twelve weapons received a first detailing pass: wraps, runes, inlays, vents and rivets.
  This is an enhancement of the existing silhouettes, not a complete weapon redesign.
- The web menus/HUD use dark metal panels and amber accents. Existing custom stage backgrounds
  retain priority. A low-contrast damage badge found in visual review was corrected.
- Roblox world-effect art is a simplified pooled-rectangle interpretation, not pixel-identical
  parity with every web particle or ultimate world effect.

## Verification

- Final `roblox/check.sh`: exit 0 after the last code changes, including generation, type checking,
  all replay suites and the new runtime-input/world-scene tests.
- Final `cd web && npm test`: exit 0, now 17 test files.
- The soak run completed 144 matches / 684,265 simulation frames (190.1 simulated minutes),
  covering all six stages and twelve weapons without crashes or non-finite state.
- New scene tests exercise live hazard simulations on every stage, require all ten hazard
  families to emit drawing primitives, serialize a deliberately cyclic projectile safely,
  and draw all five items. Background draw counts are bounded at multiple viewport widths and
  camera positions; the tested entity group peaked at 29 Frames.
- Ten deliberate regressions were introduced, observed failing, then restored: shortcut
  collision, missing background draw, invalid saved slots, malformed URL crash, unreliable
  input, missing scene projectiles, wrong held-item field, prediction history leak, ignored
  rematch stocks, and the opponents-summary overlap.
- Browser review covered title/menu styling, an in-game view and the six-stage background gallery.
- Fresh Studio playtest: Input and Scene are RemoteEvents; 119 scene packets arrived in four
  seconds with live Smeltworks hazards. The match reached results. GUI inspection counted 300
  allocated Frames / 270 visible at the sampled instant, with zero non-finite Position/Size/
  Rotation values. No renderer errors appeared in the console.
- A second fresh Studio session confirmed the final menu: 1003-pixel weapon canvas inside a
  710-pixel scrolling row, opponents row ending at y=458, summary y=462–476, Fight beginning
  at y=480. The idle lobby no longer printed a missing-snapshot warning.

## Remaining verification and handoff

- Still needs real multi-client latency/loss testing, sustained scene-stream bandwidth testing,
  mobile/gamepad hands-on QA and low-end-device profiling. Frame counts are not frame-time proof.
- Full human visual review in Studio remains necessary for all attacks, items and hazard phases;
  GUI-tree checks establish runtime output and valid geometry, not final artistic quality.
- Audio, durable Roblox persistence and matchmaking remain separate work. This pass does not
  claim to implement them or every remaining web-only rendering flourish.
- Studio playtests started for this audit were stopped. No private Rojo server was started;
  the existing shared Rojo server was used for sync and left intact for the next editor.

The preceding completed task was the twelve-weapon ultimate-VFX pass (commit `104991a`). This
pass followed it with bug fixes, world visibility and the first shared environment/weapon-art update.
