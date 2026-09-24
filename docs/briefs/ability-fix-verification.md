# Shield / ultimate input fix — 2026-09-23

## What was found

Bindings were already present and synced to Studio: I / Left Ctrl (hold shield), O (ultimate).
A controlled live test proved these keys reached the server and rendered the abilities.
The original report's precise circumstances could not be reconstructed, but two real input-loss
defects were reproduced with failing regressions:

1. A full press/release between simulation samples disappeared in both web and Roblox polling.
2. The server queue's overflow cap discarded old press edges, including an ultimate press.

## Changes

- Capture bounded pending press edges while continuing to poll held keys. Consume each edge
  once; clear pending inputs on match/lobby reset and suppress text-entry presses. Both builds
  retain keyboard taps; Roblox also retains gamepad press events.
- Coalesce overflowing server input into the next frame instead of dropping the press. Keep
  the existing queue limit and consumed-frame acknowledgement accounting.
- Show the LOCAL player's weapon, shield status, ultimate charge and readiness in the combat
  HUD. Explain uncharged and grounded-only denials; never announce another fighter's readiness
  as the local player's. Denial reason data is emitted by both simulation builds.

## Authoritative evidence

Baseline `roblox/check.sh`: exit 0 before changes.

Headless `abilities.luau` exercises the real input sampler, codec, RemoteInput, Match, Snapshot,
Predictor and render channels for ALL 12 weapons. It asserts that holding I enters shield,
shield blocks a real combat hit without damage, release lowers shield, an uncharged O is denied,
and a between-frame full-meter O activates Ultimate and spends charge on server AND prediction.
It also checks chat/reset guards and readiness/denial messaging.

Fresh Studio Play tests used each weapon through the actual room flow and actual keyboard
inputs. A server-only, temporary BindableFunction supplied a full meter and a stationary
opponent; it did not activate either ability. Renderer observations recorded the real cyan
shield Frame and predicted Ultimate animation. Results:

| Weapon | Shield visibly drawn | Ultimate rendered frames |
| --- | --- | --- |
| Sword | yes | 24 |
| Scythe | yes | 28 |
| Blasters | yes | 41 |
| Grimoire | yes | 34 |
| Axe | yes | 36 |
| Pike | yes | 34 |
| Gauntlets | yes | 38 |
| Hammer | yes | 40 |
| Longbow | yes | 29 |
| Flail | yes | 37 |
| Shield | yes | 47 |
| Daggers | yes | 36 |

Charge was spent at activation. Gauntlets and Hammer then landed hits and recharged to 6 and 4;
checking only the meter after the move would incorrectly call those successful attacks failures.

Additional live check: Left Ctrl held Daggers' shield; a real combat hit reduced shield from
42.5 to 38.9 while percent stayed 0. Releasing Ctrl returned to idle. An uncharged O displayed
“Ultimate is not charged yet — land hits to fill YOUR meter.” in the actual HUD.

Studio returned to Edit mode and both temporary script suffixes were removed. No full-meter
command, diagnostic remote or temporary probe is shipped in repository source.

Final gates: `roblox/check.sh` exit 0, `(cd web && npm test)` exit 0, `git diff --check` clean.
Six deliberate mutations in a nonsynced copy failed as expected: removing Roblox tap retention,
discarding overflow edges, disabling shield entry, suppressing active-ultimate status, announcing
an opponent's readiness as local, and removing web tap retention. All mutation sources were
restored. Studio Edit source was independently checked for the synced fixes and absence of probes.
