# Keeping players playing: the retention plan (v3)

Owner's ask (2026-10-30): "find ways to get players to keep playing and make them want to play the
game more ... create a plan, show it, start implementing using the reviewer agent".

Roblox only. Builds on what exists: levels, unlocks and Ranked (`Progression`), the drop meter,
crates, keys and Sparks (`Economy`), first-win-of-the-day, the featured shop's daily rotation,
cosmetics, emotes and the Skyline Climb. It is phase 6 of `crates-and-monetisation-plan.md`
("Coming back"), made concrete. v2 took up round 1 (5.9), v3 round 2 (6.7):
`docs/reviews/retention-round{1,2}-review.md`.

## What keeps a player in a game like this

| Loop | Length | Question it answers | What we have | What is missing |
|---|---|---|---|---|
| **The match** | 3 min | "One more?" | the room rematches; results podium | new opponents in one press; the next goal shown *now* |
| **The session** | 30-60 min | "What am I working towards tonight?" | drop meter, level bar | goals that finish inside a session - and progress that does not stop at the hourly cap |
| **The day** | 24 h | "Why open it today?" | first win bonus, featured shop | daily quests, a streak |
| **The week** | 7 days | "What is this week about?" | nothing | weekly challenges, a weekly event |
| **The season** | 6-8 weeks | "Where do I stand?" | Ranked tiers (never reset) | seasons and a board - once there are enough players |

Multipliers on all of them: **friends**, **mastery**, **collection**. And three players the first
plan forgot: the **new** player (first ten minutes), the **solo** player on a quiet server, and the
**lapsed** player coming back after a week.

## Facts this plan rests on (checked in round 1)
- A match counts (pays anything) after 45 s with a hit dealt or taken, outside Training; CPU
  matches count 0.75; at most 12 count in a rolling hour (`Economy.qualifies`, `HOURLY_CAP`).
- 12 matches is about 36 minutes: **today an engaged player's progress stops mid-session** - a
  capped match pays nothing at all, first win included.
- `results.cpu` is true when ANY fighter is a CPU; nothing yet says "every opponent was a CPU".
- There are no private rooms: every room comes from PLAY's queue (so no win-trading by arrangement
  today; if private rooms come, they are excluded from win and KO quests).
- Level N to N+1 needs 140 + 15(N-1) XP: level 20 about 3 matches, level 49 about 6; levels 16-50
  together about 160 matches. Today only levels 3, 5, 6, 8, 9, 11, 12, 14 and 15 pay (a weapon).
- Result rows carry kos, damage, taken, falls, team and first weapon, so quests can count them.
- An equipped-title slot exists in the saved inventory but nothing draws a title yet.
- Nobody has XP from before levels shipped (all records start at 0), so **there is no back-pay**.
- Craft costs run 30 (Common) to 8000 (Mythic); a Forge Key sells for 75 R$; first win 25 Sparks;
  a ranked win 15 Sparks.

## The plan, in build order

### Step 0 - Count before changing anything (half a day)
`AnalyticsService` custom events from the server: session start/end, match finished (format, cpu,
counted, capped, ranked), level up, queue / FILL WITH BOTS / NEW OPPONENTS presses (later: quest
completed, streak day). **Released on its own, a few days before Step 1's screens are switched on**,
so Step 1 has a baseline. (Built: `roblox/src/server/Analytics.luau`.)

