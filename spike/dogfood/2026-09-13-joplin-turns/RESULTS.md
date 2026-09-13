# joplin's writing threads: do they write one at a time? (#558) — 2026-09-13

joplin CLI 3.7.1 is refused `multiple_threads_detected` by the writer count: four threads of one `node` process write the profile (2026-09-11, `../2026-09-11-past-walls/RESULTS.md`). #539 would admit a second writing thread whose writes follow a `pthread_join` of the first, and #558 asked what any rule beyond that needs answered first: do joplin's writers overlap, or does each operation follow the last?

**Under strace, as joplin runs, they overlap**: the logger's opens and appends of `log.txt` fall inside the database's `fsync`s in every run. **With the logger held to errors (`--log-level error`), they do not**: `log.txt` is not touched, and the other 26 operations come one at a time, in the order they came in with the logger on, from four threads that never exit between one thread's operation and the next. The refusal stands either way — Sideeye refuses both on the writer count, one preflight each, and under strace four threads write in both. What the second measurement decided is the question the plan reserved for that outcome, whether a stage that could admit it is worth designing; the owner's answer was to file it, as #580.

"One at a time" in this record means two things together: no operation overlaps another thread's, and the same operations recur in the same order. It is not what "take turns" means in the README and ADR 0053, where two processes' writes must not interleave: joplin's threads hand the work between them five or six times in every run.

## Provenance

| | |
|---|---|
| target | joplin CLI 3.7.1 (`npm install -g joplin@3.7.1`), node v20.19.2, `apparatus/Dockerfile` (Debian trixie) |
| operation | `joplin [--log-level error] --profile /w/jp mknote SecondNote`, from a seed of `mkbook TestBook`, `use TestBook` and `mknote SeedNote`, restored with `cp -a` before every run |
| capture | `strace -f -y -ttt -T`, strace 6.13, glibc 2.41, aarch64, in Docker with its default seccomp profile |
| reader | `apparatus/turns.py`, sha256 `f27b94a1d30732f0eb9a1dd56cbb7b1ec60f2c9235d1d5e28b16889590e57c2a`, for every reading below. The logger-on captures were first read inside `run.sh` by `1f1095e271f250194c2aa89c5062a15a49902833468c2cc34aec29e6ee35270c` (`transcripts/run.txt`) and read again after review by the final reader (`transcripts/reread.txt`) |
| driver | `apparatus/run.sh`: `a6c4d3b5d02c614710841f8704c9c9dc3646bd159f39f5563552aff5d7c9eeb0` for the logger-on runs, `0cb08d671bf096ac218cf61687b15e38ada61960dc25054f44e7511ccb7b60a9` for the logger-off runs, which added `JOPLIN_FLAGS` and print it on their first line |
| engine, for the refusal | main `478c954` from `git archive`, built for aarch64-linux with zig 0.16.0; engine sha256 `7aae148a80db75a4a82473fdc59ca0260f3d0dfb1bd4055ed43eab6e5b399091`, shim `9804f98183894b02fcd1b6b80dbae9b55f5195609f10d094e19a640d6c911059`, both printed with the commit at the top of `transcripts/preflight-main.txt` and of the pair `apparatus/preflight-main.sh` (`cc06b70c2f112a15fc20483124f68da738c44afd25de167ab3c82e507212557e`, which added `JOPLIN_FLAGS` and prints it) wrote after review, `transcripts/preflight-main-flags-none.txt` and `transcripts/preflight-main-log-level-error.txt` |

To reproduce, build `apparatus/Dockerfile` as `sideeye-joplin:2026-09-13` and run the command in `apparatus/run.sh`'s header, adding `-e JOPLIN_FLAGS='--log-level error'` for the second set. The captures are about 6 MB each and are not committed; `run.sh` makes them again, `turns.py run` reads any one of them, and `turns.py pairs` lists their strong overlaps.

## What was read, fixed before the runs

