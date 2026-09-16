#!/bin/sh
# Novelty pre-scan through the search API (keyword AND), for the four FAILs. `gh search issues
# --repo R "a b"` sends a spaced argument as a quoted phrase and returns nothing (the 2026-09-16
# crossed-walls run), so the API is called directly. 30 requests a minute: every query waits 2.5 s.
# Each query prints up to 100 results.
q() { printf '## %s  [%s]\n' "$1" "$2"; gh api -X GET search/issues -f q="repo:$1 $2" -f per_page=100 \
  --jq '"  total \(.total_count)", (.items[] | "  #\(.number) [\(.state)] \(.created_at[:10]) \(.title)")'; sleep 2.5; }
for t in "credentials file empty" "credentials file truncated" "credentials file wiped" "credentials file deleted" "configure set credentials lost" "credentials file corrupted" "configure set disk full" "credentials atomic"; do q aws/aws-cli "$t"; done
for t in "shada empty" "shada truncated" "shada lost" "shada corrupted" "shada tmp" "E138" "shada rename" "shada crash" "shada disk full"; do q neovim/neovim "$t"; done
for t in "jbang.properties empty" "config set empty" "properties truncated"; do q jbangdev/jbang "$t"; done
for t in "version file empty" "global empty" "version file truncated"; do q pyenv/pyenv "$t"; done
