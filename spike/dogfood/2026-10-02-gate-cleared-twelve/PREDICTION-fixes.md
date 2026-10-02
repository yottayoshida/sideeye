# Prediction — two upstream fixes, committed before either is run (2026-10-02)

Two reports this project filed on 2026-09-16 were answered with a fix that nothing here has
measured: codespell-project/codespell#4028 (merged 2026-09-21 as `68804d2f`) and
rubocop/rubocop#15721 (merged 2026-09-16 as `b39e7f467`). Both replace a truncating write with a
temporary file beside the target and a rename. A fix of that shape was measured twice
before (ImageMagick 2026-09-06, terraform 2026-09-29) and both times it changed something the
old write did not — so each is run beside its parent commit, on the 2026-09-16 define, and then
asked the questions a rename raises.

Written from the two diffs only; nothing has been run.

| | codespell `68804d2f` | RuboCop `b39e7f467` |
|---|---|---|
| explore, the 2026-09-16 define | PASS | PASS |
| the parent commit, same define | FAIL (as 2026-09-16: 0 bytes) | FAIL (as 2026-09-16: 0 bytes) |
| modes `0600` / `0664` / `0755` | kept (`os.chmod` to the original's mode) | kept (`File.chmod` to the original's mode) |
| relative symlink, run from the parent | link kept, target fixed (`os.path.realpath`) | link kept, target fixed (`File.realpath`) |
| a second hard link | detached — the other name keeps the old bytes; the diff says nothing of it | detached — the commit message says so |
| `ulimit -f 0` | the original kept, no temporary left (`except Exception` removes it) | the original kept, no temporary left (`ensure` removes it; `EFBIG` is not one of the errors that fall back to a direct write) |
| SIGKILL on entry to the rename | the original kept, a `.codespell-*.tmp` left | the original kept, a `*.rubocop.tmp` left (the commit message says so) |

Least sure: that both run from source in the 2026-09-28 box at all (codespell needs a
`_version.py` the build generates; RuboCop's tree is run against gems installed for standard).
If either cannot be run that way, that is the result for it, and it is recorded as not measured.
