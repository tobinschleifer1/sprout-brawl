# Brief: port the ultimate VFX to the Roblox client

Repository: https://github.com/tobinschleifer1/sprout-brawl
Branch: `main` (everything you need is there; do not use any other branch)

## Read first

`AGENTS.md` at the repo root. It is short and it is not optional — it states the one rule this
repository is built on and the three consequences that follow from it. `roblox/README.md` has the
detail on the port's traps.

## Set up and prove the baseline BEFORE you change anything

```bash
git clone https://github.com/tobinschleifer1/sprout-brawl.git && cd sprout-brawl
curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
rokit add --global rojo-rbx/rojo JohnnyMorganz/luau-lsp lune-org/lune
export PATH="$HOME/.rokit/bin:$PATH"
cd roblox && ./check.sh          # must exit 0, fourteen suites. If it does not, stop and report.
cd ../web && npm install && npm test
```

`check.sh` fetches what it needs and names the install commands for anything missing. It takes
under a minute. **Run it before you start and before you finish.**

## The task

Port `drawUltimate` and `drawMuzzle` from `web/src/render2d/weapons2d.js` (lines ~887 to the end of
the file, about 255 lines) into a new `roblox/src/client/UltimateVfx.luau`, and call it from
`roblox/src/client/Fighter2D.luau`.

These draw the parts of an ultimate that are not the weapon itself: afterimage blades, the reaper's
moon, the second pistol, the rune stack, the muzzle flash.

**Everything it needs already exists.** The pose half of `weapons2d.js` is already ported as
`roblox/src/client/WeaponPose.luau` and is parity-tested against the JavaScript across 384,808
values. Every `U.*` field `drawUltimate` reads — `aiming, blur, chop, crush, extend, glow, haul,
lance, pull, reave, rifle, rise, rounds, runes` — is already produced by `WeaponPose.For(...).ult`
and already covered by that test. **You need no new snapshot fields, no server changes and no
netcode changes.** If you think you do, you have misread something; stop and say so.

### Follow the established pattern

`roblox/src/client/Weapons2D.luau` and `Avatar2D.luau` are the precedent, and the reasoning in
their header comments applies here unchanged:

- Roblox UI **cannot fill a polygon**. `Canvas2D` gives you `rect`, `circle`, `ellipse` and `tri`
  (a staircased triangle, six Frames). A `Frame` **is** a rotated rectangle exactly, so draw mass
  as rectangles and spend a `tri` only where a silhouette genuinely needs a point.
- Keep the Frame count honest. Four fighters with weapons and full avatars currently cost 0.676ms
  a frame against 216 pooled Frames. An ultimate is one fighter at a time, but a per-frame cost
  that doubles the budget is not acceptable — say what it costs in your summary.
- Where the JavaScript draws a curve you cannot reproduce, **say so in a comment and say what you
  did instead**, as those two files do. Do not silently approximate.

### Scope — do not touch these

Another agent is working on character/stage select in parallel. To avoid collisions:

- **Do not modify** `init.client.luau`, `Hud.luau`, `MatchService.luau`, `RemoteInput.luau`,
  `Snapshot.luau`, `Net.luau`, or anything under `roblox/src/shared/`.
- `Fighter2D.luau` is the **only** existing file you should need to change, and only to call your
  new module. Keep that edit to a few lines.
- If the task seems to require touching anything on that list, stop and report rather than
  widening the change.

## Verifying it

`check.sh` cannot tell you whether an ultimate looks right. See the verification section of
`AGENTS.md`: check whether you have Roblox Studio tools, and if you do, use them — sync with
`rojo serve`, start play, and read the drawn Frames out of the `ScreenGui` rather than taking a
screenshot, because the game draws no 3D at all.

Twelve ultimates is more than you will want to trigger by playing. The practical approach is to
call your draw directly against a `Canvas2D` for each weapon and phase and inspect what it
produced — that is how `Weapons2D` and `Avatar2D` were checked.

State plainly in your summary which parts you verified and how. **Never describe unverified
rendering as working.**

## Definition of done

1. `roblox/check.sh` exits 0 — fourteen suites, unchanged.
2. `luau-lsp analyze` is clean (`check.sh` runs it).
3. `cd web && npm test` — 13 suites, 0 failed. You should not be changing `web/` at all here; if
   you did, say why.
4. Every one of the twelve ultimates draws without erroring. Prove it with a Lune test that calls
   your draw for each weapon across the windup/active/end phases and asserts no error and a
   non-zero Frame count — `roblox/tests/` has the loader shims you need (`Loader.loadFrom`, plus
   `game`, `Color3` and `Vector2` stubs).
5. **Mutate your own test and confirm it fails.** A test that has never failed has proven nothing.
   Say in your summary which mutations you tried and which were caught.
6. One commit, with a message that explains *why* — what the JavaScript does, what you could not
   reproduce and what you did instead. Match the existing commit style; read a few first.

## If you get stuck

Report what you found rather than guessing. Two specific things worth flagging rather than
working around: a `U.*` field that `WeaponPose` does not actually produce, or a shape that cannot
be drawn within the Frame budget.
