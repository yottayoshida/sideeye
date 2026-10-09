git init -q demo && cd demo
printf '#!/bin/sh\nnpm test\n' > .git/hooks/pre-commit
dotenvx precommit --install
strace -f -qq -o /dev/null -P "$PWD/.git/hooks/pre-commit" -e inject=write:error=ENOSPC dotenvx protect
wc -c .git/hooks/pre-commit
