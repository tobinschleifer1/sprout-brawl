#!/usr/bin/env bash
# Start (or resume) GPT-6-Astra on the task queue in docs/briefs/gpt-handoff.md.
#
#   roblox/tools/codex-handoff.sh            # run from anywhere inside the repo
#
# It works in its own worktree (.claude/worktrees/gpt-handoff, branch chore/gpt-handoff off
# feature/character-rig), so it never touches your checkout. If Codex stops at a usage limit,
# commit nothing yourself: run this script again after the limit resets (or after using a reset)
# and GPT picks up from its last WIP commit.
set -euo pipefail
CODEX=/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex
ROOT=$(git rev-parse --path-format=absolute --git-common-dir)/..
ROOT=$(cd "$ROOT" && pwd)
WT="$ROOT/.claude/worktrees/gpt-handoff"
if [ ! -d "$WT" ]; then
  git -C "$ROOT" fetch -q origin feature/character-rig || true
  git -C "$ROOT" worktree add -q "$WT" -b chore/gpt-handoff feature/character-rig
fi
LOG="$WT/../gpt-handoff.log"
{
  cat "$WT/docs/briefs/gpt-handoff.md"
  printf '\n\n## This run\n\nYou are in %s. Check `git log --oneline -15` across your branches and the\n"Questions for the owner" section to see what earlier runs finished, then continue with the first\nunfinished task in the queue. If the last commit on a task branch is "WIP: ...", continue it.\n' "$WT"
} | "$CODEX" exec -m gpt-6-astra -c model_reasoning_effort=xhigh -s workspace-write \
      --add-dir "$ROOT/.git" --add-dir /tmp --skip-git-repo-check -C "$WT" - 2>&1 | tee "$LOG"
if grep -q "You’ve hit your usage limit" "$LOG"; then
  echo
  echo "Stopped by the ChatGPT usage limit. Commit any work in $WT as WIP if GPT did not, then run"
  echo "this script again after the reset time shown above."
fi
