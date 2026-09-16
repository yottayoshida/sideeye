# 2026-09-16 crossed-walls — predictions, committed before `apparatus/explore.sh` ran

Written after the three screens (`apparatus/screen.sh`, `screen2.sh`, `screen3.sh`) and
before any exploration. Each line names the verdict expected per build and mode, the
mechanism behind it, and a confidence. A run that reaches a verdict for a different reason
than the one named here counts as a miss on the mechanism even when the verdict matches.

| Target | Build, mode | Expected | Mechanism | Confidence |
|---|---|---|---|---|
| Bun 1.4.2 `bun add` | v1.4.0, syscalls, x3 | **PASS** 3/3 | `package.json` is rewritten in place (`openat O_RDWR`, then the write) but the new content is longer than the old, so no kill between two syscalls leaves old bytes past the new end; `bun.lock` goes temp-then-rename; the re-run repairs `node_modules` | 60% |
| ninja 1.12.1 | v1.4.0, syscalls, x3 | **PASS** 3/3 | `.ninja_log` is an append judged by the history form; `out.txt` is `cp`'s and the checker does not depend on it; `ninja -n` reads a log with a torn tail | 70% |
| markdownlint-cli 0.49.1 `--fix` | v1.4.0, wrappers x3 and syscalls x1 | **FAIL** 4/4 | `fs.writeFileSync` opens `README.md` with `O_TRUNC` and writes after: a kill between leaves 0 bytes, the original nowhere — the shape seven of the eight 2026-09-16 counterexamples had | 85% |
| google-java-format 1.36.1 `--replace` | v1.4.0, wrappers x3 and syscalls x1 | **FAIL** 4/4 | the same window: the file is opened for truncation before the formatted text is written (2 state-changing operations in the screen: the open and one write) | 80% |
| xz 5.8.1 `-T2` | v1.4.0, wrappers x3 and syscalls x1 | **PASS** 4/4 | `f.bin.xz` is created beside `f.bin`, written, `fsync`ed with its directory, and only then is `f.bin` unlinked; a partial `.xz` beside an intact original passes the checker | 85% |
| all five | main d5911cd, first mode above, x1 | **the same verdict as v1.4.0** | none of the five depends on #539: each has one writing thread per process in the screen, so contract v18 adds nothing to decide | 85% |

What would falsify the premise of the run rather than a single row: any of the five refused
at exploration on the wall its screen said it had crossed (`oracle_missed_operation` for Bun
or ninja under syscalls; `multiple_threads_detected` for markdownlint-cli, google-java-format
or xz).
