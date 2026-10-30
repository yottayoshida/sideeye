# #987: two thread ids writing in turn — what strace sees of the eight static Go walls

**Under the rules registered for it (`PREDICTIONS-v2.md`), six of the seven targets measured pass and
the two controls read as stated: the criteria say *build*.** What passes is the evidence a rule would
need as strace sees it — no hand-over overlapping in any run, and the same sequence of writes in ten of
ten — not a rule: building one is a separate plan, and three things it has to answer first are below.

## How

`sideeye-gh1029` (`apparatus/Dockerfile`: 2026-10-25's assets, layer for layer, and strace 6.13), each
target seeded by 2026-10-25's own `seed.sh` before every run and run with its `env.sh` (`GOMAXPROCS=1`),
without Sideeye, ten times in each of two arms of `strace -f -ttt -T -y` (`apparatus/measure.sh`): arm 1
with strings cut at 64 bytes, for the hand-overs and Q1; arm 2 with the bytes (`-s 1048576 -x`), for Q2.
Read by `apparatus/handoff.py` (`--selftest`: 24 checks, the three fixed readers each caught). Every run
of every target and control exited 0. The captures (1.8 GB a measurement) are not committed; each
target's judgement, `define.txt` and `exits.txt` are, under `transcripts/v1/` and `transcripts/v2/`.

## Two measurements

**The first** (21:35–21:42, rules `PREDICTIONS.md`, sha256 `8faab9bd…7bef0fe` printed at 21:31,
reader `apparatus/handoff.py` as it then stood, kept as `apparatus/handoff_v1.py`, sha256 `cd00f00d…`, copied
before v2's edits — its hash was not printed before the run, as v2's was) gave four of seven: *do not build*. Reading the three failures:

- vmrestore's runs removed files in a different order from each other — a real difference.
- JuiceFS differed only in the descriptor number an `openat` returned (8 or 9): v1 compared each call's
  return, which for an open is not what was written or where. **A defect of the reader.**
- Dolt differed in the name of each archive `gc` makes (a hash, new each run) and in how many bytes one
  write of `journal.idx` carried in two runs of nine.

Corrected for the descriptor alone, the same captures gave five of seven: *build*. A conclusion that
turns on a reader fixed after its data was read is not one to record, so the owner chose to fix the
reader, register the rules again (`PREDICTIONS-v2.md`, sha256 `31f7ee9e…f026531`, reader `e1f7c475…ffc7e`,
printed at 21:58), and measure again. v2 compares what `src/prefix.zig` compares: whether a call failed,
not what it returned; a count goes with the bytes; two paths the state did not start with, each unwritten
by the other run, count as the same, as `sameWhereRecorded` lets them.

During part of the first measurement a unit-test build ran on the same machine. Nothing else ran during
the second.

## The second measurement (21:58:29–22:05:25)

| target | arm-1 runs with a hand-over | hand-overs (arm 1 / arm 2) | overlapping | Q2 | result |
|---|---|---|---|---|---|
| `ctl-race` | 10 | 1000 / 999 | 353 | order | **fail**, as predicted |
| `ctl-condvar` | 10 | 20 / 20 | 0 | same | **pass**, as predicted |
| etcd `etcdutl defrag` | 0 | 0 / 1 | — | same | **unmeasured** |
| Dolt `dolt gc` | 10 | 39 / 24 | 0 | content | pass |
| Grafana `cli admin reset-admin-password` | 5 | 7 / 13 | 0 | content | pass |
| vmrestore | 10 | 78 / 70 | 0 | sequence | **fail** |
| Gogs `restore` | 10 | 1034 / 1028 | 0 | content | pass |
| gqlgen `generate` | 8 | 20 / 21 | 0 | same | pass |
| JuiceFS `config` | 8 | 8 / 8 | 0 | content | pass |
| Navidrome `backup restore` | 3 | 3 / 0 | 0 | content | pass |

Seven measured, six pass: two-thirds and more. Every prediction in `PREDICTIONS-v2.md` held.

- **No target's hand-over overlapped**, in 1,189 arm-1 hand-overs. The race control's did, in every run
  (10 to 48 of each run's 100, `transcripts/steps/ctl-race.txt`).
- *content* is bytes no other run wrote at that write: Grafana's journal, Gogs's database (a restore
  stamps rows), JuiceFS's journal, Dolt's `journal.idx` and archive bytes, Navidrome's database.
- vmrestore fails by its own order, not its threads': the files a restore removes come in a different
  order from run to run (Go's map iteration is the likely source; not read from its source).
- etcd handed over in no arm-1 run of either measurement; in arm 2 it handed over once in the second
  and never in the first — one hand-over in forty runs. 2026-10-25's single `strace -f -y` of it saw one
  run of `pwrite64` move between threads. Under the engine itself (`--observe supervised`, the 2026-10-25
  define, `GOMAXPROCS=1`) it was refused `multiple_threads_detected` on the first explore, in main's build
  and in this change's (`transcripts/steps/etcdutl-supervised-gomaxprocs1.txt`, which also holds the two
  next steps: main's asks for `GOMAXPROCS=1`, this change's says it is already set).

## What this does not show, and what a rule has to answer first

1. **strace lines threads up.** Without strace the race control's last writer was A in 17 runs of 20 and
   B in 3 when it was chosen, and 18 and 2 when re-run for the record (`transcripts/steps/ctl-race.txt`); under strace, in the first measurement, its two threads alternated the same way in ten runs of
   ten (Q2 *same*), and only overlaps failed it; in the second, Q2 caught it too (*order*). Q2's *same* under strace is weak evidence of the same
   order without it. The supervising engine also stops each call it is notified of; whether it lines the
   threads up as strace does was not measured. A rule's first measurement is under the engine itself.
2. **The engine cannot see what Q1 saw.** Q1 reads each write's return from strace. The engine answers a
   call and is not told when it returns. Q3: in 1,072 of 1,189 arm-1 hand-overs the earlier thread had
   entered another call — mostly `futex` and `fcntl` — before the later write started; neither is a call
   the supervising filter notifies. How the engine would know the earlier write was done is open.
3. **The turn-taking control passes too.** Q1 and Q2 do not tell one goroutine moving between threads from
   two threads a condition variable hands writes between — the shape ADR 0138 decision 1 keeps outside the
   order when the hand-over's record is the evidence. A rule built from this evidence would judge both, by
   showing every world the same as the recording rather than by a recorded hand-over; whether that is a
   change to decision 1 is the rule's plan's to settle.

Changed after the first predictions were written: the race control writes fifty times a thread with a
yield between (with three writes a thread, A was last in twenty plain runs of twenty), which `PREDICTIONS.md` provided
for, and arm 1 prints strings to 64 bytes instead of `-e raw=` on the writes, which dropped `-y`'s path
from a write's descriptor and read no hand-over at all.

## The step this change prints

The refusal's next step, main's build beside this change's, on the same runs
(`transcripts/steps/`):

- `toys-main-and-change.txt`: the acceptance toys — two unordered writer threads under the shim, with no
  switch, `UV_THREADPOOL_SIZE=1` and `RAYON_NUM_THREADS=1`, and the static two-thread toy under
  `--observe supervised`, with no switch and `GOMAXPROCS=1`. Main asks for a switch in all five; this
  change asks in the two with none set.
- `bitwarden-uv-threadpool1.txt`: the Bitwarden CLI, 2026-10-09 follow-ups 3's define with
  `UV_THREADPOOL_SIZE=1` (#980): main asks for `UV_THREADPOOL_SIZE=1`; this change says it is set.
- `etcdutl-supervised-gomaxprocs1.txt`: etcd under `--observe supervised` with `GOMAXPROCS=1` (#987):
  main asks for `GOMAXPROCS=1`; this change says it is set.
