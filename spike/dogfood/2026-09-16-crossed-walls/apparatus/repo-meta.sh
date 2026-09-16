#!/bin/sh
# Rules 1-3 for the candidates this run met for the first time: stars and language
# (`repos/<r>`), and commits on the default branch since 2026-03-16 with their authors
# (`repos/<r>/commits?since=`; 100 is the API's page limit, a floor). The run's first
# reading of these was taken by hand and one jq filter carried a flag gh does not have, so
# the record is this script's output, taken again.
set -u
since=2026-03-16T00:00:00Z
for r in prettier/prettier svg/svgo igorshubovych/markdownlint-cli npm/cli madler/pigz lz4/lz4 \
         yadm-dev/yadm microsoft/TypeScript google/google-java-format tukaani-project/xz; do
  meta=$(gh api "repos/$r" --jq '"\(.stargazers_count)★ \(.language) default=\(.default_branch) archived=\(.archived) pushed=\(.pushed_at[:10])"')
  commits=$(gh api "repos/$r/commits?since=$since&per_page=100" --jq '"\(length) commits; " + ([.[] | (.author.login // .commit.author.name)] | group_by(.) | map("\(.[0])=\(length)") | join(" "))')
  printf '%s | %s | %s\n' "$r" "$meta" "$commits"
done
