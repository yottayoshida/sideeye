# #1000: the hand-over rule, measured before it ships — the rules, fixed before the runs

ADR 0138 decision 2, as amended on 2026-11-02, builds the rule only in a form that reads where the
earlier writer is again, within a bound, and has it measured under rules fixed before its runs, on
the targets and controls, before it ships. This file is those rules. Its sha256 and the apparatus's
are printed before the first run and copied into RESULTS.md.

## The rule measured

Under `--observe supervised`, in a process whose image carries a Go build-info section saying
`CGO_ENABLED=0` and whose own environment sets `GOMAXPROCS=1` (the owner's ruling of 2026-11-03),
a state-changing call from one thread id after another thread id of the process wrote the judged
state is taken as ordered when (1) no other notification was waiting when the earlier writer's
last crash-point call was answered, and (2) the earlier writer's `/proc/<pid>/task/<tid>/syscall`
names a call the engine is not notified of, or the task is gone — read again while it reads
`running` or `-1`, up to 1,000 reads or 20 ms. Any other hand-over in scope is recorded as not
taken, with its reason, and refuses `multiple_threads_detected` as before.

## The box and the runs

`sideeye-gh1029`, rebuilt on 2026-11-03 from `spike/dogfood/2026-10-29-go-handoff/apparatus/`
(aarch64, Docker Desktop; its CPU count is recorded with the runs). The engine is this change's,
built with `zig build -Dtarget=aarch64-linux-gnu`. Each subject is explored ten times with
`explore --observe supervised`, `GOMAXPROCS=1` exported, in two modes: `--no-oracle
--allow-unverified`, and `--oracle /usr/bin/strace`. `apparatus/run.sh` runs them, `apparatus/measure.sh`
runs one subject, `apparatus/classify.py` reads them.

Subjects. Read from each target's `.go.buildinfo` in the rebuilt box before this file was fixed:
etcd's `etcdutl`, Grafana, Gogs and gqlgen are `CGO_ENABLED=0` and in scope; Dolt, vmrestore,
JuiceFS and Navidrome are `CGO_ENABLED=1` and out of scope, so not measured. Their defines are
2026-10-25's (`spike/dogfood/2026-10-25-shipped-v1160/apparatus/defines/`). Three controls, Go,
`CGO_ENABLED=0`, in `apparatus/controls/`: `race-loop` (two goroutines write the same eight bytes'
place fifty times each), `race-once` (two goroutines released together write one file each, once),
`turns` (two goroutines take turns through channels, ten writes each).

## What is counted

A run **has hand-overs** when its report's processes line counts one or more, or when it was refused
`multiple_threads_detected`. A run with hand-overs **succeeds** when it was not refused
`multiple_threads_detected`. Every other verdict is counted and reported, and decides nothing here.

## Criteria, per mode

1. **Races refused**: `race-loop` and `race-once` each have hand-overs in ten runs of ten, and none
   succeeds.
2. **Turns taken**: `turns` has hand-overs in ten runs of ten, and nine or more succeed.
3. **Targets**: of the four targets, those with hand-overs in at least one run are *measured*; three or
   more are measured, and in two thirds or more of the measured ones (rounded up), nine or more of the
   runs with hand-overs succeed.

Reported and deciding nothing: hand-overs taken and not taken, by reason; how often the bound ran out
(`running`); verdicts.

## Conclusion, per mode

- 1, 2 and 3 hold: the rule ships for that mode, and the property names it.
- 1 or 2 fails: the rule does not ship for that mode. If it fails in both, nothing ships and ADR 0138
  decision 2 is revisited with these numbers.
- Only 3 fails: the numbers go to the owner before anything ships for that mode.

A run that fails for the box (a seed that does not complete, a crash of the engine) is reported and
run again once; the replacement is said.
