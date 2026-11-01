# Retention, round 4 review: Step 2 as built - 7.0 / 10 (almost there)

One independent Claude reviewer (brief: `retention-round4.md`). Correctness 7.5, exploit-resistance
7.0, test strength 5.5, player-facing 7.0. All five claims true in the code; the tests behind two
were weak.

## Found, and what was done
1. **"Keys rest past the cap" was effectively untested**: an operator-precedence slip in the test's
   key check, and after twelve losses no rested win could reach a key anyway. -> The test now starts
   one win short of the boost key with nothing else due, and asserts no Sparks, no key, no win counted.
2. **`humanFoe = false` constant would pass every suite.** -> multiplayer asserts both directions
   through the real server (and see 5).
3. **The first-drop test accepted any of three matches.** -> It checks the meter: one left after a
   new player's first match against people.
4. **No back-pay test from a pre-Step-2 record.** -> A record with level-30 XP and no watermark is
   paid levels 2-30 once (29 rewards, 3 keys, 6 crates, two titles), and not again after re-reading.
5. **An idle alt among bots made the main's match "against a person"**, opening the past-the-cap
   path to AFK farming. -> A person counts as an opponent only if they dealt damage. Tested: in a
   1v1 where one fought and one stood idle, only the one who was fought counts.
6. **The level-30 back-pay strip** would not fit (the test that was added measured 78 characters).
   -> Level rewards and new titles are lines of their own in the turning strip; every line of the
   biggest back-pay is at most 64 characters.
7. **Tier promotions pay past the cap.** By design (rank points move; each tier pays once) - now
   stated in the plan and tested.

Not done: the "What's new" card that would explain a back-pay windfall, and the lobby name tag.
Mastery titles get no locker headroom yet (note for Step 5).
