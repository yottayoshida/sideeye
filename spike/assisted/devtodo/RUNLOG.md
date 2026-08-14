# devtodo — assisted run log (#118)

## Timeline (UTC, measured)

| T | Time | Δ from T0 | Event |
|---|------|-----------|-------|
| T0 | 14:14:53 | 0 | scout start |
| T2 | 14:16:32 | 1m39s | define done (remove measured deterministic; add/done measured per-second flaky). **The proposal ARTIFACT was formalized after the verdict — R1 finding 2; metadata lived in toml/checker comments at define time** |
| T3 | 14:16:53 | **2m00s** | exploration verdict: UNKNOWN (after one dodge attempt) |

## Result

**UNKNOWN `unsupported_syscall_observed: fchmodat`** — devtodo rewrites its
database by creating a fresh file and unconditionally fchmod-ing it (its
own "created database has group or world permissions" warning fires on
every rewrite); a setup-side chmod/umask does not dodge it. The third
unsupported syscall of this experiment (with buku's fchown and stow's
symlinkat): three measured absences from the trace contract — no common
family is claimed (R1: fchown is not an *at name, symlinkat creates
entries rather than changing metadata) — each of which blocked one target
here.

The define is written but its checker was never exercised by an
exploration (UNKNOWN before the falsification gate — R1). Its determinism
map: `--remove` is byte-deterministic
(measured 2s apart) while `--add`/`--done` are per-second flaky
(epoch stamps — measured), which is exactly the kind of determinism
cartography the scout can hand the engine for free.

## Human judgement (yotta, post-run)

- P1 meaningful question? ☐
- `*at` family support worth one engine issue? ☐
