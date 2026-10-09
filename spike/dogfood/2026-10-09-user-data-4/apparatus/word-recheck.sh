#!/bin/sh
# Every whole-word hit of each name in spike/ and docs/, outside this run's own directory — the check
# fresh.sh's first-hit, substring answer could not give (`uv` read fresh behind `libuv`, `tenv` behind
# `dotenvx`). Prints file:line and the line around the hit; reading them is the decision.
#   sh word-recheck.sh <name> [...]   (from the repository root)
for n in "$@"; do
  echo "== $n"
  grep -rn -w -i -F -- "$n" spike docs 2>/dev/null \
    | grep -v '^spike/dogfood/2026-10-09-user-data-4/' \
    | grep -v -E '^spike/[^:]*\.(json|log)|/apparatus/defines/|/transcripts/' \
    | cut -c1-230 | head -${MAXN:-8}
done
