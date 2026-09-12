# Design review briefs

Every scored design review in this project reads a brief from this folder instead of being handed
a wall of prose and told to go exploring.

## Why this exists

The first five reviews cost between 150,000 and 210,000 tokens each. Almost none of that was
judgement — it was rediscovery. Each agent started cold, grepped the repo to work out what had
changed, opened whole files to find the twenty lines that mattered, re-derived measurements that
had already been taken, and re-ran suites that had already been run.

A brief removes the rediscovery and leaves the judgement, which is the only part worth paying for.

## What a brief must contain

1. **What changed, specifically.** File and symbol names, not "the hazard system was improved".
2. **The exact files to read, and nothing else.** A short list. If a file is 500 lines and only one
   function matters, name the function.
3. **The commands to run**, with expected runtimes. Say which are cheap and which are expensive.
4. **Every measurement already taken**, labelled as a CLAIM TO VERIFY rather than as a fact.
5. **The scoring rubric and the bands.**
6. **The specific questions** the round is meant to answer.

## What a brief must NOT do

- **It must not tell the agent what to conclude.** Numbers in a brief are claims; the agent's job
  is to check the ones that matter and say so when one is wrong. Reviews on this project have
  found that my own measurements were wrong more than once, and that is the point of running them.
- **It must not hide the weak parts.** Naming the thing I am least sure about is what gets it
  looked at.

## The rule that produced the best review so far

> Measure everything. Do not grade effort.

An earlier review scored a subsystem 6.5/10 by grading the changes; a second measured the same work
and found a 4, including two engine bugs that made half the feature a no-op. Every brief should
carry that instruction, and a warning about sample size — bot-vs-bot outcomes in this game are so
noisy that the same 14-game duel returned 3/14 and then 7/14.

## Bands

| Band | Meaning |
|---|---|
| under 4.5 | bad design |
| 4.5 – 6.5 | getting better, not good enough |
| 6.5 – 8 | almost there, only a few iterations left |
| 8 – 10 | workable |

Three rounds per subject. Stop early if a round scores above 8; if 8 is not reached by round three,
carry on anyway.

## Briefs

- `weapons-axe-pike-round1.md` — the Battle Axe and the Warpike
- `../hazard-design-review.md` — stage hazards (rounds 1–2 done, round 3 outstanding)
- bot AI — round 1 was launched twice and lost both times to process restarts; no brief written yet