The readings and the branches were written into the plan and reviewed twice before a capture was read, and `turns.py` carries them in its header:

- An **operation** is what the shim counts: the kill-point classes (`src/contract.zig`'s `OpClass`), an open counted when `openIsWriteCapable` would count it, `unlinkat` with `AT_REMOVEDIR` as an rmdir, and **failed attempts included** — the shim records before it calls, and the engine counts a writer whether its call succeeded or not.
- Three sets: **all** operations; **log**, those on `log.txt`; **rest**, everything else.
- **(m)** the multiset of operations (kind, path, ok or errno); **(o)** among runs with the same multiset, their order with thread names stripped — libuv hands a task to whichever pool thread is free, so a comparison by thread name counts the pool's choices as differences of order; **(g)** which operations shared a thread, names stripped, for reference; **(b)** strong overlaps — an operation wholly containing another thread's and lasting at least 0.5 ms, well above the tens of microseconds a short call takes under strace, and within log or rest only pairs whose two sides are both in the set; **(c)** in rest, each change of thread and whether the previous thread had exited before it.
- A run is valid when joplin exited 0 and the note was written (a write to the journal), and — added after review — when every kill-point call the reader met was read and placed: `unparsed` counts a line naming the state directory whose call could not be read, `unplaced` a kill-point call whose path could not be resolved. Every run below has both at 0. Two ways a call can go unread are counted by neither: a call left `<unfinished ...>` and never resumed, and a `<... resumed>` line with no unfinished half; nor does any selftest case reach the reader's branch for a call that returns `?` with no note. A count over the 40 kept captures, outside the committed apparatus, found none of the first naming the state directory and none of the second for a kill-point call.
- The branches: strong overlaps anywhere in all → **T1**, threads write at the same time; none → back to the plan. Rest with one multiset, one order and no strong overlap → **T2**; otherwise **T2'**. **T1 and T2 together make one more step required before any question about #539**: stop the logger if joplin can, and run again. If it can be stopped and the first run without it has no strong overlap, whether to design a stage beyond #539 goes to the owner; if it cannot, or an overlap remains, the answer is no and nothing is asked.

`turns.py --selftest` (31 checks: 15 cases, 12 mutations, 4 branch decisions; `transcripts/logger-error/selftest.txt`; `transcripts/runs/selftest.txt` is the first reader's 19, left beside the logger-on JSON the final reader rewrote, and `transcripts/logger-error/strong-pairs.txt` is `turns.py pairs` by the final reader over the logger-off captures, without the header `strong-pairs-20.txt` carries) holds each reading against synthetic captures copied in shape from a real one, and each mutation must break a case: no join of split lines, intersection for containment, no duration floor, orders compared with thread names, `AT_REMOVEDIR` not read, failed attempts dropped — and six that review found no case breaking: a split exit not read, an unsplit call's duration ignored, `log.txt` read from a two-path operation's first path only, a child process's calls kept, joplin's exit status ignored, unread calls ignored. `run.sh` runs it before it captures anything.

## The twenty runs, as joplin runs

Twenty tried, twenty valid, 79 seconds (`transcripts/run.txt`; one JSON reading per run in `transcripts/runs/`, from the final reader).

| set | operations per run | (m) multisets | (o) orders | (g) groupings | (b) strong overlaps |
|---|---|---|---|---|---|
| all | 80–87, from 4 threads | 8 | at most 5 within one multiset, 20 in all | 20 | **in 20 of 20 runs**: 48 pairs at 0.5 ms (50 at 0.25 ms, 20 at 1 ms) |
| log | 54–61, from 4 threads | 8 | 1 within each multiset | 20 | none |
| rest | **26 in every run**, from 4 threads | **1** | **1** | 8 | **none**, and no weak overlap either |

The logger's count is what moves the multiset of all operations: joplin writes a varying number of log lines, each an `open` and a `write` of `log.txt`, except that the seven runs whose count is odd have one `open` more than `write`s. `io_uring_setup` returned EPERM three times in every run, so libuv's thread pool did the file work; what refused it was not measured.

## The overlaps are database fsyncs containing the logger

All 48 strong pairs have the same shape (`transcripts/strong-pairs-20.txt`, printed by `turns.py pairs`): a database `fsync` on one thread — the journal's in 29, the database's in 19 — wholly contains a `log.txt` open (23) or write (25) on another. Checked by hand on a capture kept from before the runs (`transcripts/strong-pair-by-hand.txt`): tid 53's journal `fsync` entered at .348236 and returned 1.677 ms later, while tid 55 opened `log.txt` and tid 52 wrote to it, each also issuing futex and eventfd calls in between. That is two threads running while a third is inside `fsync`, not the order in which strace happened to reap three stopped threads.

## Everything but the logger: one at a time, in one order

The same 26 operations, in this order, in all twenty runs:

```
rmdir(tmp)=ok  mkdir(.)=EEXIST  mkdir(resources)=EEXIST  mkdir(tmp)=ok  mkdir(cache)=EEXIST
open(database.sqlite)=ok  open(database.sqlite-journal)=ok
write(database.sqlite-journal)=ok ×10  fsync(database.sqlite-journal)=ok  fsync(.)=ok
write(database.sqlite-journal)=ok  fsync(database.sqlite-journal)=ok
write(database.sqlite)=ok ×3  fsync(database.sqlite)=ok  unlink(database.sqlite-journal)=ok
```

Four threads carry them in every run, in eight different groupings — which thread takes which task is the pool's choice — with 114 changes of thread over the twenty runs and not one after the previous thread had exited; no thread that wrote exited before the last of these operations. Whatever orders them is not a join. The order has the shape of one asynchronous chain in JavaScript handing each file call to whichever pool thread is free; that is an inference from Node's design, not something this run measured.

## With the logger held to errors

joplin 3.7.1 takes its log level from a start-up flag, `--log-level <none|error|warn|info|debug>`, or from `flags.txt` in the profile, and its file logger compares that level before every append (`transcripts/logger-settings.txt`, the installed package's own code as `apparatus/logger-level.sh` prints it). `none` does not stop it, and `warn` does: one `mknote` per level, each over a fresh seed (`apparatus/logger-levels.sh`, `transcripts/logger-levels.txt`), grew `log.txt` with no flag and with `none`, `info` and `debug`, and left it the same size with `error` and `warn`. Why `none` logs is not in the transcripts — the flag parser's fallback to INFO is, what `none` parses to is not. Neither `help all` nor the keys of `config -v` mention the flag — which is where the first reading of this step looked, and why it reported that the logger could not be stopped.

Twenty runs with `--log-level error` (`transcripts/logger-error/`; twenty tried, twenty valid, 68 seconds):

| set | operations per run | (m) multisets | (o) orders | (g) groupings | (b) strong overlaps |
|---|---|---|---|---|---|
| all | **26 in every run**, from 4 threads | **1** | **1** | 4 | **none in any run**, and no weak overlap either |
| log | **0** | — | — | — | — |

The 26 are the rest of the logger-on runs, in the same order; ten threads were created in every run, as before, with 120 changes of thread over the twenty — six in each — and none after the previous thread had exited. The first valid run, the one the plan's rule reads, has no strong overlap, and neither has any of the other nineteen. The reader's summary for this set prints "T1' … back to the plan": that is the branch for the logger-on runs applied to a set it was not written for, and the rule for this step is the one above.

So the plan's question went to the owner: design a stage that admits threads writing one at a time with no join between them? The answer was to file it, as #580, which sets out what such a stage would have to decide — above all that the shim's only evidence would be the repetition of an order, not a mechanism it can observe.

## The refusal on main

`transcripts/preflight-main.txt`, main `478c954`, the same seed and operation with the logger on, the default mode (written by `apparatus/preflight-main.sh` before it took `JOPLIN_FLAGS`; the committed script's own logger-on run, `transcripts/preflight-main-flags-none.txt`, prints the same hashes and the same refusal): `UNKNOWN multiple_threads_detected`, tid 75 `rmdir(/w/jp/tmp)` and tid 76 `mkdir(/w/jp)`, ten threads created and four thread ids of the subject writing — the refusal of 2026-09-11, naming the same two operations. Both are the first two of the rest's 26, the second a failed attempt, which is why the reader counts failed attempts. That refusal is the writer count's own: the rest alone is written by four threads in every run, with the logger on and with it off. The logger decides only whether a stage beyond #539 could take joplin at all.

## What this does not say

- **Only what strace saw.** Every order and every overlap here was observed under strace, which stops each thread at each call. The order of an unobserved run is not claimed.
- **Only the thread pool.** `io_uring_setup` was refused. On a host where io_uring is available, libuv may issue file operations that way; that was not measured.
- One command (`mknote`), one pre-state, aarch64, a container filesystem.
- "One at a time" does not mean one thread. Under strace four threads write in every run, with the logger on or off. Sideeye's count is not strace's, so the refusal was measured on its own: a preflight with the logger on and one with `--log-level error`, both on main `478c954` and both from `apparatus/preflight-main.sh` as committed (`transcripts/preflight-main-flags-none.txt`, `transcripts/preflight-main-log-level-error.txt`), are refused `multiple_threads_detected`, naming tid 75 `rmdir(/w/jp/tmp)` and tid 76 `mkdir(/w/jp)`; with the logger held to errors the atomicity line no longer names `log.txt`. That is one run of each, and the refusal names two writing threads, not four.

## Apparatus errors, and what caught them

- **The pilot lost a run to its own pipe**: output sent through `tee file | head -150` stopped `tee` when `head` closed, and the third pilot's reading never reached the file.
- **The pilot's comparison was not a comparison of order**: it compared thread names, so the pool handing the journal to t10 in one run and t8 in the other read as a different order. Plan review caught it, and a second review caught a sentence I then copied from the first reviewer without checking (the database operations on one thread per run — they are not).
- **The pilot dropped failed calls**, so the profile directory's own `mkdir`, which the refusal names, was not among its operations.
- **The first `turns.py` dropped every successful open** while its selftest passed: `strace -y` annotates a returned descriptor (`= 17</w/jp/log.txt>`), the pattern did not allow it, and the synthetic lines had been written without it. A sweep of one real capture found 35 of 89 kill-point calls unparsed before any of the twenty runs; after the fix it finds none, and restoring the old pattern fails three selftest cases.
- **The logger step looked where a start-up flag cannot appear.** It read `help all` and `config -v`, found nothing, and the first version of this record, the joplin row and the dogfood index said joplin CLI cannot stop its logger. Diff review read joplin's source and found `--log-level`; the twenty logger-off runs above are what the plan's branch then required.
- **Six of the reader's decisions had no case that broke without them**, found by diff review: a split exit, an unsplit call's duration, a two-path operation onto `log.txt`, the root-process filter, joplin's exit status — and the count of calls not read, which the plan asked for and the reader did not have, so `run` returned 0 over a misread capture, the shape of the 35-of-89 failure. Each has a case and a mutation now, and the twenty logger-on captures read again with the final reader gave the same readings in all twenty, with nothing unparsed or unplaced (`transcripts/reread.txt`).
- **Three sentences were wrong.** "Each an open and a write" is not true of the seven odd counts. The refusal "stands, and the logger is why" named the wrong cause: the operations it names are the rest's, and the rest alone has four writers. And "take turns" meant something other than what the README means by it.
- **The main build could not be told from the transcript**: `sideeye --version` prints a version every commit since v1.3.0 shares. The preflight was run again from `git archive 478c954` with the commit and both hashes printed; the first run had named tids 72 and 73, and the same two operations.
- **The strong-pair list and its totals came from a one-off script.** `turns.py pairs` prints them now, and they are the same pairs and totals.
