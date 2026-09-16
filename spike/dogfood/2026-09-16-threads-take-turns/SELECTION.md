# Selection — threads that take turns (#539, contract v18)

Not a slate: a re-measurement of the two targets the thread wall's rows name as Python,
made twice — once before the design, under an `LD_PRELOAD` probe and no Sideeye, to learn
what a join rule could reach; once after, under the branch build of Sideeye, to see what it
did reach. The record is the pair.

## Considered

Every row of `docs/target-classes.md` refused `multiple_threads_detected` by the writer
count as of 2026-09-16, and what the probe would have to find for a rule built on the
shim's own records to admit it.

| target | row | taken? | why |
|---|---|---|---|
| beets 2.1.0 | "Python CLIs that start a thread at the entry point" — the issue's own target, `spike/followup-item4/` | **yes** | two thread ids open `library.db`; whether a join separates them was unmeasured, and the issue said so |
| virtualenv 20.31.2 | "Python tools that parallelise directory creation", `spike/dogfood/2026-09-16-userview-3/` | **yes** | two thread ids `mkdir` in the judged root; a `ThreadPoolExecutor` is joined at shutdown, so a join was plausible |
| joplin CLI 3.7.1 | "Node/libuv tools" | no | measured overlapping on 2026-09-13 (`2026-09-13-joplin-turns/`): the logger's appends fall inside the database's `fsync`s. No join orders two threads that overlap |
| Bun 1.4.2 | "Multi-threaded runtimes, and behind the thread wall, raw syscalls" | no | one writer under v16; the wall behind it is the raw `openat` the shim never sees (#217), not the thread rule |
| git-annex | control row, `spike/followup-item4/` | no | the two writers are a child process's threads (Haskell runtime), and git-annex's own writes go through seventeen `git` children — the process rule's territory |
| zstd 1.5.x | "Compressors with a worker pool" | no | one writer under v16; what refuses it is the stdio wall or a pool write the shim misses, not the count |
| mlr 6.13.0 | control row | no | zero writing threads through libc; the Go runtime's writes bypass it |

## What the probe measured, and what decided the design

`apparatus/joinlog.c`, three runs each (`transcripts/probe/`):

- **beets** (`import -q`): the main thread opens `library.db`, creates three workers, two of
  them write the database and its journal in turn, the main thread joins all three afterwards
  and writes nothing more. The two writers are siblings — created by the same thread, joined
  after both wrote — so **no rule reading creations and joins admits beets**. What orders them
  is the pipeline's queue, which the shim does not see (#580's territory, closed).
- **virtualenv**: the main thread writes 23 records, creates a thread and joins it at once (it
  writes nothing), creates a second that installs pip (499 records, the main thread silent
  throughout), joins it, writes the six activation files and `pyvenv.cfg` again. A creation and
  a join fix that order.
  **A rule reading joins alone does not admit it** — the worker's writes follow the main
  thread's first ones by the creation — and one reading both does. The owner chose both, over
  "joins only" and over closing the issue on beets alone (2026-09-16). glibc handed the pip
  thread the silent thread's `pthread_t`, which is the reuse ADR 0067 decision 2 is built
  around; and the order in which pip writes its four console scripts (`pip`, `pip3`, `pip3.13`,
  `pip-3.13`) differed between runs (two orders in three), which is the next wall the record
  watches for.
- **control**: plain Python 3.13.5's `Thread.join()` is a real `pthread_join` (3.12 detached
  every thread and waited on a lock), which is what puts Python targets in reach on trixie.

## Rejected without measuring

- A synthetic joining target (a C or Rust program built for this record). The toys in
  `spike/acceptance.sh` are that, and a record is for what users point Sideeye at.
- Re-measuring the whole thread wall. The rule changed for two writers ordered by a creation
  or a join; the rows above say which of the wall's targets could be that, and only two could.
