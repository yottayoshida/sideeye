#!/bin/sh
# Novelty pre-scan through the search API, keyword AND. `gh search issues --repo R "a b"` was
# tried first and returned nothing for every query: one argument holding a space is sent as a
# quoted phrase (checked: the same words through `gh api search/issues` return 1,552 for Bun).
# The search API allows 30 requests a minute; the first pass hit that at the 16th, so every
# query waits 2.5 s.
q() { printf '## %s  [%s]\n' "$1" "$2"; gh api -X GET search/issues -f q="repo:$1 $2" -f per_page=8 \
  --jq '"  total \(.total_count)", (.items[] | "  #\(.number) [\(.state)] \(.created_at[:10]) \(.title)")'; sleep 2.5; }
for t in "package.json truncated" "package.json empty" "package.json atomic" "package.json ENOSPC" "write_file_atomically"; do q oven-sh/bun "$t"; done
for t in "fix empty" "fix truncated" "fix atomic" "fix EFBIG" "fix ENOSPC" "writeFileSync" "fix file lost"; do q igorshubovych/markdownlint-cli "$t"; done
for t in "fix empty" "fix atomic" "writeFileSync atomic" "fix ENOSPC"; do q DavidAnson/markdownlint-cli2 "$t"; done
for t in "replace empty" "replace atomic" "replace truncated" "replace disk full" "replace file lost" "replace zero"; do q google/google-java-format "$t"; done
