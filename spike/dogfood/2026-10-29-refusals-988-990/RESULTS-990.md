# #990 — a child's thread is that child: Prisma's `db pull` on main and on the change

One box (`apparatus/Dockerfile`, `sideeye-r1029`: Debian trixie, Node 24.22.1, Prisma 7.10.1, strace 6.13,
linux/arm64) and two builds, `zig build -Dtarget=aarch64-linux-gnu` of main at `3a27be61` and of this
change, each mounted at `/se`. The define is the 2026-10-25 run's `prisma`
(`spike/dogfood/2026-10-25-shipped-v1160/apparatus/defines/prisma/`, the database inside the state)
unchanged, mounted at `/ap` and run by `apparatus/run.sh` from its own `seed.sh`, `--network none`,
privileged with its own cgroup namespace.

| Build | Command | Answer | Transcript |
|---|---|---|---|
| main `3a27be61` | `preflight --twice --oracle` | UNKNOWN `child_touched_state_dir`: pid 31 performed `open(/s/shop/prisma/dev.db)` "and the oracle's account does not place it. That reader resolves a relative path …" | `transcripts/prisma.base.preflight.txt` |
| this change | `preflight --twice --oracle` | UNKNOWN `child_touched_state_dir`: pid 31 performed `open(/s/shop/prisma/dev.db)`, "and process 22 (its thread 30) wrote in the judged directory while it was still running" | `transcripts/prisma.990.preflight.txt` |

The first refusal is the one #990 reports: the schema engine (pid 31) opens `dev.db` from its thread 38,
which strace names and the shim records as pid 31, thread 38, and the two were compared as though both
named processes. On the change they are one writer, and the run meets the next condition instead: the
subject's own thread 30 — Node's libuv pool — truncates and rewrites `schema.prisma` before the engine
has exited and been reaped. The capture's lines for each step, by line number, are in
`transcripts/prisma.990.oracle-lines.txt`: 30 created by the subject (8098), 31's exec (15310), 38's
open of `dev.db` (15733), 30's `O_TRUNC` of `schema.prisma` and its write (15910, 15957), 31 exiting
(16029) and the subject reaping it (16046). That is ADR 0053's second condition, a writer that overlaps
an unreaped child, and the detail now says so of the writer that did it; the first capture was taken on
a build that still called thread 30 "process 30", and the sentence was corrected before this one.

The `next` line is unchanged — "Check whether the operation is a shell script wrapping another
command" — and is not this target's case; it is the step every `child_touched_state_dir` arm but the
shimmed writer's carries, and #990's done-when is the detail.
