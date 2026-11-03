# #1000: the hand-over rule, measured before it ships — it does not ship

**The rule failed the criteria `PREDICTIONS.md` fixed before the runs, in both modes, so it does not ship
and ADR 0138 decision 2 is revisited with these numbers (owner, 2026-11-03).** Without an oracle the
turn-taking control changed thread in four runs of ten, short of criterion 2's ten, and read as fixed —
nine or more runs with hand-overs succeeding — criterion 3 held for gqlgen alone. Under `--oracle`,
`race-once` — two goroutines released together, writing once each — had hand-overs in eight runs of
ten, and in all eight the recording took every one as ordered and the run was not refused for its
threads: criterion 1 failed. None of those eight reached a PASS, which says little: the control writes
files the state did not hold and cannot reach one by construction (five ended `nothing_could_fail`).
The rule's code is not in the tree; `apparatus/rule.diff` is the change the measured engine was built from.

## How

`PREDICTIONS.md` (sha256 `2deb7fb7…5b4d509fd0`) and the apparatus's sha256 were printed at
2026-11-03T11:24:14Z, before any run (`transcripts/sha256-before-runs.txt`; the time is the shell's
`date -u` printed beside it, `transcripts/box.txt`). The runs started at 11:24:23Z
(`transcripts/started.txt`). Box: `sideeye-gh1029`, built on 2026-11-03 from
`spike/dogfood/2026-10-29-go-handoff/apparatus/`; Docker's layer cache gave it the 2026-11-01 image
(`transcripts/box.txt`: image id, 10 CPUs, Go 1.27.3, aarch64). Engine: main `0fff6366` with the rule,
built for aarch64-linux in Debug; its sha256 is in `transcripts/box.txt`. `apparatus/rule.diff` was
written after the runs from the tree that engine was built from, and a build of `0fff6366` with it
applied compiles, but not to the same bytes (the build path differs), so the diff is the change, not a
proof of the binary. Its comments name an ADR 0152 that was never written: the rule did not ship.

Before `PREDICTIONS.md` was fixed, each target's `.go.buildinfo` was read in the box: etcd's `etcdutl`
(go1.26.10), Grafana (go1.26.9), Gogs (go1.25.10) and gqlgen (go1.26.0) are `CGO_ENABLED=0`; Dolt,
vmrestore, JuiceFS and Navidrome are `CGO_ENABLED=1` and out of the rule's scope. The three controls
were built in the box with `CGO_ENABLED=0`.

Kept: `transcripts/runs.tsv` (each run's verdict line and its recording's hand-over counts) and
`transcripts/classify.jsonl` (`apparatus/classify.py` over every run). The full captures are not
committed. A run refused in an explored world prints that world's refusal, not why the rule did not take
that world's hand-over, so for those runs the reason is not in the record.

**Stopped early.** Under `--oracle`, one Gogs exploration took more than twenty minutes, and the
remaining nine Gogs runs and ten gqlgen runs would have taken some four hours. They count only towards
criterion 3, and `--oracle` had already failed criterion 1, so the measurement was stopped at
2026-11-03T12:25Z (`transcripts/stopped.txt`) with one Gogs run and no gqlgen run in that mode.

## Results

A run *has hand-overs* when its recording's line counts any or it was refused
`multiple_threads_detected`; it *succeeds* when it was not refused `multiple_threads_detected`. The
hand-over counts are the recordings' only.

