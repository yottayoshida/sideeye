# 2026-09-08 — The thread wall's targets under contract v16 (item 4)

The last of the four reach items measured on 2026-09-07. That measurement, with strace
and a tid-aware analyser, found eight targets behind the thread wall and five of them —
sqlfluff, vips, zstd, bundler, beets — writing the judged directory from one thread. This
directory measures those, plus two controls, against the engine that judges one writing
thread per process (ADR 0055), in both observation modes, in the same image the 2026-09-07
measurement used (`Dockerfile`; `sideeye-reach:2026-09-07` locally). Sideeye is cross-built
on the host and mounted; state and work live on the container's own filesystem (#528).

`run.sh` is the whole apparatus. Every row below is the report's own headline; nothing is
re-counted (#528's rule).

## The table

| target | threads the shim saw | `--observe wrappers` | `--observe syscalls` | what it says |
|---|---|---|---|---|
| sqlfluff | 1 created, 1 wrote | **PASS** 5/5 (4 crash points + baseline), `oracle_verified` | **PASS** 5/5 | judged; the first target through the thread rule |
| vips | 6 created, 1 wrote | **FAIL** 1/3, crash point 2 of 2 | **FAIL** 1/3, crash point 2 of 2 | judged; `out.png` is 0 bytes between its `open` and its `write` |
| zstd | 2 created, 1 wrote | `oracle_missed_operation` — a 4096-byte `write` the shim did not see | **PASS** 9/9 (8 + baseline), `oracle_verified` | thread rule passed; the wrappers-mode refusal is ADR 0005's far side (the metaflac class) |
| bundler | 1 created, 1 wrote | **FAIL** 1/3, crash point 2 of 2 | **FAIL** 1/3, crash point 2 of 2 | judged; `Gemfile` is 0 bytes between its `open` and its `write` (third define — see below) |
| beets | 3 created, **2 wrote** | `multiple_threads_detected` | `multiple_threads_detected` | **refused by the thread rule, correctly**: two threads open `library.db` |
| git-annex (control) | 5 created (subject), 0 subject writers; a child's two threads wrote | `multiple_threads_detected` | `multiple_threads_detected` | refused: tid 413 `mkdir(fsckdb.tmp)`, tid 418 `open(fsckdb/db)` — a child process's threads |
| mlr (control) | 5 created, 0 wrote | `unsupported_syscall_observed` (`epoll_ctl`) | `recording_run_failed` | refused before the thread rule is reached, in both modes |

Four of the five reach a verdict. The fifth does not, and that is the measurement's most
useful line.

## What moved, and what the plan had wrong

**beets writes from two threads.** The 2026-09-07 count said one writer; the shim's record
says two — `tid 364 performed open(library.db)` and `tid 366 performed open(library.db)`,
in both modes, in all seven runs (two modes and five repetitions). The shim's record is the
one the rule reads, and it names two threads opening the same SQLite database with write
intent; whatever the earlier analyser counted as a writer, it was not this. The plan's
"five of eight" is four of eight, and the refusal beets gets now names what it does rather
than that it has threads. Python is not a safe class on its own (the row already said so),
and neither is "one writer" a property a language has.

**vips FAILs, and it is not a bug report.** `vips copy` opens `out.png` with truncation and
writes into it; the world killed between those two operations leaves a zero-byte file
beside an intact input, and the checker — which asks only that the output be a readable
image *if present* — refuses it. Five of five runs, both modes, byte-identical kill-point
sequences. The input survives and the output is regenerable, which is the shape the
upstream-report gate declines (2026-09-07). Recorded as what it is: an in-place output, the
same shape as black, rustfmt, exiv2 and bean-format in the verdict table.

**bundler took three defines, and the first two measured the apparatus.** An empty state
directory refuses `checker_not_falsified` — there is nothing to corrupt — and says nothing
about threads; a checker that asks whether `README.md` exists accepts a state where every
file has been overwritten with junk, and refuses the same way. The third checker reads the
file's content and is falsified, and the run is judged: `bundle init` writes `Gemfile` in
place, zero bytes between `open` and `write`. The three attempts are committed side by side
(`bundler-attempt1-empty-state.*`, `bundler-attempt2-presence-checker.*`, `bundler.*`).

**zstd crosses the thread rule and meets the stdio wall in one mode.** Under wrappers the
oracle sees a 4096-byte `write` to `a.bin.zst` the shim did not record — a full buffer
written from inside `fwrite`, ADR 0005's far side, the class metaflac and fontforge are in.
Under `--observe syscalls` the same define is PASS over eight crash points with the oracle
agreeing. The thread clause in both accounts reads `2 thread(s) created, and 1 thread id(s)
wrote`.

**mlr refuses before threads are the question.** Under wrappers, `epoll_ctl` — a call
neither observer models — and under syscalls the recording run does not exit normally.
The second is the Go runtime under a seccomp trap and is not investigated here; the
2026-09-07 note that mlr's writer count changes between runs could not be re-measured,
because the rule that would read it is never reached.

**git-annex is the control it was meant to be.** Two threads of one process write —
one makes `fsckdb.tmp`, another opens `fsckdb/db` — and the refusal names both. That
process is a child, not the subject: the same report's account reads `a process other
than the subject operated on the judged directory` and `0 thread id(s) wrote the judged
directory` — the count is of the subject's own threads, which the clause says in so many
words since the review of this sweep (the committed artifact carries the earlier
wording) — so the rule fired on a child's two threads, which is what "every process, not
only the subject" means. (The first draft of this note said "the subject
process itself"; review read the artifact and it does not say that.)

One more thing the artifacts carry from the implementation they were taken under: the
account's `N thread id(s) wrote` was computed by a version that stopped counting at 2, so
`2` in a committed report means "two or more" — for beets and git-annex it happens to be
exactly two, which the refusal text (capture-derived) shows, but the count itself was not
what the shipped engine computes. The engine counts distinct ids since the review round;
the sweep was not re-run for a number the refusal already carries.

## Determinism

The same define five times, `--observe wrappers` (`rep-sequences.txt`, decoded from each
run's `trace-record.bin`):

- **vips**: the kill-point sequence is byte-identical across the five — `open:out.png
  write:out.png`, one tid — and every run is FAIL 1/3 at crash point 2.
- **sqlfluff**: the class sequence is identical across the five — `open write fsync
  rename` — and every run is PASS over 4 crash points. The basename differs per run
  (`q.sqlxg8e5aph.sql`, `q.sqlpl757zfm.sql`, …): the temp name is random, the sequence is
  not. This is the shape the engine addresses by position and class.
- **mlr**: refuses all five, before the rule.

The plan's third falsifiable check named beets here. beets refuses, so the two judged
threaded targets carry the check instead; the control (mlr) does not reach the rule, so the
"a target that varies is caught" half of that check is not demonstrated by this sweep.

## What the sweep did not measure

- **A non-main writing thread on a real target.** All four judged runs write from the main
  thread (`tid == pid` in every kill-point record of `rep-sequences.txt`). The shape where
  the one writer is a worker is carried by `TOY_THREAD_ONLY_WORKER` in the acceptance suite,
  not by a real target — the 2026-09-07 measurement predicted this, and it held.
- **Bun, joplin, the Homebrew `gh`.** Not in this image (the first two) or not Linux (the
  third). Their `docs/target-classes.md` rows say the refusal they met was the rule of the
  time — any thread — and that what they would meet now is the writer count, unmeasured.
- **The busy-thread race on a real target.** vips' six threads are the closest (workers
  that open no state file while the main thread writes), and its oracle agreed in every
  run; the race itself is pinned on `TOY_THREAD_BUSY`.

## Cost

`cost.sh` / `bench.c`, acceptance image, medians of seven over 200,000 open+close pairs on
`/dev/null` (`artifacts/cost.txt`): 0.428 µs a pair with no shim, 0.676 under the v15 shim,
0.851 under v16. The slot costs 0.09 µs per interposed call.

## Files

- `run.sh` — the sweep and the five-run repetition; `Dockerfile` — the image; `mkwav.py`
  — beets' fixture; `bench.c` / `cost.sh` — the cost measurement.
- `artifacts/<target>.<mode>.{txt,json}` — every run's report; `bundler-attempt{1,2}-*` —
  the two defines that measured the apparatus; `<target>.rep{1..5}.txt` — the repetitions;
  `rep-sequences.txt` — their kill-point sequences with tids; `sweep-transcript.txt`,
  `rep-transcript.txt` — the driver's own output; `toys-vs-commit3-control.txt` — the four
  toy shapes against the engine before the slice, both modes.
