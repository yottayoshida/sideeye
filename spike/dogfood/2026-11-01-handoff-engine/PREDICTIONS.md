# #1000: where the earlier writer is at a hand-over, under the engine itself — the rules, fixed before the runs

ADR 0138 decision 2 decides to build a rule that judges two thread ids of one process writing in turn
under `--observe supervised`, and leaves three questions for its first step. This measurement answers
the first two under the engine itself, without strace (which lines threads up), and decides by the
rules below whether the rule's plan is written or decision 2 is revisited with these numbers. The
engine's verdicts do not change: the probe is `-Dtest-handoff-probe` (`sideeye-testhandoffprobe`),
which only writes lines.

## What runs

Box `sideeye-gh1029` (`../2026-10-29-go-handoff/apparatus/Dockerfile`, rebuilt), as root,
`--privileged --cgroupns=private --network none`. Each target with 2026-10-25's own `seed.sh`,
`env.sh` and `sideeye.toml`, plus `--observe supervised --no-oracle --allow-unverified` and
`GOMAXPROCS=1`, ten times (`apparatus/measure.sh`). Targets: Dolt `gc`, Grafana
`cli admin reset-admin-password`, Gogs `restore`, gqlgen `generate`, JuiceFS `config`, Navidrome
`backup restore` — the six that passed under strace on 2026-10-29. etcd and vmrestore are run and
tabled, not counted. Controls: `ctl-race` (two threads writing one file with nothing ordering them)
and `ctl-condvar` (two threads handing writes over through a condition variable), as built in the box.
Today's engine refuses `multiple_threads_detected` after the recording run, so what is measured is
ten recording runs per target. The same ten run again under the shipped engine (`plain`); the
recordings' hand-over counts (thread id changes between successive crash points of one process,
read from `trace-ops --records`) are compared, for the observer effect.

## What a hand-over is, and its classes

The probe writes a `handover` line when a state-changing call inside the judged state arrives from a
thread T whose process last wrote from a different thread W, before the engine answers: W's
`/proc/<pid>/task/<W>/syscall` first word and `stat` state, W's last call number and T's. The engine's
own thread-order reader writes a `verdict` line per crash point. A hand-over is **counted** only where
the verdict at its seq is `unordered` — the hand-overs the engine refuses on; ones a creation or a join
orders, and writes the define declares scratch, are not counted. Classes (`apparatus/classify.py`):

- **A**: W is in a call the supervising filter does not watch — its earlier call returned
- **B**: W is stopped in a different watched call — returned
- **C**: W is in the same call number, `running`, or anything else — cannot tell
- **D**: W's entries could not be read

## The criteria

"Build" — write the rule's plan — only when all three hold; otherwise "revisit": rewrite decision 2
with these numbers, conditional or withdrawn.

1. **The probe can see an overlap.** `ctl-race`'s counted hand-overs are C in a fraction p ≥ 0.2.
2. **Enough targets measured, and clean.** A target is *measured* when its counted hand-overs over
   its ten runs, n, reach (1 − p)ⁿ ≤ 0.05 — a racing target would then have shown a C with 95%
   probability. Five or more targets measured, and in five or more of them every counted hand-over A
   or B (no C, no D). Fewer than five measured is "revisit (could not measure)".
3. **The turn-taking control is clean.** `ctl-condvar` has every counted hand-over A or B in nine
   runs of ten or more.

Known misreadings, not counted: W inside a signal handler sitting in `futex` while its write is not
yet resumed reads as A; a reused thread id reads as A or B.

## Fixed

This file's sha256 and `apparatus/classify.py`'s are printed before the first run and copied into
RESULTS.md.
