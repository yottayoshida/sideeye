# 2026-09-16 outside-git — predictions, committed before `apparatus/explore.sh` ran

Written after the two screens (`apparatus/screen.sh`, `screen2.sh`) and before any exploration.
The mechanism column is read from the screens' strace captures, operation by operation, in order
(the crossed-walls run missed Bun by reading a probe `open` as the rewrite).

| Target | Build, mode | Expected | Mechanism | Confidence |
|---|---|---|---|---|
| aws-cli 2.23.6 `aws configure set … --profile work` | v1.4.0, wrappers x3, syscalls x1 | **FAIL** | `openat(credentials, O_WRONLY\|O_CREAT\|O_TRUNC)`, then one 230-byte `write` of the whole file: a kill between leaves it empty, and the `default` profile's keys go with the profile being edited | 85% |
| hatch 1.18.0 `hatch config set terminal.styles.info italic` (the default is `bold`) | v1.4.0, wrappers x3, syscalls x1 | **PASS** | a temporary file created `O_EXCL`, written, `fsync`ed, and renamed over `config.toml` | 80% |
| neovim 0.10.4, `:wshada` | v1.4.0, wrappers x3, syscalls x1 | **FAIL** | `main.shada.tmp.a` created, **`main.shada` unlinked**, the temporary renamed over it, and only **then** the 160-byte `write` and the `fsync` on the same descriptor: a kill after the rename leaves an empty `main.shada`, and one after the unlink leaves no `main.shada` at all | 70% |
| jbang 0.141.0 `config set`, the JVM named directly | v1.4.0, wrappers x3, syscalls x1 | **FAIL** | `openat(jbang.properties, O_WRONLY\|O_CREAT\|O_TRUNC)`, then one 45-byte `write` | 85% |
| pyenv 2.8.5 `pyenv global` | v1.4.0, syscalls x3 (wrappers refuses `state_changed_without_ops`) | **FAIL** | a bash child opens `version` `O_TRUNC`, closes it, reopens it `O_APPEND` and writes: a kill between leaves an empty `version`, which pyenv reads as the `system` Python | 75% |
| all five | main `047592d`, first mode above, x1 | **the same verdict as v1.4.0** | each has one writing thread per process in the screen | 85% |

What would falsify the run's premise rather than one row: any of the five refused at exploration
on a wall its screen did not show.

## Added after the first exploration: neovim's second define

Written after neovim's three `wrappers` explorations and one `syscalls` exploration returned
`UNKNOWN baseline_violates_invariant`, and before the second define ran. `apparatus/probe-shada.sh`
measured why the uncrashed re-run differs: every differing byte between two runs of the same
operation from the same state lies inside a msgpack timestamp or the header's `pid`
(`transcripts/probes/shada.txt`). The second define declares `main.shada` scratch (ADR 0043) and
leaves the claim to the checker, which reads the history entry and register the setup stored.

| Target | Build, mode | Expected | Mechanism | Confidence |
|---|---|---|---|---|
| neovim 0.10.4, `:wshada`, `--scratch main.shada` | v1.4.0, wrappers x3, syscalls x1; main wrappers x1 | **FAIL**, on the checker | the worlds the first define explored already printed the checker's failures before the baseline refused the run: *"main.shada is gone (main.shada.tmp.a )"* and *"register a is lost (0 bytes in main.shada)"* — the kills after the unlink and after the rename | 85% |

## Added after the first review: neovim 0.12.5, and a second neovim checker

Written after the first review of this record read `packer.packer_flush(&packer)` at
`shada_write_exit:` in src/nvim/shada.c from v0.11.0 on (absent at v0.10.4) — the whole file flushed
into the temporary before the rename — and before `apparatus/nvim-v2.sh` ran. The review also found
the first checker falsified on one of its predicates only; checker v2 asks nvim in every branch and
fails on an E57x message, a missing register or a missing history entry.

| Target | Build, mode | Expected | Mechanism | Confidence |
|---|---|---|---|---|
| checker v2, both binaries | — | passes the setup's and the operation's states, leaves the file unchanged, and fails on each of: emptied, absent with a complete `main.shada.tmp.a`, cut by 20 bytes, no register, no history | — | 75% |
| neovim 0.12.5, strace | — | every byte written to `main.shada.tmp.a` before `unlink(main.shada)` and the rename | the flush at `shada_write_exit:` | 85% |
| neovim 0.12.5, no scratch | v1.4.0 wrappers x3 | **UNKNOWN** `baseline_violates_invariant` | timestamps and pid in the format, as at 0.10.4 | 80% |
| neovim 0.12.5, `--scratch main.shada`, checker v2 | v1.4.0 wrappers x3, syscalls x1; main wrappers x1 | **FAIL**, only in the worlds between `unlink(main.shada)` and the rename: `main.shada` absent, the complete temporary beside it, register and history lost to nvim | `vim_rename` still calls `os_remove(to)` before `os_rename` | 70% |
| neovim 0.10.4, `--scratch main.shada`, checker v2 | same | **FAIL**, the same 6 of 13 worlds as checker v1 | nothing about 0.10.4 changed | 80% |
| neovim 0.12.5, `ulimit -f 0` on the small file | — | **no loss**: the write to the temporary fails before the rename, `main.shada` intact and `main.shada.tmp.a` left beside it | the same flush | 80% |
| neovim 0.12.5, limits near the size of a 400-entry file | — | never a cut `main.shada`: either the original intact (limit below the file) or the new file whole | the same flush | 80% |