### Step 1 - The match loop: next goal, new opponents, invite (no economy risk)
1. **The near-miss line** on the results podium: the single closest goal, by the fraction still to
   go, among: the next level ("85 XP to level 9 - the Shield"), the next tier ("40 RP to Gold - 2
   wins"), and (from Step 3) a quest ("1 more KO"). Ties go to the level. Never shown when the match
   did not count (it says why instead).
2. **NEW OPPONENTS** beside the room's rematch: leaves the room and re-queues the same format in one
   press. If that format is now closed to the player (it cannot be today: Ranked never re-locks) it
   opens PLAY instead. The room's rematch stays the default.
3. **A quiet queue nudges**: after 20 s with nobody joining, the queue card pulses FILL WITH BOTS and
   says "Quiet right now - bots are ready". Solo players are never stuck.
4. **INVITE** on the PLAY panel: `SocialService:PromptGameInvite`. (The friend bonus is Step 7.)
5. **The one left behind** when someone presses NEW OPPONENTS keeps the room; its open place goes to
   the queue as usual (never back to the leaver) and FILL WITH BOTS / ADD BOT still work.
6. The RP part of the near-miss line shows only after a Ranked match.
7. **First session** (was Step 4): the first time PLAY opens, 1v1 pulses with "Start here - bots fill
   in if it's quiet". (Bots stay hard: the owner's call. If Step 0 shows new players quitting after
   losing to bots, a gentler first opponent is the owner's decision to revisit.)

### Step 2 - Progress never stops mid-session, and every level pays
1. **The cap moves**, and a match now has three states (`Economy._matchFinished`):
   - *counted* (under the cap): everything, as today;
   - *progressing* (past the cap, **with at least one human opponent**): XP, rank points and quest
     progress, but no drops, first win or ranked Sparks/keys; "Drops rest until :MM - XP still counts";
   - *not counted* (too short, no hit, Training, or past the cap against CPU only): nothing, and why.
   Past the cap, CPU-only matches pay nothing: that closes scripting levels against bots for the
   Sparks, crates and keys Road to 50 pays. `MatchService.results` gains `humans` (per row: was any
   opponent a person) to tell them apart.
2. **Road to 50**: every level from 2 to 50 pays **20 + 2 x level Sparks** (24 at level 2, 120 at
   50; about 3,500 in all); every 5th level also a **Scrap Crate**; every 10th a **Forge Key** (5 in
   all); titles at **15 Veteran, 25 Elite, 50 Master** (new cosmetics, `source = "level"`: never
   sold, never in a crate; `Inventory.SOURCES` gains `level` and `mastery`). Several rewards landing
   at once read as one line: "LEVEL 10! +40 Sparks, Forge Key, Shield unlocked".
   - **Paid once, by watermark**: `progress.paid` = the highest level whose reward was paid. Each
     match pays every level from `paid + 1` to the level reached (a jump of several pays them all),
     then sets `paid`. Players who levelled before Step 2 ships are paid up to their level on their
     first match after it - once, because of the watermark.
   - **A title grant cannot fail**: titles skip the locker's capacity check (a title is one small
     instance; at most three exist), and are granted before anything else in the match's write.
   - **The first counted match** pays at least the XP for level 2, win or lose (was Step 4).
   - **A new record's drop meter** starts at 2, so the first drop comes within two matches (was Step 4).
3. **Welcome back** (was Step 5): `progress.seen` (UTC day of the last counted match). Away 7+
   days, the first counted match back pays a Scrap Crate (at most once per 30 days) and the lobby
   shows a one-time "What's new" card.
4. **Titles shown**: the equipped title under the name on the results podium and the lobby name tag.
   Equipped in the Locker like any slot (it exists).
5. PLAY's level line shows the next reward: "LEVEL 9 · 85 XP to 10: Forge Key + Shield".

### Step 3 - Daily quests and weekly challenges
- **Daily: three** a UTC day, **15 Sparks and 50 XP each**, one free reroll a day. Drawn per player
  by a seed of (UTC day, user id): personal, reproducible, the same on every server. No "not used
  lately" weighting (it would need saved history; not worth it yet).
  The pool (15): play 3 matches · win 1 match · win 2 matches · play a free-for-all · win a
  free-for-all · play a team match (2v2/3v3) · deal 400 damage · deal 800 damage · take 4 KOs ·
  take 8 KOs · play 2 matches with a weapon you have not picked today · play with a non-starter
  weapon (level 3+) · finish a match without falling off · play a Ranked match (only drawn at level
  10+, judged at draw time; a player who reaches 10 that day sees it from tomorrow) · win a Ranked
  match (10+). The first day's first quest is always "play 1 match" (was Step 4).
- **Weekly: three**, Monday 00:00 UTC, **60 Sparks each, and one Forge Key for finishing all
  three**. Same targets for everyone (no level scaling: it punished levelling). The pool (8): win 8
  matches · take 25 KOs · deal 4,000 damage · play 6 free-for-alls · play 6 team matches · play 5
  Ranked matches (10+) · play 4 different weapons · reach a new rank tier (only drawn below Champion).
- **Against bots**: only **win, KO and damage** quests count half, and only when **every opponent was
  a CPU** (`row.humans`). Playing, mode and weapon quests count in full - the solo player on a quiet
  server is not taxed for the bots the game itself offered them.
