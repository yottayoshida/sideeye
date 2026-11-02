# #1000, second measurement: the rules, fixed again before its runs

The first measurement (`PREDICTIONS.md`) fixed two things that disagreed. Its text said what is
measured is ten recording runs per target; its reader (`apparatus/classify.py`) counted every line
the probe wrote, and the probe writes for the recording and for every world an exploration goes on to
run. Read the first way, Grafana is not measured and the conclusion is *revisit (could not measure)*;
read the second, it is *build*. A conclusion chosen between two readings after the data was read is
not one to record (the owner's ruling on 2026-10-29's measurement, applied again), so the rules are
fixed again here and the targets run again. The first measurement stays in RESULTS.md as it was.

## What changes

1. **What is counted: every supervised run the exploration made.** The recording and each explored
   world. A rule built from this measurement would judge hand-overs in every world, not only in the
   recording.
2. **Which hand-overs: every one the reader does not order.** A hand-over counts where the engine's
   thread-order reader gave the later write, at the same seq and pid, a verdict other than `turned`
   or `first`. The first reader counted `unordered` only; a hand-over back to the process's first
   writer reads `same`, because the reader does not move its writer on an unordered write, and was not
   counted. The join is on seq and pid, since seq restarts in every world.
3. **The probe.** It kept one last writer for the whole run and so missed a hand-over when another
   process wrote between; it keeps one per process now. It closes its file with the session.

The reader is `apparatus/classify_v2.py`. Everything else stands as `PREDICTIONS.md` fixed it: the
box, the ten targets and two controls, ten runs each under the probe engine and under the shipped one,
the classes A–D, and the three criteria with their numbers (p ≥ 0.2; a target measured when
(1 − p)ⁿ ≤ 0.05, five or more measured and five or more of them clean; the condition-variable control
clean in nine runs of ten or more).

## Fixed

This file's sha256 and `apparatus/classify_v2.py`'s are printed before the first run and copied into
RESULTS.md.
