# devtodo — assisted run log (#118)

## Timeline (UTC, measured)

| T | Time | Δ from T0 | Event |
|---|------|-----------|-------|
| T0 | 14:14:53 | 0 | scout start |
| T2 | 14:16:32 | 1m39s | proposals + define done (remove measured deterministic; add/done measured per-second flaky — the worst refusal shape) |
| T3 | 14:16:53 | **2m00s** | exploration verdict: UNKNOWN (after one dodge attempt) |

## Result

**UNKNOWN `unsupported_syscall_observed: fchmodat`** — devtodo rewrites its
database by creating a fresh file and unconditionally fchmod-ing it (its
own "created database has group or world permissions" warning fires on
every rewrite); a setup-side chmod/umask does not dodge it. The third
engine coverage gap of this experiment, and with buku's fchown and stow's
symlinkat it forms a clean class: **the `*at` metadata family
(fchown/fchmodat/symlinkat) is missing from the trace contract**, and each
absence turns a whole target family into UNKNOWN.

The define itself is sound and waiting: `--remove` is byte-deterministic
(measured 2s apart) while `--add`/`--done` are per-second flaky
(epoch stamps — measured), which is exactly the kind of determinism
cartography the scout can hand the engine for free.

## Human judgement (yotta, post-run)

- P1 meaningful question? ☐
- `*at` family support worth one engine issue? ☐
