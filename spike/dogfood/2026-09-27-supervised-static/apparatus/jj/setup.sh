#!/bin/sh
# Cohort-2 jj define (P1) setup: the probe's pre-state shape — one pinned
# commit, one modified working file, reflog disabled (probes/jj-v2.txt
# measured the reflog's wall-clock line as the one nondeterministic byte
# run). Identity/clock pins arrive via the environment (launcher).
set -eu
mkdir -p /tmp/cohort2/jj
R=/tmp/cohort2/jj/repo
rm -rf "$R"
mkdir -p "$R"
cd "$R"
jj git init > /dev/null
git config core.logAllRefUpdates false
rm -rf .git/logs
printf 'alpha, fixed bytes\n' > alpha
touch -t 202601010000 alpha
jj commit -m initial > /dev/null
printf 'alpha, modified fixed bytes\n' > alpha
touch -t 202601020000 alpha
