# #1000: where the earlier writer is at a hand-over, under the engine itself

**Two measurements. The second, under rules fixed again before its runs (`PREDICTIONS-v2.md`), reads
*revisit*: in Dolt one hand-over of 21 found the earlier writer running, which one read cannot tell
from still writing, so four of the five targets measured are clean and criterion 2 needs five. The
owner ruled on 2026-11-02 to make ADR 0138 decision 2 conditional rather than withdraw it: a rule is
built only in a form that reads again until the earlier writer is out of its call, and that form is
measured before it ships.** The first measurement read *build* by its reader and *revisit* by its own
text; why, and why it was run again, is in `PREDICTIONS-v2.md`. Both are below, the second first.

## The second measurement (2026-11-01, 12:59:39–13:10:32Z)

`PREDICTIONS-v2.md` (sha256 `7c8f3d9b…76b83dbd0`) and `apparatus/classify_v2.py` (`56c0c60d…f60d736c`)
were printed at 12:59:39Z, before any run; `apparatus/measure.sh` unchanged (`d83ae8b8…48105794`).
What changed from the first is in that file: every supervised run an exploration made is counted (the
recording and its explored worlds), every hand-over the reader does not order (`unordered` or `same`),
joined on seq and pid, and the probe keeps one last writer per process and closes its file. The probe
engine was rebuilt with those two fixes; nothing else ran on the machine. Kept lines and output as
for the first (`transcripts-v2/`).

| target | runs | counted hand-overs (all) | A | B | C | D | verdicts |
|---|---|---|---|---|---|---|---|
| `ctl-race` | 10 | 1,000 (1,000) | 10 | 0 | **990** | 0 | 10 refused, threads |
| `ctl-condvar` | 10 | 20 (20) | 20 | 0 | 0 | 0 | 10 refused, threads |
| Dolt `gc` | 10 | 21 (21) | 20 | 0 | **1** | 0 | 10 refused, threads |
| Grafana `reset-admin-password` | 10 | 8 (11) | 8 | 0 | 0 | 0 | 3 PASS, 7 refused, threads |
| Gogs `restore` | 10 | 307 (307) | 307 | 0 | 0 | 0 | 10 refused, threads |
| gqlgen `generate` | 10 | 9 (9) | 9 | 0 | 0 | 0 | 9 refused, threads; 1 `boundary_without_oracle` |
| JuiceFS `config` | 10 | 0 (0) | — | — | — | — | refused `baseline_violates_invariant` |
| Navidrome `backup restore` | 10 | 10 (10) | 10 | 0 | 0 | 0 | 10 refused, threads |
| etcd `defrag` (tabled) | 10 | 13 (13) | 13 | 0 | 0 | 0 | — |
| vmrestore (tabled) | 10 | — | | | | | SETUP ERROR, as in the first |

p = 0.99 again; five targets measured (all but JuiceFS); four clean (Grafana, Gogs, gqlgen, Navidrome).
Criterion 1 holds, criterion 3 holds (ten of ten), **criterion 2 does not**: Dolt's hand-over at seq
19 of its first run found the earlier writer, whose last call was `unlinkat` (35), `running`
(state R) as the later `unlinkat` arrived. Every other counted hand-over in the targets found it out of its call: in `futex`, and once (gqlgen) in
`epoll_pwait` (22). The counted number is below all hand-overs in Grafana (8 of 11): two read `first`
and one has no verdict line of its pid. Recording thread-id changes (`transcripts-v2/observer.jsonl`): Dolt 1 in eight runs and 6 or
7 in two under the probe, 1 in each under the shipped engine; Gogs 11–79 and 14–25; the controls the
same under both. Verdicts that differed with the arm: Grafana 3 PASS and 7 refused under the probe,
6 PASS and 4 refused under the shipped engine; gqlgen one `boundary_without_oracle` under the probe;
JuiceFS `baseline_violates_invariant` in all ten under both, so the first measurement's JuiceFS
difference did not recur. The probe keeps the last writer of at most 16 processes; a seventeenth's
hand-overs would go unwritten, and no run here reached that.

## The first measurement (2026-11-01, 12:11:26–12:19:16Z)

### How

`PREDICTIONS.md` (sha256 `573b017f…5a9009e8`), `apparatus/classify.py` (`89288ebf…ac6cde16`) and
`apparatus/measure.sh` (`d83ae8b8…48105794`) were printed at 2026-11-01T12:10:56Z, before any run.
One run of `ctl-race` followed, to see the probe write at all (`transcripts/smoke-ctl-race-run01.probe`:
100 hand-overs, counted in nothing below). The measurement ran 12:11:26–12:19:16Z, nothing else on the
machine: `apparatus/run.sh`, box `sideeye-gh1029` rebuilt from 2026-10-29's Dockerfile, engine built
from this change with `-Dtest-handoff-probe -Dtrace-ops` (aarch64-linux, Debug).

Each target's probe file holds the supervising engine's `handover` lines and the trace reader's
`verdict` lines for the recording and every world the run explored. The committed files keep the
`handover` lines and the `verdict` lines of the same seq and pid, which are all `classify.py` reads;
its output on the kept lines was compared with its output on the full captures before they were cut,
and matched (`transcripts/judge.jsonl`); the full captures are not committed.
Joining on seq alone, as `classify.py` does, and on seq, pid and thread id gave the same counts for
every target.

