#!/bin/sh
# Rules 1 and 2 (spike/cohort4/SCOUT-BRIEF.md) for each repository named: stars, the last push,
# archived or not, and whether issues are enabled. One `gh api repos/<r>` per name.
#   sh stars.sh <owner/repo> [...]
# Prints: <owner/repo> stars=<n> pushed=<date> archived=<bool> issues=<bool> (or ERROR <message>).
for r in "$@"; do
  out=$(gh api "repos/$r" --jq '"stars=\(.stargazers_count) pushed=\(.pushed_at[0:10]) archived=\(.archived) issues=\(.has_issues) full=\(.full_name)"' 2>&1) || out="ERROR $(echo "$out" | head -1)"
  echo "$r $out"
done
