# #987: rules v2, written before the second measurement

`PREDICTIONS.md` registered the first measurement, and is kept unchanged. Read with its reader
(`apparatus/handoff_v1.py`), the first measurement gave four of seven measured targets passing, below
two-thirds: *do not build*. Reading why three failed found a defect in that reader: its Q2 compared each
call's return, and for an open the return is a descriptor number, which JuiceFS's runs drew differently
(8 or 9) while writing the same files in the same order. Corrected for that alone, the same captures
give five of seven, above two-thirds. A conclusion that turns on a reader fixed after its data was read
is not one to record, so the owner chose (2026-10-29) to fix the reader, register the rules again, and
measure again, the first measurement's captures left as they were (`transcripts/v1/`).

This file was written before any capture of the second measurement was taken; its sha256 was printed in
the working session before `run.sh` was started, and it is committed unchanged. These predictions are
**not blind**: they were written after the first measurement was read.

## What changes from v1

Only Q2's comparison, so that it compares what the engine's own world check compares
(`src/prefix.zig`) and not more:

- A write's shape keeps whether it failed, not what it returned: an open's descriptor number is out,
  and the count a write wrote goes with its bytes (*content*), not its shape.
- Two paths that differ count as the same where `sameWhereRecorded` would let them: the later run's
  path is not in the state before the run and not written by the first run, and the first run's is not
  in the state before the run (a name made new each run, such as Dolt's archive names, which a hash
  of the archive picks). `measure.sh` lists the state before every run for this.

Unchanged: the two arms, ten runs each, `GOMAXPROCS=1`, Q1, Q3, what *pass*, *fail* and *unmeasured* are,
the criteria (five or more measured; two-thirds passing, with the race control failing and the
turn-taking control passing, means *build*; otherwise *do not build*; four or fewer measured, or a
control not as stated, goes to the owner), and the controls themselves (`controls/race.c` as the first
measurement used it: fifty writes each with a yield, since three each left one thread last in 20 runs of
20).

## What the first measurement already showed

- Under strace the race control's two threads alternated the same way in all ten runs: strace's stops
  line them up, so Q2 sees little of a race; Q1 is what failed it (412 overlaps in 1,000 hand-overs).
- etcd's `etcdutl defrag` wrote from one thread in all twenty runs under strace.
- vmrestore's runs removed files in a different order from each other (the third write was
  `cache/metric_usage_tracker` in one run and `data/small/2026_10/parts.json` in another).

## Predictions, per target

| target | prediction |
|---|---|
| etcd | unmeasured (no hand-over under strace) |
| Dolt | pass (the archive names are new names; `journal.idx`'s count is content) |
| Grafana | pass |
| vmrestore | fail (its removals' order) |
| Gogs | pass |
| gqlgen | pass |
| JuiceFS | pass |
| Navidrome `backup restore` | pass |

Six of seven measured predicted to pass: the prediction is **build**.
