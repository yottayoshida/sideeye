set -eu
rm -rf /s/prek && mkdir -p /s/prek/repo && cd /s/prek/repo
git init -q . && rm -f .git/hooks/*.sample
printf 'repos: []\n' > .pre-commit-config.yaml
printf '#!/bin/sh\n# my own pre-commit hook, written by hand\nexec ./scripts/check-licenses.sh\n' > .git/hooks/pre-commit && chmod 755 .git/hooks/pre-commit
test -x .git/hooks/pre-commit
