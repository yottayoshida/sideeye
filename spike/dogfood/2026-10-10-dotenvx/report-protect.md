Title: dotenvx protect empties a pre-commit hook or git attributes file if its write fails

`protect` rewrites these files with `fs.writeFileSync`, which empties a file before writing it, so a failed write (a full disk) or a kill in between leaves 0 bytes. #1014 made `fsx` atomic; these calls bypass it, and none of the files is under version control:

- `uninstallPrecommitHook.js:62`: `.git/hooks/pre-commit`, with the user's own hook above the block `precommit --install` appended (`precommit`'s deprecation notice sends them to `protect`)
- `installProtectFilter.js:46`: the global attributes file, holding older `filter=dotenvx` lines
- `removeLegacyProtectFilter.js:39`: `.git/info/attributes`
- `protectSettings.js:23`: the global ignore and attributes files, when a protection is unticked

`init.js:70` (`spec --overwrite`) writes `Envfile` the same way.

To reproduce (2.34.2, Debian 13 arm64), with no crash:

```
git init -q demo && cd demo
printf '#!/bin/sh\nnpm test\n' > .git/hooks/pre-commit
dotenvx precommit --install
strace -f -qq -o /dev/null -P "$PWD/.git/hooks/pre-commit" -e inject=write:error=ENOSPC dotenvx protect
wc -c .git/hooks/pre-commit
```

The hook goes from 438 bytes to 0, `npm test` with it.

**Expected:** each file holds its old content or its new content.

`encrypt`, `set`, `decrypt` and `del` hold on 2.34.2 at every kill point, across several files too.

Found with Sideeye, as #1012. Not measured: power loss.