- **Rerolls**: one a day, of any daily not yet complete; its progress is lost. Weeklies never reroll.
- **Rules**: progress comes from counted and progressing matches (Step 2). A match counts toward the
  day it *finished* in. Record: `inv.quests = { day, list = {{ id, n, done }}, rerolled, week,
  weekly = {{ id, n, done }}, weeklyKey }`, sanitised like every balance.
- **The reset, shown**: the QUESTS panel counts down to 00:00 UTC in the player's own hours ("new
  quests in 3h 12m") - for US players it flips mid-evening.
- A QUESTS button beside PLAY; ticks on the results line; the near-miss line can name a quest.

### Step 4 - Streak
A day counts only if it includes a counted or progressing match (alts that only log in get
nothing). Days 1-6 pay **10/15/20/25/30/40 Sparks**, day 7 a **Scrap Crate**, then the week repeats.
**A missed day pauses the streak** (no loss, no step back): an every-other-day player still climbs
the week. **No keys on the streak** - a deliberate change from the monetisation plan's "7-day
calendar ending in a Forge Key", which with alts would mint keys from logins.

### Step 5 - Weapon mastery
Mastery XP per weapon from counted matches with it in either hand. Mastery 1-10 per weapon; a
title at 5 ("Axe Adept", `source = "mastery"`), a mastery-only tint at 10. Shown on the select
screen's card. It gives a level-15 player fifteen more tracks.

### Step 6 - Friends
- +10% XP per Roblox friend in your room, at most +30%, **XP only**, only when the friend's match
  also counted and the friend is level 5+ (alts made friends do not pay).
- A PARTY queue: a group queues together and lands on one team. **Not in Ranked.**

### Step 7 - Ranked seasons and a board (gated on population)
Six-week seasons, rank points soft-reset to the start of the tier below the one reached, a season
title by best tier. A top-100 board in the lobby (OrderedDataStore, like `ClimbBoards`). Switched on
only once Step 0 shows enough daily Ranked players that a board is not the same names forever.

### Step 8 - Weekly event and the collection book
A rotating weekend rule (Disaster Weekend, Double XP free-for-alls, Daggers Only) on the lobby
billboard; the collection book in the Locker, a finished set paying a title.

### Later - outside the game, and the season track
Roblox experience notifications (opt-in) to reach lapsed players who have not come back - the
"What's new" card only reaches those who did. Then the Season Pass from the monetisation plan.

## The weekly budget (what an active player earns)

| Source | Casual (daily, ~30 min) | Heavy (2 h a day, Ranked) |
|---|---|---|
| Daily quests (15 x 3 x 7) | 315 Sparks | 315 Sparks |
| First win (25 x 7) | 175 | 175 |
| Streak | 140 + a Scrap Crate | 140 + a Scrap Crate |
| Weeklies (60 x 3) | 180 + 1 Forge Key | 180 + 1 Forge Key |
| Ranked wins (15 each) | - | ~900 (60 wins) |
| Road to 50 (once, spread) | ~200 | ~400 |
| **Sparks a week** | **~1,000** | **~2,100** |
| **Earned Forge Keys a week** | **1** | **1 + ranked (capped at 3) = 4** |

- Today a casual player earns about 175 Sparks a week (first wins) plus drops; ~1,000 lets them
  craft an Epic (750) a week or a Legendary (2,500) in under three. That is the intent: the free
  path is real, and keys/featured items still save weeks.
- **Ranked keys get a weekly cap of 3** (today: 1 per 3 ranked wins, unlimited - about 20 a week for
  a two-hour-a-day player, ~1,500 R$ of value). Changed in Step 2 alongside the cap rework.
- **VIP** (+10% Sparks in code today, first win doubled) applies to every Sparks reward above.
  The monetisation plan said +20%; the code's 10% stands until the owner says otherwise.

## What is NOT in this plan, deliberately
- No energy, no timers to wait out, no losing progress for missing a day.
- No paid XP, no paid rank. Robux buys cosmetics and keys, as now.
- No fake scarcity: quests and rotations are the same for everyone and stated plainly.

## How each step is built and checked
Server-owned (`Economy` decides inside the record's transaction), pure rules in a shared module with
a Lune test, every test mutation-checked, `check.sh` green, screens rendered. **One independent
Claude reviewer per round** scores the plan and then each step: under 4.5 bad - 4.5-6.5 getting
better - 6.5-8 almost there - 8-10 workable. Reviews in `docs/reviews/retention-roundN*.md`.
