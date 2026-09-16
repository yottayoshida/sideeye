#!/bin/sh
# What RESULTS.md says about Bun's upstream state, captured: the pull requests' authors, states,
# the sentences quoted, which files #39689 changes, and Bun's latest release.
set -u
for n in 39689 39666 39701; do
  gh api repos/oven-sh/bun/pulls/$n --jq '"== #\(.number) \(.title)\n  state=\(.state) merged=\(.merged) author=\(.user.login) association=\(.author_association) created=\(.created_at[:10]) base=\(.base.ref)"'
  gh api repos/oven-sh/bun/pulls/$n --jq '.body' | grep -n -i -E 'package\.json|write_file_atomically|stacked|0-byte|interrupted' | head -12 | cut -c1-400 | sed 's/^/  body:/'
done
echo "== #39689 changed files naming package.json or the atomic helper"
gh api --paginate "repos/oven-sh/bun/pulls/39689/files?per_page=100" --jq '.[] | select((.patch // "") | test("write_file_atomically")) | "  \(.filename) (+\(.additions)/-\(.deletions))"'
echo "== latest release"
gh api repos/oven-sh/bun/releases/latest --jq '"  \(.tag_name) published \(.published_at[:10])"'