### Results

| target | runs | counted hand-overs (all) | A | B | C | D | verdicts |
|---|---|---|---|---|---|---|---|
| `ctl-race` | 10 | 1,000 (1,000) | 10 | 0 | **990** | 0 | 10 refused, threads |
| `ctl-condvar` | 10 | 10 (20) | 10 | 0 | 0 | 0 | 10 refused, threads |
| Dolt `gc` | 10 | 10 (10) | 10 | 0 | 0 | 0 | 10 refused, threads |
| Grafana `reset-admin-password` | 10 | 2 (2) | 2 | 0 | 0 | 0 | 8 PASS, 2 refused in an explored world |
| Gogs `restore` | 10 | 149 (212) | 149 | 0 | 0 | 0 | 10 refused, threads |
| gqlgen `generate` | 10 | 14 (16) | 14 | 0 | 0 | 0 | 10 refused, threads |
| JuiceFS `config` | 10 | 0 (0) | — | — | — | — | refused `baseline_violates_invariant` |
| Navidrome `backup restore` | 10 | 10 (10) | 10 | 0 | 0 | 0 | 10 refused, threads: 9 in an explored world, 1 in the recording |
| etcd `defrag` (tabled) | 10 | 12 (17) | 12 | 0 | 0 | 0 | — |
| vmrestore (tabled) | 10 | — | | | | | SETUP ERROR: its define's checker is not installed by its seed |

The counted number is smaller than all hand-overs where the reader's verdict at the later write was
`same`, not `unordered`: the reader does not move its writer on an unordered write, so a hand-over back
to the first writer reads `same` and this reader did not count it (Gogs 63, gqlgen 2, etcd 4,
`ctl-condvar` 10; all of them A); one more of etcd's has no verdict line of its pid, a hand-over across
processes that this probe, keeping one last writer for the whole run, wrote by mistake. p = 990 / 1,000 = 0.99, so (1 − p)ⁿ ≤ 0.05 needs n ≥ 1: five targets measured (all but JuiceFS), and
all five clean. `ctl-condvar` clean in ten runs of ten.

- **Criterion 1** holds: p = 0.99 ≥ 0.2.
- **Criterion 2** holds as its reader counted: five measured, five clean. Read as its text fixed it — ten recording runs — Grafana has no hand-over in a recording (its two are in explored worlds), four targets are measured, and criterion 2 does not hold: *revisit (could not measure)*.
- **Criterion 3** holds: ten of ten.

Every A was the earlier writer in call 98 (`futex`, aarch64), in the targets and in both controls; there was no B and no D. The race control's C split 584 `running` and 406 in the same call (68, `pwrite64`).

### The observer effect

Thread id changes between successive crash points of one process, per recording, from
`trace-ops --records` (`apparatus/observer.py`, `transcripts/observer.jsonl`), under the probe engine
and under the shipped one:

| target | probe | shipped |
|---|---|---|
| `ctl-race` | 100 in each run | 98, then 100 in nine |
| `ctl-condvar` | 2 in each run | 2 in each run |
| Dolt | 1 in each run | 1 in nine, 5 in one |
| Gogs | 16–25 | 22–36 |
| gqlgen | 1–3 | 1–4 |
| etcd | 0–3 | 0–8 |
| Navidrome | 1 in one recording, 0 in nine | 0 in each recording |
| Grafana, JuiceFS, vmrestore | 0 in each recording | 0 in each recording |

Gogs handed over less under the probe engine here (16–25 against 22–36) and more in the second measurement (11–79 against 14–25); like etcd's, its runs vary too much in ten for a difference to be the probe's, and the two arms ran one after the other, not paired. One verdict changed with the arm: JuiceFS was refused `multiple_threads_detected` in four of ten runs under the shipped engine and in none under the probe engine, where all ten reached `baseline_violates_invariant` (`transcripts/plain/juicefs/exits.txt`). The controls were the same under both.

## What this does not show

1. **One read cannot tell running from still writing.** Dolt's C in the second measurement is an
   earlier writer `running` as the later call arrived; returned to user code, or still in its call, a
   single read does not say. The race control is also an easy one: its two threads write the same file
   back to back, so p comes out 0.99 and one hand-over is enough to call a target measured (criterion
   2's n ≥ 1). A race whose writes overlap rarely would be caught less often. Both say the rule cannot
   rest on reading `/proc` once.
2. **Under the engine, the targets hand over less than under strace.** Grafana handed over in five of
   ten strace runs on 2026-10-29, in no recording of the first measurement here and in three of the
   second; Navidrome in three of ten there, and here mostly in explored worlds. The engine stops every
   watched call, which may keep Go's runtime on one thread longer. The rule's measurement has to count
   its hand-overs under the engine, not assume strace's.
3. **A at a hand-over is not order on the next run.** It says the earlier write had returned when the
   later one arrived, on this run. ADR 0138 decision 1 keeps a recorded hand-over out of the order for
   that reason; question 3 is the rule's plan's.
4. **Known misreadings, not counted** (as `PREDICTIONS.md` fixed): an earlier writer inside a signal
   handler waiting in `futex` reads as A; a reused thread id reads as A or B.
