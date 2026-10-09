set -eu
rm -rf /s/repo && git init -q /s/repo && cd /s/repo
printf '#!/bin/sh\n# my own pre-commit checks, written by hand\nnpm run lint --silent || exit 1\n' > .git/hooks/pre-commit && chmod 755 .git/hooks/pre-commit
dotenvx precommit --install > /s/seed-dotenvx.log 2>&1
grep -q 'dotenvx precommit' .git/hooks/pre-commit
