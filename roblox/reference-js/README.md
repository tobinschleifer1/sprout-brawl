# Fighting & physics reference (JS → Luau source material)

These are copies of the combat/movement engine from the web build, pulled out so they can be
ported to Roblox without digging through the rest of the codebase (rendering, UI, audio). They
are copies, not symlinks — editing here does not affect the web build, and pulling changes from
the web build later means re-copying, not syncing.

## Port order (each depends on the ones above it)

1. **`config.js`** — every tunable constant: gravity, frame rate, shield HP/regen, ledge
   invincibility windows, dash/dodge frame counts, grab timing, knockdown/tech windows, throw
   data. Port this first; everything else reads from it.
2. **`engine/knockback.js`** — the whole damage model in ~35 lines: launch speed formula,
   hitstun/blockstun/hitlag duration, and the DI (directional influence) velocity calculation.
   Port this exactly, or knockback will feel different immediately.
3. **`engine/fighter.js`** — the per-player state machine: grounded/air movement, jumps, dash,
   shield, spot/air dodge, ledge grab (+ roll/attack/getup options), grabs and throws,
   hitstun/tumble/knockdown/tech, gravity and fastfall, and the per-character "mechanic" hooks.
   `step()` at the top is the per-frame entry point.
4. **`engine/combat.js`** — hitbox-vs-hurtbox overlap, resolving a hit into damage/launch/hitlag,
   shield block and perfect-block, counters and armor, projectiles, throws, item logic.
5. **`engine/stage.js`** — platform collision (including moving/sinking platforms), ledge
   detection, blast-zone (ring-out) checks, hazard state machines.
6. **`engine/match.js`** — the match loop: countdown → fight → KO/respawn → stocks/timer →
   sudden death → results. Shows how everything above is driven frame-by-frame.
7. **`engine/input.js`** — keyboard/gamepad polling into a per-frame input struct with
   press-edges vs held state. Roblox replaces this wholesale with `UserInputService` /
   `ContextActionService`, but keep the input *shape*
   (`{x, y, jump, light, heavy, dodge, guard, grab, ...}`) identical so the state machine in
   `fighter.js` ports over unchanged.

8. **`engine/ai.js`** — the bots. Not needed for the port itself, but it is the only consumer of the
   input struct other than a real player, so it doubles as a worked example of driving `fighter.js`
   from code. Port it last, or replace it outright.

`data/items.js` is here too because `combat.js` imports it directly. Everything in this folder now
resolves as a module graph on its own (`node -e "import('./engine/match.js')"` from this directory),
so the engine can be loaded and tested headlessly before a single line of Luau is written.

## Not included here (rendering/presentation, not simulation)

Everything under `render/`, `ui/`, `audio/` in the web build, and `data/characters` + `data/stages`
(those are passed into `new Match({...})` as config, not imported by the engine).

## One thing that will bite you if you skip it

This engine runs deterministically at a fixed 60 Hz tick (`FRAME = 1/60` in `config.js`) with no
interpolation inside the simulation. Roblox's `RunService.Heartbeat` gives a *variable* delta, not
a fixed one. Driving this logic straight off `Heartbeat` will make knockback and frame data drift
frame-to-frame. Use a fixed-timestep accumulator on the server instead — same pattern
`match.step()` uses here — so 1 call = 1/60 of a second, every time, regardless of actual frame
rate:

```lua
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
    accumulator += dt
    while accumulator >= FRAME do
        match:step()          -- your ported per-frame logic, always exactly 1/60s
        accumulator -= FRAME
    end
end)
```

Combat should be server-authoritative in Roblox regardless (per the original design doc) — the
client predicts animation, the server resolves every hit — so this accumulator belongs on the
server's match loop, not a client-side render loop.
