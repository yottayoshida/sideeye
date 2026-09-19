# Contract card — `lmdb-utils` (shape: journaled/transactional store whose contract includes recovery)

Sealed before the run for this target. Backings: `documented` / `measured` / `unspecified`;
`unspecified` is excluded from grading. Package version in the box: **0.9.24-1**.

## What the tool does

`mdb_load -f FILE ENVPATH` writes records into an LMDB environment directory; `mdb_dump` and
`mdb_stat` read one back.

## Claims

| # | claim | backing | evidence |
|---|---|---|---|
| 1 | The environment is a directory holding `data.mdb` and `lock.mdb` | `measured` | after `mdb_load -f /tmp/in.txt /tmp/lm` in the box, `ls -la /tmp/lm` shows exactly `data.mdb` (12288 bytes) and `lock.mdb` (8256 bytes) |
| 2 | `lock.mdb` is **not durable state**: the environment reads correctly without it, and it is recreated on the next open | `measured` | `rm -f /tmp/lm/lock.mdb` then `mdb_dump -p /tmp/lm` prints the record (` ka` / ` va`), and `ls /tmp/lm` afterwards shows `lock.mdb` back |
| 3 | `data.mdb` is the durable state, and commits reach it with `O_DSYNC` writes rather than by writing a second file and renaming | `measured` | `strace -f -e trace=openat,msync,fsync,rename mdb_load …`: `openat(AT_FDCWD, "/tmp/lm/data.mdb", O_WRONLY\|O_DSYNC\|O_CLOEXEC) = 5`, and no `rename` of anything in the environment appears |
| 4 | The contract after a crash is that the environment **still opens and reads back a committed transaction** — not that `data.mdb` holds the same bytes it held before | `documented` | `man mdb_stat` describes the tool as displaying "the status of an LMDB environment"; LMDB's own design — a copy-on-write B+tree with two meta pages — is why the file's bytes change on every commit while older committed data stays readable. A checker comparing `data.mdb` byte for byte would fail a correct run |
| 5 | Whether a crash mid-`mdb_load` must leave **all** of that load's records or none — the granularity of the transaction the tool uses per invocation | `unspecified` | the manual does not say whether `mdb_load` commits once per file or in batches, and the box's tooling cannot see inside a transaction that never completed |

## What a checker should assert

That the environment opens and the records that were committed before the crash read back — the
tool's own reader (`mdb_dump`, `mdb_stat`) is the right instrument, per claim 4. `lock.mdb`
belongs in `scratch` (claim 2).

A define that asserts byte equality of `data.mdb` contradicts claim 4 and is `wrong question`.
A define that requires every record of the interrupted load to be present turns on claim 5 and
is `unresolved by card`. A checker that only tests that `data.mdb` exists is vacuous: it exists
from the first page write onwards.
