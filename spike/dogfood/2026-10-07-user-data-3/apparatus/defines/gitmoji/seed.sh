set -eu
rm -rf /s/gm && mkdir -p /s/gm && cd /s/gm && git init -q . && rm -f .git/hooks/*.sample
printf '#!/bin/sh\n# my own prepare-commit-msg hook, written by hand\nticket=$(git rev-parse --abbrev-ref HEAD | sed -n "s|.*/\\([A-Z]*-[0-9]*\\).*|\\1|p")\n[ -n "$ticket" ] && sed -i "1s|^|[$ticket] |" "$1"\n' > .git/hooks/prepare-commit-msg && chmod 755 .git/hooks/prepare-commit-msg
test -x .git/hooks/prepare-commit-msg
