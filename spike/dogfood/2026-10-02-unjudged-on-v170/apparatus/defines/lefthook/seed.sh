set -eu
# The repository lives OUTSIDE the judged root: the judged root is `.git/hooks`, what
# `lefthook install` owes, and `cwd` cannot be the state directory (docs/cli.md). The hooks
# directory holds exactly what `git init` puts there — the samples — which is the pre-state the
# built-in rule judges against (2026-09-21 seed-state.sh).
rm -rf /s/lefthook && mkdir -p /s/lefthook/lh-repo && cd /s/lefthook/lh-repo
git init -q .
git config user.email t@example.com
git config user.name t
printf 'pre-commit:\n  commands:\n    noop:\n      run: "true"\n' > lefthook.yml
