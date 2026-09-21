#!/bin/sh
# Produce the state `overcommit --install` runs against.
#
# The repository lives at /tmp/oc-repo, OUTSIDE the judged root, because the judged root is
# `/tmp/oc-repo/.git/hooks` — what the operation actually owes — and because `cwd` is
# resolved before the state directory is made, so `cwd` cannot be the state. That ordering
# is not on any page; it is #647.
#
# Setup runs once per world, after the engine has emptied the judged root. It rebuilds the
# repository from scratch so every world starts from the same place, and it leaves the
# hooks directory holding exactly what `git init` puts there — the samples — which is the
# pre-state the built-in rule judges against.
set -eu
repo=${OC_REPO:-/tmp/oc-repo}
rm -rf "$repo"
mkdir -p "$repo"
cd "$repo"
git init -q .
git config user.email t@example.com
git config user.name t
printf 'PreCommit:\n  TrailingWhitespace:\n    enabled: true\n' > .overcommit.yml
