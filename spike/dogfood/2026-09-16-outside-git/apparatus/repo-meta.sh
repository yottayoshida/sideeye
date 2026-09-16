#!/bin/sh
# Rules 1-3 for this run's candidates: stars, language and default branch (`repos/<r>`), and
# commits on the default branch since 2026-03-16 with their authors (`repos/<r>/commits?since=`;
# 100 is the API's page limit, a floor). Copied from the 2026-09-16 crossed-walls run with the
# repositories taken from argv.
#   repo-meta.sh <owner/repo>...
set -u
since=2026-03-16T00:00:00Z
for r in "$@"; do
  meta=$(gh api "repos/$r" --jq '"\(.stargazers_count)★ \(.language) default=\(.default_branch) archived=\(.archived) issues=\(.has_issues) pushed=\(.pushed_at[:10])"')
  commits=$(gh api "repos/$r/commits?since=$since&per_page=100" --jq '"\(length) commits; " + ([.[] | (.author.login // .commit.author.name)] | group_by(.) | map("\(.[0])=\(length)") | join(" "))')
  printf '%s | %s | %s\n' "$r" "$meta" "$commits"
done
