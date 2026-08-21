#!/bin/sh
# Cohort-2 hg define (P1) setup: a repository with one pinned changeset of
# two files and one modified working file — the probe's pre-state shape
# (probes/hg.txt), rebuilt fresh for the engine.
set -eu
mkdir -p /tmp/cohort2/hg
# The pinned config is GENERATED here rather than committed as a loose
# file: the provenance verifier holds setup/check/toml/launcher to byte
# identity (D2) but knows nothing about extra files, so the config's bytes
# live inside a file the verifier does hold. revbranchcache.mmap=no is the
# measured off switch for the commit-path thread (probes/hg.txt).
cat > /tmp/cohort2/hg/hgrc <<'EOF'
[ui]
username = probe <probe@example.invalid>

[storage]
revbranchcache.mmap = no
EOF
export HGRCPATH=/tmp/cohort2/hg/hgrc
R=/tmp/cohort2/hg/repo
rm -rf "$R"
hg init "$R"
printf 'alpha, fixed bytes\n' > "$R/alpha"
printf 'beta, fixed bytes\n'  > "$R/beta"
touch -t 202601010000 "$R/alpha" "$R/beta"
hg -R "$R" add "$R/alpha" "$R/beta"
hg -R "$R" commit -m initial -d "2026-01-01 00:00:00 +0000"
printf 'alpha, modified fixed bytes\n' > "$R/alpha"
touch -t 202601020000 "$R/alpha"
