#!/bin/sh
# 2026-09-27's setup (cohort 2's P1 pre-state): one pinned commit, one modified working file, the reflog off.
set -eu
mkdir -p /s/jj-home /s/jj-in
R=/s/jj/repo
rm -rf /s/jj && mkdir -p "$R" && cd "$R"
jj git init > /dev/null
git config core.logAllRefUpdates false
rm -rf .git/logs
printf 'alpha, fixed bytes\n' > alpha
touch -t 202601010000 alpha
jj commit -m initial > /dev/null
printf 'alpha, modified fixed bytes\n' > alpha
touch -t 202601020000 alpha