| mode | subject | runs | with hand-overs | succeeded | taken / all (recordings) | not taken: queued, busy, running, unreadable (recordings) | verdicts |
|---|---|---|---|---|---|---|---|
| no oracle | race-loop | 10 | 10 | 0 | 3 / 203 | 198, 2, 0, 0 | 10 `multiple_threads_detected` |
| no oracle | race-once | 10 | 10 | 0 | 10 / 26 | 12, 4, 0, 0 | 10 `multiple_threads_detected` |
| no oracle | turns | 10 | **4** | 4 | 5 / 5 | 0, 0, 0, 0 | 10 `nothing_could_fail` |
| no oracle | etcdutl | 10 | 6 | 6 | 9 / 9 | 0 | 10 FAIL |
| no oracle | Gogs | 10 | 10 | 1 | 244 / 244 | 0 | 9 `multiple_threads_detected`, 1 `state_changed_unaccounted` |
| no oracle | gqlgen | 10 | 10 | 10 | 10 / 10 | 0 | 10 `boundary_without_oracle` |
| no oracle | Grafana | 10 | 0 | 0 | 0 / 0 | 0 | 10 PASS |
| oracle | race-loop | 10 | **9** | 1 | 18 / 130 | 5, 107, 0, 0 | 8 `multiple_threads_detected`, 2 `oracle_missed_operation` |
| oracle | race-once | 10 | **8** | **8** | 17 / 17 | 0 | 5 `nothing_could_fail`, 4 `oracle_missed_operation`, 1 `kill_did_not_land` |
| oracle | turns | 10 | 10 | 10 | 29 / 29 | 0 | 10 `nothing_could_fail` |
| oracle | etcdutl | 10 | 7 | 7 | 9 / 9 | 0 | 10 FAIL |
| oracle | Grafana | 10 | 6 | 6 | 8 / 8 | 0 | 10 PASS |
| oracle | Gogs | 1 (run02 stopped) | 1 | 1 | 74 / 74 | 0 | 1 `baseline_violates_invariant` |

Where the races were refused, the rule's own reason is not always the recording's. Without an oracle,
the "not taken" counts come from eleven recordings, 198 of the 216 from two `race-loop` runs (run06, run08);
in nine of the twenty race runs (`race-loop` run01–03, 05, 07, 09, 10; `race-once` run04, run10) the
recording carried no hand-over line or took every hand-over, and the refusal came from an explored world.
`race-once`'s recordings took one or more hand-overs in each of the nine runs that carried a line. Under
`--oracle`, `race-loop`'s recordings took every hand-over in five of its nine runs with hand-overs
(run01, 03, 04, 06, 07). The two modes' "succeeded" are not like for like: the oracle-mode controls ended
`nothing_could_fail` or were refused early, and may have met fewer explored worlds than the same controls
without it, which were refused in a world (a reading of the verdicts, not measured).

`turns` and `race-once` write files the state did not hold, so no world could fail them
(`nothing_could_fail`); they are controls of the hand-over, not of a verdict. Gogs's recordings took every
hand-over without an oracle, and nine runs were refused in an explored world. etcd's FAIL is a verdict
the threads wall had kept from it; it was not looked into here.

## Against the criteria, as fixed

- **No oracle.** 1 holds: both races have hand-overs in 10 of 10 and none succeeds. 2 fails: `turns`
  has hand-overs in 4 runs of 10, not 10 (the four all succeed). 3 fails as written — "nine or more of
  the runs with hand-overs succeed" counts runs: etcdutl, Gogs and gqlgen are measured, and only gqlgen
  has nine or more succeeding (10); etcdutl's six of six are fewer than nine, Gogs has one. Read as a
  share it would hold for two of three; it was not written as one.
- **Oracle.** 1 fails twice over: `race-once` has hand-overs in 8 runs of 10 and `race-loop` in 9, not
  10 of 10, and `race-once` succeeds in all 8, `race-loop` in 1. 2 holds: 10 of 10. 3 fails whatever
  the stopped runs would have shown: etcdutl (7 of 7) and Grafana (6 of 6) ran all ten and neither reaches
  nine, so at most Gogs and gqlgen could pass, two of four where three are needed.

1 or 2 fails in each mode, so, as fixed: nothing ships, and ADR 0138 decision 2 is revisited.

## What this does and does not show

1. **Under `--oracle` the evidence did not hold for `race-once`.** In the eight runs with hand-overs the
   recording took every one, where the same control without an oracle had 12 of its 26 recorded
   hand-overs refused for a call waiting in the queue. That is consistent with strace's stops keeping the
   second write out of the engine's queue when the first was answered, with the earlier writer asleep in
   the runtime by the time it was read; the mechanism was not observed, and nothing measured whether the
   later write was issued after the earlier one returned.
2. **Without an oracle the races were refused in every run, the rule's reasons on record for eleven of
   twenty.** The other nine were refused in an explored world, for a reason the record does not keep.
   `race-once`'s recordings took some hand-overs as ordered in every run that carried a line. etcd's and
   gqlgen's recorded hand-overs were all taken. That mode is `--allow-unverified`'s weaker claim.
3. **The turn-taking control changed thread in four runs of ten** without an oracle, and in ten of ten
   with one. Why the runtime kept both goroutines on one thread more often without strace was not
   measured. The owner chose not to rebuild the control and measure again (2026-11-03).
