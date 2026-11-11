# Bots, round 1 review: 4.1 / 10 (bad design)

One independent Claude reviewer (brief: `bots-round1.md`), about 4,000 matches. Every fix it
proposes was tested as a wrapper around `Ai.computeBotInput`, behind one flag `Ai.ROBLOX_LAYERS`
that the replay turns off, and played against the shipping bot. The baseline side bias is 168 of
360 for side A.

| Area | Weight | Score |
|---|---|---|
| The ladder | 25% | 6.0 |
| Competence | 25% | 3.5 |
| Weapon knowledge | 20% | 3.0 |
| Feel and fairness | 15% | 4.0 |
| Robustness | 15% | 3.5 |

## Ranked fixes, measured

1. **A bot stops pressing anything once its opponent is dead.** `decide` returns before the
   recovery block. Fix: with no enemy alive and airborne, recover toward `main.cx`. Self-destructs
   fall from 303 to 226.
2. **Undertow drowns them.** Fix: in water, swim to the nearest ledge, jump within 4 studs and
   recover within 6. Undertow self-destructs fall from 141 to 74.
3. **The bot only knows `stage.main`.** On Smeltworks and Faultline it spends recoveries over
   solid ground. Fix: over a solid, steer toward the target and stay above it. False recoveries
   fall 62%. It needs a pit recovery to cut self-destructs, and none has been found.
4. **The kill press is always side+heavy.**
   - The Blasters' press is Full Auto, which cannot KO. Scattergun instead wins 22-2, and matches
     fall from 367 s to about 200 s.
   - Against a wall, SigNeutral at angle 70 or more takes a pinned 200% target: Gauntlets 0/6 to
     6/6.
5. **No tactic presses a neutral heavy.**
   - Anti-air SigNeutral (angle 70 or more, within 4 studs and 3-12 above).
   - Counterguard instead of shielding.
   - Measured: 189 wins against 168.
6. **Air finishers cannot be reached.** `frame.x = dir*0.6` overwrites a neutral combo press. Fix:
   x 0 on a neutral press. Air finishers go 0 → 512, and 187 wins against 168.
7. **Bots cannot reach anything above them.** A player standing on a top platform ended at 0% in
   17 of 28 runs. Fix: climb by `weaponAction`'s step route, and drop through soft platforms.
8. **Zoners spend their recovery as an attack.** Fix: an airborne heavy outside the recovery
   branch becomes a light.

All the layers together win 206 of 360 against 168, and the self-destruct share falls 18% → 12%.

## Claims

- The ladder is in order, but a cliff at the bottom (easy beats normal 6%) and nearly flat at the
  top (elite beats impossible 37%).
- The rise in self-destructs with difficulty comes from Undertow and Smeltworks, not from
  difficulty.
- "Difficulty is perception" is false: hard given easy's sight still wins 60-4.
