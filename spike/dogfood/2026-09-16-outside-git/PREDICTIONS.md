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
