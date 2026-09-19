# Written before the results were read (2026-09-18)

The table below is the prediction, recorded before the first run finished and committed
unedited — errors included, because editing it afterwards would defeat the point of having
it. The section after it was written once the results were in.

| target | default mode | `--observe syscalls` |
|---|---|---|
| pacpl | UNKNOWN `child_touched_state_dir` (flac writes the state as a child) | **unknown** — ADR 0054 made both witnesses witnesses of the same run, so the child's writes might now carry numbers and reach a verdict |
| mail-expire | same (gzip is the child) | same as above |
| lbdb | UNKNOWN `child_touched_state_dir` (`fetchaddr` writes through the parent shell's redirect and records nothing) | **PASS, 8 crash points** — `docs/target-classes.md` already records it; this run is a reproduction on another machine |

Falsifier stated at the same time: if lbdb does **not** reach PASS, the page's record is
what to doubt, not the run.

## How it came out

lbdb held. The pacpl / mail-expire guess was **wrong**, and wrong in the way worth keeping:
it treated the class as one thing because the refusal has one name. Both refuse in both
modes, and their message names a condition the mode cannot touch — a child writing while
the subject is still running. The guess asked "can the second observation path see it?"
when the question was "did the two writers take turns?".
