set -eu
# Stack's root with its user config and the global project (lab 10: without the global project
# `config set` asks the network for snapshots.json; lab 11: with it, no network). The pantry and
# stack SQLite caches stack opens on every run are declared scratch in the toml.
rm -rf /s/aux/home/.stack /s/stk && mkdir -p /s/stk /s/aux/home/.stack/global-project
printf 'snapshot: lts-22.44\npackages: []\n' > /s/aux/home/.stack/global-project/stack.yaml
printf '# This file contains default non-project-specific settings for Stack.\n# See https://docs.haskellstack.org/en/stable/configure/yaml/\ntemplates:\n  params:\n    author-name: A. Person\n    author-email: a.person@example.org\ninstall-ghc: true\nsystem-ghc: false\n' > /s/aux/home/.stack/config.yaml
grep -q author-name /s/aux/home/.stack/config.yaml
